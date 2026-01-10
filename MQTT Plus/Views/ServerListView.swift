//
//  ServerListView.swift
//  MQTT Plus
//
//  Created by Aditya on 10/01/26.
//

import SwiftUI
import CoreData

struct ServerListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var tabManager: TabManager
    
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
                    ServerRowView(server: server, tabManager: tabManager)
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
            AddServerView()
        }
        .navigationTitle("Servers")
    }
    
    private func deleteServer(_ server: ServerConfig) {
        cleanupCredentials(for: server)
        viewContext.delete(server)
        try? viewContext.save()
    }
    
    private func deleteServers(offsets: IndexSet) {
        offsets.map { servers[$0] }.forEach { server in
            cleanupCredentials(for: server)
            viewContext.delete(server)
        }
        try? viewContext.save()
    }

    private func cleanupCredentials(for server: ServerConfig) {
        if let passwordKey = server.value(forKey: "passwordKeychainId") as? String, !passwordKey.isEmpty {
            try? KeychainService.delete(key: passwordKey)
        }
        if let tokenKey = server.value(forKey: "tokenKeychainId") as? String, !tokenKey.isEmpty {
            try? KeychainService.delete(key: tokenKey)
        }
    }
}

struct ServerRowView: View {
    let server: ServerConfig
    @ObservedObject var tabManager: TabManager
    @ObservedObject private var providerRegistry = MQProviderRegistry.shared
    @State private var showingModeSelector = false
    @State private var selectedMode: ConnectionMode = .core

    private var provider: MQProviderKind? {
        if let providerId = server.providerId, !providerId.isEmpty {
            return MQProviderKind(providerId: providerId)
        }
        return MQProviderKind(urlString: server.urlString ?? "")
    }
    
    var session: Session? {
        tabManager.session(for: server.id)
    }
    
    var isConnected: Bool {
        session != nil
    }
    
    var body: some View {
        HStack {
            Image(systemName: providerIcon)
                .foregroundColor(isConnected ? .green : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name ?? "Unnamed Server")
                    .font(.headline)
                Text(urlDisplayText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isConnected {
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
                    tabManager.openTab(for: server, mode: mode)
                    showingModeSelector = false
                }
            )
        }
    }

    private var providerIcon: String {
        if let providerId = server.providerId,
           let info = providerRegistry.providerInfo(for: providerId) {
            return info.iconName
        }

        switch provider {
        case .nats:
            return "antenna.radiowaves.left.and.right"
        case .redis:
            return "cylinder.fill"
        case .kafka:
            return "arrow.triangle.pull"
        case nil:
            return "server.rack"
        }
    }

    private var urlDisplayText: String {
        let base = server.urlString ?? ""
        if (server.value(forKey: "useTLS") as? Bool) == true {
            return "\(base) (TLS)"
        }
        return base
    }
    
    private func handleTap() {
        if isConnected {
            // If already connected, just switch to that tab
            if let id = session?.id {
                tabManager.selectTab(id: id)
            }
        } else {
            switch provider {
            case .nats:
                // Show mode selector instead of connecting directly
                showingModeSelector = true
            default:
                tabManager.openTab(for: server)
            }
        }
    }
}

#Preview {
    ServerListView(tabManager: TabManager())
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
