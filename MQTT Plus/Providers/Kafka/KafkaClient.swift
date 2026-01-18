//
//  KafkaClient.swift
//  MQTT Plus
//

import Foundation
import Combine

public final class KafkaClient: @unchecked Sendable {
    public let config: MQConnectionConfig
    private let kafkaConfig: KafkaConfiguration
    
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
    
    private var producer: OpaquePointer?
    private var consumer: OpaquePointer?
    private let operationQueue = DispatchQueue(label: "KafkaClient.operations", attributes: .concurrent)
    
    private var subscriptions: [String: AsyncStream<MQMessage>.Continuation] = [:]
    private let subscriptionsLock = NSLock()
    private var consumeTask: Task<Void, Never>?
    
    private var cachedTopics: [String] = []
    private let metadataLock = NSLock()
    
    public init(config: MQConnectionConfig) {
        self.config = config
        
        if let optionsJSON = config.options["kafkaConfig"],
           let kafkaConf = KafkaConfiguration.fromJSON(optionsJSON) {
            self.kafkaConfig = kafkaConf
        } else {
            self.kafkaConfig = .default
        }
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
            return conts
        }
        continuations.forEach { $0.finish() }
        
        if let c = consumer {
            rd_kafka_consumer_close(c)
            rd_kafka_destroy(c)
            consumer = nil
        }
        
        if let p = producer {
            rd_kafka_flush(p, 5000)
            rd_kafka_destroy(p)
            producer = nil
        }
        
        metadataLock.withLock { cachedTopics.removeAll() }
    }
    
    private func createConfig() -> OpaquePointer? {
        guard let conf = rd_kafka_conf_new() else { return nil }
        
        var errstr = [CChar](repeating: 0, count: 512)
        
        func setConfig(_ key: String, _ value: String) -> Bool {
            let result = rd_kafka_conf_set(conf, key, value, &errstr, errstr.count)
            if result != RD_KAFKA_CONF_OK {
                print("[KafkaClient] Config error for \(key): \(String(cString: errstr))")
                return false
            }
            return true
        }
        
        _ = setConfig("bootstrap.servers", parseBootstrapServers())
        _ = setConfig("client.id", kafkaConfig.clientId)
        _ = setConfig("security.protocol", kafkaConfig.securityProtocol.rawValue)
        
        if kafkaConfig.securityProtocol.requiresSASL, let mechanism = kafkaConfig.saslMechanism {
            _ = setConfig("sasl.mechanism", mechanism.rawValue)
            
            switch mechanism {
            case .plain, .scramSHA256, .scramSHA512:
                if let username = config.username, !username.isEmpty {
                    _ = setConfig("sasl.username", username)
                }
                if let password = config.password, !password.isEmpty {
                    _ = setConfig("sasl.password", password)
                }
                
            case .oauthbearer:
                if let oauth = kafkaConfig.oauthConfig {
                    _ = setConfig("sasl.oauthbearer.method", "oidc")
                    _ = setConfig("sasl.oauthbearer.token.endpoint.url", oauth.tokenEndpoint)
                    _ = setConfig("sasl.oauthbearer.client.id", oauth.clientId)
                    _ = setConfig("sasl.oauthbearer.client.secret", oauth.clientSecret)
                    if let scope = oauth.scope, !scope.isEmpty {
                        _ = setConfig("sasl.oauthbearer.scope", scope)
                    }
                }
                
            case .gssapi:
                break
            }
        }
        
        if kafkaConfig.securityProtocol.requiresSSL {
            let sslConf = kafkaConfig.sslConfig
            
            if sslConf.enableHostnameVerification {
                _ = setConfig("ssl.endpoint.identification.algorithm", "https")
            } else {
                _ = setConfig("ssl.endpoint.identification.algorithm", "none")
            }
            
            if let ca = sslConf.caLocation, !ca.isEmpty {
                _ = setConfig("ssl.ca.location", ca)
            }
            if let cert = sslConf.certificateLocation, !cert.isEmpty {
                _ = setConfig("ssl.certificate.location", cert)
            }
            if let key = sslConf.keyLocation, !key.isEmpty {
                _ = setConfig("ssl.key.location", key)
            }
            if let keyPass = sslConf.keyPassword, !keyPass.isEmpty {
                _ = setConfig("ssl.key.password", keyPass)
            }
        }
        
        _ = setConfig("socket.connection.setup.timeout.ms", String(kafkaConfig.connectionTimeoutMs))
        _ = setConfig("metadata.max.age.ms", String(kafkaConfig.metadataMaxAgeMs))
        
        return conf
    }
    
    private func parseBootstrapServers() -> String {
        var url = config.url
        if url.hasPrefix("kafka://") {
            url = String(url.dropFirst(8))
        } else if url.hasPrefix("kafkas://") {
            url = String(url.dropFirst(9))
        }
        return url
    }
    
    private func createProducer() throws {
        guard let conf = createConfig() else {
            throw MQError.connectionFailed("Failed to create Kafka configuration")
        }
        
        let prodConf = kafkaConfig.producerConfig
        var errstr = [CChar](repeating: 0, count: 512)
        
        func setConfig(_ key: String, _ value: String) {
            rd_kafka_conf_set(conf, key, value, &errstr, errstr.count)
        }
        
        setConfig("acks", prodConf.acks.rawValue)
        setConfig("retries", String(prodConf.retries))
        setConfig("enable.idempotence", prodConf.enableIdempotence ? "true" : "false")
        setConfig("compression.type", prodConf.compressionType.rawValue)
        setConfig("linger.ms", String(prodConf.lingerMs))
        setConfig("batch.size", String(prodConf.batchSize))
        setConfig("delivery.timeout.ms", String(prodConf.deliveryTimeoutMs))
        setConfig("request.timeout.ms", String(prodConf.requestTimeoutMs))
        
        let prod = rd_kafka_new(RD_KAFKA_PRODUCER, conf, &errstr, errstr.count)
        guard let prod else {
            throw MQError.connectionFailed("Failed to create producer: \(String(cString: errstr))")
        }
        
        producer = prod
    }
    
    private func createConsumer() throws {
        guard let conf = createConfig() else {
            throw MQError.connectionFailed("Failed to create Kafka configuration")
        }
        
        let consConf = kafkaConfig.consumerConfig
        var errstr = [CChar](repeating: 0, count: 512)
        
        func setConfig(_ key: String, _ value: String) {
            rd_kafka_conf_set(conf, key, value, &errstr, errstr.count)
        }
        
        setConfig("group.id", consConf.groupId)
        setConfig("auto.offset.reset", consConf.autoOffsetReset.rawValue)
        setConfig("enable.auto.commit", consConf.enableAutoCommit ? "true" : "false")
        setConfig("auto.commit.interval.ms", String(consConf.autoCommitIntervalMs))
        setConfig("session.timeout.ms", String(consConf.sessionTimeoutMs))
        setConfig("heartbeat.interval.ms", String(consConf.heartbeatIntervalMs))
        setConfig("max.poll.interval.ms", String(consConf.maxPollIntervalMs))
        setConfig("fetch.min.bytes", String(consConf.fetchMinBytes))
        setConfig("fetch.max.bytes", String(consConf.fetchMaxBytes))
        
        let cons = rd_kafka_new(RD_KAFKA_CONSUMER, conf, &errstr, errstr.count)
        guard let cons else {
            throw MQError.connectionFailed("Failed to create consumer: \(String(cString: errstr))")
        }
        
        rd_kafka_poll_set_consumer(cons)
        consumer = cons
    }
    
    private func refreshMetadata() async throws {
        guard let prod = producer else { return }
        
        var metadata: UnsafePointer<rd_kafka_metadata>?
        let result = rd_kafka_metadata(prod, 1, nil, &metadata, 5000)
        
        guard result == RD_KAFKA_RESP_ERR_NO_ERROR, let meta = metadata else {
            throw MQError.connectionFailed("Failed to fetch metadata: \(String(cString: rd_kafka_err2str(result)))")
        }
        
        defer { rd_kafka_metadata_destroy(meta) }
        
        var topics: [String] = []
        for i in 0..<Int(meta.pointee.topic_cnt) {
            let topic = meta.pointee.topics[i]
            let name = String(cString: topic.topic)
            if !name.hasPrefix("__") {
                topics.append(name)
            }
        }
        
        metadataLock.withLock { cachedTopics = topics }
    }
}

extension KafkaClient: MessageQueueClient {
    public func connect() async throws {
        guard state != .connected else { return }
        
        updateState(.connecting)
        
        do {
            try createProducer()
            try createConsumer()
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
        guard state == .connected, let prod = producer else {
            throw MQError.notConnected
        }
        
        let topicPtr = rd_kafka_topic_new(prod, subject, nil)
        guard let topicPtr else {
            throw MQError.publishFailed("Failed to create topic handle")
        }
        defer { rd_kafka_topic_destroy(topicPtr) }
        
        let result = message.payload.withUnsafeBytes { payloadPtr -> Int32 in
            let payload = payloadPtr.baseAddress
            let len = payloadPtr.count
            
            return rd_kafka_produce(
                topicPtr,
                RD_KAFKA_PARTITION_UA,
                Int32(RD_KAFKA_MSG_F_COPY),
                UnsafeMutableRawPointer(mutating: payload),
                len,
                nil, 0,
                nil
            )
        }
        
        if result == -1 {
            let err = rd_kafka_last_error()
            throw MQError.publishFailed("Produce failed: \(String(cString: rd_kafka_err2str(err)))")
        }
        
        rd_kafka_poll(prod, 0)
    }
    
    public func subscribe(to pattern: String) async throws -> AsyncStream<MQMessage> {
        guard state == .connected, let cons = consumer else {
            throw MQError.notConnected
        }
        
        let topics = metadataLock.withLock { cachedTopics.filter { topicMatches($0, pattern: pattern) } }
        guard !topics.isEmpty else {
            throw MQError.subscriptionFailed("No topics match pattern: \(pattern)")
        }
        
        let topicList = rd_kafka_topic_partition_list_new(Int32(topics.count))
        defer { rd_kafka_topic_partition_list_destroy(topicList) }
        
        for topic in topics {
            rd_kafka_topic_partition_list_add(topicList, topic, RD_KAFKA_PARTITION_UA)
        }
        
        let result = rd_kafka_subscribe(cons, topicList)
        if result != RD_KAFKA_RESP_ERR_NO_ERROR {
            throw MQError.subscriptionFailed("Subscribe failed: \(String(cString: rd_kafka_err2str(result)))")
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
            }
            
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    try? await self?.unsubscribe(from: pattern)
                }
            }
        }
        
        _ = capturedContinuation
        startConsumeLoopIfNeeded()
        
        return stream
    }
    
    public func unsubscribe(from pattern: String) async throws {
        let continuation = subscriptionsLock.withLock { subscriptions.removeValue(forKey: pattern) }
        continuation?.finish()
        
        if subscriptionsLock.withLock({ subscriptions.isEmpty }) {
            consumeTask?.cancel()
            consumeTask = nil
            if let cons = consumer {
                rd_kafka_unsubscribe(cons)
            }
        }
    }
    
    private func startConsumeLoopIfNeeded() {
        guard consumeTask == nil else { return }
        
        consumeTask = Task { [weak self] in
            guard let self else { return }
            
            while !Task.isCancelled {
                guard let cons = self.consumer else { break }
                
                let msg = rd_kafka_consumer_poll(cons, 100)
                guard let msg else { continue }
                defer { rd_kafka_message_destroy(msg) }
                
                let msgRef = msg.pointee
                
                if msgRef.err != RD_KAFKA_RESP_ERR_NO_ERROR {
                    if msgRef.err != RD_KAFKA_RESP_ERR__PARTITION_EOF {
                        print("[KafkaClient] Consumer error: \(String(cString: rd_kafka_err2str(msgRef.err)))")
                    }
                    continue
                }
                
                let topic = String(cString: rd_kafka_topic_name(msgRef.rkt))
                var payload = Data()
                if let payloadPtr = msgRef.payload, msgRef.len > 0 {
                    payload = Data(bytes: payloadPtr, count: msgRef.len)
                }
                
                var headers: [String: String] = [
                    "kafka.partition": String(msgRef.partition),
                    "kafka.offset": String(msgRef.offset)
                ]
                
                var hdrsPtr: OpaquePointer?
                if rd_kafka_message_headers(msg, &hdrsPtr) == RD_KAFKA_RESP_ERR_NO_ERROR, let hdrs = hdrsPtr {
                    var idx: Int = 0
                    var name: UnsafePointer<CChar>?
                    var value: UnsafeRawPointer?
                    var valueSize: Int = 0
                    
                    while rd_kafka_header_get_all(hdrs, idx, &name, &value, &valueSize) == RD_KAFKA_RESP_ERR_NO_ERROR {
                        if let n = name {
                            let headerName = String(cString: n)
                            if let v = value, valueSize > 0 {
                                let headerValue = String(data: Data(bytes: v, count: valueSize), encoding: .utf8) ?? ""
                                headers[headerName] = headerValue
                            }
                        }
                        idx += 1
                    }
                }
                
                let message = MQMessage(
                    subject: topic,
                    payload: payload,
                    headers: headers,
                    timestamp: Date(timeIntervalSince1970: Double(msgRef.offset) / 1000.0)
                )
                
                let continuations = self.subscriptionsLock.withLock {
                    self.subscriptions.filter { self.topicMatches(topic, pattern: $0.key) }.values.map { $0 }
                }
                
                for continuation in continuations {
                    continuation.yield(message)
                }
            }
        }
    }
    
    private func topicMatches(_ topic: String, pattern: String) -> Bool {
        if pattern == ">" || pattern == "*" || pattern == "#" {
            return true
        }
        if pattern.contains("*") {
            let regex = pattern.replacingOccurrences(of: "*", with: ".*")
            return topic.range(of: "^\(regex)$", options: .regularExpression) != nil
        }
        return topic == pattern
    }
}

extension KafkaClient: StreamingClient {
    public func listStreams() async throws -> [MQStreamInfo] {
        guard state == .connected else {
            throw MQError.notConnected
        }
        
        try await refreshMetadata()
        
        return metadataLock.withLock {
            cachedTopics.map { topic in
                MQStreamInfo(
                    name: topic,
                    subjects: [topic],
                    messageCount: 0,
                    byteCount: 0,
                    firstSequence: 0,
                    lastSequence: 0,
                    retention: .limits,
                    storage: .file,
                    replicas: 1
                )
            }
        }
    }
    
    public func createStream(_ streamConfig: MQStreamConfig) async throws -> MQStreamInfo {
        guard state == .connected, let prod = producer else {
            throw MQError.notConnected
        }
        
        let newTopic = rd_kafka_NewTopic_new(streamConfig.name, 1, 1, nil, 0)
        guard let newTopic else {
            throw MQError.providerError("Failed to create NewTopic object")
        }
        defer { rd_kafka_NewTopic_destroy(newTopic) }
        
        var topics: [OpaquePointer?] = [newTopic]
        let adminOptions = rd_kafka_AdminOptions_new(prod, RD_KAFKA_ADMIN_OP_CREATETOPICS)
        defer { rd_kafka_AdminOptions_destroy(adminOptions) }
        
        let queue = rd_kafka_queue_new(prod)
        defer { rd_kafka_queue_destroy(queue) }
        
        rd_kafka_CreateTopics(prod, &topics, 1, adminOptions, queue)
        
        let event = rd_kafka_queue_poll(queue, 10000)
        defer { if let e = event { rd_kafka_event_destroy(e) } }
        
        if let event, rd_kafka_event_type(event) == RD_KAFKA_EVENT_CREATETOPICS_RESULT {
            let result = rd_kafka_event_CreateTopics_result(event)
            var cnt: Int = 0
            let topicResults = rd_kafka_CreateTopics_result_topics(result, &cnt)
            
            if cnt > 0, let topicResults {
                let err = rd_kafka_topic_result_error(topicResults[0])
                if err != RD_KAFKA_RESP_ERR_NO_ERROR {
                    let errStr = String(cString: rd_kafka_topic_result_error_string(topicResults[0]) ?? rd_kafka_err2str(err))
                    throw MQError.providerError("Failed to create topic: \(errStr)")
                }
            }
        }
        
        try await refreshMetadata()
        
        return MQStreamInfo(
            name: streamConfig.name,
            subjects: streamConfig.subjects,
            retention: streamConfig.retention,
            storage: streamConfig.storage,
            replicas: streamConfig.replicas
        )
    }
    
    public func deleteStream(_ name: String) async throws {
        guard state == .connected, let prod = producer else {
            throw MQError.notConnected
        }
        
        let deleteTopic = rd_kafka_DeleteTopic_new(name)
        defer { rd_kafka_DeleteTopic_destroy(deleteTopic) }
        
        var topics: [OpaquePointer?] = [deleteTopic]
        let adminOptions = rd_kafka_AdminOptions_new(prod, RD_KAFKA_ADMIN_OP_DELETETOPICS)
        defer { rd_kafka_AdminOptions_destroy(adminOptions) }
        
        let queue = rd_kafka_queue_new(prod)
        defer { rd_kafka_queue_destroy(queue) }
        
        rd_kafka_DeleteTopics(prod, &topics, 1, adminOptions, queue)
        
        let event = rd_kafka_queue_poll(queue, 10000)
        defer { if let e = event { rd_kafka_event_destroy(e) } }
        
        if let event, rd_kafka_event_type(event) == RD_KAFKA_EVENT_DELETETOPICS_RESULT {
            let result = rd_kafka_event_DeleteTopics_result(event)
            var cnt: Int = 0
            let topicResults = rd_kafka_DeleteTopics_result_topics(result, &cnt)
            
            if cnt > 0, let topicResults {
                let err = rd_kafka_topic_result_error(topicResults[0])
                if err != RD_KAFKA_RESP_ERR_NO_ERROR {
                    let errStr = String(cString: rd_kafka_topic_result_error_string(topicResults[0]) ?? rd_kafka_err2str(err))
                    throw MQError.providerError("Failed to delete topic: \(errStr)")
                }
            }
        }
        
        try await refreshMetadata()
    }
    
    public func getStreamInfo(_ name: String) async throws -> MQStreamInfo? {
        let streams = try await listStreams()
        return streams.first { $0.name == name }
    }
    
    public func listConsumers(stream: String) async throws -> [MQConsumerInfo] {
        return []
    }
    
    public func createConsumer(stream: String, config: MQConsumerConfig) async throws -> MQConsumerInfo {
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
    
    public func deleteConsumer(stream: String, name: String) async throws {}
    
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
        return []
    }
}

extension KafkaClient {
    public func fetchClusterMetrics() async throws -> KafkaMetrics {
        guard state == .connected else {
            throw MQError.notConnected
        }
        
        try await refreshMetadata()
        let topicCount = metadataLock.withLock { cachedTopics.count }
        
        return KafkaMetrics(
            partitionCount: topicCount,
            underReplicatedPartitions: 0,
            consumerGroupLag: 0,
            isrShrinkRate: 0.0,
            logEndOffset: 0
        )
    }
    
    public func listTopics() async throws -> [String] {
        guard state == .connected else {
            throw MQError.notConnected
        }
        
        try await refreshMetadata()
        return metadataLock.withLock { cachedTopics }
    }
    
    public func fetchLastMessages(topic: String, count: Int) async throws -> [MQMessage] {
        guard state == .connected, let cons = consumer else {
            throw MQError.notConnected
        }
        
        let topicList = rd_kafka_topic_partition_list_new(1)
        defer { rd_kafka_topic_partition_list_destroy(topicList) }
        
        rd_kafka_topic_partition_list_add(topicList, topic, RD_KAFKA_PARTITION_UA)
        rd_kafka_topic_partition_list_set_offset(topicList, topic, RD_KAFKA_PARTITION_UA, Int64(RD_KAFKA_OFFSET_END) - Int64(count))
        
        rd_kafka_assign(cons, topicList)
        defer { rd_kafka_assign(cons, nil) }
        
        var messages: [MQMessage] = []
        let deadline = Date().addingTimeInterval(5.0)
        
        while messages.count < count && Date() < deadline {
            let msg = rd_kafka_consumer_poll(cons, 100)
            guard let msg else { continue }
            defer { rd_kafka_message_destroy(msg) }
            
            let msgRef = msg.pointee
            
            if msgRef.err != RD_KAFKA_RESP_ERR_NO_ERROR {
                continue
            }
            
            var payload = Data()
            if let payloadPtr = msgRef.payload, msgRef.len > 0 {
                payload = Data(bytes: payloadPtr, count: msgRef.len)
            }
            
            let message = MQMessage(
                subject: topic,
                payload: payload,
                headers: [
                    "kafka.partition": String(msgRef.partition),
                    "kafka.offset": String(msgRef.offset)
                ],
                timestamp: Date()
            )
            messages.append(message)
        }
        
        return messages
    }
}

private struct KafkaAcknowledgeableMessage: MQAcknowledgeableMessage {
    let message: MQMessage
    let metadata: MQMessageMetadata
    
    func ack() async throws {}
    func nak(delay: Duration?) async throws {}
    func term() async throws {}
    func inProgress() async throws {}
}
