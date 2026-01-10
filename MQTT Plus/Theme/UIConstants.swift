//
//  UIConstants.swift
//  MQTT Plus
//
//  Shared design system constants for consistent UI styling
//

import SwiftUI

// MARK: - Spacing

enum MQSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
    static let xxxl: CGFloat = 24
}

// MARK: - Corner Radius

enum MQRadius {
    static let xs: CGFloat = 3
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 8
    static let xl: CGFloat = 12
}

// MARK: - Badge Styling

struct MQBadge: ViewModifier {
    let color: Color
    let isSmall: Bool
    
    init(color: Color, small: Bool = false) {
        self.color = color
        self.isSmall = small
    }
    
    func body(content: Content) -> some View {
        content
            .font(isSmall ? .caption2.weight(.medium) : .caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, isSmall ? 5 : 6)
            .padding(.vertical, isSmall ? 2 : 3)
            .background(color.opacity(0.12))
            .cornerRadius(MQRadius.sm)
    }
}

extension View {
    func mqBadge(color: Color, small: Bool = false) -> some View {
        modifier(MQBadge(color: color, small: small))
    }
}

// MARK: - Panel Header

struct MQPanelHeader<TrailingContent: View>: View {
    let title: String
    let trailing: TrailingContent
    
    init(_ title: String, @ViewBuilder trailing: () -> TrailingContent = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            trailing
        }
        .padding(.horizontal, MQSpacing.xl)
        .padding(.vertical, MQSpacing.lg)
        .frame(height: 44)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Row Hover Effect

struct MQRowHover: ViewModifier {
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    func mqRowHover() -> some View {
        modifier(MQRowHover())
    }
}

// MARK: - Card Styling

struct MQCard: ViewModifier {
    let isSelected: Bool
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: MQRadius.lg, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MQRadius.lg, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
    }
}

extension View {
    func mqCard(selected: Bool = false) -> some View {
        modifier(MQCard(isSelected: selected))
    }
}

// MARK: - Status Dot with Animation

struct MQStatusDot: View {
    let state: ConnectionState
    
    @State private var isAnimating = false
    
    var color: Color {
        switch state {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .gray
        }
    }
    
    var body: some View {
        ZStack {
            if state == .connecting {
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .scaleEffect(isAnimating ? 1.5 : 1.0)
                    .opacity(isAnimating ? 0 : 0.5)
                    .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: isAnimating)
            }
            
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            if state == .connecting {
                isAnimating = true
            }
        }
        .onChange(of: state) { _, newState in
            isAnimating = newState == .connecting
        }
    }
}

// MARK: - Icon Button

struct MQIconButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    let size: CGFloat
    
    init(_ icon: String, color: Color = .primary, size: CGFloat = 28, action: @escaping () -> Void) {
        self.icon = icon
        self.color = color
        self.size = size
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(color, in: RoundedRectangle(cornerRadius: MQRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Header

struct MQSectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

// MARK: - Filled Text Field Style

struct MQFilledTextFieldStyle: TextFieldStyle {
    var isSuccess: Bool = false
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, MQSpacing.lg)
            .padding(.vertical, MQSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: MQRadius.md, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MQRadius.md, style: .continuous)
                    .strokeBorder(isSuccess ? Color.green.opacity(0.7) : Color.clear, lineWidth: 2)
            )
    }
}

extension View {
    func mqFilledField(success: Bool = false) -> some View {
        self.modifier(MQFilledFieldModifier(isSuccess: success))
    }
}

struct MQFilledFieldModifier: ViewModifier {
    var isSuccess: Bool = false
    
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, MQSpacing.lg)
            .padding(.vertical, MQSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: MQRadius.md, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MQRadius.md, style: .continuous)
                    .strokeBorder(isSuccess ? Color.green.opacity(0.7) : Color.secondary.opacity(0.15), lineWidth: isSuccess ? 2 : 1)
            )
    }
}
