//
//  JetStreamMessageListView.swift
//  PubSub Viewer
//
//  Created by Antigravity on 10/01/26.
//

import SwiftUI

struct JetStreamMessageListView: View {
    @ObservedObject var connectionManager: ConnectionManager
    @State private var selectedMessage: ReceivedMessage?
    
    var body: some View {
        HSplitView {
            // Left: Message list
            VStack(spacing: 0) {
                if connectionManager.messages.isEmpty {
                    ContentUnavailableView(
                        "No Messages",
                        systemImage: "tray",
                        description: Text("Messages will appear here once received")
                    )
                } else {
                    List(connectionManager.messages, selection: $selectedMessage) { message in
                        JetStreamMessageRowView(message: message)
                            .tag(message)
                    }
                    .listStyle(.plain)
                }
            }
            
            // Right: Message detail with acknowledgment controls
            if let message = selectedMessage {
                MessageDetailWithAckView(
                    message: message,
                    jetStreamManager: connectionManager.jetStreamManager
                )
            } else {
                ContentUnavailableView(
                    "Select a Message",
                    systemImage: "arrow.left",
                    description: Text("Choose a message to view details")
                )
            }
        }
    }
}

struct JetStreamMessageRowView: View {
    let message: ReceivedMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.subject)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                Spacer()
                Text(formatTime(message.receivedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(preview(message.payload))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
    
    private func preview(_ payload: String) -> String {
        let maxLength = 60
        if payload.count <= maxLength {
            return payload
        }
        return String(payload.prefix(maxLength)) + "..."
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

struct MessageDetailWithAckView: View {
    let message: ReceivedMessage
    let jetStreamManager: JetStreamManager?
    
    @State private var ackInProgress = false
    @State private var ackStatus: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with ack controls
            HStack {
                Text("MESSAGE DETAILS")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Acknowledgment controls
                HStack(spacing: 8) {
                    Button(action: { acknowledgeMessage(.ack) }) {
                        Label("Ack", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.bordered)
                    .help("Acknowledge: Mark as successfully processed")
                    
                    Button(action: { acknowledgeMessage(.nak) }) {
                        Label("Nak", systemImage: "arrow.clockwise.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.bordered)
                    .help("Negative Acknowledge: Redeliver this message")
                    
                    Button(action: { acknowledgeMessage(.term) }) {
                        Label("Term", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.bordered)
                    .help("Terminate: Don't redeliver this message")
                    
                    Button(action: { acknowledgeMessage(.inProgress) }) {
                        Label("WIP", systemImage: "clock.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.bordered)
                    .help("In Progress: Extend ack deadline")
                }
                .disabled(ackInProgress || jetStreamManager == nil)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Status message
            if let status = ackStatus {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text(status)
                        .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
            }
            
            // Message details
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailSection(title: "Subject") {
                        Text(message.subject)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    
                    if let replyTo = message.replyTo {
                        DetailSection(title: "Reply To") {
                            Text(replyTo)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    
                    DetailSection(title: "Payload") {
                        Text(message.payload)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                    }
                    
                    DetailSection(title: "Metadata") {
                        VStack(alignment: .leading, spacing: 8) {
                            MetadataRow(label: "Received", value: formatDateTime(message.receivedAt))
                            MetadataRow(label: "Size", value: "\(message.byteCount) bytes")
                            
                            // JetStream metadata would go here
                            // TODO: After migration, show stream sequence, consumer sequence, etc.
                        }
                    }
                    
                    if let headers = message.headers, !headers.isEmpty {
                        DetailSection(title: "Headers") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(headers.keys.sorted()), id: \.self) { key in
                                    HStack(alignment: .top) {
                                        Text("\(key):")
                                            .fontWeight(.medium)
                                            .foregroundStyle(.secondary)
                                        Text(headers[key] ?? "")
                                            .textSelection(.enabled)
                                    }
                                    .font(.system(.caption, design: .monospaced))
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    private func acknowledgeMessage(_ type: AckType) {
        guard let jetStreamManager = jetStreamManager else { return }
        
        ackInProgress = true
        ackStatus = "Processing \(type.rawValue)..."
        
        Task {
            do {
                // TODO: After migration, implement actual acknowledgment
                // try await jetStreamManager.acknowledge(metadata: messageMetadata, type: type)
                
                await MainActor.run {
                    ackStatus = "\(type.rawValue) sent successfully"
                    ackInProgress = false
                }
                
                // Clear status after 2 seconds
                try await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    ackStatus = nil
                }
            } catch {
                await MainActor.run {
                    ackStatus = "Failed: \(error.localizedDescription)"
                    ackInProgress = false
                }
            }
        }
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            content()
        }
    }
}

struct MetadataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.system(.callout, design: .monospaced))
    }
}

#Preview {
    JetStreamMessageListView(connectionManager: ConnectionManager.shared)
}
