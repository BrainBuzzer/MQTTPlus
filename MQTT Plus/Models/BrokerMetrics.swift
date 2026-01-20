//
//  BrokerMetrics.swift
//  MQTT Plus
//
//  Unified data models for broker-specific health metrics
//  Supports NATS (JetStream), Redis, and Kafka backends
//

import Foundation

// MARK: - Broker Type

/// Supported message broker backends
public enum BrokerType: String, CaseIterable, Sendable, Identifiable {
    case nats
    case redis
    case kafka
    case rabbitmq
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .nats: return "NATS"
        case .redis: return "Redis"
        case .kafka: return "Kafka"
        case .rabbitmq: return "RabbitMQ"
        }
    }
    
    public var iconName: String {
        switch self {
        case .nats: return "bolt.horizontal.circle.fill"
        case .redis: return "memorychip.fill"
        case .kafka: return "arrow.trianglehead.branch"
        case .rabbitmq: return "arrow.trianglehead.2.clockwise.rotate.90"
        }
    }
    
    /// Detect broker type from URL string
    public static func detect(from url: String) -> BrokerType {
        let lowercased = url.lowercased()
        if lowercased.contains("redis") || lowercased.hasPrefix("redis://") || lowercased.contains(":6379") {
            return .redis
        } else if lowercased.contains("kafka") || lowercased.contains(":9092") {
            return .kafka
        } else if lowercased.contains("amqp") || lowercased.hasPrefix("amqp://") || lowercased.contains(":5672") {
            return .rabbitmq
        } else {
            return .nats
        }
    }
}

// MARK: - Health Status

/// Health status indicator for broker metrics
public enum HealthStatus: String, Sendable {
    case healthy
    case warning
    case critical
    
    public var color: String {
        switch self {
        case .healthy: return "green"
        case .warning: return "orange"
        case .critical: return "red"
        }
    }
    
    public var iconName: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        }
    }
    
    public var description: String {
        switch self {
        case .healthy: return "All systems operational"
        case .warning: return "Degraded performance"
        case .critical: return "Critical issues detected"
        }
    }
}

// MARK: - Metric History Point

/// Single data point for sparkline charts
public struct MetricHistoryPoint: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let value: Double
    
    public init(timestamp: Date = Date(), value: Double) {
        self.timestamp = timestamp
        self.value = value
    }
}

// MARK: - NATS Metrics

/// NATS JetStream specific metrics
public struct NatsMetrics: Sendable, Equatable {
    public let streamName: String
    public let storageType: MQStorageType
    public let msgCount: UInt64
    public let byteCount: UInt64
    public let consumerLag: UInt64
    public let slowConsumerCount: Int
    
    public init(
        streamName: String = "default",
        storageType: MQStorageType = .file,
        msgCount: UInt64 = 0,
        byteCount: UInt64 = 0,
        consumerLag: UInt64 = 0,
        slowConsumerCount: Int = 0
    ) {
        self.streamName = streamName
        self.storageType = storageType
        self.msgCount = msgCount
        self.byteCount = byteCount
        self.consumerLag = consumerLag
        self.slowConsumerCount = slowConsumerCount
    }
    
    /// Compute health status based on metrics
    public var healthStatus: HealthStatus {
        if slowConsumerCount > 5 || consumerLag > 10000 {
            return .critical
        } else if slowConsumerCount > 0 || consumerLag > 1000 {
            return .warning
        }
        return .healthy
    }
    
    /// Human-readable byte count
    public var byteCountFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .binary)
    }
    
    /// Summary for collapsed view
    public var healthSummary: String {
        "\(msgCount.formatted()) msgs • \(byteCountFormatted) • Lag: \(consumerLag.formatted())"
    }
}

// MARK: - Redis Metrics

/// Redis specific metrics
public struct RedisMetrics: Sendable, Equatable {
    public let usedMemoryHuman: String
    public let usedMemoryBytes: UInt64
    public let instantaneousOpsPerSec: Int
    public let connectedClients: Int
    public let memFragmentationRatio: Double
    public let totalNetInputBytes: UInt64
    
    public init(
        usedMemoryHuman: String = "0B",
        usedMemoryBytes: UInt64 = 0,
        instantaneousOpsPerSec: Int = 0,
        connectedClients: Int = 0,
        memFragmentationRatio: Double = 1.0,
        totalNetInputBytes: UInt64 = 0
    ) {
        self.usedMemoryHuman = usedMemoryHuman
        self.usedMemoryBytes = usedMemoryBytes
        self.instantaneousOpsPerSec = instantaneousOpsPerSec
        self.connectedClients = connectedClients
        self.memFragmentationRatio = memFragmentationRatio
        self.totalNetInputBytes = totalNetInputBytes
    }
    
    /// Compute health status based on metrics
    public var healthStatus: HealthStatus {
        if memFragmentationRatio > 2.0 || connectedClients > 10000 {
            return .critical
        } else if memFragmentationRatio > 1.5 || connectedClients > 5000 {
            return .warning
        }
        return .healthy
    }
    
    /// Human-readable network input
    public var netInputFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalNetInputBytes), countStyle: .binary)
    }
    
    /// Summary for collapsed view
    public var healthSummary: String {
        "\(usedMemoryHuman) • \(instantaneousOpsPerSec.formatted()) ops/s • Frag: \(String(format: "%.2f", memFragmentationRatio))"
    }
}

// MARK: - Kafka Metrics

/// Kafka specific metrics
public struct KafkaMetrics: Sendable, Equatable {
    public let partitionCount: Int
    public let underReplicatedPartitions: Int
    public let consumerGroupLag: Int64
    public let isrShrinkRate: Double
    public let logEndOffset: Int64
    
    public init(
        partitionCount: Int = 0,
        underReplicatedPartitions: Int = 0,
        consumerGroupLag: Int64 = 0,
        isrShrinkRate: Double = 0.0,
        logEndOffset: Int64 = 0
    ) {
        self.partitionCount = partitionCount
        self.underReplicatedPartitions = underReplicatedPartitions
        self.consumerGroupLag = consumerGroupLag
        self.isrShrinkRate = isrShrinkRate
        self.logEndOffset = logEndOffset
    }
    
    /// Compute health status based on metrics
    public var healthStatus: HealthStatus {
        if underReplicatedPartitions > 0 || isrShrinkRate > 0.1 {
            return .critical
        } else if consumerGroupLag > 10000 {
            return .warning
        }
        return .healthy
    }
    
    /// Summary for collapsed view
    public var healthSummary: String {
        "\(partitionCount) partitions • URPs: \(underReplicatedPartitions) • Lag: \(consumerGroupLag.formatted())"
    }
}

// MARK: - Unified Broker Metrics

/// Unified wrapper containing metrics for the active broker type
public struct BrokerMetrics: Sendable {
    public let type: BrokerType
    public let nats: NatsMetrics?
    public let redis: RedisMetrics?
    public let kafka: KafkaMetrics?
    public let rabbitmq: RabbitMQMetrics?
    public let timestamp: Date
    
    public init(
        type: BrokerType,
        nats: NatsMetrics? = nil,
        redis: RedisMetrics? = nil,
        kafka: KafkaMetrics? = nil,
        rabbitmq: RabbitMQMetrics? = nil,
        timestamp: Date = Date()
    ) {
        self.type = type
        self.nats = nats
        self.redis = redis
        self.kafka = kafka
        self.rabbitmq = rabbitmq
        self.timestamp = timestamp
    }
    
    /// Overall health status based on active broker
    public var healthStatus: HealthStatus {
        switch type {
        case .nats: return nats?.healthStatus ?? .healthy
        case .redis: return redis?.healthStatus ?? .healthy
        case .kafka: return kafka?.healthStatus ?? .healthy
        case .rabbitmq: return rabbitmq?.healthStatus ?? .healthy
        }
    }
    
    /// Summary text for collapsed view
    public var healthSummary: String {
        switch type {
        case .nats: return nats?.healthSummary ?? "No data"
        case .redis: return redis?.healthSummary ?? "No data"
        case .kafka: return kafka?.healthSummary ?? "No data"
        case .rabbitmq: return rabbitmq?.healthSummary ?? "No data"
        }
    }
    
    // MARK: - Factory Methods
    
    public static func nats(_ metrics: NatsMetrics) -> BrokerMetrics {
        BrokerMetrics(type: .nats, nats: metrics)
    }
    
    public static func redis(_ metrics: RedisMetrics) -> BrokerMetrics {
        BrokerMetrics(type: .redis, redis: metrics)
    }
    
    public static func kafka(_ metrics: KafkaMetrics) -> BrokerMetrics {
        BrokerMetrics(type: .kafka, kafka: metrics)
    }
    
    public static func rabbitmq(_ metrics: RabbitMQMetrics) -> BrokerMetrics {
        BrokerMetrics(type: .rabbitmq, rabbitmq: metrics)
    }
}

// MARK: - Metric History Container

/// Container for metric history used in sparkline charts
public struct MetricHistory: Sendable {
    public private(set) var points: [MetricHistoryPoint]
    public let maxPoints: Int
    
    public init(maxPoints: Int = 60) {
        self.points = []
        self.maxPoints = maxPoints
    }
    
    public mutating func append(_ value: Double) {
        let point = MetricHistoryPoint(value: value)
        points.append(point)
        
        // Keep only the last maxPoints
        if points.count > maxPoints {
            points.removeFirst(points.count - maxPoints)
        }
    }
    
    public var latestValue: Double {
        points.last?.value ?? 0
    }
    
    public var minValue: Double {
        points.map(\.value).min() ?? 0
    }
    
    public var maxValue: Double {
        points.map(\.value).max() ?? 0
    }
}
