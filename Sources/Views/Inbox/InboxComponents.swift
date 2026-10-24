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

// `CategoryToolTile` moved to `Components/CategoryToolTile.swift`; `InboxBlueprintPaper`,
// `OnBlueprint`, `InboxPrimaryButtonStyle`, `OnBlueprintButtonStyle` and `InboxSwitchStyle` moved to
// `Components/LegacyBlueprint.swift` (v2 revamp plan, package 0a).

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
