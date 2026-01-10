//
//  RedisClient.swift
//  PubSub Viewer
//
//  Lightweight Redis Pub/Sub client using RESP over TCP (Network.framework)
//

import Foundation
import Combine
import Network

// MARK: - Redis Client

/// Redis Pub/Sub client (RESP2) implemented in Swift.
/// - Supports: `PUBLISH`, `SUBSCRIBE`, `PSUBSCRIBE`, `UNSUBSCRIBE`, `PUNSUBSCRIBE`
/// - Connection: `redis://` (TCP) and `rediss://` (TLS)
public final class RedisClient: @unchecked Sendable {
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

    private let commandQueue = DispatchQueue(label: "RedisClient.command")
    private let pubSubQueue = DispatchQueue(label: "RedisClient.pubsub")

    private var commandConnection: NWConnection?
    private var commandExecutor: RedisCommandExecutor?
    private var pubSubSender: RedisPubSubSender?
    private var pubSubConnection: NWConnection?
    private var pubSubParser = RESPParser()
    private var pubSubTask: Task<Void, Never>?

    private struct Subscription {
        enum Kind: Hashable {
            case channel
            case pattern
        }

        let kind: Kind
        let continuation: AsyncStream<MQMessage>.Continuation
    }

    private var subscriptions: [String: Subscription] = [:]
    private let subscriptionsLock = NSLock()

    private struct SubscriptionAckKey: Hashable {
        let kind: Subscription.Kind
        let key: String
    }

    private var pendingSubscriptionAcks: [SubscriptionAckKey: AsyncStream<Void>.Continuation] = [:]
    private let pendingSubscriptionAcksLock = NSLock()

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
        pubSubTask?.cancel()
        pubSubTask = nil

        let continuations = subscriptionsLock.withLock { () -> [AsyncStream<MQMessage>.Continuation] in
            let continuations = subscriptions.values.map { $0.continuation }
            subscriptions.removeAll()
            return continuations
        }
        continuations.forEach { $0.finish() }

        let ackContinuations = pendingSubscriptionAcksLock.withLock { () -> [AsyncStream<Void>.Continuation] in
            let continuations = pendingSubscriptionAcks.values.map { $0 }
            pendingSubscriptionAcks.removeAll()
            return continuations
        }
        ackContinuations.forEach { $0.finish() }

        pubSubConnection?.cancel()
        pubSubConnection = nil
        pubSubSender = nil

        commandConnection?.cancel()
        commandConnection = nil
        commandExecutor = nil
    }
}

// MARK: - MessageQueueClient

extension RedisClient: MessageQueueClient {
    public func connect() async throws {
        guard state != .connected else { return }

        updateState(.connecting)

        let endpoint = try RedisEndpoint.parse(from: config)

        do {
            let cmdConn = try await makeConnection(endpoint: endpoint, queue: commandQueue)
            commandConnection = cmdConn
            let executor = RedisCommandExecutor(connection: cmdConn)
            commandExecutor = executor

            // AUTH (optional)
            let authUsername = config.username ?? endpoint.username
            let authPassword = config.password ?? endpoint.password

            if let password = authPassword, !password.isEmpty {
                if let username = authUsername, !username.isEmpty {
                    _ = try await executor.execute([.string("AUTH"), .string(username), .string(password)])
                } else {
                    _ = try await executor.execute([.string("AUTH"), .string(password)])
                }
            }

            // PING to validate connectivity
            let pong = try await executor.execute([.string("PING")])
            guard case .simpleString(let value) = pong, value.uppercased() == "PONG" else {
                throw MQError.connectionFailed("Unexpected PING response")
            }

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
        guard state == .connected, let executor = commandExecutor else {
            throw MQError.notConnected
        }

        let reply = try await executor.execute([.string("PUBLISH"), .string(subject), .data(message.payload)])
        guard case .integer = reply else {
            throw MQError.publishFailed("Unexpected reply for PUBLISH")
        }
    }

    public func subscribe(to pattern: String) async throws -> AsyncStream<MQMessage> {
        guard state == .connected else {
            throw MQError.notConnected
        }

        let normalized = normalizePattern(pattern)
        let kind: Subscription.Kind = isGlobPattern(normalized) ? .pattern : .channel

        try await ensurePubSubConnection()

        var capturedContinuation: AsyncStream<MQMessage>.Continuation?
        let stream = AsyncStream { [weak self] continuation in
            capturedContinuation = continuation
            guard let self else {
                continuation.finish()
                return
            }

            self.subscriptionsLock.withLock {
                if let existing = self.subscriptions[normalized] {
                    existing.continuation.finish()
                }
                self.subscriptions[normalized] = Subscription(kind: kind, continuation: continuation)
            }

            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    try? await self?.unsubscribe(from: normalized)
                }
            }
        }

        guard let continuation = capturedContinuation else { return stream }

        let ackStream = registerSubscriptionAck(kind: kind, key: normalized)
        let timeoutNanoseconds: UInt64 = 5_000_000_000

        do {
            try await sendSubscribe(normalized, kind: kind)
            try await waitForSubscriptionAck(ackStream, timeoutNanoseconds: timeoutNanoseconds)
        } catch {
            cancelSubscriptionAck(kind: kind, key: normalized)
            subscriptionsLock.withLock {
                _ = subscriptions.removeValue(forKey: normalized)
            }
            continuation.finish()
            throw error
        }

        return stream
    }

    public func unsubscribe(from pattern: String) async throws {
        let normalized = normalizePattern(pattern)

        let subscription = subscriptionsLock.withLock { subscriptions.removeValue(forKey: normalized) }

        subscription?.continuation.finish()

        guard let subscription else { return }
        guard state == .connected else { return }

        switch subscription.kind {
        case .channel:
            try await sendPubSubOnly([.string("UNSUBSCRIBE"), .string(normalized)])
        case .pattern:
            try await sendPubSubOnly([.string("PUNSUBSCRIBE"), .string(normalized)])
        }
    }
}

// MARK: - Redis Metrics

extension RedisClient {
    public func fetchServerMetrics() async throws -> RedisMetrics {
        guard state == .connected, let executor = commandExecutor else {
            throw MQError.notConnected
        }

        let reply = try await executor.execute([.string("INFO")])
        guard let infoString = reply.asString else {
            throw MQError.providerError("Unexpected INFO response")
        }

        let info = parseInfo(infoString)

        let usedMemoryBytes = UInt64(info["used_memory"] ?? "") ?? 0
        let usedMemoryHuman = info["used_memory_human"] ?? ByteCountFormatter.string(fromByteCount: Int64(usedMemoryBytes), countStyle: .binary)
        let instantaneousOpsPerSec = Int(info["instantaneous_ops_per_sec"] ?? "") ?? 0
        let connectedClients = Int(info["connected_clients"] ?? "") ?? 0
        let memFragmentationRatio = Double(info["mem_fragmentation_ratio"] ?? "") ?? 1.0
        let totalNetInputBytes = UInt64(info["total_net_input_bytes"] ?? "") ?? 0

        return RedisMetrics(
            usedMemoryHuman: usedMemoryHuman,
            usedMemoryBytes: usedMemoryBytes,
            instantaneousOpsPerSec: instantaneousOpsPerSec,
            connectedClients: connectedClients,
            memFragmentationRatio: memFragmentationRatio,
            totalNetInputBytes: totalNetInputBytes
        )
    }

    private func parseInfo(_ info: String) -> [String: String] {
        var result: [String: String] = [:]
        result.reserveCapacity(64)

        for line in info.split(whereSeparator: \.isNewline) {
            guard !line.isEmpty else { continue }
            if line.first == "#" { continue }

            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let key = String(parts[0])
            let value = String(parts[1])
            result[key] = value
        }

        return result
    }
}

// MARK: - Connection / PubSub Loop

private extension RedisClient {
    func ensurePubSubConnection() async throws {
        if pubSubConnection != nil { return }

        let endpoint = try RedisEndpoint.parse(from: config)
        let conn = try await makeConnection(endpoint: endpoint, queue: pubSubQueue)
        pubSubConnection = conn
        pubSubParser = RESPParser()
        pubSubSender = RedisPubSubSender(connection: conn)

        pubSubTask = Task { [weak self] in
            guard let self else { return }
            await self.runPubSubLoop(connection: conn)
        }
    }

    func runPubSubLoop(connection: NWConnection) async {
        do {
            while !Task.isCancelled {
                if let value = try pubSubParser.nextValue() {
                    handlePubSubValue(value)
                    continue
                }

                guard let data = try await receiveChunk(from: connection) else {
                    break
                }
                pubSubParser.feed(data)
            }
        } catch {
            updateState(.error(error.localizedDescription))
        }
    }

    func handlePubSubValue(_ value: RESPValue) {
        guard case .array(let elements) = value else { return }
        guard let elements else { return }
        guard let first = elements.first, let type = first.asString?.lowercased() else { return }

        switch type {
        case "message":
            // ["message", channel, payload]
            guard elements.count >= 3 else { return }
            guard let channel = elements[1].asString else { return }
            let payload = elements[2].asData ?? Data()
            yield(to: channel, message: MQMessage(subject: channel, payload: payload, timestamp: Date()))

        case "pmessage":
            // ["pmessage", pattern, channel, payload]
            guard elements.count >= 4 else { return }
            guard let pattern = elements[1].asString else { return }
            guard let channel = elements[2].asString else { return }
            let payload = elements[3].asData ?? Data()

            let msg = MQMessage(
                subject: channel,
                payload: payload,
                headers: ["redis.pattern": pattern],
                timestamp: Date()
            )
            yield(to: pattern, message: msg)

        case "subscribe":
            // ["subscribe", channel, count]
            guard elements.count >= 2 else { return }
            guard let channel = elements[1].asString else { return }
            acknowledgeSubscription(kind: .channel, key: channel)

        case "psubscribe":
            // ["psubscribe", pattern, count]
            guard elements.count >= 2 else { return }
            guard let pattern = elements[1].asString else { return }
            acknowledgeSubscription(kind: .pattern, key: pattern)

        case "unsubscribe", "punsubscribe":
            // Subscription control messages; ignore.
            break

        default:
            break
        }
    }

    private func acknowledgeSubscription(kind: Subscription.Kind, key: String) {
        let ackKey = SubscriptionAckKey(kind: kind, key: key)
        let continuation = pendingSubscriptionAcksLock.withLock { pendingSubscriptionAcks.removeValue(forKey: ackKey) }
        continuation?.yield(())
        continuation?.finish()
    }

    func yield(to key: String, message: MQMessage) {
        let continuation = subscriptionsLock.withLock { subscriptions[key]?.continuation }
        continuation?.yield(message)
    }

    private func registerSubscriptionAck(kind: Subscription.Kind, key: String) -> AsyncStream<Void> {
        let ackKey = SubscriptionAckKey(kind: kind, key: key)
        return AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            self.pendingSubscriptionAcksLock.withLock {
                self.pendingSubscriptionAcks[ackKey]?.finish()
                self.pendingSubscriptionAcks[ackKey] = continuation
            }
        }
    }

    private func cancelSubscriptionAck(kind: Subscription.Kind, key: String) {
        let ackKey = SubscriptionAckKey(kind: kind, key: key)
        let continuation = pendingSubscriptionAcksLock.withLock { pendingSubscriptionAcks.removeValue(forKey: ackKey) }
        continuation?.finish()
    }

    private func waitForSubscriptionAck(_ stream: AsyncStream<Void>, timeoutNanoseconds: UInt64) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in stream {
                    return
                }
                throw MQError.subscriptionFailed("Subscription acknowledgement stream ended")
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw MQError.timeout
            }

            try await group.next()!
            group.cancelAll()
        }
    }

    private func sendSubscribe(_ key: String, kind: Subscription.Kind) async throws {
        guard state == .connected else {
            throw MQError.notConnected
        }

        switch kind {
        case .channel:
            try await sendPubSubOnly([.string("SUBSCRIBE"), .string(key)])
        case .pattern:
            try await sendPubSubOnly([.string("PSUBSCRIBE"), .string(key)])
        }
    }
}

// MARK: - RESP Transport

private extension RedisClient {
    func makeConnection(endpoint: RedisEndpoint, queue: DispatchQueue) async throws -> NWConnection {
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

        let connection = NWConnection(host: host, port: port, using: params)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    continuation.resume(returning: ())
                case .failed(let error):
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                case .cancelled:
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: MQError.connectionFailed("Connection cancelled"))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }

        return connection
    }

    func receiveChunk(from connection: NWConnection) async throws -> Data? {
        while true {
            let (data, isComplete) = try await receiveOnce(from: connection)

            if isComplete {
                guard let data, !data.isEmpty else { return nil }
                return data
            }

            if let data, !data.isEmpty { return data }

            // Defensive: `NWConnection` can surface `nil`/empty chunks without completing the stream.
            // Avoid tight loops that would starve other tasks.
            await Task.yield()
        }
    }

    func receiveOnce(from connection: NWConnection) async throws -> (data: Data?, isComplete: Bool) {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (data, isComplete))
            }
        }
    }

    func sendPubSubOnly(_ parts: [RedisCommandPart]) async throws {
        guard let sender = pubSubSender else {
            throw MQError.notConnected
        }
        try await sender.send(parts)
    }
}

// MARK: - Redis URL Parsing

private struct RedisEndpoint {
    let host: String
    let port: UInt16
    let username: String?
    let password: String?
    let useTLS: Bool

    static func parse(from config: MQConnectionConfig) throws -> RedisEndpoint {
        guard let url = URL(string: config.url) else {
            throw MQError.invalidConfiguration("Invalid Redis URL")
        }

        guard let scheme = url.scheme?.lowercased() else {
            throw MQError.invalidConfiguration("Missing URL scheme")
        }

        let useTLS: Bool
        switch scheme {
        case "redis":
            useTLS = false
        case "rediss":
            useTLS = true
        default:
            throw MQError.invalidConfiguration("Unsupported Redis scheme: \(scheme)")
        }

        guard let host = url.host, !host.isEmpty else {
            throw MQError.invalidConfiguration("Missing host")
        }

        let portInt = url.port ?? 6379
        guard (1...65535).contains(portInt) else {
            throw MQError.invalidConfiguration("Invalid port: \(portInt)")
        }
        let port = UInt16(portInt)

        let username = (url.user?.isEmpty == false) ? url.user : nil
        let password = url.password

        return RedisEndpoint(host: host, port: port, username: username, password: password, useTLS: useTLS || config.tlsEnabled)
    }
}

// MARK: - Pattern Helpers

private extension RedisClient {
    func normalizePattern(_ pattern: String) -> String {
        // Allow NATS-style ">" in the UI to mean "all" for Redis as well.
        if pattern == ">" { return "*" }
        return pattern
    }

    func isGlobPattern(_ pattern: String) -> Bool {
        pattern.contains("*") || pattern.contains("?") || pattern.contains("[")
    }
}

// MARK: - RESP Types

private enum RESPValue: Sendable {
    case simpleString(String)
    case error(String)
    case integer(Int64)
    case bulkString(Data?)
    case array([RESPValue]?)

    var asString: String? {
        switch self {
        case .simpleString(let s):
            return s
        case .bulkString(let data?):
            return String(data: data, encoding: .utf8)
        default:
            return nil
        }
    }

    var asData: Data? {
        switch self {
        case .bulkString(let data):
            return data
        case .simpleString(let s):
            return s.data(using: .utf8)
        default:
            return nil
        }
    }
}

private enum RedisCommandPart: Sendable {
    case string(String)
    case data(Data)

    nonisolated var bytes: Data {
        switch self {
        case .string(let s):
            return s.data(using: .utf8) ?? Data()
        case .data(let d):
            return d
        }
    }
}

private actor RedisCommandExecutor {
    private let connection: NWConnection
    private var parser = RESPParser()

    init(connection: NWConnection) {
        self.connection = connection
    }

    func execute(_ parts: [RedisCommandPart]) async throws -> RESPValue {
        let encoded = RESPEncoder.encodeArray(parts)
        try await sendData(encoded)

        while true {
            if let value = try parser.nextValue() {
                return value
            }
            guard let chunk = try await receiveChunk() else {
                throw MQError.connectionFailed("Connection closed")
            }
            parser.feed(chunk)
        }
    }

    private func sendData(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    private func receiveChunk() async throws -> Data? {
        while true {
            let (data, isComplete) = try await receiveOnce()

            if isComplete {
                guard let data, !data.isEmpty else { return nil }
                return data
            }

            if let data, !data.isEmpty { return data }

            // Defensive: avoid tight loops if `NWConnection` produces `nil`/empty chunks.
            await Task.yield()
        }
    }

    private func receiveOnce() async throws -> (data: Data?, isComplete: Bool) {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (data, isComplete))
            }
        }
    }
}

private actor RedisPubSubSender {
    private let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
    }

    func send(_ parts: [RedisCommandPart]) async throws {
        let encoded = RESPEncoder.encodeArray(parts)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: encoded, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }
}

private enum RESPEncoder {
    nonisolated static func encodeArray(_ parts: [RedisCommandPart]) -> Data {
        var out = Data()
        out.append(contentsOf: "*\(parts.count)\r\n".utf8)
        for part in parts {
            let bytes = part.bytes
            out.append(contentsOf: "$\(bytes.count)\r\n".utf8)
            out.append(bytes)
            out.append(contentsOf: "\r\n".utf8)
        }
        return out
    }
}

private struct RESPParser: Sendable {
    private var buffer = Data()

    nonisolated init() {}

    nonisolated mutating func feed(_ data: Data) {
        buffer.append(data)
    }

    nonisolated mutating func nextValue() throws -> RESPValue? {
        var index = buffer.startIndex
        guard let value = try RESPParser.parse(buffer, index: &index) else {
            return nil
        }
        buffer.removeSubrange(buffer.startIndex ..< index)
        return value
    }

    nonisolated private static func parse(_ data: Data, index: inout Data.Index) throws -> RESPValue? {
        guard index < data.endIndex else { return nil }

        let prefix = data[index]
        index += 1

        switch prefix {
        case UInt8(ascii: "+"):
            guard let line = readLine(data, index: &index) else { return nil }
            return .simpleString(line)

        case UInt8(ascii: "-"):
            guard let line = readLine(data, index: &index) else { return nil }
            return .error(line)

        case UInt8(ascii: ":"):
            guard let line = readLine(data, index: &index) else { return nil }
            guard let value = Int64(line) else { throw MQError.providerError("Invalid integer reply") }
            return .integer(value)

        case UInt8(ascii: "$"):
            guard let line = readLine(data, index: &index) else { return nil }
            guard let len = Int(line) else { throw MQError.providerError("Invalid bulk length") }
            if len == -1 { return .bulkString(nil) }

            let needed = len + 2
            guard index + needed <= data.endIndex else { return nil }
            let bytes = data.subdata(in: index ..< (index + len))
            index += len
            // Consume \r\n
            index += 2
            return .bulkString(bytes)

        case UInt8(ascii: "*"):
            guard let line = readLine(data, index: &index) else { return nil }
            guard let count = Int(line) else { throw MQError.providerError("Invalid array length") }
            if count == -1 { return .array(nil) }

            var items: [RESPValue] = []
            items.reserveCapacity(count)
            for _ in 0..<count {
                guard let item = try parse(data, index: &index) else { return nil }
                items.append(item)
            }
            return .array(items)

        default:
            throw MQError.providerError("Unknown RESP prefix: \(prefix)")
        }
    }

    nonisolated private static func readLine(_ data: Data, index: inout Data.Index) -> String? {
        guard index < data.endIndex else { return nil }
        guard let range = data[index...].range(of: Data([0x0D, 0x0A])) else { return nil }
        let lineData = data.subdata(in: index ..< range.lowerBound)
        index = range.upperBound
        return String(data: lineData, encoding: .utf8) ?? ""
    }
}
