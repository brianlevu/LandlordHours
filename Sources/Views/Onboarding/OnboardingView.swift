import SwiftUI
import Combine

// MARK: - Entry points
//
// New users: `OnboardingView` replaces the 1.x sign-in wall and onboarding. Welcome leads with
// "Get started"; there is no sign-in (2.2, package K: iCloud is the identity). Under the button,
// K's `WelcomeRecordsFooter` says where records live, that it is checking iCloud, or what it found
// (then the button reads Continue). Upgraders: `OnbWhatsNewSheet` over Today.

struct OnboardingView: View {
    @Binding var showOnboarding: Bool
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var flow: OnbFlow?

    var body: some View {
        Group {
            if let flow {
                OnbRoot(flow: flow)
                    .environment(\.onbWelcomeAccount, OnbWelcomeAccount.resolve(hasCompletedOnboarding: viewModel.activeProfileCompletedOnboarding))
                    .environment(\.onbLeaveWelcome, { showOnboarding = false })
            } else {
                Color.clear
            }
        }
        // Welcome draws its own dusk/night page; the steps draw the plain canvas. Until the flow
        // exists the page shows, so the launch hand-off fades into `pageTop`, never a flash.
        .background(LHPage())
        .onAppear {
            guard flow == nil else { return }
            viewModel.suppressCelebrations = true
            let start = OnbDebugLaunch.startStep
            var services = OnbServices.live(app: viewModel, environment: .current) { completion in
                finish(completion)
            }
            // Hold the flow on screen before any new profile exists (see `holdingOnboarding`).
            let keepShown = $showOnboarding
            services = services.holdingOnboarding { keepShown.wrappedValue = true }
            let made = OnbFlow(cohort: .new, services: services, startAt: start)
            OnbDebugLaunch.apply(to: made)
            OnbBackfill.flowStarted()
            // A capture launch past Welcome: the record set always exists (package K).
            if (start ?? .welcome) != .welcome { showOnboarding = true }
            flow = made
            made.appeared()
        }
        .onDisappear {
            viewModel.suppressCelebrations = false
            // Left without finishing (sign-out, profile restore): never hold Today's reveal.
            if OnbBackfill.flowActive { OnbBackfill.flowEnded(foundShown: false) }
        }
    }

    private func finish(_ completion: OnbCompletion) {
        UserDefaults.standard.set(true, forKey: UserScope.key("hasCompletedOnboarding"))
        // The question the 2.0 What's new asks was answered here.
        CaptureOptIn.markWhatsNewSeen()
        // Staked led with the found hours: Today never repeats them in a reveal.
        OnbBackfill.flowEnded(foundShown: completion.foundShown)
        CaptureSetupHandoff.openInboxAfterOnboarding = completion.openInbox
        Analytics.onboardingCompleted(skippedProperty: completion.skippedProperty, calendar: completion.calendar.analyticsKey)
        viewModel.suppressCelebrations = false
        withAnimation(AppAnimation.standard) { showOnboarding = false }
    }
}

/// Upgraders from 1.x: their hours and the house, then the calendar and visit-end note.
struct OnbWhatsNewSheet: View {
    var onFinish: (_ openInbox: Bool) -> Void
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var flow: OnbFlow?

    var body: some View {
        Group {
            if let flow { OnbRoot(flow: flow, embedded: true) } else { Color.clear }
        }
        .background(LHCanvas())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onb.whatsNew")
        .onAppear {
            guard flow == nil else { return }
            let made = OnbFlow(cohort: .upgrade, services: .live(app: viewModel, environment: .current) { completion in
                CaptureOptIn.markWhatsNewSeen()
                OnbBackfill.flowEnded(foundShown: completion.foundShown)
                onFinish(completion.openInbox)
            })
            OnbBackfill.flowStarted()
            let input = Self.houseInput(for: viewModel)
            made.upgradeHours = input.hours
            made.upgradeGoal = input.goal
            made.upgradeIsRecord = GoalManager.shared.goalChoice == .record
            made.goal = viewModel.houseGoal == .reps750 ? .reps750 : (viewModel.houseGoal == .mp500 ? .mp500 : .mp100)
            OnbDebugLaunch.apply(to: made)
            flow = made
            made.appeared()
        }
    }

    /// The house the upgrader sees first: this year's countable hours for their goal, the same
    /// number Today's house uses (REPS: your own hours only; material participation adds a
    /// spouse only when tracked jointly).
    static func houseInput(for app: AppViewModel) -> (hours: Double, goal: HouseGoal) {
        (app.houseCountableHours(), app.houseGoal)
    }
}

// MARK: - Live wiring

extension OnbServices {
    /// The real app: profile, goal, tax profile, property, calendar + 90-day look-back,
    /// visit-end consent, analytics.
    static func live(app: AppViewModel, environment: CaptureSetupEnvironment, complete: @escaping (OnbCompletion) -> Void) -> OnbServices {
        var s = OnbServices()
        // Package K: no profile to make and no sign-in; the record set exists from the first launch.
        s.ensureProfile = {}
        s.signUpWithApple = {}
        s.saveGoal = { goal in GoalManager.shared.setGoalChoice(goal.goalChoice) }
        s.saveWho = { who in TaxProfileManager.shared.spouseTracking = (who == .both) }
        s.saveGoalAnswers = { rental, pro in GoalManager.shared.setGoalSetup(rental: rental, pro: pro) }
        s.addProperty = { name, address, type in
            app.addProperty(name: name, address: address, type: type)
            OnbBackfill.placeUnplaced(app: app)
        }
        s.requestCalendar = { await environment.requestCalendar() }
        s.setCalendarSuggestions = { on in
            CaptureOptIn.setCalendarSuggestionsEnabled(on)
            if !on { EventPromptsConsent.set(false) }
            app.objectWillChange.send()
        }
        s.startBackfill = { update in OnbBackfill.start(app: app, environment: environment, update: update) }
        s.requestNotifications = { await environment.requestNotifications() }
        s.setEventPrompts = { on in
            // End-of-event prompts need calendar events to talk about.
            EventPromptsConsent.set(on && CaptureOptIn.calendarSuggestionsEnabled())
            Task { await CaptureNotificationRefresher.shared.refresh(reason: on ? "capture-opt-in" : "capture-opt-out") }
        }
        s.complete = complete
        s.track = { Analytics.onboarding($0) }
        return s
    }
}

/// The 90-day look-back, started from onboarding and running while the user answers. It is
/// WP-L's `BackfillJob` (streaming into the profile's inbox); what onboarding reports is read
/// back from that inbox, so every count is the Inbox's own.
@MainActor
enum OnbBackfill {
    /// An onboarding or What's new flow is on screen: Today's reveal waits for it to close.
    static private(set) var flowActive = false
    private static var observation: AnyCancellable?

    static func flowStarted() { flowActive = true }

    /// The flow ended. Staked showed the count: the reveal never plays. Otherwise a reveal that
    /// arrived during the flow is handed to Today again now that nothing covers it.
    static func flowEnded(foundShown: Bool) {
        flowActive = false
        let events = TodayHouseEvents.shared
        if foundShown {
            events.markBackfillShown()
        } else if let held = events.pendingBackfill {
            events.backfillFinished(foundHours: held.foundHours, suggestionCount: held.suggestionCount)
        }
    }

    /// The look-back may find events before the first property exists. Once the owner has exactly
    /// one property, every unplaced pending suggestion goes to it, in the store, before the
    /// Inbox shows them (so each row can be confirmed in one tap).
    static func placeUnplaced(app: AppViewModel) {
        guard let id = OnbPlacement.soleProperty(app.properties),
              let store = AppModelHost.shared.suggestionStore,
              store.attachPropertyToUnplaced(id) > 0 else { return }
        NotificationCenter.default.post(name: .captureSuggestionsDidChange, object: nil)
    }

    static func start(app: AppViewModel, environment: CaptureSetupEnvironment, update: @escaping @MainActor (OnbScanUpdate) -> Void) {
        guard let store = AppModelHost.shared.suggestionStore else {
            update(OnbScanUpdate(state: .blocked, found: .none))
            return
        }
        let job = BackfillJob.shared
        job.start(environment.makeScanner(app, store))
        observation = job.$phase
            .combineLatest(job.$foundCount)
            .receive(on: DispatchQueue.main)
            .sink { phase, _ in
                MainActor.assumeIsolated {
                    // Items that stream in after the first property was saved go to it too.
                    placeUnplaced(app: app)
                    let found = OnbFound.from(store.suggestions, now: InboxClock.now())
                    update(OnbScanUpdate(state: state(phase), found: found, progress: progress(phase)))
                }
            }
    }

    static func state(_ phase: BackfillJob.Phase) -> OnbScanState {
        switch phase {
        case .idle: return .idle
        case .scanning: return .running
        case .finished: return .finished
        case .blocked, .cancelled: return .blocked
        }
    }

    static func progress(_ phase: BackfillJob.Phase) -> Double {
        switch phase {
        case .scanning(let completed, let total): return total > 0 ? Double(completed) / Double(total) : 0
        case .finished: return 1
        default: return 0
        }
    }
}


// MARK: - Root

enum OnbWelcomeAccount {
    case shown, hidden

    /// Sign in and Restore stay on Welcome until the active profile has finished onboarding. A
    /// profile made by "Get started" that was never finished has nothing to protect, so hiding
    /// them for it left a returning person with no way back to their records.
    static func resolve(hasCompletedOnboarding: Bool) -> OnbWelcomeAccount {
        hasCompletedOnboarding ? .hidden : .shown
    }
}
private struct LeaveWelcomeKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
private struct WelcomeAccountKey: EnvironmentKey { static let defaultValue: OnbWelcomeAccount = .shown }
extension EnvironmentValues {
    /// Welcome's "Have an account?" (hidden once a finished profile exists).
    var onbWelcomeAccount: OnbWelcomeAccount {
        get { self[WelcomeAccountKey.self] }
        set { self[WelcomeAccountKey.self] = newValue }
    }
    /// Closes onboarding when a returning person signs in from Welcome while a half-made profile
    /// was already active (the shell is then not re-entered by a sign-in change).
    var onbLeaveWelcome: () -> Void {
        get { self[LeaveWelcomeKey.self] }
        set { self[LeaveWelcomeKey.self] = newValue }
    }
}

/// Onboarding shell (standard §1.24). Welcome is the crafted house on the dusk/night page. Every
/// other step is a question on the plain canvas: a top bar (back `.icon`, the 3pt progress track),
/// the step title, the options, and one pinned `.primary`.
struct OnbRoot: View {
    @Bindable var flow: OnbFlow
    /// Inside the What's new sheet: no Welcome, the sheet's own chrome.
    var embedded = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ZStack {
            if flow.step == .welcome && !embedded {
                OnbWelcomeView(flow: flow)
                    .transition(.opacity)
            } else {
                steps
                    .transition(.opacity)
            }
        }
        .animation(OnbMotion.morph(reduce), value: flow.step == .welcome)
    }

    private var steps: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                stepContent
                    .id(flow.step)
                    .transition(OnbMotion.stepTransition(forward: flow.forward, reduce: reduce))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(LHCanvas())
    }

    // MARK: Top bar: back `.icon` + the progress track (never a skip; skips are per step)

    private var canGoBack: Bool {
        if flow.cohort == .new { return flow.index > 0 }
        return flow.index > 0
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            if canGoBack {
                Button { flow.back(OnbMotion.morph(reduce)) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(LHButton.icon)
                    .accessibilityLabel(String(localized: "Back", table: "ConversionPath"))
                    .accessibilityIdentifier("onb-back")
            } else {
                Color.clear.frame(width: LHMetrics.minTap, height: LHMetrics.minTap)
                    .accessibilityHidden(true)
            }
            OnbProgressTrack(total: flow.progressTotal, value: flow.progressValue)
            Color.clear.frame(width: LHMetrics.minTap, height: LHMetrics.minTap)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.top, embedded ? 12 : 4)
        .frame(minHeight: 52)
    }

    @ViewBuilder private var stepContent: some View {
        switch flow.step {
        case .goal: OnbGoalStep(flow: flow)
        case .calendar: OnbSourceStep(flow: flow, source: .calendar)
        case .who: OnbWhoStep(flow: flow)
        case .property: OnbPropertyStep(flow: flow)
        case .notify: OnbNotifyStep(flow: flow)
        case .wnHouse: OnbWhatsNewHouseStep(flow: flow)
        case .staked: OnbStakedStep(flow: flow)
        case .welcome: EmptyView()
        }
    }
}

// MARK: - 0 · Welcome: the crafted house on the dusk/night page (§H.5, §1.24)

/// The finished house, lit, at the Today hero size (H1; H3 at accessibility sizes, never hidden),
/// the Fraunces 34 headline, one line, one pinned `.primary` and package K's records footer under
/// it (P1 / P3 / P2; no sign-in in 2.2). The words scroll under the pinned
/// actions at large sizes; nothing is clamped.
struct OnbWelcomeView: View {
    let flow: OnbFlow
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.onbLeaveWelcome) private var leaveWelcome

    /// The number block on Today overlaps the frame by 44 (H4); here the headline sits just under
    /// the lot, inside the frame's empty foot (the art's ground line is at 0.92 of the frame).
    static let headlineOverlap: CGFloat = 20

    /// The fade above the pinned actions: 72 at accessibility sizes (one line is ~60pt), 24 otherwise.
    static func fadeHeight(accessibility: Bool) -> CGFloat { accessibility ? 72 : 24 }
    /// Space under the words so the scrolled-to-end last line sits clear of that fade.
    static func bottomClearance(accessibility: Bool) -> CGFloat { accessibility ? fadeHeight(accessibility: true) + 8 : 16 }

    static var headline: String { String(localized: "Every rental hour, counted.", table: "ConversionPath") }
    static var line: String {
        String(localized: "Pick a goal: 100, 500 or 750 hours. We spot rental work in your calendar. You confirm it, and the house shows how far you’ve come.", table: "ConversionPath")
    }

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        GeometryReader { g in
            let windowW = g.size.width + g.safeAreaInsets.leading + g.safeAreaInsets.trailing
            let windowH = g.size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom
            let ax = typeSize.isAccessibilitySize
            let side = Self.heroSide(windowWidth: windowW, windowHeight: windowH, accessibility: ax)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CraftHouseView(stage: .complete, windowsLit: true, side: side)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(Self.headline)
                            .lhDisplayFont(.display)
                            .foregroundStyle(colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("welcome.headline")
                        Text(Self.line)
                            .font(.body)
                            .foregroundStyle(colors.textSecondary)
                    }
                    .padding(.horizontal, LHMetrics.gutter)
                    .padding(.top, ax ? 8 : -Self.headlineOverlap)
                    // Scrolled to the end, the last line clears the fade above the pinned actions
                    // (72 at accessibility sizes, 24 otherwise), so no line ever rests under it.
                    .padding(.bottom, Self.bottomClearance(accessibility: ax))
                    .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(OnbDebugLaunch.scrollToBottom ? .bottom : .top)
            .safeAreaInset(edge: .bottom, spacing: 0) { actions(colors) }
        }
        .background(LHPage())
        // Package K: P3 while iCloud is checked (≤ 8 s), then P2 or P1.
        .task {
            await viewModel.identity.runWelcomeCheck(liveHours: { viewModel.timeEntries.reduce(0) { $0 + $1.hours } },
                                                     sync: viewModel.syncService)
        }
    }

    /// H1 at default to XXL, H3 at accessibility sizes; bands B and C a fixed 390 frame (H6).
    static func heroSide(windowWidth: CGFloat, windowHeight: CGFloat, accessibility: Bool) -> CGFloat {
        if windowWidth >= 600 { return min(CraftHeroSize.wideBandSide, CraftHeroSize.hero(windowWidth: windowWidth, windowHeight: windowHeight, accessibility: accessibility)) }
        return CraftHeroSize.hero(windowWidth: windowWidth, windowHeight: windowHeight, accessibility: accessibility)
    }

    private func actions(_ colors: AdaptiveColors) -> some View {
        VStack(spacing: 4) {
            Button(viewModel.welcomePrimaryTitle) {
                if case .found = viewModel.identity.welcome {
                    // Earlier records are already here: straight to Today.
                    viewModel.completeOnboardingWithEarlierRecords()
                    leaveWelcome()
                } else {
                    flow.start(OnbMotion.morph(reduce))
                }
            }
                .buttonStyle(LHButton.primary)
                .accessibilityIdentifier("onb-start")
            WelcomeRecordsFooter(state: viewModel.identity.welcome)
        }
        .padding(.horizontal, LHMetrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: LHMetrics.readingColumn)
        .frame(maxWidth: .infinity)
        // Words scrolling toward the pinned actions fade into the page's foot, never hard-cut.
        .background(alignment: .top) {
            // At accessibility sizes one line is ~60pt, so the fade grows to keep a soft edge.
            let fade = Self.fadeHeight(accessibility: typeSize.isAccessibilitySize)
            LinearGradient(stops: [.init(color: colors.pageBottom.opacity(0), location: 0),
                                   .init(color: colors.pageBottom, location: typeSize.isAccessibilitySize ? 0.3 : 0.35)],
                           startPoint: .top, endPoint: .bottom)
                .padding(.top, -fade)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

}

// MARK: - 6 · Staked: the last step, on the plain canvas

/// What onboarding found (or that the user is set up), with the 120pt house thumbnail of the
/// first rental, then one `.primary`: "Review N suggestions" (to the Inbox) or "Go to Today".
struct OnbStakedStep: View {
    @Bindable var flow: OnbFlow
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let headline = flow.stakedHeadline
        OnbStepScaffold(title: title(headline), titleIdentifier: identifier(headline)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    OnbHouseThumb(stage: .started, lit: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(flow.displayName)
                            .font(.headline)
                            .foregroundStyle(colors.textPrimary)
                        Text(OnbCopy.countLine(goal: flow.goal))
                            .font(.subheadline)
                            .fontDesign(.rounded)
                            .monospacedDigit()
                            .foregroundStyle(colors.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                switch headline {
                case .found(let found):
                    Text(OnbCopy.foundBody(count: found.count, goal: flow.goal))
                        .font(.body)
                        .foregroundStyle(colors.textSecondary)
                        .onAppear { flow.foundShown = true }
                default:
                    if case .nothingCountable(let count) = headline {
                        Text(OnbStakedHeadline.nothingCountableLine(count))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(colors.textPrimary)
                            .accessibilityIdentifier("staked-nothing-countable")
                    }
                    Text(OnbCopy.setUpBody(goal: flow.goal))
                        .font(.body)
                        .foregroundStyle(colors.textSecondary)
                    if case .lookingBack(let found) = headline {
                        Label(found.hours > 0
                              ? String(localized: "Looking back 90 days. \(found.hoursText) so far.", table: "ConversionPath")
                              : String(localized: "Looking back 90 days.", table: "ConversionPath"),
                              systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(colors.textSecondary)
                            .accessibilityIdentifier("staked-looking")
                    } else if headline == .nothingFound {
                        Text(String(localized: "Nothing in the last 90 days looked like rental work.", table: "ConversionPath"))
                            .font(.subheadline)
                            .foregroundStyle(colors.textSecondary)
                            .accessibilityIdentifier("staked-nothing")
                    }
                }
            }
            .animation(AppAnimation.standard, value: headline)
        } actions: {
            Button(headline.reviewCount.map { String(localized: "Review \(OnbFormat.suggestions($0))", table: "ConversionPath") }
                   ?? String(localized: "Go to Today", table: "ConversionPath")) {
                flow.leaveStaked()
            }
            .buttonStyle(LHButton.primary)
            .accessibilityIdentifier("onb-today")
        }
    }

    private func title(_ headline: OnbStakedHeadline) -> String {
        if case .found(let found) = headline { return OnbCopy.foundHeadline(found) }
        return OnbCopy.setUpHeadline(goal: flow.goal)
    }

    private func identifier(_ headline: OnbStakedHeadline) -> String {
        if case .found = headline { return "staked-found" }
        return "staked-setup"
    }
}
