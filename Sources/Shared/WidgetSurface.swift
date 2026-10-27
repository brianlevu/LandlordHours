import Foundation

// MARK: - Widget surface (shared by the app and the widget extension)
//
// The app writes one `WidgetSurfaceSnapshot` to the App Group whenever its data changes (saves,
// goal or tax-profile edits, Inbox changes, the timer). The widget only reads it and maps it to
// words with `WidgetSurfaceDisplay`. Everything the widget shows is decided here, in pure code, so
// the unit tests cover the same strings the Home and Lock Screens draw.
//
// Hours rule (IRC 469(c)(7)(B)): for REPS the number is the user's OWN hours, never combined with
// a spouse. Material participation combines spouses only when the household tracks them jointly.
// The app computes `hours` with the same function as Today's house (`houseCountableHours`).
// `pendingCount` comes from the same source as the Inbox tab badge (`InboxLogic.visible`).

struct WidgetSurfaceSnapshot: Codable, Equatable {
    enum Goal: String, Codable, Equatable {
        case reps750 = "reps"
        case mp500
        case mp100
    }

    var updatedAt: Date
    var taxYear: Int
    var propertyCount: Int
    /// Countable confirmed hours for the goal (REPS: own hours only).
    var hours: Double
    var goal: Goal
    var goalHours: Double
    /// Linear pace target for today (0 early in January).
    var requiredHoursToDate: Double
    /// Inbox items waiting to be confirmed (same count as the Inbox badge).
    var pendingCount: Int
    var timerStart: Date?
    var timerPropertyName: String?
    /// `HouseKeyframe.rawValue` for these hours, e.g. "k07_frame060".
    var houseKeyframe: String
    /// "Frame going up" (HouseStage.spokenName).
    var stageTitle: String
    /// "Roof at 500h", or "House finished" when every step is done.
    var nextStepLabel: String

    static let empty = WidgetSurfaceSnapshot(
        updatedAt: Date(timeIntervalSince1970: 0),
        taxYear: Calendar.current.component(.year, from: Date()),
        propertyCount: 0,
        hours: 0,
        goal: .reps750,
        goalHours: 750,
        requiredHoursToDate: 0,
        pendingCount: 0,
        timerStart: nil,
        timerPropertyName: nil,
        houseKeyframe: "k00_lot",
        stageTitle: "An empty lot",
        nextStepLabel: "Foundation at 100h"
    )
}

enum WidgetSurfaceStore {
    static let appGroupIdentifier = "group.com.openclaw.landlordhours"
    static let key = "LandlordHours.widgetSurface.v2"
    static let widgetKind = "LandlordHoursWidget"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupIdentifier) }

    static func save(_ snapshot: WidgetSurfaceSnapshot, to defaults: UserDefaults? = WidgetSurfaceStore.defaults) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    static func load(from defaults: UserDefaults? = WidgetSurfaceStore.defaults) -> WidgetSurfaceSnapshot {
        guard let data = defaults?.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSurfaceSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}

/// Everything the widget families draw, as words and states.
struct WidgetSurfaceDisplay: Equatable {
    enum State: Equatable {
        case noProperty
        /// A property, but no confirmed hours yet.
        case empty
        case behind(gap: Int)
        case onPace
        /// More than the goal's hours (the law's wording).
        case met
        case timer
    }

    /// Colour role of the status line. The widget maps it to on-blueprint tokens.
    enum Tone: Equatable { case caution, positive, neutral, drafting }

    struct Status: Equatable {
        var symbol: String
        var text: String
        var tone: Tone
    }

    struct Pill: Equatable {
        var text: String
        var symbol: String
        var url: URL
    }

    /// One circular Lock Screen face.
    struct Face: Equatable {
        var symbol: String?
        var text: String
        /// True for a count or number (large); false for a word ("Done", "Add").
        var isLarge: Bool
        var accessibilityLabel: String
    }

    let snapshot: WidgetSurfaceSnapshot
    let state: State

    init(snapshot: WidgetSurfaceSnapshot) {
        self.snapshot = snapshot
        self.state = Self.state(for: snapshot)
    }

    static func state(for s: WidgetSurfaceSnapshot) -> State {
        if s.timerStart != nil && s.propertyCount > 0 { return .timer }
        if s.propertyCount == 0 { return .noProperty }
        if s.hours > s.goalHours { return .met }
        if s.hours < 1 { return .empty }
        // Same rule as the engagement snapshot: 5h of slack before "behind".
        if s.hours + 5 < s.requiredHoursToDate {
            return .behind(gap: Int((s.requiredHoursToDate - s.hours).rounded(.up)))
        }
        return .onPace
    }

    // MARK: Numbers

    /// Whole hours, rounded down so the number never runs ahead of the records.
    var number: String { "\(Int(max(0, snapshot.hours).rounded(.down)))" }
    var goalNumber: Int { Int(snapshot.goalHours) }
    /// "of 750h"
    var goalText: String { "of \(goalNumber)h" }
    var progress: Double { snapshot.goalHours > 0 ? min(1, max(0, snapshot.hours / snapshot.goalHours)) : 0 }
    var pendingCount: Int { max(0, snapshot.pendingCount) }
    var timerPropertyName: String { snapshot.timerPropertyName?.isEmpty == false ? snapshot.timerPropertyName! : "Timer running" }

    // MARK: Labels (SF Mono eyebrows)

    var smallLabel: String {
        switch state {
        case .timer: return "Timer"
        case .noProperty: return "Start here"
        default: return "Your hours"
        }
    }

    var mediumLabel: String {
        switch state {
        case .timer: return "Timer · today"
        case .noProperty: return "Dormer"
        default:
            let who = snapshot.goal == .reps750 ? "Your REPS hours" : "Your hours"
            return "\(who) · \(String(snapshot.taxYear))"
        }
    }

    // MARK: Status line (same words as the Today hero)

    var status: Status? {
        switch state {
        case .behind(let gap): return Status(symbol: "exclamationmark.circle.fill", text: "Behind by \(gap)h", tone: .caution)
        case .onPace: return Status(symbol: "checkmark.circle.fill", text: "On pace", tone: .positive)
        case .met: return Status(symbol: "checkmark.seal.fill", text: metStatusText, tone: .positive)
        case .empty: return Status(symbol: "circle.dashed", text: "Nothing confirmed yet", tone: .neutral)
        case .timer: return Status(symbol: "timer", text: timerPropertyName, tone: .drafting)
        case .noProperty: return nil
        }
    }

    /// The goal-met status keeps "House finished" only for REPS (the house is finished at >750h).
    /// MP goals say the goal's hours are reached instead.
    var metStatusText: String {
        snapshot.goal == .reps750 ? "House finished" : "\(goalNumber)h reached"
    }

    // MARK: The one tappable thing (medium)

    var pill: Pill? {
        switch state {
        case .noProperty: return Pill(text: "Add property", symbol: "plus", url: WidgetLinks.addProperty)
        case .timer: return Pill(text: "Stop and review", symbol: "stop.fill", url: WidgetLinks.logTime)
        default:
            guard pendingCount > 0 else { return nil }
            return Pill(text: "\(pendingCount) to confirm", symbol: "tray.fill", url: WidgetLinks.inbox)
        }
    }

    /// Shown in the medium widget when nothing waits: "Frame going up" / "Roof at 500h".
    var stageLine: (title: String, next: String) {
        (snapshot.stageTitle, snapshot.nextStepLabel)
    }

    // MARK: Lock Screen

    var inlineSymbol: String { state == .timer ? "timer" : "house.fill" }

    /// Inline (beside the date). `elapsed` is the timer text ("0:42").
    func inlineText(elapsed: String) -> String {
        switch state {
        case .noProperty: return "Add a property"
        case .timer: return "Timer \(elapsed) · \(timerPropertyName)"
        case .met: return "\(goalNumber)h reached"
        case .empty: return "0 of \(goalNumber)h so far"
        case .onPace:
            return pendingCount > 0 ? "\(number) of \(goalNumber)h · \(pendingCount) to confirm" : "\(number) of \(goalNumber)h · on pace"
        case .behind:
            return pendingCount > 0 ? "\(number) of \(goalNumber)h · \(pendingCount) to confirm" : "\(number) of \(goalNumber)h"
        }
    }

    var rectangularTitle: String { state == .timer ? "Timer" : "Your hours" }

    func rectangularHeadline(elapsed: String) -> String {
        switch state {
        case .noProperty: return "Add a property"
        case .timer: return "\(elapsed) · \(timerPropertyName)"
        default: return "\(number) \(goalText)"
        }
    }

    var rectangularLine: String {
        switch state {
        case .noProperty: return "to start counting"
        case .timer: return "Stop it to review"
        case .empty: return pendingCount > 0 ? "\(pendingCount) to confirm" : "Nothing confirmed yet"
        case .behind(let gap): return pendingCount > 0 ? "\(pendingCount) to confirm" : "Behind by \(gap)h"
        case .onPace: return pendingCount > 0 ? "\(pendingCount) to confirm" : "On pace"
        case .met: return pendingCount > 0 ? "\(pendingCount) to confirm" : metStatusText
        }
    }

    /// The hours circular: the number in a ring (a checkmark once met, a plus with no property).
    var hoursFace: Face {
        switch state {
        case .noProperty: return Face(symbol: "plus", text: "", isLarge: false, accessibilityLabel: "Add a property")
        case .met: return Face(symbol: "checkmark", text: "", isLarge: false, accessibilityLabel: "\(number) of your \(goalNumber) hours. Goal reached.")
        case .timer: return Face(symbol: nil, text: "", isLarge: true, accessibilityLabel: "Timer running at \(timerPropertyName)")
        default: return Face(symbol: nil, text: number, isLarge: true, accessibilityLabel: "\(number) of your \(goalNumber) hours")
        }
    }

    /// The to-confirm circular. "Done" only when there are hours and nothing waits.
    var pendingFace: Face {
        if pendingCount > 0 {
            return Face(symbol: "tray.fill", text: "\(pendingCount)", isLarge: true, accessibilityLabel: "\(pendingCount) to confirm")
        }
        switch state {
        case .noProperty: return Face(symbol: "plus", text: "Add", isLarge: false, accessibilityLabel: "Add a property")
        case .empty: return Face(symbol: "tray", text: "–", isLarge: true, accessibilityLabel: "Nothing to confirm yet")
        default: return Face(symbol: "checkmark", text: "Done", isLarge: false, accessibilityLabel: "Nothing to confirm")
        }
    }

    // MARK: Taps

    /// Where a tap on the widget body goes.
    var url: URL {
        switch state {
        case .noProperty: return WidgetLinks.addProperty
        case .timer: return WidgetLinks.logTime
        default: return pendingCount > 0 ? WidgetLinks.inbox : WidgetLinks.today
        }
    }

    var pendingURL: URL { state == .noProperty ? WidgetLinks.addProperty : (pendingCount > 0 ? WidgetLinks.inbox : WidgetLinks.today) }

    // MARK: Accessibility

    var accessibilityLabel: String {
        switch state {
        case .noProperty: return "Dormer. Add a rental to start counting."
        case .timer: return "Timer running at \(timerPropertyName)."
        default:
            var parts = ["\(number) of your \(goalNumber) hours."]
            if let s = status { parts.append(s.text + ".") }
            if pendingCount > 0 { parts.append("\(pendingCount) to confirm.") }
            return parts.joined(separator: " ")
        }
    }

    /// "0:42" / "4:12" (hours:minutes) for a frozen capture or the inline family.
    static func elapsedText(from start: Date, to now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }
}

/// Deep links the widget opens (`landlordhours://open?destination=…`, LandlordHoursIntentDestination raw values).
enum WidgetLinks {
    static let today = link("home")
    static let inbox = link("inbox")
    static let logTime = link("track")
    static let addProperty = link("properties")

    private static func link(_ destination: String) -> URL {
        URL(string: "landlordhours://open?destination=\(destination)")!
    }
}
