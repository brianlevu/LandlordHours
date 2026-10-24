import SwiftUI

// MARK: - Today v2: the parts under the crafted house (standard §H.8)
//
//   chip · hero (H1) + dots · number (Fraunces 84) · "of 100 hours" · pace sentence ·
//   "To confirm · N" · one grouped container on the page with ≤ 2 `LHRow.Action` rows and a
//   "See all N" foot · nothing else.
//
// The rules live in `TodayLogic.swift`; these views only draw what it returns. Strings are in the
// package catalog `Today.xcstrings` (`String(localized:defaultValue:table: "Today")`).

/// Today's own strings.
enum TodayText {
    static var allRentals: String { String(localized: "today.allRentals", defaultValue: "All rentals", table: "Today") }
    static var toConfirmTitle: String { String(localized: "today.confirm.title", defaultValue: "To confirm", table: "Today") }
    static func toConfirm(_ count: Int) -> String {
        String(localized: "today.confirm.titleCount", defaultValue: "To confirm · \(count)", table: "Today")
    }
    static func seeAll(_ count: Int) -> String {
        String(localized: "today.confirm.seeAll", defaultValue: "See all \(count)", table: "Today")
    }
    static func ofHours(_ goal: Int) -> String {
        String(localized: "today.number.of", defaultValue: "of \(goal) hours", table: "Today")
    }
    static func hoursIn(_ year: Int) -> String {
        String(localized: "today.number.record", defaultValue: "hours in \(String(year))", table: "Today")
    }
    static func logged(_ hours: String, at rental: String) -> String {
        String(localized: "today.toast.logged", defaultValue: "Logged \(hours) at \(rental).", table: "Today")
    }
    static func loggedPlain(_ hours: String) -> String {
        String(localized: "today.toast.loggedPlain", defaultValue: "Logged \(hours).", table: "Today")
    }
    static var undo: String { String(localized: "today.toast.undo", defaultValue: "Undo", table: "Today") }
    static var markedNotWork: String {
        String(localized: "today.toast.notWork", defaultValue: "Marked not rental work.", table: "Today")
    }
}

// MARK: - The number block

/// The number tied to the house: the Fraunces numeral, "of 100 hours", the pace sentence.
struct TodayNumberBlock: View {
    let hours: Double
    let goal: Double
    let year: Int
    let isRecord: Bool
    let pace: TodayPaceSentence
    /// The numeral's size (84 default, 64 under 700pt of height, 54 at AX; H3/H7).
    let numeralSize: CGFloat
    /// While the first iCloud pull is pending the number shows a dash.
    var isPending = false
    /// The pace line opens a question ("did anyone else do more?").
    var onPaceTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var whole: Int { Int(max(0, hours).rounded(.down)) }

    var body: some View {
        VStack(spacing: 2) {
            Text(isPending ? "—" : "\(whole)")
                .font(LHFont.heroNumeral(size: numeralSize))
                .tracking(-2)
                .foregroundStyle(colors.textPrimary)
                .contentTransition(.numericText(value: Double(whole)))
                .animation(reduceMotion ? nil : AppAnimation.count, value: whole)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityIdentifier("today.number")
            Text(isRecord ? TodayText.hoursIn(year) : TodayText.ofHours(Int(goal.rounded())))
                .font(.body)
                .foregroundStyle(colors.textSecondary)
            paceLine
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("today.numberBlock")
    }

    @ViewBuilder private var paceLine: some View {
        let line = paceText
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
            .accessibilityIdentifier("today.pace")
        if let onPaceTap {
            Button(action: onPaceTap) { line }
                .buttonStyle(LHButton.press)
                .accessibilityHint(String(localized: "today.pace.questionHint",
                                          defaultValue: "Opens the question about anyone else’s hours", table: "Today"))
        } else {
            line
        }
    }

    private var paceText: Text {
        let rest = Text(pace.rest).foregroundStyle(colors.textSecondary)
        guard let lead = pace.lead else { return rest }
        let ink: Color
        switch pace.tone {
        case .behind: ink = colors.behind
        case .positive: ink = colors.positiveOnPage
        case .neutral: ink = colors.textPrimary
        }
        return Text(lead).foregroundStyle(ink).fontWeight(.semibold) + Text(verbatim: " ") + rest
    }
}

// MARK: - To confirm

/// "To confirm · N", at most `limit` `LHRow.Action` rows in one grouped container on the page,
/// and a "See all N" foot. Reads the Inbox model; every action is the Inbox's own.
struct TodayConfirmBlock: View {
    @ObservedObject var inbox: InboxViewModel
    let state: TodayConfirm.State
    let isScanning: Bool
    let limit: Int
    var onSeeAll: () -> Void
    var onTurnOn: () -> Void
    /// A row was logged (the hero rolls from the live hours; the caller posts the toast).
    var onLogged: (Suggestion) -> Void = { _ in }
    var onNotWork: (Suggestion) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Rows whose control has filled (`rowConfirm`), before the row collapses.
    @State private var confirming: Set<String> = []

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var count: Int { inbox.badgeCount }
    private var rows: [Suggestion] { TodayConfirm.rows(visible: inbox.visible, limit: limit) }

    var body: some View {
        if state != .hidden {
            VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
                Text(state == .rows ? TodayText.toConfirm(count) : TodayText.toConfirmTitle)
                    .font(.headline)
                    .foregroundStyle(colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("today.confirm.count")
                    .padding(.horizontal, 4)
                switch state {
                case .rows: card
                case .loading: scanning
                case .caughtUp(let captureOn): caughtUp(captureOn: captureOn)
                case .hidden: EmptyView()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.confirm")
        }
    }

    // MARK: Rows

    private var card: some View {
        let shown = rows
        return LHRowGroup(onPage: true) {
            ForEach(Array(shown.enumerated()), id: \.element.sourceKey) { index, suggestion in
                if index > 0 { LHDivider(leadingInset: LHRow.actionDividerInset) }
                row(suggestion)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
            if TodayConfirm.showsReviewAll(count: count, limit: limit) {
                LHDivider()
                Button(TodayText.seeAll(count), action: onSeeAll)
                    .buttonStyle(LHButton.tertiary)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint(String(localized: "today.confirm.seeAllHint", defaultValue: "Opens your Inbox", table: "Today"))
                    .accessibilityIdentifier("today.confirm.seeAll")
            }
        }
        .animation(reduceMotion ? AppAnimation.quick : AppAnimation.collapse, value: shown.map(\.sourceKey))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.confirm.card")
    }

    private func row(_ suggestion: Suggestion) -> some View {
        let badges = inbox.badges(for: suggestion)
        let quick = inbox.canQuickLog(suggestion)
        let hours = badges.needsHours ? nil : suggestion.proposedHours
        let title = Self.title(suggestion, propertyName: inbox.propertyName(for: suggestion))
        return LHRow.Action(
            title: title,
            sourceSymbol: InboxFormat.kindSymbol(suggestion.kind),
            meta: Self.meta(suggestion),
            tag: Self.tag(suggestion, badges: badges, colors: colors),
            hours: hours,
            control: confirming.contains(suggestion.sourceKey) ? .confirmed : .open,
            controlLabel: quick
                ? String(localized: "today.row.confirmHours", defaultValue: "Confirm \(InboxFormat.spokenHours(hours ?? 0))", table: "Today")
                : String(localized: "today.row.review", defaultValue: "Review and confirm", table: "Today"),
            onControl: { confirm(suggestion, quick: quick) },
            onOpen: { inbox.sheetSuggestion = suggestion },
            identifier: "today.row.\(suggestion.sourceKey)"
        )
        .accessibilityAction(named: String(localized: "today.row.notWork", defaultValue: "Not rental work", table: "Today")) {
            notWork(suggestion)
        }
        .contextMenu {
            if quick {
                Button { confirm(suggestion, quick: true) } label: {
                    Label(String(localized: "today.menu.confirm", defaultValue: "Confirm", table: "Today"), systemImage: "checkmark")
                }
            }
            Button { inbox.sheetSuggestion = suggestion } label: {
                Label(String(localized: "today.menu.open", defaultValue: "Open", table: "Today"), systemImage: "arrow.up.right")
            }
            Button { notWork(suggestion) } label: {
                Label(String(localized: "today.row.notWork", defaultValue: "Not rental work", table: "Today"), systemImage: "xmark")
            }
        }
    }

    /// "Plumber at Pine Cabin" (§1.3 title).
    static func title(_ suggestion: Suggestion, propertyName: String?) -> String {
        guard let propertyName, !propertyName.isEmpty else { return suggestion.title }
        return String(localized: "today.row.title", defaultValue: "\(suggestion.title) at \(propertyName)", table: "Today")
    }

    /// "Calendar · 12–2" (no date: Today's rows are this week's work; the Inbox has the day headers).
    static func meta(_ suggestion: Suggestion) -> String {
        let kind = InboxFormat.kindLabel(suggestion.kind)
        if suggestion.kind == .receipt { return kind }
        return "\(kind) · \(InboxFormat.timeRange(start: suggestion.start, end: suggestion.end))"
    }

    /// One tag: a status tag replaces the category.
    static func tag(_ suggestion: Suggestion, badges: SuggestionBadges, colors: AdaptiveColors) -> LHTag? {
        if badges.mightAlreadyBeLogged {
            return LHTag(String(localized: "today.tag.mightBeLogged", defaultValue: "Might be logged", table: "Today"), tone: .informational)
        }
        if badges.needsHours {
            return LHTag(String(localized: "today.tag.needsHours", defaultValue: "Needs hours", table: "Today"), tone: .caution)
        }
        if badges.notSure {
            return LHTag(String(localized: "today.tag.notSure", defaultValue: "Not sure", table: "Today"), tone: .neutral)
        }
        guard let category = suggestion.proposedCategory else { return nil }
        return LHTag(category.inboxLabel, tone: .custom(ink: colors.categoryInk(category), wash: colors.categoryWash(category)))
    }

    // MARK: Actions

    private func confirm(_ suggestion: Suggestion, quick: Bool) {
        guard quick else {
            inbox.sheetSuggestion = suggestion
            return
        }
        guard !confirming.contains(suggestion.sourceKey) else { return }
        // `rowConfirm`: the control fills (the row's `.success` fires with it), then the row collapses.
        confirming.insert(suggestion.sourceKey)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.12 + 0.25))
            if inbox.swipeLog(suggestion) == .logged { onLogged(suggestion) }
            confirming.remove(suggestion.sourceKey)
        }
    }

    private func notWork(_ suggestion: Suggestion) {
        inbox.dismiss(suggestion)
        onNotWork(suggestion)
    }

    // MARK: States

    private var scanning: some View {
        LHRowGroup(onPage: true) {
            Text(String(localized: "today.confirm.scanning", defaultValue: "Looking through your calendar. Work we find shows up here.", table: "Today"))
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(LHRow.insets)
                .frame(minHeight: LHMetrics.rowMinHeight)
        }
        .accessibilityIdentifier("today.lookingBack")
    }

    private func caughtUp(captureOn: Bool) -> some View {
        LHRowGroup(onPage: true) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.positive)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "today.caughtUp.title", defaultValue: "All caught up", table: "Today"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(captureOn
                         ? String(localized: "today.caughtUp.on", defaultValue: "New work from your calendar shows up here.", table: "Today")
                         : String(localized: "today.caughtUp.off", defaultValue: "Turn on suggestions and we’ll spot the work for you.", table: "Today"))
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(LHRow.insets)
            .frame(minHeight: LHMetrics.rowMinHeight)
            .accessibilityElement(children: .combine)
            if !captureOn {
                LHDivider()
                Button(String(localized: "today.caughtUp.turnOn", defaultValue: "Turn on suggestions", table: "Today"), action: onTurnOn)
                    .buttonStyle(LHButton.tertiary)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("today.confirm.turnOn")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(captureOn ? "today.caughtUp" : "today.caughtUp.off")
    }
}

// MARK: - Timer slot

/// A running or stopped timer (package E's `TodayTimerSection`); renders nothing otherwise.
struct TodayTimerSlot: View {
    var body: some View {
        TodayTimerSection()
    }
}

// MARK: - Your record (free)

/// Today's Pro surface for a free user with 10 confirmed hours or more, below the fold (the rule
/// is ProGate's). `onUnlock` runs after a purchase (Today opens the export).
struct TodayRecordSlot: View {
    let year: Int
    let confirmedHours: Double
    var onUnlock: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    static func isShown(isPro: Bool, confirmedHours: Double) -> Bool {
        ProGate.showsTodayRecordLock(isPro: isPro, confirmedHours: confirmedHours)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            Text(String(localized: "today.record.title", defaultValue: "Your record", table: "Today"))
                .font(.headline)
                .foregroundStyle(AdaptiveColors(colorScheme: colorScheme).textPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 4)
            TodayRecordLockCard(year: year, confirmedHours: confirmedHours, onUnlocked: onUnlock)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Today's "Your record" card for a free user: a page thumbnail with its top third sharp, the rest
/// under the lock. "Unlock Pro" opens the paywall about the user's own hours; afterwards it opens
/// the export.
struct TodayRecordLockCard: View {
    let year: Int
    let confirmedHours: Double
    /// Runs after a purchase. The card itself disappears once Pro is on, so Today owns what comes next.
    var onUnlocked: () -> Void
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var page: RecordPageModel?
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private static let pageHeight: CGFloat = 300
    private static let sharpPage: CGFloat = 104

    var body: some View {
        LockedPreview(
            size: .card,
            entry: .todayRecord,
            line: ProGate.lockLine(.todayRecord, confirmedHours: confirmedHours),
            keeps: ProGate.keepsLine(.todayRecord),
            surface: colors.backgroundSecondary,
            onUnlock: {
                ProPaywallPresenter.shared.present(entry: .todayRecord, confirmedHours: confirmedHours, onUnlocked: onUnlocked)
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "doc.richtext").font(.title3).foregroundStyle(colors.action)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "today.record.cardTitle", defaultValue: "Your \(String(year)) record", table: "Today"))
                            .font(.headline).foregroundStyle(colors.textPrimary)
                        Text(String(localized: "today.record.cardMeta", defaultValue: "PDF and spreadsheet · \(entryCount) entries", table: "Today"))
                            .font(.subheadline).foregroundStyle(colors.textSecondary)
                    }
                }
                pageView
                    .frame(height: Self.sharpPage, alignment: .top)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: LHMetrics.innerRadius, topTrailingRadius: LHMetrics.innerRadius, style: .continuous))
            }
            .padding([.horizontal, .top], LHMetrics.cardPadding)
        } locked: {
            pageView
                .offset(y: -Self.sharpPage)
                .frame(height: Self.pageHeight - Self.sharpPage, alignment: .top)
                .clipped()
                .padding(.horizontal, LHMetrics.cardPadding)
                .padding(.bottom, LHMetrics.cardPadding)
        }
        .background(RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous).fill(colors.backgroundSecondary))
        .overlay(RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous).strokeBorder(colors.pageCardEdge, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.yourRecord")
        .task { await load() }
    }

    private var entryCount: Int {
        viewModel.timeEntries.filter { Calendar.current.component(.year, from: $0.date) == year }.count
    }

    @ViewBuilder private var pageView: some View {
        Group {
            if let page {
                RecordPagePreview(model: page)
            } else {
                DraftingLoader(sketch: .document, surface: .adaptive, subject: "your record")
                    .padding(40)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Self.pageHeight, alignment: .top)
        .overlay(RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous).strokeBorder(colors.border, lineWidth: 0.5))
    }

    private func load() async {
        guard page == nil else { return }
        page = await RecordPageModel.load(entries: viewModel.timeEntries, properties: viewModel.properties,
                                          owner: viewModel.userName, year: year)
    }
}
