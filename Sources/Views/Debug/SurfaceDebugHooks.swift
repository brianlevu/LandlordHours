import Foundation
import UserNotifications

#if DEBUG
// MARK: - DEBUG hooks for surfaces captures (compiled out of Release)
//
//   -LHDebugToast saveError|loadError|propertyAdded|timerDiscarded|undo
//       shows that toast in the real shell (through LHToastCenter), held for captures.
//   -LHDebugPostSampleNotifications
//       asks for notification permission, registers the real categories and posts the 2.0
//       notifications built by NotificationCopy (end of visit, two follow-ups, two nudges), so a
//       UI test can capture them on the simulator's Lock Screen / Notification Center.

@MainActor
enum SurfaceDebugHooks {
    private static var applied = false

    static func apply(toasts: LHToastCenter, app: AppViewModel) {
        guard !applied else { return }
        applied = true
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-LHDebugToast"), args.indices.contains(i + 1) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { showToast(args[i + 1], center: toasts, app: app) }
        }
        if args.contains("-LHDebugPostSampleNotifications") {
            Task { await postSampleNotifications() }
        }
    }

    private static func showToast(_ name: String, center: LHToastCenter, app: AppViewModel) {
        switch name {
        case "saveError": center.show(.problem, AppViewModel.saveFailureMessage, actionTitle: "Retry") {}
        case "loadError": center.show(.problem, AppViewModel.loadFailureMessage, actionTitle: "Help") {}
        case "propertyAdded":
            center.show(.success, "Added \(app.properties.first?.name ?? "The Arroyo Seco Schoolhouse Lofts, Unit 4B")")
        case "propertyAddedLong": center.show(.success, "Added The Arroyo Seco Schoolhouse Lofts, Unit 4B")
        case "timerDiscarded": center.show(.neutral, "Timer discarded", actionTitle: "Undo") {}
        case "undo": center.show(.neutral, "Marked not rental work", actionTitle: "Undo") {}
        default: break
        }
    }

    static func postSampleNotifications() async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }
        center.setNotificationCategories(CaptureNotificationCategories.all)
        center.removeAllDeliveredNotifications()
        let samples: [(String, NotificationText, String)] = [
            ("sample.yearEnd", NotificationCopy.yearEnd(hours: 212.5, year: 2026), "LANDLORDHOURS_EXPORT"),
            ("sample.quiet", NotificationCopy.inactive(days: 9), "LANDLORDHOURS_TRACK"),
            ("sample.moved", NotificationCopy.followUp(.eventMoved, eventTitle: "Showing at Pine Cabin"), CaptureNotificationAction.reviewCategoryIdentifier),
            ("sample.mute", NotificationCopy.followUp(.offerMute, eventTitle: "Dentist"), CaptureNotificationAction.muteOfferCategoryIdentifier),
            ("sample.endOfVisit", NotificationCopy.endOfVisit(eventTitle: "Plumber visit", timing: .justEnded, hours: 2, propertyName: "Pine Cabin"),
             CaptureNotificationAction.categoryIdentifier),
        ]
        for (offset, sample) in samples.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = sample.1.title
            content.body = sample.1.body
            content.categoryIdentifier = sample.2
            content.threadIdentifier = "sample.\(sample.0)"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3 + Double(offset) * 0.6, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: sample.0, content: content, trigger: trigger))
        }
    }
}
#endif
