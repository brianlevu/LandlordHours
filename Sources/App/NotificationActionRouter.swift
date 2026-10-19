import Foundation
import UserNotifications

// MARK: - Notification payload contract
//
// Every notification the app schedules carries the profile id it was made for. A capture
// action whose profile is no longer active is rejected, so a "Log it" tapped after a profile
// switch can never write into the wrong person's tax records.
enum NotificationPayload {
    static let profileIdKey = "profileId"
    static let destinationKey = "destination"
    static let sourceKeyKey = "sourceKey"

    static func profileId(in userInfo: [AnyHashable: Any]) -> String? {
        userInfo[profileIdKey] as? String
    }
}

/// Identifiers for end-of-event capture notifications. Scheduling lives in
/// `EndOfEventScheduler`; categories (with the user-facing titles) in
/// `CaptureNotificationCategories`.
enum CaptureNotificationAction {
    static let categoryIdentifier = "LANDLORDHOURS_CAPTURE_SUGGESTION"
    /// Must be registered with `.authenticationRequired` (writes a tax record from the lock screen).
    static let logIt = "LANDLORDHOURS_ACTION_CAPTURE_LOG"
    /// Foreground: opens the confirm sheet.
    static let edit = "LANDLORDHOURS_ACTION_CAPTURE_EDIT"
    static let notLandlordWork = "LANDLORDHOURS_ACTION_CAPTURE_DISMISS"
    /// Follow-up after "Log it" couldn't save safely; tapping it opens the confirm sheet.
    static let reviewCategoryIdentifier = "LANDLORDHOURS_CAPTURE_REVIEW"
    /// Follow-up after "Not landlord work": offers to mute events like it.
    static let muteOfferCategoryIdentifier = "LANDLORDHOURS_CAPTURE_MUTE_OFFER"
    static let mute = "LANDLORDHOURS_ACTION_CAPTURE_MUTE"

    /// UserDefaults key the UI reads to open the confirm sheet for a suggestion.
    static let pendingEditKey = "LandlordHours.pendingCaptureEditKey"

    static func userInfo(profileId: String, sourceKey: String) -> [String: Any] {
        [
            NotificationPayload.profileIdKey: profileId,
            NotificationPayload.sourceKeyKey: sourceKey
        ]
    }
}

/// The parts of a `UNNotificationResponse` the router needs (responses can't be built in tests).
struct NotificationActionRequest {
    var actionIdentifier: String
    var categoryIdentifier: String
    var userInfo: [AnyHashable: Any]

    init(actionIdentifier: String, categoryIdentifier: String = "", userInfo: [AnyHashable: Any]) {
        self.actionIdentifier = actionIdentifier
        self.categoryIdentifier = categoryIdentifier
        self.userInfo = userInfo
    }

    init(_ response: UNNotificationResponse) {
        self.init(
            actionIdentifier: response.actionIdentifier,
            categoryIdentifier: response.notification.request.content.categoryIdentifier,
            userInfo: response.notification.request.content.userInfo
        )
    }
}

// MARK: - Router

/// Handles notification responses against the single model (`AppModelHost`). The caller's
/// completion handler is called only AFTER any write is on disk; an iCloud push then runs
/// under a background-task assertion.
@MainActor
final class NotificationActionRouter {
    enum EditReason: Equatable {
        case mightAlreadyBeLogged
        case eventMoved
        case cannotVerify
    }

    enum Outcome: Equatable {
        case navigated(LandlordHoursIntentDestination)
        case confirmed(entryId: UUID)
        case alreadyRecorded(entryId: UUID)
        case needsInput
        case openedForEdit
        /// "Log it" didn't write; the confirm sheet opens next time the app does.
        case routedToEdit(EditReason)
        /// "Log it" didn't write: the event is no longer on the calendar.
        case eventGone
        /// Waiting for protected data or the initial iCloud pull; replayed later.
        case queued
        case dismissed
        case muted
        case rejectedWrongProfile
        case suggestionNotFound
        case ignored
    }

    private let host: AppModelHost
    private let environment: CaptureActionEnvironment
    /// Test seam: observes the moment the write finished, before completion is called.
    var onWriteFinished: (() -> Void)?

    init(host: AppModelHost, environment: CaptureActionEnvironment? = nil) {
        self.host = host
        self.environment = environment ?? .live
    }

    /// Handles one response. `completion` is the system's completion handler.
    @discardableResult
    func handle(_ request: NotificationActionRequest, completion: @escaping () -> Void) async -> Outcome {
        let captureCategories = [
            CaptureNotificationAction.categoryIdentifier,
            CaptureNotificationAction.reviewCategoryIdentifier,
            CaptureNotificationAction.muteOfferCategoryIdentifier
        ]
        let isCaptureAction = [
            CaptureNotificationAction.logIt,
            CaptureNotificationAction.edit,
            CaptureNotificationAction.notLandlordWork,
            CaptureNotificationAction.mute
        ].contains(request.actionIdentifier)
            || captureCategories.contains(request.categoryIdentifier)

        guard isCaptureAction else {
            let outcome = routeNavigation(request)
            completion()
            return outcome
        }

        let (outcome, wroteRecord) = await handleCapture(request)
        onWriteFinished?()
        completion()
        if wroteRecord {
            await host.pushHoldingBackgroundTask(named: "LandlordHours.capture.push")
        }
        return outcome
    }

    // MARK: Capture actions

    private func handleCapture(_ request: NotificationActionRequest) async -> (Outcome, Bool) {
        guard let profileId = NotificationPayload.profileId(in: request.userInfo),
              profileId == UserScope.userId else {
            return (.rejectedWrongProfile, false)
        }
        guard let key = request.userInfo[NotificationPayload.sourceKeyKey] as? String else {
            return (.suggestionNotFound, false)
        }
        // Locked data reads as an empty store (and a save would overwrite the real one).
        guard environment.isProtectedDataAvailable() else {
            switch request.actionIdentifier {
            case CaptureNotificationAction.logIt:
                enqueue(.confirm, key: key, profileId: profileId)
                return (.queued, false)
            case CaptureNotificationAction.notLandlordWork:
                enqueue(.dismiss, key: key, profileId: profileId)
                return (.queued, false)
            case CaptureNotificationAction.mute:
                return (.ignored, false)
            default:
                routeToEdit(key)
                return (.openedForEdit, false)
            }
        }
        guard let store = host.suggestionStore, let suggestion = store.suggestion(forKey: key) else {
            return (.suggestionNotFound, false)
        }

        switch request.actionIdentifier {
        case CaptureNotificationAction.logIt:
            return await logIt(suggestion, store: store, profileId: profileId)
        case CaptureNotificationAction.notLandlordWork:
            host.performWrite(named: "LandlordHours.capture.dismiss") { model in
                model.dismiss(suggestion, reason: .notLandlordWork, store: store)
            }
            if !store.isMuted(suggestion) {
                await environment.followUps.post(.offerMute, for: suggestion, profileId: profileId)
            }
            return (.dismissed, false)
        case CaptureNotificationAction.mute:
            let title = suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return (.ignored, false) }
            let before = Set(store.pending.map(\.sourceKey))
            host.performWrite(named: "LandlordHours.capture.mute") { _ in
                store.addMuteRule(CaptureMuteRule(match: .titleContains, value: title))
            }
            let mutedKeys = before.subtracting(store.pending.map(\.sourceKey))
            await environment.notifier?.cancel(sourceKeys: Array(mutedKeys).sorted())
            return (.muted, false)
        default:
            // Edit… or a plain tap on the notification: open the confirm sheet.
            routeToEdit(key)
            return (.openedForEdit, false)
        }
    }

    /// "Log it": hold until this profile's first iCloud pull (an old import or a confirm from
    /// another device may not be on this phone yet), then the tap-time checks.
    private func logIt(_ suggestion: Suggestion, store: SuggestionStore, profileId: String) async -> (Outcome, Bool) {
        let gate = environment.pullGate(host)
        guard gate.state(for: profileId) == .pending else {
            return await logItChecked(suggestion.sourceKey, store: store, profileId: profileId)
        }
        // Queue first, so a suspension during the wait can't lose the tap.
        enqueue(.confirm, key: suggestion.sourceKey, profileId: profileId)
        let pulled = await gate.waitForInitialPull(profileId: profileId, timeout: environment.pullWaitTimeout)
        // Still pending (slow or failed pull): stays queued. Turned out to have no iCloud
        // (checked during the wait): nothing to wait for, go ahead.
        guard pulled || gate.state(for: profileId) != .pending else {
            return (.queued, false)
        }
        CaptureActionQueue.remove(profileId: profileId, sourceKey: suggestion.sourceKey, defaults: environment.defaults)
        return await logItChecked(suggestion.sourceKey, store: store, profileId: profileId)
    }

    /// Re-checks the event and "might already be logged" at tap time, then confirms.
    private func logItChecked(_ key: String, store: SuggestionStore, profileId: String) async -> (Outcome, Bool) {
        // Re-resolve against current entries (a pull, a manual log, another device's confirm).
        store.reconcile(with: host.viewModel.timeEntries)
        guard let suggestion = store.suggestion(forKey: key) else { return (.suggestionNotFound, false) }

        switch suggestion.state {
        case .confirmed(let id):
            await environment.notifier?.cancel(sourceKeys: [key])
            return (.alreadyRecorded(entryId: id), false)
        case .dismissed:
            // Dismissed in the app after this notification went out: don't write blind.
            routeToEdit(key)
            return (.routedToEdit(.cannotVerify), false)
        case .pending:
            break
        }

        switch await environment.eventChecker.check(suggestion) {
        case .unchanged:
            break
        case .gone:
            await environment.followUps.post(.eventGone, for: suggestion, profileId: profileId)
            return (.eventGone, false)
        case .moved:
            routeToEdit(key)
            await environment.followUps.post(.eventMoved, for: suggestion, profileId: profileId)
            return (.routedToEdit(.eventMoved), false)
        case .unverifiable:
            routeToEdit(key)
            await environment.followUps.post(.cannotVerify, for: suggestion, profileId: profileId)
            return (.routedToEdit(.cannotVerify), false)
        }

        if suggestion.mightAlreadyBeLogged {
            routeToEdit(key)
            await environment.followUps.post(.mightAlreadyBeLogged, for: suggestion, profileId: profileId)
            return (.routedToEdit(.mightAlreadyBeLogged), false)
        }

        let result = host.performWrite(named: "LandlordHours.capture.confirm") { model in
            model.confirm(suggestion, store: store)
        }
        switch result {
        case .created(let id):
            await environment.notifier?.cancel(sourceKeys: [key])
            return (.confirmed(entryId: id), true)
        case .alreadyRecorded(let id):
            await environment.notifier?.cancel(sourceKeys: [key])
            return (.alreadyRecorded(entryId: id), false)
        case .needsInput:
            routeToEdit(key)
            await environment.followUps.post(.needsInput, for: suggestion, profileId: profileId)
            return (.needsInput, false)
        }
    }

    private func routeToEdit(_ key: String) {
        UserDefaults.standard.set(key, forKey: CaptureNotificationAction.pendingEditKey)
    }

    private func enqueue(_ kind: QueuedCaptureAction.Kind, key: String, profileId: String) {
        CaptureActionQueue.enqueue(
            QueuedCaptureAction(profileId: profileId, sourceKey: key, kind: kind, queuedAt: Date()),
            defaults: environment.defaults
        )
    }

    // MARK: Queued actions

    /// Replays queued "Log it" / "Not landlord work" taps for the active profile. Run when the
    /// initial iCloud pull completes and when the app comes to the foreground. A confirm whose
    /// pull is still pending stays queued. Returns each key's outcome.
    @discardableResult
    func drainQueuedActions(now: Date = Date()) async -> [String: Outcome] {
        CaptureActionQueue.prune(now: now, defaults: environment.defaults)
        guard environment.isProtectedDataAvailable(),
              let profileId = UserScope.userId,
              let store = host.suggestionStore else { return [:] }
        let items = CaptureActionQueue.all(defaults: environment.defaults).filter { $0.profileId == profileId }
        guard !items.isEmpty else { return [:] }
        let gate = environment.pullGate(host)
        var outcomes: [String: Outcome] = [:]
        var wroteRecord = false
        for item in items {
            guard store.suggestion(forKey: item.sourceKey) != nil else {
                CaptureActionQueue.remove(profileId: profileId, sourceKey: item.sourceKey, defaults: environment.defaults)
                outcomes[item.sourceKey] = .suggestionNotFound
                continue
            }
            switch item.kind {
            case .dismiss:
                if let suggestion = store.suggestion(forKey: item.sourceKey) {
                    host.performWrite(named: "LandlordHours.capture.dismiss") { model in
                        model.dismiss(suggestion, reason: .notLandlordWork, store: store)
                    }
                }
                CaptureActionQueue.remove(profileId: profileId, sourceKey: item.sourceKey, defaults: environment.defaults)
                outcomes[item.sourceKey] = .dismissed
            case .confirm:
                guard gate.state(for: profileId) != .pending else {
                    outcomes[item.sourceKey] = .queued
                    continue
                }
                CaptureActionQueue.remove(profileId: profileId, sourceKey: item.sourceKey, defaults: environment.defaults)
                let (outcome, wrote) = await logItChecked(item.sourceKey, store: store, profileId: profileId)
                wroteRecord = wroteRecord || wrote
                outcomes[item.sourceKey] = outcome
            }
        }
        if wroteRecord {
            await host.pushHoldingBackgroundTask(named: "LandlordHours.capture.push")
        }
        return outcomes
    }

    // MARK: Navigation (1.1 behaviour, unchanged)

    private func routeNavigation(_ request: NotificationActionRequest) -> Outcome {
        guard let rawDestination = request.userInfo[NotificationPayload.destinationKey] as? String,
              let destination = Self.notificationDestination(for: rawDestination) else {
            return .ignored
        }
        UserDefaults.standard.set(destination.rawValue, forKey: AppIntentNavigationRequest.pendingDestinationKey)
        Task { @MainActor in
            NotificationCenter.default.post(name: .switchToTab, object: destination.tabIndex)
        }
        return .navigated(destination)
    }

    static func notificationDestination(for rawDestination: String) -> LandlordHoursIntentDestination? {
        if let directDestination = LandlordHoursIntentDestination(rawValue: rawDestination) {
            return directDestination
        }

        guard let engagementDestination = EngagementDestination(rawValue: rawDestination) else {
            return nil
        }

        switch engagementDestination {
        case .addProperty:
            return .properties
        case .track, .timerReview:
            return .track
        case .reports, .calendarReview, .export:
            return .reports
        case .none:
            return .home
        }
    }
}
