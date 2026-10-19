import Foundation

// MARK: - 2.0 navigation destinations
//
// Destinations for the future 4-tab shell (Today / Inbox / Records / Properties, with Settings
// under the avatar and Log Time behind the round + button). Enum only — no views use it yet.
// Raw values keep the 1.x strings ("home", "reports", "track", ...) so destinations already
// persisted by notifications, App Intents and widgets keep resolving after the shell changes.

enum AppTab: String, CaseIterable {
    case today
    case inbox
    case records
    case properties
}

enum AppDestination: String, CaseIterable {
    case today = "home"
    case inbox
    case records = "reports"
    case properties
    /// Opened from the avatar, not a tab.
    case settings
    /// The round + button (log time / timer).
    case logTime = "track"
    /// The confirm sheet for one suggestion (key in `CaptureNotificationAction.pendingEditKey`).
    case confirmSuggestion

    /// The tab that hosts this destination.
    var tab: AppTab {
        switch self {
        case .today, .settings, .logTime: return .today
        case .inbox, .confirmSuggestion: return .inbox
        case .records: return .records
        case .properties: return .properties
        }
    }

    /// Maps a 1.x intent/notification destination.
    init(legacy destination: LandlordHoursIntentDestination) {
        switch destination {
        case .home: self = .today
        case .properties: self = .properties
        case .track: self = .logTime
        case .reports: self = .records
        case .settings: self = .settings
        }
    }

    /// Maps an engagement (widget / notification) destination.
    init(engagement destination: EngagementDestination) {
        switch destination {
        case .addProperty: self = .properties
        case .track, .timerReview: self = .logTime
        case .reports, .export: self = .records
        case .calendarReview: self = .inbox
        case .none: self = .today
        }
    }
}
