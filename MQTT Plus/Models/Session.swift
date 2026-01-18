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
    let serverID: UUID?
    
    @Published var connectionManager: ConnectionManager
    @Published var mode: ConnectionMode
    @Published var unreadCount: Int = 0
    
    private var messageCountWhenLastViewed: Int = 0
    private var cancellables = Set<AnyCancellable>()
    
    init(server: ServerConfig, mode: ConnectionMode = .core) {
        self.id = UUID()
        self.name = server.name ?? "Unknown Server"
        self.serverID = server.id
        self.mode = mode
        self.connectionManager = ConnectionManager()
        setupMessageTracking()
    }
    
    init(name: String, connectionManager: ConnectionManager? = nil) {
        self.id = UUID()
        self.name = name
        self.serverID = nil
        self.mode = .core
        self.connectionManager = connectionManager ?? ConnectionManager()
        setupMessageTracking()
    }
    
    private func setupMessageTracking() {
        connectionManager.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                guard let self = self else { return }
                let newCount = messages.count - self.messageCountWhenLastViewed
                if newCount > 0 {
                    self.unreadCount = newCount
                }
            }
            .store(in: &cancellables)
    }
    
    func markAsRead() {
        messageCountWhenLastViewed = connectionManager.messages.count
        unreadCount = 0
    }
    
    func refresh() {
        connectionManager.refresh()
    }
}
