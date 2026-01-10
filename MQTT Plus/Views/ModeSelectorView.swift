import SwiftUI

// MARK: - Mode Selector

struct ModeSelectorView: View {
    @Binding var selectedMode: ConnectionMode
    let onConnect: (ConnectionMode) -> Void
    
    var body: some View {
        VStack(spacing: MQSpacing.xl) {
            Text("Select Connection Mode")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: MQSpacing.lg) {
                ForEach(ConnectionMode.allCases, id: \.self) { mode in
                    ModeOptionView(
                        mode: mode,
                        isSelected: selectedMode == mode,
                        action: {
                            selectedMode = mode
                            onConnect(mode)
                        }
                    )
                }
            }
        }
        .padding(MQSpacing.xl)
        .frame(width: 350)
    }
}

struct ModeOptionView: View {
    let mode: ConnectionMode
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: MQSpacing.lg) {
                Image(systemName: mode == .core ? "antenna.radiowaves.left.and.right" : "cylinder.split.1x2")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: MQSpacing.xxs) {
                    Text(mode.description)
                        .font(.system(.headline, weight: isSelected ? .semibold : .medium))
                    
                    Text(mode == .core ? "Traditional pub/sub messaging" : "Persistent streams with replay")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
            }
            .padding(MQSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MQRadius.lg, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MQRadius.lg, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
