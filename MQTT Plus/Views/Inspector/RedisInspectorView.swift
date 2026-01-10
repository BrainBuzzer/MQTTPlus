//
//  RedisInspectorView.swift
//  MQTT Plus
//
//  Collapsible inspector view for Redis metrics
//  Displays memory usage, ops/sec, and client connections
//

import SwiftUI

// MARK: - Redis Inspector View

/// Collapsible detail view for Redis metrics
struct RedisInspectorView: View {
    @Binding var isExpanded: Bool
    let metrics: RedisMetrics
    let opsHistory: [MetricHistoryPoint]
    let memoryHistory: [MetricHistoryPoint]
    
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
            Image(systemName: "memorychip.fill")
                .font(.title2)
                .foregroundStyle(.red)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Redis")
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
            // Server info header
            serverInfoHeader
            
            // Metric cards grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                MetricCardView(
                    title: "Memory Used",
                    value: metrics.usedMemoryHuman,
                    status: memoryStatus,
                    history: memoryHistory
                )
                
                MetricCardView(
                    title: "Ops/sec",
                    value: metrics.instantaneousOpsPerSec,
                    status: .healthy,
                    history: opsHistory
                )
                
                MetricCardView(
                    title: "Connected Clients",
                    value: "\(metrics.connectedClients)",
                    status: clientStatus,
                    history: [],
                    showSparkline: false
                )
                
                MetricCardView(
                    title: "Fragmentation Ratio",
                    value: metrics.memFragmentationRatio,
                    format: "%.2f",
                    status: fragmentationStatus,
                    history: [],
                    showSparkline: false
                )
            }
            
            // Network I/O row
            HStack(spacing: 12) {
                CompactMetricCardView(
                    title: "Net Input",
                    value: metrics.netInputFormatted,
                    status: .healthy
                )
            }
            
            Divider()
            
            // Additional details
            detailsSection
        }
        .padding(.top, 8)
    }
    
    private var serverInfoHeader: some View {
        HStack {
            Label("Redis Server", systemImage: "server.rack")
                .font(.subheadline.weight(.medium))
            
            Spacer()
            
            Text("In-Memory Store")
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
            Text("Server Details")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    Text("Used Memory")
                        .foregroundStyle(.secondary)
                    Text(metrics.usedMemoryHuman)
                        .fontWeight(.medium)
                }
                
                GridRow {
                    Text("Total Net Input")
                        .foregroundStyle(.secondary)
                    Text(metrics.netInputFormatted)
                        .fontWeight(.medium)
                }
                
                GridRow {
                    Text("Fragmentation")
                        .foregroundStyle(.secondary)
                    HStack {
                        Circle()
                            .fill(statusColor(for: fragmentationStatus))
                            .frame(width: 8, height: 8)
                        Text(String(format: "%.2fx", metrics.memFragmentationRatio))
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
    
    private var memoryStatus: HealthStatus {
        if metrics.usedMemoryBytes > 8_000_000_000 { return .critical }
        if metrics.usedMemoryBytes > 4_000_000_000 { return .warning }
        return .healthy
    }
    
    private var clientStatus: HealthStatus {
        if metrics.connectedClients > 10000 { return .critical }
        if metrics.connectedClients > 5000 { return .warning }
        return .healthy
    }
    
    private var fragmentationStatus: HealthStatus {
        if metrics.memFragmentationRatio > 2.0 { return .critical }
        if metrics.memFragmentationRatio > 1.5 { return .warning }
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

#Preview("Redis Inspector") {
    VStack {
        RedisInspectorView(
            isExpanded: .constant(true),
            metrics: RedisMetrics(
                usedMemoryHuman: "512.00M",
                usedMemoryBytes: 512_000_000,
                instantaneousOpsPerSec: 15234,
                connectedClients: 42,
                memFragmentationRatio: 1.18,
                totalNetInputBytes: 1_500_000_000
            ),
            opsHistory: (0..<30).map { i in
                MetricHistoryPoint(
                    timestamp: Date().addingTimeInterval(Double(-30 + i)),
                    value: Double.random(in: 14000...16500)
                )
            },
            memoryHistory: (0..<30).map { i in
                MetricHistoryPoint(
                    timestamp: Date().addingTimeInterval(Double(-30 + i)),
                    value: Double.random(in: 480...540)
                )
            }
        )
    }
    .padding()
    .frame(width: 450)
    .background(Color.gray.opacity(0.1))
}
