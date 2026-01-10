//
//  Session.swift
//  MQTT Plus
//
//  Created by Aditya on 10/01/26.
//

import Foundation
import Combine

@MainActor
class Session: Identifiable, ObservableObject {
    let id: UUID
    let name: String
    let serverID: UUID? // Optional, in case we have ad-hoc connections later
    
    @Published var connectionManager: ConnectionManager
    @Published var mode: ConnectionMode
    
    init(server: ServerConfig, mode: ConnectionMode = .core) {
        self.id = UUID()
        self.name = server.name ?? "Unknown Server"
        self.serverID = server.id
        self.mode = mode
        self.connectionManager = ConnectionManager() // New instance for this session
    }
    
    // For ad-hoc or testing
    init(name: String, connectionManager: ConnectionManager? = nil) {
        self.id = UUID()
        self.name = name
        self.serverID = nil
        self.mode = .core
        self.connectionManager = connectionManager ?? ConnectionManager()
    }
    
    func refresh() {
        connectionManager.refresh()
    }
}
