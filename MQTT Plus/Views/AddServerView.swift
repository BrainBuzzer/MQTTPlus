//
//  AddServerView.swift
//  MQTT Plus
//
//  Created by Aditya on 10/01/26.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

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
    
    @State private var kafkaSecurityProtocol: KafkaSecurityProtocol = .plaintext
    @State private var kafkaSASLMechanism: KafkaSASLMechanism = .plain
    
    @State private var kafkaOAuthTokenEndpoint = ""
    @State private var kafkaOAuthClientId = ""
    @State private var kafkaOAuthClientSecret = ""
    @State private var kafkaOAuthScope = ""
    
    @State private var kafkaSSLCAPath = ""
    @State private var kafkaSSLCertPath = ""
    @State private var kafkaSSLKeyPath = ""
    @State private var kafkaSSLKeyPassword = ""
    @State private var kafkaSSLVerifyHostname = true
    
    @State private var kafkaGroupId = "mqtt-plus"
    @State private var kafkaClientId = "mqtt-plus-client"
    
    @State private var isTesting = false
    @State private var testResult: Bool? = nil
    @State private var testMessage: String? = nil
    @State private var showingTestAlert = false
    
    @State private var showAdvancedKafka = false

    private var selectedProviderInfo: MQProviderInfo? {
        registry.providerInfo(for: selectedProviderId)
    }
    
    private var isKafka: Bool { selectedProviderId == "kafka" }
    
    var body: some View {
        HStack(spacing: 0) {
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
            
            VStack(spacing: 0) {
                HStack {
                    Text("\(selectedProviderInfo?.displayName ?? "Broker") Connection")
                        .font(.headline)
                    Spacer()
                }
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        connectionBasicsSection
                        
                        Divider().padding(.vertical, 4)
                        
                        if isKafka {
                            kafkaSecuritySection
                            Divider().padding(.vertical, 4)
                        }
                        
                        authenticationSection
                        
                        if isKafka && kafkaSecurityProtocol.requiresSSL {
                            Divider().padding(.vertical, 4)
                            kafkaSSLSection
                        }
                        
                        if isKafka && kafkaSASLMechanism == .oauthbearer && kafkaSecurityProtocol.requiresSASL {
                            Divider().padding(.vertical, 4)
                            kafkaOAuthSection
                        }
                        
                        if isKafka {
                            Divider().padding(.vertical, 4)
                            kafkaAdvancedSection
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                footerSection
            }
        }
        .frame(width: 700, height: isKafka ? 600 : 450)
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
    
    private var connectionBasicsSection: some View {
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
            
            if !isKafka {
                GridRow {
                    Color.clear
                        .gridCellUnsizedAxes([.vertical, .horizontal])
                    Toggle("Use TLS/SSL", isOn: $useTLS)
                        .toggleStyle(.checkbox)
                        .gridColumnAlignment(.leading)
                }
            }
        }
    }
    
    private var kafkaSecuritySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Security")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Protocol")
                        .foregroundStyle(.secondary)
                    Picker("", selection: $kafkaSecurityProtocol) {
                        ForEach(KafkaSecurityProtocol.allCases, id: \.self) { proto in
                            Text(proto.displayName).tag(proto)
                        }
                    }
                    .labelsHidden()
                    .gridColumnAlignment(.leading)
                }
                
                if kafkaSecurityProtocol.requiresSASL {
                    GridRow {
                        Text("SASL Mechanism")
                            .foregroundStyle(.secondary)
                        Picker("", selection: $kafkaSASLMechanism) {
                            ForEach(KafkaSASLMechanism.allCases, id: \.self) { mech in
                                Text(mech.displayName).tag(mech)
                            }
                        }
                        .labelsHidden()
                        .gridColumnAlignment(.leading)
                    }
                }
            }
            
            if kafkaSecurityProtocol == .saslSSL && kafkaSASLMechanism == .plain {
                HStack(spacing: 8) {
                    Image(systemName: "cloud.fill")
                        .foregroundStyle(.blue)
                    Text("Confluent Cloud compatible")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }
    
    private var authenticationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Authentication")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if isKafka && kafkaSecurityProtocol.requiresSASL && kafkaSASLMechanism == .oauthbearer {
                Text("OAuth credentials configured below")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        Text(isKafka ? "API Key / Username" : "User")
                            .foregroundStyle(.secondary)
                        TextField(isKafka ? "API Key" : "User", text: $user)
                            .mqFilledField()
                            .gridColumnAlignment(.leading)
                    }
                    
                    GridRow {
                        Text(isKafka ? "API Secret / Password" : "Password")
                            .foregroundStyle(.secondary)
                        SecureField(isKafka ? "API Secret" : "Password", text: $password)
                            .mqFilledField()
                    }
                }
            }
        }
    }
    
    private var kafkaSSLSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SSL/TLS Configuration")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("CA Certificate")
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("Path to CA certificate (optional)", text: $kafkaSSLCAPath)
                            .mqFilledField()
                        Button("Browse...") {
                            selectFile(for: $kafkaSSLCAPath)
                        }
                    }
                    .gridColumnAlignment(.leading)
                }
                
                GridRow {
                    Text("Client Certificate")
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("Path to client certificate (mTLS)", text: $kafkaSSLCertPath)
                            .mqFilledField()
                        Button("Browse...") {
                            selectFile(for: $kafkaSSLCertPath)
                        }
                    }
                }
                
                GridRow {
                    Text("Client Key")
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("Path to client key (mTLS)", text: $kafkaSSLKeyPath)
                            .mqFilledField()
                        Button("Browse...") {
                            selectFile(for: $kafkaSSLKeyPath)
                        }
                    }
                }
                
                if !kafkaSSLKeyPath.isEmpty {
                    GridRow {
                        Text("Key Password")
                            .foregroundStyle(.secondary)
                        SecureField("Key password (if encrypted)", text: $kafkaSSLKeyPassword)
                            .mqFilledField()
                    }
                }
                
                GridRow {
                    Color.clear
                        .gridCellUnsizedAxes([.vertical, .horizontal])
                    Toggle("Verify hostname", isOn: $kafkaSSLVerifyHostname)
                        .toggleStyle(.checkbox)
                        .gridColumnAlignment(.leading)
                }
            }
        }
    }
    
    private var kafkaOAuthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OAuth / OIDC Configuration")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Token Endpoint")
                        .foregroundStyle(.secondary)
                    TextField("https://auth.example.com/oauth/token", text: $kafkaOAuthTokenEndpoint)
                        .mqFilledField()
                        .gridColumnAlignment(.leading)
                }
                
                GridRow {
                    Text("Client ID")
                        .foregroundStyle(.secondary)
                    TextField("OAuth Client ID", text: $kafkaOAuthClientId)
                        .mqFilledField()
                }
                
                GridRow {
                    Text("Client Secret")
                        .foregroundStyle(.secondary)
                    SecureField("OAuth Client Secret", text: $kafkaOAuthClientSecret)
                        .mqFilledField()
                }
                
                GridRow {
                    Text("Scope")
                        .foregroundStyle(.secondary)
                    TextField("Optional scope", text: $kafkaOAuthScope)
                        .mqFilledField()
                }
            }
        }
    }
    
    private var kafkaAdvancedSection: some View {
        DisclosureGroup("Advanced Options", isExpanded: $showAdvancedKafka) {
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Client ID")
                        .foregroundStyle(.secondary)
                    TextField("mqtt-plus-client", text: $kafkaClientId)
                        .mqFilledField()
                        .gridColumnAlignment(.leading)
                }
                
                GridRow {
                    Text("Consumer Group")
                        .foregroundStyle(.secondary)
                    TextField("mqtt-plus", text: $kafkaGroupId)
                        .mqFilledField()
                }
            }
            .padding(.top, 8)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    
    private var footerSection: some View {
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
    
    private func selectFile(for binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.data]
        
        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url.path
        }
    }
    
    private func selectProvider(_ provider: MQProviderInfo) {
        let previousDefaultPort = selectedProviderInfo?.defaultPort
        selectedProviderId = provider.id

        if port.isEmpty || (previousDefaultPort != nil && port == String(previousDefaultPort!)) {
            port = String(provider.defaultPort)
        }
        
        if provider.id == "kafka" {
            kafkaSecurityProtocol = .plaintext
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
        newServer.setValue(useTLS || (isKafka && kafkaSecurityProtocol.requiresSSL), forKey: "useTLS")
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
        
        if isKafka {
            if let kafkaJSON = buildKafkaConfiguration().toJSON() {
                newServer.setValue(kafkaJSON, forKey: "optionsJSON")
            }
        }

        newServer.urlString = constructURL()
        newServer.createdAt = Date()
        
        try? viewContext.save()
        dismiss()
    }
    
    private func buildKafkaConfiguration() -> KafkaConfiguration {
        var oauthConfig: KafkaOAuthConfig? = nil
        if kafkaSASLMechanism == .oauthbearer && kafkaSecurityProtocol.requiresSASL {
            oauthConfig = KafkaOAuthConfig(
                tokenEndpoint: kafkaOAuthTokenEndpoint,
                clientId: kafkaOAuthClientId,
                clientSecret: kafkaOAuthClientSecret,
                scope: kafkaOAuthScope.isEmpty ? nil : kafkaOAuthScope
            )
        }
        
        let sslConfig = KafkaSSLConfig(
            caLocation: kafkaSSLCAPath.isEmpty ? nil : kafkaSSLCAPath,
            certificateLocation: kafkaSSLCertPath.isEmpty ? nil : kafkaSSLCertPath,
            keyLocation: kafkaSSLKeyPath.isEmpty ? nil : kafkaSSLKeyPath,
            keyPassword: kafkaSSLKeyPassword.isEmpty ? nil : kafkaSSLKeyPassword,
            enableHostnameVerification: kafkaSSLVerifyHostname
        )
        
        let consumerConfig = KafkaConsumerConfig(groupId: kafkaGroupId)
        
        return KafkaConfiguration(
            securityProtocol: kafkaSecurityProtocol,
            saslMechanism: kafkaSecurityProtocol.requiresSASL ? kafkaSASLMechanism : nil,
            sslConfig: sslConfig,
            oauthConfig: oauthConfig,
            consumerConfig: consumerConfig,
            clientId: kafkaClientId
        )
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
        
        var options: [String: String] = [:]
        if isKafka {
            if let kafkaJSON = buildKafkaConfiguration().toJSON() {
                options["kafkaConfig"] = kafkaJSON
            }
        }
        
        let config = MQConnectionConfig(
            url: constructURL(),
            name: "Test Connection",
            username: user.isEmpty ? nil : user,
            password: password.isEmpty ? nil : password,
            token: nil,
            tlsEnabled: useTLS || (isKafka && kafkaSecurityProtocol.requiresSSL),
            options: options
        )
        
        Task {
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
                try? await client.disconnect()
                
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
