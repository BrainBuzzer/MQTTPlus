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
            
            // Log List
            ScrollViewReader { proxy in
                List {
                    ForEach(connectionManager.logs) { log in
                        HStack(alignment: .top, spacing: MQSpacing.md) {
                            Text(log.timestamp, style: .time)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                                .frame(width: 60, alignment: .leading)
                            
                            Text(log.level.rawValue.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(color(for: log.level))
                                .frame(width: 50, alignment: .leading)
                            
                            Text(log.message)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .id(log.id)
                        .padding(.vertical, MQSpacing.xxs)
                    }
                }
                .listStyle(.plain)
                .onChange(of: connectionManager.logs) {
                    if autoScroll, let lastLog = connectionManager.logs.last {
                        withAnimation {
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
}

#Preview {
    let manager = ConnectionManager()
    manager.log("Test Info Log", level: .info)
    manager.log("Test Warning Log", level: .warning)
    manager.log("Test Error Log", level: .error)
    return ConsoleView(connectionManager: manager)
}
