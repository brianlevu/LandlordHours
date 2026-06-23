import Foundation

enum EngagementSurface: String, Codable, Equatable {
    case none
    case homeNudge
    case notification
    case widget
    case siriShortcut
    case liveActivity
}

enum EngagementDestination: String, Codable, Equatable {
    case none
    case addProperty
    case track
    case reports
    case calendarReview
    case export
    case timerReview
}

enum EngagementReason: String, Codable, Equatable {
    case noActionNeeded
    case setupProperty
    case inactiveLogging
    case timerSafety
    case calendarDraftsReady
    case behindPace
    case yearEndExport
    case portfolioSummary
}

struct EngagementRecommendation: Equatable {
    let surface: EngagementSurface
    let reason: EngagementReason
    let destination: EngagementDestination
    let title: String
    let message: String
    let cooldownDays: Int

    static let doNothing = EngagementRecommendation(
        surface: .none,
        reason: .noActionNeeded,
        destination: .none,
        title: "",
        message: "",
        cooldownDays: 0
    )
}

struct EngagementDismissal: Equatable {
    let reason: EngagementReason
    let dismissedAt: Date
}

struct EngagementContext {
    var now: Date
    var taxYear: Int
    var properties: [RentalProperty]
    var timeEntries: [TimeEntry]
    var calendarDraftCount: Int
    var isTimerRunning: Bool
    var timerStartTime: Date?
    var notificationPermission: NotificationPermissionState
    var recentDismissals: [EngagementDismissal]
    var isProUser: Bool
    var targetHours: Double = REPSRequirements.annualHourThreshold

    enum NotificationPermissionState: Equatable {
        case notDetermined
        case provisional
        case authorized
        case denied
    }
}

struct EngagementSnapshot: Equatable {
    let yearHours: Double
    let lastLogDate: Date?
    let daysSinceLastLog: Int?
    let daysRemainingInYear: Int
    let requiredHoursToDate: Double
    let isBehindPace: Bool
    let timerAgeHours: Double?
}

final class EngagementIntelligenceService {
    static let shared = EngagementIntelligenceService()

    private let inactivityThresholdDays = 7
    private let timerSafetyThresholdHours = 4.0
    private let repeatedDismissalThreshold = 2
    private let repeatedDismissalCooldownDays = 14

    init() {}

    func snapshot(for context: EngagementContext, calendar: Calendar = .current) -> EngagementSnapshot {
        let yearEntries = context.timeEntries.filter {
            calendar.component(.year, from: $0.date) == context.taxYear && $0.category.countsForREPS
        }
        let yearHours = yearEntries.reduce(0) { $0 + $1.hours }
        let lastLogDate = yearEntries.map(\.date).max()
        let daysSinceLastLog = lastLogDate.map {
            max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: context.now)).day ?? 0)
        }

        let daysElapsed = max(1, calendar.ordinality(of: .day, in: .year, for: context.now) ?? 1)
        let range = calendar.range(of: .day, in: .year, for: context.now)
        let daysInYear = range?.count ?? 365
        let daysRemaining = max(0, daysInYear - daysElapsed)
        let targetHours = max(context.targetHours, 1)
        let requiredHoursToDate = targetHours * (Double(daysElapsed) / Double(daysInYear))
        let isBehindPace = yearHours + 5 < requiredHoursToDate

        let timerAgeHours = context.timerStartTime.map {
            max(0, context.now.timeIntervalSince($0) / 3600)
        }

        return EngagementSnapshot(
            yearHours: yearHours,
            lastLogDate: lastLogDate,
            daysSinceLastLog: daysSinceLastLog,
            daysRemainingInYear: daysRemaining,
            requiredHoursToDate: requiredHoursToDate,
            isBehindPace: isBehindPace,
            timerAgeHours: timerAgeHours
        )
    }

    func recommendation(for context: EngagementContext, calendar: Calendar = .current) -> EngagementRecommendation {
        let snapshot = snapshot(for: context, calendar: calendar)

        let candidate: EngagementRecommendation
        if context.properties.isEmpty {
            candidate = setupPropertyRecommendation
        } else if context.isTimerRunning,
                  let timerAgeHours = snapshot.timerAgeHours,
                  timerAgeHours >= timerSafetyThresholdHours {
            candidate = timerSafetyRecommendation(hours: timerAgeHours)
        } else if context.calendarDraftCount > 0 {
            candidate = calendarDraftRecommendation(count: context.calendarDraftCount)
        } else if shouldSuggestYearEndExport(context: context, snapshot: snapshot, calendar: calendar) {
            candidate = yearEndExportRecommendation(hours: snapshot.yearHours)
        } else if shouldSuggestInactivity(snapshot: snapshot) {
            candidate = inactivityRecommendation(days: snapshot.daysSinceLastLog ?? inactivityThresholdDays)
        } else if shouldSuggestBehindPace(snapshot: snapshot, calendar: calendar, now: context.now) {
            candidate = behindPaceRecommendation(snapshot: snapshot)
        } else if context.isProUser && context.properties.count > 1 && snapshot.yearHours > 0 {
            candidate = portfolioSummaryRecommendation(propertyCount: context.properties.count, hours: snapshot.yearHours)
        } else {
            candidate = .doNothing
        }

        guard candidate.surface != .none else { return candidate }
        return isSuppressed(candidate.reason, in: context, calendar: calendar) ? .doNothing : candidate
    }

    private var setupPropertyRecommendation: EngagementRecommendation {
        EngagementRecommendation(
            surface: .homeNudge,
            reason: .setupProperty,
            destination: .addProperty,
            title: "Create your first evidence file",
            message: "Add a property before reminders or pace checks begin.",
            cooldownDays: 0
        )
    }

    private func timerSafetyRecommendation(hours: Double) -> EngagementRecommendation {
        EngagementRecommendation(
            surface: .liveActivity,
            reason: .timerSafety,
            destination: .timerReview,
            title: "Timer still running",
            message: "Review this \(String(format: "%.1f", hours))h timer before saving.",
            cooldownDays: 1
        )
    }

    private func calendarDraftRecommendation(count: Int) -> EngagementRecommendation {
        EngagementRecommendation(
            surface: .notification,
            reason: .calendarDraftsReady,
            destination: .calendarReview,
            title: "Review likely landlord work",
            message: "\(count) calendar item\(count == 1 ? "" : "s") may be landlord work.",
            cooldownDays: 3
        )
    }

    private func inactivityRecommendation(days: Int) -> EngagementRecommendation {
        EngagementRecommendation(
            surface: .notification,
            reason: .inactiveLogging,
            destination: .track,
            title: "Log recent landlord work",
            message: "No hours saved in \(days) days. Log anything you handled recently.",
            cooldownDays: 7
        )
    }

    private func behindPaceRecommendation(snapshot: EngagementSnapshot) -> EngagementRecommendation {
        let gap = max(0, snapshot.requiredHoursToDate - snapshot.yearHours)
        return EngagementRecommendation(
            surface: .widget,
            reason: .behindPace,
            destination: .reports,
            title: "Behind REPS pace",
            message: "\(String(format: "%.0f", gap))h behind today's 750h pace.",
            cooldownDays: 7
        )
    }

    private func yearEndExportRecommendation(hours: Double) -> EngagementRecommendation {
        EngagementRecommendation(
            surface: .notification,
            reason: .yearEndExport,
            destination: .export,
            title: "Prepare tax-year records",
            message: "\(String(format: "%.1f", hours))h are ready for tax-year review.",
            cooldownDays: 14
        )
    }

    private func portfolioSummaryRecommendation(propertyCount: Int, hours: Double) -> EngagementRecommendation {
        EngagementRecommendation(
            surface: .widget,
            reason: .portfolioSummary,
            destination: .reports,
            title: "Portfolio evidence summary",
            message: "\(propertyCount) properties, \(String(format: "%.1f", hours))h logged this year.",
            cooldownDays: 7
        )
    }

    private func shouldSuggestInactivity(snapshot: EngagementSnapshot) -> Bool {
        guard let days = snapshot.daysSinceLastLog else { return true }
        return days >= inactivityThresholdDays
    }

    private func shouldSuggestBehindPace(snapshot: EngagementSnapshot, calendar: Calendar, now: Date) -> Bool {
        let month = calendar.component(.month, from: now)
        return month >= 3 && snapshot.yearHours > 0 && snapshot.isBehindPace
    }

    private func shouldSuggestYearEndExport(
        context: EngagementContext,
        snapshot: EngagementSnapshot,
        calendar: Calendar
    ) -> Bool {
        let month = calendar.component(.month, from: context.now)
        return month >= 11 && snapshot.yearHours >= 10
    }

    private func isSuppressed(
        _ reason: EngagementReason,
        in context: EngagementContext,
        calendar: Calendar
    ) -> Bool {
        let matchingDismissals = context.recentDismissals.filter { dismissal in
            dismissal.reason == reason &&
            daysBetween(dismissal.dismissedAt, and: context.now, calendar: calendar) <= repeatedDismissalCooldownDays
        }

        return matchingDismissals.count >= repeatedDismissalThreshold
    }

    private func daysBetween(_ start: Date, and end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: start),
            to: calendar.startOfDay(for: end)
        ).day ?? 0
    }
}
