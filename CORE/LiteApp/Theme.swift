import SwiftUI

/// "Soft Focus" design system for CORE Focus: indigo-night gradients, warm
/// peach accent, lavender-white text. The creature's Core colour is reserved
/// for creature elements (progress bar, aura, motes) — never for chrome.
enum Theme {
    // Backgrounds
    static let bgTop    = Color(hex: 0x12141F)
    static let bgBottom = Color(hex: 0x1C2030)
    static var background: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
    }

    // Accent
    static let accent   = Color(hex: 0xFFB58A)
    static let onAccent = Color(hex: 0x12141F)

    // Text
    static let text      = Color(hex: 0xEDEBFF)
    static let textDim   = Color(hex: 0xEDEBFF).opacity(0.65)
    static let textFaint = Color(hex: 0xEDEBFF).opacity(0.4)

    // Surfaces
    static let surface       = Color.white.opacity(0.07)
    static let surfaceRaised = Color(hex: 0x1C2030).opacity(0.88)
    static let canvas        = Color(hex: 0x232838)

    // Semantic
    static let danger = Color(hex: 0xFF8A80)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Buttons

/// Full-width peach capsule — the one primary action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(isEnabled ? Theme.accent : Theme.surface, in: Capsule())
            .foregroundStyle(isEnabled ? Theme.onAccent : Theme.textFaint)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Quiet secondary capsule.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(Theme.surface, in: Capsule())
            .foregroundStyle(Theme.text)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
extension ButtonStyle where Self == GhostButtonStyle {
    static var ghost: GhostButtonStyle { GhostButtonStyle() }
}

// MARK: - Screens

struct ThemedScreen: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Theme.text)
            .background(Theme.background.ignoresSafeArea())
    }
}

extension View {
    func themedScreen() -> some View { modifier(ThemedScreen()) }
}
