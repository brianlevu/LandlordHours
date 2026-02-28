import SwiftUI
import LucideIcons

extension Notification.Name {
    static let switchToTab = Notification.Name("switchToTab")
}

struct ContentView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var goalManager = GoalManager.shared
    @State private var selectedTab = 0
    @State private var showOnboarding = false
    @State private var showPaywall = false
    @State private var showSplashAfterSignOut = false

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        Group {
            if viewModel.isInitializing || showSplashAfterSignOut {
                splashScreen
            } else if !viewModel.isSignedIn {
                LoginView()
            } else if showOnboarding {
                OnboardingView(showOnboarding: $showOnboarding)
                    .onDisappear {
                        UserDefaults.standard.set(true, forKey: UserScope.key("hasCompletedOnboarding"))
                    }
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
        }
        .onChange(of: viewModel.isSignedIn) { _, newValue in
            if newValue {
                checkPostSignInFlow()
            } else {
                // User signed out — show splash briefly, then login
                showOnboarding = false
                showPaywall = false
                showSplashAfterSignOut = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(AppAnimation.standard) {
                        showSplashAfterSignOut = false
                    }
                }
            }
        }
    }

    // MARK: - Splash / Loading Screen
    private var splashScreen: some View {
        ZStack {
            // Soft lavender gradient — adapts to dark mode
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(hex: "1A1535"), Color(hex: "1C1A2E"), Color(hex: "0D0D0D")]
                    : [Color(hex: "C4B5FD"), Color(hex: "DDD6FE"), Color(hex: "EDE9FE"), Color(hex: "F5F3FF"), Color.white],
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
                            .shadow(color: AppColors.primary.opacity(0.3), radius: 20, y: 6)
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
                                .foregroundStyle(Color(hex: "F5C563"))
                        }
                    }

                    Text("Trusted by 2,000+ landlords")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.slate)

                    // Badge row
                    HStack(spacing: 0) {
                        splashBadge(icon: "apple.logo", text: "Featured on\nApp Store")
                        splashDivider
                        splashBadge(icon: "lock.fill", text: "Tax-grade\naccuracy")
                        splashDivider
                        splashBadge(icon: "icloud.fill", text: "iCloud\nencrypted")
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
        } else if subscriptionManager.showPaywall {
            showPaywall = true
        }
    }

    // MARK: - Main Content with Tab Bar
    var mainContent: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                DashboardView()
                    .tabItem {
                        lucideTabIcon(Lucide.house)
                        Text("Home")
                    }
                    .tag(0)

                PropertiesView()
                    .tabItem {
                        lucideTabIcon(Lucide.building2)
                        Text("Properties")
                    }
                    .tag(1)

                TimeLogView()
                    .tabItem {
                        lucideTabIcon(Lucide.clock)
                        Text("Track")
                    }
                    .tag(2)

                ReportsView()
                    .tabItem {
                        lucideTabIcon(Lucide.chartColumnIncreasing)
                        Text("Reports")
                    }
                    .tag(3)

                SettingsView()
                    .tabItem {
                        lucideTabIcon(Lucide.settings)
                        Text("Settings")
                    }
                    .tag(4)
            }
            .tint(AppColors.primary)
            .onReceive(NotificationCenter.default.publisher(for: .switchToTab)) { notification in
                if let tab = notification.object as? Int {
                    selectedTab = tab
                }
            }

            // Floating timer banner (visible on all tabs except Track)
            if viewModel.isTimerRunning && selectedTab != 2 {
                FloatingTimerBanner(viewModel: viewModel) {
                    selectedTab = 2
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 52) // above tab bar
            }
        }
    }

    private func lucideTabIcon(_ image: UIImage) -> some View {
        LucideIcon(image: image, size: 22)
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
                    .foregroundStyle(.white)
                Text(propertyName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                Spacer()
                LucideIcon(image: Lucide.chevronRight, size: 14)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppColors.primary)
            .clipShape(Capsule())
            .shadow(color: AppColors.primary.opacity(0.4), radius: 12, y: 4)
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
