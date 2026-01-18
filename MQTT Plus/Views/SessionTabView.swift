//
//  SessionTabView.swift
//  MQTT Plus
//
//  Created by Aditya on 10/01/26.
//

import SwiftUI

struct SessionTabView: View {
    @ObservedObject var tabManager: TabManager
    @Namespace private var tabNamespace
    
    var body: some View {
        VStack(spacing: 0) {
            if !tabManager.sessions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(tabManager.sessions) { session in
                            SessionTabItem(
                                session: session,
                                isSelected: session.id == tabManager.selectedSessionID,
                                namespace: tabNamespace,
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
                .frame(height: 38)
                .background(Color(nsColor: .controlBackgroundColor))
                
                Divider()
            }
            
            if let selectedSession = tabManager.selectedSession {
                ActiveSessionView(connectionManager: selectedSession.connectionManager)
                    .id(selectedSession.id)
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.closeCurrentTab)) { _ in
            if let selectedID = tabManager.selectedSessionID {
                tabManager.closeTab(id: selectedID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.selectTabByIndex)) { notification in
            if let index = notification.object as? Int, index >= 1, index <= tabManager.sessions.count {
                let session = tabManager.sessions[index - 1]
                tabManager.selectTab(id: session.id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.selectPreviousTab)) { _ in
            tabManager.selectPreviousTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.selectNextTab)) { _ in
            tabManager.selectNextTab()
        }
    }
}

struct SessionTabItem: View {
    @ObservedObject var session: Session
    let isSelected: Bool
    let namespace: Namespace.ID
    let onClose: () -> Void
    let onSelect: () -> Void
    
    @ObservedObject var connectionManager: ConnectionManager
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    @State private var isCloseHovered = false
    
    init(session: Session, isSelected: Bool, namespace: Namespace.ID, onClose: @escaping () -> Void, onSelect: @escaping () -> Void) {
        self.session = session
        self.isSelected = isSelected
        self.namespace = namespace
        self.onClose = onClose
        self.onSelect = onSelect
        self.connectionManager = session.connectionManager
    }
    
    private var providerColor: Color {
        MQProviderColor.color(for: connectionManager.currentProvider?.rawValue)
    }
    
    var body: some View {
        HStack(spacing: MQSpacing.sm) {
            Image(systemName: providerIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(providerColor.opacity(0.7))
            
            MQStatusDot(state: connectionManager.connectionState)
            
            Text(session.name)
                .font(.system(.callout, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .primary : .secondary)
            
            if !isSelected && session.unreadCount > 0 {
                Text(session.unreadCount > 99 ? "99+" : "\(session.unreadCount)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .clipShape(Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
                
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isCloseHovered ? .primary : .tertiary)
                    .frame(width: 16, height: 16)
                    .background(isCloseHovered ? Color.primary.opacity(0.1) : Color.clear)
                    .clipShape(Circle())
            }
            .buttonStyle(.borderless)
            .onHover { isCloseHovered = $0 }
            .opacity(isHovered || isSelected ? 1 : 0)
        }
        .padding(.horizontal, MQSpacing.lg)
        .padding(.vertical, MQSpacing.xs)
        .frame(height: 38)
        .animation(MQAnimation.quick, value: session.unreadCount)
        .background(
            isSelected
                ? Color(nsColor: .windowBackgroundColor)
                : (isHovered
                   ? Color.primary.opacity(0.05)
                   : (colorScheme == .dark
                      ? Color.black.opacity(0.2)
                      : Color.gray.opacity(0.08)))
        )
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .matchedGeometryEffect(id: "tab-indicator", in: namespace)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onSelect)
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(nsColor: .separatorColor).opacity(0.3)),
            alignment: .trailing
        )
        .animation(MQAnimation.quick, value: isHovered)
        .animation(MQAnimation.spring, value: isSelected)
    }
    
    private var providerIcon: String {
        switch connectionManager.currentProvider {
        case .nats: return "antenna.radiowaves.left.and.right"
        case .redis: return "cylinder.fill"
        case .kafka: return "arrow.triangle.pull"
        case nil: return "server.rack"
        }
    }
}
