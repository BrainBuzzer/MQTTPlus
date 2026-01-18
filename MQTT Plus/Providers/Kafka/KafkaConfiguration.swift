//
//  KafkaConfiguration.swift
//  MQTT Plus
//
//  Comprehensive Kafka configuration supporting all security protocols and SASL mechanisms
//

import Foundation

public enum KafkaSecurityProtocol: String, CaseIterable, Codable, Sendable {
    case plaintext = "PLAINTEXT"
    case ssl = "SSL"
    case saslPlaintext = "SASL_PLAINTEXT"
    case saslSSL = "SASL_SSL"
    
    var displayName: String {
        switch self {
        case .plaintext: return "Plaintext (No Security)"
        case .ssl: return "SSL/TLS"
        case .saslPlaintext: return "SASL (No Encryption)"
        case .saslSSL: return "SASL + SSL/TLS"
        }
    }
    
    var requiresSASL: Bool {
        self == .saslPlaintext || self == .saslSSL
    }
    
    var requiresSSL: Bool {
        self == .ssl || self == .saslSSL
    }
}

public enum KafkaSASLMechanism: String, CaseIterable, Codable, Sendable {
    case plain = "PLAIN"
    case scramSHA256 = "SCRAM-SHA-256"
    case scramSHA512 = "SCRAM-SHA-512"
    case oauthbearer = "OAUTHBEARER"
    case gssapi = "GSSAPI"
    
    var displayName: String {
        switch self {
        case .plain: return "PLAIN (Username/Password)"
        case .scramSHA256: return "SCRAM-SHA-256"
        case .scramSHA512: return "SCRAM-SHA-512"
        case .oauthbearer: return "OAuth Bearer Token"
        case .gssapi: return "GSSAPI (Kerberos)"
        }
    }
    
    var requiresUsernamePassword: Bool {
        switch self {
        case .plain, .scramSHA256, .scramSHA512: return true
        case .oauthbearer, .gssapi: return false
        }
    }
}

public struct KafkaSSLConfig: Codable, Sendable {
    public var caLocation: String?
    public var certificateLocation: String?
    public var keyLocation: String?
    public var keyPassword: String?
    public var enableHostnameVerification: Bool
    
    public init(
        caLocation: String? = nil,
        certificateLocation: String? = nil,
        keyLocation: String? = nil,
        keyPassword: String? = nil,
        enableHostnameVerification: Bool = true
    ) {
        self.caLocation = caLocation
        self.certificateLocation = certificateLocation
        self.keyLocation = keyLocation
        self.keyPassword = keyPassword
        self.enableHostnameVerification = enableHostnameVerification
    }
    
    public static let `default` = KafkaSSLConfig()
}

public struct KafkaOAuthConfig: Codable, Sendable {
    public var tokenEndpoint: String
    public var clientId: String
    public var clientSecret: String
    public var scope: String?
    public var extensions: [String: String]?
    
    public init(
        tokenEndpoint: String = "",
        clientId: String = "",
        clientSecret: String = "",
        scope: String? = nil,
        extensions: [String: String]? = nil
    ) {
        self.tokenEndpoint = tokenEndpoint
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.scope = scope
        self.extensions = extensions
    }
}

public struct KafkaProducerConfig: Codable, Sendable {
    public enum Acks: String, CaseIterable, Codable, Sendable {
        case none = "0"
        case leader = "1"
        case all = "-1"
        
        var displayName: String {
            switch self {
            case .none: return "None (0)"
            case .leader: return "Leader (1)"
            case .all: return "All (-1)"
            }
        }
    }
    
    public enum CompressionType: String, CaseIterable, Codable, Sendable {
        case none = "none"
        case gzip = "gzip"
        case snappy = "snappy"
        case lz4 = "lz4"
        case zstd = "zstd"
    }
    
    public var acks: Acks
    public var retries: Int
    public var enableIdempotence: Bool
    public var compressionType: CompressionType
    public var lingerMs: Int
    public var batchSize: Int
    public var deliveryTimeoutMs: Int
    public var requestTimeoutMs: Int
    
    public init(
        acks: Acks = .all,
        retries: Int = 2147483647,
        enableIdempotence: Bool = true,
        compressionType: CompressionType = .none,
        lingerMs: Int = 5,
        batchSize: Int = 16384,
        deliveryTimeoutMs: Int = 120000,
        requestTimeoutMs: Int = 30000
    ) {
        self.acks = acks
        self.retries = retries
        self.enableIdempotence = enableIdempotence
        self.compressionType = compressionType
        self.lingerMs = lingerMs
        self.batchSize = batchSize
        self.deliveryTimeoutMs = deliveryTimeoutMs
        self.requestTimeoutMs = requestTimeoutMs
    }
    
    public static let `default` = KafkaProducerConfig()
}

public struct KafkaConsumerConfig: Codable, Sendable {
    public enum AutoOffsetReset: String, CaseIterable, Codable, Sendable {
        case earliest = "earliest"
        case latest = "latest"
        case none = "none"
    }
    
    public var groupId: String
    public var autoOffsetReset: AutoOffsetReset
    public var enableAutoCommit: Bool
    public var autoCommitIntervalMs: Int
    public var sessionTimeoutMs: Int
    public var heartbeatIntervalMs: Int
    public var maxPollRecords: Int
    public var maxPollIntervalMs: Int
    public var fetchMinBytes: Int
    public var fetchMaxBytes: Int
    
    public init(
        groupId: String = "mqtt-plus",
        autoOffsetReset: AutoOffsetReset = .latest,
        enableAutoCommit: Bool = true,
        autoCommitIntervalMs: Int = 5000,
        sessionTimeoutMs: Int = 45000,
        heartbeatIntervalMs: Int = 3000,
        maxPollRecords: Int = 500,
        maxPollIntervalMs: Int = 300000,
        fetchMinBytes: Int = 1,
        fetchMaxBytes: Int = 52428800
    ) {
        self.groupId = groupId
        self.autoOffsetReset = autoOffsetReset
        self.enableAutoCommit = enableAutoCommit
        self.autoCommitIntervalMs = autoCommitIntervalMs
        self.sessionTimeoutMs = sessionTimeoutMs
        self.heartbeatIntervalMs = heartbeatIntervalMs
        self.maxPollRecords = maxPollRecords
        self.maxPollIntervalMs = maxPollIntervalMs
        self.fetchMinBytes = fetchMinBytes
        self.fetchMaxBytes = fetchMaxBytes
    }
    
    public static let `default` = KafkaConsumerConfig()
}

public struct KafkaConfiguration: Codable, Sendable {
    public var securityProtocol: KafkaSecurityProtocol
    public var saslMechanism: KafkaSASLMechanism?
    public var sslConfig: KafkaSSLConfig
    public var oauthConfig: KafkaOAuthConfig?
    public var producerConfig: KafkaProducerConfig
    public var consumerConfig: KafkaConsumerConfig
    public var clientId: String
    public var connectionTimeoutMs: Int
    public var metadataMaxAgeMs: Int
    
    public init(
        securityProtocol: KafkaSecurityProtocol = .plaintext,
        saslMechanism: KafkaSASLMechanism? = nil,
        sslConfig: KafkaSSLConfig = .default,
        oauthConfig: KafkaOAuthConfig? = nil,
        producerConfig: KafkaProducerConfig = .default,
        consumerConfig: KafkaConsumerConfig = .default,
        clientId: String = "mqtt-plus-client",
        connectionTimeoutMs: Int = 10000,
        metadataMaxAgeMs: Int = 300000
    ) {
        self.securityProtocol = securityProtocol
        self.saslMechanism = saslMechanism
        self.sslConfig = sslConfig
        self.oauthConfig = oauthConfig
        self.producerConfig = producerConfig
        self.consumerConfig = consumerConfig
        self.clientId = clientId
        self.connectionTimeoutMs = connectionTimeoutMs
        self.metadataMaxAgeMs = metadataMaxAgeMs
    }
    
    public static let `default` = KafkaConfiguration()
    
    public static let confluentCloud = KafkaConfiguration(
        securityProtocol: .saslSSL,
        saslMechanism: .plain,
        producerConfig: KafkaProducerConfig(
            acks: .all,
            enableIdempotence: true,
            compressionType: .lz4
        )
    )
    
    public func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    public static func fromJSON(_ json: String) -> KafkaConfiguration? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(KafkaConfiguration.self, from: data)
    }
}

extension KafkaConfiguration {
    func applyTo(config: OpaquePointer) {
        rd_kafka_conf_set(config, "client.id", clientId, nil, 0)
        rd_kafka_conf_set(config, "security.protocol", securityProtocol.rawValue, nil, 0)
        
        if securityProtocol.requiresSASL, let mechanism = saslMechanism {
            rd_kafka_conf_set(config, "sasl.mechanism", mechanism.rawValue, nil, 0)
        }
        
        if securityProtocol.requiresSSL {
            if sslConfig.enableHostnameVerification {
                rd_kafka_conf_set(config, "ssl.endpoint.identification.algorithm", "https", nil, 0)
            } else {
                rd_kafka_conf_set(config, "ssl.endpoint.identification.algorithm", "none", nil, 0)
            }
            
            if let ca = sslConfig.caLocation, !ca.isEmpty {
                rd_kafka_conf_set(config, "ssl.ca.location", ca, nil, 0)
            }
            if let cert = sslConfig.certificateLocation, !cert.isEmpty {
                rd_kafka_conf_set(config, "ssl.certificate.location", cert, nil, 0)
            }
            if let key = sslConfig.keyLocation, !key.isEmpty {
                rd_kafka_conf_set(config, "ssl.key.location", key, nil, 0)
            }
            if let keyPass = sslConfig.keyPassword, !keyPass.isEmpty {
                rd_kafka_conf_set(config, "ssl.key.password", keyPass, nil, 0)
            }
        }
        
        rd_kafka_conf_set(config, "socket.connection.setup.timeout.ms", String(connectionTimeoutMs), nil, 0)
        rd_kafka_conf_set(config, "metadata.max.age.ms", String(metadataMaxAgeMs), nil, 0)
    }
    
    func applyProducerConfig(to config: OpaquePointer) {
        rd_kafka_conf_set(config, "acks", producerConfig.acks.rawValue, nil, 0)
        rd_kafka_conf_set(config, "retries", String(producerConfig.retries), nil, 0)
        rd_kafka_conf_set(config, "enable.idempotence", producerConfig.enableIdempotence ? "true" : "false", nil, 0)
        rd_kafka_conf_set(config, "compression.type", producerConfig.compressionType.rawValue, nil, 0)
        rd_kafka_conf_set(config, "linger.ms", String(producerConfig.lingerMs), nil, 0)
        rd_kafka_conf_set(config, "batch.size", String(producerConfig.batchSize), nil, 0)
        rd_kafka_conf_set(config, "delivery.timeout.ms", String(producerConfig.deliveryTimeoutMs), nil, 0)
        rd_kafka_conf_set(config, "request.timeout.ms", String(producerConfig.requestTimeoutMs), nil, 0)
    }
    
    func applyConsumerConfig(to config: OpaquePointer) {
        rd_kafka_conf_set(config, "group.id", consumerConfig.groupId, nil, 0)
        rd_kafka_conf_set(config, "auto.offset.reset", consumerConfig.autoOffsetReset.rawValue, nil, 0)
        rd_kafka_conf_set(config, "enable.auto.commit", consumerConfig.enableAutoCommit ? "true" : "false", nil, 0)
        rd_kafka_conf_set(config, "auto.commit.interval.ms", String(consumerConfig.autoCommitIntervalMs), nil, 0)
        rd_kafka_conf_set(config, "session.timeout.ms", String(consumerConfig.sessionTimeoutMs), nil, 0)
        rd_kafka_conf_set(config, "heartbeat.interval.ms", String(consumerConfig.heartbeatIntervalMs), nil, 0)
        rd_kafka_conf_set(config, "max.poll.records", String(consumerConfig.maxPollRecords), nil, 0)
        rd_kafka_conf_set(config, "max.poll.interval.ms", String(consumerConfig.maxPollIntervalMs), nil, 0)
        rd_kafka_conf_set(config, "fetch.min.bytes", String(consumerConfig.fetchMinBytes), nil, 0)
        rd_kafka_conf_set(config, "fetch.max.bytes", String(consumerConfig.fetchMaxBytes), nil, 0)
    }
}
