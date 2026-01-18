//
//  MessageLogView.swift
//  MQTT Plus
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
            MQEmptyState(
                icon: "tray",
                title: "No Messages",
                description: "Messages will appear here when received. Subscribe to a subject to start receiving."
            )
        } else {
            HSplitView {
                List(selection: $selectedMessage) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        MessageRowView(message: message, dateFormatter: dateFormatter, onRepublish: onRepublish, index: index)
                            .tag(message)
                    }
                }
                .listStyle(.plain)
                .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
                
                if let message = selectedMessage {
                    MessageDetailView(message: message, dateFormatter: dateFormatter, onRepublish: onRepublish)
                        .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    MQEmptyState(
                        icon: "doc.text.magnifyingglass",
                        title: "Select a Message",
                        description: "Click on a message from the list to view its details and payload.",
                        animate: false
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
    var index: Int = 0
    
    private var ageColor: Color {
        let age = Date().timeIntervalSince(message.receivedAt)
        if age < 1 { return .green }
        if age < 5 { return .blue }
        return .clear
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(ageColor)
                .frame(width: 3)
                .animation(MQAnimation.quick, value: ageColor)
            
            VStack(alignment: .leading, spacing: MQSpacing.sm) {
                HStack(spacing: MQSpacing.md) {
                    Text(message.subject)
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    HStack(spacing: MQSpacing.sm) {
                        if message.headers != nil {
                            Image(systemName: "doc.text")
                                .font(.caption2)
                                .foregroundStyle(.blue.opacity(0.7))
                                .help("Has Headers")
                        }
                        
                        Text(ByteCountFormatter.string(fromByteCount: Int64(message.byteCount), countStyle: .memory))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        
                        Text(dateFormatter.string(from: message.receivedAt))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Text(message.payload)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, MQSpacing.md)
            .padding(.horizontal, MQSpacing.lg)
        }
        .background(index % 2 == 0 ? Color.clear : Color.primary.opacity(0.02))
        .mqRowHover()
        .contextMenu {
            Button {
                onRepublish?(message)
            } label: {
                Label("Republish", systemImage: "paperplane")
            }
            
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.payload, forType: .string)
            } label: {
                Label("Copy Payload", systemImage: "doc.on.doc")
            }
            
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.subject, forType: .string)
            } label: {
                Label("Copy Subject", systemImage: "tag")
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
    @State private var showingExpandedPayload = false
    
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
                            
                            Button(action: { showingExpandedPayload = true }) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                            }
                            .buttonStyle(.borderless)
                            .help("Expand payload in a separate window")
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
        .sheet(isPresented: $showingExpandedPayload) {
            ExpandedPayloadView(
                payload: selectedTab == .hex ? message.payload.hexDump : (selectedTab == .raw ? message.payload : formattedPayload),
                isJSON: selectedTab == .preview && isValidJSON,
                subject: message.subject,
                isPresented: $showingExpandedPayload
            )
        }
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
    
    private var displayContent: Text {
        if isJSON {
            return Text(JSONSyntaxHighlighter.highlightSimple(text))
        } else {
            return Text(text)
                .font(.system(.body, design: .monospaced))
        }
    }
    
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            displayContent
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .multilineTextAlignment(.leading)
                .padding(MQSpacing.xl)
        }
        .frame(minHeight: 100, maxHeight: 400, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(MQRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: MQRadius.lg)
                .stroke(isJSON ? Color.green.opacity(0.4) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

struct ExpandedPayloadView: View {
    let payload: String
    let isJSON: Bool
    let subject: String
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Payload Preview")
                        .font(.headline)
                    Text(subject)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: copyToClipboard) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            ScrollView([.horizontal, .vertical]) {
                Group {
                    if isJSON {
                        Text(JSONSyntaxHighlighter.highlightSimple(payload))
                    } else {
                        Text(payload)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .multilineTextAlignment(.leading)
                .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 600, idealWidth: 800, minHeight: 400, idealHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
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
