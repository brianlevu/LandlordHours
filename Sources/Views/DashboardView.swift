import SwiftUI

/// WP-L: what Today says while things are still arriving. Loading (the first iCloud pull) never
/// reads as a brand-new user, and a running 90-day look-back gets its own state instead of
/// "Log your first hour".
enum TodayPresentation {
    enum Mode: Equatable {
        case loading, lookingBack, newUser, normal

        var showsActivationCard: Bool { self == .newUser }

        /// nil: the caller's own copy (new-user setup titles or the live hours).
        var title: String? {
            switch self {
            case .loading: return "Today’s work"
            case .lookingBack: return "Looking through your calendar"
            case .newUser, .normal: return nil
            }
        }

        var subtitle: String? {
            switch self {
            case .loading: return "Bringing in your latest hours from iCloud."
            case .lookingBack: return "Rental work we find goes to your Inbox. Nothing counts until you confirm it."
            case .newUser, .normal: return nil
            }
        }

        var compactTitle: String? {
            switch self {
            case .loading: return "Getting your hours"
            case .lookingBack: return "Looking through your calendar"
            case .newUser, .normal: return nil
            }
        }

        /// nil for `.normal`: the live pace line.
        var compactSubtitle: String? {
            switch self {
            case .loading: return "Bringing in your latest hours"
            case .lookingBack: return "Suggestions go to your Inbox"
            case .newUser, .normal: return nil
            }
        }
    }

    static func mode(hoursPending: Bool, backfillScanning: Bool, hasProperties: Bool, hasEntries: Bool) -> Mode {
        if hoursPending { return .loading }
        guard hasProperties && hasEntries else { return backfillScanning ? .lookingBack : .newUser }
        return .normal
    }
}

// MARK: - Today (standard §H.8; plan package C)
//
// The crafted house on the dusk/night page: rental chip (Menu) in the toast's slot · the hero
// (`CraftHouseView`, H1–H3, H10 "All rentals") with page dots and a swipe · the Fraunces number ·
// "of 100 hours" · the pace sentence · "To confirm · N" with ≤ 2 `LHRow.Action` rows and a
// "See all N" foot. Pace tiles and "This week" left Today (rental page, Reports).
//
// Motion is the house's own (`timberDrop`, `windowsOn`, `stageFade`) and `rentalSlide`, bound to
// the live hours while Today is visible. While Today is off screen the hero is frozen, and on
// return it remounts at the new state with no motion (§H.6 "never on appear").

struct DashboardView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var goalManager: GoalManager
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutBand) private var band
    /// The Inbox's model (shell-owned): Today's To confirm reads and writes the same list, so the
    /// count here, the Inbox and its tab badge are one number.
    @ObservedObject var inbox: InboxViewModel
    @ObservedObject private var taxProfile = TaxProfileManager.shared
    @ObservedObject private var houseEvents = TodayHouseEvents.shared
    @ObservedObject private var backfill = BackfillJob.shared

    /// The selected page, remembered per scene (§1.27 scenes).
    @SceneStorage("today.focus") private var rememberedFocus = ""
    @State private var focusID: String?
    @State private var slideEdge: Edge = .trailing
    @State private var window: CGSize = .zero
    @State private var heroSide: CraftHeroSide?
    @State private var isVisible = false
    /// The hero as it was when Today left the screen; nil while Today is visible.
    @State private var frozen: HeroSnapshot?
    /// Bumped to remount the hero without motion (return to Today, a DEBUG seed).
    @State private var heroMount = 0
    /// The hours the number last landed on, per page. While a timber drop is pending from these
    /// hours to the live ones, the number shows these, then rolls as the last timber lands
    /// (`heroCountUp`). Derived in `shownHours`, so the number never flashes the new value first
    /// (r2 showed 46 → 48 → 46 for eight frames when the hold was set in `onChange`).
    @State private var settledHours: (focus: String, hours: Double)?
    @State private var calendarSuggestionsOn = CaptureOptIn.calendarSuggestionsEnabled()
    @State private var showParticipationSheet = false
    @State private var showRecordExport = false
    @State private var showCaptureSetup = false
    @State private var showLearningCenter = ProcessInfo.processInfo.arguments.contains("-LHOpenLearningCenter")
    @State private var shownCelebration: TodayCelebration?
    @State private var shownBackfill: HouseBackfillReveal?
    @ScaledMetric(relativeTo: .largeTitle) private var scaledNumeral: CGFloat = 84

    private struct HeroSnapshot: Equatable {
        let focus: String
        let stage: CraftStage
        let lit: Bool
        let hours: Double
    }

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var ax: Bool { dynamicTypeSize.isAccessibilitySize }
    private var houseGoal: HouseGoal { goalManager.houseGoal }
    private var isRecord: Bool { goalManager.goalChoice == .record }
    private var hoursPending: Bool { viewModel.isAwaitingInitialPull }

    // MARK: Figures

    private var focuses: [TodayFocus] {
        let rentals = viewModel.properties.map {
            TodayFocusList.Rental(id: $0.id, name: $0.name,
                                  hours: viewModel.propertyCountableHours($0.id, goal: houseGoal, year: currentYear))
        }
        return TodayFocusList.make(rentals: rentals, goal: houseGoal.targetHours, allRentalsName: TodayText.allRentals)
    }

    private var focus: TodayFocus? {
        let all = focuses
        return all.first { $0.id == focusID } ?? all.first
    }

    private var focusIndex: Int { focuses.firstIndex { $0.id == focus?.id } ?? 0 }

    private func lit(_ focus: TodayFocus) -> Bool {
        TodayWindowState.loggedToday(entries: viewModel.timeEntries, rentalIDs: focus.rentalIDs, now: InboxClock.now())
    }

    /// What the hero draws: the live state, or the frozen one while Today is off screen.
    private var heroState: HeroSnapshot {
        frozen ?? liveHeroState()
    }

    /// The number shown: held at the pre-save value through a drop.
    private var shownHours: Double {
        let live = heroState.hours
        if let settled = settledHours, settled.focus == heroState.focus, dropPending(from: settled.hours, to: live) {
            return settled.hours
        }
        return live
    }

    /// A save on the shown page that will play the timber drop (the same test `CraftHouseView` makes).
    private func dropPending(from old: Double, to new: Double) -> Bool {
        guard isVisible, frozen == nil, new > old, let focus, dropAllowed, !reduceMotion,
              CraftHouseView.buildClipURL(dark: colorScheme == .dark) != nil else { return false }
        return CraftMotion.stageMotion(from: CraftStage.stage(hours: old, goal: focus.goal),
                                       to: CraftStage.stage(hours: new, goal: focus.goal)) == .timberDrop
    }

    private func settleNumber() {
        settledHours = focus.map { ($0.id, $0.hours) }
    }

    private var side: CGFloat {
        heroSide?.side ?? CraftHeroSize.hero(windowWidth: max(window.width, 402), windowHeight: max(window.height, 874), accessibility: ax)
    }

    private var numeralSize: CGFloat {
        let cap = CraftHeroSize.numeralCap(windowHeight: window.height > 0 ? window.height : 874, accessibility: ax) ?? 84
        return min(scaledNumeral, cap)
    }

    private var rowLimit: Int { TodayConfirm.rowLimit(windowHeight: window.height, typeSize: dynamicTypeSize) }

    private var daysOfData: Int {
        let calendar = Calendar.current
        guard let first = viewModel.timeEntries.filter({ calendar.component(.year, from: $0.date) == currentYear }).map(\.date).min() else { return 0 }
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: InboxClock.now())).day ?? 0)
    }

    /// The 1.x hero words, per page: they carry the goal-reached caveats (the 750's half rule, the
    /// 100-hour "did anyone do more?").
    private func heroCopy(_ focus: TodayFocus) -> TodayHeroCopy {
        TodayHeroCopy.make(.init(
            goal: houseGoal, isRecord: isRecord, hours: focus.hours, year: currentYear, now: InboxClock.now(),
            repsParticipant: goalManager.repsParticipant,
            halfTest: viewModel.repsStatus(participant: goalManager.repsParticipant, year: currentYear).moreThanHalfStatus,
            noOneParticipatedMore: taxProfile.noOneParticipatedMore(forYear: currentYear),
            propertyName: nil, daysOfData: daysOfData, hasPendingToConfirm: inbox.badgeCount > 0))
    }

    private var pace: TodayPaceSentence {
        if hoursPending {
            return TodayPaceSentence(lead: nil, rest: String(localized: "today.pace.loading", defaultValue: "Bringing in your latest hours from iCloud.", table: "Today"), tone: .neutral)
        }
        guard let focus else {
            return TodayPaceSentence(lead: nil, rest: TodayHeroCopy.emptyLotLine(target: isRecord ? nil : Int(houseGoal.targetHours)), tone: .neutral)
        }
        let copy = heroCopy(focus)
        let caveat = (focus.hours >= focus.goal && !copy.claimsReached) ? Self.reachedCaveat(copy, hours: focus.hours, goal: focus.goal) : nil
        return TodayPaceSentence.make(.init(
            hours: shownHours, goal: focus.goal, year: currentYear, now: InboxClock.now(), isRecord: isRecord,
            paceReady: TodayHeroCopy.paceIsReady(hours: focus.hours, daysOfData: daysOfData),
            hasPendingToConfirm: inbox.badgeCount > 0, reachedCaveat: caveat))
    }

    /// What is still open once the hours reach the goal, in Today's words: the 100-hour question
    /// (the pace line opens it), the "more than" line at exactly the goal, else the hero copy's status.
    static func reachedCaveat(_ copy: TodayHeroCopy, hours: Double, goal: Double) -> String? {
        if copy.needsConfirmation {
            return String(localized: "today.pace.askNoOneMore", defaultValue: "Did anyone do more? Tap to answer.", table: "Today")
        }
        if hours <= goal {
            return String(localized: "today.pace.moreThan", defaultValue: "The test needs more than \(Int(goal.rounded())) hours.", table: "Today")
        }
        // The hero copy may already start with "750 reached." (the half rule); the lead says it once.
        guard var status = copy.status else { return nil }
        let lead = "\(Int(goal.rounded())) reached."
        if status.hasPrefix(lead) { status = String(status.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces) }
        return status.isEmpty ? nil : status
    }

    private var paceTap: (() -> Void)? {
        guard let focus, !hoursPending, heroCopy(focus).needsConfirmation else { return nil }
        return { showParticipationSheet = true }
    }

    private var confirmState: TodayConfirm.State {
        TodayConfirm.state(hasProperties: !viewModel.properties.isEmpty, pendingCount: inbox.badgeCount,
                           backfillScanning: backfill.isScanning, captureOn: calendarSuggestionsOn)
    }

    private var countedHours: Double { viewModel.houseCountableHours(goal: houseGoal, year: currentYear) }

    private var showsRecordSlot: Bool {
        !hoursPending && !viewModel.timeEntries.isEmpty
            && TodayRecordSlot.isShown(isPro: subscriptionManager.isPro, confirmedHours: countedHours)
    }

    private var dropAllowed: Bool {
        guard let focus else { return false }
        return !CraftDropLedger().hasPlayed(rentalID: focus.rentalID, stage: .framing, year: currentYear)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    page
                        .frame(maxWidth: band == .a ? .infinity : (band == .c ? 960 : LHMetrics.readingColumn))
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                #if DEBUG
                .task {
                    TodayDebugSeed.applyIfNeeded(app: viewModel)
                    inbox.reload()
                    refreshCaptureState()
                    resolveFocus()
                    if let i = TodayDebugSeed.focusIndex, focuses.indices.contains(i) { focusID = focuses[i].id }
                    heroMount += 1   // the seed replaced the data: remount, no motion
                    settleNumber()
                    if let focus { TodayDebugSeed.scheduleLog(app: viewModel, rentalID: focus.rentalID, rentalName: focus.name) }
                    TodayDebugSeed.runTabTour()
                    guard TodayDebugSeed.scrollsToEnd else { return }
                    try? await Task.sleep(for: .seconds(1.2))
                    withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("today.end", anchor: .bottom) }
                }
                #endif
            }
            .background { LHPage() }
            .background {
                // The window size (H1 uses the whole window, safe areas included).
                Color.clear
                    .onGeometryChange(for: CGSize.self) { proxy in
                        CGSize(width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                               height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
                    } action: { size in
                        window = size
                        resolveHeroSide()
                    }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sensoryFeedback(.selection, trigger: focusID)
            .onAppear(perform: appeared)
            .onDisappear(perform: disappeared)
            .onChange(of: dynamicTypeSize) { _, _ in resolveHeroSide() }
            .onChange(of: band) { _, _ in resolveHeroSide() }
            .onChange(of: focuses.map(\.id)) { _, _ in resolveFocus() }
            .onChange(of: focus?.hours) { old, new in hoursChanged(from: old, to: new) }
            .onReceive(NotificationCenter.default.publisher(for: .captureSuggestionsDidChange)) { _ in refreshCaptureState() }
            .onChange(of: hoursPending) { wasPending, isPending in
                guard wasPending, !isPending else { return }
                UIAccessibility.post(notification: .announcement, argument: pace.spoken)
            }
            .onChange(of: houseEvents.pendingConfirm) { _, confirm in
                // The hero builds from the live hours; consume the event so nothing replays later.
                guard confirm != nil, isVisible else { return }
                houseEvents.takeConfirm()
            }
            .onChange(of: houseEvents.celebrationTick) { _, _ in
                guard isVisible else { return }
                scheduleCelebration(after: shownHours != heroState.hours ? Self.afterDrop : Self.afterSettle)
            }
            .onChange(of: houseEvents.pendingBackfill) { _, reveal in
                guard reveal != nil, isVisible else { return }
                presentBackfillIfNeeded()
            }
            .sheet(isPresented: $showRecordExport) { ExportPDFView(year: currentYear) }
            .sheet(item: $inbox.sheetSuggestion) { suggestion in
                SuggestionConfirmSheet(suggestion: suggestion, model: inbox)
            }
            .sheet(isPresented: $showCaptureSetup, onDismiss: {
                refreshCaptureState()
                inbox.reload()
            }) {
                CaptureSetupFlow(mode: .whatsNew, environment: .current, startAtBackfill: false) { _ in
                    showCaptureSetup = false
                }
                .environmentObject(viewModel)
            }
            .sheet(isPresented: $showParticipationSheet) {
                ParticipationConfirmationSheet(year: currentYear,
                                               currentAnswer: taxProfile.noOneParticipatedMore(forYear: currentYear)) { answer in
                    taxProfile.setNoOneParticipatedMore(answer, forYear: currentYear)
                }
            }
            .navigationDestination(isPresented: $showLearningCenter) { LearningCenterView() }
            .fullScreenCover(item: $shownCelebration, onDismiss: {
                presentBackfillIfNeeded()
                presentNextCelebration()
            }) { item in
                MilestoneCelebrationView(celebration: item.celebration, hours: countedHours,
                                         windowsLit: TodayWindowState.loggedToday(entries: viewModel.timeEntries, now: InboxClock.now()),
                                         onContinue: { shownCelebration = nil })
            }
        }
        .fullScreenCover(item: $shownBackfill, onDismiss: { presentNextCelebration() }) { reveal in
            BackfillRevealView(
                foundHours: reveal.foundHours,
                suggestionCount: reveal.suggestionCount,
                confirmedHours: countedHours,
                onReview: {
                    shownBackfill = nil
                    NotificationCenter.default.post(name: .switchToTab, object: ShellTab.inboxIndex)
                },
                onSkip: { shownBackfill = nil }
            )
        }
    }

    // MARK: Layout

    @ViewBuilder private var page: some View {
        if band == .c {
            // H6 band C: the hero and the number on the left, To confirm on the right.
            HStack(alignment: .top, spacing: LHMetrics.sectionGap) {
                VStack(spacing: 0) { heroColumn }
                    .frame(maxWidth: .infinity)
                VStack(spacing: 0) { belowHero }
                    .frame(maxWidth: 420)
                    .padding(.top, 64)
            }
            .padding(.horizontal, LHMetrics.wideGutter)
        } else {
            VStack(spacing: 0) {
                heroColumn
                belowHero
            }
        }
    }

    @ViewBuilder private var heroColumn: some View {
        if ax { chipRow }
        hero
            .padding(.top, ax ? 0 : 10)   // headroom so the chip clears the roof ridge at "finished"
            .overlay(alignment: .top) { if !ax { chipRow.padding(.top, 4) } }
        TodayNumberBlock(hours: shownHours, goal: focus?.goal ?? houseGoal.targetHours, year: currentYear,
                         isRecord: isRecord, pace: pace, numeralSize: numeralSize, isPending: hoursPending,
                         onPaceTap: paceTap)
            .dynamicTypeSize(...DynamicTypeSize.accessibility5)
            .padding(.top, ax ? 0 : -44)   // the number sits in the diorama's shadow (H4)
        if viewModel.properties.isEmpty {
            Button(String(localized: "today.addRental", defaultValue: "Add a rental", table: "Today")) {
                NotificationCenter.default.post(name: .switchToPropertiesAndOpenAddProperty, object: nil)
            }
            .buttonStyle(LHButton.primary)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.top, LHMetrics.sectionGap)
            .accessibilityIdentifier("today.addRental")
        }
    }

    @ViewBuilder private var belowHero: some View {
        TodayTimerSlot()
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.top, 12)
        TodayConfirmBlock(inbox: inbox, state: confirmState, isScanning: backfill.isScanning, limit: rowLimit,
                          onSeeAll: { NotificationCenter.default.post(name: .switchToTab, object: ShellTab.inboxIndex) },
                          onTurnOn: { showCaptureSetup = true },
                          onLogged: rowLogged, onNotWork: { _ in
                              AppToastCenter.shared.show(TodayText.markedNotWork, kind: .neutral, undo: { inbox.undo() })
                          })
            .padding(.top, ax ? 12 : 8)
            .padding(.horizontal, LHMetrics.gutter)
        if showsRecordSlot {
            TodayRecordSlot(year: currentYear, confirmedHours: countedHours) { showRecordExport = true }
                .padding(.horizontal, LHMetrics.gutter)
                .padding(.top, LHMetrics.sectionGap)
                .id("today.section.record")
        }
        Color.clear.frame(height: 1).id("today.end")
    }

    // MARK: Chip

    /// The rental chip (a `Menu`), with the account menu at the trailing edge. The top toast
    /// replaces the row while it shows (`LHToastChipSlot`, §H.8).
    private var chipRow: some View {
        LHToastChipSlot {
            ZStack {
                switcher
                HStack {
                    Spacer()
                    accountMenu
                }
                .padding(.horizontal, LHMetrics.gutter)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    @ViewBuilder private var switcher: some View {
        if let focus {
            let pages = focuses
            Menu {
                Picker(String(localized: "today.chip.picker", defaultValue: "Rental", table: "Today"),
                       selection: Binding(get: { focus.id }, set: { select($0) })) {
                    ForEach(pages) { page in Text(page.name).tag(page.id) }
                }
            } label: {
                // The whole name when it fits beside the account button; a long name drops whole
                // words, never breaks inside one ("Santa Ray…" at AX3 and "Schoolhous…" were FAILs, §H.8).
                ViewThatFits(in: .horizontal) {
                    ForEach(TodayChipName.candidates(focus.name), id: \.self) { name in
                        LHHeroChip(name, showsChevron: pages.count > 1)
                    }
                }
                .frame(maxWidth: max(160, min(window.width > 0 ? window.width : 402, 402) - 2 * (LHMetrics.gutter + LHMetrics.minTap)))
                .contentTransition(.opacity)
            }
            .disabled(pages.count < 2)
            .accessibilityLabel(String(localized: "today.chip.label", defaultValue: "Rental: \(focus.name)", table: "Today"))
            .accessibilityHint(pages.count > 1 ? String(localized: "today.chip.hint", defaultValue: "Switches the rental", table: "Today") : "")
            .accessibilityIdentifier("today.chip")
        }
    }

    /// Reports and Settings open in the Today tab (`TodayRoute`), so Today keeps one quiet way in.
    private var accountMenu: some View {
        Menu {
            Button {
                NotificationCenter.default.post(name: .switchToTab, object: ShellTab.reportsIndex)
            } label: {
                Label(String(localized: "today.account.reports", defaultValue: "Reports", table: "Today"), systemImage: "chart.bar")
            }
            Button {
                NotificationCenter.default.post(name: .switchToTab, object: ShellTab.settingsIndex)
            } label: {
                Label(String(localized: "today.account.settings", defaultValue: "Settings", table: "Today"), systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(colors.textSecondary)
                .frame(width: 36, height: 36)
                .background(colors.heroChipFill, in: Circle())
                .overlay(Circle().strokeBorder(colors.heroChipHairline, lineWidth: 0.5))
                .frame(width: LHMetrics.minTap, height: LHMetrics.minTap)
                .contentShape(Circle())
        }
        .accessibilityLabel(String(localized: "today.account.label", defaultValue: "Reports and settings", table: "Today"))
        .accessibilityIdentifier("today.account")
    }

    // MARK: Hero

    private var hero: some View {
        let state = heroState
        let pages = focuses
        return VStack(spacing: 0) {
            ZStack {
                CraftHouseView(
                    stage: state.stage,
                    windowsLit: state.lit,
                    side: side,
                    fillsStage: !ax,
                    dropAllowed: dropAllowed,
                    onStageSettled: stageSettled,
                    onSwipe: pages.count > 1 ? { step($0) } : nil
                )
                .id("\(state.focus)#\(heroMount)")
                .transition(CraftHouseView.rentalSlide(edge: slideEdge, reduceMotion: reduceMotion))
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityIdentifier("today.hero")
            if pages.count > 1 && !ax {
                LHPageDots(count: pages.count, current: focusIndex)
                    .padding(.top, -48)
            }
        }
    }

    // MARK: Actions

    private func select(_ id: String) {
        guard id != focus?.id else { return }
        let pages = focuses
        let to = pages.firstIndex { $0.id == id } ?? 0
        slideEdge = to > focusIndex ? .trailing : .leading
        if let page = pages.first(where: { $0.id == id }) { settledHours = (page.id, page.hours) }
        withAnimation(CraftHouseView.rentalSlideAnimation(reduceMotion: reduceMotion)) { focusID = id }
        rememberedFocus = id
    }

    private func step(_ delta: Int) {
        guard let next = TodayFocusList.step(focuses, from: focus?.id, by: delta) else { return }
        let pages = focuses
        let from = focusIndex
        let to = pages.firstIndex { $0.id == next } ?? 0
        select(next)
        // A wrap-around swipe still slides the way the finger went.
        if (delta > 0 && to < from) || (delta < 0 && to > from) { slideEdge = delta > 0 ? .trailing : .leading }
    }

    private func resolveFocus() {
        let pages = focuses
        if let focusID, pages.contains(where: { $0.id == focusID }) { return }
        focusID = TodayFocusList.initialFocusID(pages, remembered: rememberedFocus.isEmpty ? nil : rememberedFocus,
                                                countedRental: viewModel.todayFocusProperty(year: currentYear)?.id)
    }

    private func resolveHeroSide() {
        guard window.width > 0, window.height > 0 else { return }
        heroSide = CraftHeroSide.resolve(previous: heroSide, kind: .hero, window: window, band: band, accessibility: ax)
    }

    /// Hours on the shown page changed. Unless the change plays the timber drop (the number then
    /// waits in `shownHours` for the last timber), the number lands on the new hours now.
    private func hoursChanged(from old: Double?, to new: Double?) {
        guard let focus, let new else { return }
        if settledHours?.focus == focus.id, let settled = settledHours?.hours, dropPending(from: settled, to: new) { return }
        settledHours = (focus.id, new)
    }

    private func stageSettled(_ motion: CraftStageMotion) {
        if motion == .timberDrop, let focus {
            CraftDropLedger().markPlayed(rentalID: focus.rentalID, stage: .framing, year: currentYear)
        }
        settleNumber()
    }

    private func rowLogged(_ suggestion: Suggestion) {
        let hours = InboxFormat.hours(suggestion.proposedHours ?? 0)
        let message = inbox.propertyName(for: suggestion).map { TodayText.logged(hours, at: $0) } ?? TodayText.loggedPlain(hours)
        AppToastCenter.shared.show(message, kind: .success, undo: { inbox.undo() })
    }

    private func refreshCaptureState() {
        calendarSuggestionsOn = CaptureOptIn.calendarSuggestionsEnabled()
    }

    private func appeared() {
        isVisible = true
        refreshCaptureState()
        resolveFocus()
        if let frozen, frozen != liveHeroState() {
            // Saved while away: show the new state at once, with no motion (§H.6).
            heroMount += 1
        }
        frozen = nil
        settleNumber()
        houseEvents.takeConfirm()
        scheduleCelebration(after: Self.afterAppear)
    }

    private func disappeared() {
        frozen = heroState
        isVisible = false
    }

    private func liveHeroState() -> HeroSnapshot {
        guard let focus else { return HeroSnapshot(focus: "none", stage: .started, lit: false, hours: 0) }
        return HeroSnapshot(focus: focus.id, stage: focus.stage, lit: lit(focus), hours: focus.hours)
    }

    // MARK: Celebrations and the Day-1 reveal

    /// After Today appears, the milestone waits a beat so the eye is on the house.
    private static let afterAppear: Double = 0.45
    /// After a stage fade and the windows (0.25 + 0.30 + 0.40).
    private static let afterSettle: Double = 1.0
    /// After the drop (0.20 + 2.0 + 0.30) and the windows (0.40).
    private static let afterDrop: Double = 3.0

    private func scheduleCelebration(after delay: Double) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(reduceMotion ? min(delay, 0.3) : delay))
            presentBackfillIfNeeded()
            presentNextCelebration()
        }
    }

    /// Presents the highest queued milestone once. The ledger marks it (and any lower one it
    /// replaces) celebrated at presentation, so it never repeats.
    private func presentNextCelebration() {
        guard isVisible, shownCelebration == nil, shownBackfill == nil,
              let next = houseEvents.nextCelebration else { return }
        houseEvents.markPresented(next.celebration, year: next.year)
        shownCelebration = TodayCelebration(celebration: next.celebration, year: next.year)
    }

    /// The Day-1 reveal, once per profile; never over onboarding or What's new.
    private func presentBackfillIfNeeded() {
        guard isVisible, shownCelebration == nil, shownBackfill == nil, !OnbBackfill.flowActive,
              let reveal = houseEvents.pendingBackfill else { return }
        houseEvents.markBackfillShown()
        shownBackfill = reveal
    }
}

/// A milestone Today is presenting (the celebration and the tax year it belongs to).
struct TodayCelebration: Identifiable, Equatable {
    let celebration: HouseCelebration
    let year: Int
    var id: String { HouseCelebrationLedger.token(celebration, year: year) }
}

#Preview {
    DashboardView(inbox: InboxViewModel(app: nil, storeProvider: { nil }))
        .environmentObject(AppViewModel())
        .environmentObject(GoalManager.shared)
}
