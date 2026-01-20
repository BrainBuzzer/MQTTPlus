//
//  BrokerDetailView.swift
//  MQTT Plus
//
//  Main dashboard container for broker inspector views
//  Dynamically switches between NATS, Redis, and Kafka inspectors
//

import SwiftUI

// MARK: - Broker Detail View

/// Main container view that orchestrates broker-specific inspector views
struct BrokerDetailView: View {
    @StateObject private var metricsProvider = MockBrokerMetricsProvider()
    @State private var isInspectorExpanded = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Backend selector
                backendPicker
                
                // Dynamic inspector view
                inspectorView
                    .animation(.spring(duration: 0.3), value: metricsProvider.selectedBrokerType)
                
                // Message feed placeholder
                messageFeedSection
            }
            .padding()
        }
        .background {
            // Subtle gradient background
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .windowBackgroundColor).opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .navigationTitle("Broker Inspector")
    }
    
    // MARK: - Backend Picker
    
    private var backendPicker: some View {
        HStack {
            Text("Backend")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            
            Picker("Backend", selection: $metricsProvider.selectedBrokerType) {
                ForEach(BrokerType.allCases) { type in
                    Label(type.displayName, systemImage: type.iconName)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            
            Spacer()
            
            // Refresh/status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Live")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .cornerRadius(6)
        }
    }
    
    // MARK: - Dynamic Inspector View
    
    @ViewBuilder
    private var inspectorView: some View {
        switch metricsProvider.selectedBrokerType {
        case .nats:
            NatsInspectorView(
                isExpanded: $isInspectorExpanded,
                metrics: metricsProvider.natsMetrics,
                lagHistory: metricsProvider.natsLagHistory.points,
                msgHistory: metricsProvider.natsMsgHistory.points
            )
            
        case .redis:
            RedisInspectorView(
                isExpanded: $isInspectorExpanded,
                metrics: metricsProvider.redisMetrics,
                opsHistory: metricsProvider.redisOpsHistory.points,
                memoryHistory: metricsProvider.redisMemoryHistory.points
            )
            
        case .kafka:
            KafkaInspectorView(
                isExpanded: $isInspectorExpanded,
                metrics: metricsProvider.kafkaMetrics,
                lagHistory: metricsProvider.kafkaLagHistory.points,
                urpHistory: metricsProvider.kafkaUrpHistory.points
            )
            
        case .rabbitmq:
            RabbitMQInspectorView(
                isExpanded: $isInspectorExpanded,
                metrics: metricsProvider.rabbitmqMetrics,
                publishHistory: metricsProvider.rabbitmqPublishHistory.points,
                deliverHistory: metricsProvider.rabbitmqDeliverHistory.points
            )
        }
    }
    
    // MARK: - Message Feed Section
    
    private var messageFeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Message Feed", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                
                Spacer()
                
                Text(backendMetadataLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .cornerRadius(6)
            }
            
            // Placeholder message list
            messageFeedPlaceholder
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }
    
    private var backendMetadataLabel: String {
        switch metricsProvider.selectedBrokerType {
        case .nats: return "Showing Sequence Numbers"
        case .redis: return "Showing Channel Metadata"
        case .kafka: return "Showing Partition IDs"
        case .rabbitmq: return "Showing Queue Names"
        }
    }
    
    private var messageFeedPlaceholder: some View {
        VStack(spacing: 8) {
            ForEach(0..<5) { index in
                MessageRowPlaceholder(
                    brokerType: metricsProvider.selectedBrokerType,
                    index: index
                )
            }
        }
    }
}

// MARK: - Message Row Placeholder

private struct MessageRowPlaceholder: View {
    let brokerType: BrokerType
    let index: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // Backend-specific metadata badge
            metadataBadge
            
            VStack(alignment: .leading, spacing: 2) {
                Text(sampleSubject)
                    .font(.subheadline.weight(.medium))
                
                Text(samplePayload)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(sampleTimestamp)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.background)
        }
    }
    
    @ViewBuilder
    private var metadataBadge: some View {
        switch brokerType {
        case .nats:
            // Sequence number
            Text("seq:\(1000 + index)")
                .font(.caption2.monospaced())
                .foregroundStyle(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.1))
                .cornerRadius(4)
            
        case .redis:
            // Channel info
            Text("ch:events")
                .font(.caption2.monospaced())
                .foregroundStyle(.red)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.red.opacity(0.1))
                .cornerRadius(4)
            
        case .kafka:
            // Partition ID
            Text("p:\(index % 3)")
                .font(.caption2.monospaced())
                .foregroundStyle(.purple)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.purple.opacity(0.1))
                .cornerRadius(4)
            
        case .rabbitmq:
            // Queue name
            Text("q:tasks")
                .font(.caption2.monospaced())
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.1))
                .cornerRadius(4)
        }
    }
    
    private var sampleSubject: String {
        switch brokerType {
        case .nats: return "orders.created.\(["us", "eu", "ap"][index % 3])"
        case .redis: return "events:\(["user", "order", "payment"][index % 3])"
        case .kafka: return "transactions-\(["prod", "staging"][index % 2])"
        case .rabbitmq: return "tasks.\(["email", "sms", "push"][index % 3])"
        }
    }
    
    private var samplePayload: String {
        "{\"id\": \"abc-\(index)\", \"type\": \"sample\", \"data\": {...}}"
    }
    
    private var sampleTimestamp: String {
        "12:34:\(String(format: "%02d", 50 + index))"
    }
}

// MARK: - Preview

#Preview("Broker Detail View") {
    BrokerDetailView()
        .frame(width: 500, height: 700)
}

#Preview("Dark Mode") {
    BrokerDetailView()
        .frame(width: 500, height: 700)
        .preferredColorScheme(.dark)
}
