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
    @ObservedObject private var backfill = BackfillJob.shared
    @State private var confirming: Set<String> = []
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
        return GeometryReader { g in
            ScrollView {
                VStack(spacing: 10) {
                    if state == .rows {
                        confirmCard(items: items, hidden: hidden, total: visible.count)
                    } else {
                        TodayConfirmBlock(inbox: inbox, state: state, isScanning: backfill.isScanning, limit: 0,
                                          onSeeAll: { NotificationCenter.default.post(name: .switchToTab, object: ShellTab.inboxIndex) },
                                          onTurnOn: { showCaptureSetup = true })
                    }
                    // "On the record today" fills the pane to the bar (§1.27), so a tall iPad pane
                    // never shows a band of bare wall under the cards (DU4).
                    OnTheRecordCard(rentalID: rentalID, fills: true)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .frame(maxWidth: PaneMetrics.contentCap)
                .frame(maxWidth: .infinity)
                .frame(minHeight: max(0, g.size.height - 20), alignment: .top)
            }
            // The tab content's safe area already ends above the bar; 12 more keeps the last row
            // clear of the glass at rest (DU4).
            .contentMargins(.bottom, 12, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
        .background { paneWall }
    }

    private func confirmCard(items: [Suggestion], hidden: Int, total: Int) -> some View {
        let shown = stacked ? Array(items.prefix(1)) : items
        let remaining = items.count - confirming.count
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
            ForEach(shown, id: \.sourceKey) { suggestion in
                LHDivider(leadingInset: suggestion.sourceKey == shown.first?.sourceKey ? 0 : LHRow.actionDividerInset)
                row(suggestion)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
            if stacked, items.count > 1 {
                LHDivider()
                Button(TodayText.seeAll(items.count)) {
                    NotificationCenter.default.post(name: .switchToTab, object: ShellTab.inboxIndex)
                }
                .buttonStyle(LHButton.tertiary)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("pane.seeAll")
            } else if hidden > 0 {
                LHDivider()
                Button(String(localized: "twoPane.list.moreElsewhere", defaultValue: "\(hidden) more at other rentals", table: "Adaptive")) {
                    selection.select(HouseShelf.allID)
                }
                .buttonStyle(LHButton.tertiary)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("pane.moreElsewhere")
            }
        }
        .animation(reduceMotion ? AppAnimation.quick : AppAnimation.collapse, value: shown.map(\.sourceKey))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane.confirm")
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
        VStack(alignment: .leading, spacing: 0) {
            Button { selection.close() } label: {
                Label(String(localized: "twoPane.detail.back", defaultValue: "To confirm", table: "Adaptive"), systemImage: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(minHeight: LHMetrics.minTap)
            }
            .foregroundStyle(colors.action)
            .buttonStyle(LHButton.press)
            .keyboardShortcut(.cancelAction)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("pane.back")
            SuggestionConfirmSheet(suggestion: suggestion, model: inbox)
                .clipShape(RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
                    .strokeBorder(colorScheme == .dark ? AppColors.duoNightCardEdge : colors.pageCardEdge, lineWidth: 1))
                .padding(.horizontal, 16)
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
