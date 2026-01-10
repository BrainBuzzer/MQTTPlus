//
//  NatsInspectorView.swift
//  MQTT Plus
//
//  Collapsible inspector view for NATS/JetStream metrics
//  Displays stream health, message counts, and consumer lag
//

import SwiftUI

// MARK: - NATS Inspector View

/// Collapsible detail view for NATS JetStream metrics
struct NatsInspectorView: View {
    @Binding var isExpanded: Bool
    let metrics: NatsMetrics
    let lagHistory: [MetricHistoryPoint]
    let msgHistory: [MetricHistoryPoint]
    
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
            // Icon
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("NATS JetStream")
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
            // Stream info header
            streamInfoHeader
            
            // Metric cards grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                MetricCardView(
                    title: "Messages",
                    value: metrics.msgCount,
                    unit: "total",
                    status: .healthy,
                    history: msgHistory
                )
                
                MetricCardView(
                    title: "Storage",
                    value: metrics.byteCountFormatted,
                    status: .healthy,
                    history: [],
                    showSparkline: false
                )
                
                MetricCardView(
                    title: "Consumer Lag",
                    value: metrics.consumerLag,
                    unit: "msgs",
                    status: lagStatus,
                    history: lagHistory
                )
                
                MetricCardView(
                    title: "Slow Consumers",
                    value: "\(metrics.slowConsumerCount)",
                    status: slowConsumerStatus,
                    history: [],
                    showSparkline: false
                )
            }
            
            Divider()
            
            // Additional details
            detailsSection
        }
        .padding(.top, 8)
    }
    
    private var streamInfoHeader: some View {
        HStack {
            Label(metrics.streamName, systemImage: "shippingbox.fill")
                .font(.subheadline.weight(.medium))
            
            Spacer()
            
            HStack(spacing: 4) {
                Image(systemName: metrics.storageType == .file ? "internaldrive.fill" : "memorychip.fill")
                Text(metrics.storageType.rawValue)
            }
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
            Text("Stream Details")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    Text("Storage Type")
                        .foregroundStyle(.secondary)
                    Text(metrics.storageType.rawValue)
                        .fontWeight(.medium)
                }
                
                GridRow {
                    Text("Total Bytes")
                        .foregroundStyle(.secondary)
                    Text(metrics.byteCountFormatted)
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
    
    // MARK: - Helpers
    
    private var lagStatus: HealthStatus {
        if metrics.consumerLag > 10000 { return .critical }
        if metrics.consumerLag > 1000 { return .warning }
        return .healthy
    }
    
    private var slowConsumerStatus: HealthStatus {
        if metrics.slowConsumerCount > 5 { return .critical }
        if metrics.slowConsumerCount > 0 { return .warning }
        return .healthy
    }
    
    private func statusColor(for status: HealthStatus) -> Color {
        switch status {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: HealthStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            
            Text(status.rawValue.capitalized)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .cornerRadius(4)
    }
    
    private var color: Color {
        switch status {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Custom Disclosure Style

struct InspectorDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack {
                    configuration.label
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            
            if configuration.isExpanded {
                configuration.content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
}

// MARK: - Preview

#Preview("NATS Inspector") {
    VStack {
        NatsInspectorView(
            isExpanded: .constant(true),
            metrics: NatsMetrics(
                streamName: "ORDERS",
                storageType: .file,
                msgCount: 1_234_567,
                byteCount: 512_000_000,
                consumerLag: 1500,
                slowConsumerCount: 1
            ),
            lagHistory: (0..<30).map { i in
                MetricHistoryPoint(
                    timestamp: Date().addingTimeInterval(Double(-30 + i)),
                    value: Double.random(in: 100...2000)
                )
            },
            msgHistory: (0..<30).map { i in
                MetricHistoryPoint(
                    timestamp: Date().addingTimeInterval(Double(-30 + i)),
                    value: 1_234_000 + Double(i * 100)
                )
            }
        )
    }
    .padding()
    .frame(width: 450)
    .background(Color.gray.opacity(0.1))
}
