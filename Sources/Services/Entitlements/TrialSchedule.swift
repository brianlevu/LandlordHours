import Foundation

// MARK: - The trial timeline and the day-12 reminder (2.3 paywall B)
//
// The paywall opens on Today → In 12 days (reminder) → In 14 days (renewal). The length comes from
// the product's intro offer; the reminder is two days before the renewal. The day-12 sheet says
// "Keep Pro" with a "Cancel in Settings" link, once per trial, and only while it will renew.

struct TrialSchedule: Equatable, Sendable {
    static let defaultTrialDays = 14
    /// Days before the renewal that the reminder comes (day 12 of 14).
    static let reminderLeadDays = 2

    let start: Date
    let reminder: Date
    let renewal: Date

    /// The timeline before the purchase, from today.
    static func preview(from now: Date, trialDays: Int = defaultTrialDays, calendar: Calendar = .current) -> TrialSchedule {
        let renewal = calendar.date(byAdding: .day, value: trialDays, to: now) ?? now
        return TrialSchedule(start: now, reminder: reminderDate(renewal: renewal, calendar: calendar), renewal: renewal)
    }

    /// The running trial's real dates. Nil when the plan isn't a trial.
    static func current(_ plan: Plan, calendar: Calendar = .current) -> TrialSchedule? {
        guard case .trial(let sub) = plan else { return nil }
        return TrialSchedule(start: sub.startedAt, reminder: reminderDate(renewal: sub.expiresAt, calendar: calendar),
                             renewal: sub.expiresAt)
    }

    static func reminderDate(renewal: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -reminderLeadDays, to: renewal) ?? renewal
    }

    /// Show the day-12 sheet: a trial that will renew, on or after the reminder day, before the
    /// renewal, not yet shown for this trial (keyed by original transaction id).
    static func shouldShowDay12Reminder(plan: Plan, now: Date, shown: Set<UInt64>, calendar: Calendar = .current) -> Bool {
        guard case .trial(let sub) = plan, sub.willAutoRenew, !shown.contains(sub.originalTransactionID),
              let schedule = current(plan, calendar: calendar) else { return false }
        return now >= schedule.reminder && now < schedule.renewal
    }
}

/// What the paywall offers.
enum PaywallOffer: Equatable, Sendable {
    /// Start Apple's free trial (the paywall leads with the timeline).
    case freeTrial(days: Int)
    /// Trial already used: subscribe at the StoreKit price.
    case subscribe
    /// Already has Pro (trial, paid or founding).
    case owned

    static func resolve(plan: Plan, eligibleForIntroOffer: Bool, introTrialDays: Int?) -> PaywallOffer {
        if plan.hasProAccess { return .owned }
        if eligibleForIntroOffer, let days = introTrialDays, days > 0 { return .freeTrial(days: days) }
        return .subscribe
    }
}
