//
//  ConnectionMode.swift
//  PubSub Viewer
//

import Foundation

/// Connection mode selector for NATS sessions.
enum ConnectionMode: String, Codable, CaseIterable {
    case core = "Pub/Sub"
    case jetstream = "JetStream"

    var description: String { rawValue }
}

