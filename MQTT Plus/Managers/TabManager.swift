//
//  TabManager.swift
//  MQTT Plus
//
//  Created by Aditya on 10/01/26.
//

import Foundation
import Combine
import CoreData

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
            let tlsEnabled = (server.value(forKey: "useTLS") as? Bool) == true
            let username = server.value(forKey: "username") as? String

            let password: String? = {
                guard let key = server.value(forKey: "passwordKeychainId") as? String,
                      !key.isEmpty else { return nil }
                return try? KeychainService.readString(key: key)
            }()

            let token: String? = {
                guard let key = server.value(forKey: "tokenKeychainId") as? String,
                      !key.isEmpty else { return nil }
                return try? KeychainService.readString(key: key)
            }()

            let options: [String: String] = {
                guard let json = server.value(forKey: "optionsJSON") as? String,
                      !json.isEmpty,
                      let data = json.data(using: .utf8),
                      let decoded = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] else {
                    return [:]
                }
                return decoded
            }()

            await newSession.connectionManager.connect(
                to: server.urlString ?? "",
                providerId: server.providerId,
                serverName: server.name ?? "Unknown",
                serverID: server.id,
                mode: mode,
                username: username,
                password: password,
                token: token,
                tlsEnabledOverride: tlsEnabled,
                options: options
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

