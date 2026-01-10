//
//  MessageQueueClient.swift
//  MQTT Plus
//
//  Core protocol for all message queue clients
//

import Foundation
import Combine

// MARK: - Connection State

/// Unified connection state for all MQ clients
public enum MQConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case error(String)
    
    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    
    public var description: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting..."
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Connection Configuration

/// Configuration for connecting to a message queue
public struct MQConnectionConfig: Sendable {
    public let url: String
    public let name: String
    public let username: String?
    public let password: String?
    public let token: String?
    public let tlsEnabled: Bool
    public let options: [String: String]
    
    public init(
        url: String,
        name: String,
        username: String? = nil,
        password: String? = nil,
        token: String? = nil,
        tlsEnabled: Bool = false,
        options: [String: String] = [:]
    ) {
        self.url = url
        self.name = name
        self.username = username
        self.password = password
        self.token = token
        self.tlsEnabled = tlsEnabled
        self.options = options
    }
}

// MARK: - Message Queue Client Protocol

/// Base protocol for all message queue clients
/// Supports basic pub/sub operations
public protocol MessageQueueClient: AnyObject, Sendable {
    /// Current connection state
    var state: MQConnectionState { get }
    
    /// Publisher for connection state changes
    var statePublisher: AnyPublisher<MQConnectionState, Never> { get }
    
    /// Connection configuration
    var config: MQConnectionConfig { get }
    
    // MARK: - Connection
    
    /// Connect to the message queue server
    func connect() async throws
    
    /// Disconnect from the server
    func disconnect() async
    
    // MARK: - Basic Pub/Sub
    
    /// Publish a message to a subject/topic
    /// - Parameters:
    ///   - message: The message to publish
    ///   - subject: The subject/topic to publish to
    func publish(_ message: MQMessage, to subject: String) async throws
    
    /// Subscribe to messages matching a pattern
    /// - Parameter pattern: Subject pattern (supports wildcards)
    /// - Returns: AsyncStream of incoming messages
    func subscribe(to pattern: String) async throws -> AsyncStream<MQMessage>
    
    /// Unsubscribe from a pattern
    /// - Parameter pattern: The pattern to unsubscribe from
    func unsubscribe(from pattern: String) async throws
    
    // MARK: - Request-Reply (Optional)
    
    /// Send a request and wait for a reply
    /// - Parameters:
    ///   - message: The request message
    ///   - subject: The subject to send to
    ///   - timeout: Maximum time to wait for reply
    /// - Returns: The reply message, or nil if timeout
    func request(_ message: MQMessage, to subject: String, timeout: Duration) async throws -> MQMessage?
}

// MARK: - Default Implementation

public extension MessageQueueClient {
    /// Default implementation throws - not all MQ systems support request-reply
    func request(_ message: MQMessage, to subject: String, timeout: Duration) async throws -> MQMessage? {
        throw MQError.operationNotSupported("Request-reply not supported by this provider")
    }
}

// MARK: - MQ Error

/// Errors that can occur in MQ operations
public enum MQError: Error, LocalizedError {
    case connectionFailed(String)
    case notConnected
    case subscriptionFailed(String)
    case publishFailed(String)
    case operationNotSupported(String)
    case timeout
    case invalidConfiguration(String)
    case providerError(String)
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .notConnected: return "Not connected to server"
        case .subscriptionFailed(let msg): return "Subscription failed: \(msg)"
        case .publishFailed(let msg): return "Publish failed: \(msg)"
        case .operationNotSupported(let msg): return "Operation not supported: \(msg)"
        case .timeout: return "Operation timed out"
        case .invalidConfiguration(let msg): return "Invalid configuration: \(msg)"
        case .providerError(let msg): return "Provider error: \(msg)"
        }
    }
}
