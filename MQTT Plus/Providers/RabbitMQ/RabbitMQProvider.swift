//
//  RabbitMQProvider.swift
//  MQTT Plus
//
//  RabbitMQ provider implementation using AMQP 0-9-1 protocol
//

import Foundation

// MARK: - RabbitMQ Provider

/// RabbitMQ message queue provider
/// Uses pure Swift implementation over TCP (Network.framework)
public struct RabbitMQProvider: MessageQueueProvider {
    
    public static let identifier = "rabbitmq"
    public static let displayName = "RabbitMQ"
    public static let iconName = "icon_rabbitmq"
    public static let supportsStreaming = false
    public static let defaultPort = 5672
    public static let urlScheme = "amqp"
    
    public static func createClient(config: MQConnectionConfig) -> any MessageQueueClient {
        return RabbitMQClient(config: config)
    }
    
    public static func createStreamingClient(config: MQConnectionConfig) -> (any StreamingClient)? {
        // RabbitMQ Streams not implemented yet
        nil
    }
    
    public static func validateURL(_ url: String) -> Bool {
        url.hasPrefix("amqp://") || url.hasPrefix("amqps://")
    }
}
