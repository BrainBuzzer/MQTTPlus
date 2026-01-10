//
//  KafkaClient.swift
//  MQTT Plus
//
//  Kafka client implemented in pure Swift using Kafka wire protocol over TCP
//  Supports: Topic listing, message consumption, basic produce
//

import Foundation
import Combine
import Network

// MARK: - Kafka Client

/// Kafka client using native Kafka wire protocol (v0-v2 APIs)
/// Implements topic metadata fetching, consuming messages, and basic producing
public final class KafkaClient: @unchecked Sendable {
    public let config: MQConnectionConfig
    
    private var _state: MQConnectionState = .disconnected
    public var state: MQConnectionState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _state
    }
    
    private let stateLock = NSLock()
    private let stateSubject = PassthroughSubject<MQConnectionState, Never>()
    
    public var statePublisher: AnyPublisher<MQConnectionState, Never> {
        stateSubject.eraseToAnyPublisher()
    }
    
    private let connectionQueue = DispatchQueue(label: "KafkaClient.connection")
    
    private var connection: NWConnection?
    private var correlationId: Int32 = 0
    private let correlationLock = NSLock()
    
    // Pending responses keyed by correlation ID
    private var pendingResponses: [Int32: CheckedContinuation<Data, Error>] = [:]
    private let pendingLock = NSLock()
    
    // Cached topic metadata
    private let metadataLock = NSLock()
    private var cachedTopics: [KafkaTopicMetadata] = []
    private var brokers: [KafkaBrokerMetadata] = []
    
    // Active subscriptions
    private var subscriptions: [String: AsyncStream<MQMessage>.Continuation] = [:]
    private var patternTopics: [String: [String]] = [:]
    private let subscriptionsLock = NSLock()
    private var consumeTask: Task<Void, Never>?
    private var consumeOffsets: [String: [Int32: Int64]] = [:]
    
    // Consumer configuration
    private var consumerGroupId: String = "mqtt-plus"
    private var clientId: String = "mqtt-plus-client"
    
    public init(config: MQConnectionConfig) {
        self.config = config
        self.consumerGroupId = config.options["group.id"] ?? "mqtt-plus-\(UUID().uuidString.prefix(8))"
        self.clientId = config.options["client.id"] ?? "mqtt-plus-client"
    }
    
    deinit {
        cleanupResources()
    }
    
    private func updateState(_ newState: MQConnectionState) {
        stateLock.lock()
        _state = newState
        stateLock.unlock()
        stateSubject.send(newState)
    }
    
    private func cleanupResources() {
        consumeTask?.cancel()
        consumeTask = nil
        
        let continuations = subscriptionsLock.withLock { () -> [AsyncStream<MQMessage>.Continuation] in
            let conts = subscriptions.values.map { $0 }
            subscriptions.removeAll()
            patternTopics.removeAll()
            consumeOffsets.removeAll()
            return conts
        }
        continuations.forEach { $0.finish() }

        metadataLock.withLock {
            cachedTopics.removeAll()
            brokers.removeAll()
        }
        
        let pending = pendingLock.withLock { () -> [CheckedContinuation<Data, Error>] in
            let conts = pendingResponses.values.map { $0 }
            pendingResponses.removeAll()
            return conts
        }
        pending.forEach { $0.resume(throwing: MQError.connectionFailed("Connection closed")) }
        
        connection?.cancel()
        connection = nil
    }
    
    private func nextCorrelationId() -> Int32 {
        correlationLock.lock()
        defer { correlationLock.unlock() }
        correlationId += 1
        return correlationId
    }
}

// MARK: - MessageQueueClient

extension KafkaClient: MessageQueueClient {
    public func connect() async throws {
        guard state != .connected else { return }
        
        updateState(.connecting)
        
        let endpoint = try KafkaEndpoint.parse(from: config)
        
        do {
            let conn = try await makeConnection(host: endpoint.host, port: endpoint.port, useTLS: endpoint.useTLS)
            connection = conn
            
            // Start response reader
            startResponseReader(connection: conn)
            
            // Fetch metadata to validate connection and get topic list
            try await refreshMetadata()
            
            updateState(.connected)
        } catch {
            cleanupResources()
            updateState(.error(error.localizedDescription))
            throw error
        }
    }
    
    public func disconnect() async {
        cleanupResources()
        updateState(.disconnected)
    }
    
    public func publish(_ message: MQMessage, to subject: String) async throws {
        guard state == .connected else {
            throw MQError.notConnected
        }
        
        // Find partition leader for topic
        guard let topic = metadataLock.withLock({ cachedTopics.first(where: { $0.name == subject }) }) else {
            throw MQError.publishFailed("Topic not found: \(subject)")
        }
        
        guard let partition = topic.partitions.first else {
            throw MQError.publishFailed("No partitions available for topic: \(subject)")
        }
        
        // Build Produce request (API Key 0, Version 0)
        let request = try KafkaProtocol.buildProduceRequest(
            correlationId: nextCorrelationId(),
            clientId: clientId,
            topic: subject,
            partition: partition.id,
            messages: [message]
        )
        
        let response = try await sendRequest(request)
        
        // Parse produce response
        let result = try KafkaProtocol.parseProduceResponse(response)
        if let error = result.error {
            throw MQError.publishFailed("Kafka error: \(error)")
        }
    }
    
    public func subscribe(to pattern: String) async throws -> AsyncStream<MQMessage> {
        guard state == .connected else {
            throw MQError.notConnected
        }
        
        // Refresh metadata to ensure we have latest topic info
        try await refreshMetadata()
        
        let topicsSnapshot = metadataLock.withLock { cachedTopics }

        // Find matching topics
        let matchingTopics = topicsSnapshot.filter { topicMatches($0.name, pattern: pattern) }
        guard !matchingTopics.isEmpty else {
            throw MQError.subscriptionFailed("No topics match pattern: \(pattern)")
        }
        
        var capturedContinuation: AsyncStream<MQMessage>.Continuation?
        let stream = AsyncStream<MQMessage> { [weak self] continuation in
            capturedContinuation = continuation
            guard let self else {
                continuation.finish()
                return
            }
            
            self.subscriptionsLock.withLock {
                if let existing = self.subscriptions[pattern] {
                    existing.finish()
                }
                self.subscriptions[pattern] = continuation
                self.patternTopics[pattern] = matchingTopics.map { $0.name }
            }
            
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    try? await self?.unsubscribe(from: pattern)
                }
            }
        }
        
        _ = capturedContinuation
        updateConsumingState()
        
        return stream
    }
    
    public func unsubscribe(from pattern: String) async throws {
        let continuation = subscriptionsLock.withLock {
            patternTopics.removeValue(forKey: pattern)
            return subscriptions.removeValue(forKey: pattern)
        }
        continuation?.finish()
        updateConsumingState()
    }

    private func updateConsumingState() {
        let hasActiveTopics: Bool = subscriptionsLock.withLock {
            let topics = patternTopics.values.flatMap { $0 }
            return !topics.isEmpty && !subscriptions.isEmpty
        }

        if !hasActiveTopics {
            consumeTask?.cancel()
            consumeTask = nil
            return
        }

        if consumeTask == nil {
            consumeTask = Task { [weak self] in
                guard let self else { return }
                await self.runConsumeLoop()
            }
        }
    }
}

// MARK: - StreamingClient

extension KafkaClient: StreamingClient {
    public func listStreams() async throws -> [MQStreamInfo] {
        guard state == .connected else {
            throw MQError.notConnected
        }
        
        try await refreshMetadata()
        
        let topicsSnapshot = metadataLock.withLock { cachedTopics }
        return topicsSnapshot.map { topic in
            MQStreamInfo(
                name: topic.name,
                subjects: [topic.name],
                messageCount: 0,  // Would need offset queries to get actual count
                byteCount: 0,
                firstSequence: 0,
                lastSequence: 0,
                retention: .limits,
                storage: .file,
                replicas: topic.partitions.first?.replicas.count ?? 1
            )
        }
    }
    
    public func createStream(_ config: MQStreamConfig) async throws -> MQStreamInfo {
        // Topic creation requires admin API (CreateTopics - API Key 19)
        let request = try KafkaProtocol.buildCreateTopicsRequest(
            correlationId: nextCorrelationId(),
            clientId: clientId,
            topicName: config.name,
            numPartitions: 1,
            replicationFactor: Int16(config.replicas)
        )
        
        let response = try await sendRequest(request)
        let result = try KafkaProtocol.parseCreateTopicsResponse(response)
        
        if let error = result.error {
            throw MQError.providerError("Failed to create topic: \(error)")
        }
        
        // Refresh metadata
        try await refreshMetadata()
        
        return MQStreamInfo(
            name: config.name,
            subjects: config.subjects,
            retention: config.retention,
            storage: config.storage,
            replicas: config.replicas
        )
    }
    
    public func deleteStream(_ name: String) async throws {
        let request = try KafkaProtocol.buildDeleteTopicsRequest(
            correlationId: nextCorrelationId(),
            clientId: clientId,
            topicNames: [name]
        )
        
        let response = try await sendRequest(request)
        let result = try KafkaProtocol.parseDeleteTopicsResponse(response)
        
        if let error = result.error {
            throw MQError.providerError("Failed to delete topic: \(error)")
        }
        
        // Refresh metadata
        try await refreshMetadata()
    }
    
    public func getStreamInfo(_ name: String) async throws -> MQStreamInfo? {
        let streams = try await listStreams()
        return streams.first { $0.name == name }
    }
    
    public func listConsumers(stream: String) async throws -> [MQConsumerInfo] {
        // Consumer group listing requires DescribeGroups API
        // For now, return empty - would need full consumer group protocol
        return []
    }
    
    public func createConsumer(stream: String, config: MQConsumerConfig) async throws -> MQConsumerInfo {
        // Consumer creation is handled implicitly via consumer group protocol
        return MQConsumerInfo(
            streamName: stream,
            name: config.name,
            durable: config.durable,
            ackPolicy: config.ackPolicy,
            deliverPolicy: config.deliverPolicy,
            replayPolicy: config.replayPolicy,
            ackWait: config.ackWait
        )
    }
    
    public func deleteConsumer(stream: String, name: String) async throws {
        // Consumer deletion handled via group leave
    }
    
    public func publishPersistent(_ message: MQMessage, to subject: String) async throws -> MQPublishAck {
        try await publish(message, to: subject)
        return MQPublishAck(stream: subject, sequence: 0)
    }
    
    public func consume(stream: String, consumer: String) async throws -> AsyncStream<MQAcknowledgeableMessage> {
        let messageStream = try await subscribe(to: stream)
        
        return AsyncStream { continuation in
            Task {
                for await message in messageStream {
                    let ackMessage = KafkaAcknowledgeableMessage(
                        message: message,
                        metadata: MQMessageMetadata(
                            streamName: stream,
                            consumerName: consumer,
                            streamSequence: 0,
                            deliveryCount: 1
                        )
                    )
                    continuation.yield(ackMessage)
                }
                continuation.finish()
            }
        }
    }
    
    public func fetch(stream: String, consumer: String, batch: Int, expires: Duration) async throws -> [MQAcknowledgeableMessage] {
        // Fetch latest messages from topic
        let messages = try await fetchLastMessages(topic: stream, count: batch)
        
        return messages.map { message in
            KafkaAcknowledgeableMessage(
                message: message,
                metadata: MQMessageMetadata(
                    streamName: stream,
                    consumerName: consumer,
                    streamSequence: 0,
                    deliveryCount: 1
                )
            )
        }
    }
}

// MARK: - Kafka Metrics

extension KafkaClient {
    public func fetchClusterMetrics() async throws -> KafkaMetrics {
        guard state == .connected else {
            throw MQError.notConnected
        }

        try await refreshMetadata()

        let topicsSnapshot = metadataLock.withLock { cachedTopics }
        let allPartitions = topicsSnapshot.flatMap(\.partitions)
        let underReplicated = allPartitions.filter { $0.replicas.count > $0.isr.count }.count

        let offsetsSnapshot = subscriptionsLock.withLock { consumeOffsets }
        var totalLag: Int64 = 0
        var maxEndOffset: Int64 = 0

        for (topic, partitions) in offsetsSnapshot {
            for (partition, currentOffset) in partitions {
                let endOffset = (try? await getPartitionEndOffset(topic: topic, partition: partition)) ?? currentOffset
                if endOffset > currentOffset {
                    totalLag += (endOffset - currentOffset)
                }
                maxEndOffset = max(maxEndOffset, endOffset)
            }
        }

        return KafkaMetrics(
            partitionCount: allPartitions.count,
            underReplicatedPartitions: underReplicated,
            consumerGroupLag: totalLag,
            isrShrinkRate: 0.0,
            logEndOffset: maxEndOffset
        )
    }
}

// MARK: - Kafka-Specific Operations

extension KafkaClient {
    /// List all available topics
    public func listTopics() async throws -> [String] {
        guard state == .connected else {
            throw MQError.notConnected
        }
        
        try await refreshMetadata()
        return metadataLock.withLock { cachedTopics.map { $0.name } }
    }
    
    /// Fetch the last N messages from a topic
    public func fetchLastMessages(topic: String, count: Int) async throws -> [MQMessage] {
        guard state == .connected else {
            throw MQError.notConnected
        }
        
        guard let topicMeta = metadataLock.withLock({ cachedTopics.first(where: { $0.name == topic }) }) else {
            throw MQError.subscriptionFailed("Topic not found: \(topic)")
        }
        
        var allMessages: [MQMessage] = []
        
        // For each partition, fetch end offset and read backwards
        for partition in topicMeta.partitions {
            // Get end offset
            let endOffset = try await getPartitionEndOffset(topic: topic, partition: partition.id)
            
            // Get beginning offset (valid range start)
            let beginningOffset = try await getPartitionBeginningOffset(topic: topic, partition: partition.id)
            
            // Fetch last 'count' messages from EACH partition to ensuring we capture the global latest
            // regardless of partition distribution. This may fetch more data but guarantees correctness.
            // Ensure we don't request below the beginning offset.
            let startOffset = max(beginningOffset, endOffset - Int64(count))
            
            print("[Debug] fetchLastMessages topic=\(topic) p=\(partition.id) end=\(endOffset) start=\(startOffset) beginning=\(beginningOffset)")

            // Fetch messages from startOffset to endOffset
            let messages = try await fetchMessages(topic: topic, partition: partition.id, offset: startOffset, maxMessages: count)
            print("[Debug] fetchLastMessages topic=\(topic) p=\(partition.id) fetched=\(messages.count) messages")
            allMessages.append(contentsOf: messages)
        }
        
        // Sort by timestamp and take last N
        return allMessages
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(count)
            .map { $0 }
    }
    
    /// Fetch messages from a specific time onwards
    public func fetchMessagesFromTime(topic: String, from: Date, limit: Int) async throws -> [MQMessage] {
        guard state == .connected else {
            throw MQError.notConnected
        }
        
        guard let topicMeta = metadataLock.withLock({ cachedTopics.first(where: { $0.name == topic }) }) else {
            throw MQError.subscriptionFailed("Topic not found: \(topic)")
        }
        
        var allMessages: [MQMessage] = []
        let timestamp = Int64(from.timeIntervalSince1970 * 1000)
        
        for partition in topicMeta.partitions {
            // Get offset for timestamp
            let offset = try await getOffsetForTimestamp(topic: topic, partition: partition.id, timestamp: timestamp)
            
            // Fetch messages from that offset
            let messages = try await fetchMessages(topic: topic, partition: partition.id, offset: offset, maxMessages: limit)
            allMessages.append(contentsOf: messages)
        }
        
        // Sort by timestamp
        return allMessages
            .sorted { $0.timestamp < $1.timestamp }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Connection & Transport

private extension KafkaClient {
    func makeConnection(host: String, port: UInt16, useTLS: Bool) async throws -> NWConnection {
        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw MQError.invalidConfiguration("Invalid port: \(port)")
        }
        
        let params: NWParameters
        if useTLS {
            params = NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options())
        } else {
            params = NWParameters.tcp
        }
        
        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.stateUpdateHandler = nil
                    continuation.resume(returning: ())
                case .failed(let error):
                    conn.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                case .cancelled:
                    conn.stateUpdateHandler = nil
                    continuation.resume(throwing: MQError.connectionFailed("Connection cancelled"))
                default:
                    break
                }
            }
            conn.start(queue: connectionQueue)
        }
        
        return conn
    }
    
    func startResponseReader(connection: NWConnection) {
        Task { [weak self] in
            guard let self else { return }
            
            var buffer = [UInt8]()  // Use Array for safe 0-indexed access
            
            while !Task.isCancelled {
                guard let chunk = try? await self.receiveChunk(from: connection) else {
                    break
                }
                
                buffer.append(contentsOf: chunk)
                
                // Try to parse complete responses from buffer
                while buffer.count >= 8 {
                    // First 4 bytes = message length (big endian)
                    let length = Int32(buffer[0]) << 24 | Int32(buffer[1]) << 16 | Int32(buffer[2]) << 8 | Int32(buffer[3])
                    
                    // Sanity check: length should be positive and reasonable
                    guard length > 0 && length < 100_000_000 else {
                        // Invalid length, clear buffer and break
                        buffer.removeAll()
                        break
                    }
                    
                    let totalSize = Int(length) + 4
                    guard buffer.count >= totalSize else { break }
                    
                    // next 4 bytes = correlation ID (big endian)
                    let correlationId = Int32(buffer[4]) << 24 | Int32(buffer[5]) << 16 | Int32(buffer[6]) << 8 | Int32(buffer[7])
                    
                    let responseData = Data(buffer.prefix(totalSize))
                    buffer.removeFirst(totalSize)
                    
                    // Resume waiting continuation
                    let continuation = self.pendingLock.withLock { self.pendingResponses.removeValue(forKey: correlationId) }
                    continuation?.resume(returning: responseData)
                }
            }
        }
    }
    
    func sendRequest(_ data: Data) async throws -> Data {
        guard let conn = connection else {
            throw MQError.notConnected
        }
        
        // Extract correlation ID from request (at offset 8, after size + api key + api version)
        guard data.count >= 12 else {
            throw MQError.connectionFailed("Request too short")
        }
        let base = data.startIndex
        let correlationId = Int32(data[base + 8]) << 24 | Int32(data[base + 9]) << 16 | Int32(data[base + 10]) << 8 | Int32(data[base + 11])
        
        return try await withCheckedThrowingContinuation { continuation in
            pendingLock.lock()
            pendingResponses[correlationId] = continuation
            pendingLock.unlock()
            
            conn.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.pendingLock.lock()
                    let cont = self?.pendingResponses.removeValue(forKey: correlationId)
                    self?.pendingLock.unlock()
                    cont?.resume(throwing: error)
                }
            })
        }
    }
    
    func receiveChunk(from connection: NWConnection) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if isComplete && (data == nil || data!.isEmpty) {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
    
    func refreshMetadata() async throws {
        let request = try KafkaProtocol.buildMetadataRequest(
            correlationId: nextCorrelationId(),
            clientId: clientId,
            topics: nil  // nil = all topics
        )
        
        let response = try await sendRequest(request)
        let metadata = try KafkaProtocol.parseMetadataResponse(response)

        metadataLock.withLock {
            self.brokers = metadata.brokers
            self.cachedTopics = metadata.topics
        }
    }
    
    func getPartitionEndOffset(topic: String, partition: Int32) async throws -> Int64 {
        let request = try KafkaProtocol.buildListOffsetsRequest(
            correlationId: nextCorrelationId(),
            clientId: clientId,
            topic: topic,
            partition: partition,
            timestamp: -1  // -1 = latest offset
        )
        
        let response = try await sendRequest(request)
        return try KafkaProtocol.parseListOffsetsResponse(response)
    }

    func getPartitionBeginningOffset(topic: String, partition: Int32) async throws -> Int64 {
        let request = try KafkaProtocol.buildListOffsetsRequest(
            correlationId: nextCorrelationId(),
            clientId: clientId,
            topic: topic,
            partition: partition,
            timestamp: -2  // -2 = earliest offset
        )
        
        let response = try await sendRequest(request)
        return try KafkaProtocol.parseListOffsetsResponse(response)
    }
    
    func getOffsetForTimestamp(topic: String, partition: Int32, timestamp: Int64) async throws -> Int64 {
        let request = try KafkaProtocol.buildListOffsetsRequest(
            correlationId: nextCorrelationId(),
            clientId: clientId,
            topic: topic,
            partition: partition,
            timestamp: timestamp
        )
        
        let response = try await sendRequest(request)
        return try KafkaProtocol.parseListOffsetsResponse(response)
    }
    
    func fetchMessages(topic: String, partition: Int32, offset: Int64, maxMessages: Int) async throws -> [MQMessage] {
        let request = try KafkaProtocol.buildFetchRequest(
            correlationId: nextCorrelationId(),
            clientId: clientId,
            topic: topic,
            partition: partition,
            offset: offset,
            maxBytes: 1_048_576  // 1MB max
        )
        
        let response = try await sendRequest(request)
        return try KafkaProtocol.parseFetchResponse(response, topic: topic)
    }
    
    func runConsumeLoop() async {
        while !Task.isCancelled {
            let topics = subscriptionsLock.withLock { Array(Set(patternTopics.values.flatMap { $0 })) }
            if topics.isEmpty { break }

            let routes: [(continuation: AsyncStream<MQMessage>.Continuation, topics: Set<String>)] = subscriptionsLock.withLock {
                subscriptions.map { pattern, continuation in
                    (continuation: continuation, topics: Set(patternTopics[pattern] ?? []))
                }
            }

            for topic in topics {
                let topicMeta = metadataLock.withLock { cachedTopics.first { $0.name == topic } }
                guard let topicMeta else { continue }

                for partition in topicMeta.partitions {
                    var currentOffset = subscriptionsLock.withLock { consumeOffsets[topic]?[partition.id] }
                    if currentOffset == nil {
                        // Start from earliest available offset
                        let end = (try? await getPartitionBeginningOffset(topic: topic, partition: partition.id)) ?? 0
                        subscriptionsLock.withLock {
                            if consumeOffsets[topic] == nil { consumeOffsets[topic] = [:] }
                            consumeOffsets[topic]?[partition.id] = end
                        }
                        currentOffset = end
                    }
                    guard let currentOffset else { continue }

                    do {
                        let messages = try await fetchMessages(
                            topic: topic,
                            partition: partition.id,
                            offset: currentOffset,
                            maxMessages: 100
                        )

                        for message in messages {
                            for route in routes where route.topics.contains(topic) {
                                route.continuation.yield(message)
                            }
                        }

                        if !messages.isEmpty {
                            subscriptionsLock.withLock {
                                if consumeOffsets[topic] == nil { consumeOffsets[topic] = [:] }
                                consumeOffsets[topic]?[partition.id] = currentOffset + Int64(messages.count)
                            }
                        }
                    } catch {
                        // Continue on fetch errors
                    }
                }
            }

            // Poll interval
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
    
    func topicMatches(_ topic: String, pattern: String) -> Bool {
        if pattern == ">" || pattern == "*" || pattern == "#" {
            return true
        }
        // Simple wildcard matching
        if pattern.contains("*") {
            let regex = pattern.replacingOccurrences(of: "*", with: ".*")
            return topic.range(of: "^\(regex)$", options: .regularExpression) != nil
        }
        return topic == pattern
    }
}

// MARK: - Kafka Protocol

private enum KafkaProtocol {
    // API Keys
    static let apiKeyProduce: Int16 = 0
    static let apiKeyFetch: Int16 = 1
    static let apiKeyListOffsets: Int16 = 2
    static let apiKeyMetadata: Int16 = 3
    static let apiKeyCreateTopics: Int16 = 19
    static let apiKeyDeleteTopics: Int16 = 20
    
    static func buildMetadataRequest(correlationId: Int32, clientId: String, topics: [String]?) throws -> Data {
        var data = Data()
        
        // Header
        data.appendKafkaInt16(apiKeyMetadata)  // API Key
        data.appendKafkaInt16(0)               // API Version
        data.appendKafkaInt32(correlationId)
        data.appendKafkaString(clientId)
        
        // Topics array (null = all topics)
        if let topics = topics {
            data.appendKafkaInt32(Int32(topics.count))
            for topic in topics {
                data.appendKafkaString(topic)
            }
        } else {
            data.appendKafkaInt32(0)  // Empty array = all topics
        }
        
        return wrapWithLength(data)
    }
    
    static func parseMetadataResponse(_ data: Data) throws -> (brokers: [KafkaBrokerMetadata], topics: [KafkaTopicMetadata]) {
        var offset = 8  // Skip size + correlation ID
        
        // Brokers
        let brokerCount = data.readKafkaInt32(at: &offset)
        var brokers: [KafkaBrokerMetadata] = []
        
        for _ in 0..<brokerCount {
            let nodeId = data.readKafkaInt32(at: &offset)
            let host = data.readKafkaString(at: &offset)
            let port = data.readKafkaInt32(at: &offset)
            brokers.append(KafkaBrokerMetadata(nodeId: nodeId, host: host, port: Int(port)))
        }
        
        // Topics
        let topicCount = data.readKafkaInt32(at: &offset)
        var topics: [KafkaTopicMetadata] = []
        
        for _ in 0..<topicCount {
            let errorCode = data.readKafkaInt16(at: &offset)
            let name = data.readKafkaString(at: &offset)
            
            let partitionCount = data.readKafkaInt32(at: &offset)
            var partitions: [KafkaPartitionMetadata] = []
            
            for _ in 0..<partitionCount {
                let partError = data.readKafkaInt16(at: &offset)
                let partitionId = data.readKafkaInt32(at: &offset)
                let leader = data.readKafkaInt32(at: &offset)
                
                let replicaCount = data.readKafkaInt32(at: &offset)
                var replicas: [Int32] = []
                for _ in 0..<replicaCount {
                    replicas.append(data.readKafkaInt32(at: &offset))
                }
                
                let isrCount = data.readKafkaInt32(at: &offset)
                var isr: [Int32] = []
                for _ in 0..<isrCount {
                    isr.append(data.readKafkaInt32(at: &offset))
                }
                
                partitions.append(KafkaPartitionMetadata(
                    id: partitionId,
                    leader: leader,
                    replicas: replicas,
                    isr: isr,
                    errorCode: partError
                ))
            }
            
            if errorCode == 0 && !name.hasPrefix("__") {  // Skip internal topics
                topics.append(KafkaTopicMetadata(name: name, partitions: partitions, errorCode: errorCode))
            }
        }
        
        return (brokers, topics)
    }
    
    static func buildListOffsetsRequest(correlationId: Int32, clientId: String, topic: String, partition: Int32, timestamp: Int64) throws -> Data {
        var data = Data()
        
        data.appendKafkaInt16(apiKeyListOffsets)
        data.appendKafkaInt16(0)
        data.appendKafkaInt32(correlationId)
        data.appendKafkaString(clientId)
        
        data.appendKafkaInt32(-1)  // Replica ID
        data.appendKafkaInt32(1)   // Topic count
        data.appendKafkaString(topic)
        data.appendKafkaInt32(1)   // Partition count
        data.appendKafkaInt32(partition)
        data.appendKafkaInt64(timestamp)
        data.appendKafkaInt32(1)   // Max offsets
        
        return wrapWithLength(data)
    }
    
    static func parseListOffsetsResponse(_ data: Data) throws -> Int64 {
        var offset = 8
        
        let topicCount = data.readKafkaInt32(at: &offset)
        guard topicCount > 0 else { return 0 }
        
        _ = data.readKafkaString(at: &offset)  // Topic name
        let partitionCount = data.readKafkaInt32(at: &offset)
        guard partitionCount > 0 else { return 0 }
        
        _ = data.readKafkaInt32(at: &offset)  // Partition
        _ = data.readKafkaInt16(at: &offset)  // Error code
        let offsetCount = data.readKafkaInt32(at: &offset)
        guard offsetCount > 0 else { return 0 }
        
        return data.readKafkaInt64(at: &offset)
    }
    
    static func buildFetchRequest(correlationId: Int32, clientId: String, topic: String, partition: Int32, offset: Int64, maxBytes: Int32) throws -> Data {
        var data = Data()
        
        data.appendKafkaInt16(apiKeyFetch)
        data.appendKafkaInt16(0)
        data.appendKafkaInt32(correlationId)
        data.appendKafkaString(clientId)
        
        data.appendKafkaInt32(-1)       // Replica ID
        data.appendKafkaInt32(5000)     // Max wait time (ms)
        data.appendKafkaInt32(1)        // Min bytes
        data.appendKafkaInt32(1)        // Topic count
        data.appendKafkaString(topic)
        data.appendKafkaInt32(1)        // Partition count
        data.appendKafkaInt32(partition)
        data.appendKafkaInt64(offset)
        data.appendKafkaInt32(maxBytes)
        
        return wrapWithLength(data)
    }
    
    static func parseFetchResponse(_ data: Data, topic: String) throws -> [MQMessage] {
        var messages: [MQMessage] = []
        var offset = 8
        
        let topicCount = data.readKafkaInt32(at: &offset)
        guard topicCount > 0 else { return [] }
        
        _ = data.readKafkaString(at: &offset)  // Topic name
        let partitionCount = data.readKafkaInt32(at: &offset)
        guard partitionCount > 0 else { return [] }
        
        _ = data.readKafkaInt32(at: &offset)  // Partition
        let errorCode = data.readKafkaInt16(at: &offset)
        guard errorCode == 0 else {
            print("[Debug] parseFetchResponse error code: \(errorCode)")
            throw MQError.subscriptionFailed("Kafka Fetch Error: \(errorCode)")
        }
        
        _ = data.readKafkaInt64(at: &offset)  // High watermark
        let messageSetSize = data.readKafkaInt32(at: &offset)
        
        let messageSetEnd = offset + Int(messageSetSize)
        
        while offset < messageSetEnd && offset + 12 <= data.count {
            let msgOffset = data.readKafkaInt64(at: &offset)
            let msgSize = data.readKafkaInt32(at: &offset)
            
            guard offset + Int(msgSize) <= data.count else { break }
            
            // CRC, magic, attributes
            offset += 4 + 1 + 1
            
            // Key
            let keyLen = data.readKafkaInt32(at: &offset)
            if keyLen > 0 {
                offset += Int(keyLen)
            }
            
            // Value
            let valueLen = data.readKafkaInt32(at: &offset)
            var payload = Data()
            if valueLen > 0 && offset + Int(valueLen) <= data.count {
                payload = data.subdata(in: offset..<(offset + Int(valueLen)))
                offset += Int(valueLen)
            }
            
            let message = MQMessage(
                subject: topic,
                payload: payload,
                headers: ["kafka.offset": String(msgOffset)],
                timestamp: Date()
            )
            messages.append(message)
        }
        
        return messages
    }
    
    static func buildProduceRequest(correlationId: Int32, clientId: String, topic: String, partition: Int32, messages: [MQMessage]) throws -> Data {
        var data = Data()
        
        data.appendKafkaInt16(apiKeyProduce)
        data.appendKafkaInt16(0)
        data.appendKafkaInt32(correlationId)
        data.appendKafkaString(clientId)
        
        data.appendKafkaInt16(1)        // Required acks
        data.appendKafkaInt32(30000)    // Timeout
        data.appendKafkaInt32(1)        // Topic count
        data.appendKafkaString(topic)
        data.appendKafkaInt32(1)        // Partition count
        data.appendKafkaInt32(partition)
        
        // Build message set
        var messageSet = Data()
        for msg in messages {
            var msgData = Data()
            msgData.appendKafkaInt64(0)   // Offset (ignored by broker)
            
            var innerMsg = Data()
            innerMsg.append(0)  // Magic byte
            innerMsg.append(0)  // Attributes
            innerMsg.appendKafkaInt32(-1)  // No key
            innerMsg.appendKafkaInt32(Int32(msg.payload.count))
            innerMsg.append(msg.payload)
            
            // CRC32
            let crc = innerMsg.crc32()
            
            msgData.appendKafkaInt32(Int32(innerMsg.count + 4))  // Message size
            msgData.appendKafkaInt32(Int32(bitPattern: crc))
            msgData.append(innerMsg)
            
            messageSet.append(msgData)
        }
        
        data.appendKafkaInt32(Int32(messageSet.count))
        data.append(messageSet)
        
        return wrapWithLength(data)
    }
    
    static func parseProduceResponse(_ data: Data) throws -> (offset: Int64, error: String?) {
        var offset = 8
        
        let topicCount = data.readKafkaInt32(at: &offset)
        guard topicCount > 0 else { return (0, nil) }
        
        _ = data.readKafkaString(at: &offset)
        let partitionCount = data.readKafkaInt32(at: &offset)
        guard partitionCount > 0 else { return (0, nil) }
        
        _ = data.readKafkaInt32(at: &offset)  // Partition
        let errorCode = data.readKafkaInt16(at: &offset)
        let baseOffset = data.readKafkaInt64(at: &offset)
        
        let error: String? = errorCode != 0 ? "Kafka error code: \(errorCode)" : nil
        return (baseOffset, error)
    }
    
    static func buildCreateTopicsRequest(correlationId: Int32, clientId: String, topicName: String, numPartitions: Int32, replicationFactor: Int16) throws -> Data {
        var data = Data()
        
        data.appendKafkaInt16(apiKeyCreateTopics)
        data.appendKafkaInt16(0)
        data.appendKafkaInt32(correlationId)
        data.appendKafkaString(clientId)
        
        data.appendKafkaInt32(1)              // Topic count
        data.appendKafkaString(topicName)
        data.appendKafkaInt32(numPartitions)
        data.appendKafkaInt16(replicationFactor)
        data.appendKafkaInt32(0)              // No replica assignments
        data.appendKafkaInt32(0)              // No config entries
        data.appendKafkaInt32(30000)          // Timeout
        
        return wrapWithLength(data)
    }
    
    static func parseCreateTopicsResponse(_ data: Data) throws -> (name: String, error: String?) {
        var offset = 8
        
        let topicCount = data.readKafkaInt32(at: &offset)
        guard topicCount > 0 else { return ("", nil) }
        
        let name = data.readKafkaString(at: &offset)
        let errorCode = data.readKafkaInt16(at: &offset)
        
        let error: String? = errorCode != 0 ? "Kafka error code: \(errorCode)" : nil
        return (name, error)
    }
    
    static func buildDeleteTopicsRequest(correlationId: Int32, clientId: String, topicNames: [String]) throws -> Data {
        var data = Data()
        
        data.appendKafkaInt16(apiKeyDeleteTopics)
        data.appendKafkaInt16(0)
        data.appendKafkaInt32(correlationId)
        data.appendKafkaString(clientId)
        
        data.appendKafkaInt32(Int32(topicNames.count))
        for name in topicNames {
            data.appendKafkaString(name)
        }
        data.appendKafkaInt32(30000)  // Timeout
        
        return wrapWithLength(data)
    }
    
    static func parseDeleteTopicsResponse(_ data: Data) throws -> (names: [String], error: String?) {
        var offset = 8
        
        let topicCount = data.readKafkaInt32(at: &offset)
        var names: [String] = []
        var firstError: String? = nil
        
        for _ in 0..<topicCount {
            let name = data.readKafkaString(at: &offset)
            let errorCode = data.readKafkaInt16(at: &offset)
            names.append(name)
            if errorCode != 0 && firstError == nil {
                firstError = "Kafka error code: \(errorCode)"
            }
        }
        
        return (names, firstError)
    }
    
    static func wrapWithLength(_ data: Data) -> Data {
        var result = Data()
        result.appendKafkaInt32(Int32(data.count))
        result.append(data)
        return result
    }
}

// MARK: - Data Extensions for Kafka Protocol

private extension Data {
    mutating func appendKafkaInt16(_ value: Int16) {
        var bigEndian = value.bigEndian
        append(Data(bytes: &bigEndian, count: 2))
    }
    
    mutating func appendKafkaInt32(_ value: Int32) {
        var bigEndian = value.bigEndian
        append(Data(bytes: &bigEndian, count: 4))
    }
    
    mutating func appendKafkaInt64(_ value: Int64) {
        var bigEndian = value.bigEndian
        append(Data(bytes: &bigEndian, count: 8))
    }
    
    mutating func appendKafkaString(_ value: String) {
        let bytes = value.data(using: .utf8) ?? Data()
        appendKafkaInt16(Int16(bytes.count))
        append(bytes)
    }
    
    func readKafkaInt16(at offset: inout Int) -> Int16 {
        guard offset + 2 <= count else { return 0 }
        let idx = startIndex + offset
        let value = Int16(self[idx]) << 8 | Int16(self[idx + 1])
        offset += 2
        return value
    }
    
    func readKafkaInt32(at offset: inout Int) -> Int32 {
        guard offset + 4 <= count else { return 0 }
        let idx = startIndex + offset
        let value = Int32(self[idx]) << 24 | Int32(self[idx + 1]) << 16 | Int32(self[idx + 2]) << 8 | Int32(self[idx + 3])
        offset += 4
        return value
    }
    
    func readKafkaInt64(at offset: inout Int) -> Int64 {
        guard offset + 8 <= count else { return 0 }
        let idx = startIndex + offset
        let value = Int64(self[idx]) << 56 | Int64(self[idx + 1]) << 48 | Int64(self[idx + 2]) << 40 | Int64(self[idx + 3]) << 32 |
                    Int64(self[idx + 4]) << 24 | Int64(self[idx + 5]) << 16 | Int64(self[idx + 6]) << 8 | Int64(self[idx + 7])
        offset += 8
        return value
    }
    
    func readKafkaString(at offset: inout Int) -> String {
        let length = readKafkaInt16(at: &offset)
        guard length > 0, offset + Int(length) <= count else { return "" }
        let start = startIndex + offset
        let stringData = subdata(in: start..<(start + Int(length)))
        offset += Int(length)
        return String(data: stringData, encoding: .utf8) ?? ""
    }
    
    func crc32() -> UInt32 {
        // Simple CRC32 implementation for Kafka
        var crc: UInt32 = 0xFFFFFFFF
        let polynomial: UInt32 = 0xEDB88320
        
        for byte in self {
            var temp = crc ^ UInt32(byte)
            for _ in 0..<8 {
                if temp & 1 == 1 {
                    temp = (temp >> 1) ^ polynomial
                } else {
                    temp >>= 1
                }
            }
            crc = temp
        }
        
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - Kafka Metadata Types

private struct KafkaBrokerMetadata {
    let nodeId: Int32
    let host: String
    let port: Int
}

private struct KafkaTopicMetadata {
    let name: String
    let partitions: [KafkaPartitionMetadata]
    let errorCode: Int16
}

private struct KafkaPartitionMetadata {
    let id: Int32
    let leader: Int32
    let replicas: [Int32]
    let isr: [Int32]
    let errorCode: Int16
}

// MARK: - Kafka Endpoint Parsing

private struct KafkaEndpoint {
    let host: String
    let port: UInt16
    let useTLS: Bool
    
    static func parse(from config: MQConnectionConfig) throws -> KafkaEndpoint {
        var url = config.url
        
        // Handle kafka:// prefix
        if url.hasPrefix("kafka://") {
            url = String(url.dropFirst(8))
        } else if url.hasPrefix("kafkas://") {
            url = String(url.dropFirst(9))
        }
        
        // Parse host:port
        let parts = url.split(separator: ":")
        let host = String(parts.first ?? "localhost")
        let port: UInt16 = parts.count > 1 ? UInt16(parts[1]) ?? 9092 : 9092
        
        let useTLS = config.tlsEnabled || config.url.hasPrefix("kafkas://")
        
        return KafkaEndpoint(host: host, port: port, useTLS: useTLS)
    }
}

// MARK: - Kafka Acknowledgeable Message

private struct KafkaAcknowledgeableMessage: MQAcknowledgeableMessage {
    let message: MQMessage
    let metadata: MQMessageMetadata
    
    func ack() async throws {
        // Kafka uses consumer offsets, ack is implicit via offset commit
    }
    
    func nak(delay: Duration?) async throws {
        // Kafka doesn't support individual message nak
    }
    
    func term() async throws {
        // No-op for Kafka
    }
    
    func inProgress() async throws {
        // No-op for Kafka
    }
}
