import SwiftUI

// MARK: - Today in the work pane (§1.27 "What sits where", DU4, DU5, DU13)
//
// Two-pane: an opaque card over the interior wall with "To confirm", the rental filter chip and the
// count set large, the rows, "N more at other rentals" at the foot; then "On the record today",
// filling the pane to the bar. Picking a rental on the shelf filters the list to that rental's items
// plus items with no rental yet; the foot (or clearing the chip) shows every rental again. A row's
// detail opens here with the back link "To confirm". Stacked: 1 row + "See all N" + On the record.
//
// The rows are the phone's `LHRow.Action` with Today's own title, meta and tag rules
// (`TodayConfirmBlock`), and every action is the Inbox model's own.

/// The filter (pure): the selected rental's items plus items with no rental yet; nil = all.
enum PaneConfirmFilter {
    static func items(_ visible: [Suggestion], rentalID: UUID?) -> [Suggestion] {
        let ranked = InboxLogic.ranked(visible)
        guard let rentalID else { return ranked }
        return ranked.filter { $0.proposedPropertyId == nil || $0.proposedPropertyId == rentalID }
    }

    static func hiddenCount(_ visible: [Suggestion], rentalID: UUID?) -> Int {
        visible.count - items(visible, rentalID: rentalID).count
    }
}

/// How much of Today's work pane sits above the bar at rest (pure; gate J r2). Every card is whole:
/// the bar never cuts a row, a foot or "On the record today" at rest.
///
/// `ends` are To confirm's measured bottoms in its own card: 0 the header, 1...n each row; `seeAll`
/// and `moreElsewhere` are the heights of the two feet. `record` is the height of "On the record
/// today" without "Earlier" (header and today's rows). `room` is how far the column may reach.
///   · Everything fits: every row, then the record (its "Earlier" rows fill what is left).
///   · A rental is picked (DU4 filtered): at least 3 rows (or all of them), "See all N" and the
///     record, if that fits.
///   · Otherwise, and on "All rentals" (DU4: rows run to the bar): as many whole rows as fit, with
///     "See all N"; the record follows only if it fits too.
///   · At AX a single row may be taller than the pane: then 1 row, and it scrolls.
enum PaneConfirmFit {
    struct Plan: Equatable {
        var rows: Int
        var showsRecord: Bool
    }

    static let top: CGFloat = 8
    static let gap: CGFloat = 10

    static func plan(ends: [Int: CGFloat], count n: Int, hidden: Int, seeAll: CGFloat?, moreElsewhere: CGFloat?,
                     record: CGFloat?, filtered: Bool, room: CGFloat) -> Plan {
        guard n > 0, let seeAll, let moreElsewhere, let record, room > 0,
              (0...n).allSatisfy({ ends[$0] != nil }) else { return Plan(rows: n, showsRecord: true) }
        func card(_ k: Int) -> CGFloat {
            let foot: CGFloat = k < n ? seeAll : (hidden > 0 ? moreElsewhere : 0)
            return top + (ends[k] ?? 0) + foot
        }
        func fits(_ k: Int, record withRecord: Bool) -> Bool {
            card(k) + (withRecord ? gap + record : 0) <= room
        }
        if fits(n, record: true) { return Plan(rows: n, showsRecord: true) }
        if filtered {
            for k in stride(from: n - 1, through: min(3, n), by: -1) where fits(k, record: true) {
                return Plan(rows: k, showsRecord: true)
            }
        }
        for k in stride(from: n, through: 1, by: -1) where fits(k, record: false) {
            // Room left under the rows for the record too (a short list on "All rentals").
            return Plan(rows: k, showsRecord: fits(k, record: true))
        }
        return Plan(rows: 1, showsRecord: false)
    }
}

/// The Today tab's root: the locked phone Today in compact, the work pane in two-pane and stacked.
struct AdaptiveToday: View {
    @ObservedObject var inbox: InboxViewModel
    @Environment(\.paneContext) private var paneContext

    var body: some View {
        switch paneContext {
        case .sheet: DashboardView(inbox: inbox)
        case .pane: TodayWorkPane(inbox: inbox)
        }
    }
}

struct TodayWorkPane: View {
    @ObservedObject var inbox: InboxViewModel

    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var selection: AdaptiveSelection
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutMode) private var mode
    @Environment(\.paneFoldInset) private var foldInset
    @Environment(\.paneGutter) private var gutter
    @Environment(\.paneWindowHeight) private var windowHeight
    @ObservedObject private var backfill = BackfillJob.shared
    @State private var confirming: Set<String> = []
    /// To confirm laid out off-screen at the card's width: 0 the header, 1...n each row's bottom,
    /// n + 1 and n + 2 the bottoms of the two feet below them (`PaneConfirmFit`).
    @State private var confirmMeasure = EarlierMeasure()
    /// "On the record today" without "Earlier", laid out off-screen (`PaneConfirmFit`).
    @State private var recordBase: CGFloat?
    /// The detail's confirm card at its content height (the scroll's content plus its pinned
    /// actions), so a tall pane never stretches it into an empty band above Log (D4, gate J r2).
    @State private var detailIdeal: CGFloat = 0
    @State private var detailRecordBase: CGFloat?
    @State private var captureOn = CaptureOptIn.calendarSuggestionsEnabled()
    @State private var showCaptureSetup = false

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var stacked: Bool { mode == .stacked }
    private var rentalID: UUID? { selection.selectedRentalID }
    private var rentalName: String? { rentalID.flatMap { id in viewModel.properties.first { $0.id == id }?.name } }

    var body: some View {
        // The detail pushes in place: the confirm view's own `dismiss()` (its close button, Log,
        // Not rental work) pops back to the list, as it closes its sheet on the phone.
        NavigationStack(path: detailPath) {
            list
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: String.self) { key in
                    if let suggestion = inbox.suggestions.first(where: { $0.sourceKey == key }) {
                        detail(suggestion).toolbar(.hidden, for: .navigationBar)
                    }
                }
        }
        .onChange(of: inbox.visible.map(\.sourceKey)) { _, keys in
            // The detail confirmed or dismissed its item: back to the list.
            if case .suggestion(let key) = selection.route, !keys.contains(key) { selection.close() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .captureSuggestionsDidChange)) { _ in
            captureOn = CaptureOptIn.calendarSuggestionsEnabled()
        }
        .sheet(isPresented: $showCaptureSetup, onDismiss: {
            captureOn = CaptureOptIn.calendarSuggestionsEnabled()
            inbox.reload()
        }) {
            CaptureSetupFlow(mode: .whatsNew, environment: .current, startAtBackfill: false) { _ in showCaptureSetup = false }
                .environmentObject(viewModel)
        }
        #if DEBUG
        .task {
            TodayDebugSeed.applyIfNeeded(app: viewModel)
            inbox.reload()
            AdaptiveDebug.applySelection(selection, app: viewModel)
        }
        #endif
        .accessibilityIdentifier("pane.today")
    }

    /// The pane's push path, derived from the selection's route.
    private var detailPath: Binding<[String]> {
        Binding(get: {
            if case .suggestion(let key) = selection.route { return [key] }
            return []
        }, set: { path in
            selection.route = path.last.map { .suggestion($0) }
        })
    }

    /// The pane's own wall (the tab content is opaque): the same light profile as the wall across
    /// the gap; when propped, the fold is the top edge (DU9, DU2).
    /// Air between the last row and the bar glass at rest (DU4).
    static let bottomMargin: CGFloat = 12

    private var paneWall: some View {
        InteriorWall(glowCenter: stacked ? UnitPoint(x: 0.5, y: 0) : UnitPoint(x: 0, y: 0.38),
                     foldInset: foldInset, foldAbove: stacked)
    }

    // MARK: List

    private var state: TodayConfirm.State {
        TodayConfirm.state(hasProperties: !viewModel.properties.isEmpty, pendingCount: inbox.badgeCount,
                           backfillScanning: backfill.isScanning, captureOn: captureOn)
    }

    private var list: some View {
        let visible = inbox.visible
        let items = PaneConfirmFilter.items(visible, rentalID: rentalID)
        let hidden = PaneConfirmFilter.hiddenCount(visible, rentalID: rentalID)
        let measureKey = EarlierMeasure.key(items.map(\.id), typeSize: typeSize) ^ hidden
        return GeometryReader { g in
            let room = PaneReach.room(visible: g.size.height, columnTop: g.frame(in: .global).minY, windowHeight: windowHeight)
            let plan: PaneConfirmFit.Plan = (stacked || state != .rows)
                ? PaneConfirmFit.Plan(rows: items.count, showsRecord: true)
                : PaneConfirmFit.plan(ends: confirmMeasure.key == measureKey ? confirmMeasure.ends : [:], count: items.count,
                                      hidden: hidden, seeAll: footHeight(confirmMeasure.key == measureKey, items.count, 1),
                                      moreElsewhere: footHeight(confirmMeasure.key == measureKey, items.count, 2),
                                      record: recordBase, filtered: rentalID != nil, room: room)
            ScrollView {
                // Every card sizes to its content (rows never compress to fit, D7) and sits whole
                // above the bar at rest (`PaneConfirmFit`): To confirm shows the rows that fit with
                // "See all N", then "On the record today" goes on with as many "Earlier" rows as fit,
                // so a tall pane fills with rows, not with an empty card or bare wall (§1.27, D4,
                // D6, DU4), and a short one never has a card under the bar.
                VStack(spacing: PaneConfirmFit.gap) {
                    if state == .rows {
                        confirmCard(items: items, hidden: hidden, total: visible.count, limit: plan.rows)
                    } else {
                        TodayConfirmBlock(inbox: inbox, state: state, isScanning: backfill.isScanning, limit: 0,
                                          onSeeAll: { NotificationCenter.default.post(name: .switchToTab, object: ShellTab.inboxIndex) },
                                          onTurnOn: { showCaptureSetup = true })
                    }
                    if plan.showsRecord {
                        OnTheRecordCard(rentalID: rentalID, fitHeight: room)
                    }
                }
                .background(alignment: .topLeading) {
                    // The off-screen measures the fit reads (never shown, never read aloud).
                    VStack(spacing: 0) {
                        if !stacked, state == .rows, !items.isEmpty {
                            confirmCard(items: items, hidden: hidden, total: visible.count, limit: nil, measureKey: measureKey)
                                .fixedSize(horizontal: false, vertical: true)
                                .coordinateSpace(.named(Self.confirmSpace))
                        }
                        OnTheRecordCard(rentalID: rentalID)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { recordBase = $0 }
                    }
                    .hidden()
                    .accessibilityHidden(true)
                }
                .padding(.horizontal, gutter)
                .padding(.top, PaneConfirmFit.top)
                .coordinateSpace(.named(OnTheRecordCard.space))
                .frame(maxWidth: PaneMetrics.contentCap)
                .frame(maxWidth: .infinity)
            }
            // The tab content's safe area already ends above the bar; 12 more keeps the last row
            // clear of the glass at rest (DU4).
            .contentMargins(.bottom, Self.bottomMargin, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
        .background { paneWall }
    }

    /// The off-screen To confirm's coordinate space.
    private static let confirmSpace = "pane.confirm.measure"

    /// A foot's measured height (`which` 1: "See all N", 2: "N more at other rentals").
    private func footHeight(_ current: Bool, _ n: Int, _ which: Int) -> CGFloat? {
        guard current, let rows = confirmMeasure.ends[n], let first = confirmMeasure.ends[n + 1] else { return nil }
        if which == 1 { return first - rows }
        guard let second = confirmMeasure.ends[n + 2] else { return nil }
        return second - first
    }

    /// `limit` caps the rows (nil = every row, the off-screen measure); with `measureKey` the card
    /// reports its parts' bottoms and carries both feet.
    private func confirmCard(items: [Suggestion], hidden: Int, total: Int, limit: Int?, measureKey: Int? = nil) -> some View {
        let measuring = measureKey != nil
        let cap = stacked ? 1 : (limit ?? items.count)
        let shown = Array(items.prefix(max(1, cap)))
        let remaining = items.count - confirming.count
        let report: (Int, CGFloat) -> Void = { index, end in confirmMeasure.record(key: measureKey ?? 0, index: index, end: end) }
        return PaneCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(TodayText.toConfirmTitle)
                        .font(.headline)
                        .foregroundStyle(colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    if let rentalName {
                        Button { selection.select(HouseShelf.allID) } label: {
                            HStack(spacing: 6) {
                                Text(rentalName).font(.subheadline.weight(.semibold))
                                Image(systemName: "xmark").font(.caption.weight(.bold))
                            }
                            .foregroundStyle(colors.action)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 32)
                            .background(colors.actionSurface, in: Capsule())
                        }
                        .buttonStyle(LHButton.press)
                        .hoverEffect(.highlight)
                        .accessibilityLabel(String(localized: "twoPane.list.filterA11y", defaultValue: "Showing \(rentalName). Show all rentals", table: "Adaptive"))
                        .accessibilityIdentifier("pane.filter")
                    }
                }
                Spacer(minLength: 8)
                Text(verbatim: "\(max(0, remaining))")
                    .font(LHFont.heroNumeral(size: typeSize.isAccessibilitySize ? 34 : 44))
                    .tracking(-1)
                    .foregroundStyle(colors.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(remaining)))
                    .accessibilityLabel(TodayText.toConfirm(remaining))
                    .accessibilityIdentifier("pane.count")
            }
            .padding(.horizontal, LHMetrics.cardPadding)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .modifier(MeasureEnd(index: 0, measuring: measuring, space: Self.confirmSpace, report: report))
            ForEach(Array(shown.enumerated()), id: \.element.sourceKey) { i, suggestion in
                VStack(spacing: 0) {
                    LHDivider(leadingInset: i == 0 ? 0 : LHRow.actionDividerInset)
                    row(suggestion)
                }
                .modifier(MeasureEnd(index: i + 1, measuring: measuring, space: Self.confirmSpace, report: report))
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
            if measuring {
                // Both feet, so the fit knows their heights whichever one it shows.
                seeAllFoot(items.count)
                    .modifier(MeasureEnd(index: shown.count + 1, measuring: true, space: Self.confirmSpace, report: report))
                moreElsewhereFoot(max(hidden, 1))
                    .modifier(MeasureEnd(index: shown.count + 2, measuring: true, space: Self.confirmSpace, report: report))
            } else if shown.count < items.count {
                seeAllFoot(items.count)
            } else if hidden > 0 {
                moreElsewhereFoot(hidden)
            }
        }
        .animation(reduceMotion ? AppAnimation.quick : AppAnimation.collapse, value: shown.map(\.sourceKey))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane.confirm")
    }

    /// "See all N": the rows that did not fit (or, stacked, all but the first) are in Inbox.
    private func seeAllFoot(_ count: Int) -> some View {
        VStack(spacing: 0) {
            LHDivider()
            Button(TodayText.seeAll(count)) {
                NotificationCenter.default.post(name: .switchToTab, object: ShellTab.inboxIndex)
            }
            .buttonStyle(LHButton.tertiary)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("pane.seeAll")
        }
    }

    /// "N more at other rentals": every row of the picked rental shows; the rest are elsewhere.
    private func moreElsewhereFoot(_ hidden: Int) -> some View {
        VStack(spacing: 0) {
            LHDivider()
            Button(String(localized: "twoPane.list.moreElsewhere", defaultValue: "\(hidden) more at other rentals", table: "Adaptive")) {
                selection.select(HouseShelf.allID)
            }
            .buttonStyle(LHButton.tertiary)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("pane.moreElsewhere")
        }
    }

    private func row(_ suggestion: Suggestion) -> some View {
        let badges = inbox.badges(for: suggestion)
        let quick = inbox.canQuickLog(suggestion)
        let hours = badges.needsHours ? nil : suggestion.proposedHours
        return LHRow.Action(
            title: TodayConfirmBlock.title(suggestion, propertyName: inbox.propertyName(for: suggestion)),
            sourceSymbol: InboxFormat.kindSymbol(suggestion.kind),
            meta: TodayConfirmBlock.meta(suggestion),
            tag: TodayConfirmBlock.tag(suggestion, badges: badges, colors: colors),
            hours: hours,
            control: confirming.contains(suggestion.sourceKey) ? .confirmed : .open,
            controlLabel: quick
                ? String(localized: "today.row.confirmHours", defaultValue: "Confirm \(InboxFormat.spokenHours(hours ?? 0))", table: "Today")
                : String(localized: "today.row.review", defaultValue: "Review and confirm", table: "Today"),
            onControl: { confirm(suggestion, quick: quick) },
            onOpen: { selection.open(.suggestion(suggestion.sourceKey)) },
            identifier: "pane.row.\(suggestion.sourceKey)"
        )
        .hoverEffect(.highlight)
        .accessibilityAction(named: String(localized: "today.row.notWork", defaultValue: "Not rental work", table: "Today")) {
            notWork(suggestion)
        }
        .contextMenu {
            if quick {
                Button { confirm(suggestion, quick: true) } label: {
                    Label(String(localized: "today.menu.confirm", defaultValue: "Confirm", table: "Today"), systemImage: "checkmark")
                }
            }
            Button { selection.open(.suggestion(suggestion.sourceKey)) } label: {
                Label(String(localized: "today.menu.open", defaultValue: "Open", table: "Today"), systemImage: "arrow.up.right")
            }
            Button { notWork(suggestion) } label: {
                Label(String(localized: "today.row.notWork", defaultValue: "Not rental work", table: "Today"), systemImage: "xmark")
            }
        }
    }

    // MARK: Detail, in the pane

    private func detail(_ suggestion: Suggestion) -> some View {
        let recordRental = suggestion.proposedPropertyId ?? rentalID
        return VStack(alignment: .leading, spacing: 0) {
            Button { selection.close() } label: {
                Label(String(localized: "twoPane.detail.back", defaultValue: "To confirm", table: "Adaptive"), systemImage: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(minHeight: LHMetrics.minTap)
            }
            .foregroundStyle(colors.action)
            .buttonStyle(LHButton.press)
            .keyboardShortcut(.cancelAction)
            .padding(.horizontal, gutter)
            .accessibilityIdentifier("pane.back")
            GeometryReader { g in
                let room = PaneReach.room(visible: g.size.height + PaneReach.air, columnTop: g.frame(in: .global).minY,
                                          windowHeight: windowHeight)
                // The card hugs its content, Log pinned right under it, never stretched into an
                // empty band (D4); a long item, or a keyboard, makes it scroll inside.
                let card = detailIdeal > 0 ? min(detailIdeal, room) : room
                let fitsRecord = detailIdeal > 0 && (detailRecordBase.map { room - card - PaneConfirmFit.gap >= $0 } ?? false)
                VStack(spacing: PaneConfirmFit.gap) {
                    SuggestionConfirmSheet(suggestion: suggestion, model: inbox)
                        .onScrollGeometryChange(for: CGFloat.self) { geometry in
                            (geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom).rounded(.up)
                        } action: { _, ideal in
                            detailIdeal = ideal
                        }
                        .clipShape(RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
                            .strokeBorder(colorScheme == .dark ? AppColors.duoNightCardEdge : colors.pageCardEdge, lineWidth: 1))
                        .frame(height: card)
                    // A tall pane goes on with what is already on the record at the item's rental
                    // (the "Might be logged" check, in place), as many whole rows as fit (DU4).
                    if fitsRecord {
                        OnTheRecordCard(rentalID: recordRental, fitHeight: room)
                            .transition(.opacity)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .coordinateSpace(.named(OnTheRecordCard.space))
                .background(alignment: .topLeading) {
                    OnTheRecordCard(rentalID: recordRental)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { detailRecordBase = $0 }
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, gutter)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: PaneMetrics.contentCap)
        .frame(maxWidth: .infinity)
        .background { paneWall }
        .accessibilityIdentifier("pane.detail")
    }

    // MARK: Actions

    private func confirm(_ suggestion: Suggestion, quick: Bool) {
        guard quick else {
            selection.open(.suggestion(suggestion.sourceKey))
            return
        }
        guard !confirming.contains(suggestion.sourceKey) else { return }
        confirming.insert(suggestion.sourceKey)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.12 + 0.25))
            if inbox.swipeLog(suggestion) == .logged {
                let hours = InboxFormat.hours(suggestion.proposedHours ?? 0)
                let message = inbox.propertyName(for: suggestion).map { TodayText.logged(hours, at: $0) } ?? TodayText.loggedPlain(hours)
                AppToastCenter.shared.show(message, kind: .success, undo: { inbox.undo() })
            }
            confirming.remove(suggestion.sourceKey)
        }
    }

    private func notWork(_ suggestion: Suggestion) {
        inbox.dismiss(suggestion)
        AppToastCenter.shared.show(TodayText.markedNotWork, kind: .neutral, undo: { inbox.undo() })
    }
}
