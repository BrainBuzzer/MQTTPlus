//
//  ConnectionManager.swift
//  MQTT Plus
//
//  Created by Aditya on 10/01/26.
//  Refactored to use C FFI via NatsCClient
//

import Foundation
import Combine

// MARK: - Models

enum MQProviderKind: String, Sendable, Hashable, CaseIterable {
    case nats
    case redis
    case kafka

    init?(providerId: String) {
        self.init(rawValue: providerId.lowercased())
    }

    init?(urlString: String) {
        if urlString.hasPrefix("nats://") || urlString.hasPrefix("tls://") {
            self = .nats
        } else if urlString.hasPrefix("redis://") || urlString.hasPrefix("rediss://") {
            self = .redis
        } else if urlString.hasPrefix("kafka://") || urlString.hasPrefix("kafkas://") {
            self = .kafka
        } else {
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .nats: return "NATS"
        case .redis: return "Redis"
        case .kafka: return "Kafka"
        }
    }

    var firehosePattern: String {
        switch self {
        case .nats: return ">"
        case .redis: return "*"
        case .kafka: return "*"  // Wildcard for Kafka topic matching
        }
    }

    var defaultPort: Int {
        switch self {
        case .nats: return 4222
        case .redis: return 6379
        case .kafka: return 9092
        }
    }
}

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

/// JetStream message wrapper that includes required metadata and supports stable selection.
struct JetStreamMessageEnvelope: Identifiable, Hashable {
    let message: MQMessage
    let metadata: MQMessageMetadata

    var id: UUID { message.id }
    var subject: String { message.subject }
    var payloadString: String { message.payloadString ?? "" }
    var headers: [String: String]? { message.headers }
    var replyTo: String? { message.replyTo }
    var byteCount: Int { message.byteCount }
    var timestamp: Date { message.timestamp }
}

/// Connection state for the NATS client
enum ConnectionState: Equatable {
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
class ConnectionManager: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var subscribedSubjects: [String] = []
    @Published var messages: [ReceivedMessage] = []
    @Published var currentServerName: String?
    @Published var currentServerID: UUID?
    @Published var logs: [LogEntry] = []
    
    // JetStream support
    @Published var mode: ConnectionMode = .core
    
    // Streams and Consumers (JetStream)
    @Published var streams: [MQStreamInfo] = []
    @Published var consumers: [String: [MQConsumerInfo]] = [:]
    @Published var jetStreamMessages: [JetStreamMessageEnvelope] = []

    @Published var currentProvider: MQProviderKind?
    @Published var isFirehoseEnabled: Bool = false
    @Published var isPaused: Bool = false
    @Published var pausedMessageCount: Int = 0
    @Published var messageRetentionLimit: Int = 500
    
    struct LogEntry: Identifiable, Hashable {
        let id = UUID()
        let timestamp = Date()
        let level: LogLevel
        let message: String
        
        enum LogLevel: String {
            case info, warning, error
        }
    }

    // Active MQ client (provider-dependent)
    private var client: (any MessageQueueClient)?
    private var firehoseTask: Task<Void, Never>?
    private var activeFirehosePattern: String?
    private var subscriptionTasksByPattern: [String: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()

    private var pausedBuffer: [ReceivedMessage] = []

    private var jetStreamConsumeTask: Task<Void, Never>?
    private var jetStreamAckablesById: [UUID: any MQAcknowledgeableMessage] = [:]

    var activeClient: (any MessageQueueClient)? {
        client
    }
    
    init() {}
    
    // MARK: - Connection Management
    
    func connect(
        to urlString: String,
        providerId: String? = nil,
        serverName: String,
        serverID: UUID? = nil,
        mode: ConnectionMode = .core,
        username: String? = nil,
        password: String? = nil,
        token: String? = nil,
        tlsEnabledOverride: Bool? = nil,
        options: [String: String] = [:]
    ) async {
        guard connectionState != .connecting else { return }

        log("Initiating connection to \(serverName) (\(sanitizeURL(urlString)))...", level: .info)
        connectionState = .connecting
        currentServerName = serverName
        currentServerID = serverID

        let inferredProvider = providerId.flatMap { MQProviderKind(providerId: $0) } ?? MQProviderKind(urlString: urlString)
        guard let provider = inferredProvider else {
            let errorMsg = "Unsupported URL scheme"
            connectionState = .error(errorMsg)
            log(errorMsg, level: .error)
            return
        }

        currentProvider = provider
        isFirehoseEnabled = defaultFirehoseEnabled(for: provider)
        self.mode = (provider == .nats) ? mode : .core

        // Log connection mode
        log("Provider: \(provider.displayName)", level: .info)
        if provider == .nats {
            log("Connection mode: \(self.mode.description)", level: .info)
        }

        do {
            let url = URL(string: urlString)
            let parsedUsername = (url?.user?.isEmpty == false) ? url?.user : nil
            let parsedPassword = url?.password
            let tlsEnabled = tlsEnabledOverride ?? ((url?.scheme?.lowercased() == "tls")
                || (url?.scheme?.lowercased() == "rediss")
                || (url?.scheme?.lowercased() == "kafkas"))

            // Create configuration
            let config = MQConnectionConfig(
                url: sanitizeURL(urlString),
                name: serverName,
                username: username ?? parsedUsername,
                password: password ?? parsedPassword,
                token: token,
                tlsEnabled: tlsEnabled,
                options: options
            )

            let resolvedProviderId = providerId?.lowercased() ?? provider.rawValue
            var mqClient = MQProviderRegistry.shared.createClient(provider: resolvedProviderId, config: config)
            if mqClient == nil {
                registerAllProviders()
                mqClient = MQProviderRegistry.shared.createClient(provider: resolvedProviderId, config: config)
            }
            guard let mqClient else {
                throw MQError.invalidConfiguration("Unknown provider: \(resolvedProviderId)")
            }
            self.client = mqClient

            // Subscribe to state changes
            mqClient.statePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.connectionState = ConnectionState(from: state)
                }
                .store(in: &cancellables)

            // Connect
            try await mqClient.connect()

            connectionState = .connected
            log("Connected to \(urlString)", level: .info)

            // Optional firehose subscription
            if isFirehoseEnabled {
                startFirehoseSubscription()
            }

            // Provider-specific post-connect actions
            if provider == .kafka {
                if let kafkaClient = mqClient as? StreamingClient {
                    do {
                        let topics = try await kafkaClient.listStreams()
                        streams = topics
                        log("Found \(topics.count) Kafka topics", level: .info)
                    } catch {
                        log("Failed to list Kafka topics: \(error.localizedDescription)", level: .warning)
                    }
                }
            }

            // Initialize JetStream if in JetStream mode (NATS only)
            if provider == .nats, self.mode == .jetstream {
                log("JetStream mode initialized", level: .info)

                // Load streams
                await refreshStreams()
            }
            
        } catch {
            self.client = nil
            connectionState = .error(error.localizedDescription)
            log("Connection failed: \(error.localizedDescription)", level: .error)
            print("[ConnectionManager] Connection error: \(error)")
        }
    }

    private func sanitizeURL(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else { return urlString }
        components.user = nil
        components.password = nil
        return components.string ?? urlString
    }

    private func defaultFirehoseEnabled(for provider: MQProviderKind) -> Bool {
        switch provider {
        case .nats:
            return true
        case .redis:
            return false
        case .kafka:
            return false
        }
    }
    
    func disconnect() {
        let clientToDisconnect = client
        Task {
            await clientToDisconnect?.disconnect()
        }
        handleDisconnect()
    }
    
    private func handleDisconnect() {
        firehoseTask?.cancel()
        firehoseTask = nil
        activeFirehosePattern = nil

        for (_, task) in subscriptionTasksByPattern {
            task.cancel()
        }
        subscriptionTasksByPattern.removeAll()

        client = nil
        subscribedSubjects.removeAll()
        connectionState = .disconnected
        currentServerName = nil
        currentServerID = nil
        currentProvider = nil
        isFirehoseEnabled = false
        isPaused = false
        pausedMessageCount = 0
        pausedBuffer.removeAll()
        streams.removeAll()
        consumers.removeAll()
        jetStreamConsumeTask?.cancel()
        jetStreamConsumeTask = nil
        jetStreamMessages.removeAll()
        jetStreamAckablesById.removeAll()
        cancellables.removeAll()
        log("Disconnected", level: .info)
        print("[ConnectionManager] Disconnected")
    }
    
    // MARK: - Subscription Management
    
    func setFirehoseEnabled(_ enabled: Bool) {
        isFirehoseEnabled = enabled
        if enabled {
            startFirehoseSubscription()
        } else {
            stopFirehoseSubscription()
        }
    }

    private func startFirehoseSubscription() {
        guard let client, connectionState.isConnected else { return }

        let pattern = currentProvider?.firehosePattern ?? ">"
        activeFirehosePattern = pattern

        firehoseTask?.cancel()
        firehoseTask = Task { [weak self] in
            do {
                let stream = try await client.subscribe(to: pattern)

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

        log("Subscribed to Firehose (\(pattern))", level: .info)
    }

    private func stopFirehoseSubscription() {
        firehoseTask?.cancel()
        firehoseTask = nil

        guard let pattern = activeFirehosePattern else { return }
        activeFirehosePattern = nil

        Task { [weak self] in
            try? await self?.client?.unsubscribe(from: pattern)
        }

        log("Unsubscribed from Firehose (\(pattern))", level: .info)
    }
    
    func subscribe(to subject: String) {
        let pattern = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        guard !subscribedSubjects.contains(pattern) else { return }

        subscribedSubjects.append(pattern)
        log("Subscribing to \(pattern)…", level: .info)

        startPatternSubscription(pattern)
    }
    
    func unsubscribe(from subject: String) {
        let pattern = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        subscribedSubjects.removeAll { $0 == pattern }

        let task = subscriptionTasksByPattern.removeValue(forKey: pattern)
        task?.cancel()

        Task { [weak self] in
            try? await self?.client?.unsubscribe(from: pattern)
        }

        log("Unsubscribed from \(pattern)", level: .info)
    }

    private func startPatternSubscription(_ pattern: String) {
        guard let client, connectionState.isConnected else { return }
        guard subscriptionTasksByPattern[pattern] == nil else { return }

        subscriptionTasksByPattern[pattern] = Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.subscriptionTasksByPattern.removeValue(forKey: pattern)
                }
            }

            do {
                let stream = try await client.subscribe(to: pattern)
                for await message in stream {
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        self?.handleMessage(message)
                    }
                }
            } catch {
                await MainActor.run {
                    self?.log("Subscription error (\(pattern)): \(error.localizedDescription)", level: .error)
                }
            }
        }
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
        
        print("[ConnectionManager] Published to \(subject): \(payload)")
    }
    
    // MARK: - JetStream Operations
    
    func refreshStreams() async {
        guard mode == .jetstream, currentProvider == .nats else { return }
        guard let client = client as? any StreamingClient else { return }

        do {
            let streamList = try await client.listStreams()
            streams = streamList
            log("Loaded \(streamList.count) streams", level: .info)
        } catch {
            log("Failed to list streams: \(error.localizedDescription)", level: .error)
        }
    }
    
    func createStream(_ config: MQStreamConfig) async throws -> MQStreamInfo {
        guard mode == .jetstream, currentProvider == .nats else {
            throw MQError.notConnected
        }
        guard let client = client as? any StreamingClient else {
            throw MQError.operationNotSupported("Streaming not supported")
        }

        let stream = try await client.createStream(config)
        await refreshStreams()
        log("Created stream: \(stream.name)", level: .info)
        return stream
    }
    
    func deleteStream(_ name: String) async throws {
        guard mode == .jetstream, currentProvider == .nats else {
            throw MQError.notConnected
        }
        guard let client = client as? any StreamingClient else {
            throw MQError.operationNotSupported("Streaming not supported")
        }

        try await client.deleteStream(name)
        await refreshStreams()
        log("Deleted stream: \(name)", level: .info)
    }
    
    func refreshConsumers(for stream: String) async {
        guard mode == .jetstream, currentProvider == .nats else { return }
        guard let client = client as? any StreamingClient else { return }

        do {
            let consumerList = try await client.listConsumers(stream: stream)
            consumers[stream] = consumerList
            log("Loaded \(consumerList.count) consumers for \(stream)", level: .info)
        } catch {
            log("Failed to list consumers: \(error.localizedDescription)", level: .error)
        }
    }
    
    func createConsumer(stream: String, config: MQConsumerConfig) async throws -> MQConsumerInfo {
        guard mode == .jetstream, currentProvider == .nats else {
            throw MQError.notConnected
        }
        guard let client = client as? any StreamingClient else {
            throw MQError.operationNotSupported("Streaming not supported")
        }

        let consumer = try await client.createConsumer(stream: stream, config: config)
        await refreshConsumers(for: stream)
        log("Created consumer: \(consumer.name)", level: .info)
        return consumer
    }
    
    func deleteConsumer(stream: String, name: String) async throws {
        guard mode == .jetstream, currentProvider == .nats else {
            throw MQError.notConnected
        }
        guard let client = client as? any StreamingClient else {
            throw MQError.operationNotSupported("Streaming not supported")
        }

        try await client.deleteConsumer(stream: stream, name: name)
        await refreshConsumers(for: stream)
        log("Deleted consumer: \(name)", level: .info)
    }
    
    func publishToJetStream(to subject: String, payload: String) async throws -> MQPublishAck {
        guard mode == .jetstream, currentProvider == .nats else {
            throw MQError.notConnected
        }
        guard let client = client as? any StreamingClient else {
            throw MQError.operationNotSupported("Streaming not supported")
        }

        let message = MQMessage(subject: subject, payloadString: payload)
        let ack = try await client.publishPersistent(message, to: subject)
        log("JetStream published to \(subject), seq: \(ack.sequence)", level: .info)
        return ack
    }

    func startJetStreamConsume(stream: String, consumer: String) {
        guard mode == .jetstream, currentProvider == .nats else { return }
        guard let client = client as? any StreamingClient else { return }
        guard connectionState.isConnected else { return }

        jetStreamConsumeTask?.cancel()
        clearJetStreamMessages()

        jetStreamConsumeTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let messageStream = try await client.consume(stream: stream, consumer: consumer)
                for await ackable in messageStream {
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        let envelope = JetStreamMessageEnvelope(message: ackable.message, metadata: ackable.metadata)
                        self.jetStreamAckablesById[envelope.id] = ackable
                        self.jetStreamMessages.insert(envelope, at: 0)
                        self.trimJetStreamMessagesIfNeeded()
                    }
                }
            } catch {
                await MainActor.run {
                    self.log("JetStream consume error: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    func stopJetStreamConsume() {
        jetStreamConsumeTask?.cancel()
        jetStreamConsumeTask = nil
    }

    func clearJetStreamMessages() {
        jetStreamMessages.removeAll()
        jetStreamAckablesById.removeAll()
    }

    func acknowledgeJetStreamMessage(id: UUID, type: MQAckType, delay: Duration? = nil) async throws {
        guard let ackable = jetStreamAckablesById[id] else {
            throw MQError.providerError("JetStream message is no longer available")
        }

        switch type {
        case .ack:
            try await ackable.ack()
        case .nak:
            try await ackable.nak(delay: delay)
        case .term:
            try await ackable.term()
        case .inProgress:
            try await ackable.inProgress()
        }
    }
    
    // MARK: - Message Handling
    
    func previewTopic(_ topic: String) {
        guard let kafkaClient = client as? KafkaClient else { return }
        
        Task { @MainActor in
            do {
                let msgs = try await kafkaClient.fetchLastMessages(topic: topic, count: 20)
                let receivedMsgs = msgs.map { ReceivedMessage(from: $0) }
                
                // Deduplicate based on kafka.offset
                let existingOffsets = Set(self.messages
                    .filter { $0.subject == topic }
                    .compactMap { $0.headers?["kafka.offset"] }
                )
                
                let uniqueMsgs = receivedMsgs.filter { msg in
                    guard let offset = msg.headers?["kafka.offset"] else { return true }
                    return !existingOffsets.contains(offset)
                }
                
                if !uniqueMsgs.isEmpty {
                    self.messages.append(contentsOf: uniqueMsgs)
                    self.messages.sort { $0.receivedAt < $1.receivedAt }
                }
            } catch {
                if let mqError = error as? MQError, case .providerError(let msg) = mqError {
                   log("Failed to preview topic \(topic): \(msg)", level: .error)
                } else {
                   log("Failed to preview topic \(topic): \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    private func handleMessage(_ message: MQMessage) {
        let receivedMessage = ReceivedMessage(from: message)
        addMessage(receivedMessage)
    }
    
    private func addMessage(_ message: ReceivedMessage) {
        // Deduplication check for Kafka messages
        if let newOffset = message.headers?["kafka.offset"] {
            let isDuplicate = messages.contains { existingMsg in
                existingMsg.subject == message.subject &&
                existingMsg.headers?["kafka.offset"] == newOffset
            }
            if isDuplicate { return }
            
            // Also check paused buffer if paused
            if isPaused {
                let isDuplicateInPaused = pausedBuffer.contains { existingMsg in
                    existingMsg.subject == message.subject &&
                    existingMsg.headers?["kafka.offset"] == newOffset
                }
                if isDuplicateInPaused { return }
            }
        }
        
        if isPaused {
            pausedBuffer.insert(message, at: 0)
            trimPausedBufferIfNeeded()
            pausedMessageCount = pausedBuffer.count
            return
        }

        messages.insert(message, at: 0)
        trimMessagesIfNeeded()
    }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused

        if !paused {
            if !pausedBuffer.isEmpty {
                messages.insert(contentsOf: pausedBuffer, at: 0)
                pausedBuffer.removeAll()
                pausedMessageCount = 0
                trimMessagesIfNeeded()
            }
        }
    }

    func setMessageRetentionLimit(_ limit: Int) {
        messageRetentionLimit = max(1, limit)
        trimMessagesIfNeeded()
        trimPausedBufferIfNeeded()
        pausedMessageCount = pausedBuffer.count
    }

    private func trimMessagesIfNeeded() {
        let limit = max(1, messageRetentionLimit)
        if messages.count > limit {
            messages = Array(messages.prefix(limit))
        }
    }

    private func trimPausedBufferIfNeeded() {
        let limit = max(1, messageRetentionLimit)
        if pausedBuffer.count > limit {
            pausedBuffer = Array(pausedBuffer.prefix(limit))
        }
    }

    private func trimJetStreamMessagesIfNeeded() {
        let limit = max(1, messageRetentionLimit)
        guard jetStreamMessages.count > limit else { return }

        let overflow = jetStreamMessages.suffix(from: limit)
        for message in overflow {
            jetStreamAckablesById.removeValue(forKey: message.id)
        }
        jetStreamMessages.removeLast(jetStreamMessages.count - limit)
    }
    
    func clearMessages() {
        messages.removeAll()
        pausedBuffer.removeAll()
        pausedMessageCount = 0
    }
    
    func clearMessages(for subject: String) {
        messages.removeAll { $0.subject == subject }
        pausedBuffer.removeAll { $0.subject == subject }
        pausedMessageCount = pausedBuffer.count
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
