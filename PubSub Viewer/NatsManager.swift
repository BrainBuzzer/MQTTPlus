//
//  NatsManager.swift
//  PubSub Viewer
//
//  Created by Aditya on 10/01/26.
//  Refactored to use C FFI via NatsCClient
//

import Foundation
import Combine

// MARK: - Models

/// Represents a single received message (our app model)
struct ReceivedMessage: Identifiable, Hashable {
    let id = UUID()
    let subject: String
    let payload: String
    let headers: [String: String]?
    let replyTo: String?
    let byteCount: Int
    let receivedAt: Date
    
    // Convert from MQMessage
    init(from message: MQMessage) {
        self.subject = message.subject
        self.payload = message.payloadString ?? ""
        self.headers = message.headers
        self.replyTo = message.replyTo
        self.byteCount = message.byteCount
        self.receivedAt = message.timestamp
    }
    
    // Legacy init for compatibility
    init(subject: String, payload: String, headers: [String: String]?, replyTo: String?, byteCount: Int, receivedAt: Date) {
        self.subject = subject
        self.payload = payload
        self.headers = headers
        self.replyTo = replyTo
        self.byteCount = byteCount
        self.receivedAt = receivedAt
    }
}

/// Connection state for the NATS client
enum NatsConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
    
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    
    // Convert from MQConnectionState
    init(from state: MQConnectionState) {
        switch state {
        case .disconnected: self = .disconnected
        case .connecting: self = .connecting
        case .connected: self = .connected
        case .reconnecting: self = .connecting
        case .error(let msg): self = .error(msg)
        }
    }
}

// MARK: - NATS Manager

/// Manager class for NATS connections using C FFI
@MainActor
class NatsManager: ObservableObject {
    static let shared = NatsManager()
    
    @Published var connectionState: NatsConnectionState = .disconnected
    @Published var subscribedSubjects: [String] = []
    @Published var messages: [ReceivedMessage] = []
    @Published var currentServerName: String?
    @Published var logs: [LogEntry] = []
    
    // JetStream support
    @Published var mode: NatsMode = .core
    @Published var jetStreamManager: JetStreamManager?
    
    // Streams and Consumers (JetStream)
    @Published var streams: [MQStreamInfo] = []
    @Published var consumers: [String: [MQConsumerInfo]] = [:]
    
    struct LogEntry: Identifiable, Hashable {
        let id = UUID()
        let timestamp = Date()
        let level: LogLevel
        let message: String
        
        enum LogLevel: String {
            case info, warning, error
        }
    }
    
    // C FFI Client
    private var client: NatsCClient?
    private var subscriptionTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // MARK: - Connection Management
    
    func connect(to urlString: String, serverName: String, mode: NatsMode = .core) async {
        guard connectionState != .connecting else { return }
        
        log("Initiating connection to \(serverName) (\(urlString))...", level: .info)
        connectionState = .connecting
        currentServerName = serverName
        self.mode = mode
        
        // Log connection mode
        log("Connection mode: \(mode.description)", level: .info)
        
        // Validate URL format
        guard urlString.hasPrefix("nats://") || urlString.hasPrefix("tls://") else {
            let errorMsg = "Invalid NATS URL format"
            connectionState = .error(errorMsg)
            log(errorMsg, level: .error)
            return
        }
        
        do {
            // Create configuration
            let config = MQConnectionConfig(
                url: urlString,
                name: serverName
            )
            
            // Create C FFI client
            let natsClient = NatsCClient(config: config)
            self.client = natsClient
            
            // Subscribe to state changes
            natsClient.statePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.connectionState = NatsConnectionState(from: state)
                }
                .store(in: &cancellables)
            
            // Connect
            try await natsClient.connect()
            
            connectionState = .connected
            log("Connected to \(urlString)", level: .info)
            
            // Auto-subscribe to firehose
            subscribeToFirehose()
            
            // Initialize JetStream if in JetStream mode
            if mode == .jetstream {
                jetStreamManager = JetStreamManager()
                log("JetStream mode initialized", level: .info)
                
                // Load streams
                await refreshStreams()
            }
            
        } catch {
            self.client = nil
            connectionState = .error(error.localizedDescription)
            log("Connection failed: \(error.localizedDescription)", level: .error)
            print("[NatsManager] Connection error: \(error)")
        }
    }
    
    func disconnect() {
        Task {
            await client?.disconnect()
        }
        handleDisconnect()
    }
    
    private func handleDisconnect() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        client = nil
        subscribedSubjects.removeAll()
        connectionState = .disconnected
        currentServerName = nil
        streams.removeAll()
        consumers.removeAll()
        jetStreamManager = nil
        cancellables.removeAll()
        log("Disconnected", level: .info)
        print("[NatsManager] Disconnected")
    }
    
    // MARK: - Subscription Management
    
    private func subscribeToFirehose() {
        guard let client = client else { return }
        
        subscriptionTask = Task { [weak self] in
            do {
                let stream = try await client.subscribe(to: ">")
                
                for await message in stream {
                    guard !Task.isCancelled else { break }
                    
                    await MainActor.run {
                        self?.handleMessage(message)
                    }
                }
            } catch {
                await MainActor.run {
                    self?.log("Firehose subscription error: \(error.localizedDescription)", level: .error)
                }
            }
        }
        
        log("Subscribed to Firehose (>)", level: .info)
        print("[NatsManager] Subscribed to Firehose (>)")
    }
    
    func subscribe(to subject: String) {
        // Just track the subject for UI filtering
        guard !subscribedSubjects.contains(subject) else { return }
        subscribedSubjects.append(subject)
        log("Added local filter: \(subject)", level: .info)
        print("[NatsManager] Added filter: \(subject)")
    }
    
    func unsubscribe(from subject: String) {
        // Just remove from tracking
        subscribedSubjects.removeAll { $0 == subject }
        log("Removed local filter: \(subject)", level: .info)
        print("[NatsManager] Removed filter: \(subject)")
    }
    
    // MARK: - Publishing
    
    func publish(to subject: String, payload: String) {
        guard let client = client, connectionState.isConnected else { return }
        
        Task {
            do {
                let message = MQMessage(subject: subject, payloadString: payload)
                try await client.publish(message, to: subject)
                
                await MainActor.run {
                    self.log("Published to \(subject): \(payload)", level: .info)
                }
            } catch {
                await MainActor.run {
                    self.log("Publish failed: \(error.localizedDescription)", level: .error)
                }
            }
        }
        
        print("[NatsManager] Published to \(subject): \(payload)")
    }
    
    // MARK: - JetStream Operations
    
    func refreshStreams() async {
        guard let client = client, mode == .jetstream else { return }
        
        do {
            let streamList = try await client.listStreams()
            streams = streamList
            log("Loaded \(streamList.count) streams", level: .info)
        } catch {
            log("Failed to list streams: \(error.localizedDescription)", level: .error)
        }
    }
    
    func createStream(_ config: MQStreamConfig) async throws -> MQStreamInfo {
        guard let client = client, mode == .jetstream else {
            throw MQError.notConnected
        }
        
        let stream = try await client.createStream(config)
        await refreshStreams()
        log("Created stream: \(stream.name)", level: .info)
        return stream
    }
    
    func deleteStream(_ name: String) async throws {
        guard let client = client, mode == .jetstream else {
            throw MQError.notConnected
        }
        
        try await client.deleteStream(name)
        await refreshStreams()
        log("Deleted stream: \(name)", level: .info)
    }
    
    func refreshConsumers(for stream: String) async {
        guard let client = client, mode == .jetstream else { return }
        
        do {
            let consumerList = try await client.listConsumers(stream: stream)
            consumers[stream] = consumerList
            log("Loaded \(consumerList.count) consumers for \(stream)", level: .info)
        } catch {
            log("Failed to list consumers: \(error.localizedDescription)", level: .error)
        }
    }
    
    func createConsumer(stream: String, config: MQConsumerConfig) async throws -> MQConsumerInfo {
        guard let client = client, mode == .jetstream else {
            throw MQError.notConnected
        }
        
        let consumer = try await client.createConsumer(stream: stream, config: config)
        await refreshConsumers(for: stream)
        log("Created consumer: \(consumer.name)", level: .info)
        return consumer
    }
    
    func deleteConsumer(stream: String, name: String) async throws {
        guard let client = client, mode == .jetstream else {
            throw MQError.notConnected
        }
        
        try await client.deleteConsumer(stream: stream, name: name)
        await refreshConsumers(for: stream)
        log("Deleted consumer: \(name)", level: .info)
    }
    
    func publishToJetStream(to subject: String, payload: String) async throws -> MQPublishAck {
        guard let client = client, mode == .jetstream else {
            throw MQError.notConnected
        }
        
        let message = MQMessage(subject: subject, payloadString: payload)
        let ack = try await client.publishPersistent(message, to: subject)
        log("JetStream published to \(subject), seq: \(ack.sequence)", level: .info)
        return ack
    }
    
    // MARK: - Message Handling
    
    private func handleMessage(_ message: MQMessage) {
        let receivedMessage = ReceivedMessage(from: message)
        addMessage(receivedMessage)
    }
    
    private func addMessage(_ message: ReceivedMessage) {
        messages.insert(message, at: 0)
        
        // Keep only last 500 messages to prevent memory issues
        if messages.count > 500 {
            messages = Array(messages.prefix(500))
        }
    }
    
    func clearMessages() {
        messages.removeAll()
    }
    
    func clearMessages(for subject: String) {
        messages.removeAll { $0.subject == subject }
    }
    
    // MARK: - Logging
    
    func log(_ message: String, level: LogEntry.LogLevel = .info) {
        let entry = LogEntry(level: level, message: message)
        
        Task { @MainActor in
            logs.append(entry)
            if logs.count > 1000 {
                logs.removeFirst(logs.count - 1000)
            }
        }
    }
}
