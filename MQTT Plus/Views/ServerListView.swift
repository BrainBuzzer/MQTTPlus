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
                            serverContextMenu(for: server)
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

    @ViewBuilder
    private func serverContextMenu(for server: ServerConfig) -> some View {
        Button("Connect (Core)") {
            tabManager.openTab(for: server, mode: .core)
        }
        Button("Connect (JetStream)") {
            tabManager.openTab(for: server, mode: .jetstream)
        }
        Divider()
        Button("Delete", role: .destructive) {
            deleteServer(server)
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
    
    var connectionState: ConnectionState {
        guard let id = server.id else { return .disconnected }
        return tabManager.serverStates[id] ?? .disconnected
    }
    
    var body: some View {
        HStack(spacing: MQSpacing.lg) {
            iconView
                .frame(width: 20, height: 20)
            
            VStack(alignment: .leading, spacing: MQSpacing.xxs) {
                Text(server.name ?? "Unnamed Server")
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)
                Text(urlDisplayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if connectionState != .disconnected {
                MQStatusDot(state: connectionState)
            }
        }
        .padding(.vertical, MQSpacing.md)
        .padding(.horizontal, MQSpacing.xs)
        .contentShape(Rectangle())
        .mqRowHover()
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

    private var connectionColor: Color {
        switch connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .secondary
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
        if connectionState != .disconnected {
            // If already connected/connecting, just switch to that tab
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

    @ViewBuilder
    private var iconView: some View {
        if let id = server.providerId, let _ = NSImage(named: "icon_\(id)") {
            Image("icon_\(id)")
                .resizable()
                .renderingMode(.template) // Allow tinting
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .foregroundColor(connectionState == .connected ? .green : .secondary)
        } else {
            Image(systemName: providerIcon)
                .foregroundColor(connectionState == .connected ? .green : .secondary)
        }
    }
}

#Preview {
    ServerListView(tabManager: TabManager())
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
