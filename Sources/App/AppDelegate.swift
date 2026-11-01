import SwiftUI
import UserNotifications

// MARK: - App Delegate (CloudKit remote notifications)

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = self
        registerEngagementNotificationCategories(center: notificationCenter)
        application.registerForRemoteNotifications()
        Analytics.configure()
        Analytics.appOpened()
        RatingPromptCoordinator.shared.recordLaunch()
        LandlordPurchases.configure()
        // The single model exists before any scene, notification response or intent.
        _ = AppModelHost.shared
        startCaptureNotifications()
        startNudges()
        return true
    }

    // MARK: End-of-event notifications (2.0)

    private var foregroundObserver: NSObjectProtocol?
    private var timeZoneObserver: NSObjectProtocol?

    /// Registers the BGAppRefresh handler (must happen during launch), then rebuilds the
    /// end-of-event schedule now, on every foreground, and in background refreshes. Queued
    /// "Log it" taps are replayed when the initial iCloud pull finishes or the app comes back.
    private func startCaptureNotifications() {
        CaptureNotificationRefresher.registerBackgroundRefresh()
        // Unit tests drive these pieces directly; the test host stays quiet.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        let host = AppModelHost.shared
        host.viewModel.syncService.onInitialSyncCompleted = { _ in
            Task { @MainActor in
                await NotificationActionRouter(host: AppModelHost.shared).drainQueuedActions()
                await CaptureNotificationRefresher.shared.refresh(reason: "initial-pull")
            }
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                await NotificationActionRouter(host: AppModelHost.shared).drainQueuedActions()
                await CaptureNotificationRefresher.shared.refresh(reason: "foreground")
                CaptureNotificationRefresher.scheduleBackgroundRefresh()
            }
        }
        // Travel or a DST switch moves quiet hours and "yesterday" in the copy: rebuild.
        timeZoneObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                await CaptureNotificationRefresher.shared.refresh(reason: "time-zone")
            }
        }
        Task { @MainActor in
            await CaptureNotificationRefresher.shared.refresh(reason: "launch")
            CaptureNotificationRefresher.scheduleBackgroundRefresh()
        }
    }

    // MARK: Pace and care nudges (2.3)

    private var nudgeObservers: [NSObjectProtocol] = []

    /// Rebuilds the opt-in nudges at launch, on every foreground and background (so the numbers in
    /// the next weekly note are the latest), and when the time zone changes (quiet hours move).
    private func startNudges() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        #if DEBUG
        NudgeDebug.applyLaunchSeeds()
        #endif
        let rebuild: (String) -> Void = { reason in
            Task { @MainActor in await NudgeScheduler.shared.rebuild(reason: reason) }
        }
        let center = NotificationCenter.default
        nudgeObservers = [
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in rebuild("foreground") },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in rebuild("background") },
            center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { _ in rebuild("time-zone") }
        ]
        rebuild("launch")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // CloudKit subscription notification — pull changes into the single model, which
        // exists even when iOS launched the app in the background with no scene.
        Task { @MainActor in
            let pulled = await AppModelHost.shared.viewModel.syncService.pullChanges()
            completionHandler(pulled ? .newData : .noData)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = NotificationActionRequest(response)
        Task { @MainActor in
            // The router calls the completion handler only after any write is saved.
            await NotificationActionRouter(host: AppModelHost.shared).handle(request, completion: completionHandler)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // A nudge made for another profile never shows (the profile was switched since).
        let info = notification.request.content.userInfo
        if notification.request.content.categoryIdentifier == NudgeNotification.category,
           let profile = NotificationPayload.profileId(in: info), profile != UserScope.userId {
            completionHandler([])
            return
        }
        #if DEBUG
        completionHandler([.banner, .list])
        #else
        completionHandler([.list])
        #endif
    }

    private func registerEngagementNotificationCategories(center: UNUserNotificationCenter) {
        let foreground: UNNotificationActionOptions = [.foreground]
        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(
                identifier: "LANDLORDHOURS_TRACK",
                actions: [
                    UNNotificationAction(identifier: "LANDLORDHOURS_ACTION_TRACK", title: "Log time", options: foreground)
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "LANDLORDHOURS_REVIEW_CALENDAR",
                actions: [
                    UNNotificationAction(identifier: "LANDLORDHOURS_ACTION_REVIEW_CALENDAR", title: "See what’s waiting", options: foreground)
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "LANDLORDHOURS_EXPORT",
                actions: [
                    UNNotificationAction(identifier: "LANDLORDHOURS_ACTION_EXPORT", title: "Make the PDF", options: foreground)
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "LANDLORDHOURS_REPORTS",
                actions: [
                    UNNotificationAction(identifier: "LANDLORDHOURS_ACTION_REPORTS", title: "Open reports", options: foreground)
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "LANDLORDHOURS_ADD_PROPERTY",
                actions: [
                    UNNotificationAction(identifier: "LANDLORDHOURS_ACTION_ADD_PROPERTY", title: "Add property", options: foreground)
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "LANDLORDHOURS_TIMER",
                actions: [
                    UNNotificationAction(identifier: "LANDLORDHOURS_ACTION_TIMER", title: "Check the timer", options: foreground)
                ],
                intentIdentifiers: [],
                options: []
            )
        ]

        // 2.0 end-of-event capture categories (Log it / Edit… / Not rental work, follow-ups).
        center.setNotificationCategories(categories.union(CaptureNotificationCategories.all))
    }

}
