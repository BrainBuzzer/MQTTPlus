//
//  ServerListView.swift
//  PubSub Viewer
//
//  Created by Aditya on 10/01/26.
//

import SwiftUI
import CoreData

struct ServerListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var natsManager: NatsManager
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ServerConfig.createdAt, ascending: false)],
        animation: .default
    )
    private var servers: FetchedResults<ServerConfig>
    
    @State private var showingAddServer = false
    @State private var selectedServer: ServerConfig?
    
    var body: some View {
        List(selection: $selectedServer) {
            Section("Servers") {
                ForEach(servers) { server in
                    ServerRowView(server: server, natsManager: natsManager)
                        .tag(server)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                deleteServer(server)
                            }
                        }
                }
                .onDelete(perform: deleteServers)
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button(action: { showingAddServer = true }) {
                    Label("Add Server", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddServer) {
            AddServerSheet(isPresented: $showingAddServer)
        }
        .navigationTitle("Servers")
    }
    
    private func deleteServer(_ server: ServerConfig) {
        viewContext.delete(server)
        try? viewContext.save()
    }
    
    private func deleteServers(offsets: IndexSet) {
        offsets.map { servers[$0] }.forEach(viewContext.delete)
        try? viewContext.save()
    }
}

struct ServerRowView: View {
    let server: ServerConfig
    @ObservedObject var natsManager: NatsManager
    @State private var showingModeSelector = false
    @State private var selectedMode: NatsMode = .core
    
    var isConnected: Bool {
        natsManager.connectionState.isConnected && natsManager.currentServerName == server.name
    }
    
    var isConnecting: Bool {
        if case .connecting = natsManager.connectionState {
            return natsManager.currentServerName == server.name
        }
        return false
    }
    
    var body: some View {
        HStack {
            Image(systemName: "server.rack")
                .foregroundColor(isConnected ? .green : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name ?? "Unnamed Server")
                    .font(.headline)
                Text(server.urlString ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isConnecting {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.5) // Make it smaller to fit nicely
                    .frame(width: 8, height: 8)
            } else if isConnected {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        .popover(isPresented: $showingModeSelector) {
            ModeSelectorView(
                selectedMode: $selectedMode,
                onConnect: { mode in
                    Task {
                        await natsManager.connect(
                            to: server.urlString ?? "",
                            serverName: server.name ?? "Unknown",
                            mode: mode
                        )
                    }
                    showingModeSelector = false
                }
            )
        }
    }
    
    private func handleTap() {
        guard !isConnecting else { return }
        
        if isConnected {
            natsManager.disconnect()
        } else {
            // Show mode selector instead of connecting directly
            showingModeSelector = true
        }
    }
}

struct AddServerSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var isPresented: Bool
    
    @State private var name = ""
    @State private var urlString = "nats://localhost:4222"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add NATS Server")
                .font(.headline)
            
            Form {
                TextField("Server Name", text: $name)
                TextField("URL", text: $urlString)
            }
            .formStyle(.grouped)
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Add") {
                    addServer()
                }
                .keyboardShortcut(.return)
                .disabled(name.isEmpty || urlString.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 200)
    }
    
    private func addServer() {
        let newServer = ServerConfig(context: viewContext)
        newServer.id = UUID()
        newServer.name = name
        newServer.urlString = urlString
        newServer.createdAt = Date()
        
        try? viewContext.save()
        isPresented = false
    }
}

#Preview {
    ServerListView(natsManager: NatsManager.shared)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
