import SwiftUI
import Combine
import AuthenticationServices

// MARK: - Entry points
//
// New users: `OnboardingView` replaces the 1.x sign-in wall and onboarding. Welcome leads with
// "Start building" (a profile on this iPhone); Sign in with Apple and "Restore earlier data" sit
// small under it for returning people, until the active profile has finished onboarding. Upgraders: `OnbWhatsNewSheet` over Today.

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
        .background(OnbColor.card.ignoresSafeArea())
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
            // A capture launch past Welcome needs a profile to write to.
            if (start ?? .welcome) != .welcome, !viewModel.isSignedIn {
                showOnboarding = true
                viewModel.continueWithoutAccount()
            }
            flow = made
            made.appeared()
        }
        .onDisappear {
            viewModel.suppressCelebrations = false
            OnbStatusBar.set(.default)
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
        OnbStatusBar.set(.default)
        withAnimation(.easeInOut(duration: 0.35)) { showOnboarding = false }
    }
}

/// Upgraders from 1.x: "Your hours now build a house", then the calendar and visit-end note.
struct OnbWhatsNewSheet: View {
    var onFinish: (_ openInbox: Bool) -> Void
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var flow: OnbFlow?

    var body: some View {
        Group {
            if let flow { OnbRoot(flow: flow, embedded: true).environment(\.onbDisplayTitles, true) } else { Color.clear }
        }
        .background(OnbColor.card.ignoresSafeArea())
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
        s.ensureProfile = { if !app.isSignedIn { app.continueWithoutAccount() } }
        s.signUpWithApple = { app.signUp() }
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

private struct BottomInsetKey: EnvironmentKey { static let defaultValue: CGFloat = 34 }
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
private struct DisplayTitlesKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var onbBottomInset: CGFloat {
        get { self[BottomInsetKey.self] }
        set { self[BottomInsetKey.self] = newValue }
    }
    /// Welcome's "Have an account?" row (hidden once a profile exists).
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
    /// Step titles in Fraunces display (What's new).
    var onbDisplayTitles: Bool {
        get { self[DisplayTitlesKey.self] }
        set { self[DisplayTitlesKey.self] = newValue }
    }
}

/// Onboarding shell. Welcome and Staked are full-bleed blueprint; steps 1–5 share one layout: a
/// blueprint band holding the lot scene, a sheet below with one question. The band and the
/// scene are ONE view whose frame morphs between steps.
struct OnbRoot: View {
    @Bindable var flow: OnbFlow
    var embedded = false               // inside the What's new sheet: no full-bleed, no status bar
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var keyboardUp = false

    private var bandFraction: CGFloat {
        if typeSize.isAccessibilitySize { return 0.22 }
        if typeSize >= .xxLarge { return 0.30 }
        if flow.step == .calendar { return embedded ? 0.22 : 0.33 }
        if flow.step == .goal { return 0.23 }
        return 0.38
    }

    var body: some View {
        GeometryReader { g in
            let top = embedded ? 0 : g.safeAreaInsets.top
            let bottom = embedded ? 0 : g.safeAreaInsets.bottom
            // Side insets (iPhone Duo folded: an 84 pt vertical status bar on the trailing edge).
            // Content stays inside them; the blueprint paper runs under them.
            let lead = embedded ? 0 : g.safeAreaInsets.leading
            let trail = embedded ? 0 : g.safeAreaInsets.trailing
            let H = g.size.height + top + bottom
            let W = g.size.width
            let hideHouse = flow.step == .welcome && !embedded && typeSize.isAccessibilitySize
            let full = flow.step.isFullBleed && !embedded
            let bandH = full ? H : (keyboardUp ? top + 50 + 96 : H * (embedded ? bandFraction + 0.02 : bandFraction))
            let scene = sceneFrame(W: W, H: H, top: top, bandH: bandH)

            ZStack(alignment: .top) {
                OnbScene(flow: flow, step: flow.step)
                    .dynamicTypeSize(.large)                  // decorative drawing; the sheet carries the readable copy
                    .frame(width: scene.width, height: scene.width)
                    .position(x: scene.midX, y: scene.midY)
                    // Accessibility sizes give the room to the words; the house returns on the steps.
                    .opacity(hideHouse ? 0 : 1)
                    .accessibilityHidden(hideHouse)

                if !full { chrome(top: top) }

                if !full {
                    sheet(bandH: bandH, H: H)
                        .transition(.opacity)
                }

                if flow.step == .welcome && !embedded {
                    OnbWelcomeContent(flow: flow, leadInset: lead, trailInset: trail, houseBottom: typeSize.isAccessibilitySize ? top + 12 : scene.maxY - scene.width * 0.08)
                        .frame(width: W, height: H)
                        .transition(.opacity)
                }
                if flow.step == .staked && !embedded {
                    OnbStakedContent(flow: flow, sceneBottom: scene.maxY)
                        .frame(width: W, height: H)
                        .transition(.opacity)
                }
            }
            .frame(width: W, height: H)
            // Paper and card are backgrounds so the wider paper never changes the layout width.
            .background(alignment: .top) {
                HouseBlueprintPaper()
                    .frame(width: W + lead + trail, height: bandH)
                    .clipped()
                    .offset(x: (trail - lead) / 2)
                    .accessibilityHidden(true)
            }
            .background(OnbColor.card)
            .environment(\.onbBottomInset, max(bottom, 16))
            .offset(y: -top)
        }
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: flow.stakeDropped)
        .onAppear { if !embedded { OnbStatusBar.set(.lightContent) } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(reduce ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.9)) { keyboardUp = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(reduce ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.9)) { keyboardUp = false }
        }
    }

    // MARK: Layout

    private func sceneFrame(W: CGFloat, H: CGFloat, top: CGFloat, bandH: CGFloat) -> CGRect {
        switch flow.step {
        case .welcome where !embedded:
            let s = min(W * 0.92, H * (typeSize >= .xLarge ? 0.30 : (H < 760 ? 0.28 : 0.42)))
            return CGRect(x: (W - s) / 2, y: top + 4, width: s, height: s)
        case .staked where !embedded:
            let s = min(W * 0.96, H * 0.45)
            return CGRect(x: (W - s) / 2, y: top + 18, width: s, height: s)
        default:
            let chromeH: CGFloat = embedded ? 34 : 50
            let avail = bandH - 26 - (top + chromeH)
            let s = max(0, min(W * 1.0, avail / 0.84))
            // The render's content sits between y 0.10 (ridge) and 0.93 (lot corner).
            return CGRect(x: (W - s) / 2, y: top + chromeH - 0.09 * s, width: s, height: s)
        }
    }

    // MARK: Progress dimension line + back chevron (in the band, never a skip)

    private func chrome(top: CGFloat) -> some View {
        VStack(spacing: 2) {
            OnbDimensionLine(total: flow.progressTotal, value: flow.progressValue)
                .frame(height: 14)
                .padding(.horizontal, 24)
                .padding(.top, top + (embedded ? 14 : 6))
                .animation(OnbMotion.progress(reduce), value: flow.progressValue)
            HStack {
                if flow.index > 0 {
                    Button { flow.back(OnbMotion.morph(reduce)) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(HouseTokens.onHeroPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(OnbPressable())
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("onb-back")
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: The sheet (one question, one primary, one link)

    private func sheet(bandH: CGFloat, H: CGFloat) -> some View {
        let overlap: CGFloat = 22
        return ZStack {
            stepContent
                .id(flow.step)
                .transition(reduce ? .opacity : .asymmetric(
                    insertion: .offset(x: flow.forward ? 36 : -36).combined(with: .opacity),
                    removal: .offset(x: flow.forward ? -36 : 36).combined(with: .opacity)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OnbColor.card, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .frame(height: max(0, H - bandH + overlap))
        // Clipped to the sheet's own shape: scrolled content never shows over the blueprint band.
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder private var stepContent: some View {
        switch flow.step {
        case .goal: OnbGoalStep(flow: flow)
        case .calendar: OnbSourceStep(flow: flow, source: .calendar)
        case .who: OnbWhoStep(flow: flow)
        case .property: OnbPropertyStep(flow: flow)
        case .notify: OnbNotifyStep(flow: flow)
        case .wnHouse: OnbWhatsNewHouseStep(flow: flow)
        case .welcome, .staked: EmptyView()
        }
    }
}

// MARK: - 0 · Welcome (full-bleed blueprint)

struct OnbWelcomeContent: View {
    let flow: OnbFlow
    /// Side safe-area insets the scrims run under, so the paper has no seam beside the content.
    var leadInset: CGFloat = 0
    var trailInset: CGFloat = 0
    var houseBottom: CGFloat
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.onbBottomInset) private var bottomInset
    @Environment(\.onbWelcomeAccount) private var account
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.onbLeaveWelcome) private var leaveWelcome
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var restorable: [DiscoveredProfile] = []
    @State private var cloudProblem = false
    @State private var isRetrying = false
    @State private var showRestore = false
    @State private var signInError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: max(0, houseBottom))
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Know where you stand on your hours.")
                        .lhDisplayFont(.display)
                        .foregroundStyle(HouseTokens.onHeroPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("Pick the hour target you’re aiming for: 100, 500 or 750. We find the hours you already spend on your rentals. You confirm them, and the house shows how close you are.")
                        .font(.body)
                        .foregroundStyle(HouseTokens.onHeroSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                    // One row when it fits; otherwise a two-column grid; never clipped.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { chips }
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                            GridRow { chip("100h", "Foundation"); chip("500h", "Roof") }
                            GridRow { chip("750h", "Keys") }
                        }
                        VStack(alignment: .leading, spacing: 8) { chips }
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 52)          // clears both scrims (44 pt fade + 40 pt button scrim) so the last chip stays readable
                    // Accessibility sizes: only "Get started" stays pinned; the returning-user rows
                    // scroll with the words, so the headline gets the room and nothing is cut off.
                    if typeSize.isAccessibilitySize {
                        VStack(spacing: 10) { secondaryRows }
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 28)
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Words that scroll toward the pinned button fade out before they reach it.
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [HouseTokens.blueprintDeep.opacity(0), HouseTokens.blueprintDeep], startPoint: .top, endPoint: .bottom)
                    .frame(height: 44)
                    .padding(.horizontal, -24)
                    .padding(.leading, -leadInset)
                    .padding(.trailing, -trailInset)
                    .allowsHitTesting(false)
            }
            VStack(spacing: 10) {
                Button("Get started") { flow.start(OnbMotion.morph(reduce)) }
                    .buttonStyle(OnbHeroPill())
                    .accessibilityIdentifier("onb-start")
                if !typeSize.isAccessibilitySize { secondaryRows }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, bottomInset + 8)
            .background(alignment: .top) {
                LinearGradient(colors: [HouseTokens.blueprintDeep.opacity(0), HouseTokens.blueprintDeep.opacity(0.85)], startPoint: .top, endPoint: .init(x: 0.5, y: 0.25))
                    .padding(.top, -40)
                    .padding(.horizontal, -24)
                    .padding(.leading, -leadInset)
                    .padding(.trailing, -trailInset)
                    .allowsHitTesting(false)
            }
        }
        .task {
            guard account == .shown else { return }
            await search(announce: true)
        }
        .sheet(isPresented: $showRestore) {
            ProfileRestoreSheet(
                profiles: restorable, context: .welcome,
                cloudProblem: cloudProblem, isRetrying: isRetrying,
                onRetry: {
                    Task {
                        isRetrying = true
                        await search(announce: false)
                        isRetrying = false
                    }
                }
            ) { profile in
                showRestore = false
                viewModel.switchToProfile(profile)
                // Sign-out and sign-in land in one pass, so the shell never sees the change. When
                // Welcome was held open by an unfinished profile, close it ourselves.
                if viewModel.activeProfileCompletedOnboarding { leaveWelcome() }
            }
            .environmentObject(viewModel)
        }
        .alert("Sign In Failed", isPresented: $signInError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(AppleSignInFlow.failureMessage)
        }
    }

    /// Returning-user rows under "Get started": Sign in with Apple, restore, and the privacy line.
    @ViewBuilder private var secondaryRows: some View {
                if account == .shown {
                    // Apple's own button (App Review): white on the blueprint, small, under the pill.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { accountLead; appleButton }
                        VStack(spacing: 8) { accountLead; appleButton }
                    }
                    .padding(.top, 4)
                    if !restorable.isEmpty || cloudProblem {
                        Button { showRestore = true } label: {
                            if restorable.count <= 1 { Text("Restore earlier records") } else { Text("Restore earlier records (\(restorable.count))") }
                        }
                            .buttonStyle(OnbLink(color: HouseTokens.onHeroPrimary))
                            .font(.footnote.weight(.semibold))
                            // Wraps to a second line at large sizes; never truncates, never overlaps.
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("welcome.restoreEarlierData")
                    }
                }
                Text("Your records stay on your iPhone and in your iCloud.")
                    .font(.footnote)
                    .foregroundStyle(HouseTokens.onHeroSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
    }

    private func search(announce: Bool) async {
        let found = await viewModel.discoverRestorable()
        restorable = found.profiles
        cloudProblem = found.cloudProblem
        guard announce, !found.profiles.isEmpty || found.cloudProblem else { return }
        let kinds = found.profiles.map(\.analyticsKind)
        Analytics.restoreOffered(
            emailCount: kinds.filter { $0 == "email" }.count,
            localCount: kinds.filter { $0 == "local" }.count,
            appleCount: kinds.filter { $0 == "apple" }.count,
            cloudProblem: found.cloudProblem
        )
    }

    private var accountLead: some View {
        Text("Been here before?")
            .font(.footnote)
            .foregroundStyle(HouseTokens.onHeroSecondary)
    }

    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            AppleSignInFlow.configure(request)
        } onCompletion: { result in
            switch AppleSignInFlow.complete(result) {
            case .signedIn(let isNewUser):
                if isNewUser {
                    flow.signUpWithApple(OnbMotion.morph(reduce))
                } else {
                    // Returning: their profile already finished setup, so the app opens on Today.
                    viewModel.adoptReturningAppleSignIn()
                    leaveWelcome()
                }
            case .cancelled: break
            case .failed: signInError = true
            }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(width: 168, height: 36)
        .clipShape(Capsule())
        .accessibilityIdentifier("welcome.signInWithApple")
    }

    @ViewBuilder private var chips: some View {
        chip("100h", "Foundation")
        chip("500h", "Roof")
        chip("750h", "Keys")
    }

    private func chip(_ h: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(h).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(HouseTokens.onHeroPrimary)
            Text(label).font(.subheadline).foregroundStyle(HouseTokens.onHeroSecondary)
        }
        // Accessibility sizes: a chip wraps inside the screen instead of running past it (a chip
        // wider than the screen widened the whole page and pushed the headline off the edge).
        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
        .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .overlay(Capsule().strokeBorder(HouseTokens.drafting.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 6 · Staked (full-bleed blueprint)

struct OnbStakedContent: View {
    let flow: OnbFlow
    var sceneBottom: CGFloat
    @Environment(\.onbBottomInset) private var bottomInset

    var body: some View {
        let headline = flow.stakedHeadline
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: max(0, sceneBottom - 6))
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    switch headline {
                    case .found(let found):
                        // The aha leads: what we found, then that it is theirs to confirm.
                        Text(String(localized: "\(flow.displayName) is staked")).onbDrafting(HouseTokens.drafting)
                        Text(OnbCopy.foundHeadline(found))
                            .lhDisplayFont(.display)
                            .foregroundStyle(HouseTokens.onHeroPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("staked-found")
                            .onAppear { flow.foundShown = true }
                        Text(OnbCopy.foundBody(count: found.count, goal: flow.goal))
                            .font(.body)
                            .foregroundStyle(HouseTokens.onHeroSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    default:
                        Text(OnbCopy.countLine(goal: flow.goal)).onbDrafting(HouseTokens.drafting)
                        Text(OnbCopy.setUpHeadline(goal: flow.goal))
                            .lhDisplayFont(.display)
                            .foregroundStyle(HouseTokens.onHeroPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("staked-setup")
                        if case .nothingCountable(let count) = headline {
                            // Right under the headline, so it's seen at every text size.
                            // A sentence, so body text (mono caps are for short eyebrows only).
                            Text(OnbStakedHeadline.nothingCountableLine(count))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(HouseTokens.onHeroPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 10)
                                .accessibilityIdentifier("staked-nothing-countable")
                        }
                        Text(OnbCopy.setUpBody(goal: flow.goal))
                            .font(.body)
                            .foregroundStyle(HouseTokens.onHeroSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                        if case .lookingBack(let found) = headline {
                            Text(found.hours > 0 ? String(localized: "Looking back 90 days · \(found.hoursText) so far") : String(localized: "Looking back 90 days"))
                                .onbDrafting(HouseTokens.drafting)
                                .padding(.top, 16)
                                .accessibilityIdentifier("staked-looking")
                        } else if headline == .nothingFound {
                            Text("Nothing in the last 90 days looked like rental work")
                                .onbDrafting(HouseTokens.drafting)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 16)
                                .accessibilityIdentifier("staked-nothing")
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)          // clears the scrim above the pinned button
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Words that scroll toward the pinned button fade out before they reach it.
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [HouseTokens.blueprintDeep.opacity(0), HouseTokens.blueprintDeep], startPoint: .top, endPoint: .bottom)
                    .frame(height: 44)
                    .allowsHitTesting(false)
            }
            Button(headline.reviewCount.map { String(localized: "Review \(OnbFormat.suggestions($0))") } ?? String(localized: "Go to Today")) {
                flow.leaveStaked()
            }
            .buttonStyle(OnbHeroPill())
            .accessibilityIdentifier("onb-today")
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, bottomInset + 8)
            .background(alignment: .top) {
                // Words scrolling under the pinned button fade out instead of running under it.
                LinearGradient(colors: [HouseTokens.blueprintDeep.opacity(0), HouseTokens.blueprintDeep.opacity(0.85)], startPoint: .top, endPoint: .init(x: 0.5, y: 0.25))
                    .padding(.top, -40)
                    .allowsHitTesting(false)
            }
        }
        .animation(AppAnimation.standard, value: headline)
    }
}
