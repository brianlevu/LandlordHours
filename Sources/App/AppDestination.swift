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
        case .inbox: self = .inbox
        case .records: self = .records
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

// MARK: - Shell tab indices (WP-D)
//
// The shell keeps the 1.x integer `selectedTab` so `.switchToTab` posts, `-LHInitialTab` launch
// arguments, App Intents and UI tests keep resolving. 0–4 keep their 1.x meaning; 2.0 adds Inbox
// and Records. Reports (3) and Settings (4) are not tabs: they open from Today's header. Log time
// (2) is the round + button.
enum ShellTab {
    static let todayIndex = 0
    static let propertiesIndex = 1
    static let logTimeIndex = 2
    static let reportsIndex = 3
    static let settingsIndex = 4
    static let inboxIndex = 5
    static let recordsIndex = 6
    static let maxIndex = 6
}

extension AppTab {
    var shellIndex: Int {
        switch self {
        case .today: return ShellTab.todayIndex
        case .inbox: return ShellTab.inboxIndex
        case .records: return ShellTab.recordsIndex
        case .properties: return ShellTab.propertiesIndex
        }
    }

    var title: String {
        switch self {
        case .today: return "Today"
        case .inbox: return "Inbox"
        case .records: return "Records"
        case .properties: return "Properties"
        }
    }

    /// SF Symbol (outline); `selectedSymbol` is the filled variant.
    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .inbox: return "tray"
        case .records: return "list.bullet.rectangle"
        case .properties: return "house"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .today: return "sun.max.fill"
        case .inbox: return "tray.fill"
        case .records: return "list.bullet.rectangle.fill"
        case .properties: return "house.fill"
        }
    }

    var accessibilityIdentifier: String { "tab.\(rawValue)" }
}
