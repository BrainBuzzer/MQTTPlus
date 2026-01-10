//
//  JetStreamModels.swift
//  PubSub Viewer
//
//  Created by Antigravity on 10/01/26.
//

import Foundation

// MARK: - Connection Mode

/// Connection mode selector for NATS
enum NatsMode: String, Codable, CaseIterable {
    case core = "Core NATS"
    case jetstream = "JetStream"
    
    var description: String { rawValue }
}

// MARK: - JetStream Retention & Storage

enum RetentionPolicy: String, Codable {
    case limits = "Limits"
    case interest = "Interest"
    case workQueue = "Work Queue"
}

enum StorageType: String, Codable {
    case file = "File"
    case memory = "Memory"
}

// MARK: - Stream Models

/// Represents a JetStream stream
struct StreamInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let subjects: [String]
    let messageCount: UInt64
    let byteCount: UInt64
    let firstSequence: UInt64
    let lastSequence: UInt64
    let retention: RetentionPolicy
    let storage: StorageType
    let maxAge: TimeInterval? // In seconds
    let maxBytes: Int64?
    let maxMsgSize: Int32?
    let maxConsumers: Int?
    let createdAt: Date
}

/// Configuration for creating a stream
struct StreamConfig {
    let name: String
    let subjects: [String]
    let retention: RetentionPolicy
    let storage: StorageType
    let maxAge: TimeInterval? // In seconds
    let maxBytes: Int64?
    let maxMsgSize: Int32?
    let maxConsumers: Int?
    let replicas: Int
    let duplicateWindow: TimeInterval? // In seconds
    
    init(
        name: String,
        subjects: [String],
        retention: RetentionPolicy = .limits,
        storage: StorageType = .file,
        maxAge: TimeInterval? = nil,
        maxBytes: Int64? = nil,
        maxMsgSize: Int32? = nil,
        maxConsumers: Int? = nil,
        replicas: Int = 1,
        duplicateWindow: TimeInterval? = nil
    ) {
        self.name = name
        self.subjects = subjects
        self.retention = retention
        self.storage = storage
        self.maxAge = maxAge
        self.maxBytes = maxBytes
        self.maxMsgSize = maxMsgSize
        self.maxConsumers = maxConsumers
        self.replicas = replicas
        self.duplicateWindow = duplicateWindow
    }
}

// MARK: - Consumer Models

enum DeliverPolicy: String, Codable {
    case all = "All"
    case last = "Last"
    case new = "New"
    case byStartSequence = "By Start Sequence"
    case byStartTime = "By Start Time"
}

enum AckPolicy: String, Codable {
    case none = "None"
    case all = "All"
    case explicit = "Explicit"
}

/// Represents a JetStream consumer
struct ConsumerInfo: Identifiable, Hashable {
    let id = UUID()
    let streamName: String
    let name: String
    let durable: Bool
    let deliverPolicy: DeliverPolicy
    let ackPolicy: AckPolicy
    let ackWait: TimeInterval // In seconds
    let maxDeliver: Int?
    let pending: UInt64
    let delivered: UInt64
    let redelivered: UInt64
    let numAckPending: UInt64
    let createdAt: Date
}

/// Configuration for creating a consumer
struct ConsumerConfig {
    let name: String?
    let durable: Bool
    let deliverPolicy: DeliverPolicy
    let ackPolicy: AckPolicy
    let ackWait: TimeInterval // In seconds
    let maxDeliver: Int?
    let filterSubject: String?
    let replayPolicy: ReplayPolicy
    let deliverSubject: String? // For push consumers
    
    init(
        name: String? = nil,
        durable: Bool = true,
        deliverPolicy: DeliverPolicy = .all,
        ackPolicy: AckPolicy = .explicit,
        ackWait: TimeInterval = 30,
        maxDeliver: Int? = nil,
        filterSubject: String? = nil,
        replayPolicy: ReplayPolicy = .instant,
        deliverSubject: String? = nil
    ) {
        self.name = name
        self.durable = durable
        self.deliverPolicy = deliverPolicy
        self.ackPolicy = ackPolicy
        self.ackWait = ackWait
        self.maxDeliver = maxDeliver
        self.filterSubject = filterSubject
        self.replayPolicy = replayPolicy
        self.deliverSubject = deliverSubject
    }
}

enum ReplayPolicy: String, Codable {
    case instant = "Instant"
    case original = "Original"
}

// MARK: - Message Acknowledgment

enum AckType: String {
    case ack = "Ack"
    case nak = "Nak"
    case term = "Term"
    case inProgress = "In Progress"
}

// MARK: - JetStream Message Metadata

/// Extended message model with JetStream metadata
struct JetStreamMessageMetadata: Hashable {
    let streamName: String
    let consumerName: String?
    let streamSequence: UInt64
    let consumerSequence: UInt64
    let delivered: UInt64
    let pending: UInt64
    let timestamp: Date
}

// MARK: - Enhanced ReceivedMessage

/// Extension to ReceivedMessage for JetStream metadata
extension ReceivedMessage {
    /// Create a JetStream message with metadata
    static func jetstream(
        subject: String,
        payload: String,
        headers: [String: String]?,
        replyTo: String?,
        byteCount: Int,
        receivedAt: Date,
        metadata: JetStreamMessageMetadata
    ) -> ReceivedMessage {
        // Store metadata in a special way (could use a different struct in the future)
        return ReceivedMessage(
            subject: subject,
            payload: payload,
            headers: headers,
            replyTo: replyTo,
            byteCount: byteCount,
            receivedAt: receivedAt
        )
    }
}

// MARK: - Publish Acknowledgment

struct PublishAck: Hashable {
    let stream: String
    let sequence: UInt64
    let duplicate: Bool
}
