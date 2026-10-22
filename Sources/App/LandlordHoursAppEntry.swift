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
    /// 2.0: the first frame repeats the launch screen, then hands off (LaunchHandoffView.swift).
    @State private var launchHandoffFinished = false

    init() {
        #if DEBUG
        RestoreFailureLaunch.prepare()   // -LHRestoreOutcome timeout|failure (captures only)
        #endif
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

        // Navigation bar — transparent; inline titles SF Pro, large titles Fraunces (2.0 brand,
        // 34pt ≥ the 28pt floor) so system large titles such as Records match the custom roots.
        let navBar = UINavigationBarAppearance()
        navBar.configureWithTransparentBackground()
        // Title colour is the textPrimary token (not system black/white).
        let titleInk = UIColor { traits in
            UIColor(lhHex: traits.userInterfaceStyle == .dark ? AppColors.Hex.darkTextPrimary : AppColors.Hex.textPrimary)
        }
        navBar.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: titleInk
        ]
        navBar.largeTitleTextAttributes = [
            .font: LHFont.frauncesUIFont(.largeTitle, contentSize: UITraitCollection.current.preferredContentSizeCategory),
            .foregroundColor: titleInk
        ]
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
    }

    private var appRoot: some View {
        ContentView()
            .environmentObject(viewModel)
            .environmentObject(categoryManager)
            .environmentObject(appearanceManager)
            .preferredColorScheme(AppearanceManager.forcedColorSchemeFromLaunchArguments ?? appearanceManager.preferredColorScheme)
            .overlay {
                if !launchHandoffFinished {
                    LaunchHandoffOverlay(
                        destination: viewModel.isSignedIn ? .today : .welcome,
                        isFinished: $launchHandoffFinished
                    )
                }
            }
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // House capture hook (-LHHousePreview <hours> <goal> <scheme>); see HousePreviewLaunchHook.swift.
            if LogTimeProtoLaunch.isOn {
                // Throwaway Log time design prototype (-LHLogTimeProto 1); see Views/LogTime/Proto.
                LogTimeProtoRoot()
            } else if let board = SurfaceBoardLaunch.current {
                // Surfaces capture boards (-LHSurfaceBoard <name>); see SurfaceCaptureBoard.swift.
                SurfaceCaptureRoot(launch: board)
            } else if let housePreview = HousePreviewLaunch.current {
                HousePreviewRoot(config: housePreview)
            } else {
                appRoot
            }
            #else
            appRoot
            #endif
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            AppModelHost.shared.sceneDidChange(isActive: phase == .active)
        }
    }

}
