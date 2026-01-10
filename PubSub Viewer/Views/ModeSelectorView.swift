import SwiftUI

// MARK: - Mode Selector

struct ModeSelectorView: View {
    @Binding var selectedMode: NatsMode
    let onConnect: (NatsMode) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Select Connection Mode")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                ForEach(NatsMode.allCases, id: \.self) { mode in
                    Button(action: {
                        selectedMode = mode
                        onConnect(mode)
                    }) {
                        HStack {
                            Image(systemName: mode == .core ? "antenna.radiowaves.left.and.right" : "cylinder.split.1x2")
                                .frame(width: 20)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.description)
                                    .font(.headline)
                                
                                Text(mode == .core ? "Traditional pub/sub messaging" : "Persistent streams with replay")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedMode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(12)
                        .background(selectedMode == mode ? Color.blue.opacity(0.1) : Color.clear)
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .frame(width: 350)
    }
}
