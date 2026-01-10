//
//  AddServerView.swift
//  MQTT Plus
//
//  Created by Aditya on 10/01/26.
//

import SwiftUI
import CoreData

struct AddServerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @ObservedObject private var registry = MQProviderRegistry.shared
    @State private var selectedProviderId: String = "nats"
    @State private var name = ""
    @State private var host = "localhost"
    @State private var port = ""
    @State private var user = ""
    @State private var password = ""
    @State private var useTLS = false

    private var selectedProviderInfo: MQProviderInfo? {
        registry.providerInfo(for: selectedProviderId)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Pane: Provider Selection
            VStack(alignment: .leading, spacing: 16) {
                Text("New Connection")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 20)
                
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
                        ForEach(registry.availableProviders) { provider in
                            ProviderOption(
                                info: provider,
                                isSelected: selectedProviderId == provider.id,
                                action: { selectProvider(provider) }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .frame(width: 200)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Right Pane: Connection Details
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("\(selectedProviderInfo?.displayName ?? "Broker") Connection")
                        .font(.headline)
                    Spacer()
                }
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // Connection Basics
                        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 12) {
                            GridRow {
                                Text("Name")
                                    .foregroundColor(.secondary)
                                TextField("Optional", text: $name)
                                    .textFieldStyle(.roundedBorder)
                                    .gridColumnAlignment(.leading)
                            }
                            
                            GridRow {
                                Text("Host")
                                    .foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    TextField("127.0.0.1", text: $host)
                                        .textFieldStyle(.roundedBorder)
                                    
                                    Text("Port")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                    
                                    TextField(portPlaceholder, text: $port)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 60)
                                }
                            }
                            
                            GridRow {
                                Color.clear
                                    .gridCellUnsizedAxes([.vertical, .horizontal])
                                Toggle("Use TLS/SSL", isOn: $useTLS)
                                    .toggleStyle(.checkbox)
                                    .gridColumnAlignment(.leading)
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        Text("Authentication")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 12) {
                            GridRow {
                                Text("User")
                                    .foregroundColor(.secondary)
                                TextField("User", text: $user)
                                    .textFieldStyle(.roundedBorder)
                                    .gridColumnAlignment(.leading)
                            }
                            
                            GridRow {
                                Text("Password")
                                    .foregroundColor(.secondary)
                                SecureField("Password", text: $password)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                // Footer
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape)
                    
                    Spacer()
                    
                    Button("Test") {
                        // TODO: Implement connection test
                    }
                    
                    Button("Connect") {
                        addServer()
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(host.isEmpty || port.isEmpty)
                }
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(width: 650, height: 450)
        .onAppear {
            if registry.availableProviders.isEmpty {
                registerAllProviders()
            }
            if port.isEmpty {
                port = String(selectedProviderInfo?.defaultPort ?? 4222)
            }
        }
    }
    
    private func selectProvider(_ provider: MQProviderInfo) {
        let previousDefaultPort = selectedProviderInfo?.defaultPort

        selectedProviderId = provider.id

        if port.isEmpty || (previousDefaultPort != nil && port == String(previousDefaultPort!)) {
            port = String(provider.defaultPort)
        }
    }

    private func addServer() {
        let newServer = ServerConfig(context: viewContext)
        let serverId = UUID()
        newServer.id = serverId
        newServer.name = name.isEmpty ? "\(selectedProviderInfo?.displayName ?? "Broker") @ \(host)" : name
        newServer.providerId = selectedProviderId
        newServer.host = host
        newServer.setValue(Int32(Int(port) ?? (selectedProviderInfo?.defaultPort ?? 0)), forKey: "port")
        newServer.setValue(useTLS, forKey: "useTLS")
        newServer.username = user.isEmpty ? nil : user

        if !password.isEmpty {
            let key = KeychainService.key(for: serverId, kind: .password)
            do {
                try KeychainService.storeString(password, key: key)
                newServer.setValue(key, forKey: "passwordKeychainId")
            } catch {
                print("[AddServerView] Failed to store password in Keychain: \(error)")
            }
        }

        newServer.urlString = constructURL()
        newServer.createdAt = Date()
        
        try? viewContext.save()
        dismiss()
    }
    
    private var portPlaceholder: String {
        String(selectedProviderInfo?.defaultPort ?? 0)
    }
    
    private func constructURL() -> String {
        let scheme: String = {
            switch selectedProviderId {
            case "nats":
                return useTLS ? "tls" : "nats"
            case "redis":
                return "redis"
            case "kafka":
                return "kafka"
            default:
                return selectedProviderInfo?.urlScheme ?? "nats"
            }
        }()

        return "\(scheme)://\(host):\(port)"
    }
}

struct ProviderOption: View {
    let info: MQProviderInfo
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text(info.displayName)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(width: 80, height: 80)
            .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var iconName: String {
        info.iconName
    }
}
