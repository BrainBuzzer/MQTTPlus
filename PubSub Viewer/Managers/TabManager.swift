//
//  TabManager.swift
//  PubSub Viewer
//
//  Created by Aditya on 10/01/26.
//

import Foundation
import Combine

@MainActor
class TabManager: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var selectedSessionID: UUID?
    
    var selectedSession: Session? {
        guard let id = selectedSessionID else { return nil }
        return sessions.first(where: { $0.id == id })
    }
    
    func openTab(for server: ServerConfig, mode: ConnectionMode = .core) {
        // Check if already open
        if let existingSession = sessions.first(where: { $0.serverID == server.id }) {
            selectedSessionID = existingSession.id
            return
        }
        
        // Create new session
        let newSession = Session(server: server)
        sessions.append(newSession)
        selectedSessionID = newSession.id
        
        // Auto-connect
        Task {
            await newSession.connectionManager.connect(
                to: server.urlString ?? "",
                serverName: server.name ?? "Unknown",
                serverID: server.id,
                mode: mode
            )
        }
    }
    
    func closeTab(id: UUID) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions[sessionIndex]
        
        // Disconnect
        session.connectionManager.disconnect()
        
        // Remove
        sessions.remove(at: sessionIndex)
        
        // Update selection if needed
        if selectedSessionID == id {
            if sessions.isEmpty {
                selectedSessionID = nil
            } else {
                // Select the one to the left, or the first one
                let newIndex = max(0, sessionIndex - 1)
                selectedSessionID = sessions[newIndex].id
            }
        }
    }
    
    func selectTab(id: UUID) {
        selectedSessionID = id
    }
    
    func session(for serverID: UUID?) -> Session? {
        guard let serverID = serverID else { return nil }
        return sessions.first(where: { $0.serverID == serverID })
    }
}
