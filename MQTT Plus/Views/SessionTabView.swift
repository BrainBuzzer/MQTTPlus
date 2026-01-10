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
    @State private var isHovered = false
    
    init(session: Session, isSelected: Bool, onClose: @escaping () -> Void, onSelect: @escaping () -> Void) {
        self.session = session
        self.isSelected = isSelected
        self.onClose = onClose
        self.onSelect = onSelect
        self.connectionManager = session.connectionManager
    }
    
    var body: some View {
        HStack(spacing: MQSpacing.sm) {
            MQStatusDot(state: connectionManager.connectionState)
            
            Text(session.name)
                .font(.system(.callout, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(isHovered || isSelected ? 1 : 0)
        }
        .padding(.horizontal, MQSpacing.lg)
        .frame(height: 32)
        .background(
            isSelected
                ? Color(nsColor: .windowBackgroundColor)
                : (isHovered
                   ? Color.primary.opacity(0.05)
                   : (colorScheme == .dark
                      ? Color.black.opacity(0.25)
                      : Color.gray.opacity(0.1)))
        )
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onSelect)
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(nsColor: .separatorColor).opacity(0.5)),
            alignment: .trailing
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}
