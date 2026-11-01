import Foundation
import UserNotifications

// MARK: - The day-12 billing reminder as a local notification (2.3)
//
// Scheduled for `TrialSchedule.current(plan).reminder` while a trial will renew; cancelled the
// moment it won't (auto-renew off, the trial ended, Pro bought, a founding buyer). It is not a
// nudge: it ignores the nudge switches and quiet hours (package D). It never asks for permission:
// it schedules only when notifications are already allowed. Opening the app on or after the
// reminder day shows the day-12 sheet either way (`ProPaywallHost`).

/// What the scheduler needs from `UNUserNotificationCenter` (a fake in tests).
protocol TrialReminderCenter: AnyObject {
    func canSchedule() async -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePending(_ identifiers: [String])
    func pendingIdentifiers() async -> [String]
}

final class SystemTrialReminderCenter: TrialReminderCenter {
    private let center = UNUserNotificationCenter.current()

    func canSchedule() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func removePending(_ identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    func pendingIdentifiers() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }
}

@MainActor
final class TrialReminderScheduler {
    static let shared = TrialReminderScheduler()
    /// One identifier per trial, so a new trial never reuses an old request.
    static let identifierPrefix = "trial.day12."

    static func identifier(_ originalTransactionID: UInt64) -> String { "\(identifierPrefix)\(originalTransactionID)" }

    private let center: TrialReminderCenter
    private let clock: () -> Date

    init(center: TrialReminderCenter = SystemTrialReminderCenter(), clock: @escaping () -> Date = Date.init) {
        self.center = center
        self.clock = clock
    }

    /// The decision, pure: the request to schedule for this plan, or nil (and every old one goes).
    struct ReminderRequest: Equatable {
        let identifier: String
        let fireAt: Date
        let renewal: Date
    }

    static func decide(plan: Plan, now: Date, calendar: Calendar = .current) -> ReminderRequest? {
        guard case .trial(let sub) = plan, sub.willAutoRenew,
              let schedule = TrialSchedule.current(plan, calendar: calendar),
              schedule.reminder > now, schedule.renewal > now else { return nil }
        return ReminderRequest(identifier: identifier(sub.originalTransactionID), fireAt: schedule.reminder, renewal: schedule.renewal)
    }

    /// Brings the pending requests in line with the plan. Safe to call on every plan change.
    func sync(plan: Plan, price: String?) async {
        let wanted = Self.decide(plan: plan, now: clock())
        let stale = await center.pendingIdentifiers().filter {
            $0.hasPrefix(Self.identifierPrefix) && $0 != wanted?.identifier
        }
        if !stale.isEmpty { center.removePending(stale) }
        guard let wanted, await center.canSchedule() else { return }
        if await center.pendingIdentifiers().contains(wanted.identifier) { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "day12.push.title", defaultValue: "Your trial ends in 2 days", table: "Pricing")
        let date = PricingFormat.short(wanted.renewal)
        content.body = price.map {
            String(localized: "day12.push.body", defaultValue: "Pro renews at \($0) a year on \(date). To stop it, cancel in Settings at least a day before.", table: "Pricing")
        } ?? String(localized: "day12.push.bodyNoPrice", defaultValue: "Pro renews on \(date). To stop it, cancel in Settings at least a day before.", table: "Pricing")
        content.sound = .default
        content.threadIdentifier = "trial"
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: wanted.fireAt)
        let request = UNNotificationRequest(identifier: wanted.identifier, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        try? await center.add(request)
    }
}
