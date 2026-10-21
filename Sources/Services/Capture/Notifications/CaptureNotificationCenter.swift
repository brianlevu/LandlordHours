import Foundation
import UserNotifications

// MARK: - Notification center seam
//
// The scheduler and the follow-ups talk to this protocol, never to UNUserNotificationCenter
// directly, so budget, quiet hours, rebuild and cancel are unit-tested with a fake.

protocol CaptureNotificationCenter: AnyObject {
    func pendingRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func removePending(identifiers: [String])
    func removeDelivered(identifiers: [String])
    /// Authorized or provisional. Never prompts.
    func canDeliver() async -> Bool
}

final class SystemCaptureNotificationCenter: CaptureNotificationCenter {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePending(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDelivered(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func canDeliver() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        case .denied, .notDetermined: return false
        @unknown default: return false
        }
    }
}

// MARK: - Categories
//
// Registered at launch (AppDelegate) next to the 1.x engagement categories. Identifiers live
// in `CaptureNotificationAction` (NotificationActionRouter.swift).

enum CaptureNotificationCategories {
    /// End-of-event prompt: Log it / Edit… / Not rental work.
    static var suggestion: UNNotificationCategory {
        UNNotificationCategory(
            identifier: CaptureNotificationAction.categoryIdentifier,
            actions: [
                // Writes a tax record from the lock screen, so the device must be unlocked.
                UNNotificationAction(identifier: CaptureNotificationAction.logIt, title: NotificationCopy.Action.logIt.title,
                                     options: [.authenticationRequired], icon: NotificationCopy.Action.logIt.icon),
                UNNotificationAction(identifier: CaptureNotificationAction.edit, title: NotificationCopy.Action.edit.title,
                                     options: [.foreground], icon: NotificationCopy.Action.edit.icon),
                UNNotificationAction(identifier: CaptureNotificationAction.notLandlordWork, title: NotificationCopy.Action.notRentalWork.title,
                                     options: [], icon: NotificationCopy.Action.notRentalWork.icon)
            ],
            intentIdentifiers: [],
            options: []
        )
    }

    /// Follow-up when "Log it" could not save safely: tap opens the confirm sheet.
    static var review: UNNotificationCategory {
        UNNotificationCategory(
            identifier: CaptureNotificationAction.reviewCategoryIdentifier,
            actions: [
                UNNotificationAction(identifier: CaptureNotificationAction.edit, title: "Review",
                                     options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "pencil"))
            ],
            intentIdentifiers: [],
            options: []
        )
    }

    /// Follow-up after "Not rental work": offers to stop suggesting events like it.
    static var muteOffer: UNNotificationCategory {
        UNNotificationCategory(
            identifier: CaptureNotificationAction.muteOfferCategoryIdentifier,
            actions: [
                UNNotificationAction(identifier: CaptureNotificationAction.mute, title: "Stop suggesting these",
                                     options: [.authenticationRequired])
            ],
            intentIdentifiers: [],
            options: []
        )
    }

    static var all: Set<UNNotificationCategory> { [suggestion, review, muteOffer] }
}
