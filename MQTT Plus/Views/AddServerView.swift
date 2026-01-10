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
    
    // Test Connection State
    @State private var isTesting = false
    @State private var testResult: Bool? = nil
    @State private var testMessage: String? = nil
    @State private var showingTestAlert = false

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
                                    .foregroundStyle(.secondary)
                                TextField("Optional", text: $name)
                                    .mqFilledField()
                                    .gridColumnAlignment(.leading)
                            }
                            
                            GridRow {
                                Text("Host")
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    TextField("127.0.0.1", text: $host)
                                        .mqFilledField(success: testResult == true)
                                    
                                    Text("Port")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                    
                                    TextField(portPlaceholder, text: $port)
                                        .mqFilledField(success: testResult == true)
                                        .frame(width: 70)
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
                            .foregroundStyle(.secondary)
                        
                        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 12) {
                            GridRow {
                                Text("User")
                                    .foregroundStyle(.secondary)
                                TextField("User", text: $user)
                                    .mqFilledField()
                                    .gridColumnAlignment(.leading)
                            }
                            
                            GridRow {
                                Text("Password")
                                    .foregroundStyle(.secondary)
                                SecureField("Password", text: $password)
                                    .mqFilledField()
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
                    
                    Button(action: performTest) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.5)
                        } else {
                            Text("Test")
                        }
                    }
                    .disabled(isTesting || host.isEmpty || port.isEmpty)
                    
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
        .alert("Connection Test", isPresented: $showingTestAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(testMessage ?? "Unknown error")
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
    
    private func performTest() {
        isTesting = true
        testResult = nil
        
        let config = MQConnectionConfig(
            url: constructURL(),
            name: "Test Connection",
            username: user.isEmpty ? nil : user,
            password: password.isEmpty ? nil : password,
            token: nil
        )
        
        Task {
            // Create a temporary client
            guard let client = registry.createClient(provider: selectedProviderId, config: config) else {
                await MainActor.run {
                    isTesting = false
                    testResult = false
                    testMessage = "Could not create client for provider \(selectedProviderId)"
                    showingTestAlert = true
                }
                return
            }
            
            do {
                try await client.connect()
                // If we get here, connection successful
                try? await client.disconnect() // Clean up
                
                await MainActor.run {
                    isTesting = false
                    testResult = true
                    testMessage = "Successfully connected!"
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testResult = false
                    testMessage = "Connection failed: \(error.localizedDescription)"
                    showingTestAlert = true
                }
            }
        }
    }
}

struct ProviderOption: View {
    let info: MQProviderInfo
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: MQSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: MQRadius.md, style: .continuous)
                        .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
                        .frame(width: 44, height: 44)
                    
                    if let _ = NSImage(named: "icon_\(info.id)") {
                        Image("icon_\(info.id)")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: info.iconName)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(isSelected ? .white : .primary)
                    }
                }
                
                Text(info.displayName)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
            }
            .frame(width: 80, height: 80)
            .background(
                RoundedRectangle(cornerRadius: MQRadius.lg, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MQRadius.lg, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
            )
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
