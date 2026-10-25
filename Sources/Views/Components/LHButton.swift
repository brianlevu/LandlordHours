import SwiftUI

// MARK: - LHButton (standard §1.13)
//
// One ButtonStyle, four cases. It retires PropertyTintedButtonStyle, ProTintedButtonStyle,
// TodayTintedButtonStyle, the inline Confirm capsule, ProUnlockButtonStyle, the Onb* pills,
// InboxPrimaryButtonStyle and the hand-built close circles as each package moves its callers.
//
//   .primary    52 full-width capsule, .body.semibold, action / onAction. One per column or sheet,
//               pinned bottom in sheets. `.primaryGlass` adds Liquid Glass on iOS 26+ (the Log time
//               sheet's button); on iOS 18–25 it is the same solid capsule.
//   .secondary  44 hug, padding 18, capsule, .subheadline.semibold, actionSurface / action.
//   .tertiary   44 text, .subheadline.semibold, action ink (`.destructiveTertiary`: destructive ink).
//   .icon       44 circle, symbol .body.semibold, backgroundTertiary / textSecondary.
//
// Press = motion `press` (scale 0.97, `feedback` down / `quick` up; opacity 0.8 under Reduce
// Motion). Disabled = no opacity dim: a muted fill (`backgroundTertiary`, hairline `border`) with
// `textSecondary` ink on primary and secondary (≥ 4.5:1), `textSecondary` ink alone on tertiary and icon. `onBlueprint` keeps the 1.x blueprint-band variants (white on
// brand) for the screens that still draw that band until their package removes it.
//
// Usage: `Button("Log") { … }.buttonStyle(LHButton.primary)`;
//        `Button { … } label: { Image(systemName: "xmark") }.buttonStyle(LHButton.icon)
//             .accessibilityLabel("Close")`.

struct LHButton: ButtonStyle {
    enum Kind: Equatable, Sendable {
        case primary
        case secondary
        case tertiary
        case icon
    }

    var kind: Kind
    /// Tertiary only: destructive ink ("Delete rental", "Not rental work" in a sheet foot).
    var destructive = false
    /// Primary only: Liquid Glass on iOS 26+ (inside the availability branch; solid before).
    var glass = false
    /// The 1.x blueprint band (white / brand). Retires with the band.
    var onBlueprint = false

    static let primary = LHButton(kind: .primary)
    static let primaryGlass = LHButton(kind: .primary, glass: true)
    static let secondary = LHButton(kind: .secondary)
    static let tertiary = LHButton(kind: .tertiary)
    static let destructiveTertiary = LHButton(kind: .tertiary, destructive: true)
    static let icon = LHButton(kind: .icon)
    static let primaryOnBlueprint = LHButton(kind: .primary, onBlueprint: true)
    static let iconOnBlueprint = LHButton(kind: .icon, onBlueprint: true)

    /// Heights and paddings (§1.13), exposed for the component sheet and tests.
    enum Metrics {
        static let primaryHeight: CGFloat = 52
        static let controlHeight: CGFloat = 44
        static let secondaryPadding: CGFloat = 18
        static let primaryPadding: CGFloat = 20
        static let pressedScale: CGFloat = 0.97
            }

    func makeBody(configuration: Configuration) -> some View {
        LHButtonBody(style: self, configuration: configuration)
    }
}

private struct LHButtonBody: View {
    let style: LHButton
    let configuration: ButtonStyle.Configuration

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The icon circle grows with the text so the glyph stays inside it at AX sizes (min 44).
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = LHButton.Metrics.controlHeight

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var pressed: Bool { configuration.isPressed }

    var body: some View {
        styled
            .opacity(reduceMotion && pressed ? 0.8 : 1)
            .scaleEffect(pressed && !reduceMotion ? LHButton.Metrics.pressedScale : 1)
            .animation(pressed ? AppAnimation.feedback : AppAnimation.quick, value: pressed)
    }

    /// Disabled ink and fill (§1.13): full-contrast secondary text on a muted fill, never a dimmed label.
    private var disabledInk: Color { colors.textSecondary }
    private func disabledFill(_ shape: some InsettableShape) -> some View {
        shape.fill(colors.backgroundTertiary).overlay(shape.strokeBorder(colors.border, lineWidth: 1))
    }

    @ViewBuilder private var styled: some View {
        switch style.kind {
        case .primary: primary
        case .secondary: secondary
        case .tertiary: tertiary
        case .icon: icon
        }
    }

    // MARK: Cases

    private var primaryFill: Color { style.onBlueprint ? Color.white : colors.action }
    private var primaryInk: Color { style.onBlueprint ? AppColors.brand : colors.onAction }

    @ViewBuilder private var primary: some View {
        let label = configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, LHButton.Metrics.primaryPadding)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: LHButton.Metrics.primaryHeight)
            .contentShape(Capsule())
        if !isEnabled {
            label
                .foregroundStyle(disabledInk)
                .background(disabledFill(Capsule()))
        } else if style.glass, #available(iOS 26.0, *) {
            label
                .foregroundStyle(primaryInk)
                .glassEffect(.regular.tint(primaryFill).interactive(), in: .capsule)
        } else {
            label
                .foregroundStyle(primaryInk)
                .background(primaryFill, in: Capsule())
        }
    }

    private var secondary: some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? (style.onBlueprint ? Color.white : colors.action) : disabledInk)
            .multilineTextAlignment(.center)
            .padding(.horizontal, LHButton.Metrics.secondaryPadding)
            .padding(.vertical, 10)
            .frame(minHeight: LHButton.Metrics.controlHeight)
            .background {
                if isEnabled { Capsule().fill(style.onBlueprint ? Color.white.opacity(0.14) : colors.actionSurface) }
                else { disabledFill(Capsule()) }
            }
            .contentShape(Capsule())
    }

    private var tertiary: some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? (style.destructive ? colors.destructive : (style.onBlueprint ? Color.white : colors.action)) : disabledInk)
            .multilineTextAlignment(.center)
            .frame(minHeight: LHButton.Metrics.controlHeight)
            .contentShape(Rectangle())
    }

    private var icon: some View {
        configuration.label
            // §1.17: the one place a symbol weight is set explicitly.
            .font(.body.weight(.semibold))
            .imageScale(.medium)
            .foregroundStyle(style.onBlueprint ? Color.white : (isEnabled ? colors.textSecondary : colors.textTertiary))
            .frame(width: max(iconSide, LHButton.Metrics.controlHeight), height: max(iconSide, LHButton.Metrics.controlHeight))
            .background(style.onBlueprint ? Color.white.opacity(0.14) : colors.backgroundTertiary, in: Circle())
            .contentShape(Circle())
    }
}

// MARK: - Press for whole-row and whole-tile targets

extension LHButton {
    /// `press` on a tappable row, tile or chip that is not one of the four cases (the row is the
    /// target; §1.1): scale 0.97 on down, opacity 0.8 under Reduce Motion, no fill and no ink.
    /// Usage: `.buttonStyle(LHButton.press)`.
    static let press = LHPressStyle()
}

struct LHPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LHPressBody(configuration: configuration)
    }
}

private struct LHPressBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(pressed && !reduceMotion ? LHButton.Metrics.pressedScale : 1)
            .opacity(isEnabled ? (pressed && reduceMotion ? 0.8 : 1) : 0.4)
            .animation(pressed ? AppAnimation.feedback : AppAnimation.quick, value: pressed)
    }
}
