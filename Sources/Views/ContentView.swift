import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var goalManager = GoalManager.shared
    @State private var selectedTab = 0
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @State private var showPaywall = false

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        Group {
            if viewModel.isInitializing {
                splashScreen
            } else if showOnboarding {
                OnboardingView(showOnboarding: $showOnboarding)
                    .onDisappear {
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    }
            } else if !viewModel.isSignedIn {
                LoginView(showLogin: $showOnboarding)
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
        .environmentObject(CategoryManager.shared)
        .environmentObject(goalManager)
        .onAppear {
            viewModel.checkSignInState()
            if viewModel.isSignedIn && subscriptionManager.showPaywall {
                showPaywall = true
            }
        }
        .onChange(of: viewModel.isSignedIn) { _, newValue in
            if !newValue {
                showOnboarding = true
            }
        }
    }

    // MARK: - Splash / Loading Screen (Tiimo-style)
    private var splashScreen: some View {
        ZStack {
            // White → soft lavender gradient (Tiimo splash)
            LinearGradient(
                colors: [Color.white, AppColors.primarySurface.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 32) {
                    // Logo in nested circles (Tiimo style)
                    ZStack {
                        Circle()
                            .fill(AppColors.primarySurface)
                            .frame(width: 160, height: 160)

                        LHCircleBadge(
                            icon: .home,
                            bgColor: AppColors.primary,
                            fgColor: .white,
                            size: 96,
                            iconScale: 0.45
                        )
                    }

                    VStack(spacing: 8) {
                        Text("LandlordHours")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(Color(hex: "111827"))

                        Text("Track your path to tax qualification")
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: "9CA3AF"))
                    }
                }

                Spacer()

                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.primary))
                    .scaleEffect(1.1)
                    .padding(.bottom, 80)
            }
        }
    }

    // MARK: - Main Content with Tab Bar
    var mainContent: some View {
        VStack(spacing: 0) {
            // Trial banner
            TrialBannerView()
                .padding(.top, 8)

            TabView(selection: $selectedTab) {
                DashboardView()
                    .tabItem {
                        LHIcon.home.tabItemImage
                        Text("Home")
                    }
                    .tag(0)

                PropertiesView()
                    .tabItem {
                        LHIcon.properties.tabItemImage
                        Text("Properties")
                    }
                    .tag(1)

                TimeLogView()
                    .tabItem {
                        LHIcon.track.tabItemImage
                        Text("Track")
                    }
                    .tag(2)

                ReportsView()
                    .tabItem {
                        LHIcon.reports.tabItemImage
                        Text("Reports")
                    }
                    .tag(3)

                SettingsView()
                    .tabItem {
                        LHIcon.settings.tabItemImage
                        Text("Settings")
                    }
                    .tag(4)
            }
            .tint(AppColors.primary)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppViewModel())
}
