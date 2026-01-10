//
//  KafkaProvider.swift
//  MQTT Plus
//
//  Kafka provider implementation using native Swift Kafka protocol
//

import Foundation
import Combine

// MARK: - Kafka Provider

/// Apache Kafka message queue provider
/// Uses pure Swift implementation over TCP (Network.framework)
public struct KafkaProvider: MessageQueueProvider {
    
    public static let identifier = "kafka"
    public static let displayName = "Kafka"
    public static let iconName = "arrow.triangle.pull"
    public static let supportsStreaming = true
    public static let defaultPort = 9092
    public static let urlScheme = "kafka"
    
    public static func createClient(config: MQConnectionConfig) -> any MessageQueueClient {
        return KafkaClient(config: config)
    }
    
    public static func createStreamingClient(config: MQConnectionConfig) -> (any StreamingClient)? {
        return KafkaClient(config: config)
    }
    
    public static func validateURL(_ url: String) -> Bool {
        // Kafka bootstrap servers: kafka://host:port or just host:port
        url.hasPrefix("kafka://") || url.contains(":")
    }
}
