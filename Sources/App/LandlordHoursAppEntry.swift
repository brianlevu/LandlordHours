import SwiftUI

// MARK: - App entry point

@main
struct LandlordHoursApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    /// The one AppViewModel, owned by `AppModelHost` (created at launch, outside SwiftUI).
    private var viewModel: AppViewModel { AppModelHost.shared.viewModel }
    @StateObject private var categoryManager = CategoryManager.shared
    @StateObject private var appearanceManager = AppearanceManager.shared

    init() {
        // Tab bar: soft but legible. Keep content from visually bleeding through the controls.
        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundEffect = nil
        tabBar.backgroundColor = UIColor.systemBackground
        tabBar.shadowImage = UIImage()
        tabBar.shadowColor = UIColor.separator.withAlphaComponent(0.18)
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
        UITabBar.appearance().tintColor = UIColor(AppColors.primary)

        // Navigation bar — transparent with rounded font
        let navBar = UINavigationBarAppearance()
        navBar.configureWithTransparentBackground()
        navBar.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold).rounded()
        ]
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(categoryManager)
                .environmentObject(appearanceManager)
                .preferredColorScheme(AppearanceManager.forcedColorSchemeFromLaunchArguments ?? appearanceManager.preferredColorScheme)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            AppModelHost.shared.sceneDidChange(isActive: phase == .active)
        }
    }

}
