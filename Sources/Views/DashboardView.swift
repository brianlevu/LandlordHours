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
// Motion is the house's own (`timberDrop`, `windowsOn`, `stageFade`) and `rentalSlide`. Reveal on
// return (§B.3 `houseReveal`, Brian 2026-10-26): the hero draws what the user last SAW
// (`HouseSeenLedger`) until Today is visible — its tab selected, the app active, no sheet or cover
// over it — then plays ONE transition to the live state and stores that as seen. A save in Records,
// under the Log time sheet or on another device never plays out of sight.

/// The shell tells Today whether anything of its own covers the Today tab (another tab selected,
/// Reports or Settings in its place, the Log time sheet until it has finished dismissing, a shell
/// cover). Today adds its own sheets and the scene phase.
private struct TodayShellUncoveredKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var todayShellUncovered: Bool {
        get { self[TodayShellUncoveredKey.self] }
        set { self[TodayShellUncoveredKey.self] = newValue }
    }
}

struct DashboardView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var goalManager: GoalManager
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutBand) private var band
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.todayShellUncovered) private var shellUncovered
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
    /// Today's view is in the window (its tab is selected). `isVisible` adds the rest.
    @State private var onScreen = false
    /// What the hero draws: the last-seen state until a reveal plays, then the live one. It never
    /// follows the live data while Today is hidden. nil = the live state (first draw).
    @State private var shown: HeroSnapshot?
    /// The number while a reveal is in flight (the seen hours until the stage lands); nil = the
    /// hero's hours. Set in the same transaction as `shown`, so it never flashes the new value first.
    @State private var shownNumber: Double?
    /// A local sheet or cover has been told to close and has not finished dismissing.
    @State private var coverClosing = false
    @State private var revealTask: Task<Void, Never>?
    /// When the last rental slide started: a catch-up waits for the slide to land.
    @State private var slideStarted: Date?
    /// Bumped to remount the hero without motion (a page shown as it is, a DEBUG seed).
    @State private var heroMount = 0
    #if DEBUG
    @ObservedObject private var revealLog = HouseRevealDebugLog.shared
    #endif
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

        init(focus: String, stage: CraftStage, lit: Bool, hours: Double) {
            self.focus = focus
            self.stage = stage
            self.lit = lit
            self.hours = hours
        }

        init(_ seen: HouseSeenState, focus: String) {
            self.init(focus: focus, stage: seen.stage, lit: seen.lit, hours: seen.hours)
        }

        var seen: HouseSeenState { HouseSeenState(stage: stage, lit: lit, hours: hours) }
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

    /// What the hero draws: the last state shown (seen, or mid-reveal), else the live one.
    private var heroState: HeroSnapshot {
        shown ?? liveHeroState()
    }

    /// The number shown: the hero's hours, held at the seen value until a drop lands.
    private var shownHours: Double {
        shownNumber ?? heroState.hours
    }

    /// A sheet or cover of Today's own is up (or still closing).
    private var locallyCovered: Bool {
        showRecordExport || inbox.sheetSuggestion != nil || showCaptureSetup || showParticipationSheet
            || showLearningCenter || shownCelebration != nil || shownBackfill != nil || coverClosing
    }

    /// Today can be seen: its tab is selected with nothing over it, and the app is active.
    private var isVisible: Bool {
        onScreen && shellUncovered && scenePhase == .active && !locallyCovered
    }

    /// Local sheets that close through `onDismiss` (the navigation push has none).
    private var localSheetUp: Bool {
        showRecordExport || inbox.sheetSuggestion != nil || showCaptureSetup || showParticipationSheet
            || shownCelebration != nil || shownBackfill != nil
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
                        .frame(maxWidth: .infinity)   // band B: the scaffold's content column (§1.27 interim)
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
                    // Once per launch (`.task` runs on every appear): the seed replaced the data,
                    // so show it as it is, with no motion, and store it as seen.
                    if !Self.didAcceptSeed {
                        Self.didAcceptSeed = true
                        if let i = TodayDebugSeed.focusIndex, focuses.indices.contains(i) { focusID = focuses[i].id }
                        showLiveAsSeen()
                    }
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
            // Screen anatomy: Today has a title like every tab. The rental picker is the header's
            // accessory (under the title, or in the bar for Option 1); the account menu is its one action.
            .lhTabScreen(String(localized: "today.title", defaultValue: "Today", table: "Today"), onPage: true, accessory: {
                // The rental chip, with the page dots beside it (they left the house base, where they
                // overlapped the lot): one row that says which rental and where it sits in the swipe.
                HStack(spacing: 12) {
                    LHToastChipSlot { switcher }.dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    if focuses.count > 1 && !ax {
                        LHPageDots(count: focuses.count, current: focusIndex)
                            .accessibilityHidden(true)
                    }
                }
            }, trailing: {
                accountMenu
            })
            .sensoryFeedback(.selection, trigger: focusID)
            .onAppear(perform: appeared)
            .onDisappear { onScreen = false }
            .onChange(of: isVisible) { _, visible in if visible { becameVisible() } }
            .onChange(of: localSheetUp) { wasUp, isUp in
                // The sheet is closing: Today waits for `onDismiss` before it plays anything.
                guard wasUp, !isUp else { return }
                coverClosing = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.0))   // safety net if onDismiss never comes
                    coverClosing = false
                }
            }
            .onChange(of: dynamicTypeSize) { _, _ in resolveHeroSide() }
            .onChange(of: band) { _, _ in resolveHeroSide() }
            .onChange(of: focuses.map(\.id)) { _, _ in resolveFocus() }
            .onChange(of: liveHeroState()) { _, _ in
                // A change while Today is visible plays now; a hidden one waits for the return.
                if isVisible { reveal() }
            }
            .onChange(of: hoursPending) { wasPending, isPending in
                if wasPending, !isPending, isVisible { reveal() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .captureSuggestionsDidChange)) { _ in refreshCaptureState() }
            .onChange(of: hoursPending) { wasPending, isPending in
                guard wasPending, !isPending else { return }
                UIAccessibility.post(notification: .announcement, argument: pace.spoken)
            }
            #if DEBUG
            .overlay(alignment: .topLeading) { revealProbe }
            #endif
            .onChange(of: houseEvents.pendingConfirm) { _, confirm in
                // The hero builds from the live hours; consume the event so nothing replays later.
                guard confirm != nil, isVisible else { return }
                houseEvents.takeConfirm()
            }
            .onChange(of: houseEvents.celebrationTick) { _, _ in
                guard isVisible else { return }
                scheduleCelebration(after: shownNumber != nil ? Self.afterDrop : Self.afterSettle)
            }
            .onChange(of: houseEvents.pendingBackfill) { _, reveal in
                guard reveal != nil, isVisible else { return }
                presentBackfillIfNeeded()
            }
            .sheet(isPresented: $showRecordExport, onDismiss: coverDismissed) { ExportPDFView(year: currentYear) }
            .sheet(item: $inbox.sheetSuggestion, onDismiss: coverDismissed) { suggestion in
                SuggestionConfirmSheet(suggestion: suggestion, model: inbox)
            }
            .sheet(isPresented: $showCaptureSetup, onDismiss: {
                coverDismissed()
                refreshCaptureState()
                inbox.reload()
            }) {
                CaptureSetupFlow(mode: .whatsNew, environment: .current, startAtBackfill: false) { _ in
                    showCaptureSetup = false
                }
                .environmentObject(viewModel)
            }
            .sheet(isPresented: $showParticipationSheet, onDismiss: coverDismissed) {
                ParticipationConfirmationSheet(year: currentYear,
                                               currentAnswer: taxProfile.noOneParticipatedMore(forYear: currentYear)) { answer in
                    taxProfile.setNoOneParticipatedMore(answer, forYear: currentYear)
                }
            }
            .navigationDestination(isPresented: $showLearningCenter) { LearningCenterView() }
            .fullScreenCover(item: $shownCelebration, onDismiss: {
                coverDismissed()
                presentBackfillIfNeeded()
                presentNextCelebration()
            }) { item in
                MilestoneCelebrationView(celebration: item.celebration, hours: countedHours,
                                         windowsLit: TodayWindowState.loggedToday(entries: viewModel.timeEntries, now: InboxClock.now()),
                                         onContinue: { shownCelebration = nil })
            }
        }
        .fullScreenCover(item: $shownBackfill, onDismiss: {
            coverDismissed()
            presentNextCelebration()
        }) { reveal in
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
        VStack(spacing: 0) {
            heroColumn
            belowHero
        }
    }

    @ViewBuilder private var heroColumn: some View {
        hero
            .modifier(TodayToastRoom(enabled: !ax))
        TodayNumberBlock(hours: shownHours, goal: focus?.goal ?? houseGoal.targetHours, year: currentYear,
                         isRecord: isRecord, pace: pace, numeralSize: numeralSize, isPending: hoursPending,
                         onPaceTap: paceTap)
            .dynamicTypeSize(...DynamicTypeSize.accessibility5)
            .padding(.top, ax ? 0 : -56)   // the number sits in the diorama's shadow (H4)
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
        // Package K's notice slot (one card, under the hero): K decides when and what.
        if let notice = viewModel.todayNotice {
            TodayIdentityCard(notice: notice)
                .padding(.horizontal, LHMetrics.gutter)
                .padding(.top, 12)
                .transition(.opacity)
        }
        TodayTimerSlot()
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.top, 12)
        TodayConfirmBlock(inbox: inbox, state: confirmState, isScanning: backfill.isScanning, limit: rowLimit,
                          onSeeAll: { NotificationCenter.default.post(name: .switchToTab, object: ShellTab.inboxIndex) },
                          onTurnOn: { showCaptureSetup = true },
                          onLogged: rowLogged, onNotWork: { _ in
                              AppToastCenter.shared.show(TodayText.markedNotWork, kind: .neutral, undo: { inbox.undo() })
                          })
            .padding(.top, LHMetrics.sectionGap)
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
                .frame(maxWidth: max(160, min(window.width > 0 ? window.width : 402, 402) - 2 * (LHMetrics.gutter + LHMetrics.minTap)),
                       alignment: .leading)
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
        }
    }

    // MARK: Actions

    private func select(_ id: String) {
        guard id != focus?.id else { return }
        let pages = focuses
        let to = pages.firstIndex { $0.id == id } ?? 0
        slideEdge = to > focusIndex ? .trailing : .leading
        // The new page slides in as the user last saw it; if it changed since, its catch-up plays
        // once after the slide (`reveal`). A page with nothing new never replays its build.
        let start = pages.first(where: { $0.id == id }).map { page -> HeroSnapshot in
            let live = snapshot(page)
            return HeroSnapshot(revealCoordinator.startState(focus: page.id, current: live.seen, year: currentYear), focus: page.id)
        }
        slideStarted = Date()
        withAnimation(CraftHouseView.rentalSlideAnimation(reduceMotion: reduceMotion)) {
            focusID = id
            shown = start
            shownNumber = nil
        }
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
        // Screen anatomy: Today now carries the tab header (title row + rental chip), so H1 is taken
        // from the height under it; the rows and their foot stay above the bar (D3b).
        let underHeader = CGSize(width: window.width, height: max(0, window.height - (ax ? 0 : LHScreenAnatomy.heroHeaderAllowance)))
        heroSide = CraftHeroSide.resolve(previous: heroSide, kind: .hero, window: underHeader, band: band, accessibility: ax)
    }

    private func stageSettled(_ motion: CraftStageMotion) {
        if motion == .timberDrop, let focus {
            CraftDropLedger().markPlayed(rentalID: focus.rentalID, stage: .framing, year: currentYear)
        }
        // The number rolls as the stage lands (`heroCountUp`).
        shownNumber = nil
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
        refreshCaptureState()
        resolveFocus()
        onScreen = true   // `onChange(isVisible)` plays the reveal
    }

    /// Today just became visible: play the catch-up (if any), then any queued milestone.
    private func becameVisible() {
        houseEvents.takeConfirm()
        let plan = reveal()
        let delay: Double
        if let plan, plan.stageMotion == .timberDrop || plan.windowsChange {
            delay = plan.stageMotion == .timberDrop ? Self.afterDrop : Self.afterSettle
        } else if plan?.stageMotion == .stageFade {
            delay = Self.afterSettle
        } else {
            delay = Self.afterAppear
        }
        scheduleCelebration(after: delay)
    }

    private func coverDismissed() {
        coverClosing = false
    }

    private var revealCoordinator: HouseRevealCoordinator { HouseRevealCoordinator() }

    private func snapshot(_ focus: TodayFocus) -> HeroSnapshot {
        HeroSnapshot(focus: focus.id, stage: focus.stage, lit: lit(focus), hours: focus.hours)
    }

    private func liveHeroState() -> HeroSnapshot {
        guard let focus else { return HeroSnapshot(focus: "none", stage: .started, lit: false, hours: 0) }
        return snapshot(focus)
    }

    /// Reveal on return (§B.3 `houseReveal`): one transition from what the user last saw on this
    /// page to the live state, then the live state is stored as seen. Only while Today is visible.
    @discardableResult
    private func reveal() -> HouseRevealPlan? {
        guard isVisible, !hoursPending, let focus else { return nil }
        let live = snapshot(focus)
        let plan = revealCoordinator.reveal(focus: focus.id, current: live.seen, year: currentYear,
                                            dropAllowed: dropAllowed, reduceMotion: reduceMotion)
        revealTask?.cancel()
        guard let plan else {
            // Never seen this year, or nothing changed: show the page as it is, with no motion.
            if shown != live {
                if shown?.focus == live.focus { heroMount += 1 }
                shown = live
            }
            shownNumber = nil
            return nil
        }
        let base = HeroSnapshot(plan.from, focus: focus.id)
        var wait: Double = 0
        if shown != base {
            // The hero is not drawing the seen state (first draw, a relaunch): put it there first.
            if shown?.focus == base.focus || shown == nil { heroMount += 1 }
            shown = base
            wait = 0.08
        }
        if let slideStarted, Date().timeIntervalSince(slideStarted) < CraftMotion.rentalSlide { wait = max(wait, CraftMotion.rentalSlide + 0.05) }
        shownNumber = plan.from.hours
        #if DEBUG
        let label = "reveal:\(plan.stageMotion):\(Int(plan.from.hours))->\(Int(plan.to.hours))"
        #endif
        revealTask = Task { @MainActor in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            #if DEBUG
            HouseRevealDebugLog.shared.record(label)
            #endif
            shown = live
            // The number rolls now, or as the last timber lands (`stageSettled`).
            if !plan.holdsNumberUntilSettled { shownNumber = nil }
        }
        return plan
    }

    #if DEBUG
    @MainActor private static var didAcceptSeed = false

    /// `-LHRevealProbe`: the ordered reveal events, for UI tests (never drawn visibly).
    @ViewBuilder private var revealProbe: some View {
        if HouseRevealDebugLog.isEnabled {
            Text(revealLog.events.isEmpty ? "none" : revealLog.events.joined(separator: ","))
                .font(.caption2)
                .frame(width: 1, height: 1)
                .clipped()
                .opacity(0.02)
                .allowsHitTesting(false)
                .accessibilityIdentifier("today.revealProbe")
        }
    }
    #endif

    /// DEBUG seeds and data resets: show the live state as it is and store it as seen.
    private func showLiveAsSeen() {
        guard let focus else { return }
        let live = snapshot(focus)
        HouseSeenLedger().markSeen(live.seen, focus: focus.id, year: currentYear)
        heroMount += 1
        shown = live
        shownNumber = nil
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


/// While a top toast shows over the hero, the art steps down so the capsule never sits on the
/// chimney or the roof ridge (§6 of the gate rubric: a toast overlapping a roof is a FAIL). The
/// toast is taller than the chip it replaces; the extra height is made here, then given back.
/// At accessibility sizes the art already lays out below the chip row, so nothing moves.
private struct TodayToastRoom: ViewModifier {
    static var lift: CGFloat { 56 }
    let enabled: Bool
    @ObservedObject private var center = LHToastCenter.shared

    func body(content: Content) -> some View {
        let room: CGFloat = enabled && center.hidesHeroChip ? Self.lift : 0
        content
            .padding(.top, room)
            .lhMotion(AppAnimation.reveal, value: room)
    }
}
