//
//  MessageQueueProvider.swift
//  PubSub Viewer
//
//  Provider protocol for registering MQ implementations
//

import Foundation
import SwiftUI

// MARK: - Provider Protocol

/// Protocol for MQ provider implementations
/// Each MQ system (NATS, Kafka, etc.) implements this to register itself
public protocol MessageQueueProvider {
    /// Unique identifier for this provider
    static var identifier: String { get }
    
    /// Human-readable display name
    static var displayName: String { get }
    
    /// SF Symbol name for the provider icon
    static var iconName: String { get }
    
    /// Whether this provider supports streaming/persistence
    static var supportsStreaming: Bool { get }
    
    /// Default port for this MQ system
    static var defaultPort: Int { get }
    
    /// URL scheme (e.g., "nats", "kafka", "amqp")
    static var urlScheme: String { get }
    
    /// Create a client instance with the given configuration
    /// - Parameter config: Connection configuration
    /// - Returns: A new client instance
    static func createClient(config: MQConnectionConfig) -> any MessageQueueClient
    
    /// Create a streaming client if supported
    /// - Parameter config: Connection configuration
    /// - Returns: A streaming client, or nil if not supported
    static func createStreamingClient(config: MQConnectionConfig) -> (any StreamingClient)?
    
    /// Validate a connection URL
    /// - Parameter url: URL string to validate
    /// - Returns: True if valid for this provider
    static func validateURL(_ url: String) -> Bool
}

// MARK: - Default Implementations

public extension MessageQueueProvider {
    static func createStreamingClient(config: MQConnectionConfig) -> (any StreamingClient)? {
        // Default: check if the regular client also conforms to StreamingClient
        let client = createClient(config: config)
        return client as? (any StreamingClient)
    }
    
    static func validateURL(_ url: String) -> Bool {
        // Default validation: check scheme
        return url.hasPrefix("\(urlScheme)://")
    }
}

// MARK: - Provider Info

/// Static information about a provider (for UI display)
public struct MQProviderInfo: Identifiable, Hashable {
    public let id: String
    public let displayName: String
    public let iconName: String
    public let supportsStreaming: Bool
    public let defaultPort: Int
    public let urlScheme: String
    
    public init<P: MessageQueueProvider>(_ provider: P.Type) {
        self.id = P.identifier
        self.displayName = P.displayName
        self.iconName = P.iconName
        self.supportsStreaming = P.supportsStreaming
        self.defaultPort = P.defaultPort
        self.urlScheme = P.urlScheme
    }
    
    public var defaultURL: String {
        "\(urlScheme)://localhost:\(defaultPort)"
    }
}

// MARK: - Provider Icon View

/// SwiftUI view for provider icon
public struct MQProviderIcon: View {
    let info: MQProviderInfo
    let size: CGFloat
    
    public init(info: MQProviderInfo, size: CGFloat = 24) {
        self.info = info
        self.size = size
    }
    
    public var body: some View {
        Image(systemName: info.iconName)
            .font(.system(size: size))
            .foregroundStyle(iconColor)
    }
    
    private var iconColor: Color {
        switch info.id {
        case "nats": return .purple
        case "kafka": return .orange
        case "rabbitmq": return .orange
        case "redis": return .red
        case "mqtt": return .green
        default: return .blue
        }
    }
}
