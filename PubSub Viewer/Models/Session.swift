//
//  Session.swift
//  PubSub Viewer
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
    
    @Published var natsManager: NatsManager
    
    init(server: ServerConfig) {
        self.id = UUID()
        self.name = server.name ?? "Unknown Server"
        self.serverID = server.id
        self.natsManager = NatsManager() // New instance for this session
    }
    
    // For ad-hoc or testing
    init(name: String, natsManager: NatsManager? = nil) {
        self.id = UUID()
        self.name = name
        self.serverID = nil
        self.natsManager = natsManager ?? NatsManager()
    }
}
