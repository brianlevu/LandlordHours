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

extension View {
    /// v2 (§1.25): pushed screens that want the whole height hide the native tab bar the system way.
    /// (1.x drove a custom bar through a preference; the native tab bar needs nothing else.)
    func hidesAppTabBar(_ hidden: Bool = true) -> some View {
        toolbarVisibility(hidden ? .hidden : .automatic, for: .tabBar)
    }
}

// MARK: - The shell's tabs (standard §1.25, §H.7)

/// The five items in the native tab bar. "Log time" is the fifth, with the search role; selecting it
/// opens the Log time sheet and restores the previous tab, so it is never the selected tab.
enum ShellItem: Hashable, CaseIterable {
    case today, inbox, records, rentals, logTime

    /// The 1.x integer routes (`.switchToTab` posts, `-LHInitialTab`, App Intents, UI tests) keep
    /// resolving: 0 Today, 1 Rentals, 2 Log time, 3 Reports (on Today), 4 Settings (on Today),
    /// 5 Inbox, 6 Records.
    init(legacyIndex: Int) {
        switch legacyIndex {
        case ShellTab.propertiesIndex: self = .rentals
        case ShellTab.logTimeIndex: self = .logTime
        case ShellTab.inboxIndex: self = .inbox
        case ShellTab.recordsIndex: self = .records
        default: self = .today
        }
    }

    var legacyIndex: Int {
        switch self {
        case .today: return ShellTab.todayIndex
        case .inbox: return ShellTab.inboxIndex
        case .records: return ShellTab.recordsIndex
        case .rentals: return ShellTab.propertiesIndex
        case .logTime: return ShellTab.logTimeIndex
        }
    }

    var title: String {
        switch self {
        case .today: return String(localized: "shell.tab.today", defaultValue: "Today", table: "Foundations")
        case .inbox: return String(localized: "shell.tab.inbox", defaultValue: "Inbox", table: "Foundations")
        case .records: return String(localized: "shell.tab.records", defaultValue: "Records", table: "Foundations")
        case .rentals: return String(localized: "shell.tab.rentals", defaultValue: "Rentals", table: "Foundations")
        case .logTime: return String(localized: "shell.tab.logTime", defaultValue: "Log time", table: "Foundations")
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.horizon"
        case .inbox: return "tray"
        case .records: return "book.closed"
        case .rentals: return "house"
        case .logTime: return "plus"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .today: return "tab.today"
        case .inbox: return "tab.inbox"
        case .records: return "tab.records"
        case .rentals: return "tab.properties"
        case .logTime: return "tab.logTime"
        }
    }
}

/// What the Today tab shows: Reports and Settings open from Today's header, in the Today tab.
enum TodayRoute: Equatable {
    case dashboard, reports, settings

    init?(legacyIndex: Int) {
        switch legacyIndex {
        case ShellTab.todayIndex: self = .dashboard
        case ShellTab.reportsIndex: self = .reports
        case ShellTab.settingsIndex: self = .settings
        default: return nil
        }
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
    /// The selected tab (never `.logTime`: selecting it opens the sheet and restores this).
    @State private var tab: ShellItem = {
        let item = ShellItem(legacyIndex: ContentView.initialTabFromLaunchArguments())
        return item == .logTime ? .today : item   // Log time opens as a sheet over Today
    }()
    /// Reports and Settings open in the Today tab from Today's header.
    @State private var todayRoute: TodayRoute = TodayRoute(legacyIndex: Self.initialTabFromLaunchArguments()) ?? .dashboard
    /// The window's layout band (§1.27), from the scene width with 8pt hysteresis.
    @State private var band: LayoutBand = .a
    #if DEBUG
    @State private var showOnboarding = WelcomeStateFixture.forceWelcome
    @State private var showComponentSheet = LHComponentSheetLaunch.isRequested
    #else
    @State private var showOnboarding = false
    #endif
    /// WP-L: background work the shell surfaces (look-back reveal, export ready banner).
    @ObservedObject private var houseEvents = TodayHouseEvents.shared
    @ObservedObject private var exportJob = ExportJob.shared
    @State private var shellBackfillReveal: HouseBackfillReveal?
    @State private var exportShare: ExportShareItem?
    /// WP3: the suggestion inbox (tab content + badge).
    @StateObject private var inboxModel = InboxViewModel.live(app: AppModelHost.shared.viewModel)
    /// WP3: one-time "What's new" auto-capture opt-in for people updating from 1.x.
    @State private var showCaptureWhatsNew = false
    /// The Log time sheet (or the timer), opened by the fifth tab, ⌘N and every 1.x "+" route.
    @State private var logRoute: LogSheetRoute?
    /// The Log time sheet is on screen, from the moment it opens until it has finished dismissing
    /// (`onDismiss`), so Today's reveal waits for the sheet to be gone (§B.3 `houseReveal`).
    @State private var logSheetUp = false
    /// 2.0 surfaces: the one toast queue (Log time and the timer post to it through
    /// `AppToastCenter`), and Get help opened from the load-error toast.
    @ObservedObject private var toastCenter = LHToastCenter.shared
    @State private var showGetHelp = false

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
                    .overlay(alignment: .bottom) {
                        LHToastHost(center: toastCenter)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
            } else {
                mainContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.background)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            band = LayoutBand.resolve(previous: band, width: width)
        }
        .environment(\.layoutBand, band)
        .overlay {
            if let celebration = viewModel.activeCelebration {
                CelebrationOverlayView(type: celebration) {
                    viewModel.activeCelebration = nil
                }
                .transition(.opacity)
                .zIndex(999)
            }
        }
        .onChange(of: viewModel.persistenceError, initial: true) { _, message in
            guard let message else { return }
            showPersistenceToast(message)
        }
        .sheet(isPresented: $showGetHelp) {
            NavigationStack { ContactSupportView() }
        }
        // WP-P: the one paywall, opened by any screen through ProPaywallPresenter.shared.
        .proPaywallHost()
        #if DEBUG
        .fullScreenCover(isPresented: .constant(PaywallPreviewLaunch.current != nil)) {
            if let preview = PaywallPreviewLaunch.current { PaywallPreviewRoot(launch: preview) }
        }
        .fullScreenCover(isPresented: $showComponentSheet) {
            LHComponentSheet(page: LHComponentSheetLaunch.page)
        }
        #endif
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
                route(toLegacy: ShellTab.inboxIndex)
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

    /// Save failed → "Retry"; load failed → "Help" (the records are still on this iPhone).
    private func showPersistenceToast(_ message: String) {
        if message == AppViewModel.loadFailureMessage {
            toastCenter.show(.problem, message, actionTitle: String(localized: "shell.toast.help", defaultValue: "Help",
                                                                  table: "Foundations")) { showGetHelp = true }
        } else {
            toastCenter.show(.problem, message, actionTitle: String(localized: "shell.toast.retry", defaultValue: "Retry",
                                                                  table: "Foundations")) { [weak viewModel] in
                viewModel?.retrySave()
            }
        }
    }

    private func applyPendingAppIntentNavigationIfNeeded() {
        guard let rawDestination = UserDefaults.standard.string(forKey: AppIntentNavigationRequest.pendingDestinationKey),
              let destination = LandlordHoursIntentDestination(rawValue: rawDestination) else {
            return
        }

        UserDefaults.standard.removeObject(forKey: AppIntentNavigationRequest.pendingDestinationKey)
        route(toLegacy: destination.tabIndex)
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
            route(toLegacy: ShellTab.todayIndex)
            return
        }

        route(toLegacy: destination.tabIndex)
    }

    /// Every 1.x integer route lands here: a tab, a Today page (Reports, Settings), or Log time.
    private func route(toLegacy index: Int) {
        let item = ShellItem(legacyIndex: min(max(index, 0), ShellTab.maxIndex))
        if item == .logTime {
            openLog(plusRoute)
            return
        }
        if item == .today { todayRoute = TodayRoute(legacyIndex: index) ?? .dashboard }
        tab = item
    }

    // MARK: - Main content: the native tab bar (§1.25, §H.7)

    var mainContent: some View {
        tabView
            .tint(colors.action)
            .modifier(TabBarMinimizeOnScroll())
            .background {
                // ⌘N logs time from anywhere (§1.27 keyboard).
                Button(ShellItem.logTime.title) { openLog(.log) }
                    .keyboardShortcut("n", modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToTab)) { notification in
                if let index = notification.object as? Int { route(toLegacy: index) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToPropertiesAndOpenAddProperty)) { _ in
                route(toLegacy: ShellTab.propertiesIndex)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    NotificationCenter.default.post(name: .openAddProperty, object: nil)
                }
            }
            .onAppear {
                #if DEBUG
                InboxDebugSeed.applyIfNeeded(app: viewModel)
                SurfaceDebugHooks.apply(toasts: toastCenter, app: viewModel)
                #endif
                inboxModel.reload()
                presentCaptureWhatsNewIfNeeded()
                if Self.initialTabFromLaunchArguments() == ShellTab.logTimeIndex {
                    openLog(plusRoute)
                }
                #if DEBUG
                LogShellDebug.applyIfNeeded(app: viewModel) { route in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { openLog(route) }
                }
                #endif
            }
            .onChange(of: tab) { oldTab, newTab in
                // "Log time" is never the selected tab: open the sheet over the tab the user was on.
                if newTab == .logTime {
                    tab = oldTab == .logTime ? .today : oldTab
                    openLog(plusRoute)
                    return
                }
                #if DEBUG
                if oldTab != .logTime, newTab != .logTime { HouseRevealDebugLog.shared.record(newTab.accessibilityIdentifier) }
                #endif
                // Leaving Today closes Reports or Settings, as the 1.x bar did.
                if oldTab == .today, newTab != .today { todayRoute = .dashboard }
                inboxModel.dismissToast()
                inboxModel.reload()
                scheduleShellBackfillReveal()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openLogSheet)) { note in
                openLog((note.object as? LogSheetRoute) ?? .log)
            }
            .sheet(item: $logRoute, onDismiss: {
                logSheetUp = false
                #if DEBUG
                HouseRevealDebugLog.shared.record("logSheetDismissed")
                #endif
            }) { route in
                LogTimeSheet(route: route) { logRoute = nil }
                    .environmentObject(viewModel)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(colors.background)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { inboxModel.reload() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .captureSuggestionsDidChange)) { _ in
                inboxModel.reload(animated: true)
                // The widget's to-confirm count is the Inbox badge's count.
                viewModel.refreshWidgetSurface()
            }
            // WP-L: the look-back finished in the background. Today plays the house reveal itself;
            // on any other tab the shell plays it once, when no sheet is in the way.
            .onChange(of: houseEvents.pendingBackfill) { _, _ in scheduleShellBackfillReveal() }
            .onChange(of: inboxModel.sheetSuggestion) { _, _ in scheduleShellBackfillReveal() }
            .fullScreenCover(item: $shellBackfillReveal) { reveal in
                BackfillRevealView(
                    foundHours: reveal.foundHours,
                    suggestionCount: reveal.suggestionCount,
                    confirmedHours: 0,
                    artScheme: colorScheme,
                    onReview: {
                        shellBackfillReveal = nil
                        route(toLegacy: ShellTab.inboxIndex)
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
                    if openInbox { route(toLegacy: ShellTab.inboxIndex) }
                }
                .environmentObject(viewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
    }

    /// Five native tabs. The system draws the bar (Liquid Glass on iOS 26+, its own material on
    /// 18–25) and its minimize behaviour; nothing here reserves a bottom height.
    private var tabView: some View {
        TabView(selection: $tab) {
            Tab(ShellItem.today.title, systemImage: ShellItem.today.systemImage, value: ShellItem.today) {
                shellRoot { todayContent }
            }
            .accessibilityIdentifier(ShellItem.today.accessibilityIdentifier)
            Tab(ShellItem.inbox.title, systemImage: ShellItem.inbox.systemImage, value: ShellItem.inbox) {
                shellRoot { InboxView(model: inboxModel) }
            }
            .badge(inboxModel.badgeCount)
            .accessibilityIdentifier(ShellItem.inbox.accessibilityIdentifier)
            Tab(ShellItem.records.title, systemImage: ShellItem.records.systemImage, value: ShellItem.records) {
                shellRoot { HistoryView() }
            }
            .accessibilityIdentifier(ShellItem.records.accessibilityIdentifier)
            Tab(ShellItem.rentals.title, systemImage: ShellItem.rentals.systemImage, value: ShellItem.rentals) {
                shellRoot { PropertiesView() }
            }
            .accessibilityIdentifier(ShellItem.rentals.accessibilityIdentifier)
            // The create action is the native fifth item (search role), inside the bar as in the
            // locked iOS 27 frame. The explicit label stops VoiceOver reading the role as "Search".
            Tab(ShellItem.logTime.title, systemImage: ShellItem.logTime.systemImage, value: ShellItem.logTime, role: .search) {
                LHCanvas()
            }
            .accessibilityLabel(ShellItem.logTime.title)
            .accessibilityIdentifier(ShellItem.logTime.accessibilityIdentifier)
        }
        .tabViewStyle(.tabBarOnly)
        // iOS 26+ drops `Tab`'s `.accessibilityIdentifier` on the floor: the bar's buttons come out
        // with an empty identifier. Stamp them on the bar's items; the badge and the tab re-stamp.
        .background(ShellTabBarIdentifierStamp(token: "\(inboxModel.badgeCount)-\(tab)"))
    }

    @ViewBuilder
    private var todayContent: some View {
        switch todayRoute {
        case .dashboard: DashboardView(inbox: inboxModel)
            .environment(\.todayShellUncovered, todayUncovered)
        case .reports: ReportsView()
        case .settings: SettingsView()
        }
    }

    /// Nothing of the shell's covers Today: its tab is selected on the dashboard, and no shell sheet
    /// or cover is up (the Log time sheet counts until it has finished dismissing).
    private var todayUncovered: Bool {
        tab == .today && todayRoute == .dashboard && logRoute == nil && !logSheetUp
            && exportShare == nil && !showCaptureWhatsNew && shellBackfillReveal == nil && !showGetHelp
            && viewModel.activeCelebration == nil
    }

    /// Each tab root: the export
    /// banner in its own row above the bar, and the bottom toasts above the bar.
    private func shellRoot<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tint(colors.action)
            .safeAreaInset(edge: .bottom, spacing: 0) {
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
            .lhMotion(AppAnimation.reveal, value: exportBanner)
            .overlay(alignment: .bottom) {
                // WP3: Undo for the last inbox action takes the slot first; the shared queue waits.
                ZStack {
                    if let toast = inboxModel.toast {
                        InboxUndoToast(toast: toast) { inboxModel.undo() }
                            // Slides only: an opacity fade would let row text show through mid-transition.
                            .transition(reduceMotion ? .identity : .move(edge: .bottom))
                    } else {
                        LHToastHost(center: toastCenter)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
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
            guard !(tab == .today && todayRoute == .dashboard),
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

    /// Log time from the fifth tab, widgets, intents and notifications (`LogSheetRoute.forPlusRoute`).
    private var plusRoute: LogSheetRoute {
        LogSheetRoute.forPlusRoute(isTimerRunning: viewModel.isTimerRunning, stoppedDraft: StoppedTimerDraftStore.load())
    }

    private func openLog(_ route: LogSheetRoute) {
        AppToastCenter.shared.dismiss()
        guard logRoute == nil else { return }
        logSheetUp = true
        logRoute = route
    }
}

// MARK: - Shell modifiers

/// §1.25: the bar shrinks to the active tab as the user scrolls down (iOS 26+; the system's own
/// behaviour before that).
private struct TabBarMinimizeOnScroll: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppViewModel())
}

// MARK: - Tab bar identifiers (iOS 26+)

/// SwiftUI's `Tab(...).accessibilityIdentifier(_:)` does not reach the native tab bar's buttons on
/// iOS 26 and 27 (they report an empty identifier), so UI tests, automation and the house-reveal
/// log could not find `tab.today` / `tab.inbox`. This finds the shell's `UITabBarController` and
/// sets each bar item's identifier, matched by the item's title, which the bar button reports.
struct ShellTabBarIdentifierStamp: UIViewRepresentable {
    /// Changes whenever the bar may rebuild its items (badge, selection), so the stamp runs again.
    let token: String

    func makeUIView(context: Context) -> StampView { StampView() }
    func updateUIView(_ view: StampView, context: Context) { view.stamp() }

    final class StampView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            stamp()
        }

        func stamp() {
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window else { return }
                ShellTabBarIdentifiers.apply(in: window)
            }
        }
    }
}

enum ShellTabBarIdentifiers {
    static func apply(in window: UIWindow) {
        guard let bar = tabBarController(from: window.rootViewController) else { return }
        let byTitle = Dictionary(ShellItem.allCases.map { ($0.title, $0.accessibilityIdentifier) },
                                 uniquingKeysWith: { first, _ in first })
        for item in bar.tabBar.items ?? [] {
            guard let title = item.title, let id = byTitle[title] else { continue }
            if item.accessibilityIdentifier != id { item.accessibilityIdentifier = id }
        }
    }

    private static func tabBarController(from root: UIViewController?) -> UITabBarController? {
        guard let root else { return nil }
        if let bar = root as? UITabBarController { return bar }
        for child in root.children {
            if let bar = tabBarController(from: child) { return bar }
        }
        return nil
    }
}
