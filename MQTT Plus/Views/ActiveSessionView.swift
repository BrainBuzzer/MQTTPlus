//
//  ActiveSessionView.swift
//  MQTT Plus
//
//  Created by Aditya on 10/01/26.
//

import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct ActiveSessionView: View {
    @ObservedObject var connectionManager: ConnectionManager
    
    @State private var newSubject = ""
    @State private var selectedSubject: String?
    @State private var showingPublishSheet = false
    @State private var republishMessage: ReceivedMessage?
    @State private var searchText = ""
    
    @State private var showingConsole = false
    @State private var showingInspector = false
    @State private var showingExportAlert = false
    @State private var exportAlertMessage = ""
    
    var body: some View {
        // Show appropriate view based on connection mode
        if connectionManager.mode == .jetstream {
            JetStreamView(connectionManager: connectionManager)
        } else {
            coreNatsView
        }
    }
    
    // Core NATS view (existing implementation)
    private var coreNatsView: some View {
        GeometryReader { geometry in
            HSplitView {
                // Left: Filter panel
                VStack(alignment: .leading, spacing: 0) {
                    // Header to match right pane toolbar
                    HStack {
                        Text("SUBSCRIPTIONS")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    
                    Divider()
                    
                    // Filter Input
                    
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundStyle(.secondary)
                        TextField(filterPlaceholder, text: $newSubject)
                            .textFieldStyle(.plain)
                            .onSubmit(subscribeToSubject)
                        
                        Button(action: subscribeToSubject) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(newSubject.isEmpty)
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                    
                    List(selection: $selectedSubject) {
                        Section("Subscriptions") {
                            // "All Messages" special filter
                            HStack {
                                Label("All Messages", systemImage: "tray.full")
                                Spacer()
                                Text(connectionManager.isFirehoseEnabled ? "Firehose" : "—")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(connectionManager.isFirehoseEnabled ? .green : .secondary)
                                Text("\(messageCount(for: ">"))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            .tag(">")
                            
                            ForEach(connectionManager.subscribedSubjects, id: \.self) { subject in
                                HStack {
                                    Label(subject, systemImage: "tag")
                                    Spacer()
                                    Text("\(messageCount(for: subject))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(4)
                                }
                                .tag(subject)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        connectionManager.unsubscribe(from: subject)
                                        if selectedSubject == subject {
                                            selectedSubject = nil
                                        }
                                    } label: {
                                        Label("Unsubscribe", systemImage: "trash")
                                    }
                                }
                            }
                        }

                        if connectionManager.currentProvider == .kafka, !connectionManager.streams.isEmpty {
                            Section("Topics") {
                            
                            ForEach(connectionManager.streams.map(\.name).filter { !connectionManager.subscribedSubjects.contains($0) }, id: \.self) { topic in
                                HStack {
                                    Label(topic, systemImage: "list.bullet.rectangle")
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .tag(topic)
                                .simultaneousGesture(TapGesture(count: 2).onEnded {
                                    connectionManager.subscribe(to: topic)
                                })
                                .simultaneousGesture(TapGesture().onEnded {
                                    if selectedSubject != topic {
                                        selectedSubject = topic
                                    }
                                })
                                .contextMenu {
                                    Button {
                                        connectionManager.subscribe(to: topic)
                                        selectedSubject = topic
                                    } label: {
                                        Label("Subscribe", systemImage: "plus")
                                    }
                                }
                            }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                }
                .frame(minWidth: 200, maxWidth: 350)
                .background(Color(nsColor: .windowBackgroundColor)) // Darker sidebar
                
                // Right: Content with Message Panel and Console
                VSplitView {
                    // Top: Messages Panel
                    VStack(spacing: 0) {
                        HStack(spacing: MQSpacing.lg) {
                            HStack(spacing: MQSpacing.md) {
                                if let subject = selectedSubject {
                                    Text(subject)
                                        .font(.system(.headline, weight: .semibold))
                                } else {
                                    Text("All Messages")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Text("\(filteredMessages.count)")
                                    .font(.caption.weight(.medium).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, MQSpacing.sm)
                                    .padding(.vertical, MQSpacing.xxs)
                                    .background(Color.secondary.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            
                            Spacer()
                            
                            MQToolbarGroup {
                                Toggle(isOn: Binding(
                                    get: { connectionManager.isFirehoseEnabled },
                                    set: { connectionManager.setFirehoseEnabled($0) }
                                )) {
                                    Label("Firehose", systemImage: "tray.full")
                                }
                                .toggleStyle(.button)
                                .controlSize(.small)
                                .help("Subscribe to all messages")
                                .disabled(connectionManager.connectionState != .connected)

                                Toggle(isOn: Binding(
                                    get: { connectionManager.isPaused },
                                    set: { connectionManager.setPaused($0) }
                                )) {
                                    if connectionManager.pausedMessageCount > 0 {
                                        Label("\(connectionManager.pausedMessageCount)", systemImage: "pause.circle.fill")
                                    } else {
                                        Label("Pause", systemImage: "pause.circle")
                                    }
                                }
                                .toggleStyle(.button)
                                .controlSize(.small)
                                .help("Pause message stream")
                                .disabled(connectionManager.connectionState != .connected)
                            }
                            
                            MQToolbarGroup {
                                MQSearchField(text: $searchText, placeholder: "Search messages...", width: 160)
                                
                                Menu {
                                    Button("Keep last 200") { connectionManager.setMessageRetentionLimit(200) }
                                    Button("Keep last 500") { connectionManager.setMessageRetentionLimit(500) }
                                    Button("Keep last 1000") { connectionManager.setMessageRetentionLimit(1000) }
                                    Button("Keep last 5000") { connectionManager.setMessageRetentionLimit(5000) }
                                } label: {
                                    Label("\(connectionManager.messageRetentionLimit)", systemImage: "tray.and.arrow.down")
                                        .font(.callout)
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .help("Message retention limit")
                            }
                            
                            MQToolbarGroup {
                                Toggle(isOn: $showingInspector) {
                                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                                }
                                .toggleStyle(.button)
                                .controlSize(.small)
                                .help("Inspector (I)")
                                
                                Toggle(isOn: $showingConsole) {
                                    Image(systemName: "terminal")
                                }
                                .toggleStyle(.button)
                                .controlSize(.small)
                                .help("Console (C)")
                            }
                            
                            HStack(spacing: MQSpacing.sm) {
                                Button(action: { showingPublishSheet = true }) {
                                    Label("Publish", systemImage: "paperplane.fill")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Menu {
                                    Button(action: { exportMessages(format: .json) }) {
                                        Label("Export as JSON", systemImage: "curlybraces")
                                    }
                                    Button(action: { exportMessages(format: .csv) }) {
                                        Label("Export as CSV", systemImage: "tablecells")
                                    }
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .menuStyle(.borderlessButton)
                                .help("Export messages")
                                .disabled(filteredMessages.isEmpty)
                                
                                Button(action: { connectionManager.clearMessages() }) {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .help("Clear messages")
                            }
                            
                            Button(action: { connectionManager.disconnect() }) {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red.opacity(0.8))
                            .help("Disconnect")
                            .disabled(connectionManager.connectionState == .disconnected)
                        }
                        .padding(.horizontal, MQSpacing.xl)
                        .padding(.vertical, MQSpacing.md)
                        .background(Color(nsColor: .controlBackgroundColor))
                        
                        Divider()
                        
                        // Messages
                        MessageLogView(
                            messages: filteredMessages,
                            connectionManager: connectionManager,
                            onRepublish: { message in
                                self.republishMessage = message
                                self.showingPublishSheet = true
                            }
                        )
                    }
                    .frame(minHeight: 200, maxHeight: .infinity)
                    
                    if showingConsole {
                        ConsoleView(connectionManager: connectionManager)
                            .frame(minHeight: 100, maxHeight: 300)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                    }
                    
                    if showingInspector {
                        BrokerInspectorPanel(connectionManager: connectionManager)
                            .frame(minHeight: 150, maxHeight: .infinity)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                    }
                }
            }
        }
        .animation(MQAnimation.spring, value: showingConsole)
        .animation(MQAnimation.spring, value: showingInspector)
        .sheet(isPresented: $showingPublishSheet) {
            PublishSheet(
                connectionManager: connectionManager,
                isPresented: $showingPublishSheet,
                initialSubject: republishMessage?.subject ?? selectedSubject,
                initialPayload: republishMessage?.payload
            )
        }
        .onChange(of: showingPublishSheet) { 
            if !showingPublishSheet {
                republishMessage = nil
            }
        }
        .onChange(of: selectedSubject) { _, newSubject in
            guard let subject = newSubject else { return }
            
            // Only preview if it's a topic (not firehose) and NOT subscribed
            if subject != ">" && !connectionManager.subscribedSubjects.contains(subject) {
                connectionManager.previewTopic(subject)
            }
        }
    } // End of coreNatsView
    
    private var filteredMessages: [ReceivedMessage] {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        var base: [ReceivedMessage]
        if let subject = selectedSubject {
            base = connectionManager.messages.filter { messageMatches(subject: $0.subject, pattern: subject) }
        } else {
            base = connectionManager.messages
        }

        guard !search.isEmpty else { return base }

        return base.filter { message in
            if message.subject.localizedCaseInsensitiveContains(search) { return true }
            if message.payload.localizedCaseInsensitiveContains(search) { return true }
            if let replyTo = message.replyTo, replyTo.localizedCaseInsensitiveContains(search) { return true }
            return false
        }
    }
    
    private func messageCount(for subject: String) -> Int {
        connectionManager.messages.filter { messageMatches(subject: $0.subject, pattern: subject) }.count
    }
    
    /// Checks if a message subject matches a subscription pattern (handling * and > wildcards)
    private func messageMatches(subject: String, pattern: String) -> Bool {
        if pattern == ">" { return true }
        if pattern == subject { return true }
        switch connectionManager.currentProvider {
        case .redis:
            return redisGlobMatch(subject: subject, pattern: pattern)
        case .kafka:
            return kafkaTopicMatch(topic: subject, pattern: pattern)
        case .nats, nil:
            return natsSubjectMatch(subject: subject, pattern: pattern)
        }
    }

    private var filterPlaceholder: String {
        switch connectionManager.currentProvider {
        case .redis:
            return "Add Channel Filter (e.g. foo*)"
        case .nats:
            return "Add Subject Filter (e.g. foo.*)"
        case .kafka:
            return "Add Topic Filter (e.g. my-topic)"
        case nil:
            return "Add Filter"
        }
    }

    private func natsSubjectMatch(subject: String, pattern: String) -> Bool {
        let subjectTokens = subject.components(separatedBy: ".")
        let patternTokens = pattern.components(separatedBy: ".")

        for (index, token) in patternTokens.enumerated() {
            if token == ">" {
                // strict wildcard: matches everything following
                return true
            }

            if index >= subjectTokens.count {
                return false
            }

            if token != "*" && token != subjectTokens[index] {
                return false
            }
        }

        // If pattern ended without '>', ensure we consumed all subject tokens
        return patternTokens.count == subjectTokens.count
    }

    private func kafkaTopicMatch(topic: String, pattern: String) -> Bool {
        if pattern == "*" { return true }
        guard pattern.contains("*") else { return topic == pattern }

        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let regex = "^\(escaped.replacingOccurrences(of: "\\\\*", with: ".*"))$"
        return topic.range(of: regex, options: [.regularExpression]) != nil
    }

    private func redisGlobMatch(subject: String, pattern: String) -> Bool {
        let regex = redisGlobToRegex(pattern)
        return subject.range(of: regex, options: [.regularExpression]) != nil
    }

    private func redisGlobToRegex(_ pattern: String) -> String {
        var regex = "^"
        regex.reserveCapacity(pattern.count * 2)

        var isEscaped = false
        var index = pattern.startIndex

        while index < pattern.endIndex {
            let ch = pattern[index]
            index = pattern.index(after: index)

            if isEscaped {
                regex.append(NSRegularExpression.escapedPattern(for: String(ch)))
                isEscaped = false
                continue
            }

            if ch == "\\" {
                isEscaped = true
                continue
            }

            switch ch {
            case "*":
                regex.append(".*")
            case "?":
                regex.append(".")
            case "[":
                var cls = "["
                var content = ""
                var foundEnd = false

                while index < pattern.endIndex {
                    let c = pattern[index]
                    index = pattern.index(after: index)
                    if c == "]" {
                        foundEnd = true
                        break
                    }
                    content.append(c)
                }

                if foundEnd {
                    if content.hasPrefix("!") {
                        cls.append("^")
                        content.removeFirst()
                    }
                    for c in content {
                        if c == "\\" {
                            cls.append("\\\\")
                        } else if c == "]" {
                            cls.append("\\]")
                        } else {
                            cls.append(c)
                        }
                    }
                    cls.append("]")
                    regex.append(cls)
                } else {
                    // Unmatched '[', treat literally.
                    regex.append("\\[")
                }

            default:
                regex.append(NSRegularExpression.escapedPattern(for: String(ch)))
            }
        }

        if isEscaped {
            regex.append("\\\\")
        }

        regex.append("$")
        return regex
    }
    
    private func subscribeToSubject() {
        guard !newSubject.isEmpty else { return }
        connectionManager.subscribe(to: newSubject)
        newSubject = ""
    }
    
    enum ExportFormat {
        case json, csv
        
        var fileExtension: String {
            switch self {
            case .json: return "json"
            case .csv: return "csv"
            }
        }
        
        var contentType: String {
            switch self {
            case .json: return "application/json"
            case .csv: return "text/csv"
            }
        }
    }
    
    private func exportMessages(format: ExportFormat) {
        let messagesToExport = filteredMessages
        guard !messagesToExport.isEmpty else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .json ? [.json] : [.commaSeparatedText]
        panel.nameFieldStringValue = "messages.\(format.fileExtension)"
        panel.title = "Export Messages"
        panel.prompt = "Export"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            do {
                switch format {
                case .json:
                    if let data = connectionManager.exportMessagesToJSON(messagesToExport) {
                        try data.write(to: url)
                    }
                case .csv:
                    let csv = connectionManager.exportMessagesToCSV(messagesToExport)
                    try csv.write(to: url, atomically: true, encoding: .utf8)
                }
            } catch {
                print("Export failed: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    ActiveSessionView(connectionManager: ConnectionManager())
}
