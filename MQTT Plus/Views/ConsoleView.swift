//
//  ConsoleView.swift
//  MQTT Plus
//
//  Created by Aditya on 10/01/26.
//

import SwiftUI

struct ConsoleView: View {
    @ObservedObject var connectionManager: ConnectionManager
    @State private var autoScroll = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            MQPanelHeader("Console") {
                HStack(spacing: MQSpacing.lg) {
                    Toggle("Auto-scroll", isOn: $autoScroll)
                        .font(.caption)
                        .controlSize(.mini)
                    
                    Button(action: { connectionManager.logs.removeAll() }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help("Clear Console")
                }
            }
            
            Divider()
            
            ScrollViewReader { proxy in
                List {
                    ForEach(connectionManager.logs) { log in
                        HStack(alignment: .top, spacing: MQSpacing.md) {
                            Text(log.timestamp, style: .time)
                                .font(.system(.caption2, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                                .frame(width: 70, alignment: .leading)
                            
                            Text(log.level.rawValue.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(color(for: log.level))
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                                .frame(width: 55, alignment: .leading)
                            
                            Text(log.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(log.level == .error ? .red : .primary)
                                .textSelection(.enabled)
                        }
                        .id(log.id)
                        .padding(.vertical, MQSpacing.xs)
                        .padding(.horizontal, MQSpacing.sm)
                        .background(backgroundColor(for: log.level))
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .onChange(of: connectionManager.logs) {
                    if autoScroll, let lastLog = connectionManager.logs.last {
                        withAnimation(MQAnimation.quick) {
                            proxy.scrollTo(lastLog.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    private func color(for level: ConnectionManager.LogEntry.LogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
    
    private func backgroundColor(for level: ConnectionManager.LogEntry.LogLevel) -> Color {
        switch level {
        case .error: return .red.opacity(0.08)
        case .warning: return .orange.opacity(0.05)
        case .info: return .clear
        }
    }
}

#Preview {
    let manager = ConnectionManager()
    manager.log("Test Info Log", level: .info)
    manager.log("Test Warning Log", level: .warning)
    manager.log("Test Error Log", level: .error)
    return ConsoleView(connectionManager: manager)
}
