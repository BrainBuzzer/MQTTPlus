//
//  NatsProvider.swift
//  MQTT Plus
//
//  NATS provider implementation using C FFI
//

import Foundation
import Combine

// MARK: - NATS Provider

/// NATS message queue provider
/// Uses nats.c library via C FFI for Core NATS and JetStream support
public struct NatsProvider: MessageQueueProvider {
    
    public static let identifier = "nats"
    public static let displayName = "NATS"
    public static let iconName = "antenna.radiowaves.left.and.right"
    public static let supportsStreaming = true
    public static let defaultPort = 4222
    public static let urlScheme = "nats"
    
    public static func createClient(config: MQConnectionConfig) -> any MessageQueueClient {
        return NatsCClient(config: config)
    }
    
    public static func createStreamingClient(config: MQConnectionConfig) -> (any StreamingClient)? {
        return NatsCClient(config: config)
    }
    
    public static func validateURL(_ url: String) -> Bool {
        url.hasPrefix("nats://") || url.hasPrefix("tls://")
    }
}
