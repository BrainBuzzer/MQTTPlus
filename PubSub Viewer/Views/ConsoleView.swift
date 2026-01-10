//
//  ConsoleView.swift
//  PubSub Viewer
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
            HStack {
                Text("CONSOLE")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .font(.caption)
                    .controlSize(.mini)
                
                Button(action: { connectionManager.logs.removeAll() }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Clear Console")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Log List
            ScrollViewReader { proxy in
                List {
                    ForEach(connectionManager.logs) { log in
                        HStack(alignment: .top, spacing: 8) {
                            Text(log.timestamp, style: .time)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .leading)
                            
                            Text(log.level.rawValue.uppercased())
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(color(for: log.level))
                                .frame(width: 50, alignment: .leading)
                            
                            Text(log.message)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .id(log.id)
                        .padding(.vertical, 2)
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
    let manager = ConnectionManager.shared
    manager.log("Test Info Log", level: .info)
    manager.log("Test Warning Log", level: .warning)
    manager.log("Test Error Log", level: .error)
    return ConsoleView(connectionManager: manager)
}
