import SwiftUI

// MARK: - Category tools

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

/// "Stays on your iPhone": a positive wash on the inner surface (radius 12), a shield, two lines.
struct CapturePrivacyFooter: View {
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title3)
                .foregroundStyle(colors.positive)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "capture.privacy.title", defaultValue: "Stays on your iPhone", table: "Inbox"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.positiveText)
                Text(String(localized: "capture.privacy.body", defaultValue: "We read event titles on your iPhone. Only events you confirm are saved.", table: "Inbox"))
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(LHMetrics.cardPadding)
        .background(colors.positiveSurface, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("capture.privacyFooter")
    }
}
