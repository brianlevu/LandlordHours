import SwiftUI
import Combine
import LucideIcons

extension Notification.Name {
    static let switchToTab = Notification.Name("switchToTab")
    static let openAddProperty = Notification.Name("openAddProperty")
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
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var goalManager = GoalManager.shared
    @StateObject private var appearanceManager = AppearanceManager.shared
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

    private static var forcedColorSchemeFromLaunchArguments: ColorScheme? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-LHColorScheme"),
              args.indices.contains(index + 1) else {
            return nil
        }

        switch args[index + 1].lowercased() {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    var body: some View {
        Group {
            if viewModel.isInitializing || showSplashAfterSignOut {
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
        .preferredColorScheme(Self.forcedColorSchemeFromLaunchArguments ?? appearanceManager.preferredColorScheme)
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
        .environmentObject(appearanceManager)
        .onAppear {
            viewModel.checkSignInState()
            checkPostSignInFlow()
            applyPaywallLaunchArgumentIfNeeded()
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
            // Soft lavender gradient — adapts to dark mode
            LinearGradient(
                colors: colorScheme == .dark
                    ? [AppColors.darkPlum, AppColors.darkInk, AppColors.darkBackground]
                    : [AppColors.lavenderSoft, AppColors.lavenderMist, AppColors.reportsAccentWash, AppColors.lavenderPale, Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Ambient glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.primary.opacity(0.12), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .offset(y: -60)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    // Concentric rings + wave-house logo
                    ZStack {
                        RoundedRectangle(cornerRadius: 52, style: .continuous)
                            .stroke(AppColors.primary.opacity(0.07), lineWidth: 1)
                            .frame(width: 176, height: 176)

                        RoundedRectangle(cornerRadius: 44, style: .continuous)
                            .stroke(AppColors.primary.opacity(0.15), lineWidth: 1.5)
                            .frame(width: 148, height: 148)

                        WaveHouseIcon(size: 120)
                            .shadow(color: AppColors.primary.opacity(0.18), radius: 10, y: 4)
                    }

                    VStack(spacing: 8) {
                        HStack(spacing: 0) {
                            Text("Landlord")
                                .foregroundColor(colors.textPrimary)
                            Text("Hours")
                                .foregroundColor(AppColors.primary)
                        }
                        .font(.system(size: 32, weight: .bold, design: .rounded))

                        Text("Track your path to tax qualification")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundColor(colors.textSecondary)
                    }
                }

                Spacer()

                // Social proof section
                VStack(spacing: 16) {
                    // Stars
                    HStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.caution)
                        }
                    }

                    Text("Built for rental owners tracking tax-year hours")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.slate)

                    // Badge row
                    HStack(spacing: 0) {
                        splashBadge(icon: "doc.text.fill", text: "Tax-year\nrecords")
                        splashDivider
                        splashBadge(icon: "checkmark.seal.fill", text: "Reviewable\nlogs")
                        splashDivider
                        splashBadge(icon: "square.and.arrow.up.fill", text: "PDF\nexports")
                    }
                }
                .padding(.bottom, 60)
            }
        }
    }

    private func splashBadge(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.mist)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.mist)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
    }

    private var splashDivider: some View {
        Rectangle()
            .fill(AppColors.cloud)
            .frame(width: 1, height: 20)
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

            if !isCustomTabBarHidden {
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
        .background(colors.backgroundSecondary)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.58), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 10, y: 4)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
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
