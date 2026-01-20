//
//  RabbitMQClient.swift
//  MQTT Plus
//
//  Pure Swift RabbitMQ client using AMQP 0-9-1 protocol over Network.framework
//

import Foundation
import Combine
import Network

// MARK: - RabbitMQ Client

/// RabbitMQ client implementing AMQP 0-9-1 protocol in pure Swift.
/// - Supports: `connect`, `publish`, `subscribe` (via queues), `unsubscribe`
/// - Connection: `amqp://` (TCP) and `amqps://` (TLS)
public final class RabbitMQClient: @unchecked Sendable {
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

    private let connectionQueue = DispatchQueue(label: "RabbitMQClient.connection")
    private var connection: NWConnection?
    private var frameParser = AMQPFrameParser()
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    // AMQP state
    private var negotiatedFrameMax: UInt32 = 131072
    private var negotiatedHeartbeat: UInt16 = 60
    private var nextChannelId: UInt16 = 1
    private var openChannels: Set<UInt16> = []
    
    // Subscription management
    private struct Subscription {
        let channelId: UInt16
        let queueName: String
        let consumerTag: String
        let continuation: AsyncStream<MQMessage>.Continuation
    }
    
    private var subscriptions: [String: Subscription] = [:]
    private let subscriptionsLock = NSLock()
    
    // Pending responses
    private var pendingResponses: [UInt16: CheckedContinuation<AMQPFrame, Error>] = [:]
    private let pendingLock = NSLock()
    
    // Metrics
    private var _messagesPublished: UInt64 = 0
    private var _messagesDelivered: UInt64 = 0
    private var _bytesPublished: UInt64 = 0
    private var _bytesDelivered: UInt64 = 0
    private let metricsLock = NSLock()

    public init(config: MQConnectionConfig) {
        self.config = config
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
        heartbeatTask?.cancel()
        heartbeatTask = nil
        
        receiveTask?.cancel()
        receiveTask = nil

        let continuations = subscriptionsLock.withLock { () -> [AsyncStream<MQMessage>.Continuation] in
            let conts = subscriptions.values.map { $0.continuation }
            subscriptions.removeAll()
            return conts
        }
        continuations.forEach { $0.finish() }
        
        pendingLock.withLock {
            for (_, continuation) in pendingResponses {
                continuation.resume(throwing: MQError.connectionFailed("Connection closed"))
            }
            pendingResponses.removeAll()
        }

        connection?.cancel()
        connection = nil
        openChannels.removeAll()
        frameParser = AMQPFrameParser()
    }
}

// MARK: - MessageQueueClient

extension RabbitMQClient: MessageQueueClient {
    public func connect() async throws {
        guard state != .connected else { return }

        updateState(.connecting)

        let endpoint = try RabbitMQEndpoint.parse(from: config)

        do {
            // Create TCP/TLS connection
            let conn = try await makeConnection(endpoint: endpoint)
            connection = conn
            
            // Start receive loop
            startReceiveLoop()

            // Send AMQP protocol header
            try await sendProtocolHeader()

            // Perform AMQP handshake
            try await performHandshake(endpoint: endpoint)
            
            // Start heartbeat
            startHeartbeat()

            updateState(.connected)
        } catch {
            cleanupResources()
            updateState(.error(error.localizedDescription))
            throw error
        }
    }

    public func disconnect() async {
        // Close all channels gracefully
        let channels = openChannels
        for channelId in channels {
            try? await closeChannel(channelId)
        }
        
        // Send Connection.Close
        if connection != nil {
            do {
                let closeFrame = AMQPFrameEncoder.connectionClose(replyCode: 200, replyText: "Normal shutdown")
                try await sendFrame(closeFrame)
                // Wait briefly for CloseOk
                try? await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                // Ignore errors during disconnect
            }
        }
        
        cleanupResources()
        updateState(.disconnected)
    }

    public func publish(_ message: MQMessage, to subject: String) async throws {
        guard state == .connected else {
            throw MQError.notConnected
        }
        
        // Use channel 1 for publishing (open it if needed)
        let channelId: UInt16 = 1
        if !openChannels.contains(channelId) {
            try await openChannel(channelId)
        }

        // Parse routing key and exchange from subject
        // Format: "exchange/routing.key" or just "routing.key" (uses default exchange)
        let (exchange, routingKey) = parseSubject(subject)
        
        // Basic.Publish
        let publishFrame = AMQPFrameEncoder.basicPublish(
            channelId: channelId,
            exchange: exchange,
            routingKey: routingKey
        )
        try await sendFrame(publishFrame)
        
        // Content header
        let headerFrame = AMQPFrameEncoder.contentHeader(
            channelId: channelId,
            bodySize: UInt64(message.payload.count),
            properties: AMQPBasicProperties(
                contentType: "application/octet-stream",
                timestamp: UInt64(message.timestamp.timeIntervalSince1970)
            )
        )
        try await sendFrame(headerFrame)
        
        // Content body
        let bodyFrame = AMQPFrameEncoder.contentBody(
            channelId: channelId,
            payload: message.payload,
            frameMax: negotiatedFrameMax
        )
        for frame in bodyFrame {
            try await sendFrame(frame)
        }
        
        // Update metrics
        metricsLock.withLock {
            _messagesPublished += 1
            _bytesPublished += UInt64(message.payload.count)
        }
    }

    public func subscribe(to pattern: String) async throws -> AsyncStream<MQMessage> {
        guard state == .connected else {
            throw MQError.notConnected
        }

        // Allocate a new channel for this subscription
        let channelId = allocateChannel()
        try await openChannel(channelId)
        
        // Declare queue (auto-generated name based on pattern)
        let queueName = try await declareQueue(channelId: channelId, name: pattern)
        
        // If pattern contains routing key, bind to exchange
        let (exchange, routingKey) = parseSubject(pattern)
        if !exchange.isEmpty {
            try await bindQueue(channelId: channelId, queue: queueName, exchange: exchange, routingKey: routingKey)
        }
        
        // Start consuming
        let consumerTag = "mqplus-\(UUID().uuidString.prefix(8))"
        
        var capturedContinuation: AsyncStream<MQMessage>.Continuation?
        let stream = AsyncStream<MQMessage> { [weak self] continuation in
            capturedContinuation = continuation
            guard let self else {
                continuation.finish()
                return
            }
            
            self.subscriptionsLock.withLock {
                self.subscriptions[pattern] = Subscription(
                    channelId: channelId,
                    queueName: queueName,
                    consumerTag: consumerTag,
                    continuation: continuation
                )
            }
            
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    try? await self?.unsubscribe(from: pattern)
                }
            }
        }
        
        guard capturedContinuation != nil else { return stream }
        
        // Send Basic.Consume
        try await startConsuming(channelId: channelId, queue: queueName, consumerTag: consumerTag)
        
        return stream
    }

    public func unsubscribe(from pattern: String) async throws {
        let subscription = subscriptionsLock.withLock { subscriptions.removeValue(forKey: pattern) }
        guard let sub = subscription else { return }
        
        sub.continuation.finish()
        
        // Send Basic.Cancel
        if state == .connected {
            try? await cancelConsuming(channelId: sub.channelId, consumerTag: sub.consumerTag)
            try? await closeChannel(sub.channelId)
        }
        
        openChannels.remove(sub.channelId)
    }
}

// MARK: - RabbitMQ Metrics

extension RabbitMQClient {
    public func fetchMetrics() -> RabbitMQMetrics {
        metricsLock.lock()
        defer { metricsLock.unlock() }
        
        return RabbitMQMetrics(
            messagesPublished: _messagesPublished,
            messagesDelivered: _messagesDelivered,
            bytesPublished: _bytesPublished,
            bytesDelivered: _bytesDelivered,
            channelCount: openChannels.count,
            consumerCount: subscriptions.count
        )
    }
}

// MARK: - Connection / Handshake

private extension RabbitMQClient {
    func makeConnection(endpoint: RabbitMQEndpoint) async throws -> NWConnection {
        let host = NWEndpoint.Host(endpoint.host)
        guard let port = NWEndpoint.Port(rawValue: endpoint.port) else {
            throw MQError.invalidConfiguration("Invalid port: \(endpoint.port)")
        }

        let params: NWParameters
        if endpoint.useTLS {
            params = NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options())
        } else {
            params = NWParameters.tcp
        }

        let conn = NWConnection(host: host, port: port, using: params)

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

    func sendProtocolHeader() async throws {
        // AMQP 0-9-1 protocol header: "AMQP" + 0 + 0 + 9 + 1
        let header = Data([0x41, 0x4D, 0x51, 0x50, 0x00, 0x00, 0x09, 0x01])
        try await sendData(header)
    }

    func performHandshake(endpoint: RabbitMQEndpoint) async throws {
        // Wait for Connection.Start
        let startFrame = try await waitForFrame(channelId: 0, timeout: 10.0)
        guard case .method(_, let classId, let methodId, _) = startFrame,
              classId == AMQP.Class.connection && methodId == AMQP.Connection.start else {
            throw MQError.connectionFailed("Expected Connection.Start")
        }
        
        // Send Connection.StartOk
        let username = config.username ?? endpoint.username ?? "guest"
        let password = config.password ?? endpoint.password ?? "guest"
        let startOkFrame = AMQPFrameEncoder.connectionStartOk(
            mechanism: "PLAIN",
            response: "\0\(username)\0\(password)"
        )
        try await sendFrame(startOkFrame)
        
        // Wait for Connection.Tune
        let tuneFrame = try await waitForFrame(channelId: 0, timeout: 10.0)
        guard case .method(_, let tuneClassId, let tuneMethodId, let tunePayload) = tuneFrame,
              tuneClassId == AMQP.Class.connection && tuneMethodId == AMQP.Connection.tune else {
            throw MQError.connectionFailed("Expected Connection.Tune")
        }
        
        // Parse tune parameters
        let (channelMax, frameMax, heartbeat) = AMQPFrameParser.parseTuneParams(tunePayload)
        negotiatedFrameMax = min(frameMax, 131072) // Cap at 128KB
        negotiatedHeartbeat = heartbeat
        
        // Send Connection.TuneOk
        let tuneOkFrame = AMQPFrameEncoder.connectionTuneOk(
            channelMax: channelMax,
            frameMax: negotiatedFrameMax,
            heartbeat: negotiatedHeartbeat
        )
        try await sendFrame(tuneOkFrame)
        
        // Send Connection.Open
        let vhost = endpoint.vhost
        let openFrame = AMQPFrameEncoder.connectionOpen(vhost: vhost)
        try await sendFrame(openFrame)
        
        // Wait for Connection.OpenOk
        let openOkFrame = try await waitForFrame(channelId: 0, timeout: 10.0)
        guard case .method(_, let openClassId, let openMethodId, _) = openOkFrame,
              openClassId == AMQP.Class.connection && openMethodId == AMQP.Connection.openOk else {
            throw MQError.connectionFailed("Expected Connection.OpenOk")
        }
    }
    
    func startHeartbeat() {
        guard negotiatedHeartbeat > 0 else { return }
        
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            let interval = UInt64(negotiatedHeartbeat) * 1_000_000_000 / 2
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { break }
                
                let heartbeatFrame = AMQPFrameEncoder.heartbeat()
                try? await self.sendFrame(heartbeatFrame)
            }
        }
    }
}

// MARK: - Channel Management

private extension RabbitMQClient {
    func allocateChannel() -> UInt16 {
        let id = nextChannelId
        nextChannelId += 1
        return id
    }
    
    func openChannel(_ channelId: UInt16) async throws {
        let openFrame = AMQPFrameEncoder.channelOpen(channelId: channelId)
        try await sendFrame(openFrame)
        
        let response = try await waitForFrame(channelId: channelId, timeout: 10.0)
        guard case .method(_, let classId, let methodId, _) = response,
              classId == AMQP.Class.channel && methodId == AMQP.Channel.openOk else {
            throw MQError.connectionFailed("Failed to open channel \(channelId)")
        }
        
        openChannels.insert(channelId)
    }
    
    func closeChannel(_ channelId: UInt16) async throws {
        let closeFrame = AMQPFrameEncoder.channelClose(channelId: channelId)
        try await sendFrame(closeFrame)
        
        _ = try? await waitForFrame(channelId: channelId, timeout: 5.0)
        openChannels.remove(channelId)
    }
}

// MARK: - Queue Operations

private extension RabbitMQClient {
    func declareQueue(channelId: UInt16, name: String) async throws -> String {
        // Use pattern as queue name, or auto-generate if empty
        let queueName = name.isEmpty ? "" : name.replacingOccurrences(of: "/", with: ".")
        
        let declareFrame = AMQPFrameEncoder.queueDeclare(
            channelId: channelId,
            queue: queueName,
            passive: false,
            durable: false,
            exclusive: false,
            autoDelete: true,
            noWait: false
        )
        try await sendFrame(declareFrame)
        
        let response = try await waitForFrame(channelId: channelId, timeout: 10.0)
        guard case .method(_, let classId, let methodId, let payload) = response,
              classId == AMQP.Class.queue && methodId == AMQP.Queue.declareOk else {
            throw MQError.subscriptionFailed("Failed to declare queue")
        }
        
        // Parse queue name from response
        let actualQueueName = AMQPFrameParser.parseQueueDeclareOk(payload)
        return actualQueueName
    }
    
    func bindQueue(channelId: UInt16, queue: String, exchange: String, routingKey: String) async throws {
        let bindFrame = AMQPFrameEncoder.queueBind(
            channelId: channelId,
            queue: queue,
            exchange: exchange,
            routingKey: routingKey
        )
        try await sendFrame(bindFrame)
        
        let response = try await waitForFrame(channelId: channelId, timeout: 10.0)
        guard case .method(_, let classId, let methodId, _) = response,
              classId == AMQP.Class.queue && methodId == AMQP.Queue.bindOk else {
            throw MQError.subscriptionFailed("Failed to bind queue")
        }
    }
    
    func startConsuming(channelId: UInt16, queue: String, consumerTag: String) async throws {
        let consumeFrame = AMQPFrameEncoder.basicConsume(
            channelId: channelId,
            queue: queue,
            consumerTag: consumerTag,
            noAck: true
        )
        try await sendFrame(consumeFrame)
        
        let response = try await waitForFrame(channelId: channelId, timeout: 10.0)
        guard case .method(_, let classId, let methodId, _) = response,
              classId == AMQP.Class.basic && methodId == AMQP.Basic.consumeOk else {
            throw MQError.subscriptionFailed("Failed to start consumer")
        }
    }
    
    func cancelConsuming(channelId: UInt16, consumerTag: String) async throws {
        let cancelFrame = AMQPFrameEncoder.basicCancel(
            channelId: channelId,
            consumerTag: consumerTag
        )
        try await sendFrame(cancelFrame)
        
        _ = try? await waitForFrame(channelId: channelId, timeout: 5.0)
    }
}

// MARK: - Frame I/O

private extension RabbitMQClient {
    func sendFrame(_ frame: Data) async throws {
        try await sendData(frame)
    }
    
    func sendData(_ data: Data) async throws {
        guard let conn = connection else {
            throw MQError.notConnected
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }
    
    func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            
            do {
                while !Task.isCancelled {
                    // Try to parse buffered frames first
                    while let frame = try self.frameParser.nextFrame() {
                        await self.handleFrame(frame)
                    }
                    
                    // Read more data
                    guard let data = try await self.receiveData() else {
                        break
                    }
                    self.frameParser.feed(data)
                }
            } catch {
                await MainActor.run {
                    self.updateState(.error(error.localizedDescription))
                }
            }
        }
    }
    
    func receiveData() async throws -> Data? {
        guard let conn = connection else { return nil }
        
        return try await withCheckedThrowingContinuation { continuation in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
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
    
    func waitForFrame(channelId: UInt16, timeout: TimeInterval) async throws -> AMQPFrame {
        try await withThrowingTaskGroup(of: AMQPFrame.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { [weak self] continuation in
                    guard let self else {
                        continuation.resume(throwing: MQError.connectionFailed("Client deallocated"))
                        return
                    }
                    self.pendingLock.withLock {
                        self.pendingResponses[channelId] = continuation
                    }
                }
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw MQError.timeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    func handleFrame(_ frame: AMQPFrame) async {
        switch frame {
        case .method(let channelId, let classId, let methodId, let payload):
            // Check if it's a delivery
            if classId == AMQP.Class.basic && methodId == AMQP.Basic.deliver {
                await handleDelivery(channelId: channelId, payload: payload)
            } else {
                // Resume pending continuation
                let continuation = pendingLock.withLock { pendingResponses.removeValue(forKey: channelId) }
                continuation?.resume(returning: frame)
            }
            
        case .header(let channelId, _, _, _):
            // Content header - part of message delivery
            let continuation = pendingLock.withLock { pendingResponses.removeValue(forKey: channelId) }
            continuation?.resume(returning: frame)
            
        case .body(let channelId, _):
            // Content body - part of message delivery
            let continuation = pendingLock.withLock { pendingResponses.removeValue(forKey: channelId) }
            continuation?.resume(returning: frame)
            
        case .heartbeat:
            // Heartbeat received - no action needed
            break
        }
    }
    
    func handleDelivery(channelId: UInt16, payload: Data) async {
        // Parse Basic.Deliver
        let (consumerTag, _, routingKey) = AMQPFrameParser.parseBasicDeliver(payload)
        
        // Wait for content header and body
        do {
            let headerFrame = try await waitForFrame(channelId: channelId, timeout: 5.0)
            guard case .header(_, _, let bodySize, _) = headerFrame else { return }
            
            var bodyData = Data()
            while UInt64(bodyData.count) < bodySize {
                let bodyFrame = try await waitForFrame(channelId: channelId, timeout: 5.0)
                guard case .body(_, let chunk) = bodyFrame else { break }
                bodyData.append(chunk)
            }
            
            // Find subscription and deliver message
            let subscription = subscriptionsLock.withLock {
                subscriptions.values.first { $0.consumerTag == consumerTag }
            }
            
            if let sub = subscription {
                let message = MQMessage(
                    subject: routingKey,
                    payload: bodyData,
                    timestamp: Date()
                )
                sub.continuation.yield(message)
                
                // Update metrics
                metricsLock.withLock {
                    _messagesDelivered += 1
                    _bytesDelivered += UInt64(bodyData.count)
                }
            }
        } catch {
            // Ignore delivery errors
        }
    }
    
    func parseSubject(_ subject: String) -> (exchange: String, routingKey: String) {
        // Format: "exchange/routing.key" or just "routing.key"
        if let slashIndex = subject.firstIndex(of: "/") {
            let exchange = String(subject[..<slashIndex])
            let routingKey = String(subject[subject.index(after: slashIndex)...])
            return (exchange, routingKey)
        }
        return ("", subject)
    }
}

// MARK: - AMQP Constants

private enum AMQP {
    enum Class {
        static let connection: UInt16 = 10
        static let channel: UInt16 = 20
        static let exchange: UInt16 = 40
        static let queue: UInt16 = 50
        static let basic: UInt16 = 60
    }
    
    enum Connection {
        static let start: UInt16 = 10
        static let startOk: UInt16 = 11
        static let tune: UInt16 = 30
        static let tuneOk: UInt16 = 31
        static let open: UInt16 = 40
        static let openOk: UInt16 = 41
        static let close: UInt16 = 50
        static let closeOk: UInt16 = 51
    }
    
    enum Channel {
        static let open: UInt16 = 10
        static let openOk: UInt16 = 11
        static let close: UInt16 = 40
        static let closeOk: UInt16 = 41
    }
    
    enum Queue {
        static let declare: UInt16 = 10
        static let declareOk: UInt16 = 11
        static let bind: UInt16 = 20
        static let bindOk: UInt16 = 21
    }
    
    enum Basic {
        static let consume: UInt16 = 20
        static let consumeOk: UInt16 = 21
        static let cancel: UInt16 = 30
        static let cancelOk: UInt16 = 31
        static let publish: UInt16 = 40
        static let deliver: UInt16 = 60
    }
}

// MARK: - AMQP Frame Types

private enum AMQPFrame {
    case method(channelId: UInt16, classId: UInt16, methodId: UInt16, payload: Data)
    case header(channelId: UInt16, classId: UInt16, bodySize: UInt64, properties: Data)
    case body(channelId: UInt16, payload: Data)
    case heartbeat
}

// MARK: - AMQP Basic Properties

private struct AMQPBasicProperties {
    var contentType: String?
    var contentEncoding: String?
    var headers: [String: String]?
    var deliveryMode: UInt8?
    var priority: UInt8?
    var correlationId: String?
    var replyTo: String?
    var expiration: String?
    var messageId: String?
    var timestamp: UInt64?
    var type: String?
    var userId: String?
    var appId: String?
}

// MARK: - AMQP Frame Encoder

private enum AMQPFrameEncoder {
    static let frameEnd: UInt8 = 0xCE
    
    static func connectionStartOk(mechanism: String, response: String) -> Data {
        var payload = Data()
        
        // Client properties (field table)
        let clientProps: [(String, String)] = [
            ("product", "MQTT Plus"),
            ("version", "1.0"),
            ("platform", "macOS")
        ]
        payload.append(encodeTable(clientProps))
        
        // Mechanism (short string)
        payload.append(encodeShortString(mechanism))
        
        // Response (long string)
        payload.append(encodeLongString(response))
        
        // Locale (short string)
        payload.append(encodeShortString("en_US"))
        
        return encodeMethodFrame(channelId: 0, classId: AMQP.Class.connection, methodId: AMQP.Connection.startOk, payload: payload)
    }
    
    static func connectionTuneOk(channelMax: UInt16, frameMax: UInt32, heartbeat: UInt16) -> Data {
        var payload = Data()
        payload.append(encodeUInt16(channelMax))
        payload.append(encodeUInt32(frameMax))
        payload.append(encodeUInt16(heartbeat))
        return encodeMethodFrame(channelId: 0, classId: AMQP.Class.connection, methodId: AMQP.Connection.tuneOk, payload: payload)
    }
    
    static func connectionOpen(vhost: String) -> Data {
        var payload = Data()
        payload.append(encodeShortString(vhost))
        payload.append(encodeShortString("")) // reserved
        payload.append(UInt8(0)) // reserved
        return encodeMethodFrame(channelId: 0, classId: AMQP.Class.connection, methodId: AMQP.Connection.open, payload: payload)
    }
    
    static func connectionClose(replyCode: UInt16, replyText: String) -> Data {
        var payload = Data()
        payload.append(encodeUInt16(replyCode))
        payload.append(encodeShortString(replyText))
        payload.append(encodeUInt16(0)) // class-id
        payload.append(encodeUInt16(0)) // method-id
        return encodeMethodFrame(channelId: 0, classId: AMQP.Class.connection, methodId: AMQP.Connection.close, payload: payload)
    }
    
    static func channelOpen(channelId: UInt16) -> Data {
        var payload = Data()
        payload.append(encodeShortString("")) // reserved
        return encodeMethodFrame(channelId: channelId, classId: AMQP.Class.channel, methodId: AMQP.Channel.open, payload: payload)
    }
    
    static func channelClose(channelId: UInt16) -> Data {
        var payload = Data()
        payload.append(encodeUInt16(200)) // reply-code
        payload.append(encodeShortString("Normal")) // reply-text
        payload.append(encodeUInt16(0)) // class-id
        payload.append(encodeUInt16(0)) // method-id
        return encodeMethodFrame(channelId: channelId, classId: AMQP.Class.channel, methodId: AMQP.Channel.close, payload: payload)
    }
    
    static func queueDeclare(channelId: UInt16, queue: String, passive: Bool, durable: Bool, exclusive: Bool, autoDelete: Bool, noWait: Bool) -> Data {
        var payload = Data()
        payload.append(encodeUInt16(0)) // reserved
        payload.append(encodeShortString(queue))
        
        var bits: UInt8 = 0
        if passive { bits |= 0x01 }
        if durable { bits |= 0x02 }
        if exclusive { bits |= 0x04 }
        if autoDelete { bits |= 0x08 }
        if noWait { bits |= 0x10 }
        payload.append(bits)
        
        payload.append(encodeTable([])) // arguments
        
        return encodeMethodFrame(channelId: channelId, classId: AMQP.Class.queue, methodId: AMQP.Queue.declare, payload: payload)
    }
    
    static func queueBind(channelId: UInt16, queue: String, exchange: String, routingKey: String) -> Data {
        var payload = Data()
        payload.append(encodeUInt16(0)) // reserved
        payload.append(encodeShortString(queue))
        payload.append(encodeShortString(exchange))
        payload.append(encodeShortString(routingKey))
        payload.append(UInt8(0)) // no-wait
        payload.append(encodeTable([])) // arguments
        return encodeMethodFrame(channelId: channelId, classId: AMQP.Class.queue, methodId: AMQP.Queue.bind, payload: payload)
    }
    
    static func basicPublish(channelId: UInt16, exchange: String, routingKey: String) -> Data {
        var payload = Data()
        payload.append(encodeUInt16(0)) // reserved
        payload.append(encodeShortString(exchange))
        payload.append(encodeShortString(routingKey))
        payload.append(UInt8(0)) // mandatory=false, immediate=false
        return encodeMethodFrame(channelId: channelId, classId: AMQP.Class.basic, methodId: AMQP.Basic.publish, payload: payload)
    }
    
    static func basicConsume(channelId: UInt16, queue: String, consumerTag: String, noAck: Bool) -> Data {
        var payload = Data()
        payload.append(encodeUInt16(0)) // reserved
        payload.append(encodeShortString(queue))
        payload.append(encodeShortString(consumerTag))
        
        var bits: UInt8 = 0
        // no-local = false (bit 0)
        if noAck { bits |= 0x02 } // no-ack (bit 1)
        // exclusive = false (bit 2)
        // no-wait = false (bit 3)
        payload.append(bits)
        
        payload.append(encodeTable([])) // arguments
        
        return encodeMethodFrame(channelId: channelId, classId: AMQP.Class.basic, methodId: AMQP.Basic.consume, payload: payload)
    }
    
    static func basicCancel(channelId: UInt16, consumerTag: String) -> Data {
        var payload = Data()
        payload.append(encodeShortString(consumerTag))
        payload.append(UInt8(0)) // no-wait
        return encodeMethodFrame(channelId: channelId, classId: AMQP.Class.basic, methodId: AMQP.Basic.cancel, payload: payload)
    }
    
    static func contentHeader(channelId: UInt16, bodySize: UInt64, properties: AMQPBasicProperties) -> Data {
        var propData = Data()
        var propFlags: UInt16 = 0
        
        // Content-type (bit 15)
        if let contentType = properties.contentType {
            propFlags |= 0x8000
            propData.append(encodeShortString(contentType))
        }
        
        // Timestamp (bit 4)
        if let timestamp = properties.timestamp {
            propFlags |= 0x0010
            propData.append(encodeUInt64(timestamp))
        }
        
        var payload = Data()
        payload.append(encodeUInt16(AMQP.Class.basic)) // class-id
        payload.append(encodeUInt16(0)) // weight (unused)
        payload.append(encodeUInt64(bodySize))
        payload.append(encodeUInt16(propFlags))
        payload.append(propData)
        
        return encodeFrame(type: 2, channelId: channelId, payload: payload)
    }
    
    static func contentBody(channelId: UInt16, payload: Data, frameMax: UInt32) -> [Data] {
        var frames: [Data] = []
        let maxBodySize = Int(frameMax) - 8 // Frame overhead
        
        var offset = 0
        while offset < payload.count {
            let chunkSize = min(maxBodySize, payload.count - offset)
            let chunk = payload.subdata(in: offset..<(offset + chunkSize))
            frames.append(encodeFrame(type: 3, channelId: channelId, payload: chunk))
            offset += chunkSize
        }
        
        if frames.isEmpty {
            frames.append(encodeFrame(type: 3, channelId: channelId, payload: Data()))
        }
        
        return frames
    }
    
    static func heartbeat() -> Data {
        return encodeFrame(type: 8, channelId: 0, payload: Data())
    }
    
    // MARK: - Encoding Helpers
    
    private static func encodeMethodFrame(channelId: UInt16, classId: UInt16, methodId: UInt16, payload: Data) -> Data {
        var methodPayload = Data()
        methodPayload.append(encodeUInt16(classId))
        methodPayload.append(encodeUInt16(methodId))
        methodPayload.append(payload)
        return encodeFrame(type: 1, channelId: channelId, payload: methodPayload)
    }
    
    private static func encodeFrame(type: UInt8, channelId: UInt16, payload: Data) -> Data {
        var frame = Data()
        frame.append(type)
        frame.append(encodeUInt16(channelId))
        frame.append(encodeUInt32(UInt32(payload.count)))
        frame.append(payload)
        frame.append(frameEnd)
        return frame
    }
    
    private static func encodeUInt16(_ value: UInt16) -> Data {
        var data = Data(count: 2)
        data[0] = UInt8((value >> 8) & 0xFF)
        data[1] = UInt8(value & 0xFF)
        return data
    }
    
    private static func encodeUInt32(_ value: UInt32) -> Data {
        var data = Data(count: 4)
        data[0] = UInt8((value >> 24) & 0xFF)
        data[1] = UInt8((value >> 16) & 0xFF)
        data[2] = UInt8((value >> 8) & 0xFF)
        data[3] = UInt8(value & 0xFF)
        return data
    }
    
    private static func encodeUInt64(_ value: UInt64) -> Data {
        var data = Data(count: 8)
        for i in 0..<8 {
            data[i] = UInt8((value >> (56 - i * 8)) & 0xFF)
        }
        return data
    }
    
    private static func encodeShortString(_ value: String) -> Data {
        let bytes = value.utf8
        var data = Data()
        data.append(UInt8(min(bytes.count, 255)))
        data.append(contentsOf: bytes.prefix(255))
        return data
    }
    
    private static func encodeLongString(_ value: String) -> Data {
        let bytes = Array(value.utf8)
        var data = Data()
        data.append(encodeUInt32(UInt32(bytes.count)))
        data.append(contentsOf: bytes)
        return data
    }
    
    private static func encodeTable(_ pairs: [(String, String)]) -> Data {
        var tableData = Data()
        for (key, value) in pairs {
            tableData.append(encodeShortString(key))
            tableData.append(UInt8(0x53)) // 'S' for long string
            tableData.append(encodeLongString(value))
        }
        
        var data = Data()
        data.append(encodeUInt32(UInt32(tableData.count)))
        data.append(tableData)
        return data
    }
}

// MARK: - AMQP Frame Parser

private struct AMQPFrameParser: Sendable {
    private var buffer = Data()
    
    nonisolated init() {}
    
    nonisolated mutating func feed(_ data: Data) {
        buffer.append(data)
    }
    
    nonisolated mutating func nextFrame() throws -> AMQPFrame? {
        // Need at least 8 bytes for frame header + end
        guard buffer.count >= 8 else { return nil }
        
        let type = buffer[0]
        let channelId = readUInt16(at: 1)
        let size = readUInt32(at: 3)
        
        let totalSize = 7 + Int(size) + 1 // header + payload + frame-end
        guard buffer.count >= totalSize else { return nil }
        
        // Verify frame end
        guard buffer[totalSize - 1] == 0xCE else {
            throw MQError.providerError("Invalid AMQP frame end marker")
        }
        
        let payload = buffer.subdata(in: 7..<(7 + Int(size)))
        buffer.removeSubrange(0..<totalSize)
        
        switch type {
        case 1: // Method
            guard payload.count >= 4 else { return nil }
            let classId = readUInt16(from: payload, at: 0)
            let methodId = readUInt16(from: payload, at: 2)
            let methodPayload = payload.count > 4 ? payload.subdata(in: 4..<payload.count) : Data()
            return .method(channelId: channelId, classId: classId, methodId: methodId, payload: methodPayload)
            
        case 2: // Header
            guard payload.count >= 12 else { return nil }
            let classId = readUInt16(from: payload, at: 0)
            // weight at 2 (unused)
            let bodySize = readUInt64(from: payload, at: 4)
            let properties = payload.count > 12 ? payload.subdata(in: 12..<payload.count) : Data()
            return .header(channelId: channelId, classId: classId, bodySize: bodySize, properties: properties)
            
        case 3: // Body
            return .body(channelId: channelId, payload: payload)
            
        case 8: // Heartbeat
            return .heartbeat
            
        default:
            throw MQError.providerError("Unknown AMQP frame type: \(type)")
        }
    }
    
    // MARK: - Static Parsing Helpers
    
    static func parseTuneParams(_ payload: Data) -> (channelMax: UInt16, frameMax: UInt32, heartbeat: UInt16) {
        guard payload.count >= 8 else { return (0, 131072, 60) }
        
        let channelMax = (UInt16(payload[0]) << 8) | UInt16(payload[1])
        let frameMax = (UInt32(payload[2]) << 24) | (UInt32(payload[3]) << 16) |
                       (UInt32(payload[4]) << 8) | UInt32(payload[5])
        let heartbeat = (UInt16(payload[6]) << 8) | UInt16(payload[7])
        
        return (channelMax, frameMax, heartbeat)
    }
    
    static func parseQueueDeclareOk(_ payload: Data) -> String {
        guard payload.count >= 1 else { return "" }
        let nameLen = Int(payload[0])
        guard payload.count >= 1 + nameLen else { return "" }
        return String(data: payload.subdata(in: 1..<(1 + nameLen)), encoding: .utf8) ?? ""
    }
    
    static func parseBasicDeliver(_ payload: Data) -> (consumerTag: String, deliveryTag: UInt64, routingKey: String) {
        guard payload.count >= 1 else { return ("", 0, "") }
        
        var offset = 0
        
        // Consumer tag (short string)
        let tagLen = Int(payload[offset])
        offset += 1
        let consumerTag = String(data: payload.subdata(in: offset..<(offset + tagLen)), encoding: .utf8) ?? ""
        offset += tagLen
        
        // Delivery tag (uint64)
        guard payload.count >= offset + 8 else { return (consumerTag, 0, "") }
        var deliveryTag: UInt64 = 0
        for i in 0..<8 {
            deliveryTag = (deliveryTag << 8) | UInt64(payload[offset + i])
        }
        offset += 8
        
        // Redelivered (bit)
        offset += 1
        
        // Exchange (short string)
        guard payload.count >= offset + 1 else { return (consumerTag, deliveryTag, "") }
        let exchangeLen = Int(payload[offset])
        offset += 1 + exchangeLen
        
        // Routing key (short string)
        guard payload.count >= offset + 1 else { return (consumerTag, deliveryTag, "") }
        let routingKeyLen = Int(payload[offset])
        offset += 1
        guard payload.count >= offset + routingKeyLen else { return (consumerTag, deliveryTag, "") }
        let routingKey = String(data: payload.subdata(in: offset..<(offset + routingKeyLen)), encoding: .utf8) ?? ""
        
        return (consumerTag, deliveryTag, routingKey)
    }
    
    // MARK: - Instance Helpers
    
    private func readUInt16(at offset: Int) -> UInt16 {
        return (UInt16(buffer[offset]) << 8) | UInt16(buffer[offset + 1])
    }
    
    private func readUInt32(at offset: Int) -> UInt32 {
        return (UInt32(buffer[offset]) << 24) | (UInt32(buffer[offset + 1]) << 16) |
               (UInt32(buffer[offset + 2]) << 8) | UInt32(buffer[offset + 3])
    }
    
    private func readUInt16(from data: Data, at offset: Int) -> UInt16 {
        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }
    
    private func readUInt64(from data: Data, at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<8 {
            value = (value << 8) | UInt64(data[offset + i])
        }
        return value
    }
}

// MARK: - RabbitMQ URL Parsing

private struct RabbitMQEndpoint {
    let host: String
    let port: UInt16
    let username: String?
    let password: String?
    let vhost: String
    let useTLS: Bool

    static func parse(from config: MQConnectionConfig) throws -> RabbitMQEndpoint {
        guard let url = URL(string: config.url) else {
            throw MQError.invalidConfiguration("Invalid RabbitMQ URL")
        }

        guard let scheme = url.scheme?.lowercased() else {
            throw MQError.invalidConfiguration("Missing URL scheme")
        }

        let useTLS: Bool
        switch scheme {
        case "amqp":
            useTLS = false
        case "amqps":
            useTLS = true
        default:
            throw MQError.invalidConfiguration("Unsupported RabbitMQ scheme: \(scheme)")
        }

        guard let host = url.host, !host.isEmpty else {
            throw MQError.invalidConfiguration("Missing host")
        }

        let portInt = url.port ?? (useTLS ? 5671 : 5672)
        guard (1...65535).contains(portInt) else {
            throw MQError.invalidConfiguration("Invalid port: \(portInt)")
        }
        let port = UInt16(portInt)

        let username = (url.user?.isEmpty == false) ? url.user : nil
        let password = url.password
        
        // Parse vhost from path (default is "/")
        var vhost = url.path
        if vhost.hasPrefix("/") {
            vhost = String(vhost.dropFirst())
        }
        if vhost.isEmpty {
            vhost = "/"
        } else {
            // URL decode vhost
            vhost = vhost.removingPercentEncoding ?? vhost
        }

        return RabbitMQEndpoint(
            host: host,
            port: port,
            username: username,
            password: password,
            vhost: vhost,
            useTLS: useTLS || config.tlsEnabled
        )
    }
}

// MARK: - RabbitMQ Metrics Model

public struct RabbitMQMetrics: Sendable, Equatable {
    public let messagesPublished: UInt64
    public let messagesDelivered: UInt64
    public let bytesPublished: UInt64
    public let bytesDelivered: UInt64
    public let channelCount: Int
    public let consumerCount: Int
    
    public init(
        messagesPublished: UInt64 = 0,
        messagesDelivered: UInt64 = 0,
        bytesPublished: UInt64 = 0,
        bytesDelivered: UInt64 = 0,
        channelCount: Int = 0,
        consumerCount: Int = 0
    ) {
        self.messagesPublished = messagesPublished
        self.messagesDelivered = messagesDelivered
        self.bytesPublished = bytesPublished
        self.bytesDelivered = bytesDelivered
        self.channelCount = channelCount
        self.consumerCount = consumerCount
    }
    
    /// Compute health status based on metrics
    public var healthStatus: HealthStatus {
        // For now, always healthy since we track local metrics only
        .healthy
    }
    
    /// Human-readable bytes published
    public var bytesPublishedFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPublished), countStyle: .binary)
    }
    
    /// Human-readable bytes delivered
    public var bytesDeliveredFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesDelivered), countStyle: .binary)
    }
    
    /// Summary for collapsed view
    public var healthSummary: String {
        "Pub: \(messagesPublished.formatted()) • Del: \(messagesDelivered.formatted()) • \(channelCount) ch"
    }
}
