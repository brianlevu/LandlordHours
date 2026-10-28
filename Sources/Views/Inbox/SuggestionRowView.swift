import SwiftUI

// MARK: - The Inbox row (standard §1.3)
//
// One `LHRow.Action` fed from a suggestion: a 22pt control in a 44 frame, the title ("Plumber at
// Pine Cabin"), one meta line (source glyph, time range, one tag) and the hours at the trailing
// edge. No tool render, no pill, no date (the day header above carries it). Swipes are the
// caller's system `.swipeActions`; the row tap opens the confirm sheet.

struct SuggestionRowView: View {
    let suggestion: Suggestion
    let propertyName: String?
    let badges: SuggestionBadges
    /// The free plan is full and this item is at a new rental.
    var limit: InboxRowLimit = .none
    /// Whether the control confirms at once (`canQuickLog`) or opens the sheet.
    var quick = false
    /// `rowConfirm`: the control has filled and the row is about to leave.
    var confirmed = false
    var now: Date = InboxClock.now()
    var onControl: () -> Void = {}
    var onOpen: (() -> Void)? = nil
    var onNotWork: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var hours: Double? { badges.needsHours ? nil : suggestion.proposedHours }

    var body: some View {
        LHRow.Action(
            title: InboxFormat.rowTitle(suggestion, propertyName: propertyName),
            sourceSymbol: InboxFormat.kindSymbol(suggestion.kind),
            meta: InboxFormat.rowMeta(suggestion),
            tag: shownTag,
            hours: hours,
            control: confirmed ? .confirmed : .open,
            controlLabel: Self.controlLabel(quick: quick, hours: hours),
            onControl: onControl,
            onOpen: onOpen,
            identifier: "inbox.row.\(suggestion.sourceKey)"
        )
        .accessibilityLabel(Self.accessibilityLabel(for: suggestion, propertyName: propertyName, badges: badges, now: now, limit: limit))
        .accessibilityHint(String(localized: "inbox.row.hint", defaultValue: "Opens the details to confirm", table: "Inbox"))
        .accessibilityAddTraits(.isButton)
        .modifier(NotWorkAction(action: onNotWork))
    }

    /// At accessibility sizes the row stacks title, time, tag and hours, and one item took a third of
    /// the screen (D2 asks for 30%). A plain category tag is the least needed of them, so it drops
    /// there; a status tag ("Needs hours", "Not sure", "Might be logged") stays.
    private var shownTag: LHTag? {
        let hasStatus = limit != .none || badges.mightAlreadyBeLogged || badges.needsHours || badges.notSure
        if typeSize.isAccessibilitySize && !hasStatus { return nil }
        return Self.tag(suggestion, badges: badges, limit: limit, colors: colors)
    }

    static func controlLabel(quick: Bool, hours: Double?) -> String {
        guard quick else {
            return String(localized: "inbox.row.review", defaultValue: "Review and confirm", table: "Inbox")
        }
        return String(localized: "inbox.row.confirmHours", defaultValue: "Confirm \(InboxFormat.spokenHours(hours ?? 0))", table: "Inbox")
    }

    /// One tag: a status word replaces the category. A missing property is asked for on the sheet,
    /// not flagged here.
    static func tag(_ suggestion: Suggestion, badges: SuggestionBadges, limit: InboxRowLimit, colors: AdaptiveColors) -> LHTag? {
        switch limit {
        case .waiting:
            return LHTag(String(localized: "inbox.tag.waitingOnPro", defaultValue: "Waiting on Pro", table: "Inbox"), tone: .neutral)
        case .newPlace:
            return LHTag(String(localized: "inbox.tag.newPlace", defaultValue: "New place", table: "Inbox"), tone: .informational)
        case .none:
            break
        }
        // Needs hours, then Not sure, then Might be logged: whether it is rental work at all
        // outranks whether it is already logged.
        if badges.needsHours {
            return LHTag(String(localized: "inbox.tag.needsHours", defaultValue: "Needs hours", table: "Inbox"), tone: .caution)
        }
        if badges.notSure {
            return LHTag(String(localized: "inbox.tag.notSure", defaultValue: "Not sure", table: "Inbox"), tone: .neutral)
        }
        if badges.mightAlreadyBeLogged {
            return LHTag(String(localized: "inbox.tag.mightBeLogged", defaultValue: "Might be logged", table: "Inbox"), tone: .informational)
        }
        guard let category = suggestion.proposedCategory else { return nil }
        return LHTag(category.inboxLabel, tone: .custom(ink: colors.categoryInk(category), wash: colors.categoryWash(category)))
    }

    /// VoiceOver sentence for the whole row: "Plumber at Pine Cabin, Calendar, 12 to 2, Repairs, 2 hours".
    static func accessibilityLabel(for suggestion: Suggestion, propertyName: String?, badges: SuggestionBadges, now: Date,
                                   limit: InboxRowLimit = .none) -> String {
        var parts: [String] = [InboxFormat.rowTitle(suggestion, propertyName: propertyName)]
        parts.append(InboxFormat.sourceLine(suggestion, now: now).replacingOccurrences(of: "–", with: " to "))
        if let category = suggestion.proposedCategory { parts.append(category.inboxLabel) }
        if badges.notSure { parts.append(ConfidenceBand.notSureLabel) }
        if badges.mightAlreadyBeLogged {
            parts.append(String(localized: "inbox.a11y.mightBeLogged", defaultValue: "Might already be logged", table: "Inbox"))
        }
        switch limit {
        case .waiting: parts.append(InboxProLimit.waitingLabel)
        case .newPlace: parts.append(InboxProLimit.newPlaceLabel)
        case .none: break
        }
        if let hours = suggestion.proposedHours, hours > 0, !badges.needsHours {
            parts.append(InboxFormat.spokenHours(hours))
        } else {
            parts.append(String(localized: "inbox.a11y.hoursNeeded", defaultValue: "Hours needed", table: "Inbox"))
        }
        return parts.joined(separator: ", ")
    }
}

private struct NotWorkAction: ViewModifier {
    let action: (() -> Void)?
    func body(content: Content) -> some View {
        if let action {
            content.accessibilityAction(named: Text(String(localized: "inbox.row.notWork", defaultValue: "Not rental work", table: "Inbox")), action)
        } else {
            content
        }
    }
}

/// How a row reads while the free plan is at its limit.
enum InboxRowLimit: Equatable {
    case none
    /// At a rental the user doesn't have: "New place".
    case newPlace
    /// Kept for later: "Waiting on Pro".
    case waiting
}
