import Foundation

enum EngagementWidgetSnapshotStore {
    static let appGroupIdentifier = "group.com.openclaw.landlordhours"
    static let snapshotKey = "LandlordHours.widgetSnapshot"
    static let widgetKind = "LandlordHoursWidget"

    static func save(_ snapshot: EngagementWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        appGroupDefaults?.set(data, forKey: snapshotKey)
    }

    static func load() -> EngagementWidgetSnapshot {
        guard let data = appGroupDefaults?.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(EngagementWidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    private static var appGroupDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
}

struct EngagementWidgetSnapshot: Codable, Equatable {
    var updatedAt: Date
    var taxYear: Int
    var propertyCount: Int
    var yearHours: Double
    var targetHours: Double
    var targetLabel: String
    var targetShortLabel: String
    var requiredHoursToDate: Double
    var daysRemainingInYear: Int
    var lastLogDate: Date?
    var isTimerRunning: Bool
    var timerStartTime: Date?
    var recommendationSurface: EngagementSurface
    var recommendationReason: EngagementReason
    var recommendationDestination: EngagementDestination
    var recommendationTitle: String
    var recommendationMessage: String

    static let empty = EngagementWidgetSnapshot(
        updatedAt: Date(),
        taxYear: Calendar.current.component(.year, from: Date()),
        propertyCount: 0,
        yearHours: 0,
        targetHours: REPSRequirements.annualHourThreshold,
        targetLabel: "750h REPS",
        targetShortLabel: "750h",
        requiredHoursToDate: 0,
        daysRemainingInYear: 0,
        lastLogDate: nil,
        isTimerRunning: false,
        timerStartTime: nil,
        recommendationSurface: .homeNudge,
        recommendationReason: .setupProperty,
        recommendationDestination: .addProperty,
        recommendationTitle: "Set up LandlordHours",
        recommendationMessage: "Add your first property to start tracking evidence."
    )

    init(
        updatedAt: Date,
        taxYear: Int,
        propertyCount: Int,
        yearHours: Double,
        targetHours: Double = REPSRequirements.annualHourThreshold,
        targetLabel: String = "750h REPS",
        targetShortLabel: String = "750h",
        requiredHoursToDate: Double,
        daysRemainingInYear: Int,
        lastLogDate: Date?,
        isTimerRunning: Bool,
        timerStartTime: Date?,
        recommendationSurface: EngagementSurface,
        recommendationReason: EngagementReason,
        recommendationDestination: EngagementDestination,
        recommendationTitle: String,
        recommendationMessage: String
    ) {
        self.updatedAt = updatedAt
        self.taxYear = taxYear
        self.propertyCount = propertyCount
        self.yearHours = yearHours
        self.targetHours = max(targetHours, 1)
        self.targetLabel = targetLabel
        self.targetShortLabel = targetShortLabel
        self.requiredHoursToDate = requiredHoursToDate
        self.daysRemainingInYear = daysRemainingInYear
        self.lastLogDate = lastLogDate
        self.isTimerRunning = isTimerRunning
        self.timerStartTime = timerStartTime
        self.recommendationSurface = recommendationSurface
        self.recommendationReason = recommendationReason
        self.recommendationDestination = recommendationDestination
        self.recommendationTitle = recommendationTitle
        self.recommendationMessage = recommendationMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        taxYear = try container.decode(Int.self, forKey: .taxYear)
        propertyCount = try container.decode(Int.self, forKey: .propertyCount)
        yearHours = try container.decode(Double.self, forKey: .yearHours)
        targetHours = try container.decodeIfPresent(Double.self, forKey: .targetHours) ?? REPSRequirements.annualHourThreshold
        targetLabel = try container.decodeIfPresent(String.self, forKey: .targetLabel) ?? "750h REPS"
        targetShortLabel = try container.decodeIfPresent(String.self, forKey: .targetShortLabel) ?? "750h"
        requiredHoursToDate = try container.decode(Double.self, forKey: .requiredHoursToDate)
        daysRemainingInYear = try container.decode(Int.self, forKey: .daysRemainingInYear)
        lastLogDate = try container.decodeIfPresent(Date.self, forKey: .lastLogDate)
        isTimerRunning = try container.decode(Bool.self, forKey: .isTimerRunning)
        timerStartTime = try container.decodeIfPresent(Date.self, forKey: .timerStartTime)
        recommendationSurface = try container.decode(EngagementSurface.self, forKey: .recommendationSurface)
        recommendationReason = try container.decode(EngagementReason.self, forKey: .recommendationReason)
        recommendationDestination = try container.decode(EngagementDestination.self, forKey: .recommendationDestination)
        recommendationTitle = try container.decode(String.self, forKey: .recommendationTitle)
        recommendationMessage = try container.decode(String.self, forKey: .recommendationMessage)
    }

    var progress: Double {
        min(max(yearHours / targetHours, 0), 1)
    }

    var isBehindPace: Bool {
        yearHours + 5 < requiredHoursToDate
    }

    var paceGapHours: Double {
        max(0, requiredHoursToDate - yearHours)
    }

    var isStale: Bool {
        Date().timeIntervalSince(updatedAt) > 36 * 60 * 60
    }

    var headline: String {
        if propertyCount == 0 { return "Set up tracking" }
        if isTimerRunning { return "Timer active" }
        if isStale { return "Open to refresh" }
        if recommendationReason == .behindPace { return "\(Int(paceGapHours.rounded(.up)))h behind" }
        if recommendationReason == .portfolioSummary { return "\(propertyCount) properties" }
        return "\(Int(yearHours.rounded()))h logged"
    }

    var detail: String {
        if propertyCount == 0 { return "Add a property before pace checks begin." }
        if isTimerRunning { return "Review before saving." }
        if isStale { return "Refresh your latest \(targetShortLabel) pace." }
        if recommendationSurface == .none { return "No urgent action right now." }
        return recommendationMessage
    }

    var actionLabel: String {
        if isTimerRunning { return "Review" }
        if isStale && !isTimerRunning { return "Refresh" }
        switch recommendationDestination {
        case .addProperty: return "Add property"
        case .track: return "Log time"
        case .reports: return recommendationReason == .behindPace ? "Review pace" : "Open reports"
        case .calendarReview: return "Review drafts"
        case .export: return "Prepare export"
        case .timerReview: return "Review"
        case .none: return "Open app"
        }
    }
}
