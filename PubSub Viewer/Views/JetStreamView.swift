//
//  JetStreamView.swift
//  PubSub Viewer
//
//  Created by Antigravity on 10/01/26.
//

import SwiftUI

struct JetStreamView: View {
    @ObservedObject var natsManager: NatsManager
    @State private var selectedStream: StreamInfo?
    @State private var selectedConsumer: ConsumerInfo?
    @State private var showingStreamCreator = false
    @State private var showingConsumerCreator = false
    @State private var showingPublishSheet = false
    
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
                    if let jetStreamManager = natsManager.jetStreamManager {
                        List(jetStreamManager.streams, selection: $selectedStream) { stream in
                            StreamRowView(stream: stream)
                                .tag(stream)
                        }
                        .listStyle(.sidebar)
                        .scrollContentBackground(.hidden)
                    } else {
                        ContentUnavailableView(
                            "JetStream Not Available",
                            systemImage: "exclamationmark.triangle",
                            description: Text("Connect in JetStream mode to view streams")
                        )
                    }
                }
                .frame(minWidth: 200, maxWidth: 300)
                .frame(maxHeight: .infinity, alignment: .top) // Align top
                
                // Middle: Consumer List
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        if let stream = selectedStream {
                            Text("CONSUMERS: \(stream.name)")
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
                    
                    if let stream = selectedStream,
                       let jetStreamManager = natsManager.jetStreamManager {
                        let consumers = jetStreamManager.consumers.filter { $0.streamName == stream.name }
                        
                        if consumers.isEmpty {
                            ContentUnavailableView(
                                "No Consumers",
                                systemImage: "tray",
                                description: Text("Create a consumer to start fetching messages")
                            )
                        } else {
                            List(consumers, selection: $selectedConsumer) { consumer in
                                ConsumerRowView(consumer: consumer)
                                    .tag(consumer)
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
                
                // Right: Messages
                VStack(spacing: 0) {
                    // Toolbar
                    HStack {
                        if let consumer = selectedConsumer {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(consumer.name)
                                    .font(.headline)
                                Text("Stream: \(consumer.streamName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Select a consumer")
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if selectedStream != nil {
                            Button(action: { showingPublishSheet = true }) {
                                Label("Publish", systemImage: "paperplane.fill")
                            }
                        }
                        
                        Button(action: { natsManager.clearMessages() }) {
                            Label("Clear", systemImage: "trash")
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .frame(height: 44)
                    
                    Divider()
                    
                    // Message list with JetStream controls
                    if selectedConsumer != nil {
                        JetStreamMessageListView(natsManager: natsManager)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView(
                            "No Consumer Selected",
                            systemImage: "arrow.left",
                            description: Text("Select a consumer to view its messages")
                        )
                    }
                }
                // .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) // This one is handled by VSplit's nature but to be safe:
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showingStreamCreator) {
            if let jetStreamManager = natsManager.jetStreamManager {
                StreamCreatorSheet(
                    jetStreamManager: jetStreamManager,
                    isPresented: $showingStreamCreator
                )
            }
        }
        .sheet(isPresented: $showingConsumerCreator) {
            if let stream = selectedStream,
               let jetStreamManager = natsManager.jetStreamManager {
                ConsumerCreatorSheet(
                    jetStreamManager: jetStreamManager,
                    streamName: stream.name,
                    isPresented: $showingConsumerCreator
                )
            }
        }
        .sheet(isPresented: $showingPublishSheet) {
            if let stream = selectedStream,
               let jetStreamManager = natsManager.jetStreamManager {
                JetStreamPublishSheet(
                    jetStreamManager: jetStreamManager,
                    streamName: stream.name,
                    isPresented: $showingPublishSheet
                )
            }
        }
    }
}

// MARK: - Stream Row

struct StreamRowView: View {
    let stream: StreamInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(stream.name, systemImage: "cylinder")
                Spacer()
            }
            
            HStack(spacing: 12) {
                Label("\\(stream.messageCount)", systemImage: "envelope")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Label(formatBytes(stream.byteCount), systemImage: "chart.bar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Text(stream.storage.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(3)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Consumer Row

struct ConsumerRowView: View {
    let consumer: ConsumerInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(consumer.name, systemImage: consumer.durable ? "pin.fill" : "pin.slash")
                Spacer()
            }
            
            HStack(spacing: 12) {
                Label("\\(consumer.pending)", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                
                Label("\\(consumer.delivered)", systemImage: "checkmark")
                    .font(.caption2)
                    .foregroundStyle(.green)
                
                Text(consumer.ackPolicy.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(3)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    JetStreamView(natsManager: NatsManager.shared)
}
