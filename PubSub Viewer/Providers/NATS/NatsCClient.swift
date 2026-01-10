//
//  NatsCClient.swift
//  PubSub Viewer
//
//  Swift wrapper around the NATS C client library (nats.c)
//  Implements MessageQueueClient and StreamingClient protocols
//

import Foundation
import Combine

// MARK: - NATS C Client

/// Swift wrapper around the NATS C client library
/// Uses C FFI to interface with nats.c for maximum performance and feature parity
public final class NatsCClient: @unchecked Sendable {
    
    // MARK: - Properties
    
    public let config: MQConnectionConfig
    
    private var _state: MQConnectionState = .disconnected
    public var state: MQConnectionState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }
    
    // Thread safety
    private let lock = NSLock()
    
    // Subject for state changes
    private let stateSubject = PassthroughSubject<MQConnectionState, Never>()
    
    public var statePublisher: AnyPublisher<MQConnectionState, Never> {
        stateSubject.eraseToAnyPublisher()
    }
    
    // C FFI pointers
    private var connection: OpaquePointer?      // natsConnection*
    private var options: OpaquePointer?         // natsOptions*
    private var jsContext: OpaquePointer?       // jsCtx* for JetStream
    
    // Active subscriptions
    private var subscriptions: [String: OpaquePointer] = [:]  // natsSubscription*
    
    // Message continuations for async streams
    private var messageContinuations: [String: AsyncStream<MQMessage>.Continuation] = [:]
    
    // MARK: - Initialization
    
    public init(config: MQConnectionConfig) {
        self.config = config
    }
    
    deinit {
        // Cleanup all C resources synchronously
        cleanupResources()
    }
    
    private func cleanupResources() {
        lock.lock()
        defer { lock.unlock() }
        
        // Close all subscriptions
        for (_, sub) in subscriptions {
            natsSubscription_Unsubscribe(sub)
            natsSubscription_Destroy(sub)
        }
        subscriptions.removeAll()
        
        // Destroy JetStream context
        if let js = jsContext {
            jsCtx_Destroy(js)
            jsContext = nil
        }
        
        // Close and destroy connection
        if let conn = connection {
            natsConnection_Close(conn)
            natsConnection_Destroy(conn)
            connection = nil
        }
        
        // Destroy options
        if let opts = options {
            natsOptions_Destroy(opts)
            options = nil
        }
    }
    
    // MARK: - State Management
    
    private func updateState(_ newState: MQConnectionState) {
        lock.lock()
        _state = newState
        lock.unlock()
        stateSubject.send(newState)
    }
}

// MARK: - MessageQueueClient Protocol

extension NatsCClient: MessageQueueClient {
    
    public func connect() async throws {
        guard state != .connected else { return }
        
        updateState(.connecting)
        
        do {
            // Create options
            var opts: OpaquePointer?
            var status = natsOptions_Create(&opts)
            guard status == NATS_OK else {
                throw MQError.connectionFailed("Failed to create options: \(natsStatusText(status))")
            }
            
            // Set URL
            status = natsOptions_SetURL(opts, config.url)
            guard status == NATS_OK else {
                natsOptions_Destroy(opts)
                throw MQError.connectionFailed("Invalid URL: \(natsStatusText(status))")
            }
            
            // Set credentials if provided
            if let username = config.username, let password = config.password {
                status = natsOptions_SetUserInfo(opts, username, password)
                guard status == NATS_OK else {
                    natsOptions_Destroy(opts)
                    throw MQError.connectionFailed("Failed to set credentials: \(natsStatusText(status))")
                }
            }
            
            // Set token if provided
            if let token = config.token {
                status = natsOptions_SetToken(opts, token)
                guard status == NATS_OK else {
                    natsOptions_Destroy(opts)
                    throw MQError.connectionFailed("Failed to set token: \(natsStatusText(status))")
                }
            }
            
            // Set connection name
            _ = natsOptions_SetName(opts, config.name)
            
            lock.lock()
            self.options = opts
            lock.unlock()
            
            // Connect
            var conn: OpaquePointer?
            status = natsConnection_Connect(&conn, opts)
            guard status == NATS_OK else {
                throw MQError.connectionFailed("Connection failed: \(natsStatusText(status))")
            }
            
            lock.lock()
            self.connection = conn
            lock.unlock()
            
            updateState(.connected)
            
        } catch {
            updateState(.error(error.localizedDescription))
            throw error
        }
    }
    
    public func disconnect() async {
        cleanupResources()
        updateState(.disconnected)
    }
    
    public func publish(_ message: MQMessage, to subject: String) async throws {
        guard state == .connected, let conn = connection else {
            throw MQError.notConnected
        }
        
        // Simple publish without headers
        let status = message.payload.withUnsafeBytes { buffer in
            natsConnection_Publish(conn, subject, buffer.baseAddress?.assumingMemoryBound(to: CChar.self), Int32(message.payload.count))
        }
        
        guard status == NATS_OK else {
            throw MQError.publishFailed("Publish failed: \(natsStatusText(status))")
        }
    }
    
    public func subscribe(to pattern: String) async throws -> AsyncStream<MQMessage> {
        guard state == .connected, let conn = connection else {
            throw MQError.notConnected
        }
        
        return AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }
            
            // Store continuation
            self.lock.lock()
            self.messageContinuations[pattern] = continuation
            self.lock.unlock()
            
            // Create subscription callback context
            let context = SubscriptionContext(pattern: pattern, continuation: continuation, client: self)
            let contextPtr = Unmanaged.passRetained(context).toOpaque()
            
            var sub: OpaquePointer?
            let status = natsConnection_Subscribe(&sub, conn, pattern, { (_, _, msg, closure) in
                guard let closure = closure, let msg = msg else { return }
                
                let ctx = Unmanaged<SubscriptionContext>.fromOpaque(closure).takeUnretainedValue()
                
                // Extract message data
                let subject = String(cString: natsMsg_GetSubject(msg))
                let dataPtr = natsMsg_GetData(msg)
                let dataLen = natsMsg_GetDataLength(msg)
                
                var payload = Data()
                if let ptr = dataPtr, dataLen > 0 {
                    payload = Data(bytes: ptr, count: Int(dataLen))
                }
                
                let replyTo: String? = {
                    if let reply = natsMsg_GetReply(msg) {
                        return String(cString: reply)
                    }
                    return nil
                }()
                
                let mqMessage = MQMessage(
                    subject: subject,
                    payload: payload,
                    headers: nil,
                    replyTo: replyTo,
                    timestamp: Date()
                )
                
                ctx.continuation.yield(mqMessage)
                
            }, contextPtr)
            
            if status == NATS_OK {
                self.lock.lock()
                self.subscriptions[pattern] = sub
                self.lock.unlock()
            } else {
                Unmanaged<SubscriptionContext>.fromOpaque(contextPtr).release()
                continuation.finish()
            }
            
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    try? await self?.unsubscribe(from: pattern)
                }
            }
        }
    }
    
    public func unsubscribe(from pattern: String) async throws {
        lock.lock()
        let sub = subscriptions.removeValue(forKey: pattern)
        let continuation = messageContinuations.removeValue(forKey: pattern)
        lock.unlock()
        
        if let sub = sub {
            natsSubscription_Unsubscribe(sub)
            natsSubscription_Destroy(sub)
        }
        continuation?.finish()
    }
    
    public func request(_ message: MQMessage, to subject: String, timeout: Duration) async throws -> MQMessage? {
        guard state == .connected, let conn = connection else {
            throw MQError.notConnected
        }
        
        let timeoutMs = Int64(timeout.components.seconds * 1000 + timeout.components.attoseconds / 1_000_000_000_000_000)
        
        var reply: OpaquePointer?
        let status = message.payload.withUnsafeBytes { buffer in
            natsConnection_Request(&reply, conn, subject, buffer.baseAddress?.assumingMemoryBound(to: CChar.self), Int32(message.payload.count), timeoutMs)
        }
        
        guard status == NATS_OK, let replyMsg = reply else {
            if status == NATS_TIMEOUT {
                return nil
            }
            throw MQError.providerError("Request failed: \(natsStatusText(status))")
        }
        
        defer { natsMsg_Destroy(replyMsg) }
        
        let replySubject = String(cString: natsMsg_GetSubject(replyMsg))
        let dataPtr = natsMsg_GetData(replyMsg)
        let dataLen = natsMsg_GetDataLength(replyMsg)
        
        var payload = Data()
        if let ptr = dataPtr, dataLen > 0 {
            payload = Data(bytes: ptr, count: Int(dataLen))
        }
        
        return MQMessage(subject: replySubject, payload: payload, timestamp: Date())
    }
}

// MARK: - StreamingClient Protocol (JetStream) - Placeholder

extension NatsCClient: StreamingClient {
    
    public func listStreams() async throws -> [MQStreamInfo] {
        // JetStream operations require more complex API - placeholder for now
        guard state == .connected else { throw MQError.notConnected }
        return []
    }
    
    public func createStream(_ config: MQStreamConfig) async throws -> MQStreamInfo {
        guard state == .connected else { throw MQError.notConnected }
        // Placeholder - JetStream API will be implemented
        return MQStreamInfo(name: config.name, subjects: config.subjects)
    }
    
    public func deleteStream(_ name: String) async throws {
        guard state == .connected else { throw MQError.notConnected }
        // Placeholder
    }
    
    public func getStreamInfo(_ name: String) async throws -> MQStreamInfo? {
        guard state == .connected else { throw MQError.notConnected }
        return nil
    }
    
    public func listConsumers(stream: String) async throws -> [MQConsumerInfo] {
        guard state == .connected else { throw MQError.notConnected }
        return []
    }
    
    public func createConsumer(stream: String, config: MQConsumerConfig) async throws -> MQConsumerInfo {
        guard state == .connected else { throw MQError.notConnected }
        return MQConsumerInfo(streamName: stream, name: config.name)
    }
    
    public func deleteConsumer(stream: String, name: String) async throws {
        guard state == .connected else { throw MQError.notConnected }
    }
    
    public func publishPersistent(_ message: MQMessage, to subject: String) async throws -> MQPublishAck {
        guard state == .connected else { throw MQError.notConnected }
        // Fallback to regular publish for now
        try await publish(message, to: subject)
        return MQPublishAck(stream: "unknown", sequence: 0)
    }
    
    public func consume(stream: String, consumer: String) async throws -> AsyncStream<MQAcknowledgeableMessage> {
        guard state == .connected else { throw MQError.notConnected }
        return AsyncStream { $0.finish() }
    }
    
    public func fetch(stream: String, consumer: String, batch: Int, expires: Duration) async throws -> [MQAcknowledgeableMessage] {
        guard state == .connected else { throw MQError.notConnected }
        return []
    }
}

// MARK: - Subscription Context

private class SubscriptionContext {
    let pattern: String
    let continuation: AsyncStream<MQMessage>.Continuation
    weak var client: NatsCClient?
    
    init(pattern: String, continuation: AsyncStream<MQMessage>.Continuation, client: NatsCClient) {
        self.pattern = pattern
        self.continuation = continuation
        self.client = client
    }
}

// MARK: - Helper Functions

private func natsStatusText(_ status: natsStatus) -> String {
    if let text = natsStatus_GetText(status) {
        return String(cString: text)
    }
    return "Unknown error"
}
