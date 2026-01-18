//
//  ContentView.swift
//  MQTT Plus
//
//  Created by Aditya on 10/01/26.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var tabManager = TabManager()
    @State private var didBootstrap = false
    
    var body: some View {
        NavigationSplitView {
            ServerListView(tabManager: tabManager)
        } detail: {
            SessionTabView(tabManager: tabManager)
        }
        .frame(minWidth: 900, minHeight: 600)
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            await AppBootstrapper.runIfNeeded(viewContext: viewContext)
        }
    }
}

struct WelcomeView: View {
    let connectionState: ConnectionState
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 24) {
            welcomeIllustration
            
            VStack(spacing: 8) {
                Text("MQTT Plus")
                    .font(.largeTitle.weight(.bold))
                
                Text("Select a server from the sidebar to connect")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            connectionStateView
            
            shortcutHints
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isAnimating = true }
    }
    
    private var welcomeIllustration: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.08))
                .frame(width: 200, height: 200)
                .blur(radius: 40)
            
            floatingIcon(index: 0)
            floatingIcon(index: 1)
            floatingIcon(index: 2)
            
            Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue.gradient)
        }
        .frame(height: 200)
    }
    
    private func floatingIcon(index: Int) -> some View {
        let angle = Double(index) * .pi * 2 / 3 + (isAnimating ? .pi / 6 : 0)
        let icons = ["message.fill", "arrow.up.arrow.down", "bolt.fill"]
        return Image(systemName: icons[index])
            .font(.title3)
            .foregroundStyle(Color.blue.opacity(0.5))
            .offset(x: cos(angle) * 70, y: sin(angle) * 70)
            .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true).delay(Double(index) * 0.3), value: isAnimating)
    }
    
    @ViewBuilder
    private var connectionStateView: some View {
        if case .connecting = connectionState {
            ProgressView("Connecting...")
        } else if case .error(let message) = connectionState {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
    
    private var shortcutHints: some View {
        HStack(spacing: 32) {
            MQShortcutHint(keys: ["⌘", "N"], label: "New Server")
            MQShortcutHint(keys: ["⌘", "R"], label: "Refresh")
            MQShortcutHint(keys: ["⌘", ","], label: "Settings")
        }
        .padding(.top, 16)
    }
}

struct StatusBar: View {
    @ObservedObject var connectionManager: ConnectionManager
    
    var statusColor: Color {
        switch connectionManager.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .gray
        }
    }
    
    var statusText: String {
        switch connectionManager.connectionState {
        case .connected:
            return "Connected to \(connectionManager.currentServerName ?? "server")"
        case .connecting:
            return "Connecting..."
        case .error(let msg):
            return "Error: \(msg)"
        case .disconnected:
            return "Disconnected"
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
            
            Spacer()
            
            if connectionManager.connectionState.isConnected {
                Text("\(connectionManager.subscribedSubjects.count) subscriptions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Text("\(connectionManager.messages.count) messages")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                // Mode badge
                Text(connectionManager.mode.description)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(connectionManager.mode == .jetstream ? .white : .blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(connectionManager.mode == .jetstream ? Color.purple : Color.blue.opacity(0.2))
                    .cornerRadius(4)
                
                Button("Disconnect") {
                    connectionManager.disconnect()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
