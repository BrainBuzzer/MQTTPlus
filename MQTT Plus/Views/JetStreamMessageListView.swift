//
//  JetStreamMessageListView.swift
//  MQTT Plus
//
//  Created by Antigravity on 10/01/26.
//

import SwiftUI

struct JetStreamMessageListView: View {
    @ObservedObject var connectionManager: ConnectionManager
    @State private var selectedMessage: JetStreamMessageEnvelope?
    
    var body: some View {
        if connectionManager.jetStreamMessages.isEmpty {
            ContentUnavailableView(
                "No Messages",
                systemImage: "tray",
                description: Text("Messages will appear here once received")
            )
        } else {
            HSplitView {
                // Left: Message list
                VStack(spacing: 0) {
                    List(connectionManager.jetStreamMessages, selection: $selectedMessage) { message in
                        JetStreamMessageRowView(message: message)
                            .tag(message)
                    }
                    .listStyle(.plain)
                }
                .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
                
                // Right: Message detail with acknowledgment controls
                ZStack {
                    if let message = selectedMessage {
                        MessageDetailWithAckView(
                            message: message,
                            connectionManager: connectionManager
                        )
                    } else {
                        ContentUnavailableView(
                            "Select a Message",
                            systemImage: "arrow.left",
                            description: Text("Choose a message to view details")
                        )
                    }
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct JetStreamMessageRowView: View {
    let message: JetStreamMessageEnvelope
    
    private var deliveryColor: Color {
        switch message.metadata.deliveryCount {
        case 1: return .green
        case 2...5: return .orange
        default: return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: MQSpacing.sm) {
            // Top row: Subject + badges
            HStack(spacing: MQSpacing.md) {
                Text(message.subject)
                    .font(.system(.body, design: .monospaced, weight: .medium))
                    .lineLimit(1)
                
                Spacer()
                
                // Delivery count badge
                HStack(spacing: MQSpacing.xxs) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                    Text("\(message.metadata.deliveryCount)")
                        .font(.caption2.weight(.semibold))
                }
                .padding(.horizontal, MQSpacing.sm)
                .padding(.vertical, MQSpacing.xxs)
                .foregroundStyle(deliveryColor)
                .background(deliveryColor.opacity(0.12))
                .cornerRadius(MQRadius.sm)
                .help("Delivery count: \(message.metadata.deliveryCount)")
                
                // Timestamp
                Text(formatTime(message.timestamp))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            
            // Bottom row: Preview + metadata
            HStack(spacing: MQSpacing.md) {
                Text(preview(message.payloadString))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                // Stream sequence badge
                Text("#\(message.metadata.streamSequence)")
                    .mqBadge(color: .blue, small: true)
                    .help("Stream sequence")
            }
        }
        .padding(.vertical, MQSpacing.md)
        .mqRowHover()
    }
    
    private func preview(_ payload: String) -> String {
        let maxLength = 50
        let trimmed = payload.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxLength {
            return trimmed
        }
        return String(trimmed.prefix(maxLength)) + "…"
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

struct MessageDetailWithAckView: View {
    let message: JetStreamMessageEnvelope
    @ObservedObject var connectionManager: ConnectionManager
    
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
                
                // Acknowledgment controls - icon-only with tooltips
                HStack(spacing: MQSpacing.sm) {
                    MQIconButton("checkmark.circle.fill", color: .green) {
                        acknowledgeMessage(.ack)
                    }
                    .help("Ack: Mark as processed")
                    
                    MQIconButton("arrow.clockwise", color: .orange) {
                        acknowledgeMessage(.nak)
                    }
                    .help("Nak: Redeliver message")
                    
                    MQIconButton("xmark", color: .red) {
                        acknowledgeMessage(.term)
                    }
                    .help("Term: Don't redeliver")
                    
                    MQIconButton("clock", color: .blue) {
                        acknowledgeMessage(.inProgress)
                    }
                    .help("WIP: Extend ack deadline")
                }
                .disabled(ackInProgress || connectionManager.connectionState != .connected)
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
            ScrollView([.horizontal, .vertical]) {
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
                        VStack(alignment: .leading, spacing: 8) {
                            // Action buttons
                            HStack(spacing: 8) {
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(message.payloadString, forType: .string)
                                }) {
                                    Label("Copy", systemImage: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Text("\(message.byteCount) bytes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                            }
                            
                            // Payload content
                            Text(message.payloadString)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
                    
                    DetailSection(title: "Metadata") {
                        VStack(alignment: .leading, spacing: 8) {
                            MetadataRow(label: "Time", value: formatDateTime(message.metadata.timestamp))
                            MetadataRow(label: "Size", value: "\(message.byteCount) bytes")
                            MetadataRow(label: "Stream", value: message.metadata.streamName)
                            MetadataRow(label: "Consumer", value: message.metadata.consumerName ?? "—")
                            MetadataRow(label: "Stream Seq", value: "\(message.metadata.streamSequence)")
                            MetadataRow(label: "Consumer Seq", value: message.metadata.consumerSequence.map { String($0) } ?? "—")
                            MetadataRow(label: "Delivered", value: "\(message.metadata.deliveryCount)")
                            MetadataRow(label: "Pending", value: "\(message.metadata.pending)")
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
    
    private func acknowledgeMessage(_ type: MQAckType) {
        ackInProgress = true
        ackStatus = "Processing \(type.rawValue)…"
        
        Task {
            do {
                try await connectionManager.acknowledgeJetStreamMessage(id: message.id, type: type)
                
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
    JetStreamMessageListView(connectionManager: ConnectionManager())
}
