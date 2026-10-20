import SwiftUI
import StoreKit
import Combine

extension Notification.Name {
    static let switchToTab = Notification.Name("switchToTab")
    static let openAddProperty = Notification.Name("openAddProperty")
    static let switchToPropertiesAndOpenAddProperty = Notification.Name("switchToPropertiesAndOpenAddProperty")
}

/// 1.x first-run coach-mark flags. The coach mark is gone (2.0 onboarding ends on Today with
/// no overlay); the keys stay so profile reset and the legacy fixture keep clearing them.
enum GuidedOnboardingStore {
    static let completedKey = "hasCompletedGuidedOnboarding"
    static let skippedKey = "hasSkippedGuidedOnboarding"

    static func skip() {
        UserDefaults.standard.set(true, forKey: UserScope.key(skippedKey))
    }
}

private struct AppTabBarHiddenPreferenceKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func hidesAppTabBar(_ hidden: Bool = true) -> some View {
        preference(key: AppTabBarHiddenPreferenceKey.self, value: hidden)
    }
}

struct ContentView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @ObservedObject private var ratingPrompt = RatingPromptCoordinator.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var goalManager = GoalManager.shared
    @State private var selectedTab = Self.initialTabFromLaunchArguments()
    @State private var showOnboarding = false
    @State private var isCustomTabBarHidden = false
    /// WP-L: background work the shell surfaces (look-back reveal, export ready banner).
    @ObservedObject private var houseEvents = TodayHouseEvents.shared
    @ObservedObject private var exportJob = ExportJob.shared
    @State private var shellBackfillReveal: HouseBackfillReveal?
    @State private var exportShare: ExportShareItem?
    /// WP3: the suggestion inbox (tab content + badge).
    @StateObject private var inboxModel = InboxViewModel.live(app: AppModelHost.shared.viewModel)
    /// WP3: one-time "What's new" auto-capture opt-in for people updating from 1.x.
    @State private var showCaptureWhatsNew = false

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private static func initialTabFromLaunchArguments() -> Int {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-LHInitialTab"),
              args.indices.contains(index + 1),
              let tab = Int(args[index + 1]) else {
            return 0
        }
        return min(max(tab, 0), ShellTab.maxIndex)
    }

    var body: some View {
        Group {
            // WP-L: no launch splash or loading screen in any path. Today renders at once from
            // local data; only the hours wait on the first iCloud pull (DashboardView).
            if !viewModel.isSignedIn || showOnboarding {
                // 2.0: Welcome replaces the sign-in wall; "Start building" makes a profile on
                // this iPhone and the same flow carries on (one branch, one view identity).
                OnboardingView(showOnboarding: $showOnboarding)
            } else {
                mainContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.background)
        .overlay {
            if let celebration = viewModel.activeCelebration {
                CelebrationOverlayView(type: celebration) {
                    viewModel.activeCelebration = nil
                }
                .transition(.opacity)
                .zIndex(999)
            }
        }
        .overlay(alignment: .top) {
            if let message = viewModel.persistenceError {
                LHErrorBanner(message: message) {
                    animate(AppAnimation.reveal) { viewModel.persistenceError = nil }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1000)
            }
        }
        .lhMotion(AppAnimation.reveal, value: viewModel.persistenceError)
        .environmentObject(CategoryManager.shared)
        .environmentObject(goalManager)
        .onAppear {
            viewModel.checkSignInState()
            checkPostSignInFlow()
            applyPendingAppIntentNavigationIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                applyPendingAppIntentNavigationIfNeeded()
            }
        }
        .onOpenURL { url in
            applyDeepLink(url)
        }
        .onChange(of: showOnboarding) { _, isShowing in
            if !isShowing, CaptureSetupHandoff.openInboxAfterOnboarding {
                CaptureSetupHandoff.openInboxAfterOnboarding = false
                selectedTab = ShellTab.inboxIndex
            }
        }
        .onChange(of: viewModel.isSignedIn) { _, newValue in
            if newValue {
                checkPostSignInFlow()
            } else {
                // Signed out: straight to sign-in (no splash).
                showOnboarding = false
            }
        }
        .onChange(of: ratingPrompt.pendingRequest) { _, trigger in
            guard trigger != nil else { return }
            // Apple's own prompt only. Wait a beat so it never lands mid-transition
            // (e.g. while the share sheet is closing).
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                requestReview()
                ratingPrompt.pendingRequest = nil
            }
        }
    }

    /// Single entry point for post-sign-in UI flow. Prevents duplicate triggers
    /// from both onAppear and onChange(of: isSignedIn).
    private func checkPostSignInFlow() {
        guard viewModel.isSignedIn, !showOnboarding else { return }
        // Pro is offered only at the moment of need (PaywallView(context:)), never on launch.
        if !UserDefaults.standard.bool(forKey: UserScope.key("hasCompletedOnboarding")) {
            showOnboarding = true
        }
    }

    /// Shows the 2.0 What's new once to people who finished 1.x onboarding. Never on top of
    /// onboarding.
    private func presentCaptureWhatsNewIfNeeded() {
        guard !showOnboarding else { return }
        let completed = UserDefaults.standard.bool(forKey: UserScope.key("hasCompletedOnboarding"))
        guard CaptureOptIn.shouldShowWhatsNew(hasCompletedOnboarding: completed) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showCaptureWhatsNew = true
        }
    }

    private func applyPendingAppIntentNavigationIfNeeded() {
        guard let rawDestination = UserDefaults.standard.string(forKey: AppIntentNavigationRequest.pendingDestinationKey),
              let destination = LandlordHoursIntentDestination(rawValue: rawDestination) else {
            return
        }

        UserDefaults.standard.removeObject(forKey: AppIntentNavigationRequest.pendingDestinationKey)
        selectedTab = destination.tabIndex
    }

    private func applyDeepLink(_ url: URL) {
        guard url.scheme == "landlordhours" else { return }

        let destinationValue: String?
        if url.host == "open" {
            destinationValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "destination" })?
                .value
        } else {
            destinationValue = url.host
        }

        guard let destinationValue,
              let destination = LandlordHoursIntentDestination(rawValue: destinationValue) else {
            selectedTab = 0
            return
        }

        selectedTab = destination.tabIndex
    }

    // MARK: - Main Content with Tab Bar
    var mainContent: some View {
        ZStack(alignment: .bottom) {
            // WP-L: the export banner sits in its own row under the tab content (not over it), so
            // the page ends above it and nothing is covered, scrolled or not.
            VStack(spacing: 0) {
                selectedTabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let banner = exportBanner {
                    ExportReadyBanner(
                        kind: banner,
                        onOpen: { exportShare = exportJob.takeReadyForSharing() },
                        onDismiss: { exportJob.dismissBanner() }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
                .safeAreaInset(edge: .bottom) {
                    if !isCustomTabBarHidden {
                        // With the banner showing, it takes the room the scroll content used to
                        // fade under; the bar keeps its own space.
                        Color.clear
                            .frame(height: exportBanner == nil ? AppSpacing.floatingTabBarReservedHeight : Self.tabBarHeight + 16)
                            .accessibilityHidden(true)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .switchToTab)) { notification in
                    if let tab = notification.object as? Int {
                        selectedTab = tab
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .switchToPropertiesAndOpenAddProperty)) { _ in
                    selectedTab = 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        NotificationCenter.default.post(name: .openAddProperty, object: nil)
                    }
                }

            if !isCustomTabBarHidden {
                tabBarUnderlay

                customTabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // WP3: Undo for the last inbox action, just above the tab bar.
            if let toast = inboxModel.toast, !isCustomTabBarHidden {
                InboxUndoToast(toast: toast) { inboxModel.undo() }
                    .padding(.horizontal, 16)
                    .padding(.bottom, Self.tabBarHeight + 8 + 12)
                    // Slides only: an opacity fade would let row text show through mid-transition.
                    .transition(reduceMotion ? .identity : .move(edge: .bottom))
                    .zIndex(5)
            }

            // Floating timer banner (visible on all tabs except Track)
            if viewModel.isTimerRunning && selectedTab != 2 && !isCustomTabBarHidden {
                FloatingTimerBanner(viewModel: viewModel) {
                    selectedTab = 2
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 52) // above tab bar
            }

        }
        .onAppear {
            #if DEBUG
            InboxDebugSeed.applyIfNeeded(app: viewModel)
            #endif
            inboxModel.reload()
            presentCaptureWhatsNewIfNeeded()
        }
        .onChange(of: selectedTab) { _, _ in
            inboxModel.dismissToast()
            inboxModel.reload()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { inboxModel.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .captureSuggestionsDidChange)) { _ in
            inboxModel.reload(animated: true)
        }
        .lhMotion(AppAnimation.reveal, value: exportBanner)
        // WP-L: the look-back finished in the background. Today plays the house reveal itself;
        // on any other tab the shell plays it once, when no sheet is in the way.
        .onChange(of: houseEvents.pendingBackfill) { _, _ in scheduleShellBackfillReveal() }
        .onChange(of: selectedTab) { _, _ in scheduleShellBackfillReveal() }
        .onChange(of: inboxModel.sheetSuggestion) { _, _ in scheduleShellBackfillReveal() }
        .fullScreenCover(item: $shellBackfillReveal) { reveal in
            BackfillRevealView(
                foundHours: reveal.foundHours,
                suggestionCount: reveal.suggestionCount,
                confirmedHours: 0,
                artScheme: colorScheme,
                onReview: {
                    shellBackfillReveal = nil
                    selectedTab = ShellTab.inboxIndex
                },
                onSkip: { shellBackfillReveal = nil }
            )
        }
        .sheet(item: $exportShare) { item in
            // The report is a PDF plus a spreadsheet: share both.
            ActivityShareSheet(items: [ExportShareFile(url: item.pdfURL), ExportShareFile(url: item.csvURL)]) { completed in
                exportShare = nil
                if completed { viewModel.exportShared(format: .pdf) }
            }
            .presentationDetents([.medium, .large])
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showCaptureWhatsNew, onDismiss: {
            // Swiping the intro away is an answer too: it never shows again, and nothing turns on.
            CaptureOptIn.markWhatsNewSeen()
            if OnbBackfill.flowActive { OnbBackfill.flowEnded(foundShown: false) }
            inboxModel.reload()
        }) {
            OnbWhatsNewSheet { openInbox in
                showCaptureWhatsNew = false
                if openInbox { selectedTab = ShellTab.inboxIndex }
            }
            .environmentObject(viewModel)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onPreferenceChange(AppTabBarHiddenPreferenceKey.self) { hidden in
            animate(AppAnimation.quick) {
                isCustomTabBarHidden = hidden
            }
        }
    }

    /// The export banner, hidden when the ready report no longer matches the records.
    private var exportBanner: ExportJob.Banner? {
        guard exportJob.banner != nil else { return nil }
        let fingerprint = exportJob.resultYear.map { ExportFingerprint.current(app: viewModel, year: $0) }
        return exportJob.banner(currentFingerprint: fingerprint)
    }

    /// Plays the look-back reveal from the shell when Today isn't on screen to play it.
    private func scheduleShellBackfillReveal() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard selectedTab != ShellTab.todayIndex,
                  shellBackfillReveal == nil,
                  inboxModel.sheetSuggestion == nil,
                  !showCaptureWhatsNew,
                  !OnbBackfill.flowActive,
                  exportShare == nil,
                  let reveal = houseEvents.pendingBackfill else { return }
            houseEvents.markBackfillShown()
            shellBackfillReveal = reveal
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case 0:
            DashboardView(inbox: inboxModel)
        case 1:
            PropertiesView()
        case 2:
            TimeLogView()
        case 3:
            ReportsView()
        case 4:
            SettingsView()
        case ShellTab.inboxIndex:
            InboxView(model: inboxModel)
        case ShellTab.recordsIndex:
            HistoryView()
        default:
            DashboardView(inbox: inboxModel)
        }
    }

    /// 2.0 shell: four tabs in one floating glass capsule (Today, Inbox, Records, Properties) and a
    /// separate round + (log time) beside it. docs/design/2.0-hifi-reference-spec.md §l.
    private var customTabBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    tabBarButton(tab)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .frame(height: Self.tabBarHeight)
            .floatingGlass(in: Capsule(), colors: colors, colorScheme: colorScheme)

            logTimeButton
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private static let tabBarHeight: CGFloat = 62

    private var logTimeButton: some View {
        let isSelected = selectedTab == ShellTab.logTimeIndex
        return Button {
            animate(AppAnimation.quick) {
                selectedTab = ShellTab.logTimeIndex
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isSelected ? colors.onAction : colors.action)
                .frame(width: Self.tabBarHeight, height: Self.tabBarHeight)
                .background(
                    Circle().fill(isSelected ? colors.action : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.lhPressable)
        .floatingGlass(in: Circle(), colors: colors, colorScheme: colorScheme)
        .accessibilityLabel("Log time")
        .accessibilityIdentifier("tab.logTime")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var tabBarUnderlay: some View {
        let dockOpacity = colorScheme == .dark ? 0.96 : 0.92

        return LinearGradient(
            stops: [
                .init(color: colors.background.opacity(0.0), location: 0.0),
                .init(color: colors.background.opacity(dockOpacity), location: 0.42),
                .init(color: colors.background.opacity(1.0), location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        // Starts at the bar's top edge (bar + its 8pt bottom padding), not above it.
        .frame(height: Self.tabBarHeight + 8)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The tab that shows as current. Reports and Settings open from Today's header, so Today stays
    /// highlighted there; Log time highlights the + instead of a tab.
    private var highlightedTab: AppTab? {
        switch selectedTab {
        case ShellTab.reportsIndex, ShellTab.settingsIndex: return .today
        case ShellTab.logTimeIndex: return nil
        default: return AppTab.allCases.first { $0.shellIndex == selectedTab } ?? .today
        }
    }

    private func tabBarButton(_ tab: AppTab) -> some View {
        let isSelected = highlightedTab == tab
        // Full-strength secondary text: lighter inactive labels measured under 4.5:1 on the glass.
        let inactiveColor = colors.textSecondary

        return Button {
            animate(AppAnimation.quick) {
                selectedTab = tab.shellIndex
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? tab.selectedSymbol : tab.symbol)
                    .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                    .frame(height: 24)
                    .overlay(alignment: .topTrailing) {
                        if tab == .inbox, inboxModel.badgeCount > 0 {
                            tabBadge(inboxModel.badgeCount)
                                .offset(x: 14, y: -6)
                        }
                    }
                Text(tab.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? colors.actionText : inactiveColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Capsule()
                    .fill(isSelected ? colors.actionSurface : Color.clear)
            )
            .contentShape(Capsule())
            .lhMotion(AppAnimation.quick, value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityValue(tab == .inbox && inboxModel.badgeCount > 0
                            ? "\(inboxModel.badgeCount) to confirm" : "")
        .accessibilityIdentifier(tab.accessibilityIdentifier)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Inbox count on the tab. Destructive red is wrong here (nothing is broken), so it uses the
    /// action colour.
    private func tabBadge(_ count: Int) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(colors.onAction)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(colors.action))
            .overlay(Capsule().strokeBorder(colors.backgroundSecondary, lineWidth: 1.5))
            .fixedSize()
            .accessibilityHidden(true)
            .accessibilityIdentifier("tab.inbox.badge")
    }

    private func animate(_ animation: Animation = AppAnimation.smooth, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }
}

private extension View {
    /// Floating chrome only (tab capsule, + circle): Liquid Glass on iOS 26+, a solid card fill before.
    @ViewBuilder
    func floatingGlass<S: Shape>(in shape: S, colors: AdaptiveColors, colorScheme: ColorScheme) -> some View {
        if #available(iOS 26.0, *) {
            self
                .background(
                    shape.fill(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.42 : 0.30))
                )
                .glassEffect(
                    .regular.tint(colors.actionSurface.opacity(colorScheme == .dark ? 0.18 : 0.26)).interactive(),
                    in: shape
                )
                .overlay(
                    shape.stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.30), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 16, y: 4)
        } else {
            self
                .background(shape.fill(colors.backgroundSecondary))
                .overlay(
                    shape.stroke(colors.border.opacity(colorScheme == .dark ? 0.9 : 0.7), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 16, y: 4)
        }
    }
}

// MARK: - Floating Timer Banner

struct FloatingTimerBanner: View {
    @ObservedObject var viewModel: AppViewModel
    let onTap: () -> Void

    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var propertyName: String {
        guard let id = viewModel.timerPropertyId else { return "" }
        return viewModel.properties.first { $0.id == id }?.name ?? "Unknown"
    }

    private var formattedTime: String {
        let h = Int(elapsed) / 3600
        let m = (Int(elapsed) % 3600) / 60
        let s = Int(elapsed) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Circle()
                    .fill(AppColors.coral)
                    .frame(width: 8, height: 8)
                Text(formattedTime)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.onAction)
                Text(propertyName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.onAction.opacity(0.8))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.onAction.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppColors.primary)
            .clipShape(Capsule())
            .shadow(color: AppColors.primary.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .onReceive(timer) { _ in
            elapsed = viewModel.timerElapsedTime
        }
        .onAppear {
            elapsed = viewModel.timerElapsedTime
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppViewModel())
}
