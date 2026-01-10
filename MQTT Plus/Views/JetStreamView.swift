//
//  JetStreamView.swift
//  MQTT Plus
//
//  Created by Antigravity on 10/01/26.
//

import SwiftUI

struct JetStreamView: View {
    @ObservedObject var connectionManager: ConnectionManager
    @State private var selectedStreamName: String?
    @State private var selectedConsumerName: String?
    @State private var showingStreamCreator = false
    @State private var showingConsumerCreator = false
    @State private var showingPublishSheet = false
    @State private var showingConsole = false
    @State private var showingInspector = false

    private var selectedStream: MQStreamInfo? {
        guard let selectedStreamName else { return nil }
        return connectionManager.streams.first { $0.name == selectedStreamName }
    }

    private var selectedConsumer: MQConsumerInfo? {
        guard let selectedStreamName, let selectedConsumerName else { return nil }
        return (connectionManager.consumers[selectedStreamName] ?? []).first { $0.name == selectedConsumerName }
    }

    private var consumersForSelectedStream: [MQConsumerInfo] {
        guard let selectedStreamName else { return [] }
        return connectionManager.consumers[selectedStreamName] ?? []
    }
    
    var body: some View {
        GeometryReader { _ in
            HSplitView {
                // Left: Stream List
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        Text("STREAMS")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(action: { showingStreamCreator = true }) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help("Create Stream")
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .frame(height: 44) // Explicit header height
                    
                    Divider()
                    
                    // Stream list
                    if connectionManager.connectionState != .connected {
                        ContentUnavailableView(
                            "Not Connected",
                            systemImage: "bolt.horizontal.circle",
                            description: Text("Connect to view JetStream streams")
                        )
                    } else if connectionManager.streams.isEmpty {
                        ContentUnavailableView(
                            "No Streams",
                            systemImage: "cylinder",
                            description: Text("Create a stream to get started")
                        )
                    } else {
                        List(selection: $selectedStreamName) {
                            ForEach(connectionManager.streams) { stream in
                                StreamRowView(stream: stream)
                                    .tag(stream.name)
                            }
                        }
                        .listStyle(.sidebar)
                        .scrollContentBackground(.hidden)
                    }
                }
                .frame(minWidth: 200, maxWidth: 300)
                .frame(maxHeight: .infinity, alignment: .top) // Align top
                
                // Middle: Consumer List
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        if let streamName = selectedStreamName {
                            Text("CONSUMERS: \(streamName)")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(action: { showingConsumerCreator = true }) {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.borderless)
                            .help("Create Consumer")
                        } else {
                            Text("SELECT A STREAM")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .frame(height: 44)
                    
                    Divider()
                    
                    if let streamName = selectedStreamName {
                        if consumersForSelectedStream.isEmpty {
                            ContentUnavailableView(
                                "No Consumers",
                                systemImage: "tray",
                                description: Text("Create a consumer to start receiving messages")
                            )
                        } else {
                            List(selection: $selectedConsumerName) {
                                ForEach(consumersForSelectedStream) { consumer in
                                    ConsumerRowView(consumer: consumer)
                                        .tag(consumer.name)
                                }
                            }
                            .listStyle(.sidebar)
                            .scrollContentBackground(.hidden)
                        }
                    } else {
                        ContentUnavailableView(
                            "Select a Stream",
                            systemImage: "arrow.left",
                            description: Text("Choose a stream to view its consumers")
                        )
                    }
                }
                .frame(minWidth: 200, maxWidth: 300)
                .frame(maxHeight: .infinity, alignment: .top) // Align top
                
                // Right: Messages with Console/Inspector
                VSplitView {
                    VStack(spacing: 0) {
                        // Toolbar
                        HStack(spacing: MQSpacing.md) {
                            if let consumer = selectedConsumer {
                                VStack(alignment: .leading, spacing: MQSpacing.xxs) {
                                    Text(consumer.name)
                                        .font(.system(.headline, weight: .semibold))
                                    Text("Stream: \(consumer.streamName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Select a consumer")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            // Action buttons group
                            HStack(spacing: MQSpacing.sm) {
                                if selectedStreamName != nil {
                                    Button(action: { showingPublishSheet = true }) {
                                        Label("Publish", systemImage: "paperplane.fill")
                                    }
                                }
                                
                                Button(action: { connectionManager.clearJetStreamMessages() }) {
                                    Label("Clear", systemImage: "trash")
                                }
                                Button(action: { connectionManager.refresh() }) {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }
                                .help("Refresh Streams and Consumers (Cmd+R)")
                                .keyboardShortcut("r", modifiers: .command)
                            }
                            
                            Divider()
                                .frame(height: 20)
                            
                            // Panels group
                            HStack(spacing: MQSpacing.sm) {
                                Toggle(isOn: $showingInspector) {
                                    Label("Inspector", systemImage: "gauge.with.dots.needle.bottom.50percent")
                                }
                                .toggleStyle(.button)
                                .help("Toggle Broker Inspector")
                                
                                Toggle(isOn: $showingConsole) {
                                    Label("Console", systemImage: "terminal")
                                }
                                .toggleStyle(.button)
                                .help("Toggle Connection Logs")
                            }
                        }
                        .padding(.horizontal, MQSpacing.xl)
                        .padding(.vertical, MQSpacing.lg)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .frame(height: 44)
                        
                        Divider()
                        
                        // Message list with JetStream controls
                        if selectedConsumerName != nil {
                            JetStreamMessageListView(connectionManager: connectionManager)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ContentUnavailableView(
                                "No Consumer Selected",
                                systemImage: "arrow.left",
                                description: Text("Select a consumer to view its messages")
                            )
                        }
                    }
                    .frame(minHeight: 200, maxHeight: .infinity)
                    
                    // Console Panel
                    if showingConsole {
                        ConsoleView(connectionManager: connectionManager)
                            .frame(minHeight: 100, maxHeight: 300)
                            .transition(.move(edge: .bottom))
                    }
                    
                    // Broker Inspector Panel
                    if showingInspector {
                        BrokerInspectorPanel(connectionManager: connectionManager)
                            .frame(minHeight: 150, maxHeight: .infinity)
                            .transition(.move(edge: .bottom))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showingStreamCreator) {
            StreamCreatorSheet(
                connectionManager: connectionManager,
                isPresented: $showingStreamCreator
            )
        }
        .sheet(isPresented: $showingConsumerCreator) {
            if let streamName = selectedStreamName {
                ConsumerCreatorSheet(
                    connectionManager: connectionManager,
                    streamName: streamName,
                    isPresented: $showingConsumerCreator
                )
            }
        }
        .sheet(isPresented: $showingPublishSheet) {
            if let streamName = selectedStreamName {
                JetStreamPublishSheet(
                    connectionManager: connectionManager,
                    streamName: streamName,
                    isPresented: $showingPublishSheet
                )
            }
        }
        .onAppear {
            Task {
                await connectionManager.refreshStreams()
            }
        }
        .onChange(of: selectedStreamName) { _, newValue in
            selectedConsumerName = nil
            connectionManager.stopJetStreamConsume()
            connectionManager.clearJetStreamMessages()

            if let streamName = newValue {
                Task {
                    await connectionManager.refreshConsumers(for: streamName)
                }
            }
        }
        .onChange(of: selectedConsumerName) { _, newValue in
            connectionManager.stopJetStreamConsume()
            connectionManager.clearJetStreamMessages()

            guard let streamName = selectedStreamName,
                  let consumerName = newValue else { return }
            connectionManager.startJetStreamConsume(stream: streamName, consumer: consumerName)
        }
    }
}

// MARK: - Stream Row

struct StreamRowView: View {
    let stream: MQStreamInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: MQSpacing.sm) {
            HStack {
                Label(stream.name, systemImage: "cylinder")
                    .font(.system(.body, weight: .medium))
                Spacer()
            }
            
            HStack(spacing: MQSpacing.lg) {
                Label("\\(stream.messageCount)", systemImage: "envelope")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Label(formatBytes(stream.byteCount), systemImage: "chart.bar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Text(stream.storage.rawValue)
                    .mqBadge(color: .blue, small: true)
            }
        }
        .padding(.vertical, MQSpacing.sm)
        .mqRowHover()
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Consumer Row

struct ConsumerRowView: View {
    let consumer: MQConsumerInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: MQSpacing.sm) {
            HStack {
                Label(consumer.name, systemImage: consumer.durable ? "pin.fill" : "pin.slash")
                    .font(.system(.body, weight: .medium))
                Spacer()
            }
            
            HStack(spacing: MQSpacing.lg) {
                Label("\\(consumer.pending)", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                
                Label("\\(consumer.delivered)", systemImage: "checkmark")
                    .font(.caption2)
                    .foregroundStyle(.green)
                
                Text(consumer.ackPolicy.rawValue)
                    .mqBadge(color: .purple, small: true)
            }
        }
        .padding(.vertical, MQSpacing.sm)
        .mqRowHover()
    }
}

#Preview {
    JetStreamView(connectionManager: ConnectionManager())
}
