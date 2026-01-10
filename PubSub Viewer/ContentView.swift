//
//  ContentView.swift
//  PubSub Viewer
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
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue.gradient)
            
            Text("PubSub Viewer")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Select a server from the sidebar to connect")
                .foregroundColor(.secondary)
            
            if case .connecting = connectionState {
                ProgressView("Connecting...")
                    .padding(.top)
            } else if case .error(let message) = connectionState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .padding(.top)
            }
        }
        .padding(40)
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
