//
//  RedisProvider.swift
//  MQTT Plus
//
//  Redis provider implementation (Pub/Sub)
//

import Foundation

public struct RedisProvider: MessageQueueProvider {
    public static let identifier = "redis"
    public static let displayName = "Redis"
    public static let iconName = "cylinder.fill"
    public static let supportsStreaming = false
    public static let defaultPort = 6379
    public static let urlScheme = "redis"

    public static func createClient(config: MQConnectionConfig) -> any MessageQueueClient {
        RedisClient(config: config)
    }

    public static func createStreamingClient(config: MQConnectionConfig) -> (any StreamingClient)? {
        nil
    }

    public static func validateURL(_ url: String) -> Bool {
        url.hasPrefix("redis://") || url.hasPrefix("rediss://")
    }
}

