import SwiftUI
import AppKit

/// Physical Taptic Engine haptic feedback for macOS Force Touch trackpads
public enum FluidHaptics {
    /// Crisp, subtle tactile click (buttons, format selection, timer pick, navigation)
    public static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }
    
    /// Firm confirmation feedback (play/pause toggle, track skip, like heart)
    public static func toggle() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    }
    
    /// Elastic snap feedback (scrubber seek, lyrics line jump, volume snap)
    public static func snap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }
}

/// Apple Design System guidelines conforming to WWDC Fluid Interfaces & macOS Human Interface Guidelines.
public enum FluidTheme {
    // MARK: - Colors & Vibrancy
    public static let accent = Color.accentColor
    public static let musicRed = Color(red: 0.95, green: 0.22, blue: 0.28)
    public static let secondaryText = Color.secondary
    
    // Backgrounds & Chrome
    public static let glassMaterial = Material.ultraThinMaterial
    public static let barMaterial = Material.bar
    public static let cardBackground = Color(nsColor: .windowBackgroundColor).opacity(0.6)
    
    // MARK: - Springs (Apple WWDC 2018 Fluid Interfaces)
    /// Critically damped spring for general UI transitions (damping 1.0, response 0.35s)
    public static let fluidSpring = Animation.spring(response: 0.35, dampingFraction: 0.9)
    
    /// Bouncy momentum spring for active gestures and cards (damping 0.8, response 0.35s)
    public static let momentumSpring = Animation.spring(response: 0.35, dampingFraction: 0.8)
    
    /// Snappy micro-interaction spring (response 0.2s)
    public static let tapSpring = Animation.spring(response: 0.2, dampingFraction: 0.85)
    
    // MARK: - Typography (Optical Sizing & Hierarchy)
    public static let titleFont = Font.system(.title2, design: .rounded).weight(.bold)
    public static let headlineFont = Font.system(.headline, design: .rounded).weight(.semibold)
    public static let bodyFont = Font.system(.body, design: .default)
    public static let captionFont = Font.system(.caption, design: .rounded).weight(.medium)
}

// MARK: - Tactile Press Button Style (Direct manipulation & 1:1 response with physical Taptic feedback)

public struct ApplePlayerButtonStyle: ButtonStyle {
    public let width: CGFloat
    public let height: CGFloat
    public let cornerRadius: CGFloat
    
    public init(width: CGFloat = 32, height: CGFloat = 32, cornerRadius: CGFloat = 7) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(FluidTheme.tapSpring, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    FluidHaptics.tap()
                }
            }
    }
}

public struct TactileButtonStyle: ButtonStyle {
    public let scaleAmount: CGFloat
    
    public init(scaleAmount: CGFloat = 0.96) {
        self.scaleAmount = scaleAmount
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleAmount : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(FluidTheme.tapSpring, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    FluidHaptics.tap()
                }
            }
    }
}

public struct ApplePopoverRowStyle: ButtonStyle {
    public let isSelected: Bool
    
    public init(isSelected: Bool = false) {
        self.isSelected = isSelected
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.12) : (isSelected ? FluidTheme.musicRed.opacity(0.12) : Color.clear))
            )
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(FluidTheme.tapSpring, value: configuration.isPressed)
    }
}

public struct GlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = 12
    
    public func body(content: Content) -> some View {
        content
            .background(FluidTheme.glassMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
}

public extension View {
    func glassCard(cornerRadius: CGFloat = 12) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}
