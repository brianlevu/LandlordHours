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

struct DashboardView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var goalManager: GoalManager
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    /// The Inbox's model (shell-owned): Today's To confirm reads and writes the same list, so the
    /// count here, the Inbox and its tab badge are one number.
    @ObservedObject var inbox: InboxViewModel
    /// The "did anyone else do more?" answer lives here; the hero's words follow it.
    @ObservedObject private var taxProfile = TaxProfileManager.shared

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    /// The real estate professional's own count: yours, or your spouse's when they answered that
    /// their spouse is the pro.
    private var repsStatus: TaxQualificationEngine.REPSResult {
        viewModel.repsStatus(participant: goalManager.repsParticipant, year: currentYear)
    }

    // MARK: House inputs
    // The hero counts the goal's countable hours only (TodayHouse.swift): REPS = your own
    // real-estate hours; MP = owner (+ spouse when tracked jointly). Investor-only tasks never count.
    private var houseGoal: HouseGoal { goalManager.houseGoal }
    private var totalHours: Double { viewModel.houseCountableHours(goal: houseGoal, year: currentYear) }
    private var targetHours: Double { houseGoal.targetHours }
    /// The pace follows the hero: the focused rental's own target, or the goal's total.
    private var pace: TodayPace { TodayPace.resolve(hours: heroState.hours, goal: heroState.goal) }

    // MARK: Focus (2.1): one value feeds the hero, the flag, the subtitle, the pace and the widget

    /// Keeps Today in step with the focus the owner picks (and the plan answers).
    @ObservedObject private var planStore = RentalPlanStore.shared
    @State private var homeSelection = HomeSelection()
    @State private var showRentalGrid = false
    @State private var rentalRowScrollRequest: String?
    @State private var didApplyHomeLaunch = false

    /// Every rental (and "All rentals" when the goal is one shared total or a record), with its
    /// own hours and plan.
    private var homeRentals: HomeRentals {
        let ctx = viewModel.rentalPlanContext
        return HomeRentals.make(
            properties: viewModel.properties, mode: RentalPlanning.mode(ctx), plans: RentalPlanning.plans(ctx),
            hours: { viewModel.rentalHours($0, year: currentYear) }, totalHours: totalHours)
    }

    /// Two or more rentals: the row under the hero. One rental: 2.0.1's Today.
    private var showsRentalRow: Bool { viewModel.properties.count >= 2 }

    private var todayFocus: TodayFocusChoice {
        _ = planStore.focusToken
        return viewModel.resolvedTodayFocus(year: currentYear)
    }

    /// The hero for the focus (or the rentals added up).
    private var heroState: HomeHeroState {
        HomeHero.make(homeRentals, focus: todayFocus, summed: homeSelection.sumIds, .init(
            year: currentYear,
            now: InboxClock.now(),
            daysOfData: daysOfData,
            hasPendingToConfirm: inbox.badgeCount > 0 || foundInInbox.count > 0,
            answer: { id in taxProfile.noOneParticipatedMore(forYear: currentYear, propertyId: id) },
            totalCopy: totalHeroCopy,
            totalHours: totalHours,
            totalGoal: houseGoal,
            totalFlag: showsRentalRow ? HomeRentals.allRentalsName : (isNewOwner ? viewModel.properties.first?.name : nil)))
    }

    /// The hero's words for the focus.
    private var heroCopy: TodayHeroCopy { heroState.copy }

    /// A pre-save total (a confirm build waiting to play) only applies when the hero shows that total.
    private var heroOverrideApplies: Bool { heroState.isTotal || abs(heroState.hours - totalHours) < 0.001 }

    /// The goal's total hero: target, whose count, and where you stand against Dec 31 (2.0.1).
    private var totalHeroCopy: TodayHeroCopy {
        TodayHeroCopy.make(.init(
            goal: houseGoal,
            isRecord: goalManager.goalChoice == .record,
            hours: totalHours,
            year: currentYear,
            now: InboxClock.now(),
            repsParticipant: goalManager.repsParticipant,
            halfTest: repsStatus.moreThanHalfStatus,
            noOneParticipatedMore: taxProfile.noOneParticipatedMore(forYear: currentYear),
            propertyName: nil,
            daysOfData: daysOfData,
            hasPendingToConfirm: inbox.badgeCount > 0 || foundInInbox.count > 0))
    }

    /// Days since the first hour logged this year (the pace waits for two weeks or ten hours).
    private var daysOfData: Int {
        let calendar = Calendar.current
        let year = currentYear
        guard let first = viewModel.timeEntries.filter({ calendar.component(.year, from: $0.date) == year }).map(\.date).min() else { return 0 }
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: InboxClock.now())).day ?? 0)
    }

    /// The rental Today names in the eyebrow, the house flag and the subtitle: always the focus
    /// (never simply the first rental added). nil on "All rentals" with several rentals.
    private var todayFocusName: String? {
        if viewModel.properties.count == 1 { return viewModel.properties[0].name }
        return heroState.isTotal ? nil : heroState.flag
    }
    @State private var showParticipationSheet = false

    /// What the hero draws: the live hours, or the pre-save hours while a confirm build waits to play.
    private var heroProgress: HouseProgress {
        HouseProgress(hours: (heroOverrideApplies ? heroHoursOverride : nil) ?? heroState.hours, goal: heroState.goal)
    }

    /// The house the hero draws, from the same stage function as the tiles. nil: the number's hours.
    private var heroStageHours: Double? {
        switch heroState.kind {
        case .total: return nil
        case .ownTarget:
            let target = heroState.copy.targetHours ?? 500
            return RentalStage.hours(track: .ownTarget(hours: target), hours: heroProgress.hours)
        default: return heroState.stageHours
        }
    }

    /// WP-L: the first iCloud pull of this launch hasn't landed, so the hours may not be final.
    /// Only the hours wait (placeholder bar + drafting loader); the rest of Today is usable.
    private var hoursPending: Bool { viewModel.isAwaitingInitialPull }

    private var isREPS: Bool { goalManager.globalGoalType == .reps || goalManager.globalGoalType == .both }

    // 50% rule compliance: ratio of RE hours to total working hours (incl. non-RE employment)
    private var fiftyPercentCompliance: Double {
        min(repsStatus.realEstateWorkPercentage, 1.0)
    }

    /// The 50% rule can't be checked until other work hours are entered (same rule as the export).
    private var otherWorkHoursMissing: Bool {
        isREPS && repsStatus.moreThanHalfStatus == .notEntered
    }

    private var fiftyPercentValue: String {
        otherWorkHoursMissing ? TaxQualificationEngine.MoreThanHalfStatus.notEnteredValue : "\(Int(fiftyPercentCompliance * 100))%"
    }

    private var fiftyPercentDetail: String? {
        switch repsStatus.moreThanHalfStatus {
        case .notEntered: return TaxQualificationEngine.MoreThanHalfStatus.notEnteredPrompt
        case .notMet: return "Not met yet: under half your work hours"
        case .met: return nil
        }
    }

    // Pace calculations
    private var daysLeftInYear: Int {
        let cal = Calendar.current
        guard let endOfYear = cal.date(from: DateComponents(year: currentYear, month: 12, day: 31)) else { return 0 }
        let remaining = cal.dateComponents([.day], from: Date(), to: endOfYear).day ?? 0
        return max(remaining, 1)
    }

    @State private var showRecordExport = false
    // The header line follows the hero: it keeps the pre-save total until the count-up lands.
    @State private var subtitleHoursOverride: Double?
    private var headerHours: Double { (heroOverrideApplies ? subtitleHoursOverride : nil) ?? totalHours }
    @State private var showLearningCenter = Self.shouldOpenLearningCenterFromLaunchArguments
    @State private var showHistory = false
    @State private var scrollOffset: CGFloat = 0

    // House: confirm build, milestone celebrations, Day-1 backfill reveal.
    @ObservedObject private var houseEvents = TodayHouseEvents.shared
    @State private var heroHoursOverride: Double?
    @State private var shownCelebration: TodayCelebration?
    @State private var shownBackfill: HouseBackfillReveal?
    @State private var isVisible = false

    private static var shouldOpenLearningCenterFromLaunchArguments: Bool {
        ProcessInfo.processInfo.arguments.contains("-LHOpenLearningCenter")
    }

    @ObservedObject private var backfill = BackfillJob.shared
    /// Backfill items in the Inbox (the same count as its tab badge), for the look-back card.
    private var inboxBackfillCount: Int { inbox.backfillCount }
    @State private var showCaptureSetup = false

    // MARK: Below the house

    /// To confirm. A new owner who said "Not now" to the calendar already has "Find hours in my
    /// calendar" under the hero, so the block stays out of the way until they turn it on.
    private var confirmState: TodayConfirm.State {
        if isNewOwner && !calendarSuggestionsOn && inbox.badgeCount == 0 { return .hidden }
        return TodayConfirm.state(
            hasProperties: !viewModel.properties.isEmpty,
            pendingCount: inbox.badgeCount,
            backfillScanning: backfill.isScanning,
            captureOn: calendarSuggestionsOn
        )
    }

    /// This week's countable hours, Monday first, with the house's spouse rule.
    private var weekDays: [TodayWeekDay] {
        TodayWeek.days(entries: viewModel.timeEntries, goal: houseGoal,
                       includeSpouse: viewModel.tracksSpouseJointly,
                       repsParticipant: goalManager.repsParticipant, now: InboxClock.now())
    }

    private var showsRecordSlot: Bool {
        !hoursPending && !viewModel.timeEntries.isEmpty
            && TodayRecordSlot.isShown(isPro: subscriptionManager.isPro, confirmedHours: totalHours)
    }

    private var mode: TodayPresentation.Mode {
        TodayPresentation.mode(
            hoursPending: hoursPending,
            backfillScanning: backfill.isScanning,
            hasProperties: !viewModel.properties.isEmpty,
            hasEntries: !viewModel.timeEntries.isEmpty
        )
    }

    // MARK: New-owner landing (2.0 onboarding hands off here)

    /// Calendar suggestions found by the look-back, still waiting in the Inbox (the Inbox's own
    /// items; countable hours only).
    @State private var foundInInbox: OnbFound = .none
    @State private var calendarSuggestionsOn = CaptureOptIn.calendarSuggestionsEnabled()
    @State private var isAskingCalendar = false

    private var isNewOwner: Bool { viewModel.timeEntries.isEmpty }

    private var heroFooter: HouseHeroFooter? {
        guard isNewOwner else { return nil }
        if viewModel.properties.isEmpty { return .emptyLot(onAddProperty: { openAddPropertyFromHome() }) }
        // While the look-back runs, WP-L's "Looking through your calendar" words lead instead.
        if !backfill.isScanning, foundInInbox.count > 0, foundInInbox.hasDisplayableHours { return .found(hoursText: foundInInbox.hoursText) }
        return nil
    }

    /// The flag on the lot: with several rentals it always names the focus; with one, only until
    /// the first hour is logged (2.0.1).
    private var heroStakeName: String? {
        if showsRentalRow { return heroState.flag }
        guard isNewOwner else { return nil }
        return todayFocusName
    }

    private func refreshNewOwnerState() {
        calendarSuggestionsOn = CaptureOptIn.calendarSuggestionsEnabled()
        foundInInbox = OnbFound.from(AppModelHost.shared.suggestionStore?.suggestions ?? [], now: InboxClock.now())
    }

    /// "Find hours in my calendar": the same ask as onboarding's calendar step, for people who
    /// said "Not now". The system prompt only when iOS has never asked; after a no, Settings.
    private var findHoursCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image("bp_tool_repairs_36")
                .resizable().scaledToFit()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Find hours in my calendar")
                    .font(.headline)
                    .foregroundStyle(colors.textPrimary)
                Text("We can look back 90 days for things like a plumber visit or a showing. You confirm each one.")
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Look at my calendar") { Task { await lookAtCalendar() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.action)
                    .frame(minHeight: 44)
                    .disabled(isAskingCalendar)
                    .accessibilityIdentifier("today-find-hours")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func lookAtCalendar() async {
        isAskingCalendar = true
        defer { isAskingCalendar = false }
        let environment = CaptureSetupEnvironment.current
        let access = await environment.requestCalendar()
        guard access == .fullAccess else {
            // iOS answers at once (no prompt) after an earlier no: the switch is in Settings.
            if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
            return
        }
        CaptureOptIn.setCalendarSuggestionsEnabled(true)
        Analytics.onboarding(.calendarResult(.allowed))
        if let store = AppModelHost.shared.suggestionStore {
            BackfillJob.shared.start(environment.makeScanner(viewModel, store))
        }
        refreshNewOwnerState()
    }

    /// The empty lot carries its own "Add property"; the setup card follows the first property.
    private var shouldShowActivationCard: Bool { mode.showsActivationCard && !viewModel.properties.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                LHMobileCanvas()

                ScrollViewReader { scroller in
                ScrollView(showsIndicators: false) {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: DashboardScrollOffsetPreferenceKey.self,
                                value: proxy.frame(in: .named("dashboardScroll")).minY
                            )
                    }
                    .frame(height: 0)

                    VStack(spacing: 22) {
                        headerSection
                        // The house leads Today in every state (approved r6 concept); a new
                        // owner's setup steps sit right under the empty lot.
                        houseHero
                        if showsRentalRow {
                            rentalRow
                                .id("today.section.rentals")
                        }
                        if isNewOwner && !calendarSuggestionsOn {
                            findHoursCard
                        }
                        // Below the house (redesign-specs §2): timer/draft slot → To confirm →
                        // This week → pace cards → Your record (free only).
                        VStack(alignment: .leading, spacing: 32) {
                            TodayTimerSlot()
                                .id("today.section.draft")
                            if mode == .lookingBack && viewModel.properties.isEmpty {
                                // No property yet: the To confirm block is hidden, so WP-L's
                                // look-back card says the scan is running.
                                BackfillProgressHeader(job: backfill, found: inboxBackfillCount, onRetry: {}, onOpen: {
                                    NotificationCenter.default.post(name: .switchToTab, object: ShellTab.inboxIndex)
                                })
                                .accessibilityAddTraits(.isButton)
                                .accessibilityHint("Opens your Inbox")
                                .accessibilityIdentifier("today.lookingBack")
                            }
                            TodayConfirmSection(
                                inbox: inbox,
                                state: confirmState,
                                isScanning: backfill.isScanning,
                                onSeeAll: { NotificationCenter.default.post(name: .switchToTab, object: ShellTab.inboxIndex) },
                                onTurnOn: { showCaptureSetup = true }
                            )
                            .id("today.section.confirm")
                            if shouldShowActivationCard {
                                homeActivationCard
                                    .id("today.section.setup")
                            }
                            if !viewModel.properties.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    TodayWeekSection(days: weekDays) { _ in
                                        NotificationCenter.default.post(name: .switchToTab, object: ShellTab.recordsIndex)
                                    }
                                    paceCards
                                }
                                .id("today.section.week")
                            }
                            if showsRecordSlot {
                                TodayRecordSlot(year: currentYear, confirmedHours: totalHours) { showRecordExport = true }
                                    .id("today.section.record")
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, AppSpacing.tabContentBottomInset)
                    // WP-L: the hours settle in with a crossfade when the first pull lands.
                    .lhMotion(AppAnimation.standard, value: hoursPending)
                }
                .coordinateSpace(name: "dashboardScroll")
                #if DEBUG
                .task {
                    TodayDebugSeed.applyIfNeeded(app: viewModel)
                    applyHomeLaunchIfNeeded()
                    inbox.reload()
                    refreshNewOwnerState()
                    guard let target = TodayDebugSeed.scrollTarget else { return }
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    scroller.scrollTo("today.section.\(target)", anchor: target == "week" ? .top : .center)
                }
                #endif
                }
                .onPreferenceChange(DashboardScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
                // The hero never scrolls under the status bar (the sandbox's top edge).
                .overlay(alignment: .top) { TodayTopEdgeFade() }
                .overlay(alignment: .top) {
                    if isCompactHeaderVisible {
                        compactDashboardBar
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showRecordExport) {
                ExportPDFView(year: currentYear)
            }
            // Tapping a To confirm row (or a confirm that needs a decision) opens the Inbox's own
            // confirm sheet, on the Inbox's own model.
            .sheet(item: $inbox.sheetSuggestion) { suggestion in
                SuggestionConfirmSheet(suggestion: suggestion, model: inbox)
            }
            .sheet(isPresented: $showCaptureSetup, onDismiss: {
                refreshNewOwnerState()
                inbox.reload()
            }) {
                CaptureSetupFlow(mode: .whatsNew, environment: .current, startAtBackfill: false) { _ in
                    showCaptureSetup = false
                }
                .environmentObject(viewModel)
            }
            .navigationDestination(isPresented: $showLearningCenter) {
                LearningCenterView()
            }
            .navigationDestination(isPresented: $showHistory) {
                HistoryView()
            }
            .onAppear {
                refreshNewOwnerState()
                isVisible = true
                // A save while Today was away (log via +, timer stop, inbox confirm): mount the
                // house at the pre-save height, then build up to the new one once it is on screen.
                if let confirm = houseEvents.pendingConfirm {
                    heroHoursOverride = confirm.oldHours
                    subtitleHoursOverride = confirm.oldHours
                }
                // Today renders its real content at once (records are local), so there is no
                // loading skeleton; the build starts once the card has been seen.
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmStartDelay) {
                    playPendingHouseWork()
                }
            }
            .onDisappear { isVisible = false }
            .onReceive(NotificationCenter.default.publisher(for: .captureSuggestionsDidChange)) { _ in
                refreshNewOwnerState()
            }
            // VoiceOver: say once when the hours finish loading (the loader itself stays quiet).
            .onChange(of: hoursPending) { wasPending, isPending in
                guard wasPending, !isPending else { return }
                UIAccessibility.post(notification: .announcement,
                                     argument: "Hours up to date. \(Int(totalHours.rounded(.down))) of \(Int(targetHours)) hours.")
            }
            // Live: a save while Today is on screen. The hero builds from the live hours change
            // itself; consume the event so it does not replay on the next appear.
            .onChange(of: houseEvents.pendingConfirm) { _, confirm in
                guard confirm != nil, isVisible, heroHoursOverride == nil else { return }
                houseEvents.takeConfirm()
            }
            .onChange(of: houseEvents.celebrationTick) { _, _ in
                guard isVisible else { return }
                schedulePendingCelebration()
            }
            .onChange(of: houseEvents.pendingBackfill) { _, reveal in
                guard reveal != nil, isVisible else { return }
                presentBackfillIfNeeded()
            }
            .fullScreenCover(item: $shownCelebration, onDismiss: {
                presentBackfillIfNeeded()
                presentNextCelebration()
            }) { item in
                MilestoneCelebrationView(
                    celebration: item.celebration,
                    hours: totalHours,
                    artScheme: colorScheme,
                    onContinue: { shownCelebration = nil }
                )
            }
        }
        .fullScreenCover(item: $shownBackfill, onDismiss: { presentNextCelebration() }) { reveal in
            BackfillRevealView(
                foundHours: reveal.foundHours,
                suggestionCount: reveal.suggestionCount,
                confirmedHours: totalHours,
                artScheme: colorScheme,
                onReview: {
                    shownBackfill = nil
                    NotificationCenter.default.post(name: .switchToTab, object: ShellTab.inboxIndex)
                },
                onSkip: { shownBackfill = nil }
            )
        }
    }

    // MARK: - House events

    /// Wait after Today appears before the beam flies, so the eye is on the card.
    private static let confirmStartDelay: Double = 0.45
    /// The confirm build (beam, board, crossfade) settles within this; celebrations follow it.
    private static let confirmSettle: Double = 2.2
    /// When the hero's count-up has landed: beam flight, then the whole-hour steps.
    private static var countUpLands: Double { HouseMotion.beamFlight + 0.04 + HouseMotion.countUpMax + 0.05 }

    private func playPendingHouseWork() {
        guard isVisible else { return }
        let hadConfirm = houseEvents.takeConfirm() != nil && heroHoursOverride != nil
        // The hero sees its hours change from the pre-save value and plays the build; it reports
        // the celebration when the build settles (at once under Reduce Motion).
        heroHoursOverride = nil
        // The header total changes when the hero's number lands, not before it.
        if subtitleHoursOverride != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : Self.countUpLands)) {
                subtitleHoursOverride = nil
            }
        }
        if hadConfirm {
            schedulePendingCelebration()
        } else {
            presentBackfillIfNeeded()
            presentNextCelebration()
        }
    }

    /// Fallback for when the hero's own callback does not fire (e.g. a build interrupted by a
    /// tab switch, or a milestone queued in the background).
    private func schedulePendingCelebration() {
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.3 : Self.confirmSettle)) {
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

    /// The Day-1 reveal, once per profile.
    private func presentBackfillIfNeeded() {
        // Never over onboarding or What's new: the flow hands the reveal back when it closes.
        guard isVisible, shownCelebration == nil, shownBackfill == nil, !OnbBackfill.flowActive,
              let reveal = houseEvents.pendingBackfill else { return }
        houseEvents.markBackfillShown()
        shownBackfill = reveal
    }

    private func animate(_ animation: Animation = AppAnimation.smooth, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }

    private var isCompactHeaderVisible: Bool {
        scrollOffset < -70
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Button {
                    NotificationCenter.default.post(name: .switchToTab, object: 4)
                } label: {
                    Circle()
                        .fill(colors.backgroundTertiary)
                        .frame(width: 54, height: 54)
                        .overlay {
                            // No name is collected at onboarding: a neutral person glyph.
                            Image(systemName: "person.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(colors.textSecondary)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            Circle()
                                .fill(colors.backgroundSecondary)
                                .frame(width: 22, height: 22)
                                .overlay {
                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(colors.textSecondary)
                                }
                                .overlay {
                                    Circle()
                                        .strokeBorder(colors.border.opacity(0.38), lineWidth: 1)
                                }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open profile and settings")

                Spacer()

                Button {
                    NotificationCenter.default.post(name: .switchToTab, object: 3)
                } label: {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                        .frame(width: 48, height: 48)
                        .background(colors.backgroundTertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open reports")
            }

            VStack(alignment: .leading, spacing: 8) {
                // 2.0: Fraunces display (34pt, never scaled below the 28pt floor).
                Text(dashboardTitle)
                    .lhDisplayFont(.largeTitle)
                    .foregroundStyle(colors.textPrimary)
                    .lineSpacing(-1)
                    .minimumScaleFactor(0.83)
                    .accessibilityIdentifier("today.header.title")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(dashboardSubtitle)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.header.subtitle")
            }

            // 2.0: the action chips are gone (redesign-specs §2); "+" in the tab bar logs time.
        }
    }

    private var compactDashboardBar: some View {
        HStack(spacing: 12) {
            Button {
                NotificationCenter.default.post(name: .switchToTab, object: 4)
            } label: {
                Image(systemName: "person.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open profile and settings")

            VStack(alignment: .leading, spacing: 1) {
                Text(compactHeaderTitle)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                Text(compactHeaderSubtitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                NotificationCenter.default.post(name: .switchToTab, object: 2)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text("Log")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                }
                .foregroundStyle(AppColors.onAction)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(colors.action)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log time")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.88 : 0.94))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(colors.border.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: colors.textPrimary.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 12, y: 6)
        .lhMotion(AppAnimation.reveal, value: isCompactHeaderVisible)
    }

    private var displayName: String {
        let name = viewModel.userName
        if name.isEmpty || name == "User" { return "Dashboard" }
        // Use first name only
        return name.components(separatedBy: " ").first ?? name
    }

    private var dashboardTitle: String {
        if let title = mode.title { return title }
        if viewModel.properties.isEmpty {
            return "Add your first property"
        }
        if viewModel.timeEntries.isEmpty {
            return "Log your first hour"
        }
        return "Today’s work"
    }

    private var dashboardSubtitle: String {
        if let subtitle = mode.subtitle { return subtitle }
        if viewModel.properties.isEmpty {
            return "Every hour you log starts with a place."
        }
        if viewModel.timeEntries.isEmpty {
            guard let name = todayFocusName else {
                return foundInInbox.count > 0
                    ? String(localized: "Your rentals are staked. Confirm what we found, or log something new.", table: "Home")
                    : String(localized: "Your rentals are staked. Log your first hour while it’s fresh.", table: "Home")
            }
            return foundInInbox.count > 0
                ? "\(name) is staked. Confirm what we found, or log something new."
                : String(localized: "\(name) is staked. Log your first hour while it’s fresh.")
        }
        if let line = HomeHero.headerLine(heroState) { return line }
        return TodayHeroCopy.headerLine(hours: headerHours, target: Int(targetHours), isRecord: goalManager.goalChoice == .record, year: currentYear)
    }

    private var compactHeaderTitle: String {
        if let title = mode.compactTitle { return title }
        if shouldShowActivationCard { return "Finish setup" }
        return String(localized: "\(OnbFormat.hours(headerHours)) logged")
    }

    private var compactHeaderSubtitle: String {
        if let subtitle = mode.compactSubtitle { return subtitle }
        if shouldShowActivationCard {
            return "\(completedActivationSteps)/2 essentials complete"
        }
        return heroCopy.status ?? pace.text
    }

    private var userInitials: String {
        let source = displayName == "Dashboard" ? "LH" : displayName
        let pieces = source.split(separator: " ")
        if pieces.count >= 2 {
            return pieces.prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
        }
        return String(source.prefix(2)).uppercased()
    }

    // MARK: - House hero
    private var houseHero: some View {
        VStack(spacing: 12) {
            ZStack {
                HouseHeroCard(
                    progress: heroProgress,
                    year: currentYear,
                    status: heroCopy.status,
                    statusTone: heroCopy.tone,
                    heroCopy: heroCopy,
                    onCelebration: { _ in presentNextCelebration() },
                    footer: heroFooter,
                    stakeName: heroStakeName,
                    isLoading: hoursPending,
                    animatesChanges: viewModel.lastEntriesChangeOrigin != .remote,
                    isLookingBack: backfill.isScanning,
                    stageHours: heroStageHours,
                    stageTitle: heroState.stageTitle
                )
                // A new focus cross-fades in (Reduce Motion: the same fade, shorter).
                .id(heroState.key)
                .transition(.opacity)
            }
            // The card grows with Dynamic Type at every size (2.1); VoiceOver reads the whole hero
            // as one element with the full words (the empty lot keeps its "Add property" button reachable).
            .contentShape(Rectangle())
            .simultaneousGesture(heroSwipe, including: showsRentalRow ? .all : .subviews)
            .accessibilityElement(children: viewModel.properties.isEmpty && isNewOwner ? .contain : .ignore)
            .accessibilityLabel(heroAccessibilityLabel)
            .accessibilityIdentifier("today.hero")
            // Over 100 hours with "did anyone do more?" unanswered: the hero opens that question.
            .onTapGesture { if heroCopy.needsConfirmation && !hoursPending { showParticipationSheet = true } }
            .accessibilityAddTraits(heroCopy.needsConfirmation ? .isButton : [])
            .accessibilityHint(heroCopy.needsConfirmation ? "Opens the question about anyone else’s hours" : "")
            .sheet(isPresented: $showParticipationSheet) {
                let propertyId = heroState.participationPropertyId
                ParticipationConfirmationSheet(
                    year: currentYear,
                    propertyName: propertyId.flatMap { id in viewModel.properties.first { $0.id == id }?.name },
                    currentAnswer: taxProfile.noOneParticipatedMore(forYear: currentYear, propertyId: propertyId)
                ) { answer in
                    taxProfile.setNoOneParticipatedMore(answer, forYear: currentYear, propertyId: propertyId)
                }
            }

        }
    }

    // MARK: - Your rentals (2.1): the row under the hero

    private var rentalRow: some View {
        HomeRentalRow(
            rentals: homeRentals,
            focus: todayFocus,
            selection: homeSelection,
            onSelect: { selectRental($0) },
            onToggleSum: { animateFocus { homeSelection.toggleSum(focus: todayFocus) } },
            onSeeAll: { showRentalGrid = true },
            onAdd: { openAddPropertyFromHome() },
            scrollRequest: rentalRowScrollRequest
        )
        .sheet(isPresented: $showRentalGrid) {
            HomeGridSheet(rentals: homeRentals, focus: todayFocus) { picked in
                showRentalGrid = false
                selectRental(picked)
            }
        }
    }

    /// A tap carries no momentum: no bounce. Reduce Motion: a cross-fade only.
    private func animateFocus(_ updates: () -> Void) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 1.0), updates)
    }

    /// Tap a tile: focus it (kept across launches), or pick it while adding up.
    private func selectRental(_ tile: TodayFocusChoice) {
        animateFocus {
            switch homeSelection.tap(tile) {
            case .focus(let focus): setTodayFocus(focus)
            case .picked: break
            }
        }
    }

    private func setTodayFocus(_ focus: TodayFocusChoice) {
        switch focus {
        case .all: RentalPlanStore.shared.setFocusAll()
        case .rental(let id): RentalPlanStore.shared.setFocus(rental: id)
        }
        // The widget follows the focus.
        viewModel.refreshWidgetSurface()
    }

    /// The horizontal swipe on the hero steps the focus, like the tiles (not while adding up).
    private var heroSwipe: some Gesture {
        DragGesture(minimumDistance: 24).onEnded { v in
            guard showsRentalRow, !homeSelection.summing,
                  abs(v.translation.width) > 48, abs(v.translation.width) > abs(v.translation.height) * 1.5,
                  let next = homeRentals.step(from: todayFocus, by: v.translation.width < 0 ? 1 : -1) else { return }
            selectRental(next)
        }
    }

    /// DEBUG launch hooks for captures and UI tests (`-LHHomeFocus`, `-LHHomeSum`, `-LHHomeSheet`,
    /// `-LHHomeAutoplay`); compiled out of Release.
    private func applyHomeLaunchIfNeeded() {
        #if DEBUG
        guard !didApplyHomeLaunch else { return }
        didApplyHomeLaunch = true
        let rentals = homeRentals
        guard rentals.showsRow else { return }
        if let index = HomeDebugLaunch.focusIndex, let focus = rentals.focus(at: index) { setTodayFocus(focus) }
        let names = HomeDebugLaunch.sumNames
        if !names.isEmpty {
            homeSelection.summing = true
            homeSelection.summed = names.compactMap { name in rentals.rentalTiles.first { $0.name == name }?.propertyId }
        }
        if HomeDebugLaunch.opensGrid { showRentalGrid = true }
        if HomeDebugLaunch.autoplay { Task { await homeAutoplay() } }
        #endif
    }

    #if DEBUG
    /// A scripted tour for a video: tap through rentals, add two up, then See all.
    private func homeAutoplay() async {
        func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
        let order = homeRentals.order
        await pause(1.5)
        for i in [1, 2] where order.indices.contains(i) { selectRental(order[i]); await pause(1.4) }
        selectRental(order[0]); await pause(1.2)
        animateFocus { homeSelection.toggleSum(focus: todayFocus) }; await pause(1.2)
        for i in [1, 2] where order.indices.contains(i) { selectRental(order[i]); await pause(1.3) }
        await pause(0.8)
        animateFocus { homeSelection.toggleSum(focus: todayFocus) }; await pause(1.3)
        rentalRowScrollRequest = "seeall"; await pause(1.4)
        if homeRentals.showsSeeAll { showRentalGrid = true; await pause(2.8); showRentalGrid = false; await pause(1.0) }
    }
    #endif

    // MARK: - Pace cards (2-up; stacked from XXL)

    /// The empty lot (no property yet) shows no pace maths: nothing can be counted.
    @ViewBuilder
    private var paceCards: some View {
        if !viewModel.properties.isEmpty {
            // Stacked from XXL (the week list switches at the same size): "53h a week" never wraps.
            let layout = dynamicTypeSize >= .xxLarge
                ? AnyLayout(VStackLayout(spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                TodayPaceCard(model: ruleCard, isPending: hoursPending)
                    .accessibilityIdentifier(isREPS ? "dashboard.fiftyPercent" : "dashboard.daysLeft")
                if let finish = finishCard {
                    TodayPaceCard(model: finish, isPending: hoursPending)
                        .accessibilityIdentifier("dashboard.finishPace")
                }
            }
        }
    }

    /// "To finish by Dec 31" for the hero's target: the focused rental's own, or the goal's total
    /// (a rental's part of a shared total shows the total's). None for a record-only rental or
    /// rentals added up: there is no target to finish.
    private var finishCard: TodayPaceCardModel? {
        let hero = heroState
        if hero.hasTarget && !hero.isTotal {
            return TodayPaceCards.finish(hours: hero.hours, goal: hero.goal, pace: pace, now: Date(),
                                         paceReady: TodayHeroCopy.paceIsReady(hours: hero.hours, daysOfData: daysOfData))
        }
        switch hero.kind {
        case .total, .sharedPart:
            return TodayPaceCards.finish(hours: totalHours, goal: houseGoal, pace: TodayPace.resolve(hours: totalHours, goal: houseGoal),
                                         now: Date(), paceReady: TodayHeroCopy.paceIsReady(hours: totalHours, daysOfData: daysOfData))
        default:
            return nil
        }
    }

    /// REPS: the 50% rule (never checked until other work hours exist). Material participation:
    /// days left in the year.
    private var ruleCard: TodayPaceCardModel {
        guard isREPS else {
            return TodayPaceCardModel(label: "Days left", value: "\(daysLeftInYear)", status: "in \(currentYear)", tone: .neutral)
        }
        let tone: TodayPaceCardModel.Tone
        switch repsStatus.moreThanHalfStatus {
        case .notMet: tone = .caution
        case .met: tone = .positive
        case .notEntered: tone = .neutral
        }
        return TodayPaceCardModel(label: "50% rule", value: fiftyPercentValue, status: fiftyPercentDetail ?? "Met: over half your work hours", tone: tone)
    }

    private var heroStatusTone: HouseStatusTone {
        switch pace.tone {
        case .positive: return .positive
        case .caution: return .caution
        case .neutral: return .neutral
        }
    }

    /// The WP-H words (hours, goal, stage, next step) plus the pace line, for the live hours.
    private var heroAccessibilityLabel: String {
        if hoursPending { return "\(currentYear). Loading your hours from iCloud." }
        if backfill.isScanning {
            return "\(currentYear). \(AppFormat.hours(totalHours)) confirmed so far. Looking through your calendar; work we find waits in your Inbox."
        }
        let live = HouseProgress(hours: heroState.hours, goal: heroState.goal)
        if let stageTitle = heroState.stageTitle {
            // No target here (a record-only rental, a rental's part of the total, rentals added up).
            let copy = heroState.copy
            var parts = ["\(copy.eyebrow).", "\(Int(heroState.hours.rounded(.down))) \(copy.caption)."]
            if let q = copy.qualifier { parts.append("\(q).") }
            if let phrase = copy.phrase { parts.append("\(phrase).") }
            parts.append("\(stageTitle).")
            return parts.joined(separator: " ")
        }
        switch heroFooter {
        case .emptyLot:
            return "\(currentYear). An empty lot. \(TodayHeroCopy.emptyLotLine(target: heroCopy.targetHours))"
        case .found(let hours):
            return "\(currentYear). \(live.accessibilityLabel) \(hours) found in your calendar, not counted until you confirm."
        case nil:
            return "\(heroCopy.propertyName == nil ? String(currentYear) : heroCopy.eyebrow). \(live.accessibilityLabel(claimsGoalReached: heroCopy.claimsReached)) \(heroCopy.qualifier.map { "\($0). " } ?? "")\(heroCopy.spoken)."
        }
    }

    // MARK: - Activation
    private var homeActivationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            let isLarge = dynamicTypeSize.isAccessibilitySize
            let badge = Text("\(completedActivationSteps)/2")
                .font(.system(.caption, design: .rounded, weight: .black))
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(colors.backgroundTertiary)
                .clipShape(Capsule())
            let words = VStack(alignment: .leading, spacing: 4) {
                Text("Finish setting up")
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A few quick steps make every hour easier to review later.")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isLarge {
                // Past the accessibility sizes the words take the full width; tile and count share a row above.
                VStack(alignment: .leading, spacing: 12) {
                    HStack { SetupHeaderTile(symbol: "checklist"); Spacer(minLength: 8); badge }
                    words
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    SetupHeaderTile(symbol: "checklist")
                    words
                    Spacer(minLength: 8)
                    badge
                }
            }

            // A plain Grid, not LazyVGrid: four tiles need no laziness, and since WP-L removed the
            // launch splash the lazy grid left its first row out of the accessibility tree.
            // At accessibility sizes the 2x2 grid becomes one column, so the scaled words fit.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    ForEach(activationTiles, id: \.identifier) { activationActionTile($0) }
                }
            } else {
                let tiles = activationTiles
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow { activationActionTile(tiles[0]); activationActionTile(tiles[1]) }
                    GridRow { activationActionTile(tiles[2]); activationActionTile(tiles[3]) }
                }
            }
        }
        .padding(18)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(colors.border.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var completedActivationSteps: Int {
        (viewModel.properties.isEmpty ? 0 : 1) + (viewModel.timeEntries.isEmpty ? 0 : 1)
    }

    private func openAddPropertyFromHome() {
        if viewModel.properties.isEmpty {
            NotificationCenter.default.post(name: .switchToPropertiesAndOpenAddProperty, object: nil)
        } else {
            NotificationCenter.default.post(name: .switchToTab, object: 1)
        }
    }

    private struct ActivationTile {
        let title: String
        let subtitle: String
        let symbol: String
        let isComplete: Bool
        let identifier: String
        let action: () -> Void
    }

    private var activationTiles: [ActivationTile] {
        [
            ActivationTile(
                title: String(localized: "Property"),
                subtitle: viewModel.properties.isEmpty ? String(localized: "Add first") : String(localized: "\(viewModel.properties.count) ready"),
                symbol: "building.2", isComplete: !viewModel.properties.isEmpty,
                identifier: "home.activation.property", action: { openAddPropertyFromHome() }),
            ActivationTile(
                title: String(localized: "First hour"),
                subtitle: viewModel.timeEntries.isEmpty ? String(localized: "Log now") : AppFormat.hours(totalHours),
                symbol: "clock", isComplete: !viewModel.timeEntries.isEmpty,
                identifier: "home.activation.firstHour",
                action: { NotificationCenter.default.post(name: .switchToTab, object: 2) }),
            ActivationTile(
                title: String(localized: "Learn"), subtitle: String(localized: "What counts"),
                symbol: "book", isComplete: false,
                identifier: "home.activation.learn", action: { showLearningCenter = true }),
            ActivationTile(
                title: String(localized: "Report"), subtitle: String(localized: "Check pace"),
                symbol: "chart.bar", isComplete: false,
                identifier: "home.activation.report",
                action: { NotificationCenter.default.post(name: .switchToTab, object: 3) }),
        ]
    }

    private func activationActionTile(_ tile: ActivationTile) -> some View {
        ActivationTileView(tile: tile.title, subtitle: tile.subtitle, symbol: tile.symbol,
                           isComplete: tile.isComplete, identifier: tile.identifier, action: tile.action)
    }

}

// MARK: - Shared Entry Row (used in Dashboard & History)
struct EntryListRow: View {
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    let entry: TimeEntry
    let propertyName: String

    private var categoryIconName: String {
        entry.category.lucideIconName
    }

    private var categoryColor: Color {
        entry.category.color
    }

    private var categoryWash: Color {
        let c = AdaptiveColors(colorScheme: colorScheme)
        switch entry.category {
        case .repairs, .renovations: return c.coralWash
        case .management, .investing: return c.sageWash
        case .leasing, .travel: return c.skyWash
        case .bookkeeping, .financing: return c.honeyWash
        case .legal: return c.roseWash
        case .insurance, .contractNegotiation: return c.primarySurface
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            JellyBadge(
                systemName: categoryIconName,
                color: categoryColor,
                wash: categoryWash,
                size: 44
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.category.rawValue)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Text(propertyName)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    if entry.isCalendarImport {
                        HStack(spacing: 2) {
                            Image(systemName: "calendar")
                                .font(.system(size: 9, weight: .medium))
                                .accessibilityHidden(true)
                            Text("Cal")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(AppColors.sky)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(colors.skyWash)
                        .clipShape(Capsule())
                    }
                    if !entry.countsForREPS {
                        Text("Not counted")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(AppColors.coral)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.coralWash)
                            .clipShape(Capsule())
                    }
                    Text(String(format: "%.1fh", entry.hours))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                }
                Text(entry.date, style: .date)
                    .font(AppTypography.caption)
                    .foregroundStyle(colors.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

/// A milestone Today is presenting (the celebration and the tax year it belongs to).
struct TodayCelebration: Identifiable, Equatable {
    let celebration: HouseCelebration
    let year: Int
    var id: String { HouseCelebrationLedger.token(celebration, year: year) }
}

private struct DashboardScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    DashboardView(inbox: InboxViewModel(app: nil, storeProvider: { nil }))
        .environmentObject(AppViewModel())
        .environmentObject(GoalManager.shared)
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
                    Image(systemName: "doc.richtext").font(.system(size: 20)).foregroundStyle(colors.action)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your \(String(year)) record").font(.headline).foregroundStyle(colors.textPrimary)
                        Text("PDF and spreadsheet · \(entryCount) \(entryCount == 1 ? "entry" : "entries")")
                            .font(.subheadline).foregroundStyle(colors.textSecondary)
                    }
                }
                pageView
                    .frame(height: Self.sharpPage, alignment: .top)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10, style: .continuous))
            }
            .padding([.horizontal, .top], 16)
        } locked: {
            pageView
                .offset(y: -Self.sharpPage)
                .frame(height: Self.pageHeight - Self.sharpPage, alignment: .top)
                .clipped()
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colors.backgroundSecondary))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(colors.border, lineWidth: 0.5))
    }

    private func load() async {
        guard page == nil else { return }
        page = await RecordPageModel.load(entries: viewModel.timeEntries, properties: viewModel.properties,
                                          owner: viewModel.userName, year: year)
    }
}


/// The setup card's header tile: a blueprint action tile with an SF Symbol (brand system §4:
/// function icons are symbols; the 3D tool renders are for categories).
private struct SetupHeaderTile: View {
    let symbol: String
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .headline) private var side: CGFloat = 42

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        Image(systemName: symbol)
            .font(.system(size: side * 0.45, weight: .regular))
            .foregroundStyle(colors.action)
            .frame(width: side, height: side)
            .background(colors.actionSurface, in: RoundedRectangle(cornerRadius: side * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}


/// One setup tile. Fonts are text styles and the glyph box is a scaled metric, so the tile grows
/// with Dynamic Type; at accessibility sizes the icon sits beside the words instead of above.
private struct ActivationTileView: View {
    let tile: String
    let subtitle: String
    let symbol: String
    let isComplete: Bool
    let identifier: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var box: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 92

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(alignment: .center, spacing: 14))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
        Button(action: action) {
            layout {
                ZStack {
                    RoundedRectangle(cornerRadius: box * 0.35, style: .continuous)
                        .fill(isComplete ? colors.positiveSurface : colors.backgroundTertiary)
                    Image(systemName: isComplete ? "checkmark.circle" : symbol)
                        .font(.system(size: box * 0.47, weight: .regular))
                        .foregroundStyle(isComplete ? colors.positive : colors.textPrimary)
                        .accessibilityHidden(true)
                }
                .frame(width: box, height: box)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tile)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                    Text(subtitle)
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(colors.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                if dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 0 : minHeight, alignment: .topLeading)
            .padding(12)
            .background(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.72 : 0.9))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(colors.border.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tile). \(subtitle)")
        .accessibilityIdentifier(identifier)
    }
}
