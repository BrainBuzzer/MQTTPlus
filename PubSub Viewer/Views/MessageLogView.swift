//
//  MessageLogView.swift
//  PubSub Viewer
//
//  Created by Aditya on 10/01/26.
//

import SwiftUI

struct MessageLogView: View {
    let messages: [ReceivedMessage]
    @ObservedObject var connectionManager: ConnectionManager
    var onRepublish: ((ReceivedMessage) -> Void)?
    
    @State private var selectedMessage: ReceivedMessage?
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    var body: some View {
        if messages.isEmpty {
            ContentUnavailableView(
                "No Messages",
                systemImage: "tray",
                description: Text("Messages will appear here when received")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                // Message list
                List(selection: $selectedMessage) {
                    ForEach(messages) { message in
                        MessageRowView(message: message, dateFormatter: dateFormatter, onRepublish: onRepublish)
                            .tag(message)
                    }
                }
                .listStyle(.plain)
                .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
                
                // Message detail
                if let message = selectedMessage {
                    MessageDetailView(message: message, dateFormatter: dateFormatter, onRepublish: onRepublish)
                        .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "Select a Message",
                        systemImage: "doc.text",
                        description: Text("Click on a message to view details")
                    )
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

struct MessageRowView: View {
    let message: ReceivedMessage
    let dateFormatter: DateFormatter
    var onRepublish: ((ReceivedMessage) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(message.subject)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                if message.headers != nil {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Has Headers")
                }
                
                Text(ByteCountFormatter.string(fromByteCount: Int64(message.byteCount), countStyle: .memory))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
                
                Text(dateFormatter.string(from: message.receivedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            
            Text(message.payload)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(2)
                .foregroundStyle(.primary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button {
                onRepublish?(message)
            } label: {
                Label("Republish", systemImage: "paperplane")
            }
        }
    }
}

struct MessageDetailView: View {
    let message: ReceivedMessage
    let dateFormatter: DateFormatter
    var onRepublish: ((ReceivedMessage) -> Void)?
    
    @State private var formattedPayload: String = ""
    @State private var isValidJSON: Bool = false
    @State private var selectedTab: PayloadTab = .preview
    
    enum PayloadTab: String, CaseIterable, Identifiable {
        case preview = "Preview"
        case raw = "Raw"
        case hex = "Hex"
        var id: String { rawValue }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Info
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Top Info Row
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            DetailRow(label: "Subject", value: message.subject, font: .title3)
                            if let replyTo = message.replyTo, !replyTo.isEmpty {
                                DetailRow(label: "Reply-To", value: replyTo, font: .body)
                                    .padding(.top, 4)
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Label(dateFormatter.string(from: message.receivedAt), systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            
                            Text(ByteCountFormatter.string(fromByteCount: Int64(message.byteCount), countStyle: .memory))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    // Headers Section
                    if let headers = message.headers, !headers.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("HEADERS")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                                ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                    GridRow {
                                        Text(key)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .gridColumnAlignment(.trailing)
                                        Text(value)
                                            .font(.system(.body, design: .monospaced))
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                            )
                        }
                        Divider()
                    }
                    
                    // Payload Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("PAYLOAD")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Picker("View", selection: $selectedTab) {
                                ForEach(PayloadTab.allCases) { tab in
                                    Text(tab.rawValue).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }
                        
                        Group {
                            switch selectedTab {
                            case .preview:
                                PayloadContentView(text: formattedPayload, isJSON: isValidJSON)
                            case .raw:
                                PayloadContentView(text: message.payload, isJSON: false)
                            case .hex:
                                PayloadContentView(text: message.payload.hexDump, isJSON: false)
                            }
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Actions Footer
            HStack {
                if isValidJSON {
                    Label("JSON Detected", systemImage: "curlybraces")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                
                Spacer()
                
                Button(action: copyToClipboard) {
                    Label("Copy Payload", systemImage: "doc.on.doc")
                }
                
                Button(action: { onRepublish?(message) }) {
                    Label("Republish", systemImage: "paperplane")
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear { formatPayload() }
        .onChange(of: message) { formatPayload() }
    }
    
    private func formatPayload() {
        // Try to format as JSON
        if let data = message.payload.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            formattedPayload = prettyString
            isValidJSON = true
        } else {
            formattedPayload = message.payload
            isValidJSON = false
        }
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            selectedTab == .raw ? message.payload : formattedPayload,
            forType: .string
        )
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var font: Font = .body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(font)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
    }
}

struct PayloadContentView: View {
    let text: String
    let isJSON: Bool
    
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .multilineTextAlignment(.leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isJSON ? Color.green.opacity(0.3) : Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .frame(minHeight: 100, maxHeight: 400)
    }
}

extension String {
    var hexDump: String {
        guard let data = self.data(using: .utf8) else { return "" }
        return data.map { String(format: "%02x", $0) }
            .joined(separator: " ")
    }
}

#Preview {
    let msg = ReceivedMessage(
        subject: "orders.new",
        payload: "{\"id\": 123, \"item\": \"Apple\"}",
        headers: ["Trace-ID": "abc-123", "Environment": "Prod"],
        replyTo: "orders.replies.123",
        byteCount: 128,
        receivedAt: Date()
    )
    return MessageLogView(messages: [msg], connectionManager: ConnectionManager())
}
