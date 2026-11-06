import SwiftUI

// MARK: - Legacy blueprint shims (plan package 0a; deleted in cleanup)
//
// v2 retires the Job Site blueprint canvas (standard §H.4: no `BlueprintGrid`, no
// `InboxBlueprintPaper` grid in `Sources/`). These five types moved here from
// `Inbox/InboxComponents.swift` so their callers in eight screen packages keep compiling while
// each lane removes its own uses (plan §4). Nothing new may adopt them; `LHButton`, `LHRow.Toggle`
// and the plain canvas replace them. When the last caller is gone, this file is deleted.
//
// `InboxBlueprintPaper` now draws a plain container: one flat fill in the brand blue, with no
// drafting grid and no hand-mixed gradient (the two hex stops are gone). It stays blue rather than
// turning white because every caller still sets white text on it (the paywall headline, the Learn
// hero, the rental hero, the backfill banner); white on `AppColors.brand` is 8.0:1
// (`ColorContrastTests.testWhiteOnBlueprintBrand`). A white container would leave that text
// invisible in light mode until each lane's redesign lands.

// MARK: - Paper

/// A plain, theme-fixed brand container. Legacy: no grid, no gradient (standard §H.4).
struct InboxBlueprintPaper: View {
    var cornerRadius: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppColors.brand)
            .accessibilityHidden(true)
    }
}

/// Text colours on the legacy brand container (theme-fixed surface).
enum OnBlueprint {
    static let primary = Color.white
    /// White at 85% on `AppColors.brand` (blends to about #DDE2F2): above 7:1, like the old #D6E0FA.
    static let secondary = Color.white.opacity(0.85)
}

// MARK: - Buttons

/// Full-width 52pt capsule in the action colour. Legacy: `LHButton.primary` replaces it.
struct InboxPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        configuration.label
            .font(AppTypography.buttonLarge)
            .foregroundStyle(isEnabled ? colors.onAction : colors.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(Capsule().fill(isEnabled ? colors.action : colors.backgroundTertiary))
            .overlay(Capsule().strokeBorder(isEnabled ? Color.clear : colors.border, lineWidth: 1))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : AppAnimation.feedback, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// White pill with brand text, for buttons that sit on the legacy brand container.
struct OnBlueprintButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.buttonLarge)
            .foregroundStyle(AppColors.brand)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(Capsule().fill(Color.white))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : AppAnimation.feedback, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

// MARK: - Switch with a visible off state

/// iOS 27's stock off track measures ~1.05:1 on a white card, so this draws its own track with a
/// border that stays visible when off. Legacy: `LHRow.Toggle` replaces it.
struct InboxSwitchStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    /// The off track: tertiary text at 35%. On a white card it blends to about #C8CCD6 (light), on
    /// the dark card to about #3E4669: the same values the old hand-picked #C7CEDD / #39446E had.
    static let offTrackOpacity = 0.35

    /// A plain style that, unlike `.plain`, does not fade the label when the row is disabled:
    /// the system fade put the row at 2.4 to 3.3:1. The disabled look is drawn with tokens by
    /// `SettingToggleRow` (calmer text colours that stay at 4.5:1 or better) and a paler switch.
    private struct NoFadeStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View { configuration.label }
    }

    func makeBody(configuration: Configuration) -> some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    // System polarity: a white knob on a grey track when off, on the action
                    // colour when on.
                    Capsule()
                        .fill(configuration.isOn ? colors.action : colors.textTertiary.opacity(Self.offTrackOpacity))
                        .frame(width: 51, height: 31)
                    Circle()
                        .fill(configuration.isOn ? colors.onAction : Color.white)
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                        .frame(width: 27, height: 27)
                        .padding(2)
                }
                .opacity(isEnabled ? 1 : 0.5)
                .animation(reduceMotion ? nil : AppAnimation.quick, value: configuration.isOn)
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(NoFadeStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
