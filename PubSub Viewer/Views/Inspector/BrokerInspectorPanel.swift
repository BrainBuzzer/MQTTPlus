//
//  BrokerInspectorPanel.swift
//  PubSub Viewer
//
//  Integration panel that connects broker inspector views with ConnectionManager
//  Uses real metrics from actual broker connections
//

import SwiftUI

// MARK: - Broker Inspector Panel

/// Panel that shows broker-specific metrics based on the current connection
struct BrokerInspectorPanel: View {
    @ObservedObject var connectionManager: ConnectionManager
    @StateObject private var metricsProvider: RealBrokerMetricsProvider
    @State private var isExpanded = true
    
    init(connectionManager: ConnectionManager) {
        self.connectionManager = connectionManager
        self._metricsProvider = StateObject(wrappedValue: RealBrokerMetricsProvider(connectionManager: connectionManager))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with separator
            HStack {
                Label("Broker Inspector", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    .font(.headline)
                
                Spacer()
                
                // Connection status
                connectionStatusBadge
                
                // Broker type badge
                brokerTypeBadge
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Inspector content
            ScrollView {
                VStack(spacing: 12) {
                    inspectorContent
                }
                .padding()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Connection Status Badge
    
    @ViewBuilder
    private var connectionStatusBadge: some View {
        let (color, text): (Color, String) = {
            switch connectionManager.connectionState {
            case .connected:
                return (.green, "Live")
            case .connecting:
                return (.orange, "Connecting")
            case .error:
                return (.red, "Error")
            case .disconnected:
                return (.gray, "Offline")
            }
        }()

        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial)
        .cornerRadius(4)
    }
    
    // MARK: - Broker Type Badge
    
    @ViewBuilder
    private var brokerTypeBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: metricsProvider.brokerType.iconName)
            Text(metricsProvider.brokerType.displayName)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(brokerColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(brokerColor.opacity(0.15))
        .cornerRadius(6)
    }
    
    private var brokerColor: Color {
        switch metricsProvider.brokerType {
        case .nats: return .blue
        case .redis: return .red
        case .kafka: return .purple
        }
    }
    
    // MARK: - Inspector Content
    
    @ViewBuilder
    private var inspectorContent: some View {
        switch connectionManager.connectionState {
        case .connected:
            switch metricsProvider.brokerType {
            case .nats:
                NatsInspectorView(
                    isExpanded: $isExpanded,
                    metrics: metricsProvider.natsMetrics,
                    lagHistory: metricsProvider.natsLagHistory.points,
                    msgHistory: metricsProvider.natsMsgHistory.points
                )
                
            case .redis:
                RedisInspectorView(
                    isExpanded: $isExpanded,
                    metrics: metricsProvider.redisMetrics,
                    opsHistory: metricsProvider.redisOpsHistory.points,
                    memoryHistory: metricsProvider.redisMemoryHistory.points
                )
                
            case .kafka:
                KafkaInspectorView(
                    isExpanded: $isExpanded,
                    metrics: metricsProvider.kafkaMetrics,
                    lagHistory: metricsProvider.kafkaLagHistory.points,
                    urpHistory: metricsProvider.kafkaUrpHistory.points
                )
            }
        case .connecting:
            connectingView
        case .error(let message):
            errorView(message: message)
        case .disconnected:
            disconnectedView
        }
    }

    private var connectingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Connecting…")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Waiting for broker to respond")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding()
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text("Connection Error")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding()
    }
    
    private var disconnectedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Not Connected")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Connect to a server to view broker metrics")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding()
    }
}

// MARK: - Preview

#Preview("Broker Inspector Panel") {
    BrokerInspectorPanel(connectionManager: ConnectionManager())
        .frame(width: 450, height: 350)
}
