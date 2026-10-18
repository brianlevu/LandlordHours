// LHDesignSandbox — throwaway design sandbox for LandlordHours 2.0. Mock data only, never shipped.
import SwiftUI
import UIKit

// MARK: - Color tokens (intent-based; see SPEC.md §13)

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// Dynamic light/dark color.
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(uiColor: UIColor { trait in
            let dark0 = trait.userInterfaceStyle == .dark
            let hex = dark0 ? dark : light
            let a = dark0 ? darkAlpha : lightAlpha
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: a)
        })
    }
}

enum LH {
    // One action color. #5B4CDB on white = 6.0:1, on #F2F2F7 = 5.37:1. #A99BFF on #1C1C1E = 7.15:1.
    static let action = Color(light: 0x5B4CDB, dark: 0xA99BFF)
    // Text on an action fill. White on #5B4CDB = 6.0:1; #14102E on #A99BFF = 7.7:1.
    static let onAction = Color(light: 0xFFFFFF, dark: 0x14102E)
    static let actionWash = Color(light: 0x5B4CDB, dark: 0xA99BFF, lightAlpha: 0.10, darkAlpha: 0.16)

    // Status colors live on words and glyphs. Light values deepened for AA on white.
    static let positive = Color(light: 0x1A7F43, dark: 0x30D158)   // 5.05:1 on white
    static let positiveWash = Color(light: 0x34C759, dark: 0x30D158, lightAlpha: 0.10, darkAlpha: 0.14)
    static let caution = Color(light: 0xB25000, dark: 0xFF9F0A)    // 5.2:1 on white
    static let cautionWash = Color(light: 0xFF9500, dark: 0xFF9F0A, lightAlpha: 0.12, darkAlpha: 0.16)
    static let destructive = Color(light: 0xD70015, dark: 0xFF6961)

    // Source hues (record tiles only). Location uses cyan, not green: green is reserved for success.
    static let srcCalendar = Color(light: 0x0A6CDB, dark: 0x5AA9FF)
    static let srcLocation = Color(light: 0x0A7C8C, dark: 0x5AD1E0)
    static let srcReceipt = Color(light: 0x6C6C70, dark: 0xAEAEB2)

    /// Secondary text. System secondaryLabel composites to ~3.4:1 on white, so it is replaced:
    /// #636366 = 5.9:1 on white, 5.3:1 on #F2F2F7; #9A9AA0 = 6.1:1 on #1C1C1E, 7.5:1 on black.
    static let secondaryText = Color(light: 0x636366, dark: 0x9A9AA0)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let fill = Color(uiColor: .systemFill)
    static let tertiaryFill = Color(uiColor: .tertiarySystemFill)
    static let separator = Color(uiColor: .separator)
}

// MARK: - Motion

enum Motion {
    /// Card expand/collapse, row collapse (SPEC §13).
    static func collapse(_ reduce: Bool) -> Animation {
        reduce ? .easeInOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.86)
    }
    /// Selection / state flips. Critically damped.
    static func snappy(_ reduce: Bool) -> Animation {
        reduce ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 1.0)
    }
}

// MARK: - Type helpers

extension View {
    func eyebrow() -> some View {
        self.font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.3)
            .foregroundStyle(LH.secondaryText)
    }

    /// One section-label style everywhere (SPEC §13: 13pt semibold caps, secondary).
    func sectionLabel() -> some View { eyebrow() }

    /// Bevel card: radius 20, padding inside handled by caller, barely-there shadow in light.
    func lhCard(radius: CGFloat = 20) -> some View {
        modifier(CardModifier(radius: radius))
    }
}

struct CardModifier: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .background(LH.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.04), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Buttons

/// Press feedback: scale 0.97, 120ms ease-out.
struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 52pt full-width capsule in the action color.
struct PrimaryCapsule: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(enabled ? LH.onAction : LH.secondaryText)
            .background(enabled ? LH.action : LH.fill, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 44pt tinted capsule (action wash + action text).
struct TintedCapsule: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(LH.action)
            .background(LH.actionWash, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 44pt round glass close button (Flighty).
struct GlassCircleButton: View {
    var systemName: String = "xmark"
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel(systemName == "xmark" ? "Close" : systemName)
    }
}

// MARK: - Shared bits

struct SourceTile: View {
    let kind: SourceKind
    var size: CGFloat = 40
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(kind.tint.opacity(scheme == .dark ? 0.18 : 0.10))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: kind.symbol)
                    .font(.system(size: size * 0.5, weight: .regular))
                    .foregroundStyle(kind.tint)
                    .symbolRenderingMode(.hierarchical)
            }
    }
}

struct StatusDot: View {
    var color: Color
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.25))
            Circle().trim(from: 0, to: 0.5).fill(color).rotationEffect(.degrees(90))
        }
        .frame(width: 10, height: 10)
    }
}

func fmt(_ h: Double) -> String {
    h == h.rounded() ? "\(Int(h))" : String(format: "%g", h)
}

/// One duration format everywhere: "2h", "45m", "2h 15m".
func fmtDur(_ h: Double) -> String {
    let t = Int((h * 60).rounded())
    let hh = t / 60, mm = t % 60
    if mm == 0 { return "\(hh)h" }
    if hh == 0 { return "\(mm)m" }
    return "\(hh)h \(mm)m"
}

/// Keep multi-word names ("Oak Street Duplex") on one line.
func nbsp(_ s: String) -> String { s.replacingOccurrences(of: " ", with: "\u{00A0}") }

func fmtHM(_ h: Double) -> (Int, Int) {
    let total = Int((h * 60).rounded())
    return (total / 60, total % 60)
}

/// Quiet "Beta" tag.
struct BetaTag: View {
    var body: some View {
        Text("Beta")
            .font(.caption2.weight(.medium))
            .foregroundStyle(LH.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(LH.separator, lineWidth: 1))
    }
}
