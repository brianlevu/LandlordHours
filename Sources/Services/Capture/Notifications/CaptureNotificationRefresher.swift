import Foundation
import UIKit
import BackgroundTasks
import os.log

private let refreshLogger = Logger(subsystem: "com.openclaw.landlordhours", category: "CaptureRefresh")

// MARK: - Refresh: scan upcoming events, rebuild end-of-event notifications
//
// Runs on launch, on every foreground, and in an opportunistic BGAppRefresh. Each run:
// iPhone only → protected data readable → a profile → kill switch on → notifications allowed
// → scan the next 7 days (only with full calendar access; never prompts) → reconcile the inbox
// with current entries → rebuild the schedule from the full pending list.
@MainActor
final class CaptureNotificationRefresher {
    static let shared = CaptureNotificationRefresher()

    /// How soon to ask iOS for the next background refresh (iOS decides when it really runs).
    static let backgroundRefreshInterval: TimeInterval = 4 * 3600

    let scheduler: EndOfEventScheduler
    private let host: @MainActor () -> AppModelHost
    private let flags: CaptureFlags
    private let isPhone: () -> Bool
    private let isProtectedDataAvailable: () -> Bool
    private let canDeliver: () async -> Bool
    private let makeCoordinator: (SuggestionStore) -> CalendarCaptureCoordinator

    private var inFlight: Task<Void, Never>?
    /// Test seam: completed runs.
    private(set) var completedRuns = 0

    init(
        scheduler: EndOfEventScheduler? = nil,
        host: @escaping @MainActor () -> AppModelHost = { AppModelHost.shared },
        flags: CaptureFlags = CaptureFlags(),
        isPhone: @escaping () -> Bool = { UIDevice.current.userInterfaceIdiom == .phone },
        isProtectedDataAvailable: @escaping () -> Bool = { UIApplication.shared.isProtectedDataAvailable },
        canDeliver: (() async -> Bool)? = nil,
        makeCoordinator: ((SuggestionStore) -> CalendarCaptureCoordinator)? = nil
    ) {
        let scheduler = scheduler ?? EndOfEventScheduler(propertyNames: {
            Dictionary(AppModelHost.shared.viewModel.properties.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        })
        self.scheduler = scheduler
        self.host = host
        self.flags = flags
        self.isPhone = isPhone
        self.isProtectedDataAvailable = isProtectedDataAvailable
        let center = SystemCaptureNotificationCenter()
        self.canDeliver = canDeliver ?? { await center.canDeliver() }
        self.makeCoordinator = makeCoordinator ?? { store in
            CalendarCaptureCoordinator(detector: CalendarDetector(source: EventKitCalendarSource()), store: store)
        }
    }

    /// One run at a time; a call while a run is in flight joins it.
    func refresh(reason: String) async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await self.run(reason: reason) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func run(reason: String) async {
        defer { completedRuns += 1 }
        guard isPhone() else {
            await scheduler.removeAllPending()
            return
        }
        guard isProtectedDataAvailable() else { return }
        guard let profileId = UserScope.userId else {
            await scheduler.removeAllPending()
            return
        }
        guard flags.isEnabled(.autoCapture) else {
            await scheduler.removeAllPending()
            return
        }
        guard await canDeliver() else {
            await scheduler.removeAllPending()
            return
        }
        let host = host()
        guard let store = host.suggestionStore, store.userId == profileId else { return }
        let model = host.viewModel

        let coordinator = makeCoordinator(store)
        if coordinator.access == .fullAccess {
            let result = await coordinator.scanUpcoming(properties: model.properties, entries: model.timeEntries)
            refreshLogger.info("Capture refresh (\(reason, privacy: .public)): \(result.added.count) new")
        }
        store.reconcile(with: model.timeEntries)
        // The profile may have switched while scanning; the next run picks the new one up.
        guard UserScope.userId == profileId else { return }
        await scheduler.schedule(store.pending, profileId: profileId)
    }

    // MARK: Background refresh

    /// Must run before the end of `didFinishLaunching`.
    static func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundTaskIdentifiers.captureRefresh, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                handle(refreshTask)
            }
        }
    }

    @MainActor private static func handle(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        let work = Task { @MainActor in
            await CaptureNotificationRefresher.shared.refresh(reason: "background")
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    /// Asks iOS for the next opportunistic refresh. Replaces any earlier request.
    static func scheduleBackgroundRefresh(now: Date = Date()) {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundTaskIdentifiers.captureRefresh)
        request.earliestBeginDate = now.addingTimeInterval(backgroundRefreshInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Simulator, Background App Refresh off, or Low Power Mode: launch and foreground
            // refreshes still run.
            refreshLogger.info("Background refresh not scheduled: \(error.localizedDescription, privacy: .public)")
        }
    }
}
