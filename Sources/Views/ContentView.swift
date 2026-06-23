import SwiftUI
import Combine
import LucideIcons

extension Notification.Name {
    static let switchToTab = Notification.Name("switchToTab")
    static let openAddProperty = Notification.Name("openAddProperty")
    static let switchToPropertiesAndOpenAddProperty = Notification.Name("switchToPropertiesAndOpenAddProperty")
    static let prefillFirstActivity = Notification.Name("prefillFirstActivity")
    static let restartGuidedOnboarding = Notification.Name("restartGuidedOnboarding")
    static let skipGuidedOnboarding = Notification.Name("skipGuidedOnboarding")
    static let suspendGuidedOnboardingOverlay = Notification.Name("suspendGuidedOnboardingOverlay")
    static let resumeGuidedOnboardingOverlay = Notification.Name("resumeGuidedOnboardingOverlay")
}

enum GuidedOnboardingStore {
    static let completedKey = "hasCompletedGuidedOnboarding"
    static let skippedKey = "hasSkippedGuidedOnboarding"

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: UserScope.key(completedKey))
    }

    static var isSkipped: Bool {
        UserDefaults.standard.bool(forKey: UserScope.key(skippedKey))
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: UserScope.key(completedKey))
        UserDefaults.standard.removeObject(forKey: UserScope.key(skippedKey))
    }

    static func skip() {
        UserDefaults.standard.set(true, forKey: UserScope.key(skippedKey))
    }

    static func restart() {
        UserDefaults.standard.removeObject(forKey: UserScope.key(completedKey))
        UserDefaults.standard.removeObject(forKey: UserScope.key(skippedKey))
    }
}

enum GuidedOnboardingStep: Hashable {
    case propertyTab
    case addProperty
    case trackTab
    case firstActivity
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
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var goalManager = GoalManager.shared
    @State private var selectedTab = Self.initialTabFromLaunchArguments()
    @State private var showOnboarding = false
    @State private var showPaywall = Self.shouldShowPaywallFromLaunchArguments
    @State private var showSplashAfterSignOut = false
    @State private var guidedOnboardingRefresh = false
    @State private var isReplayingGuidedOnboarding = false
    @State private var isGuidedOnboardingSuspended = false
    @State private var isForcingGuidedOnboardingHome = false
    @State private var hasAcknowledgedFirstActivityCoach = false
    @State private var didApplyGuidedReplayLaunchArgument = false
    @State private var didApplyPaywallLaunchArgument = false
    @State private var isCustomTabBarHidden = false
    @State private var isSplashAnimating = true
    @State private var isShowingInitialLaunchBridge = true
    @State private var didScheduleInitialLaunchBridgeDismiss = false

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private static func initialTabFromLaunchArguments() -> Int {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-LHForceGuidedSetupHome") {
            return 0
        }
        if args.contains("-LHReplayGuidedSetup") {
            return 1
        }
        guard let index = args.firstIndex(of: "-LHInitialTab"),
              args.indices.contains(index + 1),
              let tab = Int(args[index + 1]) else {
            return 0
        }
        return min(max(tab, 0), 4)
    }

    private static var shouldReplayGuidedSetupFromLaunchArguments: Bool {
        ProcessInfo.processInfo.arguments.contains("-LHReplayGuidedSetup")
    }

    private static var shouldForceGuidedSetupHomeFromLaunchArguments: Bool {
        ProcessInfo.processInfo.arguments.contains("-LHForceGuidedSetupHome")
    }

    private static var shouldShowPaywallFromLaunchArguments: Bool {
        ProcessInfo.processInfo.arguments.contains("-LHShowPaywall")
    }

    var body: some View {
        Group {
            if viewModel.isInitializing || showSplashAfterSignOut || isShowingInitialLaunchBridge {
                splashScreen
            } else if !viewModel.isSignedIn {
                LoginView()
            } else if Self.shouldShowPaywallFromLaunchArguments && showPaywall {
                PaywallView(showPaywall: $showPaywall) {
                    showPaywall = false
                }
            } else if showOnboarding {
                OnboardingView(showOnboarding: $showOnboarding)
            } else if showPaywall {
                PaywallView(showPaywall: $showPaywall) {
                    showPaywall = false
                }
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
        .environmentObject(CategoryManager.shared)
        .environmentObject(goalManager)
        .onAppear {
            viewModel.checkSignInState()
            checkPostSignInFlow()
            applyPaywallLaunchArgumentIfNeeded()
            scheduleInitialLaunchBridgeDismissIfReady()
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
        .onChange(of: viewModel.isInitializing) { _, _ in
            scheduleInitialLaunchBridgeDismissIfReady()
        }
        .onChange(of: viewModel.isSignedIn) { _, newValue in
            if newValue {
                checkPostSignInFlow()
                applyPaywallLaunchArgumentIfNeeded()
            } else {
                // User signed out — show splash briefly, then login
                showOnboarding = false
                showPaywall = false
                showSplashAfterSignOut = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    animate(AppAnimation.standard) {
                        showSplashAfterSignOut = false
                    }
                }
            }
        }
        .onChange(of: viewModel.timeEntries.count) { _, newValue in
            if newValue > 0, !GuidedOnboardingStore.isCompleted {
                GuidedOnboardingStore.markCompleted()
                guidedOnboardingRefresh.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .restartGuidedOnboarding)) { _ in
            GuidedOnboardingStore.restart()
            showOnboarding = false
            showPaywall = false
            animate(AppAnimation.smooth) {
                isReplayingGuidedOnboarding = true
                isGuidedOnboardingSuspended = false
                hasAcknowledgedFirstActivityCoach = false
                selectedTab = 1
                guidedOnboardingRefresh.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .skipGuidedOnboarding)) { _ in
            GuidedOnboardingStore.skip()
            isReplayingGuidedOnboarding = false
            isGuidedOnboardingSuspended = false
            hasAcknowledgedFirstActivityCoach = false
            guidedOnboardingRefresh.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .suspendGuidedOnboardingOverlay)) { _ in
            isGuidedOnboardingSuspended = true
            guidedOnboardingRefresh.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .resumeGuidedOnboardingOverlay)) { _ in
            isGuidedOnboardingSuspended = false
            guidedOnboardingRefresh.toggle()
        }
        .onAppear {
            applyGuidedReplayLaunchArgumentIfNeeded()
            applyPaywallLaunchArgumentIfNeeded()
        }
    }

    // MARK: - Splash / Loading Screen
    private var splashScreen: some View {
        ZStack {
            splashBackground

            VStack(spacing: 20) {
                Spacer()

                WaveHouseIcon(size: 84)
                    .shadow(color: colors.primary.opacity(colorScheme == .dark ? 0.26 : 0.20), radius: 18, y: 10)
                    .scaleEffect(isSplashAnimating ? 1 : 0.96)
                    .opacity(isSplashAnimating ? 1 : 0)

                launchWordmark
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .opacity(isSplashAnimating ? 1 : 0)

                HStack(spacing: 8) {
                    LoadingDot(delay: 0.0, color: colors.primary)
                    LoadingDot(delay: 0.12, color: colors.informational)
                    LoadingDot(delay: 0.24, color: colors.positive)
                }
                .opacity(isSplashAnimating ? 1 : 0)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            guard !reduceMotion else {
                isSplashAnimating = true
                return
            }

            withAnimation(AppAnimation.flow.delay(0.08)) {
                isSplashAnimating = true
            }
        }
    }

    private var launchWordmark: Text {
        Text("Landlord")
            .foregroundColor(colors.textPrimary)
        +
        Text("Hours")
            .foregroundColor(colors.primary)
    }

    private var splashBackground: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [AppColors.darkBackground, AppColors.darkPlum, AppColors.darkInk]
                    : [AppColors.lavenderPale, AppColors.background, AppColors.reportsAccentWash.opacity(0.8), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    colors.primary.opacity(colorScheme == .dark ? 0.22 : 0.12),
                    Color.clear,
                    colors.positive.opacity(colorScheme == .dark ? 0.12 : 0.08)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            VStack(spacing: 0) {
                Rectangle()
                    .fill(colors.primary.opacity(colorScheme == .dark ? 0.13 : 0.08))
                    .frame(height: 1)
                    .offset(y: isSplashAnimating && !reduceMotion ? 46 : 22)
                Spacer()
                Rectangle()
                    .fill(colors.primary.opacity(colorScheme == .dark ? 0.10 : 0.06))
                    .frame(height: 1)
                    .offset(y: isSplashAnimating && !reduceMotion ? -58 : -28)
            }
            .rotationEffect(.degrees(-16))
            .opacity(0.9)
        }
        .ignoresSafeArea()
    }

    private var launchHeader: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                WaveHouseIcon(size: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: colors.primary.opacity(0.16), radius: 12, y: 6)

                launchWordmark
                    .font(.system(size: 27, weight: .bold, design: .rounded))
            }

            Text("Preparing your tax-year command center")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .opacity(isSplashAnimating ? 1 : 0)
        .offset(y: isSplashAnimating ? 0 : 10)
    }

    private var qualificationMap: some View {
        VStack(spacing: 22) {
            HStack(alignment: .center, spacing: 22) {
                SplashProgressRings(isAnimating: isSplashAnimating)
                    .frame(width: 134, height: 134)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("2026")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.primary)

                        Text("Qualification map")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Hours, properties, and reports are being organized into review-ready records.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 10) {
                SplashEvidenceRow(
                    icon: "clock",
                    title: "Hour ledger",
                    detail: "Syncing recent entries",
                    tint: colors.primary,
                    isActive: isSplashAnimating
                )

                SplashEvidenceRow(
                    icon: "building-2",
                    title: "Property records",
                    detail: "Checking portfolio status",
                    tint: colors.informational,
                    isActive: isSplashAnimating
                )

                SplashEvidenceRow(
                    icon: "file-text",
                    title: "Report package",
                    detail: "Preparing export data",
                    tint: colors.positive,
                    isActive: isSplashAnimating
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous)
                .fill(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.82 : 0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous)
                .strokeBorder(colors.border.opacity(colorScheme == .dark ? 0.55 : 0.42), lineWidth: 1)
        )
        .shadow(color: colors.primary.opacity(colorScheme == .dark ? 0.12 : 0.10), radius: 18, x: 0, y: 12)
        .scaleEffect(isSplashAnimating ? 1 : 0.98)
        .opacity(isSplashAnimating ? 1 : 0)
    }

    private var splashStatusRail: some View {
        HStack(spacing: 10) {
            LoadingDot(delay: 0.0, color: colors.primary)
            LoadingDot(delay: 0.12, color: colors.informational)
            LoadingDot(delay: 0.24, color: colors.positive)

            Text("Building audit trail")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(colors.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            Capsule()
                .fill(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.70 : 0.64))
        )
        .overlay(
            Capsule()
                .strokeBorder(colors.border.opacity(0.42), lineWidth: 1)
        )
        .opacity(isSplashAnimating ? 1 : 0)
    }

    private func scheduleInitialLaunchBridgeDismissIfReady() {
        guard !viewModel.isInitializing,
              isShowingInitialLaunchBridge,
              !didScheduleInitialLaunchBridgeDismiss else { return }

        didScheduleInitialLaunchBridgeDismiss = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            animate(AppAnimation.standard) {
                isShowingInitialLaunchBridge = false
            }
        }
    }

    /// Single entry point for post-sign-in UI flow. Prevents duplicate triggers
    /// from both onAppear and onChange(of: isSignedIn).
    private func checkPostSignInFlow() {
        guard viewModel.isSignedIn, !showOnboarding, !showPaywall else { return }
        if !UserDefaults.standard.bool(forKey: UserScope.key("hasCompletedOnboarding")) {
            showOnboarding = true
        } else if subscriptionManager.showPaywall && shouldPresentPaywallAfterActivation {
            showPaywall = true
        }
    }

    private var shouldPresentPaywallAfterActivation: Bool {
        !viewModel.properties.isEmpty &&
        (!viewModel.timeEntries.isEmpty || GuidedOnboardingStore.isCompleted || GuidedOnboardingStore.isSkipped)
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
            selectedTabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom) {
                    if !isCustomTabBarHidden {
                        Color.clear
                            .frame(height: AppSpacing.floatingTabBarReservedHeight)
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

            // Floating timer banner (visible on all tabs except Track)
            if viewModel.isTimerRunning && selectedTab != 2 && !isCustomTabBarHidden {
                FloatingTimerBanner(viewModel: viewModel) {
                    selectedTab = 2
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 52) // above tab bar
            }

        }
        .onPreferenceChange(AppTabBarHiddenPreferenceKey.self) { hidden in
            animate(AppAnimation.quick) {
                isCustomTabBarHidden = hidden
            }
        }
        .overlayPreferenceValue(GuidedSpotlightTargetKey.self) { targets in
            GeometryReader { proxy in
                if let step = guidedOnboardingStep {
                    let measuredTarget = targets[step].map { proxy[$0].insetBy(dx: -5, dy: -5) }

                    GuidedOnboardingOverlay(
                        step: step,
                        spotlightOverride: measuredTarget,
                        isReplay: isReplayingGuidedOnboarding,
                        onPrimary: { handleGuidedOnboardingPrimary(step) },
                        onSecondary: { handleGuidedOnboardingSecondary(step) },
                        onSkip: {
                            GuidedOnboardingStore.skip()
                            isReplayingGuidedOnboarding = false
                            guidedOnboardingRefresh.toggle()
                        }
                    )
                    .accessibilityIdentifier("guidedSetup.overlay")
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case 0:
            DashboardView()
        case 1:
            PropertiesView()
        case 2:
            TimeLogView()
        case 3:
            ReportsView()
        case 4:
            SettingsView()
        default:
            DashboardView()
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabBarButton(index: 0, title: "Home", icon: Lucide.house)
            tabBarButton(index: 1, title: "Properties", icon: Lucide.building2)
                .guidedSpotlightTarget(.propertyTab)
            tabBarButton(index: 2, title: "Track", icon: Lucide.clock)
                .guidedSpotlightTarget(.trackTab)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(height: 78)
        .floatingDockGlass(colors: colors, colorScheme: colorScheme)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
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
        .frame(height: AppSpacing.floatingTabBarReservedHeight + 72)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tabBarButton(index: Int, title: String, icon: UIImage) -> some View {
        let isSelected = selectedTab == index
        let inactiveColor = colors.textSecondary.opacity(colorScheme == .dark ? 0.86 : 0.78)

        return Button {
            animate(AppAnimation.quick) {
                selectedTab = index
            }
        } label: {
            VStack(spacing: 5) {
                LucideIcon(image: icon, size: 22)
                    .foregroundStyle(isSelected ? AppColors.primary : inactiveColor)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? AppColors.primary : inactiveColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Capsule()
                    .fill(isSelected ? colors.primarySurface.opacity(0.82) : Color.clear)
            )
            .contentShape(Capsule())
            .lhMotion(AppAnimation.quick, value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var guidedOnboardingStep: GuidedOnboardingStep? {
        _ = guidedOnboardingRefresh
        guard viewModel.isSignedIn,
              !showOnboarding,
              !showPaywall,
              !isGuidedOnboardingSuspended else {
            return nil
        }

        if isForcingGuidedOnboardingHome {
            return currentGuidedOnboardingStep
        }

        if isReplayingGuidedOnboarding {
            if selectedTab == 1 { return .addProperty }
            if selectedTab == 2 { return .firstActivity }
            return .propertyTab
        }

        guard !GuidedOnboardingStore.isCompleted,
              !GuidedOnboardingStore.isSkipped else {
            return nil
        }

        return currentGuidedOnboardingStep
    }

    private var currentGuidedOnboardingStep: GuidedOnboardingStep? {
        if viewModel.properties.isEmpty {
            return selectedTab == 1 ? .addProperty : .propertyTab
        }
        if viewModel.timeEntries.isEmpty {
            if hasAcknowledgedFirstActivityCoach {
                return nil
            }
            return selectedTab == 2 ? .firstActivity : .trackTab
        }
        return nil
    }

    private func handleGuidedOnboardingPrimary(_ step: GuidedOnboardingStep) {
        switch step {
        case .propertyTab:
            animate(AppAnimation.smooth) { selectedTab = 1 }
        case .addProperty:
            isGuidedOnboardingSuspended = true
            NotificationCenter.default.post(name: .openAddProperty, object: nil)
            if isReplayingGuidedOnboarding, !viewModel.properties.isEmpty {
                isReplayingGuidedOnboarding = false
                guidedOnboardingRefresh.toggle()
            }
        case .trackTab:
            animate(AppAnimation.smooth) { selectedTab = 2 }
        case .firstActivity:
            NotificationCenter.default.post(name: .prefillFirstActivity, object: nil)
            isReplayingGuidedOnboarding = false
            hasAcknowledgedFirstActivityCoach = true
            guidedOnboardingRefresh.toggle()
        }
    }

    private func handleGuidedOnboardingSecondary(_ step: GuidedOnboardingStep) {
        switch step {
        case .firstActivity:
            isReplayingGuidedOnboarding = false
            hasAcknowledgedFirstActivityCoach = true
            guidedOnboardingRefresh.toggle()
        default:
            GuidedOnboardingStore.skip()
            isReplayingGuidedOnboarding = false
            guidedOnboardingRefresh.toggle()
        }
    }

    private func animate(_ animation: Animation = AppAnimation.smooth, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }

    private func applyGuidedReplayLaunchArgumentIfNeeded() {
        guard Self.shouldReplayGuidedSetupFromLaunchArguments || Self.shouldForceGuidedSetupHomeFromLaunchArguments,
              !didApplyGuidedReplayLaunchArgument else { return }
        didApplyGuidedReplayLaunchArgument = true
        GuidedOnboardingStore.restart()
        showOnboarding = false
        showPaywall = false
        isForcingGuidedOnboardingHome = Self.shouldForceGuidedSetupHomeFromLaunchArguments
        isReplayingGuidedOnboarding = Self.shouldReplayGuidedSetupFromLaunchArguments
        isGuidedOnboardingSuspended = false
        hasAcknowledgedFirstActivityCoach = false
        selectedTab = Self.shouldForceGuidedSetupHomeFromLaunchArguments ? 0 : 1
        guidedOnboardingRefresh.toggle()
    }

    private func applyPaywallLaunchArgumentIfNeeded() {
        guard Self.shouldShowPaywallFromLaunchArguments,
              !didApplyPaywallLaunchArgument,
              viewModel.isSignedIn,
              !viewModel.isInitializing else { return }
        didApplyPaywallLaunchArgument = true
        showOnboarding = false
        showPaywall = true
    }
}

// MARK: - Launch Loading Components

private struct SplashProgressRings: View {
    let isAnimating: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRotating = false

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    colors.primarySurface.opacity(colorScheme == .dark ? 0.32 : 0.70),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round, dash: [3, 7])
                )
                .rotationEffect(.degrees(isRotating ? 360 : 0))

            Circle()
                .trim(from: 0, to: isAnimating ? 0.34 : 0.06)
                .stroke(
                    LinearGradient(
                        colors: [colors.primary, AppColors.reportsAccentSoft],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(-92))
                .animation(AppAnimation.flow.delay(0.14), value: isAnimating)

            Circle()
                .stroke(
                    colors.positiveSurface.opacity(colorScheme == .dark ? 0.34 : 0.78),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .padding(25)

            Circle()
                .trim(from: 0, to: isAnimating ? 0.22 : 0.04)
                .stroke(
                    LinearGradient(
                        colors: [colors.positive, AppColors.successGreenSoft],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-92))
                .padding(25)
                .animation(AppAnimation.flow.delay(0.24), value: isAnimating)

            VStack(spacing: 1) {
                Text("21%")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Text("pace")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textTertiary)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 7.5).repeatForever(autoreverses: false)) {
                isRotating = true
            }
        }
    }
}

private struct SplashEvidenceRow: View {
    let icon: String
    let title: String
    let detail: String
    let tint: Color
    let isActive: Bool

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 12) {
            JellyBadge(systemName: icon, color: tint, size: 34)
                .shadow(color: tint.opacity(0.14), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
            }

            Spacer(minLength: 10)

            ZStack {
                Circle()
                    .fill(tint.opacity(colorScheme == .dark ? 0.22 : 0.16))
                    .frame(width: 24, height: 24)

                Circle()
                    .trim(from: 0, to: isActive ? 0.76 : 0.18)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(-90))
                    .animation(AppAnimation.flow, value: isActive)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                .fill(colors.backgroundTertiary.opacity(colorScheme == .dark ? 0.58 : 0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous)
                .strokeBorder(colors.border.opacity(0.28), lineWidth: 1)
        )
    }
}

private struct LoadingDot: View {
    let delay: Double
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isActive = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .scaleEffect(isActive && !reduceMotion ? 1.0 : 0.62)
            .opacity(isActive && !reduceMotion ? 1 : 0.45)
            .onAppear {
                guard !reduceMotion else {
                    isActive = true
                    return
                }

                withAnimation(
                    .easeInOut(duration: 0.72)
                    .delay(delay)
                    .repeatForever(autoreverses: true)
                ) {
                    isActive = true
                }
            }
    }
}

private extension View {
    @ViewBuilder
    func floatingDockGlass(colors: AdaptiveColors, colorScheme: ColorScheme) -> some View {
        if #available(iOS 26.0, *) {
            self
                .background(
                    Capsule()
                        .fill(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.42 : 0.28))
                )
                .glassEffect(
                    .regular.tint(colors.actionSurface.opacity(colorScheme == .dark ? 0.20 : 0.34)).interactive(),
                    in: .capsule
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.24), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 14, y: 8)
        } else {
            self
                .background(colors.backgroundSecondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.58), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 10, y: 4)
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
                LucideIcon(image: Lucide.chevronRight, size: 14)
                    .foregroundStyle(AppColors.onAction.opacity(0.6))
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
