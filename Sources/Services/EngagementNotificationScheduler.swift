import Foundation
import UserNotifications

struct EngagementNotificationPlan: Equatable {
    let identifier: String
    let title: String
    let body: String
    let reason: EngagementReason
    let destination: EngagementDestination
    let cooldownDays: Int
    let delay: TimeInterval
    let playsSound: Bool
}

final class EngagementNotificationScheduler {
    static let shared = EngagementNotificationScheduler()

    private let center: UNUserNotificationCenter
    private let service: EngagementIntelligenceService
    private let defaults: UserDefaults

    init(
        center: UNUserNotificationCenter = .current(),
        service: EngagementIntelligenceService = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.center = center
        self.service = service
        self.defaults = defaults
    }

    func plan(for context: EngagementContext, respectingCooldown: Bool = false) -> EngagementNotificationPlan? {
        guard context.notificationPermission != .denied else { return nil }

        let recommendation = service.recommendation(for: context)
        guard recommendation.surface == .notification else { return nil }
        guard recommendation.destination != .none else { return nil }

        let plan = EngagementNotificationPlan(
            identifier: "engagement.\(recommendation.reason.rawValue)",
            title: recommendation.title,
            body: recommendation.message,
            reason: recommendation.reason,
            destination: recommendation.destination,
            cooldownDays: recommendation.cooldownDays,
            delay: delay(for: recommendation.reason),
            playsSound: playsSound(for: recommendation.reason)
        )

        if respectingCooldown && isWithinCooldown(plan, now: context.now) {
            return nil
        }

        return plan
    }

    func scheduleIfUseful(for context: EngagementContext) async {
        guard let plan = plan(for: context, respectingCooldown: true) else { return }

        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = plan.playsSound ? .default : nil
        content.threadIdentifier = "landlordhours.engagement"
        content.categoryIdentifier = categoryIdentifier(for: plan.destination)
        content.userInfo = [
            "reason": plan.reason.rawValue,
            "destination": plan.destination.rawValue
        ]

        if #available(iOS 15.0, *) {
            content.interruptionLevel = interruptionLevel(for: plan.reason)
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: plan.delay, repeats: false)
        let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)

        center.removePendingNotificationRequests(withIdentifiers: [plan.identifier])
        do {
            try await center.add(request)
            markScheduled(plan, at: context.now)
        } catch {
            return
        }
    }

    func markScheduled(_ plan: EngagementNotificationPlan, at date: Date) {
        defaults.set(date, forKey: lastScheduledKey(for: plan))
    }

    private func isWithinCooldown(_ plan: EngagementNotificationPlan, now: Date) -> Bool {
        guard plan.cooldownDays > 0,
              let lastScheduledAt = defaults.object(forKey: lastScheduledKey(for: plan)) as? Date else {
            return false
        }
        let cooldown = TimeInterval(plan.cooldownDays * 24 * 60 * 60)
        return now.timeIntervalSince(lastScheduledAt) < cooldown
    }

    private func lastScheduledKey(for plan: EngagementNotificationPlan) -> String {
        UserScope.key("LandlordHours.notification.lastScheduled.\(plan.reason.rawValue)")
    }

    private func delay(for reason: EngagementReason) -> TimeInterval {
        switch reason {
        case .calendarDraftsReady, .yearEndExport:
            return 60
        case .inactiveLogging:
            return 60 * 60
        default:
            return 60 * 30
        }
    }

    private func playsSound(for reason: EngagementReason) -> Bool {
        reason == .timerSafety
    }

    private func categoryIdentifier(for destination: EngagementDestination) -> String {
        switch destination {
        case .track: return "LANDLORDHOURS_TRACK"
        case .calendarReview: return "LANDLORDHOURS_REVIEW_CALENDAR"
        case .export: return "LANDLORDHOURS_EXPORT"
        case .reports: return "LANDLORDHOURS_REPORTS"
        case .addProperty: return "LANDLORDHOURS_ADD_PROPERTY"
        case .timerReview: return "LANDLORDHOURS_TIMER"
        case .none: return "LANDLORDHOURS_OPEN"
        }
    }

    @available(iOS 15.0, *)
    private func interruptionLevel(for reason: EngagementReason) -> UNNotificationInterruptionLevel {
        switch reason {
        case .timerSafety:
            return .timeSensitive
        default:
            return .active
        }
    }
}
