import SwiftUI
import Combine
import AuthenticationServices

// MARK: - Entry points
//
// New users: `OnboardingView` replaces the 1.x sign-in wall and onboarding. Welcome leads with
// "Start building" (a profile on this iPhone); Sign in with Apple and "Restore earlier data" sit
// small under it for returning people. Upgraders: `OnbWhatsNewSheet` over Today.

struct OnboardingView: View {
    @Binding var showOnboarding: Bool
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var flow: OnbFlow?

    var body: some View {
        Group {
            if let flow {
                OnbRoot(flow: flow)
                    .environment(\.onbWelcomeAccount, viewModel.isSignedIn ? .hidden : .shown)
            } else {
                Color.clear
            }
        }
        .background(OnbColor.card.ignoresSafeArea())
        .onAppear {
            guard flow == nil else { return }
            viewModel.suppressCelebrations = true
            let start = OnbDebugLaunch.startStep
            let made = OnbFlow(cohort: .new, services: .live(app: viewModel, environment: .current) { completion in
                finish(completion)
            }, startAt: start)
            OnbDebugLaunch.apply(to: made)
            OnbBackfill.flowStarted()
            // A capture launch past Welcome needs a profile to write to.
            if (start ?? .welcome) != .welcome, !viewModel.isSignedIn { viewModel.continueWithoutAccount() }
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
            made.upgradeHours = viewModel.houseCountableHours()
            made.upgradeGoal = viewModel.houseGoal
            made.goal = viewModel.houseGoal == .reps750 ? .reps750 : (viewModel.houseGoal == .mp500 ? .mp500 : .mp100)
            OnbDebugLaunch.apply(to: made)
            flow = made
            made.appeared()
        }
    }
}

// MARK: - Live wiring

extension OnbServices {
    /// The real app: profile, goal, tax profile, property, calendar + 90-day look-back,
    /// visit-end consent, analytics.
    static func live(app: AppViewModel, environment: CaptureSetupEnvironment, complete: @escaping (OnbCompletion) -> Void) -> OnbServices {
        var s = OnbServices()
        s.ensureProfile = { if !app.isSignedIn { app.continueWithoutAccount() } }
        s.saveGoal = { goal in GoalManager.shared.setGoalChoice(goal.goalChoice) }
        s.saveWho = { who in TaxProfileManager.shared.spouseTracking = (who == .both) }
        s.addProperty = { name, address in
            app.addProperty(name: name, address: address, type: .ltr)
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
enum OnbWelcomeAccount { case shown, hidden }
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
            let H = g.size.height + top + bottom
            let W = g.size.width
            let full = flow.step.isFullBleed && !embedded
            let bandH = full ? H : (keyboardUp ? top + 50 + 96 : H * (embedded ? bandFraction + 0.02 : bandFraction))
            let scene = sceneFrame(W: W, H: H, top: top, bandH: bandH)

            ZStack(alignment: .top) {
                OnbColor.card

                HouseBlueprintPaper()
                    .frame(width: W, height: bandH)
                    .clipped()
                    .accessibilityHidden(true)

                OnbScene(flow: flow, step: flow.step)
                    .dynamicTypeSize(.large)                  // decorative drawing; the sheet carries the readable copy
                    .frame(width: scene.width, height: scene.width)
                    .position(x: scene.midX, y: scene.midY)

                if !full { chrome(top: top) }

                if !full {
                    sheet(bandH: bandH, H: H)
                        .transition(.opacity)
                }

                if flow.step == .welcome && !embedded {
                    OnbWelcomeContent(flow: flow, houseBottom: scene.maxY - scene.width * 0.08)
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
            let s = min(W * 0.92, H * (typeSize >= .xLarge ? 0.30 : 0.42))
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
    var houseBottom: CGFloat
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.onbBottomInset) private var bottomInset
    @Environment(\.onbWelcomeAccount) private var account
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var restorable: [DiscoveredProfile] = []
    @State private var showRestore = false
    @State private var signInError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: max(0, houseBottom))
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Every hour builds the house.")
                        .lhDisplayFont(.display)
                        .foregroundStyle(HouseTokens.onHeroPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("We find the hours you already spend on your rentals. Each one you confirm adds to the house.")
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
                    .padding(.bottom, 28)          // clears the scrim above the pinned buttons
                }
                .padding(.horizontal, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Words that scroll toward the pinned button fade out before they reach it.
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [HouseTokens.blueprintDeep.opacity(0), HouseTokens.blueprintDeep], startPoint: .top, endPoint: .bottom)
                    .frame(height: 44)
                    .allowsHitTesting(false)
            }
            VStack(spacing: 10) {
                Button("Start building") { flow.start(OnbMotion.morph(reduce)) }
                    .buttonStyle(OnbHeroPill())
                    .accessibilityIdentifier("onb-start")
                if account == .shown {
                    // Apple's own button (App Review): white on the blueprint, small, under the pill.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { accountLead; appleButton }
                        VStack(spacing: 8) { accountLead; appleButton }
                    }
                    .padding(.top, 4)
                    if !restorable.isEmpty {
                        Button(restorable.count == 1 ? "Restore earlier data" : "Restore earlier data (\(restorable.count))") { showRestore = true }
                            .buttonStyle(OnbLink(color: HouseTokens.onHeroPrimary))
                            .font(.footnote.weight(.semibold))
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
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, bottomInset + 8)
            .background(alignment: .top) {
                LinearGradient(colors: [HouseTokens.blueprintDeep.opacity(0), HouseTokens.blueprintDeep.opacity(0.85)], startPoint: .top, endPoint: .init(x: 0.5, y: 0.25))
                    .padding(.top, -40)
                    .allowsHitTesting(false)
            }
        }
        .task {
            guard account == .shown else { return }
            restorable = await viewModel.discoverRestorableProfiles()
        }
        .sheet(isPresented: $showRestore) {
            ProfileRestoreSheet(profiles: restorable, context: .welcome) { profile in
                showRestore = false
                viewModel.switchToProfile(profile)
            }
            .environmentObject(viewModel)
        }
        .alert("Sign In Failed", isPresented: $signInError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(AppleSignInFlow.failureMessage)
        }
    }

    private var accountLead: some View {
        Text("Have an account?")
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
                    viewModel.signUp()
                    flow.next(OnbMotion.morph(reduce))
                } else {
                    // Returning: their profile already finished setup, so the app opens on Today.
                    viewModel.signIn()
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
        .lineLimit(1)
        .fixedSize()
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
                        Text("\(flow.displayName) is staked").onbDrafting(HouseTokens.drafting)
                        Text("\(found.hoursText) found")
                            .lhDisplayFont(.display)
                            .foregroundStyle(HouseTokens.onHeroPrimary)
                            .padding(.top, 6)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("staked-found")
                            .onAppear { flow.foundShown = true }
                        Text("From \(found.count) calendar \(found.count == 1 ? "event" : "events") in the last 90 days. Confirm the ones that were rental work.")
                            .font(.body)
                            .foregroundStyle(HouseTokens.onHeroSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                        Text("\(OnbCopy.countLine(goal: flow.goal)) counted so far").onbDrafting(HouseTokens.drafting).padding(.top, 14)
                    default:
                        Text(OnbCopy.countLine(goal: flow.goal)).onbDrafting(HouseTokens.drafting)
                        Text("Your house is staked.")
                            .lhDisplayFont(.display)
                            .foregroundStyle(HouseTokens.onHeroPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                            .accessibilityAddTraits(.isHeader)
                        if case .nothingCountable(let count) = headline {
                            // Right under the headline, so it's seen at every text size.
                            Text(OnbStakedHeadline.nothingCountableLine(count))
                                .onbDrafting(HouseTokens.drafting)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 10)
                                .accessibilityIdentifier("staked-nothing-countable")
                        }
                        Text(flow.goal == .record
                             ? "Every hour you confirm from here is saved to your record."
                             : "Every hour you confirm from here adds to your house.")
                            .font(.body)
                            .foregroundStyle(HouseTokens.onHeroSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                        if case .lookingBack(let found) = headline {
                            Text(found.hours > 0 ? "Looking back 90 days · \(found.hoursText) so far" : "Looking back 90 days")
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
            Button(headline.reviewCount.map { "Review \(OnbFormat.suggestions($0))" } ?? "Go to Today") {
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
