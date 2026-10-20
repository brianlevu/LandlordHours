import SwiftUI
import LucideIcons

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

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var repsStatus: TaxQualificationEngine.REPSResult {
        viewModel.repsStatus(participant: .selfParticipant, year: currentYear)
    }

    // MARK: House inputs
    // The hero counts the goal's countable hours only (TodayHouse.swift): REPS = your own
    // real-estate hours; MP = owner (+ spouse when tracked jointly). Investor-only tasks never count.
    private var houseGoal: HouseGoal { goalManager.houseGoal }
    private var totalHours: Double { viewModel.houseCountableHours(goal: houseGoal, year: currentYear) }
    private var targetHours: Double { houseGoal.targetHours }
    private var isGoalMet: Bool { HouseProgress(hours: totalHours, goal: houseGoal).isGoalMet }
    private var pace: TodayPace { TodayPace.resolve(hours: totalHours, goal: houseGoal) }

    /// What the hero draws: the live hours, or the pre-save hours while a confirm build waits to play.
    private var heroProgress: HouseProgress {
        HouseProgress(hours: heroHoursOverride ?? totalHours, goal: houseGoal)
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

    @State private var showPaywall = false
    // The header line follows the hero: it keeps the pre-save total until the count-up lands.
    @State private var subtitleHoursOverride: Double?
    private var headerHours: Double { subtitleHoursOverride ?? totalHours }
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
                       includeSpouse: viewModel.tracksSpouseJointly, now: InboxClock.now())
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

    private var heroStakeName: String? {
        guard isNewOwner else { return nil }
        return viewModel.properties.first?.name
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
                                TodayRecordSlot(year: currentYear, confirmedHours: totalHours) { showPaywall = true }
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
            .sheet(isPresented: $showPaywall) {
                PaywallView(context: .dashboardUnlock, onClose: { showPaywall = false })
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
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
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
            let name = viewModel.properties.first?.name ?? "Your rental"
            return foundInInbox.count > 0
                ? "\(name) is staked. Confirm what we found, or log something new."
                : "\(name) is staked. Log your first hour while it's fresh."
        }
        return "\(AppFormat.hours(headerHours)) counted toward \(Int(targetHours)) hours this year."
    }

    private var compactHeaderTitle: String {
        if let title = mode.compactTitle { return title }
        if shouldShowActivationCard { return "Finish setup" }
        return "\(AppFormat.hours(headerHours)) logged"
    }

    private var compactHeaderSubtitle: String {
        if let subtitle = mode.compactSubtitle { return subtitle }
        if shouldShowActivationCard {
            return "\(completedActivationSteps)/2 essentials complete"
        }
        return pace.text
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
            HouseHeroCard(
                progress: heroProgress,
                year: currentYear,
                status: pace.text,
                statusTone: heroStatusTone,
                onCelebration: { _ in presentNextCelebration() },
                footer: heroFooter,
                stakeName: heroStakeName,
                isLoading: hoursPending,
                animatesChanges: viewModel.lastEntriesChangeOrigin != .remote,
                isLookingBack: backfill.isScanning
            )
            // The art has a fixed frame; past AX2 the words would wrap into it, so cap there.
            // VoiceOver reads the whole hero as one element with the full words (the empty lot
            // keeps its "Add property" button reachable).
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .accessibilityElement(children: viewModel.properties.isEmpty && isNewOwner ? .contain : .ignore)
            .accessibilityLabel(heroAccessibilityLabel)
            .accessibilityIdentifier("today.hero")

        }
    }

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
                TodayPaceCard(model: TodayPaceCards.finish(hours: totalHours, goal: houseGoal, pace: pace, now: Date()),
                              isPending: hoursPending)
                    .accessibilityIdentifier("dashboard.finishPace")
            }
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
        let live = HouseProgress(hours: totalHours, goal: houseGoal)
        switch heroFooter {
        case .emptyLot:
            return "\(currentYear). An empty lot. Add a property. Every hour you confirm builds on it."
        case .found(let hours):
            return "\(currentYear). \(live.accessibilityLabel) \(hours) found in your calendar, not counted until you confirm."
        case nil:
            return "\(currentYear). \(live.accessibilityLabel) \(pace.text)."
        }
    }

    // MARK: - Activation
    private var homeActivationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                LHIconTile(
                    icon: Lucide.listChecks,
                    color: colors.action,
                    wash: colors.actionSurface,
                    size: 42,
                    isActive: true
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Finish your tax-ready setup")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text("A few quick steps make every hour easier to review later.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .lineSpacing(2)
                }

                Spacer(minLength: 8)

                Text("\(completedActivationSteps)/2")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(colors.backgroundTertiary)
                    .clipShape(Capsule())
            }

            // A plain Grid, not LazyVGrid: four tiles need no laziness, and since WP-L removed the
            // launch splash the lazy grid left its first row out of the accessibility tree.
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                activationActionTile(
                    title: "Property",
                    subtitle: viewModel.properties.isEmpty ? "Add first" : "\(viewModel.properties.count) ready",
                    icon: Lucide.building2,
                    isComplete: !viewModel.properties.isEmpty,
                    accessibilityIdentifier: "home.activation.property",
                    action: {
                        openAddPropertyFromHome()
                    }
                )

                activationActionTile(
                    title: "First hour",
                    subtitle: viewModel.timeEntries.isEmpty ? "Log now" : AppFormat.hours(totalHours),
                    icon: Lucide.clock,
                    isComplete: !viewModel.timeEntries.isEmpty,
                    accessibilityIdentifier: "home.activation.firstHour",
                    action: {
                        NotificationCenter.default.post(name: .switchToTab, object: 2)
                    }
                )

                }
                GridRow {
                activationActionTile(
                    title: "Learn",
                    subtitle: "What counts",
                    icon: Lucide.bookOpenText,
                    isComplete: false,
                    accessibilityIdentifier: "home.activation.learn",
                    action: {
                        showLearningCenter = true
                    }
                )

                activationActionTile(
                    title: "Report",
                    subtitle: "Check pace",
                    icon: Lucide.chartColumnIncreasing,
                    isComplete: false,
                    accessibilityIdentifier: "home.activation.report",
                    action: {
                        NotificationCenter.default.post(name: .switchToTab, object: 3)
                    }
                )
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

    private func activationActionTile(
        title: String,
        subtitle: String,
        icon: UIImage,
        isComplete: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isComplete ? colors.positiveSurface : colors.backgroundTertiary)
                        .frame(width: 40, height: 40)

                    LucideIcon(image: isComplete ? Lucide.circleCheck : icon, size: 19)
                        .foregroundStyle(isComplete ? colors.positive : colors.textPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 92)
            .padding(12)
            .background(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.72 : 0.9))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(colors.border.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityIdentifier(accessibilityIdentifier)
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
                            LucideIcon(image: Lucide.calendar, size: 9)
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
                        Text("Non-REPS")
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
