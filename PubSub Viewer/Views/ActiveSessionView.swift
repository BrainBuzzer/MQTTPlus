//
//  ActiveSessionView.swift
//  PubSub Viewer
//
//  Created by Aditya on 10/01/26.
//

import SwiftUI
import Foundation

struct ActiveSessionView: View {
    @ObservedObject var connectionManager: ConnectionManager
    
    @State private var newSubject = ""
    @State private var selectedSubject: String?
    @State private var showingPublishSheet = false
    
    @State private var showingConsole = false
    
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
                        Text("FILTERS")
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
                        Section("Active Filters") {
                            // "All Messages" special filter
                            HStack {
                                Label("All Messages", systemImage: "tray.full")
                                Spacer()
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
                                        Label("Remove Filter", systemImage: "trash")
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
                        // Toolbar
                        HStack {
                            if let subject = selectedSubject {
                                Text(subject)
                                    .font(.headline)
                            } else {
                                Text("Select a subscription")
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle(isOn: $showingConsole) {
                                Label("Console", systemImage: "terminal")
                            }
                            .toggleStyle(.button)
                            .help("Toggle Connection Logs")
                            
                            Button(action: { showingPublishSheet = true }) {
                                Label("Publish", systemImage: "paperplane.fill")
                            }
                            
                            Button(action: { connectionManager.clearMessages() }) {
                                Label("Clear", systemImage: "trash")
                            }
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        
                        Divider()
                        
                        // Messages
                        MessageLogView(
                            messages: filteredMessages,
                            connectionManager: connectionManager
                        )
                    }
                    .frame(minHeight: 200, maxHeight: .infinity)
                    
                    // Bottom: Console Panel
                    if showingConsole {
                        ConsoleView(connectionManager: connectionManager)
                            .frame(minHeight: 100, maxHeight: 300)
                            .transition(.move(edge: .bottom))
                    }
                }
            }
        }
        .sheet(isPresented: $showingPublishSheet) {
            PublishSheet(connectionManager: connectionManager, isPresented: $showingPublishSheet)
        }
    } // End of coreNatsView
    
    private var filteredMessages: [ReceivedMessage] {
        if let subject = selectedSubject {
            // Use NATS wildcard matching instead of exact string equality
            return connectionManager.messages.filter { messageMatches(subject: $0.subject, pattern: subject) }
        }
        return connectionManager.messages
    }
    
    private func messageCount(for subject: String) -> Int {
        connectionManager.messages.filter { messageMatches(subject: $0.subject, pattern: subject) }.count
    }
    
    /// Checks if a message subject matches a subscription pattern (handling * and > wildcards)
    private func messageMatches(subject: String, pattern: String) -> Bool {
        if pattern == ">" { return true }
        if pattern == subject { return true }
        if connectionManager.currentProvider == .redis {
            return redisGlobMatch(subject: subject, pattern: pattern)
        } else {
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
}

#Preview {
    ActiveSessionView(connectionManager: ConnectionManager.shared)
}
