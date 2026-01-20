//
//  RabbitMQInspectorView.swift
//  MQTT Plus
//
//  Collapsible inspector view for RabbitMQ metrics
//  Displays publish/deliver counts, channels, and consumers
//

import SwiftUI

// MARK: - RabbitMQ Inspector View

struct RabbitMQInspectorView: View {
    @Binding var isExpanded: Bool
    let metrics: RabbitMQMetrics
    let publishHistory: [MetricHistoryPoint]
    let deliverHistory: [MetricHistoryPoint]
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            expandedContent
        } label: {
            collapsedLabel
        }
        .disclosureGroupStyle(InspectorDisclosureStyle())
    }
    
    // MARK: - Collapsed Label
    
    private var collapsedLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.title2)
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("RabbitMQ")
                        .font(.headline)
                    
                    StatusBadge(status: metrics.healthStatus)
                }
                
                Text(metrics.healthSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Expanded Content
    
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            serverInfoHeader
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                MetricCardView(
                    title: "Published",
                    value: "\(metrics.messagesPublished)",
                    unit: "msgs",
                    status: .healthy,
                    history: publishHistory
                )
                
                MetricCardView(
                    title: "Delivered",
                    value: "\(metrics.messagesDelivered)",
                    unit: "msgs",
                    status: .healthy,
                    history: deliverHistory
                )
                
                MetricCardView(
                    title: "Channels",
                    value: "\(metrics.channelCount)",
                    status: .healthy,
                    history: [],
                    showSparkline: false
                )
                
                MetricCardView(
                    title: "Consumers",
                    value: "\(metrics.consumerCount)",
                    status: .healthy,
                    history: [],
                    showSparkline: false
                )
            }
            
            HStack(spacing: 12) {
                CompactMetricCardView(
                    title: "Bytes Published",
                    value: metrics.bytesPublishedFormatted,
                    status: .healthy
                )
                
                CompactMetricCardView(
                    title: "Bytes Delivered",
                    value: metrics.bytesDeliveredFormatted,
                    status: .healthy
                )
            }
            
            Divider()
            
            detailsSection
        }
        .padding(.top, 8)
    }
    
    private var serverInfoHeader: some View {
        HStack {
            Label("RabbitMQ Server", systemImage: "server.rack")
                .font(.subheadline.weight(.medium))
            
            Spacer()
            
            Text("AMQP 0-9-1")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary)
                .cornerRadius(6)
        }
    }
    
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connection Details")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    Text("Messages Published")
                        .foregroundStyle(.secondary)
                    Text("\(metrics.messagesPublished)")
                        .fontWeight(.medium)
                }
                
                GridRow {
                    Text("Messages Delivered")
                        .foregroundStyle(.secondary)
                    Text("\(metrics.messagesDelivered)")
                        .fontWeight(.medium)
                }
                
                GridRow {
                    Text("Data Published")
                        .foregroundStyle(.secondary)
                    Text(metrics.bytesPublishedFormatted)
                        .fontWeight(.medium)
                }
                
                GridRow {
                    Text("Data Delivered")
                        .foregroundStyle(.secondary)
                    Text(metrics.bytesDeliveredFormatted)
                        .fontWeight(.medium)
                }
                
                GridRow {
                    Text("Health Status")
                        .foregroundStyle(.secondary)
                    HStack {
                        Circle()
                            .fill(statusColor(for: metrics.healthStatus))
                            .frame(width: 8, height: 8)
                        Text(metrics.healthStatus.description)
                    }
                }
            }
            .font(.caption)
        }
    }
    
    private func statusColor(for status: HealthStatus) -> Color {
        switch status {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Preview

#Preview("RabbitMQ Inspector") {
    VStack {
        RabbitMQInspectorView(
            isExpanded: .constant(true),
            metrics: RabbitMQMetrics(
                messagesPublished: 1234,
                messagesDelivered: 987,
                bytesPublished: 512_000,
                bytesDelivered: 384_000,
                channelCount: 3,
                consumerCount: 2
            ),
            publishHistory: (0..<30).map { i in
                MetricHistoryPoint(
                    timestamp: Date().addingTimeInterval(Double(-30 + i)),
                    value: Double.random(in: 1000...1500)
                )
            },
            deliverHistory: (0..<30).map { i in
                MetricHistoryPoint(
                    timestamp: Date().addingTimeInterval(Double(-30 + i)),
                    value: Double.random(in: 800...1100)
                )
            }
        )
    }
    .padding()
    .frame(width: 450)
    .background(Color.gray.opacity(0.1))
}
