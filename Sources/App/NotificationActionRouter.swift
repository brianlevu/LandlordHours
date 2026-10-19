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

/// Identifiers for end-of-event capture notifications. Scheduling and category registration
/// (with the user-facing titles) belong to the notifications work package; the router below
/// already handles these actions so the write path is tested from day one.
enum CaptureNotificationAction {
    static let categoryIdentifier = "LANDLORDHOURS_CAPTURE_SUGGESTION"
    /// Must be registered with `.authenticationRequired` (writes a tax record from the lock screen).
    static let logIt = "LANDLORDHOURS_ACTION_CAPTURE_LOG"
    /// Foreground: opens the confirm sheet.
    static let edit = "LANDLORDHOURS_ACTION_CAPTURE_EDIT"
    static let notLandlordWork = "LANDLORDHOURS_ACTION_CAPTURE_DISMISS"

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
    enum Outcome: Equatable {
        case navigated(LandlordHoursIntentDestination)
        case confirmed(entryId: UUID)
        case alreadyRecorded(entryId: UUID)
        case needsInput
        case openedForEdit
        case dismissed
        case rejectedWrongProfile
        case suggestionNotFound
        case ignored
    }

    private let host: AppModelHost
    /// Test seam: observes the moment the write finished, before completion is called.
    var onWriteFinished: (() -> Void)?

    init(host: AppModelHost) {
        self.host = host
    }

    /// Handles one response. `completion` is the system's completion handler.
    @discardableResult
    func handle(_ request: NotificationActionRequest, completion: @escaping () -> Void) async -> Outcome {
        let isCaptureAction = [
            CaptureNotificationAction.logIt,
            CaptureNotificationAction.edit,
            CaptureNotificationAction.notLandlordWork
        ].contains(request.actionIdentifier)
            || request.categoryIdentifier == CaptureNotificationAction.categoryIdentifier

        guard isCaptureAction else {
            let outcome = routeNavigation(request)
            completion()
            return outcome
        }

        let (outcome, wroteRecord) = handleCapture(request)
        onWriteFinished?()
        completion()
        if wroteRecord {
            await host.pushHoldingBackgroundTask(named: "LandlordHours.capture.push")
        }
        return outcome
    }

    // MARK: Capture actions

    private func handleCapture(_ request: NotificationActionRequest) -> (Outcome, Bool) {
        guard let profileId = NotificationPayload.profileId(in: request.userInfo),
              profileId == UserScope.userId else {
            return (.rejectedWrongProfile, false)
        }
        guard let key = request.userInfo[NotificationPayload.sourceKeyKey] as? String,
              let store = host.suggestionStore,
              let suggestion = store.suggestion(forKey: key) else {
            return (.suggestionNotFound, false)
        }

        switch request.actionIdentifier {
        case CaptureNotificationAction.logIt:
            let result = host.performWrite(named: "LandlordHours.capture.confirm") { model in
                model.confirm(suggestion, store: store)
            }
            switch result {
            case .created(let id): return (.confirmed(entryId: id), true)
            case .alreadyRecorded(let id): return (.alreadyRecorded(entryId: id), false)
            case .needsInput:
                UserDefaults.standard.set(key, forKey: CaptureNotificationAction.pendingEditKey)
                return (.needsInput, false)
            }
        case CaptureNotificationAction.notLandlordWork:
            host.performWrite(named: "LandlordHours.capture.dismiss") { model in
                model.dismiss(suggestion, reason: .notLandlordWork, store: store)
            }
            return (.dismissed, false)
        default:
            // Edit… or a plain tap on the notification: open the confirm sheet.
            UserDefaults.standard.set(key, forKey: CaptureNotificationAction.pendingEditKey)
            return (.openedForEdit, false)
        }
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
