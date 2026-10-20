import SwiftUI

/// Flighty result-row anatomy in the Blueprint world: big hours on the left, the category tool,
/// then source line, bold-noun title, and the category or badges.
struct SuggestionRowView: View {
    let suggestion: Suggestion
    let propertyName: String?
    let badges: SuggestionBadges
    var now: Date = InboxClock.now()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        hoursColumn
                        CategoryToolTile(category: suggestion.proposedCategory, size: 36)
                    }
                    textColumn
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    hoursColumn.frame(width: 52)
                    CategoryToolTile(category: suggestion.proposedCategory, size: 36)
                    textColumn
                }
            }
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical, 12)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var hoursColumn: some View {
        if let hours = suggestion.proposedHours, hours > 0, !badges.needsHours {
            let minutes = Int((hours * 60).rounded())
            let h = minutes / 60
            let m = minutes % 60
            VStack(spacing: 0) {
                if h > 0 {
                    Text("\(h)h")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                }
                if m > 0 {
                    Text("\(m)m")
                        .font(.system(h > 0 ? .callout : .title2, design: .rounded, weight: h > 0 ? .semibold : .bold))
                        .foregroundStyle(h > 0 ? colors.textSecondary : colors.textPrimary)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else {
            Text("—")
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
        }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: InboxFormat.kindSymbol(suggestion.kind))
                    .font(.system(size: 11, weight: .semibold))
                Text(InboxFormat.sourceLine(suggestion, now: now))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            }
            .font(.subheadline)
            .foregroundStyle(colors.textSecondary)

            title
                .font(.body)
                .foregroundStyle(colors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            detailLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: Text {
        let noun = Text(suggestion.title).fontWeight(.semibold)
        guard let propertyName else { return noun }
        return Text("\(noun) at \(Text(propertyName).fontWeight(.semibold))")
    }

    /// The classifier's category on every row; status words (not sure, might be logged, needs
    /// hours) follow it. A missing property is asked for on Confirm, not flagged with a chip.
    @ViewBuilder private var detailLine: some View {
        if let category = suggestion.proposedCategory {
            Text(category.inboxLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(category.inboxInk(colors))
        }
        if badges.notSure || badges.mightAlreadyBeLogged || badges.needsHours {
            FlowBadges(items: badgeItems)
        }
    }

    private var badgeItems: [(String, InboxBadge.Tone)] {
        var items: [(String, InboxBadge.Tone)] = []
        if badges.notSure { items.append(("Not sure", .caution)) }
        if badges.mightAlreadyBeLogged { items.append(("Might already be logged", .info)) }
        if badges.needsHours { items.append(("Needs hours", .caution)) }
        return items
    }

    /// VoiceOver sentence for the whole row.
    static func accessibilityLabel(for suggestion: Suggestion, propertyName: String?, badges: SuggestionBadges, now: Date) -> String {
        var parts: [String] = []
        if let hours = suggestion.proposedHours, hours > 0, !badges.needsHours {
            parts.append(InboxFormat.spokenHours(hours))
        } else {
            parts.append("Hours needed")
        }
        parts.append(propertyName.map { "\(suggestion.title) at \($0)" } ?? suggestion.title)
        parts.append(InboxFormat.sourceLine(suggestion, now: now).replacingOccurrences(of: "–", with: " to "))
        if let category = suggestion.proposedCategory { parts.append(category.inboxLabel) }
        if badges.notSure { parts.append(ConfidenceBand.notSureLabel) }
        if badges.mightAlreadyBeLogged { parts.append("Might already be logged") }
        return parts.joined(separator: ". ")
    }
}

/// Badges that wrap onto a second line instead of truncating.
private struct FlowBadges: View {
    let items: [(String, InboxBadge.Tone)]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                ForEach(items, id: \.0) { InboxBadge(text: $0.0, tone: $0.1) }
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items, id: \.0) { InboxBadge(text: $0.0, tone: $0.1) }
            }
        }
        .padding(.top, 2)
    }
}
