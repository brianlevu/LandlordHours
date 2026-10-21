import SwiftUI

// MARK: - Category tools (Blueprint art)

extension ActivityCategory {
    /// The Blueprint tool render for this category (Assets.xcassets/Blueprint/Tools, per
    /// design/blueprint-house/exports/manifest.json).
    var blueprintToolName: String {
        switch self {
        case .repairs: return "repairs"
        case .management: return "management"
        case .leasing: return "showing"
        case .bookkeeping: return "bookkeeping"
        case .legal: return "legal"
        case .investing: return "investing"
        case .financing: return "financing"
        case .insurance: return "insurance"
        case .contractNegotiation: return "negotiation"
        case .travel: return "travel"
        case .renovations: return "renovation"
        }
    }

    /// Short label for rows and pickers.
    var inboxLabel: String {
        switch self {
        case .repairs: return "Repairs"
        case .management: return "Management"
        case .leasing: return "Leasing"
        case .bookkeeping: return "Bookkeeping"
        case .legal: return "Legal"
        case .insurance: return "Insurance"
        case .travel: return "Travel"
        case .renovations: return "Renovation"
        case .investing: return "Investing"
        case .financing: return "Financing"
        case .contractNegotiation: return "Negotiation"
        }
    }

    /// Label ink: the category's own ink (AppColors.categoryInkHex), the one map used app-wide.
    func inboxInk(_ colors: AdaptiveColors) -> Color { colors.categoryInk(self) }

    /// Tile wash: the ink at 14%.
    func inboxWash(_ colors: AdaptiveColors) -> Color { colors.categoryWash(self) }
}

/// The category's tool on a soft material tile. Falls back to a dashed drafting square, never a
/// flat symbol mixed into the 3D set.
struct CategoryToolTile: View {
    let category: ActivityCategory?
    var size: CGFloat = 36
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(category.map { $0.inboxWash(colors) } ?? colors.backgroundTertiary)
            .frame(width: size, height: size)
            .overlay {
                if let category {
                    Image("bp_tool_\(category.blueprintToolName)_\(size > 40 ? 56 : 36)")
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.08)
                } else {
                    RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                        .strokeBorder(colors.drafting, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .padding(size * 0.22)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Blueprint paper

/// Brand blueprint with a faint drafting grid, for the backfill banner and intro.
struct InboxBlueprintPaper: View {
    var cornerRadius: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: "2447B5"), AppColors.brand, Color(hex: "18348C")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Canvas { context, size in
                    let step: CGFloat = 22
                    var path = Path()
                    var x: CGFloat = 0
                    while x <= size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        x += step
                    }
                    var y: CGFloat = 0
                    while y <= size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        y += step
                    }
                    context.stroke(path, with: .color(Color(hex: AppColors.Hex.drafting).opacity(0.12)), lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .accessibilityHidden(true)
    }
}

/// Text colours on the blueprint (theme-fixed surface).
enum OnBlueprint {
    static let primary = Color.white
    /// 8.0:1 on #1E3FA6.
    static let secondary = Color(hex: "D6E0FA")
}

// MARK: - Buttons

/// Full-width 52pt capsule in the action colour.
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

/// White pill with blueprint text, for buttons that sit on the blueprint.
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
/// border that stays visible when off.
struct InboxSwitchStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    // colour when on. The off track is darker than iOS 27's (which measures
                    // ~1.05:1 on a white card) so the off state stays visible.
                    Capsule()
                        .fill(configuration.isOn ? colors.action : (colorScheme == .dark ? Color(hex: "39446E") : Color(hex: "C7CEDD")))
                        .frame(width: 51, height: 31)
                    Circle()
                        .fill(configuration.isOn ? colors.onAction : Color.white)
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                        .frame(width: 27, height: 27)
                        .padding(2)
                }
                .animation(reduceMotion ? nil : AppAnimation.quick, value: configuration.isOn)
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

// MARK: - Privacy footer

/// Flighty's privacy footer: positive wash, shield, "Stays on your iPhone".
struct CapturePrivacyFooter: View {
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 20))
                .foregroundStyle(colors.positive)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Stays on your iPhone")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.positive)
                Text("We read event titles on your iPhone. Only events you confirm are saved.")
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(colors.positiveSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("capture.privacyFooter")
    }
}

// MARK: - Badges

struct InboxBadge: View {
    enum Tone { case caution, info }
    let text: String
    let tone: Tone
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tone == .caution ? colors.caution : colors.informational)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tone == .caution ? colors.cautionSurface : colors.informationalSurface))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Three tools resting on the canvas: the empty inbox's art ("everything put away").
struct InboxEmptyArt: View {
    var body: some View {
        ZStack {
            Image("bp_tool_showing_56").resizable().scaledToFit()
                .frame(width: 76, height: 76)
                .rotationEffect(.degrees(-8))
                .offset(x: -48, y: 10)
            Image("bp_tool_management_56").resizable().scaledToFit()
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(7))
                .offset(x: 46, y: 6)
            Image("bp_tool_repairs_56").resizable().scaledToFit()
                .frame(width: 92, height: 92)
                .offset(y: -14)
        }
        .frame(width: 200, height: 130)
        .accessibilityHidden(true)
    }
}


/// Confirm (44pt action capsule) and Not rental work, under each Inbox row's words. One line when it
/// fits; stacked at large text sizes so nothing is pushed past the card's edges.
struct InboxRowActions: View {
    let key: String
    let onConfirm: () -> Void
    let onNotWork: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { confirm; notWork }
            VStack(alignment: .leading, spacing: 2) { confirm; notWork }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Lines up with the row's words (hours column + tool tile), except at large text sizes.
        .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 108)
    }

    private var confirm: some View {
        Button(action: onConfirm) {
            // Icon and word spelled out (a Label can collapse to its icon inside a List row).
            HStack(spacing: 6) {
                Image(systemName: "checkmark").accessibilityHidden(true)
                Text("Confirm").lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.onAction)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(colors.action, in: Capsule())
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("inbox.confirm.\(key)")
    }

    private var notWork: some View {
        Button(action: onNotWork) {
            Text("Not rental work")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .fixedSize()
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Not rental work")
        .accessibilityIdentifier("inbox.notWork.\(key)")
    }
}
