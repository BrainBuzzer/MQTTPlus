//
//  MQModels.swift
//  MQTT Plus
//
//  Unified data models for all message queue systems
//

import Foundation

// MARK: - Message

/// Unified message model for all MQ systems
public struct MQMessage: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let subject: String
    public let payload: Data
    public let headers: [String: String]?
    public let replyTo: String?
    public let timestamp: Date
    
    public init(
        id: UUID = UUID(),
        subject: String,
        payload: Data,
        headers: [String: String]? = nil,
        replyTo: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.subject = subject
        self.payload = payload
        self.headers = headers
        self.replyTo = replyTo
        self.timestamp = timestamp
    }
    
    /// Create message from string payload
    public init(
        id: UUID = UUID(),
        subject: String,
        payloadString: String,
        headers: [String: String]? = nil,
        replyTo: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.subject = subject
        self.payload = payloadString.data(using: .utf8) ?? Data()
        self.headers = headers
        self.replyTo = replyTo
        self.timestamp = timestamp
    }
    
    /// Payload as UTF-8 string
    public var payloadString: String? {
        String(data: payload, encoding: .utf8)
    }
    
    /// Byte count of payload
    public var byteCount: Int {
        payload.count
    }
}

// MARK: - Stream Info

/// Information about a stream/topic
public struct MQStreamInfo: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let subjects: [String]
    public let messageCount: UInt64
    public let byteCount: UInt64
    public let firstSequence: UInt64
    public let lastSequence: UInt64
    public let retention: MQRetentionPolicy
    public let storage: MQStorageType
    public let maxAge: TimeInterval?
    public let maxBytes: Int64?
    public let maxMsgSize: Int32?
    public let maxConsumers: Int?
    public let replicas: Int
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        subjects: [String] = [],
        messageCount: UInt64 = 0,
        byteCount: UInt64 = 0,
        firstSequence: UInt64 = 0,
        lastSequence: UInt64 = 0,
        retention: MQRetentionPolicy = .limits,
        storage: MQStorageType = .file,
        maxAge: TimeInterval? = nil,
        maxBytes: Int64? = nil,
        maxMsgSize: Int32? = nil,
        maxConsumers: Int? = nil,
        replicas: Int = 1,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.subjects = subjects
        self.messageCount = messageCount
        self.byteCount = byteCount
        self.firstSequence = firstSequence
        self.lastSequence = lastSequence
        self.retention = retention
        self.storage = storage
        self.maxAge = maxAge
        self.maxBytes = maxBytes
        self.maxMsgSize = maxMsgSize
        self.maxConsumers = maxConsumers
        self.replicas = replicas
        self.createdAt = createdAt
    }
}

// MARK: - Stream Config

/// Configuration for creating a stream
public struct MQStreamConfig: Sendable {
    public let name: String
    public let subjects: [String]
    public let retention: MQRetentionPolicy
    public let storage: MQStorageType
    public let maxAge: TimeInterval?
    public let maxBytes: Int64?
    public let maxMsgSize: Int32?
    public let maxConsumers: Int?
    public let replicas: Int
    public let duplicateWindow: TimeInterval?
    
    public init(
        name: String,
        subjects: [String],
        retention: MQRetentionPolicy = .limits,
        storage: MQStorageType = .file,
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

// MARK: - Consumer Info

/// Information about a consumer
public struct MQConsumerInfo: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let streamName: String
    public let name: String
    public let durable: Bool
    public let pending: UInt64
    public let delivered: UInt64
    public let redelivered: UInt64
    public let ackPolicy: MQAckPolicy
    public let deliverPolicy: MQDeliverPolicy
    public let replayPolicy: MQReplayPolicy
    public let ackWait: TimeInterval
    public let maxDeliver: Int?
    public let filterSubject: String?
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        streamName: String,
        name: String,
        durable: Bool = true,
        pending: UInt64 = 0,
        delivered: UInt64 = 0,
        redelivered: UInt64 = 0,
        ackPolicy: MQAckPolicy = .explicit,
        deliverPolicy: MQDeliverPolicy = .all,
        replayPolicy: MQReplayPolicy = .instant,
        ackWait: TimeInterval = 30,
        maxDeliver: Int? = nil,
        filterSubject: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.streamName = streamName
        self.name = name
        self.durable = durable
        self.pending = pending
        self.delivered = delivered
        self.redelivered = redelivered
        self.ackPolicy = ackPolicy
        self.deliverPolicy = deliverPolicy
        self.replayPolicy = replayPolicy
        self.ackWait = ackWait
        self.maxDeliver = maxDeliver
        self.filterSubject = filterSubject
        self.createdAt = createdAt
    }
}

// MARK: - Consumer Config

/// Configuration for creating a consumer
public struct MQConsumerConfig: Sendable {
    public let name: String
    public let durable: Bool
    public let deliverPolicy: MQDeliverPolicy
    public let ackPolicy: MQAckPolicy
    public let replayPolicy: MQReplayPolicy
    public let ackWait: TimeInterval
    public let maxDeliver: Int?
    public let filterSubject: String?
    public let startSequence: UInt64?
    public let startTime: Date?
    
    public init(
        name: String,
        durable: Bool = true,
        deliverPolicy: MQDeliverPolicy = .all,
        ackPolicy: MQAckPolicy = .explicit,
        replayPolicy: MQReplayPolicy = .instant,
        ackWait: TimeInterval = 30,
        maxDeliver: Int? = nil,
        filterSubject: String? = nil,
        startSequence: UInt64? = nil,
        startTime: Date? = nil
    ) {
        self.name = name
        self.durable = durable
        self.deliverPolicy = deliverPolicy
        self.ackPolicy = ackPolicy
        self.replayPolicy = replayPolicy
        self.ackWait = ackWait
        self.maxDeliver = maxDeliver
        self.filterSubject = filterSubject
        self.startSequence = startSequence
        self.startTime = startTime
    }
}

// MARK: - Enums

/// Retention policy for streams
public enum MQRetentionPolicy: String, Sendable, CaseIterable {
    case limits = "Limits"
    case interest = "Interest"
    case workQueue = "Work Queue"
}

/// Storage type for streams
public enum MQStorageType: String, Sendable, CaseIterable {
    case file = "File"
    case memory = "Memory"
}

/// Acknowledgment policy
public enum MQAckPolicy: String, Sendable, CaseIterable {
    case none = "None"
    case all = "All"
    case explicit = "Explicit"
}

/// Delivery policy for consumers
public enum MQDeliverPolicy: String, Sendable, CaseIterable {
    case all = "All"
    case last = "Last"
    case new = "New"
    case byStartSequence = "By Start Sequence"
    case byStartTime = "By Start Time"
    case lastPerSubject = "Last Per Subject"
}

/// Replay policy for consumers
public enum MQReplayPolicy: String, Sendable, CaseIterable {
    case instant = "Instant"
    case original = "Original"
}

/// Acknowledgment types
public enum MQAckType: String, Sendable, CaseIterable {
    case ack = "Ack"
    case nak = "Nak"
    case term = "Terminate"
    case inProgress = "In Progress"
    
    public var description: String {
        switch self {
        case .ack: return "Acknowledge - Message processed successfully"
        case .nak: return "Negative Ack - Request redelivery"
        case .term: return "Terminate - Do not redeliver"
        case .inProgress: return "In Progress - Still processing"
        }
    }
    
    public var iconName: String {
        switch self {
        case .ack: return "checkmark.circle.fill"
        case .nak: return "arrow.counterclockwise.circle.fill"
        case .term: return "xmark.circle.fill"
        case .inProgress: return "clock.fill"
        }
    }
}
