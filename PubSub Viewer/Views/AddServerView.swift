//
//  AddServerView.swift
//  PubSub Viewer
//
//  Created by Aditya on 10/01/26.
//

import SwiftUI

struct AddServerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedProvider: MQProviderKind = .nats
    @State private var name = ""
    @State private var host = "localhost"
    @State private var port = ""
    @State private var user = ""
    @State private var password = ""
    @State private var useTLS = false
    
    // Default ports
    private let natsDefaultPort = "4222"
    private let redisDefaultPort = "6379"
    private let kafkaDefaultPort = "9092"
    
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
                        ProviderOption(
                            provider: .nats,
                            isSelected: selectedProvider == .nats,
                            action: { 
                                selectedProvider = .nats
                                if port.isEmpty || port == redisDefaultPort || port == kafkaDefaultPort {
                                    port = natsDefaultPort
                                }
                            }
                        )
                        
                        ProviderOption(
                            provider: .redis,
                            isSelected: selectedProvider == .redis,
                            action: { 
                                selectedProvider = .redis 
                                if port.isEmpty || port == natsDefaultPort || port == kafkaDefaultPort {
                                    port = redisDefaultPort
                                }
                            }
                        )
                        
                        ProviderOption(
                            provider: .kafka,
                            isSelected: selectedProvider == .kafka,
                            action: { 
                                selectedProvider = .kafka
                                if port.isEmpty || port == natsDefaultPort || port == redisDefaultPort {
                                    port = kafkaDefaultPort
                                }
                            }
                        )
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
                    Text("\(selectedProvider.displayName) Connection")
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
            if port.isEmpty {
                port = natsDefaultPort
            }
        }
    }
    
    private func addServer() {
        let newServer = ServerConfig(context: viewContext)
        newServer.id = UUID()
        newServer.name = name.isEmpty ? "\(selectedProvider.displayName) @ \(host)" : name
        newServer.urlString = constructURL()
        newServer.createdAt = Date()
        
        try? viewContext.save()
        dismiss()
    }
    
    private var portPlaceholder: String {
        switch selectedProvider {
        case .nats: return "4222"
        case .redis: return "6379"
        case .kafka: return "9092"
        }
    }
    
    private func constructURL() -> String {
        var scheme: String
        switch selectedProvider {
        case .nats:
            scheme = useTLS ? "tls" : "nats"
        case .redis:
            scheme = useTLS ? "rediss" : "redis"
        case .kafka:
            scheme = useTLS ? "kafkas" : "kafka"
        }
        
        var userInfo = ""
        if !user.isEmpty || !password.isEmpty {
            if !password.isEmpty {
                userInfo = "\(user):\(password)@"
            } else {
                userInfo = "\(user)@"
            }
        }
        
        return "\(scheme)://\(userInfo)\(host):\(port)"
    }
}

struct ProviderOption: View {
    let provider: MQProviderKind
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
                
                Text(provider.displayName)
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
        switch provider {
        case .nats: return "antenna.radiowaves.left.and.right"
        case .redis: return "cylinder.fill"
        case .kafka: return "arrow.triangle.pull"
        }
    }
}
