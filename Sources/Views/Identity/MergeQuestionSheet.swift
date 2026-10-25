import SwiftUI

// MARK: - The only question the app asks (P4, with P5 / P6 as a second step)
//
// Anchor: iOS Settings › iCloud › Contacts "Merge". Whenever two or more non-empty sets exist,
// once per held set, largest first. Swipe down = decide later: the set stays held, listed under
// Earlier records, never merged, never deleted. The REPS test is per person, so there is no size
// threshold. Spouse and aside are reversible, so they get a second step, not an alert (§1.21).

struct MergeQuestionSheet: View {
    let group: ArchivedGroup
    var index = 1
    var total = 1
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .ask

    enum Step: Equatable { case ask, spouse, aside }

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        LHSheet(title, onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: 16) {
                switch step {
                case .ask: ask
                case .spouse: confirm(String(localized: "Add \(IdentityCopy.hours(group.hours)) as your spouse’s? Their hours count with yours for the 500-hour test. They stay separate for the 750. You can undo this for 30 days.", table: "Identity"))
                case .aside: confirm(String(localized: "Keep \(IdentityCopy.hours(group.hours)) aside? Nothing is deleted. You’ll find them under Earlier records.", table: "Identity"))
                }
            }
            .padding(.top, 4)
            .animation(reduceMotion ? nil : AppAnimation.quick, value: step)
        } footer: {
            footer
        }
        .background(colors.backgroundSecondary.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("identity.mergeQuestion")
    }

    private var title: String {
        switch step {
        case .ask:
            return total > 1
                ? String(localized: "We found more records. Set \(index) of \(total).", table: "Identity")
                : String(localized: "We found two sets of records.", table: "Identity")
        case .spouse: return String(localized: "Your spouse’s hours", table: "Identity")
        case .aside: return String(localized: "Keep them aside", table: "Identity")
        }
    }

    @ViewBuilder private var ask: some View {
        let live = viewModel.timeEntries
        LHRowGroup {
            setRow(summary: IdentityCopy.groupSummary(hours: live.reduce(0) { $0 + $1.hours }, rentals: viewModel.properties.count,
                                                      last: live.map(\.date).max()),
                   source: String(localized: "Your records now", table: "Identity"), glyph: "iphone")
            LHDivider(leadingInset: LHRow.browseDividerInset)
            setRow(summary: IdentityCopy.groupSummary(hours: group.hours, rentals: group.properties.count, last: group.lastEntryDate),
                   source: IdentityCopy.groupSource(group.source), glyph: group.source == .device ? "iphone" : "icloud")
        }
        Text(String(localized: "Are both yours?", table: "Identity"))
            .font(.headline)
            .foregroundStyle(colors.textPrimary)
        Text(String(localized: "Nothing is deleted whichever you pick.", table: "Identity"))
            .font(.subheadline)
            .foregroundStyle(colors.textSecondary)
    }

    private func setRow(summary: String, source: String, glyph: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            LHRowGlyph(systemImage: glyph, tint: .neutral)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary).font(.body).foregroundStyle(colors.textPrimary)
                Text(source).font(.subheadline).foregroundStyle(colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(LHRow.insets)
        .frame(minHeight: LHMetrics.rowMinHeight)
        .accessibilityElement(children: .combine)
    }

    private func confirm(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(colors.textPrimary)
    }

    @ViewBuilder private var footer: some View {
        switch step {
        case .ask:
            // One `.primary`; the two other answers are `.tertiary` (stacked, never side by side).
            Button(String(localized: "These are my spouse’s hours", table: "Identity")) { step = .spouse }
                .buttonStyle(LHButton.tertiary)
                .accessibilityIdentifier("identity.merge.spouse")
            Button(String(localized: "Not mine, keep them aside", table: "Identity")) { step = .aside }
                .buttonStyle(LHButton.tertiary)
                .accessibilityIdentifier("identity.merge.aside")
            Button(String(localized: "Yes, combine them", table: "Identity")) { finish(.combine) }
                .buttonStyle(LHButton.primary)
                .accessibilityIdentifier("identity.merge.combine")
        case .spouse:
            Button(String(localized: "Back", table: "Identity")) { step = .ask }
                .buttonStyle(LHButton.tertiary)
                .accessibilityIdentifier("identity.merge.back")
            Button(String(localized: "Add as your spouse’s hours", table: "Identity")) { finish(.spouse) }
                .buttonStyle(LHButton.primary)
                .accessibilityIdentifier("identity.merge.confirmSpouse")
        case .aside:
            Button(String(localized: "Back", table: "Identity")) { step = .ask }
                .buttonStyle(LHButton.tertiary)
                .accessibilityIdentifier("identity.merge.back")
            Button(String(localized: "Keep aside", table: "Identity")) { finish(.aside) }
                .buttonStyle(LHButton.primary)
                .accessibilityIdentifier("identity.merge.confirmAside")
        }
    }

    private func finish(_ answer: TwoSetsAnswer) {
        viewModel.answerTwoSets(answer, group: group.id)
        switch answer {
        case .combine:
            LHToastCenter.shared.show(.success, String(localized: "Combined. \(IdentityCopy.hours(group.hours)) added.", table: "Identity"))
        case .spouse:
            LHToastCenter.shared.show(.success, String(localized: "Added as your spouse’s hours.", table: "Identity"))
        case .aside:
            LHToastCenter.shared.show(.success, String(localized: "Kept aside under Earlier records.", table: "Identity"))
        }
        dismiss()
    }
}
