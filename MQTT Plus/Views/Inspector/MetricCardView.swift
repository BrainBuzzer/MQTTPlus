import SwiftUI
import Charts

// MARK: - Metric Card View

/// A card displaying a metric value with label, status indicator, and sparkline
struct MetricCardView: View {
    let title: String
    let value: String
    let unit: String?
    let status: HealthStatus
    let history: [MetricHistoryPoint]
    let showSparkline: Bool
    
    init(
        title: String,
        value: String,
        unit: String? = nil,
        status: HealthStatus = .healthy,
        history: [MetricHistoryPoint] = [],
        showSparkline: Bool = true
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.status = status
        self.history = history
        self.showSparkline = showSparkline
    }
    
    // Convenience initializers for common numeric types
    init(title: String, value: UInt64, unit: String? = nil, status: HealthStatus = .healthy, history: [MetricHistoryPoint] = []) {
        self.init(title: title, value: value.formatted(), unit: unit, status: status, history: history)
    }
    
    init(title: String, value: Int, unit: String? = nil, status: HealthStatus = .healthy, history: [MetricHistoryPoint] = []) {
        self.init(title: title, value: value.formatted(), unit: unit, status: status, history: history)
    }
    
    init(title: String, value: Int64, unit: String? = nil, status: HealthStatus = .healthy, history: [MetricHistoryPoint] = []) {
        self.init(title: title, value: value.formatted(), unit: unit, status: status, history: history)
    }
    
    init(title: String, value: Double, format: String = "%.2f", unit: String? = nil, status: HealthStatus = .healthy, history: [MetricHistoryPoint] = [], showSparkline: Bool = true) {
        self.init(title: title, value: String(format: format, value), unit: unit, status: status, history: history, showSparkline: showSparkline)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: MQSpacing.md) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                Spacer()
                
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.5), radius: 3, x: 0, y: 0)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: MQSpacing.xs) {
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(MQAnimation.spring, value: value)
                
                if let unit = unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            // Sparkline chart (always reserve space)
            if showSparkline {
                if !history.isEmpty {
                    sparklineChart
                        .frame(height: 30)
                } else {
                    Color.clear
                        .frame(height: 30)
                }
            } else {
                 // Even if sparkline is hidden, reserve space to align with other cards? 
                 // If the user wants ALL cards to be same height, yes. 
                 // But let's assume showSparkline=false means it's a Compact card or we just want to hide it.
                 // Actually, the user said "regardless of graphs embedded in them".
                 // This implies cards WITH graphs and cards WITHOUT graphs should match.
                 // So we should probably ALWAYS reserve this space or set a fixed total height.
                 Color.clear
                    .frame(height: 30)
            }
        }
        .padding(MQSpacing.lg)
        .background {
            RoundedRectangle(cornerRadius: MQRadius.xl, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: MQRadius.xl, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [statusColor.opacity(0.4), statusColor.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
    
    @ViewBuilder
    private var sparklineChart: some View {
        Chart(history) { point in
            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Value", point.value)
            )
            .foregroundStyle(sparklineGradient)
            .interpolationMethod(.catmullRom)
            
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Value", point.value)
            )
            .foregroundStyle(areaGradient)
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: yAxisDomain)
    }
    
    private var sparklineGradient: LinearGradient {
        LinearGradient(
            colors: [statusColor, statusColor.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [statusColor.opacity(0.3), statusColor.opacity(0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var yAxisDomain: ClosedRange<Double> {
        guard !history.isEmpty else { return 0...1 }
        let values = history.map(\.value)
        let minVal = values.min() ?? 0
        let maxVal = values.max() ?? 1
        let padding = (maxVal - minVal) * 0.1
        return (minVal - padding)...(maxVal + padding)
    }
}

// MARK: - Compact Metric Card

/// Smaller metric card without sparkline for dense layouts
struct CompactMetricCardView: View {
    let title: String
    let value: String
    let status: HealthStatus
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.callout, design: .rounded, weight: .medium))
                    .contentTransition(.numericText())
            }
            
            Spacer()
            
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Preview

#Preview("Metric Card") {
    VStack(spacing: 16) {
        MetricCardView(
            title: "Consumer Lag",
            value: "1,234",
            unit: "msgs",
            status: .warning,
            history: (0..<30).map { i in
                MetricHistoryPoint(
                    timestamp: Date().addingTimeInterval(Double(-30 + i)),
                    value: Double.random(in: 100...1500)
                )
            }
        )
        .frame(width: 180)
        
        MetricCardView(
            title: "Memory Usage",
            value: "512.5",
            unit: "MB",
            status: .healthy,
            history: (0..<30).map { i in
                MetricHistoryPoint(
                    timestamp: Date().addingTimeInterval(Double(-30 + i)),
                    value: Double.random(in: 480...530)
                )
            }
        )
        .frame(width: 180)
        
        MetricCardView(
            title: "Under-Replicated",
            value: "3",
            unit: "partitions",
            status: .critical,
            history: []
        )
        .frame(width: 180)
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}

#Preview("Compact Card") {
    HStack(spacing: 8) {
        CompactMetricCardView(title: "Clients", value: "42", status: .healthy)
        CompactMetricCardView(title: "Ops/sec", value: "15.2K", status: .healthy)
        CompactMetricCardView(title: "Lag", value: "5.1K", status: .warning)
    }
    .padding()
}
