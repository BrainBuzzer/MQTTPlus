//
//  SessionTabView.swift
//  MQTT Plus
//
//  Created by Aditya on 10/01/26.
//

import SwiftUI

struct SessionTabView: View {
    @ObservedObject var tabManager: TabManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            if !tabManager.sessions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(tabManager.sessions) { session in
                            SessionTabItem(
                                session: session,
                                isSelected: session.id == tabManager.selectedSessionID,
                                onClose: {
                                    tabManager.closeTab(id: session.id)
                                },
                                onSelect: {
                                    tabManager.selectTab(id: session.id)
                                }
                            )
                        }
                    }
                }
                .frame(height: 32)
                .background(Color(nsColor: .controlBackgroundColor))
                
                Divider()
            }
            
            // Content
            if let selectedSession = tabManager.selectedSession {
                ActiveSessionView(connectionManager: selectedSession.connectionManager)
                    .id(selectedSession.id) // Force recreate if ID changes (though ID is constant)
            } else {
                WelcomeView(connectionState: .disconnected)
            }
        }
        .background(
            Button("Refresh") {
                tabManager.selectedSession?.refresh()
            }
            .keyboardShortcut("r", modifiers: .control)
            .opacity(0)
        )
    }
}

struct SessionTabItem: View {
    @ObservedObject var session: Session
    let isSelected: Bool
    let onClose: () -> Void
    let onSelect: () -> Void
    
    // Observe connection state to show status colors in the tab
    @ObservedObject var connectionManager: ConnectionManager
    @Environment(\.colorScheme) var colorScheme
    
    init(session: Session, isSelected: Bool, onClose: @escaping () -> Void, onSelect: @escaping () -> Void) {
        self.session = session
        self.isSelected = isSelected
        self.onClose = onClose
        self.onSelect = onSelect
        self.connectionManager = session.connectionManager
    }
    
    var body: some View {
        HStack(spacing: 6) {
            StatusDot(state: connectionManager.connectionState)
            
            Text(session.name)
                .font(.callout)
                .lineLimit(1)
                
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.borderless)
            .opacity(isSelected ? 1 : 0.5) // Less intrusive close button on inactive tabs
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            isSelected
                ? Color(nsColor: .windowBackgroundColor) // Active: Matches content
                : (colorScheme == .dark
                   ? Color.black.opacity(0.3) // Dark mode inactive: Darker
                   : Color.gray.opacity(0.15)) // Light mode inactive: Grayer
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(nsColor: .separatorColor)),
            alignment: .trailing
        )
    }
}

struct StatusDot: View {
    let state: ConnectionState
    
    var color: Color {
        switch state {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .gray
        }
    }
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }
}
