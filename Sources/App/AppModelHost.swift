import Foundation
import UIKit

// MARK: - Background task seam

/// Keeps the process alive while a background write and its iCloud push finish.
protocol BackgroundTaskRunning: AnyObject {
    @MainActor func beginTask(named name: String, expiration: @escaping @MainActor () -> Void) -> Int
    @MainActor func endTask(_ id: Int)
}

final class UIApplicationBackgroundTasks: BackgroundTaskRunning {
    @MainActor func beginTask(named name: String, expiration: @escaping @MainActor () -> Void) -> Int {
        var id: UIBackgroundTaskIdentifier = .invalid
        id = UIApplication.shared.beginBackgroundTask(withName: name) {
            MainActor.assumeIsolated { expiration() }
        }
        return id.rawValue
    }

    @MainActor func endTask(_ id: Int) {
        let identifier = UIBackgroundTaskIdentifier(rawValue: id)
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
    }
}

// MARK: - App model host
//
// The single writer. It creates the ONE AppViewModel at launch, outside SwiftUI, so paths that
// run with no scene (a notification action, an App Intent, a CloudKit push, a future background
// refresh) write through the same model the UI shows. Before 2.0 the model was a SwiftUI
// @StateObject published to AppDelegate only in `onAppear`, so a scene-less launch had no model
// and a second model would have overwritten the first's writes.
@MainActor
final class AppModelHost {
    /// Created on first access; `AppDelegate.didFinishLaunching` touches it so it exists before
    /// any scene, notification response or intent.
    static let shared = AppModelHost()

    let viewModel: AppViewModel
    private let backgroundTasks: BackgroundTaskRunning
    private let suggestionBaseDirectory: URL
    private var cachedStore: SuggestionStore?

    /// Whether a scene is in the foreground. Until one is, celebrations are queued.
    private(set) var isSceneActive = false

    init(
        viewModel: AppViewModel? = nil,
        backgroundTasks: BackgroundTaskRunning = UIApplicationBackgroundTasks(),
        suggestionBaseDirectory: URL? = nil
    ) {
        self.viewModel = viewModel ?? AppViewModel()
        self.backgroundTasks = backgroundTasks
        self.suggestionBaseDirectory = suggestionBaseDirectory ?? SuggestionStore.defaultBaseDirectory
        self.viewModel.queuesCelebrations = true
    }

    /// The active profile's capture inbox, or nil when no profile is signed in. Re-opened when
    /// the profile changes.
    var suggestionStore: SuggestionStore? {
        guard let userId = UserScope.userId else {
            cachedStore = nil
            return nil
        }
        if let cachedStore, cachedStore.userId == userId { return cachedStore }
        let store = SuggestionStore(userId: userId, baseDirectory: suggestionBaseDirectory)
        cachedStore = store
        return store
    }

    /// Scene phase changes from the App. Becoming active stops queueing celebrations and shows
    /// any milestone crossed while in the background.
    func sceneDidChange(isActive: Bool) {
        isSceneActive = isActive
        viewModel.queuesCelebrations = !isActive
        if isActive {
            viewModel.presentPendingCelebrationIfAny()
            // The Inbox may have grown in the background (end-of-visit detection): redraw the widget.
            viewModel.refreshWidgetSurface()
        }
    }

    /// Runs a write against the single model while holding a background-task assertion. The
    /// write is synchronous on the main actor, so when this returns the data is on disk.
    /// Celebrations crossed during the write are queued if no scene is active.
    @discardableResult
    func performWrite<T>(named name: String, _ work: (AppViewModel) -> T) -> T {
        let taskId = backgroundTasks.beginTask(named: name) {}
        defer { backgroundTasks.endTask(taskId) }
        return work(viewModel)
    }

    /// Pushes to iCloud while holding a background-task assertion. A push the sync gate holds
    /// (initial pull not done yet on this launch) is sent on the next launch.
    func pushHoldingBackgroundTask(named name: String = "LandlordHours.push") async {
        var ended = false
        var taskId = 0
        taskId = backgroundTasks.beginTask(named: name) { [weak self] in
            guard !ended else { return }
            ended = true
            self?.backgroundTasks.endTask(taskId)
        }
        await viewModel.syncService.pushAll()
        if !ended {
            ended = true
            backgroundTasks.endTask(taskId)
        }
    }
}
