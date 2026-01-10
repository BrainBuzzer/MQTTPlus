//
//  KafkaInspectorView.swift
//  MQTT Plus
//
//  Collapsible inspector view for Kafka metrics
//  Displays cluster health, partitions, and consumer lag
//

import SwiftUI

// MARK: - Kafka Inspector View

/// Collapsible detail view for Kafka metrics
struct KafkaInspectorView: View {
    @Binding var isExpanded: Bool
    let metrics: KafkaMetrics
    let lagHistory: [MetricHistoryPoint]
    let urpHistory: [MetricHistoryPoint]
    
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
            Image(systemName: "arrow.trianglehead.branch")
                .font(.title2)
                .foregroundStyle(.purple)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Kafka")
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
            // Cluster info header
            clusterInfoHeader
            
            // Warning banner for URPs
            if metrics.underReplicatedPartitions > 0 {
                urpWarningBanner
            }
            
            // Metric cards grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                MetricCardView(
                    title: "Partitions",
                    value: "\(metrics.partitionCount)",
                    status: .healthy,
                    history: [],
                    showSparkline: false
                )
                
                MetricCardView(
                    title: "Under-Replicated",
                    value: "\(metrics.underReplicatedPartitions)",
                    unit: "URPs",
                    status: urpStatus,
                    history: urpHistory
                )
                
                MetricCardView(
                    title: "Consumer Group Lag",
                    value: metrics.consumerGroupLag,
                    unit: "msgs",
                    status: lagStatus,
                    history: lagHistory
                )
                
                MetricCardView(
                    title: "ISR Shrink Rate",
                    value: metrics.isrShrinkRate,
                    format: "%.3f",
                    unit: "/s",
                    status: isrStatus,
                    history: [],
                    showSparkline: false
                )
            }
            
            // Log offset row
            HStack(spacing: 12) {
                CompactMetricCardView(
                    title: "Log End Offset",
                    value: metrics.logEndOffset.formatted(),
                    status: .healthy
                )
            }
            
            Divider()
            
            // Additional details
            detailsSection
        }
        .padding(.top, 8)
    }
    
    private var clusterInfoHeader: some View {
        HStack {
            Label("Kafka Cluster", systemImage: "cube.transparent")
                .font(.subheadline.weight(.medium))
            
            Spacer()
            
            Text("Distributed Log")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary)
                .cornerRadius(6)
        }
    }
    
    @ViewBuilder
    private var urpWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Under-Replicated Partitions Detected")
                    .font(.caption.weight(.semibold))
                Text("\(metrics.underReplicatedPartitions) partition(s) are not fully replicated. This may indicate broker issues.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.red.opacity(0.1))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.red.opacity(0.3), lineWidth: 1)
        }
    }
    
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cluster Details")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    Text("Total Partitions")
                        .foregroundStyle(.secondary)
                    Text("\(metrics.partitionCount)")
                        .fontWeight(.medium)
                }
                
                GridRow {
                    Text("Log End Offset")
                        .foregroundStyle(.secondary)
                    Text(metrics.logEndOffset.formatted())
                        .fontWeight(.medium)
                }
                
                GridRow {
                    Text("ISR Shrink Rate")
                        .foregroundStyle(.secondary)
                    HStack {
                        Circle()
                            .fill(statusColor(for: isrStatus))
                            .frame(width: 8, height: 8)
                        Text(String(format: "%.3f/s", metrics.isrShrinkRate))
                    }
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
    
    private var urpStatus: HealthStatus {
        if metrics.underReplicatedPartitions > 0 { return .critical }
        return .healthy
    }
    
    private var lagStatus: HealthStatus {
        if metrics.consumerGroupLag > 50000 { return .critical }
        if metrics.consumerGroupLag > 10000 { return .warning }
        return .healthy
    }
    
    private var isrStatus: HealthStatus {
        if metrics.isrShrinkRate > 0.1 { return .critical }
        if metrics.isrShrinkRate > 0.01 { return .warning }
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

// MARK: - Preview

#Preview("Kafka Inspector - Healthy") {
    VStack {
        KafkaInspectorView(
            isExpanded: .constant(true),
            metrics: KafkaMetrics(
                partitionCount: 12,
                underReplicatedPartitions: 0,
                consumerGroupLag: 500,
                isrShrinkRate: 0.0,
                logEndOffset: 5_000_000
            ),
            lagHistory: (0..<30).map { i in
                MetricHistoryPoint(
                    timestamp: Date().addingTimeInterval(Double(-30 + i)),
                    value: Double.random(in: 300...700)
                )
            },
            urpHistory: []
        )
    }
    .padding()
    .frame(width: 450)
    .background(Color.gray.opacity(0.1))
}

#Preview("Kafka Inspector - Critical") {
    VStack {
        KafkaInspectorView(
            isExpanded: .constant(true),
            metrics: KafkaMetrics(
                partitionCount: 12,
                underReplicatedPartitions: 2,
                consumerGroupLag: 25000,
                isrShrinkRate: 0.08,
                logEndOffset: 5_000_000
            ),
            lagHistory: (0..<30).map { i in
                MetricHistoryPoint(
                    timestamp: Date().addingTimeInterval(Double(-30 + i)),
                    value: Double.random(in: 20000...30000)
                )
            },
            urpHistory: (0..<30).map { i in
                MetricHistoryPoint(
                    timestamp: Date().addingTimeInterval(Double(-30 + i)),
                    value: i > 20 ? 2 : 0
                )
            }
        )
    }
    .padding()
    .frame(width: 450)
    .background(Color.gray.opacity(0.1))
}
