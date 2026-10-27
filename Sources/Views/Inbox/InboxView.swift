import SwiftUI

// MARK: - The Inbox tab (standard §1.3, §1.15a, §1.18, §H.5; plan package D)
//
// Detected work waiting for a yes or no. Nothing here counts until confirmed.
//
//   - A plain-canvas list: the Fraunces tab title, then one inset-grouped "To confirm · N" card.
//     Inside it, a day header ("Today", "Yesterday", "Mon Oct 19") over that day's `LHRow.Action`
//     rows, newest day first. System swipes only (`.swipeActions`): leading confirms, trailing is
//     "Not rental work". The row tap opens the confirm sheet.
//   - "Confirm N likely" (N >= 2): a `.tertiary` at the card foot when the foot is on screen, a
//     pinned capsule above the tab bar when it is not (§1.3b). One action, one toast "Logged 3".
//   - The look-back: one grouped row above the card while it runs. Afterwards its items are plain
//     rows under their own day headers (a summary row cost a row of the five D3 asks for).
//   - Nothing waiting: the diorama of the first rental on the dusk/night page (§H.5, §1.18).
//
// The tab switch from Today (dusk page) to this plain canvas has no push, so the canvas dissolves in
// from the page tone when the user came from a hero screen (`InboxCanvas`).

struct InboxView: View {
    @ObservedObject var model: InboxViewModel
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSetup = false
    @State private var setupStartsAtBackfill = false
    @State private var logTick = 0
    @State private var dismissTick = 0
    /// Rows whose control has filled (`rowConfirm`), before the row leaves.
    @State private var confirming: Set<String> = []
    /// The card's foot ("Confirm N likely") is on screen: no pinned bar then.
    @State private var footVisible = true
    /// The background 90-day look-back (header + streaming rows).
    @ObservedObject private var backfill = BackfillJob.shared
    @ObservedObject private var toasts = LHToastCenter.shared
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        NavigationStack {
            Group {
                if BackfillJob.showsEmptyState(visibleIsEmpty: model.visible.isEmpty, phase: backfill.phase) {
                    emptyState
                } else {
                    list
                        .background { InboxCanvas() }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $model.sheetSuggestion) { suggestion in
            SuggestionConfirmSheet(suggestion: suggestion, model: model)
        }
        .proPaywall($model.paywallRequest)
        .sheet(isPresented: $showSetup, onDismiss: { model.reload() }) {
            CaptureSetupFlow(mode: .whatsNew, environment: .current, startAtBackfill: setupStartsAtBackfill) { _ in
                showSetup = false
            }
            .environmentObject(viewModel)
        }
        .sensoryFeedback(.success, trigger: logTick)
        .sensoryFeedback(.impact(weight: .light), trigger: dismissTick)
        .onAppear { model.reload() }
        #if DEBUG
        .task { await runDebugHooks() }
        #endif
        .onDisappear { model.dismissToast() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .captureSuggestionsDidChange)) { _ in
            // Streamed backfill items slide in softly.
            model.reload(animated: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox.screen")
    }

    // MARK: List

    private var batch: [Suggestion] { model.likelyToConfirm }
    private var showsBatch: Bool { batch.count >= InboxLogic.batchMinimum }

    /// The pinned bar's slot: 44 for the capsule and 12 above and below. A constant, so the list's
    /// frame never depends on whether the bar is showing (an inset that follows the bar's own
    /// visibility sent the first build into a 100% CPU loop).
    private static let batchSlot: CGFloat = LHMetrics.minTap + 24

    private var barShows: Bool { showsBatch && !footVisible && !typeSize.isAccessibilitySize }

    /// Room under the rows for whatever pins above the tab bar: the batch bar, or the undo toast
    /// the shell draws there. A real layout slot, so no row is ever painted under either.
    private var bottomSlot: CGFloat {
        let toast: CGFloat = toasts.current != nil && toasts.placement == .bottom ? (typeSize.isAccessibilitySize ? 136 : 76) : 0
        let bar: CGFloat = showsBatch && !typeSize.isAccessibilitySize ? Self.batchSlot : 0
        return max(toast, bar)
    }

    private var list: some View {
        VStack(spacing: 0) {
            listBody
            Color.clear
                .frame(height: bottomSlot)
                .overlay(alignment: .center) {
                    if barShows && toasts.current == nil {
                        InboxBatchBar(count: batch.count) { confirmLikely() }
                            .padding(.horizontal, LHMetrics.gutter)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? AppAnimation.quick : AppAnimation.reveal, value: barShows)
                .animation(reduceMotion ? AppAnimation.quick : AppAnimation.reveal, value: bottomSlot)
        }
    }

    private var listBody: some View {
        List {
            Section {
                LHScreenTitle(String(localized: "inbox.title", defaultValue: "Inbox", table: "Inbox"))
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if BackfillJob.showsHeader(backfill.phase) {
                    BackfillProgressHeader(job: backfill, found: model.backfillCount, onRetry: runBackfillAgain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .transition(.opacity)
                }
            }
            if model.visible.isEmpty {
                // A stopped or blocked look-back with nothing found: the header above has the
                // action, this says what the empty list means (no "To confirm · 0" over bare canvas).
                Section {
                    VStack(spacing: 4) {
                        Text(String(localized: "inbox.empty.headline", defaultValue: "Nothing waiting.", table: "Inbox"))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(String(localized: "inbox.empty.short", defaultValue: "Anything we find in your calendar will show up here. You can log time by hand any time.", table: "Inbox"))
                            .font(.body)
                            .foregroundStyle(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("inbox.empty.short")
                }
            } else {
            Section {
                ForEach(model.sections) { section in
                    dayHeader(section.day)
                    ForEach(Array(section.items.enumerated()), id: \.element.sourceKey) { index, suggestion in
                        row(suggestion, isLastOfDay: index == section.items.count - 1)
                    }
                }
                if showsBatch { batchFoot }
            } header: {
                LHSectionHeader(String(localized: "inbox.section.toConfirm", defaultValue: "To confirm", table: "Inbox"),
                                count: model.badgeCount)
                    .textCase(nil)
                    .padding(.top, 4)
                    .accessibilityIdentifier("inbox.section.count")
            }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(LHMetrics.sectionGap)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        // The 20pt list gutter (shared lane): the card, title and header rows sit on it.
        .contentMargins(.horizontal, LHMetrics.gutter, for: .scrollContent)
        .animation(reduceMotion ? AppAnimation.quick : AppAnimation.collapse, value: model.visible.map(\.sourceKey))
        .onScrollGeometryChange(for: Bool.self) { geometry in
            // The foot is the last row: it is on screen once the content's end is.
            geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 2
        } action: { _, atEnd in
            footVisible = atEnd
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox.list")
    }

    /// A day header inside the card (§1.15a): 28pt, 16 above and 6 below, aligned with the control.
    private func dayHeader(_ day: Date) -> some View {
        LHSectionHeader(InboxFormat.dayHeader(day, now: InboxClock.now()), style: .day)
            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(colors.backgroundSecondary)
            .listRowSeparator(.hidden)
    }

    private func row(_ suggestion: Suggestion, isLastOfDay: Bool) -> some View {
        let propertyName = model.propertyName(for: suggestion)
        let badges = model.badges(for: suggestion)
        let quick = model.canQuickLog(suggestion)
        let limit: InboxRowLimit = model.isWaitingOnPro(suggestion) ? .waiting : (model.needsNewRental(suggestion) ? .newPlace : .none)
        return SuggestionRowView(
            suggestion: suggestion,
            propertyName: propertyName,
            badges: badges,
            limit: limit,
            quick: quick,
            confirmed: confirming.contains(suggestion.sourceKey),
            now: InboxClock.now(),
            onControl: { confirm(suggestion, quick: quick) },
            onOpen: { model.sheetSuggestion = suggestion },
            onNotWork: { dismiss(suggestion) }
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(colors.backgroundSecondary)
        .listRowSeparator(isLastOfDay ? .hidden : .automatic, edges: .bottom)
        .alignmentGuide(.listRowSeparatorLeading) { _ in LHRow.actionDividerInset }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                swipeLog(suggestion)
            } label: {
                Label(quick ? String(localized: "inbox.swipe.confirm", defaultValue: "Confirm", table: "Inbox")
                            : String(localized: "inbox.swipe.review", defaultValue: "Review", table: "Inbox"),
                      systemImage: quick ? "checkmark" : "square.and.pencil")
                    .labelStyle(.iconOnly)
            }
            .tint(colors.positive)
            .accessibilityIdentifier("inbox.swipe.log")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                dismiss(suggestion)
            } label: {
                Label(String(localized: "inbox.row.notWork", defaultValue: "Not rental work", table: "Inbox"), systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .tint(colors.textSecondary)
            .accessibilityIdentifier("inbox.swipe.dismiss")
        }
        .contextMenu {
            if quick {
                Button { confirm(suggestion, quick: true) } label: {
                    Label(String(localized: "inbox.menu.confirm", defaultValue: "Confirm", table: "Inbox"), systemImage: "checkmark")
                }
            }
            Button { model.sheetSuggestion = suggestion } label: {
                Label(String(localized: "inbox.menu.open", defaultValue: "Open", table: "Inbox"), systemImage: "arrow.up.right")
            }
            Button { dismiss(suggestion) } label: {
                Label(String(localized: "inbox.row.notWork", defaultValue: "Not rental work", table: "Inbox"), systemImage: "xmark")
            }
        }
    }

    /// "Confirm N likely" at the card foot (§1.3 Batch).
    private var batchFoot: some View {
        Button(InboxText.confirmLikely(batch.count)) { confirmLikely() }
            .buttonStyle(LHButton.tertiary)
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(colors.backgroundSecondary)
            .accessibilityIdentifier("inbox.confirm.batch")
    }

    // MARK: Actions

    #if DEBUG
    /// Frame captures (see `InboxDebugSeed`): open a sheet or tap the batch without a finger.
    private func runDebugHooks() async {
        guard InboxDebugSeed.has("-LHInboxOpenSheet") || InboxDebugSeed.has("-LHInboxOpenSetup") || InboxDebugSeed.has("-LHInboxConfirmLikely") || InboxDebugSeed.has("-LHInboxRunBackfill") else { return }
        try? await Task.sleep(for: .seconds(1.5))
        if let key = InboxDebugSeed.value(after: "-LHInboxOpenSheet"),
           let match = model.visible.first(where: { $0.sourceKey.hasSuffix(key) }) {
            model.sheetSuggestion = match
        }
        if InboxDebugSeed.has("-LHInboxOpenSetup") {
            setupStartsAtBackfill = false
            showSetup = true
        }
        if InboxDebugSeed.has("-LHInboxConfirmLikely") { _ = model.confirmLikely() }
        if InboxDebugSeed.has("-LHInboxRunBackfill") {
            runBackfillAgain()
            if InboxDebugSeed.has("-LHInboxCancelBackfill") {
                try? await Task.sleep(for: .seconds(2))
                backfill.cancel()
            }
        }
    }
    #endif

    private var showsBackfillHeader: Bool { BackfillJob.showsHeader(backfill.phase) }

    /// Runs the look-back again in the background (after a stop, or when it never finished).
    private func runBackfillAgain() {
        guard let store = AppModelHost.shared.suggestionStore else { return }
        BackfillJob.shared.start(CaptureSetupEnvironment.current.makeScanner(viewModel, store))
    }

    /// The control: confirm at once when nothing needs a decision (`rowConfirm`: it fills, then the
    /// row leaves), else the sheet asks for what is missing.
    private func confirm(_ suggestion: Suggestion, quick: Bool) {
        guard quick else {
            model.sheetSuggestion = suggestion
            return
        }
        guard !confirming.contains(suggestion.sourceKey) else { return }
        confirming.insert(suggestion.sourceKey)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.1 : 0.12 + 0.25))
            swipeLog(suggestion)
            confirming.remove(suggestion.sourceKey)
        }
    }

    private func swipeLog(_ suggestion: Suggestion) {
        if model.swipeLog(suggestion) == .logged {
            logTick += 1
            UIAccessibility.post(notification: .announcement, argument: InboxText.loggedAnnouncement)
        }
    }

    private func confirmLikely() {
        if model.confirmLikely() > 0 {
            logTick += 1
            UIAccessibility.post(notification: .announcement, argument: InboxText.loggedAnnouncement)
        }
    }

    private func dismiss(_ suggestion: Suggestion) {
        model.dismiss(suggestion)
        dismissTick += 1
        UIAccessibility.post(notification: .announcement, argument: InboxText.notWorkAnnouncement)
    }

    // MARK: Empty

    /// The first rental's house as the empty state: its stage, lit when hours were logged today.
    private var emptyStage: CraftStage {
        guard let rental = viewModel.properties.first else { return .started }
        let year = Calendar.current.component(.year, from: InboxClock.now())
        let hours = viewModel.propertyCountableHours(rental.id, goal: viewModel.houseGoal, year: year)
        return CraftStage.stage(hours: hours, goal: viewModel.houseGoal.targetHours)
    }

    private var emptyLit: Bool {
        guard let rental = viewModel.properties.first else { return false }
        return TodayWindowState.loggedToday(entries: viewModel.timeEntries, rentalIDs: [rental.id], now: InboxClock.now())
    }

    private var emptyState: some View {
        let captureOn = viewModel.calendarSuggestionsEnabled
        let needsLookBack = captureOn && !CaptureOptIn.backfillCompleted()
        let actionID = !captureOn ? "inbox.empty.setup" : (needsLookBack ? "inbox.empty.backfill" : "inbox.empty.log")
        return InboxEmptyPage(
            banner: BackfillJob.showsHeader(backfill.phase)
                ? AnyView(BackfillProgressHeader(job: backfill, found: model.backfillCount, onRetry: runBackfillAgain))
                : nil,
            stage: emptyStage,
            windowsLit: emptyLit,
            headline: captureOn
                ? String(localized: "inbox.empty.headline", defaultValue: "Nothing waiting.", table: "Inbox")
                : String(localized: "inbox.empty.headlineOff", defaultValue: "Nothing here yet.", table: "Inbox"),
            message: captureOn && model.store != nil
                ? String(localized: "inbox.empty.body", defaultValue: "We’ll put work here when your calendar looks like rental work. Nothing counts until you say so.", table: "Inbox")
                : String(localized: "inbox.empty.bodyOff", defaultValue: "Turn on calendar suggestions and we’ll put likely rental work here for you to confirm.", table: "Inbox"),
            actionTitle: !captureOn
                ? String(localized: "inbox.empty.setup", defaultValue: "Find rental work in my calendar", table: "Inbox")
                : (needsLookBack
                   ? String(localized: "inbox.empty.backfill", defaultValue: "Look back 90 days", table: "Inbox")
                   : String(localized: "inbox.empty.log", defaultValue: "Log time", table: "Inbox")),
            actionIdentifier: actionID,
            action: {
                if !captureOn {
                    setupStartsAtBackfill = false
                    showSetup = true
                } else if needsLookBack {
                    runBackfillAgain()
                } else {
                    NotificationCenter.default.post(name: .switchToTab, object: ShellTab.logTimeIndex)
                }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox.empty")
    }
}

// MARK: - Strings

enum InboxText {
    static func confirmLikely(_ count: Int) -> String {
        String(localized: "inbox.batch.confirm", defaultValue: "Confirm \(count) likely", table: "Inbox",
               comment: "Logs every row that is sure and complete, e.g. Confirm 3 likely")
    }

    static var loggedAnnouncement: String {
        String(localized: "inbox.a11y.logged", defaultValue: "Logged. Undo is available.", table: "Inbox")
    }

    static var notWorkAnnouncement: String {
        String(localized: "inbox.a11y.notWork", defaultValue: "Marked not rental work. Undo is available.", table: "Inbox")
    }
}

// MARK: - Pinned batch bar (standard §1.3b)

/// "Confirm N likely" pinned 12pt above the tab bar when the card's foot is off screen. Capsule 44,
/// `.regularMaterial` with a hairline, `.subheadline.semibold` `action` ink. Not a row, not a
/// `.primary`: excluded from D1/D2/D3/D6 and D8.
struct InboxBatchBar: View {
    let count: Int
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        Button(action: action) {
            Text(InboxText.confirmLikely(count))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.action)
                .contentTransition(.numericText(value: Double(count)))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 20)
                .frame(minHeight: LHMetrics.minTap)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(colors.border, lineWidth: LHMetrics.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(LHButton.press)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("inbox.confirm.batchBar")
    }
}

// MARK: - The canvas, and the tab-switch seam

/// The Inbox's plain canvas. Today sits on the dusk page, so a tab switch from it to this canvas has
/// no push and the warm-to-cool cut shows in light mode (package C's capture, plan §5 Q4). When the
/// user comes from a hero screen the canvas dissolves in from the page tone over `reveal`
/// (fade only under Reduce Motion, the same dissolve). From any other tab, or in dark mode where
/// the tones match, it is just the canvas.
private struct InboxCanvas: View {
    @ObservedObject private var toasts = LHToastCenter.shared
    @State private var cameFromHero = false
    @State private var settled = false
    @State private var armed = false

    var body: some View {
        ZStack {
            if cameFromHero { LHPage() }
            LHCanvas().opacity(cameFromHero && !settled ? 0 : 1)
        }
        .onAppear {
            // A hero screen holds the top toast placement while it is on screen. A tab switch may run
            // this appear before that screen's disappear, so also watch the first moments.
            armed = true
            if toasts.placement == .top { startDissolve() }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.35))
                armed = false
            }
        }
        .onDisappear {
            cameFromHero = false
            settled = false
        }
        .onChange(of: toasts.placement) { old, new in
            // The hero screen released its claim just after this appeared: it was the one we came from.
            if armed, old == .top, new == .bottom, !cameFromHero { startDissolve() }
        }
    }

    private func startDissolve() {
        guard !cameFromHero else { return }
        cameFromHero = true
        settled = false
        withAnimation(AppAnimation.reveal.delay(0.05)) { settled = true }
    }
}

// MARK: - The Inbox's undo toast

/// "Logged 2h · Undo". Shown by the shell just above the tab bar (the toast cannot live inside the
/// Inbox's own safe area). It is the app's one toast (`LHToast`), fed from the Inbox model.
struct InboxUndoToast: View {
    let toast: InboxToast
    var onUndo: () -> Void

    var body: some View {
        LHToast(spec: toast.spec, onAction: onUndo, identifier: "inbox.toast", actionIdentifier: "inbox.undo")
    }
}

extension InboxToast {
    /// The one toast's spec for this Inbox toast (same id, so transitions key on it).
    var spec: LHToastSpec {
        let kind: LHToastSpec.Kind
        switch self.kind {
        case .success: kind = .success
        case .neutral: kind = .neutral
        case .problem: kind = .problem
        }
        return LHToastSpec(id: id, kind: kind, message: message,
                           actionTitle: undo == nil ? nil : String(localized: "inbox.toast.undo", defaultValue: "Undo", table: "Inbox"))
    }
}

// MARK: - Nothing waiting: the diorama on the page (standard §1.18, §H.5)

/// `LHEmptyState.Page`'s layout (the first rental's house ≤ 240pt and ≤ 28% of the viewport, one
/// headline, one line, one `.primary`) with an identifier on the button, which the page component
/// does not take yet (note for package A: add `actionIdentifier` there and drop this copy).
private struct InboxEmptyPage: View {
    /// A stopped or blocked look-back, shown above the house; the page keeps one headline, one line, one primary.
    var banner: AnyView? = nil
    let stage: CraftStage
    let windowsLit: Bool
    let headline: String
    let message: String
    let actionTitle: String
    let actionIdentifier: String
    let action: () -> Void

    /// The whole window (safe areas included), the figure the hero share is measured against.
    @State private var window: CGSize = .zero
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var ax: Bool { typeSize.isAccessibilitySize }

    /// The Inbox's empty state is a hero screen (§H.5): the same frame as Today's (capped at 36% of the
    /// window for the frame, so the art stays under 28%).
    private var side: CGFloat {
        guard window.width > 0 else { return CraftHeroSize.minimumDioramaSide }
        // Conductor ruling 2026-10-26: the Inbox house is capped (art <= 240pt and <= 28% of the
        // window, §H.5/§1.18); the 36-46% hero band is Today's. The art is ~0.65 of the frame.
        let capped = min(CraftHeroSize.hero(windowWidth: window.width, windowHeight: window.height, accessibility: ax),
                         window.height * 0.36)
        return max(CraftHeroSize.minimumDioramaSide, capped)
    }

    /// With the look-back banner above the house the copy can run long, so the button scrolls with it
    /// instead of pinning over the last line.
    private var inFlowButton: Bool { ax || banner != nil }

    private var button: some View {
        Button(actionTitle, action: action)
            .buttonStyle(LHButton.primary)
            .accessibilityIdentifier(actionIdentifier)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                LHScreenTitle(String(localized: "inbox.title", defaultValue: "Inbox", table: "Inbox"))
                    .padding(.top, 8)
                if let banner { banner }
                // The frame can be wider than the 20pt gutters allow; it is an overlay so it never
                // widens the column the title and button size themselves from.
                Color.clear
                    .frame(height: side)
                    .overlay {
                        CraftHouseView(stage: stage, windowsLit: windowsLit, side: side, fillsStage: !ax)
                            .frame(width: side, height: side)
                            .clipped()
                    }
                    // The frame has dead margin under the lot; the headline tucks into it.
                    .padding(.bottom, -side * 0.12)
                Text(headline)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                // Accessibility sizes: the button is as tall as the copy, so it scrolls with it
                // instead of pinning over it.
                if inFlowButton { button.padding(.top, 8) }
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            if !inFlowButton {
                button
                    .padding(.horizontal, LHMetrics.gutter)
                    .padding(.bottom, 16)
            }
        }
        .background { LHPage() }
        .background {
            Color.clear.ignoresSafeArea()
                .onGeometryChange(for: CGSize.self) { proxy in
                    CGSize(width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                           height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
                } action: { window = $0 }
        }
    }
}
