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
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var repsStatus: TaxQualificationEngine.REPSResult {
        viewModel.repsStatus(participant: .selfParticipant, year: currentYear)
    }

    // MARK: House inputs
    // The hero counts the goal's countable hours only (TodayHouse.swift): REPS = your own
    // real-estate hours; MP = owner (+ spouse when tracked jointly). Investor-only tasks never count.
    private var houseGoal: HouseGoal { HouseGoal(goalManager.globalGoalType) }
    private var totalHours: Double { viewModel.houseCountableHours(goal: houseGoal, year: currentYear) }
    private var targetHours: Double { houseGoal.targetHours }
    private var isGoalMet: Bool { HouseProgress(hours: totalHours, goal: houseGoal).isGoalMet }
    /// Hours still to log. The tests are "more than" the target, so exactly 750 still needs a bit.
    private var remainingHours: Double { isGoalMet ? 0 : max(targetHours - totalHours, 0.01) }
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

    private var weeksLeftInYear: Double {
        max(Double(daysLeftInYear) / 7.0, 1.0)
    }

    private var hoursPerWeekNeeded: Double {
        remainingHours / weeksLeftInYear
    }

    // This week hours by day
    private var thisWeekHours: [Double] {
        let cal = Calendar.current
        let today = Date()
        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else {
            return Array(repeating: 0, count: 7)
        }
        var result: [Double] = []
        for dayOffset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: weekStart) else {
                result.append(0)
                continue
            }
            let dayHours = viewModel.timeEntries
                .filter { cal.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.hours }
            result.append(dayHours)
        }
        return result
    }

    private var thisWeekTotal: Double {
        thisWeekHours.reduce(0, +)
    }

    private var todayWeekdayIndex: Int {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: Date())
        // Convert Sunday=1 to Monday-first: Mon=0, Tue=1, ... Sun=6
        return weekday == 1 ? 6 : weekday - 2
    }

    @State private var showRecordExport = false
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
    var inboxBackfillCount = 0

    private var mode: TodayPresentation.Mode {
        TodayPresentation.mode(
            hoursPending: hoursPending,
            backfillScanning: backfill.isScanning,
            hasProperties: !viewModel.properties.isEmpty,
            hasEntries: !viewModel.timeEntries.isEmpty
        )
    }

    private var shouldShowActivationCard: Bool { mode.showsActivationCard }

    var body: some View {
        NavigationStack {
            ZStack {
                LHMobileCanvas()

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
                        if mode == .lookingBack {
                            BackfillProgressHeader(job: backfill, found: inboxBackfillCount, onRetry: {}, onOpen: {
                                NotificationCenter.default.post(name: .switchToTab, object: ShellTab.inboxIndex)
                            })
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("Opens your Inbox")
                            .accessibilityIdentifier("today.lookingBack")
                        } else if shouldShowActivationCard {
                            homeActivationCard
                        } else {
                            learningShortcutCard
                        }
                        recentEntriesSection
                        thisWeekCard
                        yourRecordLock
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, AppSpacing.tabContentBottomInset)
                    // WP-L: the hours settle in with a crossfade when the first pull lands.
                    .lhMotion(AppAnimation.standard, value: hoursPending)
                }
                .coordinateSpace(name: "dashboardScroll")
                .onPreferenceChange(DashboardScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
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
            .navigationDestination(isPresented: $showLearningCenter) {
                LearningCenterView()
            }
            .navigationDestination(isPresented: $showHistory) {
                HistoryView()
            }
            .onAppear {
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
        guard isVisible, shownCelebration == nil, shownBackfill == nil,
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
                            Text(userInitials)
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(colors.textPrimary)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            Circle()
                                .fill(colors.backgroundSecondary)
                                .frame(width: 22, height: 22)
                                .overlay {
                                    LucideIcon(image: Lucide.settings, size: 12)
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
                    LucideIcon(image: Lucide.chartColumnIncreasing, size: 22)
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

            quickActionsRow
        }
    }

    private var compactDashboardBar: some View {
        HStack(spacing: 12) {
            Button {
                NotificationCenter.default.post(name: .switchToTab, object: 4)
            } label: {
                Text(userInitials)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
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
                    LucideIcon(image: Lucide.plus, size: 14)
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
            return "Start with a property so every hour has a clean record."
        }
        if viewModel.timeEntries.isEmpty {
            return "\(viewModel.properties.count) property ready. Capture the first activity while details are fresh."
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

    // MARK: - Home Commands
    @ViewBuilder
    private var quickActionsRow: some View {
        if viewModel.properties.isEmpty {
            HStack(spacing: 10) {
                dashboardPrimaryPill("Add property", icon: Lucide.building2) {
                    openAddPropertyFromHome()
                }
                dashboardSecondaryPill("What counts", icon: Lucide.bookOpenText, width: 138) {
                    showLearningCenter = true
                }
            }
        } else if viewModel.timeEntries.isEmpty {
            HStack(spacing: 10) {
                dashboardPrimaryPill("Log time", icon: Lucide.clock) {
                    NotificationCenter.default.post(name: .switchToTab, object: 2)
                }
                dashboardSecondaryPill("Learn", icon: Lucide.bookOpenText, width: 92) {
                    showLearningCenter = true
                }
                dashboardSecondaryPill("Property", icon: Lucide.building2, width: 104) {
                    NotificationCenter.default.post(name: .switchToTab, object: 1)
                }
            }
        } else {
            HStack(spacing: 10) {
                dashboardPrimaryPill("Log time", icon: Lucide.clock) {
                    NotificationCenter.default.post(name: .switchToTab, object: 2)
                }
                dashboardSecondaryPill("Entries", icon: Lucide.list, width: 98) {
                    showHistory = true
                }
                dashboardSecondaryPill("Reports", icon: Lucide.chartColumnIncreasing, width: 100) {
                    NotificationCenter.default.post(name: .switchToTab, object: 3)
                }
            }
        }
    }

    private func dashboardPrimaryPill(_ title: String, icon: UIImage, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                LucideIcon(image: icon, size: 17)
                Text(title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(AppColors.onAction)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(colors.action)
            .clipShape(Capsule())
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(title)
    }

    private func dashboardSecondaryPill(_ title: String, icon: UIImage, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                LucideIcon(image: icon, size: 15)
                Text(title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(colors.textPrimary)
            .frame(width: width)
            .frame(height: 50)
            .background(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.72 : 1))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(title)
    }

    // MARK: - Your record (free, 10h or more): the `.card` locked preview (WP-P)
    @ViewBuilder
    private var yourRecordLock: some View {
        if shouldShowProNudge && !hoursPending
            && ProGate.showsTodayRecordLock(isPro: subscriptionManager.isPro, confirmedHours: totalHours) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your record")
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.3)
                    .foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                TodayRecordLockCard(year: currentYear, confirmedHours: totalHours, onUnlocked: { showRecordExport = true })
            }
        }
    }

    private var shouldShowProNudge: Bool {
        !viewModel.properties.isEmpty &&
        (!viewModel.timeEntries.isEmpty || GuidedOnboardingStore.isCompleted || GuidedOnboardingStore.isSkipped)
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
                isLoading: hoursPending,
                animatesChanges: viewModel.lastEntriesChangeOrigin != .remote,
                isLookingBack: backfill.isScanning
            )
            // The art has a fixed frame; past AX2 the words would wrap into it, so cap there.
            // VoiceOver reads the whole hero as one element with the full words.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(heroAccessibilityLabel)
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("today.hero")

            HStack(alignment: .top, spacing: 12) {
                if isREPS {
                    dashboardMiniMetric(
                        title: "50% rule",
                        value: fiftyPercentValue,
                        detail: fiftyPercentDetail,
                        isPending: hoursPending
                    )
                    .accessibilityIdentifier("dashboard.fiftyPercent")
                } else {
                    dashboardMiniMetric(title: "Days left", value: "\(daysLeftInYear)")
                }
                if isGoalMet && !hoursPending {
                    dashboardMiniMetric(title: "Goal hours", value: "Reached")
                } else {
                    dashboardMiniMetric(
                        title: "To finish on time",
                        value: "\(Int(hoursPerWeekNeeded.rounded(.up)))h a week",
                        isPending: hoursPending
                    )
                }
            }
        }
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
        return "\(currentYear). \(live.accessibilityLabel) \(pace.text)."
    }

    private func dashboardMiniMetric(title: String, value: String, detail: String? = nil, isPending: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(colors.textSecondary)
            Text(value)
                .font(.system(.callout, design: .rounded, weight: .black))
                .monospacedDigit()
                .foregroundStyle(colors.textPrimary)
                .opacity(isPending ? 0 : 1)
                .overlay(alignment: .leading) {
                    if isPending {
                        PlaceholderBar(width: 72, height: 14)
                            .transition(.opacity)
                    }
                }
                .accessibilityLabel(isPending ? "Loading" : value)
            if let detail {
                // While pending the words are laid out but hidden, so the card already has its
                // settled height and nothing below it moves when the hours land.
                Text(detail)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(isPending ? 0 : 1)
                    .overlay(alignment: .topLeading) {
                        if isPending {
                            PlaceholderBar(width: 96, height: 10)
                                .padding(.top, 3)
                                .transition(.opacity)
                        }
                    }
                    .accessibilityHidden(isPending)
            }
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(colors.border.opacity(0.28), lineWidth: 1)
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

    // MARK: - This Week Card
    private var thisWeekCard: some View {
        VStack(spacing: 14) {
            // Header
            HStack {
                Text("This Week")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                Text(String(format: "%.1fh", thisWeekTotal))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
            }

            // Day grid
            let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 6) {
                        let hours = thisWeekHours[i]
                        let isToday = i == todayWeekdayIndex
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    isToday ? colors.action :
                                    hours > 0 ? AppColors.sageWash :
                                    colors.backgroundTertiary
                                )
                                .frame(width: 30, height: 30)

                            if hours > 0 {
                                Text(String(format: "%.0f", hours))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(isToday ? colors.onAction : colors.textPrimary)
                            } else {
                                Text("\u{2013}")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(isToday ? colors.onAction : colors.textSecondary)
                            }
                        }
                        Text(dayLabels[i])
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(colors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(colors.border.opacity(0.28), lineWidth: 1)
        }
    }

    // MARK: - Recent Entries
    private var recentEntriesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section header
            HStack {
                Text("Recent Activity")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                if !recentEntries.isEmpty {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        HStack(spacing: 2) {
                            Text("See all")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(colors.actionText)
                            LucideIcon(image: Lucide.chevronRight, size: 14)
                                .foregroundStyle(colors.actionText)
                        }
                    }
                }
            }

            if recentEntries.isEmpty {
                emptyRecentCard
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentEntries.enumerated()), id: \.element.id) { index, entry in
                        NavigationLink {
                            TimeEntryDetailView(entry: entry)
                        } label: {
                            EntryListRow(
                                entry: entry,
                                propertyName: viewModel.properties.first { $0.id == entry.propertyId }?.name ?? "Unknown"
                            )
                        }
                        .buttonStyle(.plain)
                        if index < recentEntries.count - 1 {
                            Divider()
                                .padding(.leading, 72)
                        }
                    }
                }
                .background(colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(colors.border.opacity(0.28), lineWidth: 1)
                }
            }
        }
    }

    private var emptyRecentCard: some View {
        VStack(spacing: 12) {
            JellyBadge(systemName: "clock", color: AppColors.primary, wash: colors.primarySurface, size: 56)
            Text("No entries yet")
                .font(AppTypography.subheadline)
                .foregroundStyle(colors.textPrimary)
            Text("Tap Track to log your first hours")
                .font(AppTypography.body)
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
    }

    // MARK: - Learning Shortcut
    private var learningShortcutCard: some View {
        NavigationLink {
            LearningCenterView()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                LHIconTile(
                    icon: Lucide.bookOpenText,
                    color: AppColors.primary,
                    wash: colors.primarySurface,
                    size: 46,
                    isActive: true
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Learn what counts")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)

                    Text("REPS, STR rules, and audit-ready logs.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                LucideIcon(image: Lucide.chevronRight, size: 18)
                    .foregroundStyle(colors.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .padding(18)
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(colors.border.opacity(0.28), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open learning center. Learn what counts for rental tax tracking.")
    }

    // MARK: - Computed
    private var recentEntries: [TimeEntry] {
        Array(viewModel.timeEntries.sorted { $0.date > $1.date }.prefix(5))
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
    DashboardView()
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
