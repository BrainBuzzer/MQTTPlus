//
//  NatsCClient.swift
//  MQTT Plus
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
    private let jsApiLock = NSLock()
    
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
    private var subscriptionContexts: [String: SubscriptionContext] = [:]

    // JetStream consumer subscriptions (pull subscribe async)
    private var jetStreamSubscriptions: [String: OpaquePointer] = [:]
    private var jetStreamContinuations: [String: AsyncStream<any MQAcknowledgeableMessage>.Continuation] = [:]
    private var jetStreamContexts: [String: JetStreamConsumeContext] = [:]
    
    // MARK: - Initialization
    
    public init(config: MQConnectionConfig) {
        self.config = config
    }
    
    deinit {
        // Cleanup all C resources synchronously
        cleanupResources()
    }
    
    private func cleanupResources() {
        jsApiLock.lock()
        lock.lock()
        defer { lock.unlock() }
        defer { jsApiLock.unlock() }
        
        // Close all subscriptions
        for (_, sub) in subscriptions {
            natsSubscription_Unsubscribe(sub)
            natsSubscription_Destroy(sub)
        }
        subscriptions.removeAll()

        for (_, sub) in jetStreamSubscriptions {
            natsSubscription_Unsubscribe(sub)
            natsSubscription_Destroy(sub)
        }
        jetStreamSubscriptions.removeAll()

        for (_, continuation) in messageContinuations {
            continuation.finish()
        }
        messageContinuations.removeAll()
        subscriptionContexts.removeAll()

        for (_, continuation) in jetStreamContinuations {
            continuation.finish()
        }
        jetStreamContinuations.removeAll()
        jetStreamContexts.removeAll()
        
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

    private func withJetStreamContext<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        jsApiLock.lock()
        defer { jsApiLock.unlock() }

        lock.lock()
        let currentState = _state
        let js = jsContext
        lock.unlock()

        guard currentState == .connected else { throw MQError.notConnected }
        guard let js else {
            throw MQError.operationNotSupported("JetStream is not available for this connection")
        }

        return try operation(js)
    }

    private func jetStreamKey(stream: String, consumer: String) -> String {
        "\(stream)::\(consumer)"
    }

    private func durationToMilliseconds(_ duration: Duration) -> Int64 {
        Int64(duration.components.seconds * 1000)
            + Int64(duration.components.attoseconds / 1_000_000_000_000_000)
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

            // Create JetStream context (optional; safe to continue if not enabled)
            var js: OpaquePointer?
            let jsStatus = natsConnection_JetStream(&js, conn, nil)
            if jsStatus == NATS_OK {
                lock.lock()
                self.jsContext = js
                lock.unlock()
            }
            
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
            let contextPtr = Unmanaged.passUnretained(context).toOpaque()

            self.lock.lock()
            self.subscriptionContexts[pattern] = context
            self.lock.unlock()
            
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

                // NATS message callbacks require the user to destroy the message.
                natsMsg_Destroy(msg)
                
            }, contextPtr)
            
            if status == NATS_OK {
                self.lock.lock()
                self.subscriptions[pattern] = sub
                self.lock.unlock()
            } else {
                self.lock.lock()
                self.subscriptionContexts.removeValue(forKey: pattern)
                self.lock.unlock()
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
        let (sub, continuation): (OpaquePointer?, AsyncStream<MQMessage>.Continuation?) = lock.withLock {
            let sub = subscriptions.removeValue(forKey: pattern)
            let continuation = messageContinuations.removeValue(forKey: pattern)
            subscriptionContexts.removeValue(forKey: pattern)
            return (sub, continuation)
        }
        
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

// MARK: - StreamingClient Protocol (JetStream)

extension NatsCClient: StreamingClient {
    
    public func listStreams() async throws -> [MQStreamInfo] {
        try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { throw MQError.notConnected }
            return try self.withJetStreamContext { js in
                var errCode = jsErrCode(rawValue: 0)
                var list: UnsafeMutablePointer<jsStreamInfoList>?
                let status = js_Streams(&list, js, nil, &errCode)
                guard status == NATS_OK, let list else {
                    throw MQError.providerError("JetStream listStreams failed: \(natsStatusText(status)) (jsErrCode: \(errCode))")
                }
                defer { jsStreamInfoList_Destroy(list) }

                let count = Int(list.pointee.Count)
                guard count > 0, let items = list.pointee.List else { return [] }

                var streams: [MQStreamInfo] = []
                streams.reserveCapacity(count)
                for i in 0..<count {
                    guard let si = items[i] else { continue }
                    streams.append(self.convertStreamInfo(si))
                }
                return streams.sorted { $0.name < $1.name }
            }
        }.value
    }
    
    public func createStream(_ config: MQStreamConfig) async throws -> MQStreamInfo {
        try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { throw MQError.notConnected }
            return try self.withJetStreamContext { js in
                var cfg = jsStreamConfig()
                var status = jsStreamConfig_Init(&cfg)
                guard status == NATS_OK else {
                    throw MQError.providerError("jsStreamConfig_Init failed: \(natsStatusText(status))")
                }

                guard let namePtr = self.dupCString(config.name) else {
                    throw MQError.providerError("Failed to allocate stream name")
                }
                let subjectPtrs = config.subjects.map { self.dupCString($0) }
                defer {
                    free(namePtr)
                    for ptr in subjectPtrs {
                        if let ptr { free(ptr) }
                    }
                }

                cfg.Name = UnsafePointer(namePtr)
                cfg.SubjectsLen = Int32(subjectPtrs.count)

                if subjectPtrs.contains(where: { $0 == nil }) {
                    throw MQError.providerError("Failed to allocate subjects array")
                }
                var cSubjects: [UnsafePointer<CChar>?] = subjectPtrs.map { UnsafePointer($0!) }
                return try cSubjects.withUnsafeMutableBufferPointer { buffer in
                    cfg.Subjects = buffer.baseAddress
                    cfg.Retention = self.convertRetentionPolicy(config.retention)
                    cfg.Storage = self.convertStorageType(config.storage)

                    if let maxAge = config.maxAge, maxAge > 0 {
                        cfg.MaxAge = Int64(maxAge * 1_000_000_000)
                    }
                    if let maxBytes = config.maxBytes, maxBytes > 0 {
                        cfg.MaxBytes = maxBytes
                    }
                    if let maxMsgSize = config.maxMsgSize, maxMsgSize > 0 {
                        cfg.MaxMsgSize = maxMsgSize
                    }
                    if let maxConsumers = config.maxConsumers, maxConsumers > 0 {
                        cfg.MaxConsumers = Int64(maxConsumers)
                    }
                    cfg.Replicas = Int64(max(1, config.replicas))
                    if let dupWindow = config.duplicateWindow, dupWindow > 0 {
                        cfg.Duplicates = Int64(dupWindow * 1_000_000_000)
                    }

                    var errCode = jsErrCode(rawValue: 0)
                    var si: UnsafeMutablePointer<jsStreamInfo>?
                    status = js_AddStream(&si, js, &cfg, nil, &errCode)
                    guard status == NATS_OK, let si else {
                        throw MQError.providerError("JetStream createStream failed: \(natsStatusText(status)) (jsErrCode: \(errCode))")
                    }
                    defer { jsStreamInfo_Destroy(si) }
                    return self.convertStreamInfo(si)
                }
            }
        }.value
    }
    
    public func deleteStream(_ name: String) async throws {
        try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { throw MQError.notConnected }
            try self.withJetStreamContext { js in
                var errCode = jsErrCode(rawValue: 0)
                let status = js_DeleteStream(js, name, nil, &errCode)
                guard status == NATS_OK else {
                    throw MQError.providerError("JetStream deleteStream failed: \(natsStatusText(status)) (jsErrCode: \(errCode))")
                }
            }
        }.value
    }
    
    public func getStreamInfo(_ name: String) async throws -> MQStreamInfo? {
        try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { throw MQError.notConnected }
            return try self.withJetStreamContext { js in
                var errCode = jsErrCode(rawValue: 0)
                var si: UnsafeMutablePointer<jsStreamInfo>?
                let status = js_GetStreamInfo(&si, js, name, nil, &errCode)
                if status == NATS_OK, let si {
                    defer { jsStreamInfo_Destroy(si) }
                    return self.convertStreamInfo(si)
                }
                if errCode == JSStreamNotFoundErr {
                    return nil
                }
                throw MQError.providerError("JetStream getStreamInfo failed: \(natsStatusText(status)) (jsErrCode: \(errCode))")
            }
        }.value
    }
    
    public func listConsumers(stream: String) async throws -> [MQConsumerInfo] {
        try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { throw MQError.notConnected }
            return try self.withJetStreamContext { js in
                var errCode = jsErrCode(rawValue: 0)
                var list: UnsafeMutablePointer<jsConsumerInfoList>?
                let status = js_Consumers(&list, js, stream, nil, &errCode)
                guard status == NATS_OK, let list else {
                    throw MQError.providerError("JetStream listConsumers failed: \(natsStatusText(status)) (jsErrCode: \(errCode))")
                }
                defer { jsConsumerInfoList_Destroy(list) }

                let count = Int(list.pointee.Count)
                guard count > 0, let items = list.pointee.List else { return [] }

                var consumers: [MQConsumerInfo] = []
                consumers.reserveCapacity(count)
                for i in 0..<count {
                    guard let ci = items[i] else { continue }
                    consumers.append(self.convertConsumerInfo(ci, defaultStream: stream))
                }
                return consumers.sorted { $0.name < $1.name }
            }
        }.value
    }
    
    public func createConsumer(stream: String, config: MQConsumerConfig) async throws -> MQConsumerInfo {
        try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { throw MQError.notConnected }
            return try self.withJetStreamContext { js in
                var cfg = jsConsumerConfig()
                var status = jsConsumerConfig_Init(&cfg)
                guard status == NATS_OK else {
                    throw MQError.providerError("jsConsumerConfig_Init failed: \(natsStatusText(status))")
                }

                guard let namePtr = self.dupCString(config.name) else {
                    throw MQError.providerError("Failed to allocate consumer name")
                }
                let filterPtr = config.filterSubject.flatMap { self.dupCString($0) }
                defer {
                    free(namePtr)
                    if let filterPtr { free(filterPtr) }
                }

                if config.durable {
                    cfg.Durable = UnsafePointer(namePtr)
                    cfg.Name = UnsafePointer(namePtr)
                } else {
                    cfg.Name = UnsafePointer(namePtr)
                }

                cfg.DeliverPolicy = self.convertDeliverPolicy(config.deliverPolicy)
                cfg.AckPolicy = self.convertAckPolicy(config.ackPolicy)
                cfg.ReplayPolicy = self.convertReplayPolicy(config.replayPolicy)
                cfg.AckWait = Int64(config.ackWait * 1_000_000_000)

                if let maxDeliver = config.maxDeliver, maxDeliver > 0 {
                    cfg.MaxDeliver = Int64(maxDeliver)
                }
                if let filterPtr {
                    cfg.FilterSubject = UnsafePointer(filterPtr)
                }
                if config.deliverPolicy == .byStartSequence, let seq = config.startSequence {
                    cfg.OptStartSeq = seq
                }
                if config.deliverPolicy == .byStartTime, let time = config.startTime {
                    cfg.OptStartTime = Int64(time.timeIntervalSince1970 * 1_000_000_000)
                }

                var errCode = jsErrCode(rawValue: 0)
                var ci: UnsafeMutablePointer<jsConsumerInfo>?
                status = js_AddConsumer(&ci, js, stream, &cfg, nil, &errCode)
                guard status == NATS_OK, let ci else {
                    throw MQError.providerError("JetStream createConsumer failed: \(natsStatusText(status)) (jsErrCode: \(errCode))")
                }
                defer { jsConsumerInfo_Destroy(ci) }
                return self.convertConsumerInfo(ci, defaultStream: stream)
            }
        }.value
    }
    
    public func deleteConsumer(stream: String, name: String) async throws {
        try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { throw MQError.notConnected }
            try self.withJetStreamContext { js in
                var errCode = jsErrCode(rawValue: 0)
                let status = js_DeleteConsumer(js, stream, name, nil, &errCode)
                guard status == NATS_OK else {
                    throw MQError.providerError("JetStream deleteConsumer failed: \(natsStatusText(status)) (jsErrCode: \(errCode))")
                }
            }
        }.value
    }
    
    public func publishPersistent(_ message: MQMessage, to subject: String) async throws -> MQPublishAck {
        try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { throw MQError.notConnected }
            return try self.withJetStreamContext { js in
                var errCode = jsErrCode(rawValue: 0)
                var pubAck: UnsafeMutablePointer<jsPubAck>?

                let status = message.payload.withUnsafeBytes { buffer in
                    js_Publish(
                        &pubAck,
                        js,
                        subject,
                        buffer.baseAddress,
                        Int32(message.payload.count),
                        nil,
                        &errCode
                    )
                }

                guard status == NATS_OK, let pubAck else {
                    throw MQError.publishFailed("JetStream publish failed: \(natsStatusText(status)) (jsErrCode: \(errCode))")
                }
                defer { jsPubAck_Destroy(pubAck) }

                let ack = pubAck.pointee
                let stream = ack.Stream.map { String(cString: $0) } ?? ""
                let domain = ack.Domain.map { String(cString: $0) }
                return MQPublishAck(stream: stream, sequence: ack.Sequence, duplicate: ack.Duplicate, domain: domain)
            }
        }.value
    }
    
    public func consume(stream: String, consumer: String) async throws -> AsyncStream<MQAcknowledgeableMessage> {
        let key = jetStreamKey(stream: stream, consumer: consumer)

        // Ensure we are connected and have JetStream context before creating the stream.
        try _ = withJetStreamContext { $0 }

        // Stop any existing consume stream for this key.
        await stopJetStreamConsume(key: key, shouldFinish: false)

        var continuationRef: AsyncStream<any MQAcknowledgeableMessage>.Continuation?
        let streamOut = AsyncStream<any MQAcknowledgeableMessage> { continuation in
            continuationRef = continuation
        }
        guard let continuation = continuationRef else { return streamOut }

        let context = JetStreamConsumeContext(
            key: key,
            streamName: stream,
            consumerName: consumer,
            continuation: continuation,
            client: self
        )
        let contextPtr = Unmanaged.passUnretained(context).toOpaque()

        let sub = try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { throw MQError.notConnected }
            return try self.withJetStreamContext { js in
                let filterSubject = try self.fetchConsumerFilterSubject(js: js, stream: stream, consumer: consumer) ?? ">"

                var subOpts = jsSubOptions()
                var status = jsSubOptions_Init(&subOpts)
                guard status == NATS_OK else {
                    throw MQError.providerError("jsSubOptions_Init failed: \(natsStatusText(status))")
                }

                guard let streamPtr = self.dupCString(stream) else {
                    throw MQError.providerError("Failed to allocate stream name")
                }
                guard let consumerPtr = self.dupCString(consumer) else {
                    free(streamPtr)
                    throw MQError.providerError("Failed to allocate consumer name")
                }
                defer {
                    free(streamPtr)
                    free(consumerPtr)
                }

                subOpts.Stream = UnsafePointer(streamPtr)
                subOpts.Consumer = UnsafePointer(consumerPtr)
                subOpts.ManualAck = true

                var jsOpts = jsOptions()
                _ = jsOptions_Init(&jsOpts)
                jsOpts.PullSubscribeAsync.FetchSize = 10

                var errCode = jsErrCode(rawValue: 0)
                var sub: OpaquePointer?
                status = js_PullSubscribeAsync(&sub, js, filterSubject, nil, { (_, _, msg, closure) in
                    guard let msg, let closure else { return }
                    let ctx = Unmanaged<JetStreamConsumeContext>.fromOpaque(closure).takeUnretainedValue()
                    do {
                        let metadata = try extractJetStreamMetadata(from: msg, defaultStream: ctx.streamName, defaultConsumer: ctx.consumerName)
                        let mqMessage = extractMQMessage(from: msg, timestamp: metadata.timestamp)
                        let ackable = try NatsJetStreamAcknowledgeableMessage(msg: msg, metadata: metadata, message: mqMessage)
                        ctx.continuation.yield(ackable)
                    } catch {
                        // If we fail to extract, ensure we don't leak the message.
                        natsMsg_Destroy(msg)
                    }
                }, contextPtr, &jsOpts, &subOpts, &errCode)

                guard status == NATS_OK, let sub else {
                    throw MQError.subscriptionFailed("JetStream consume failed: \(natsStatusText(status)) (jsErrCode: \(errCode))")
                }

                return sub
            }
        }.value

        lock.withLock {
            jetStreamSubscriptions[key] = sub
            jetStreamContinuations[key] = continuation
            jetStreamContexts[key] = context
        }

        continuation.onTermination = { @Sendable [weak self] _ in
            Task { [weak self] in
                await self?.stopJetStreamConsume(key: key, shouldFinish: false)
            }
        }

        return streamOut
    }
    
    public func fetch(stream: String, consumer: String, batch: Int, expires: Duration) async throws -> [MQAcknowledgeableMessage] {
        let batchSize = max(1, batch)
        let timeoutMs = durationToMilliseconds(expires)

        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { throw MQError.notConnected }
            return try self.withJetStreamContext { js in
                let filterSubject = try self.fetchConsumerFilterSubject(js: js, stream: stream, consumer: consumer) ?? ">"

                var subOpts = jsSubOptions()
                var status = jsSubOptions_Init(&subOpts)
                guard status == NATS_OK else {
                    throw MQError.providerError("jsSubOptions_Init failed: \(natsStatusText(status))")
                }

                guard let streamPtr = self.dupCString(stream) else {
                    throw MQError.providerError("Failed to allocate stream name")
                }
                guard let consumerPtr = self.dupCString(consumer) else {
                    free(streamPtr)
                    throw MQError.providerError("Failed to allocate consumer name")
                }
                defer {
                    free(streamPtr)
                    free(consumerPtr)
                }

                subOpts.Stream = UnsafePointer(streamPtr)
                subOpts.Consumer = UnsafePointer(consumerPtr)
                subOpts.ManualAck = true

                var errCode = jsErrCode(rawValue: 0)
                var sub: OpaquePointer?
                status = js_PullSubscribe(&sub, js, filterSubject, nil, nil, &subOpts, &errCode)
                guard status == NATS_OK, let sub else {
                    throw MQError.subscriptionFailed("JetStream fetch subscribe failed: \(natsStatusText(status)) (jsErrCode: \(errCode))")
                }
                defer {
                    natsSubscription_Unsubscribe(sub)
                    natsSubscription_Destroy(sub)
                }

                var list = natsMsgList()
                status = natsSubscription_Fetch(&list, sub, Int32(batchSize), timeoutMs, &errCode)
                if status == NATS_TIMEOUT {
                    return []
                }
                guard status == NATS_OK else {
                    throw MQError.timeout
                }

                defer { natsMsgList_Destroy(&list) }

                guard list.Count > 0, let msgs = list.Msgs else { return [] }

                var out: [any MQAcknowledgeableMessage] = []
                out.reserveCapacity(Int(list.Count))

                for i in 0..<Int(list.Count) {
                    guard let msg = msgs[i] else { continue }
                    do {
                        let metadata = try extractJetStreamMetadata(from: msg, defaultStream: stream, defaultConsumer: consumer)
                        let mqMessage = extractMQMessage(from: msg, timestamp: metadata.timestamp)
                        out.append(try NatsJetStreamAcknowledgeableMessage(msg: msg, metadata: metadata, message: mqMessage))
                        // Prevent natsMsgList_Destroy from destroying it; ownership transferred.
                        msgs[i] = nil
                    } catch {
                        // Let natsMsgList_Destroy clean up.
                    }
                }

                return out
            }
        }.value
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

// MARK: - JetStream Consume Context

private final class JetStreamConsumeContext {
    let key: String
    let streamName: String
    let consumerName: String
    let continuation: AsyncStream<any MQAcknowledgeableMessage>.Continuation
    weak var client: NatsCClient?

    init(
        key: String,
        streamName: String,
        consumerName: String,
        continuation: AsyncStream<any MQAcknowledgeableMessage>.Continuation,
        client: NatsCClient
    ) {
        self.key = key
        self.streamName = streamName
        self.consumerName = consumerName
        self.continuation = continuation
        self.client = client
    }
}

// MARK: - JetStream Message Wrapper

private final class NatsJetStreamAcknowledgeableMessage: @unchecked Sendable, MQAcknowledgeableMessage {
    let message: MQMessage
    let metadata: MQMessageMetadata

    private let lock = NSLock()
    private var msg: OpaquePointer?

    init(msg: OpaquePointer, metadata: MQMessageMetadata, message: MQMessage) throws {
        self.msg = msg
        self.metadata = metadata
        self.message = message
    }

    deinit {
        if let msg {
            natsMsg_Destroy(msg)
        }
    }

    func ack() async throws {
        try await performAck { msg in
            natsMsg_Ack(msg, nil)
        }
    }

    func nak(delay: Duration?) async throws {
        if let delay {
            let delayMs = Int64(delay.components.seconds * 1000)
                + Int64(delay.components.attoseconds / 1_000_000_000_000_000)
            try await performAck { msg in
                natsMsg_NakWithDelay(msg, delayMs, nil)
            }
        } else {
            try await performAck { msg in
                natsMsg_Nak(msg, nil)
            }
        }
    }

    func term() async throws {
        try await performAck { msg in
            natsMsg_Term(msg, nil)
        }
    }

    func inProgress() async throws {
        try await performAck { msg in
            natsMsg_InProgress(msg, nil)
        }
    }

    private func performAck(_ operation: @escaping (OpaquePointer) -> natsStatus) async throws {
        let msgToAck: OpaquePointer = try lock.withLock {
            guard let msg else {
                throw MQError.providerError("Message is no longer valid")
            }
            return msg
        }

        let status = operation(msgToAck)
        guard status == NATS_OK else {
            throw MQError.providerError("JetStream acknowledgment failed: \(natsStatusText(status))")
        }

        lock.withLock {
            if let msg {
                natsMsg_Destroy(msg)
                self.msg = nil
            }
        }
    }
}

// MARK: - Helper Functions

private func natsStatusText(_ status: natsStatus) -> String {
    if let text = natsStatus_GetText(status) {
        return String(cString: text)
    }
    return "Unknown error"
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private func extractMQMessage(from msg: OpaquePointer, timestamp: Date) -> MQMessage {
    let subject = String(cString: natsMsg_GetSubject(msg))
    let dataPtr = natsMsg_GetData(msg)
    let dataLen = natsMsg_GetDataLength(msg)

    let payload: Data = {
        guard let dataPtr, dataLen > 0 else { return Data() }
        return Data(bytes: dataPtr, count: Int(dataLen))
    }()

    let replyTo: String? = {
        guard let reply = natsMsg_GetReply(msg) else { return nil }
        return String(cString: reply)
    }()

    return MQMessage(
        subject: subject,
        payload: payload,
        headers: nil,
        replyTo: replyTo,
        timestamp: timestamp
    )
}

private func extractJetStreamMetadata(from msg: OpaquePointer, defaultStream: String, defaultConsumer: String) throws -> MQMessageMetadata {
    var meta: UnsafeMutablePointer<jsMsgMetaData>?
    let status = natsMsg_GetMetaData(&meta, msg)
    guard status == NATS_OK, let meta else {
        throw MQError.providerError("Failed to get JetStream metadata: \(natsStatusText(status))")
    }
    defer { jsMsgMetaData_Destroy(meta) }

    let streamName: String = {
        guard let c = meta.pointee.Stream else { return defaultStream }
        return String(cString: c)
    }()

    let consumerName: String? = {
        guard let c = meta.pointee.Consumer else { return defaultConsumer }
        let s = String(cString: c)
        return s.isEmpty ? nil : s
    }()

    let nanos = meta.pointee.Timestamp
    let timestamp = Date(timeIntervalSince1970: TimeInterval(nanos) / 1_000_000_000)

    return MQMessageMetadata(
        streamName: streamName,
        consumerName: consumerName,
        streamSequence: meta.pointee.Sequence.Stream,
        consumerSequence: meta.pointee.Sequence.Consumer,
        deliveryCount: meta.pointee.NumDelivered,
        pending: meta.pointee.NumPending,
        timestamp: timestamp
    )
}

private extension NatsCClient {
    func stopJetStreamConsume(key: String, shouldFinish: Bool) async {
        let (sub, continuation): (OpaquePointer?, AsyncStream<any MQAcknowledgeableMessage>.Continuation?) = lock.withLock {
            let sub = jetStreamSubscriptions.removeValue(forKey: key)
            let continuation = jetStreamContinuations.removeValue(forKey: key)
            jetStreamContexts.removeValue(forKey: key)
            return (sub, continuation)
        }

        if let sub {
            natsSubscription_Unsubscribe(sub)
            natsSubscription_Destroy(sub)
        }
        if shouldFinish {
            continuation?.finish()
        }
    }

    func dupCString(_ string: String) -> UnsafeMutablePointer<CChar>? {
        string.withCString { strdup($0) }
    }

    func fetchConsumerFilterSubject(js: OpaquePointer, stream: String, consumer: String) throws -> String? {
        var errCode = jsErrCode(rawValue: 0)
        var ci: UnsafeMutablePointer<jsConsumerInfo>?
        let status = js_GetConsumerInfo(&ci, js, stream, consumer, nil, &errCode)
        guard status == NATS_OK, let ci else {
            if errCode == JSConsumerNotFoundErr {
                return nil
            }
            throw MQError.providerError("JetStream getConsumerInfo failed: \(natsStatusText(status)) (jsErrCode: \(errCode))")
        }
        defer { jsConsumerInfo_Destroy(ci) }

        guard let cfg = ci.pointee.Config else { return nil }
        if let filter = cfg.pointee.FilterSubject {
            let str = String(cString: filter)
            return str.isEmpty ? nil : str
        }
        if cfg.pointee.FilterSubjectsLen > 0, let filters = cfg.pointee.FilterSubjects {
            if let first = filters[0] {
                let str = String(cString: first)
                return str.isEmpty ? nil : str
            }
        }
        return nil
    }

    func convertRetentionPolicy(_ policy: MQRetentionPolicy) -> jsRetentionPolicy {
        switch policy {
        case .limits:
            return js_LimitsPolicy
        case .interest:
            return js_InterestPolicy
        case .workQueue:
            return js_WorkQueuePolicy
        }
    }

    func convertStorageType(_ type: MQStorageType) -> jsStorageType {
        switch type {
        case .file:
            return js_FileStorage
        case .memory:
            return js_MemoryStorage
        }
    }

    func convertDeliverPolicy(_ policy: MQDeliverPolicy) -> jsDeliverPolicy {
        switch policy {
        case .all:
            return js_DeliverAll
        case .last:
            return js_DeliverLast
        case .new:
            return js_DeliverNew
        case .byStartSequence:
            return js_DeliverByStartSequence
        case .byStartTime:
            return js_DeliverByStartTime
        case .lastPerSubject:
            return js_DeliverLastPerSubject
        }
    }

    func convertAckPolicy(_ policy: MQAckPolicy) -> jsAckPolicy {
        switch policy {
        case .none:
            return js_AckNone
        case .all:
            return js_AckAll
        case .explicit:
            return js_AckExplicit
        }
    }

    func convertReplayPolicy(_ policy: MQReplayPolicy) -> jsReplayPolicy {
        switch policy {
        case .instant:
            return js_ReplayInstant
        case .original:
            return js_ReplayOriginal
        }
    }

    func convertStreamInfo(_ si: UnsafeMutablePointer<jsStreamInfo>) -> MQStreamInfo {
        let cfg = si.pointee.Config
        let name: String = {
            guard let cfg, let cName = cfg.pointee.Name else { return "unknown" }
            return String(cString: cName)
        }()

        let subjects: [String] = {
            guard let cfg, cfg.pointee.SubjectsLen > 0, let subjPtrs = cfg.pointee.Subjects else { return [] }
            return (0..<Int(cfg.pointee.SubjectsLen)).compactMap { i in
                guard let ptr = subjPtrs[i] else { return nil }
                return String(cString: ptr)
            }
        }()

        let retention: MQRetentionPolicy = {
            guard let cfg else { return .limits }
            switch cfg.pointee.Retention {
            case js_InterestPolicy: return .interest
            case js_WorkQueuePolicy: return .workQueue
            default: return .limits
            }
        }()

        let storage: MQStorageType = {
            guard let cfg else { return .file }
            switch cfg.pointee.Storage {
            case js_MemoryStorage: return .memory
            default: return .file
            }
        }()

        let createdAt = Date(timeIntervalSince1970: TimeInterval(si.pointee.Created) / 1_000_000_000)

        let maxAgeSeconds: TimeInterval? = {
            guard let cfg else { return nil }
            guard cfg.pointee.MaxAge > 0 else { return nil }
            return TimeInterval(cfg.pointee.MaxAge) / 1_000_000_000
        }()

        let maxBytes: Int64? = {
            guard let cfg else { return nil }
            return cfg.pointee.MaxBytes > 0 ? cfg.pointee.MaxBytes : nil
        }()

        let maxMsgSize: Int32? = {
            guard let cfg else { return nil }
            return cfg.pointee.MaxMsgSize > 0 ? cfg.pointee.MaxMsgSize : nil
        }()

        let maxConsumers: Int? = {
            guard let cfg else { return nil }
            return cfg.pointee.MaxConsumers > 0 ? Int(cfg.pointee.MaxConsumers) : nil
        }()

        let replicas: Int = {
            guard let cfg else { return 1 }
            return max(1, Int(cfg.pointee.Replicas))
        }()

        return MQStreamInfo(
            name: name,
            subjects: subjects,
            messageCount: si.pointee.State.Msgs,
            byteCount: si.pointee.State.Bytes,
            firstSequence: si.pointee.State.FirstSeq,
            lastSequence: si.pointee.State.LastSeq,
            retention: retention,
            storage: storage,
            maxAge: maxAgeSeconds,
            maxBytes: maxBytes,
            maxMsgSize: maxMsgSize,
            maxConsumers: maxConsumers,
            replicas: replicas,
            createdAt: createdAt
        )
    }

    func convertConsumerInfo(_ ci: UnsafeMutablePointer<jsConsumerInfo>, defaultStream: String) -> MQConsumerInfo {
        let streamName: String = {
            guard let cStream = ci.pointee.Stream else { return defaultStream }
            return String(cString: cStream)
        }()

        let name = ci.pointee.Name.map { String(cString: $0) } ?? "unknown"

        let cfg = ci.pointee.Config
        let durable: Bool = {
            guard let cfg, let durable = cfg.pointee.Durable else { return false }
            return !String(cString: durable).isEmpty
        }()

        let ackPolicy: MQAckPolicy = {
            guard let cfg else { return .explicit }
            switch cfg.pointee.AckPolicy {
            case js_AckNone: return .none
            case js_AckAll: return .all
            default: return .explicit
            }
        }()

        let deliverPolicy: MQDeliverPolicy = {
            guard let cfg else { return .all }
            switch cfg.pointee.DeliverPolicy {
            case js_DeliverLast: return .last
            case js_DeliverNew: return .new
            case js_DeliverByStartSequence: return .byStartSequence
            case js_DeliverByStartTime: return .byStartTime
            case js_DeliverLastPerSubject: return .lastPerSubject
            default: return .all
            }
        }()

        let replayPolicy: MQReplayPolicy = {
            guard let cfg else { return .instant }
            switch cfg.pointee.ReplayPolicy {
            case js_ReplayOriginal: return .original
            default: return .instant
            }
        }()

        let ackWaitSeconds: TimeInterval = {
            guard let cfg else { return 30 }
            return max(0, TimeInterval(cfg.pointee.AckWait) / 1_000_000_000)
        }()

        let maxDeliver: Int? = {
            guard let cfg else { return nil }
            return cfg.pointee.MaxDeliver > 0 ? Int(cfg.pointee.MaxDeliver) : nil
        }()

        let filterSubject: String? = {
            guard let cfg else { return nil }
            if let filter = cfg.pointee.FilterSubject {
                let str = String(cString: filter)
                return str.isEmpty ? nil : str
            }
            if cfg.pointee.FilterSubjectsLen > 0, let filters = cfg.pointee.FilterSubjects, let first = filters[0] {
                let str = String(cString: first)
                return str.isEmpty ? nil : str
            }
            return nil
        }()

        let createdAt = Date(timeIntervalSince1970: TimeInterval(ci.pointee.Created) / 1_000_000_000)

        return MQConsumerInfo(
            streamName: streamName,
            name: name,
            durable: durable,
            pending: ci.pointee.NumPending,
            delivered: ci.pointee.Delivered.Consumer,
            redelivered: UInt64(max(0, ci.pointee.NumRedelivered)),
            ackPolicy: ackPolicy,
            deliverPolicy: deliverPolicy,
            replayPolicy: replayPolicy,
            ackWait: ackWaitSeconds,
            maxDeliver: maxDeliver,
            filterSubject: filterSubject,
            createdAt: createdAt
        )
    }
}
