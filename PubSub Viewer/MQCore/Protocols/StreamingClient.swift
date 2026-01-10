//
//  StreamingClient.swift
//  PubSub Viewer
//
//  Extended protocol for MQ systems with persistence/streaming capabilities
//

import Foundation

// MARK: - Streaming Client Protocol

/// Protocol for MQ systems with persistence and streaming capabilities
/// Examples: NATS JetStream, Kafka, RabbitMQ Streams, Redis Streams
public protocol StreamingClient: MessageQueueClient {
    
    // MARK: - Stream/Topic Management
    
    /// List all streams/topics
    func listStreams() async throws -> [MQStreamInfo]
    
    /// Create a new stream/topic
    /// - Parameter config: Stream configuration
    /// - Returns: Created stream info
    @discardableResult
    func createStream(_ config: MQStreamConfig) async throws -> MQStreamInfo
    
    /// Delete a stream/topic
    /// - Parameter name: Stream name to delete
    func deleteStream(_ name: String) async throws
    
    /// Get info about a specific stream
    /// - Parameter name: Stream name
    /// - Returns: Stream info if exists
    func getStreamInfo(_ name: String) async throws -> MQStreamInfo?
    
    // MARK: - Consumer Management
    
    /// List consumers for a stream
    /// - Parameter stream: Stream name
    func listConsumers(stream: String) async throws -> [MQConsumerInfo]
    
    /// Create a consumer for a stream
    /// - Parameters:
    ///   - stream: Stream name
    ///   - config: Consumer configuration
    /// - Returns: Created consumer info
    @discardableResult
    func createConsumer(stream: String, config: MQConsumerConfig) async throws -> MQConsumerInfo
    
    /// Delete a consumer
    /// - Parameters:
    ///   - stream: Stream name
    ///   - name: Consumer name
    func deleteConsumer(stream: String, name: String) async throws
    
    // MARK: - Persistent Publishing
    
    /// Publish a message with persistence acknowledgment
    /// - Parameters:
    ///   - message: Message to publish
    ///   - subject: Subject/topic
    /// - Returns: Acknowledgment with sequence info
    func publishPersistent(_ message: MQMessage, to subject: String) async throws -> MQPublishAck
    
    // MARK: - Consumer Subscription
    
    /// Subscribe to a consumer's message stream
    /// - Parameters:
    ///   - stream: Stream name
    ///   - consumer: Consumer name
    /// - Returns: AsyncStream of acknowledgeable messages
    func consume(stream: String, consumer: String) async throws -> AsyncStream<MQAcknowledgeableMessage>
    
    /// Fetch a batch of messages from a consumer
    /// - Parameters:
    ///   - stream: Stream name
    ///   - consumer: Consumer name
    ///   - batch: Maximum number of messages
    ///   - expires: Timeout for the fetch
    /// - Returns: Array of acknowledgeable messages
    func fetch(stream: String, consumer: String, batch: Int, expires: Duration) async throws -> [MQAcknowledgeableMessage]
}

// MARK: - Acknowledgeable Message

/// A message that requires acknowledgment
public protocol MQAcknowledgeableMessage: Sendable {
    /// The underlying message
    var message: MQMessage { get }
    
    /// Message metadata (sequence numbers, delivery count, etc.)
    var metadata: MQMessageMetadata { get }
    
    /// Acknowledge successful processing
    func ack() async throws
    
    /// Negative acknowledgment - request redelivery
    /// - Parameter delay: Optional delay before redelivery
    func nak(delay: Duration?) async throws
    
    /// Terminate - do not redeliver this message
    func term() async throws
    
    /// Signal that processing is still in progress
    func inProgress() async throws
}

// MARK: - Default Implementations

public extension MQAcknowledgeableMessage {
    func nak() async throws {
        try await nak(delay: nil)
    }
}

// MARK: - Message Metadata

/// Metadata for messages from streaming systems
public struct MQMessageMetadata: Sendable, Hashable {
    public let streamName: String
    public let consumerName: String?
    public let streamSequence: UInt64
    public let consumerSequence: UInt64?
    public let deliveryCount: UInt64
    public let pending: UInt64
    public let timestamp: Date
    
    public init(
        streamName: String,
        consumerName: String? = nil,
        streamSequence: UInt64,
        consumerSequence: UInt64? = nil,
        deliveryCount: UInt64 = 1,
        pending: UInt64 = 0,
        timestamp: Date = Date()
    ) {
        self.streamName = streamName
        self.consumerName = consumerName
        self.streamSequence = streamSequence
        self.consumerSequence = consumerSequence
        self.deliveryCount = deliveryCount
        self.pending = pending
        self.timestamp = timestamp
    }
}

// MARK: - Publish Acknowledgment

/// Acknowledgment returned when publishing to a persistent stream
public struct MQPublishAck: Sendable, Hashable {
    public let stream: String
    public let sequence: UInt64
    public let duplicate: Bool
    public let domain: String?
    
    public init(stream: String, sequence: UInt64, duplicate: Bool = false, domain: String? = nil) {
        self.stream = stream
        self.sequence = sequence
        self.duplicate = duplicate
        self.domain = domain
    }
}
