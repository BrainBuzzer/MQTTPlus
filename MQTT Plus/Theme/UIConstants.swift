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

// MARK: - Animation Presets

enum MQAnimation {
    static let quick = Animation.easeOut(duration: 0.15)
    static let standard = Animation.easeInOut(duration: 0.25)
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)
    static let gentle = Animation.easeInOut(duration: 0.4)
}

// MARK: - Provider Colors

enum MQProviderColor {
    static let nats = Color.blue
    static let redis = Color.red
    static let kafka = Color.purple
    static let mqtt = Color.green
    
    static func color(for providerId: String?) -> Color {
        switch providerId {
        case "nats": return nats
        case "redis": return redis
        case "kafka": return kafka
        case "mqtt": return mqtt
        default: return .secondary
        }
    }
}

// MARK: - Toolbar Group

struct MQToolbarGroup<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        HStack(spacing: MQSpacing.sm) {
            content
        }
        .padding(.horizontal, MQSpacing.md)
        .padding(.vertical, MQSpacing.sm)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: MQRadius.md, style: .continuous))
    }
}

// MARK: - Toolbar Button

struct MQToolbarButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    var isDestructive: Bool = false
    var isDisabled: Bool = false
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.callout)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isDestructive ? .red : (isDisabled ? Color.secondary : Color.primary))
        .padding(.horizontal, MQSpacing.sm)
        .padding(.vertical, MQSpacing.xs)
        .background(isHovered && !isDisabled ? Color.primary.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: MQRadius.sm, style: .continuous))
        .onHover { isHovered = $0 }
        .disabled(isDisabled)
    }
}

// MARK: - Search Field

struct MQSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var width: CGFloat = 200
    
    var body: some View {
        HStack(spacing: MQSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.callout)
                .foregroundStyle(.tertiary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, MQSpacing.md)
        .padding(.vertical, MQSpacing.sm)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: MQRadius.md, style: .continuous))
        .frame(width: width)
    }
}

// MARK: - Empty State

struct MQEmptyState: View {
    let icon: String
    let title: String
    let description: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil
    var animate: Bool = true
    
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: MQSpacing.xxl) {
            ZStack {
                if animate {
                    ForEach(0..<2, id: \.self) { i in
                        Circle()
                            .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
                            .frame(width: CGFloat(80 + i * 40), height: CGFloat(80 + i * 40))
                            .scaleEffect(isAnimating ? 1.15 : 1.0)
                            .opacity(isAnimating ? 0 : 0.6)
                            .animation(
                                .easeOut(duration: 2.5)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.6),
                                value: isAnimating
                            )
                    }
                }
                
                Image(systemName: icon)
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .frame(height: 140)
            
            VStack(spacing: MQSpacing.md) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            
            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if animate {
                isAnimating = true
            }
        }
    }
}

// MARK: - Keyboard Shortcut Hint

struct MQShortcutHint: View {
    let keys: [String]
    let label: String
    
    var body: some View {
        HStack(spacing: MQSpacing.xs) {
            HStack(spacing: 2) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.caption2.weight(.medium).monospaced())
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - JSON Syntax Highlighter

struct JSONSyntaxHighlighter {
    static func highlight(_ json: String) -> AttributedString {
        var result = AttributedString(json)
        
        let keyColor = Color.blue
        let stringColor = Color.orange
        let numberColor = Color.purple
        let boolNullColor = Color.cyan
        let bracketColor = Color.secondary
        
        result.font = .system(.body, design: .monospaced)
        
        let nsString = json as NSString
        
        let patterns: [(String, Color)] = [
            ("\"[^\"\\\\]*(?:\\\\.[^\"\\\\]*)*\"\\s*:", keyColor),
            (":\\s*\"[^\"\\\\]*(?:\\\\.[^\"\\\\]*)*\"", stringColor),
            (":\\s*-?\\d+\\.?\\d*([eE][+-]?\\d+)?", numberColor),
            (":\\s*(true|false|null)", boolNullColor),
            ("[\\[\\]{}]", bracketColor),
        ]
        
        for (pattern, color) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let matches = regex.matches(in: json, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                guard let range = Range(match.range, in: json) else { continue }
                let attrRange = result.range(of: String(json[range]))
                if let attrRange = attrRange {
                    result[attrRange].foregroundColor = color
                }
            }
        }
        
        return result
    }
    
    static func highlightSimple(_ json: String) -> AttributedString {
        var result = AttributedString()
        result.font = .system(.body, design: .monospaced)
        
        var inString = false
        var isKey = false
        var currentToken = ""
        var escaped = false
        
        let keyColor = Color.blue
        let stringColor = Color(red: 0.8, green: 0.4, blue: 0.1)
        let numberColor = Color.purple
        let boolNullColor = Color.teal
        let bracketColor = Color.secondary
        
        func flushToken() {
            guard !currentToken.isEmpty else { return }
            var attr = AttributedString(currentToken)
            attr.font = .system(.body, design: .monospaced)
            
            if inString {
                attr.foregroundColor = isKey ? keyColor : stringColor
            } else {
                let trimmed = currentToken.trimmingCharacters(in: .whitespaces)
                if trimmed == "true" || trimmed == "false" || trimmed == "null" {
                    attr.foregroundColor = boolNullColor
                } else if Double(trimmed) != nil {
                    attr.foregroundColor = numberColor
                }
            }
            
            result.append(attr)
            currentToken = ""
        }
        
        for char in json {
            if escaped {
                currentToken.append(char)
                escaped = false
                continue
            }
            
            if char == "\\" && inString {
                currentToken.append(char)
                escaped = true
                continue
            }
            
            if char == "\"" {
                if inString {
                    currentToken.append(char)
                    flushToken()
                    inString = false
                    isKey = false
                } else {
                    flushToken()
                    currentToken.append(char)
                    inString = true
                }
                continue
            }
            
            if !inString {
                if char == ":" {
                    isKey = true
                    flushToken()
                    var colon = AttributedString(":")
                    colon.font = .system(.body, design: .monospaced)
                    result.append(colon)
                    isKey = false
                    continue
                }
                
                if "{}[]".contains(char) {
                    flushToken()
                    var bracket = AttributedString(String(char))
                    bracket.font = .system(.body, design: .monospaced)
                    bracket.foregroundColor = bracketColor
                    result.append(bracket)
                    continue
                }
                
                if char == "," {
                    flushToken()
                    var comma = AttributedString(",")
                    comma.font = .system(.body, design: .monospaced)
                    result.append(comma)
                    continue
                }
            }
            
            currentToken.append(char)
        }
        
        flushToken()
        return result
    }
}

// MARK: - Quick Action Button (for Welcome View)

struct MQQuickActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: MQSpacing.md) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 48, height: 48)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: MQRadius.lg, style: .continuous))
                
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .padding(MQSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MQRadius.xl, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
