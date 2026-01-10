//
//  MQProviderRegistry.swift
//  PubSub Viewer
//
//  Central registry for all MQ provider implementations
//

import Foundation
import SwiftUI
import Combine

// MARK: - Provider Registry

/// Central registry for message queue providers
/// Enables dynamic discovery and instantiation of MQ clients
@MainActor
public final class MQProviderRegistry: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = MQProviderRegistry()
    
    // MARK: - Properties
    
    private var providers: [String: any MessageQueueProvider.Type] = [:]
    
    @Published public private(set) var availableProviders: [MQProviderInfo] = []
    
    // MARK: - Init
    
    private init() {}
    
    // MARK: - Registration
    
    /// Register a new MQ provider
    /// - Parameter provider: The provider type to register
    public func register<P: MessageQueueProvider>(_ provider: P.Type) {
        providers[P.identifier] = provider
        updateAvailableProviders()
    }
    
    /// Unregister a provider
    /// - Parameter identifier: Provider identifier to remove
    public func unregister(_ identifier: String) {
        providers.removeValue(forKey: identifier)
        updateAvailableProviders()
    }
    
    private func updateAvailableProviders() {
        availableProviders = providers.values.map { provider in
            MQProviderInfo(
                id: provider.identifier,
                displayName: provider.displayName,
                iconName: provider.iconName,
                supportsStreaming: provider.supportsStreaming,
                defaultPort: provider.defaultPort,
                urlScheme: provider.urlScheme
            )
        }.sorted { $0.displayName < $1.displayName }
    }
    
    // MARK: - Provider Access
    
    /// Get a provider by identifier
    /// - Parameter identifier: Provider identifier
    /// - Returns: The provider type, or nil if not found
    public func provider(for identifier: String) -> (any MessageQueueProvider.Type)? {
        providers[identifier]
    }
    
    /// Get provider info by identifier
    /// - Parameter identifier: Provider identifier
    /// - Returns: Provider info, or nil if not found
    public func providerInfo(for identifier: String) -> MQProviderInfo? {
        availableProviders.first { $0.id == identifier }
    }
    
    // MARK: - Client Creation
    
    /// Create a client for the specified provider
    /// - Parameters:
    ///   - identifier: Provider identifier
    ///   - config: Connection configuration
    /// - Returns: A new client instance
    public func createClient(provider identifier: String, config: MQConnectionConfig) -> (any MessageQueueClient)? {
        guard let provider = providers[identifier] else { return nil }
        return provider.createClient(config: config)
    }
    
    /// Create a streaming client for the specified provider
    /// - Parameters:
    ///   - identifier: Provider identifier
    ///   - config: Connection configuration
    /// - Returns: A streaming client, or nil if not supported
    public func createStreamingClient(provider identifier: String, config: MQConnectionConfig) -> (any StreamingClient)? {
        guard let provider = providers[identifier] else { return nil }
        return provider.createStreamingClient(config: config)
    }
}

// MARK: - Provider Info Extension

public extension MQProviderInfo {
    init(
        id: String,
        displayName: String,
        iconName: String,
        supportsStreaming: Bool,
        defaultPort: Int,
        urlScheme: String
    ) {
        self.id = id
        self.displayName = displayName
        self.iconName = iconName
        self.supportsStreaming = supportsStreaming
        self.defaultPort = defaultPort
        self.urlScheme = urlScheme
    }
}

// MARK: - App Registration

/// Call this at app startup to register all providers
public func registerAllProviders() {
    let registry = MQProviderRegistry.shared
    
    // Register NATS provider
    // registry.register(NatsProvider.self)
    
    // Future providers:
    // registry.register(KafkaProvider.self)
    // registry.register(RabbitMQProvider.self)
    // registry.register(RedisProvider.self)
    // registry.register(MQTTProvider.self)
}
