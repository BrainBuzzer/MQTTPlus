//
//  ContentView.swift
//  PubSub Viewer
//
//  Created by Aditya on 10/01/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var tabManager = TabManager()
    
    var body: some View {
        NavigationSplitView {
            ServerListView(tabManager: tabManager)
        } detail: {
            SessionTabView(tabManager: tabManager)
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

struct WelcomeView: View {
    let connectionState: NatsConnectionState
    
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
    @ObservedObject var natsManager: NatsManager
    
    var statusColor: Color {
        switch natsManager.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .gray
        }
    }
    
    var statusText: String {
        switch natsManager.connectionState {
        case .connected:
            return "Connected to \(natsManager.currentServerName ?? "server")"
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
            
            if natsManager.connectionState.isConnected {
                Text("\(natsManager.subscribedSubjects.count) subscriptions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Text("\(natsManager.messages.count) messages")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                // Mode badge
                Text(natsManager.mode.description)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(natsManager.mode == .jetstream ? .white : .blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(natsManager.mode == .jetstream ? Color.purple : Color.blue.opacity(0.2))
                    .cornerRadius(4)
                
                Button("Disconnect") {
                    natsManager.disconnect()
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
