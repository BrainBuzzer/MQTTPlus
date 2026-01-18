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
        // Allow multiple sessions for the same server
        // if let existingSession = sessions.first(where: { $0.serverID == server.id }) {
        //     selectedSessionID = existingSession.id
        //     return
        // }
        
        // Create new session
        let newSession = Session(server: server, mode: mode)
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
        
        updateObserving()
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
        
        updateObserving()
    }
    
    func selectTab(id: UUID) {
        selectedSessionID = id
        if let session = sessions.first(where: { $0.id == id }) {
            session.markAsRead()
        }
    }
    
    func selectPreviousTab() {
        guard !sessions.isEmpty else { return }
        guard let currentID = selectedSessionID,
              let currentIndex = sessions.firstIndex(where: { $0.id == currentID }) else {
            selectedSessionID = sessions.first?.id
            return
        }
        let newIndex = currentIndex > 0 ? currentIndex - 1 : sessions.count - 1
        selectedSessionID = sessions[newIndex].id
    }
    
    func selectNextTab() {
        guard !sessions.isEmpty else { return }
        guard let currentID = selectedSessionID,
              let currentIndex = sessions.firstIndex(where: { $0.id == currentID }) else {
            selectedSessionID = sessions.first?.id
            return
        }
        let newIndex = currentIndex < sessions.count - 1 ? currentIndex + 1 : 0
        selectedSessionID = sessions[newIndex].id
    }
    
    func session(for serverID: UUID?) -> Session? {
        guard let serverID = serverID else { return nil }
        return sessions.first(where: { $0.serverID == serverID })
    }
    
    // MARK: - Connection State Aggregation
    
    @Published var serverStates: [UUID: ConnectionState] = [:]
    private var sessionCancellables = Set<AnyCancellable>()
    
    private func updateObserving() {
        sessionCancellables.removeAll()
        
        for session in sessions {
            session.connectionManager.$connectionState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.recalculateServerStates()
                }
                .store(in: &sessionCancellables)
        }
        
        recalculateServerStates()
    }
    
    private func recalculateServerStates() {
        var newStates: [UUID: ConnectionState] = [:]
        
        // Group sessions by serverID
        let grouped = Dictionary(grouping: sessions) { $0.serverID }
        
        for (serverID, serverSessions) in grouped {
            guard let serverID = serverID else { continue }
            
            // Determine aggregate state
            // Priority: Connected > Connecting > Error > Disconnected
            
            let allStates = serverSessions.map { $0.connectionManager.connectionState }
            print("[TabManager] Recalculating state for server \(serverID): \(allStates)")
            
            if allStates.contains(where: { $0 == .connected }) {
                newStates[serverID] = .connected
            } else if allStates.contains(where: { $0 == .connecting }) {
                newStates[serverID] = .connecting
            } else if let errorState = allStates.first(where: { if case .error = $0 { return true }; return false }) {
                newStates[serverID] = errorState
            } else {
                newStates[serverID] = .disconnected
            }
        }
        
        print("[TabManager] Updated serverStates: \(newStates)")
        self.serverStates = newStates
    }
}

