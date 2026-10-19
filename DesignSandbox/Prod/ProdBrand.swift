// Production 2.0 brand tokens and type, mirrored from release/2.0 (Sources/App/LandlordHoursApp.swift,
// docs/design/2.0-brand-system.md) so onboarding screens match the shipped look exactly.
import SwiftUI
import UIKit
import CoreText

extension Color {
    /// Production's string initialiser (release/2.0 LandlordHoursApp.swift).
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(hex: UInt32(v & 0xFFFFFF))
    }
}

/// The 2.0 intent tokens (brand doc §2 table), light / dark.
enum PC {
    static let canvas = Color(light: 0xEEF2FA, dark: 0x0B1230)
    static let card = Color(light: 0xFFFFFF, dark: 0x141C3F)
    static let tertiary = Color(light: 0xF6F8FD, dark: 0x1B2550)
    static let brand = Color(hex: 0x1E3FA6)
    static let action = Color(light: 0x1E3FA6, dark: 0x8FD3FF)
    static let onAction = Color(light: 0xFFFFFF, dark: 0x0B1230)
    static let actionSurface = Color(light: 0xE3E9FA, dark: 0x182A5C)
    static let draftingInk = Color(light: 0x2369B5, dark: 0x60A8E6)
    static let timberInk = Color(light: 0x8A5A1B, dark: 0xF0BE7A)
    static let textPrimary = Color(light: 0x121B33, dark: 0xF2F4FA)
    static let textSecondary = Color(light: 0x4A5068, dark: 0xB4BCD2)
    static let textTertiary = Color(light: 0x5F6983, dark: 0x8A94B2)
    static let border = Color(light: 0xD5DBEA, dark: 0x2A3560)
    static let positive = Color(light: 0x137A42, dark: 0x4ED48A)
    static let positiveSurface = Color(light: 0xE4F7EB, dark: 0x123A2A)
    static let caution = Color(light: 0x9A560C, dark: 0xFFB454)
    static let rose = Color(light: 0xB04266, dark: 0xF08BAA)
    static let roseSurface = Color(light: 0xF9E3EA, dark: 0x3A1A28)
    static let informational = Color(light: 0x4A6392, dark: 0x9BB0D0)
}

// MARK: - Fraunces (bundled; registered at launch because the sandbox has a generated Info.plist)

enum ProdFont {
    static let family = "Fraunces"
    static func register() {
        guard UIFont.fontNames(forFamilyName: family).isEmpty,
              let url = Bundle.main.url(forResource: "Fraunces", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
    static var available: Bool { !UIFont.fontNames(forFamilyName: family).isEmpty }

    static func tag(_ t: String) -> UInt32 { t.unicodeScalars.reduce(0) { ($0 << 8) | UInt32($1.value & 0xFF) } }

    /// Display 34/500, opsz 144, SOFT 50 (Welcome, milestones), scaled like .largeTitle, never under 28.
    static func display(_ size: DynamicTypeSize) -> UIFont {
        let base: CGFloat = 34
        let traits = UITraitCollection(preferredContentSizeCategory: size.prodCategory)
        let metrics = UIFontMetrics(forTextStyle: .largeTitle)
        let d = UIFontDescriptor(fontAttributes: [.family: family]).addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String):
                [NSNumber(value: tag("wght")): 500, NSNumber(value: tag("opsz")): 144, NSNumber(value: tag("SOFT")): 50] as [NSNumber: CGFloat]
        ])
        let f = UIFont(descriptor: d, size: base)
        let font = f.familyName == family ? f : UIFont(descriptor: UIFont.systemFont(ofSize: base, weight: .medium).fontDescriptor.withDesign(.serif)!, size: base)
        let scaled = metrics.scaledFont(for: font, compatibleWith: traits)
        return scaled.pointSize < 28 ? scaled.withSize(28) : scaled
    }
}

private struct DisplayFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var size
    func body(content: Content) -> some View { content.font(Font(ProdFont.display(size))) }
}

extension View {
    /// Fraunces display (≥28pt). Welcome and Staked only.
    func prodDisplay() -> some View { modifier(DisplayFont()) }

    /// SF Mono drafting label: 11pt medium caps, +12% tracking.
    func drafting(_ color: Color) -> some View {
        self.font(.system(.caption2, design: .monospaced, weight: .medium))
            .textCase(.uppercase)
            .tracking(1.3)
            .foregroundStyle(color)
    }
}

extension DynamicTypeSize {
    var prodCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}

// MARK: - The one component set (audit: same pill, card and link on every step)

/// Blueprint pill on white (dark: cyan on navy). Full width, 52pt.
struct ProdPrimaryPill: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .foregroundStyle(enabled ? PC.onAction : PC.textTertiary)
            .background(enabled ? PC.action : PC.tertiary, in: Capsule())
            .overlay { if !enabled { Capsule().strokeBorder(PC.border, lineWidth: 1) } }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Outlined pill of equal weight (the real "Not now").
struct ProdOutlinePill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(PC.action)
            .overlay(Capsule().strokeBorder(PC.action.opacity(0.55), lineWidth: 1.5))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// White pill on blueprint (both modes).
struct ProdHeroPill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(PC.brand)
            .background(.white, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The one text link.
struct ProdLink: ButtonStyle {
    var color: Color = PC.action
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(color)
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
