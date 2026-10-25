import Foundation
import CoreGraphics

// MARK: - Widget surface (shared by the app and the widget extension)
//
// The app writes one `WidgetSurfaceSnapshot` to the App Group whenever its data changes (saves,
// goal or tax-profile edits, Inbox changes, the timer). The widget only reads it and maps it to
// words with `WidgetSurfaceDisplay`. Everything the widget shows is decided here, in pure code, so
// the unit tests cover the same strings the Home and Lock Screens draw.
//
// v2 (2.2, package I): the widget follows Today. One rental: its house at its own stage, "212 of
// 750 hours", the pace in plain words. Two or more: the skyline, "312 hours across 3 rentals",
// "3 of 3 behind", and never a goal or a stage for the whole (standard §H.1 H10). Windows are lit
// when hours were logged today (`loggedToday`, the same rule as Today). Pace is Today's pace:
// behind when the rounded gap to the linear target is 1 hour or more, and it waits for two weeks
// of hours or ten confirmed hours before it judges.
//
// Hours rule (IRC 469(c)(7)(B)): for REPS the number is the user's OWN hours, never combined with
// a spouse. Material participation combines spouses only when the household tracks them jointly.
// The app computes hours with the same functions as Today (`houseCountableHours`,
// `propertyCountableHours`). `pendingCount` comes from the same source as the Inbox tab badge
// (`InboxLogic.visible`).

/// One rental's house on the skyline: its own stage and its own lit state (Today's `RentalSkylineItem`).
struct WidgetRentalFigure: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var hours: Double
    /// `CraftStage.rawValue` for this rental's own hours and goal, e.g. "craft_half".
    var stage: String
    /// Hours were logged today on this rental (`TodayWindowState.loggedToday`).
    var lit: Bool
    /// Hours behind this rental's own linear pace (0 when on pace).
    var behindBy: Double

    init(id: String, name: String, hours: Double, stage: String, lit: Bool, behindBy: Double = 0) {
        self.id = id
        self.name = name
        self.hours = hours
        self.stage = stage
        self.lit = lit
        self.behindBy = behindBy
    }
}

/// One waiting suggestion (an Inbox item), as the large widget lists it.
struct WidgetConfirmRow: Codable, Equatable, Identifiable {
    /// The suggestion's `sourceKey` (what the Confirm button sends back to the app).
    var key: String
    var title: String
    var rentalName: String?
    var hours: Double?
    /// The suggestion has a rental, a kind of work and hours, so one tap can log it.
    var canConfirm: Bool

    var id: String { key }

    init(key: String, title: String, rentalName: String? = nil, hours: Double? = nil, canConfirm: Bool = true) {
        self.key = key
        self.title = title
        self.rentalName = rentalName
        self.hours = hours
        self.canConfirm = canConfirm
    }
}

struct WidgetSurfaceSnapshot: Codable, Equatable {
    enum Goal: String, Codable, Equatable {
        case reps750 = "reps"
        case mp500
        case mp100
    }

    var updatedAt: Date
    var taxYear: Int
    var propertyCount: Int
    /// Countable confirmed hours: one rental's own, or the sum across rentals when there are two or more.
    var hours: Double
    var goal: Goal
    var goalHours: Double
    /// Linear pace target for today (0 early in January). One rental only.
    var requiredHoursToDate: Double
    /// Inbox items waiting to be confirmed (same count as the Inbox badge).
    var pendingCount: Int
    var timerStart: Date?
    var timerPropertyName: String?
    /// Legacy v1 keyframe name; unused since 2.2 (kept so a stored snapshot still decodes).
    var houseKeyframe: String
    /// "Frame going up" (`CraftStage.spokenName`).
    var stageTitle: String
    /// Legacy v1 label; unused since 2.2.
    var nextStepLabel: String

    // MARK: 2.2 fields (decoded with defaults, so a snapshot an older build stored still loads)

    /// `CraftStage.rawValue` for the single rental's hours against its goal.
    var houseStage: String = "craft_started"
    /// Hours were logged today (on any rental).
    var loggedToday: Bool = false
    /// Pace waits for two weeks of hours or ten confirmed hours (`TodayHeroCopy.paceIsReady`).
    var paceReady: Bool = true
    /// "Just keep a record": no target, no pace.
    var isRecord: Bool = false
    /// Every rental's own house, in the shelf's order.
    var rentals: [WidgetRentalFigure] = []
    /// Up to five waiting suggestions, newest first.
    var confirmRows: [WidgetConfirmRow] = []

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
        stageTitle: "",
        nextStepLabel: ""
    )
}

extension WidgetSurfaceSnapshot {
    private enum CodingKeys: String, CodingKey {
        case updatedAt, taxYear, propertyCount, hours, goal, goalHours, requiredHoursToDate, pendingCount
        case timerStart, timerPropertyName, houseKeyframe, stageTitle, nextStepLabel
        case houseStage, loggedToday, paceReady, isRecord, rentals, confirmRows
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        taxYear = try c.decode(Int.self, forKey: .taxYear)
        propertyCount = try c.decode(Int.self, forKey: .propertyCount)
        hours = try c.decode(Double.self, forKey: .hours)
        goal = try c.decode(Goal.self, forKey: .goal)
        goalHours = try c.decode(Double.self, forKey: .goalHours)
        requiredHoursToDate = try c.decode(Double.self, forKey: .requiredHoursToDate)
        pendingCount = try c.decode(Int.self, forKey: .pendingCount)
        timerStart = try c.decodeIfPresent(Date.self, forKey: .timerStart)
        timerPropertyName = try c.decodeIfPresent(String.self, forKey: .timerPropertyName)
        houseKeyframe = try c.decodeIfPresent(String.self, forKey: .houseKeyframe) ?? ""
        stageTitle = try c.decodeIfPresent(String.self, forKey: .stageTitle) ?? ""
        nextStepLabel = try c.decodeIfPresent(String.self, forKey: .nextStepLabel) ?? ""
        houseStage = try c.decodeIfPresent(String.self, forKey: .houseStage) ?? "craft_started"
        loggedToday = try c.decodeIfPresent(Bool.self, forKey: .loggedToday) ?? false
        paceReady = try c.decodeIfPresent(Bool.self, forKey: .paceReady) ?? true
        isRecord = try c.decodeIfPresent(Bool.self, forKey: .isRecord) ?? false
        rentals = try c.decodeIfPresent([WidgetRentalFigure].self, forKey: .rentals) ?? []
        confirmRows = try c.decodeIfPresent([WidgetConfirmRow].self, forKey: .confirmRows) ?? []
    }
}

extension WidgetSurfaceSnapshot {
    /// The same snapshot after midnight: nothing is logged on the new day yet, so every window is dark.
    func nextDay() -> WidgetSurfaceSnapshot {
        var copy = self
        copy.loggedToday = false
        copy.rentals = rentals.map { var r = $0; r.lit = false; return r }
        return copy
    }
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

// MARK: - The skyline (standard §H.1 H10 for the widget)

/// The same rule as Today's `RentalSkylineLayout`: house side `min(0.42 S, (0.92 S - 0.04 S (n - 1)) / n)`,
/// never under 44pt, at most 5 houses when `S >= 290` and 4 under it, and also never more houses than
/// fit at 44pt. Over the cap the most-behind rentals show first and nothing counts the rest.
enum WidgetSkyline {
    static let minimumHouse: CGFloat = 44
    static let gapFraction: CGFloat = 0.04
    static let groundFraction: CGFloat = 0.92

    static func cap(frame: CGFloat) -> Int {
        let spec = frame >= 290 ? 5 : 4
        let gap = gapFraction * frame
        let fits = Int(((frame + gap) / (minimumHouse + gap)).rounded(.down))
        return max(1, min(spec, fits))
    }

    static func houseSide(frame: CGFloat, count: Int) -> CGFloat {
        let n = CGFloat(max(count, 1))
        let fit = (groundFraction * frame - gapFraction * frame * (n - 1)) / n
        return max(minimumHouse, min(0.42 * frame, fit))
    }

    static func visible(_ rentals: [WidgetRentalFigure], frame: CGFloat) -> [WidgetRentalFigure] {
        let cap = cap(frame: frame)
        guard rentals.count > cap else { return rentals }
        let keep = rentals.enumerated()
            .sorted { a, b in a.element.behindBy != b.element.behindBy ? a.element.behindBy > b.element.behindBy : a.offset < b.offset }
            .prefix(cap)
            .map(\.offset)
        let set = Set(keep)
        return rentals.enumerated().filter { set.contains($0.offset) }.map(\.element)
    }
}

/// Which bitmap draws a stage: `wg_thumb_<stage>` (lit) or `wg_thumb_<stage>-unlit`.
enum WidgetHouseArt {
    static func assetName(stage: String, lit: Bool) -> String {
        let known = ["started", "frame70", "framing", "half", "complete"]
        let short = stage.hasPrefix("craft_") ? String(stage.dropFirst("craft_".count)) : stage
        let name = known.contains(short) ? short : "started"
        return "wg_thumb_" + name + (lit ? "" : "-unlit")
    }

    /// The early stages are short and sit low in the frame, so the single-rental hero scales them up
    /// about the ground line, as Today does (`CraftStage.stageScale`).
    static func stageScale(stage: String) -> CGFloat {
        switch stage {
        case "craft_started": return 1.18
        case "craft_frame70": return 1.08
        default: return 1.0
        }
    }
}

enum WidgetFormat {
    /// "1.5h" or "2h" (no ".0").
    static func hours(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded))h" }
        return String(format: "%.1fh", rounded)
    }
}

/// Everything the widget families draw, as words and states.
struct WidgetSurfaceDisplay: Equatable {
    enum State: Equatable {
        case noProperty
        /// A property, but no confirmed hours yet.
        case empty
        /// One rental, hours but too few days of them to judge a pace.
        case paceNotReady
        case behind(gap: Int)
        case onPace
        /// More than the goal's hours (the law's wording).
        case met
        /// Two or more rentals: hours across them and how many are behind their own pace. No goal.
        case allRentals(behind: Int)
        case timer
    }

    /// Colour role of the status line. The widget maps it to the page inks.
    enum Tone: Equatable { case behind, positive, neutral, action }

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
        if s.hours < 1 { return .empty }
        if s.propertyCount > 1 || s.rentals.count > 1 {
            return .allRentals(behind: s.rentals.filter { $0.behindBy >= 0.5 }.count)
        }
        if !s.isRecord && s.hours > s.goalHours { return .met }
        if s.isRecord { return .onPace }
        if !s.paceReady { return .paceNotReady }
        // Today's rule: behind once the rounded gap to the linear target is an hour or more.
        let gap = Int((s.requiredHoursToDate - s.hours).rounded())
        if gap >= 1 { return .behind(gap: gap) }
        return .onPace
    }

    // MARK: Numbers

    /// Whole hours, rounded down so the number never runs ahead of the records.
    var number: String { "\(Int(max(0, snapshot.hours).rounded(.down)))" }
    var goalNumber: Int { Int(snapshot.goalHours) }
    var year: String { String(snapshot.taxYear) }
    var pendingCount: Int { max(0, snapshot.pendingCount) }
    var timerPropertyName: String {
        snapshot.timerPropertyName?.isEmpty == false ? snapshot.timerPropertyName! : String(localized: "widget.timer.running", defaultValue: "Timer running", table: "Widgets")
    }
    var isAllRentals: Bool {
        if case .allRentals = state { return true }
        return snapshot.propertyCount > 1
    }
    var rentalCount: Int { max(snapshot.propertyCount, snapshot.rentals.count) }
    /// Share of the goal reached, for the Lock Screen ring. Zero where there is no single goal.
    var progress: Double {
        guard !isAllRentals, !snapshot.isRecord, snapshot.goalHours > 0 else { return 0 }
        return min(1, max(0, snapshot.hours / snapshot.goalHours))
    }
    var hasRing: Bool { !isAllRentals && !snapshot.isRecord && state != .noProperty }

    var behindCount: Int {
        if case .allRentals(let n) = state { return n }
        return 0
    }

    /// The caption under the number: "of 750 hours", "hours across 3 rentals", "hours logged in 2026".
    var caption: String {
        if state == .noProperty {
            return String(localized: "widget.caption.start", defaultValue: "Add a rental to start counting.", table: "Widgets")
        }
        if isAllRentals {
            return String(localized: "widget.caption.across", defaultValue: "hours across \(rentalCount) rentals", table: "Widgets")
        }
        return snapshot.isRecord
            ? String(localized: "widget.caption.record", defaultValue: "hours logged in \(year)", table: "Widgets")
            : String(localized: "widget.caption.ofGoal", defaultValue: "of \(goalNumber) hours", table: "Widgets")
    }

    /// "212 of 750 hours" / "312 hours across 3 rentals" in one line (Lock Screen, VoiceOver).
    var hoursLine: String { "\(number) \(caption)" }

    // MARK: Status line (Today's pace, in plain words)

    var status: Status? {
        switch state {
        case .behind(let gap):
            return Status(symbol: "exclamationmark.circle.fill", text: String(localized: "widget.pace.behind", defaultValue: "Behind by \(gap) hours", table: "Widgets"), tone: .behind)
        case .onPace:
            return Status(symbol: "checkmark.circle.fill", text: snapshot.isRecord
                ? String(localized: "widget.pace.record", defaultValue: "On your \(year) record", table: "Widgets")
                : String(localized: "widget.pace.onPace", defaultValue: "On pace", table: "Widgets"), tone: .positive)
        case .met:
            return Status(symbol: "checkmark.seal.fill", text: metStatusText, tone: .positive)
        case .empty:
            return Status(symbol: "circle.dashed", text: String(localized: "widget.pace.none", defaultValue: "No hours yet", table: "Widgets"), tone: .neutral)
        case .paceNotReady:
            return Status(symbol: "hourglass", text: pendingCount > 0
                ? String(localized: "widget.pace.confirmFirst", defaultValue: "Confirm your found hours to see your pace", table: "Widgets")
                : String(localized: "widget.pace.notReady", defaultValue: "Log a few weeks to see your pace", table: "Widgets"), tone: .neutral)
        case .allRentals(let behind):
            return behind == 0
                ? Status(symbol: "checkmark.circle.fill", text: String(localized: "widget.all.onPace", defaultValue: "All on pace", table: "Widgets"), tone: .positive)
                : Status(symbol: "exclamationmark.circle.fill", text: String(localized: "widget.all.behind", defaultValue: "\(behind) of \(rentalCount) behind", table: "Widgets"), tone: .behind)
        case .timer:
            return Status(symbol: "timer", text: timerPropertyName, tone: .action)
        case .noProperty:
            return nil
        }
    }

    /// The goal-met line: "Done for 2026" for the 750 (the house is finished), the goal's hours otherwise.
    var metStatusText: String {
        snapshot.goal == .reps750
            ? String(localized: "widget.pace.done", defaultValue: "Done for \(year)", table: "Widgets")
            : String(localized: "widget.pace.reached", defaultValue: "\(goalNumber) hours reached", table: "Widgets")
    }

    // MARK: The one tappable thing (medium)

    var pill: Pill? {
        switch state {
        case .noProperty:
            return Pill(text: String(localized: "widget.pill.addRental", defaultValue: "Add a rental", table: "Widgets"), symbol: "plus", url: WidgetLinks.addProperty)
        case .timer:
            return Pill(text: String(localized: "widget.pill.stop", defaultValue: "Stop and review", table: "Widgets"), symbol: "stop.fill", url: WidgetLinks.logTime)
        default:
            guard pendingCount > 0 else { return nil }
            return Pill(text: toConfirmText, symbol: "tray.fill", url: WidgetLinks.inbox)
        }
    }

    /// "3 to confirm".
    var toConfirmText: String {
        String(localized: "widget.toConfirm", defaultValue: "\(pendingCount) to confirm", table: "Widgets")
    }

    /// Shown under the number when nothing is tappable: the stage in words ("Frame going up"). Nothing
    /// for two or more rentals: they have no stage of their own as a whole (§H.1 H10).
    var stageLine: String? {
        guard !isAllRentals, !snapshot.stageTitle.isEmpty else { return nil }
        return snapshot.stageTitle
    }

    // MARK: The house

    /// The houses to draw: one rental's, or the skyline's (all of them; the view trims to its frame).
    var houses: [WidgetRentalFigure] {
        if !snapshot.rentals.isEmpty { return snapshot.rentals }
        guard snapshot.propertyCount > 0 else { return [] }
        return [WidgetRentalFigure(id: "one", name: "", hours: snapshot.hours, stage: snapshot.houseStage, lit: snapshot.loggedToday)]
    }

    /// The single house's art name.
    var singleHouseAsset: String { WidgetHouseArt.assetName(stage: snapshot.houseStage, lit: snapshot.loggedToday) }

    // MARK: To confirm rows (large)

    var confirmRows: [WidgetConfirmRow] { snapshot.confirmRows }

    func detail(for row: WidgetConfirmRow) -> String {
        let hours = row.hours.map(WidgetFormat.hours)
        switch (row.rentalName, hours) {
        case let (name?, hours?): return "\(name) · \(hours)"
        case let (name?, nil): return name
        case let (nil, hours?): return hours
        default: return String(localized: "widget.row.notSure", defaultValue: "Not sure yet", table: "Widgets")
        }
    }

    // MARK: Lock Screen

    var inlineSymbol: String { state == .timer ? "timer" : "house.fill" }

    /// Inline (beside the date). `elapsed` is the timer text ("0:42").
    func inlineText(elapsed: String) -> String {
        switch state {
        case .noProperty:
            return String(localized: "widget.inline.add", defaultValue: "Add a rental", table: "Widgets")
        case .timer:
            return String(localized: "widget.inline.timer", defaultValue: "Timer \(elapsed) · \(timerPropertyName)", table: "Widgets")
        case .met:
            return String(localized: "widget.inline.reached", defaultValue: "\(goalNumber) hours reached", table: "Widgets")
        default:
            if pendingCount > 0 {
                return String(localized: "widget.inline.hoursConfirm", defaultValue: "\(number) hours · \(pendingCount) to confirm", table: "Widgets")
            }
            return isAllRentals
                ? String(localized: "widget.inline.across", defaultValue: "\(number) hours · \(rentalCount) rentals", table: "Widgets")
                : (snapshot.isRecord
                    ? String(localized: "widget.inline.hours", defaultValue: "\(number) hours in \(year)", table: "Widgets")
                    : String(localized: "widget.inline.ofGoal", defaultValue: "\(number) of \(goalNumber) hours", table: "Widgets"))
        }
    }

    var rectangularTitle: String {
        state == .timer ? String(localized: "widget.rect.timer", defaultValue: "Timer", table: "Widgets")
            : String(localized: "widget.rect.title", defaultValue: "Your hours", table: "Widgets")
    }

    func rectangularHeadline(elapsed: String) -> String {
        switch state {
        case .noProperty: return String(localized: "widget.inline.add", defaultValue: "Add a rental", table: "Widgets")
        case .timer: return "\(elapsed) · \(timerPropertyName)"
        default: return hoursLine
        }
    }

    var rectangularLine: String {
        if pendingCount > 0, state != .noProperty, state != .timer { return toConfirmText }
        switch state {
        case .noProperty: return String(localized: "widget.rect.startCounting", defaultValue: "to start counting", table: "Widgets")
        case .timer: return String(localized: "widget.rect.stopIt", defaultValue: "Stop it to review", table: "Widgets")
        default: return status?.text ?? ""
        }
    }

    /// The hours circular: the number in a ring (a checkmark once met, a plus with no rental).
    var hoursFace: Face {
        switch state {
        case .noProperty:
            return Face(symbol: "plus", text: "", isLarge: false, accessibilityLabel: String(localized: "widget.inline.add", defaultValue: "Add a rental", table: "Widgets"))
        case .met:
            return Face(symbol: "checkmark", text: "", isLarge: false, accessibilityLabel: String(localized: "widget.a11y.met", defaultValue: "\(number) of your \(goalNumber) hours. Goal reached.", table: "Widgets"))
        case .timer:
            return Face(symbol: nil, text: "", isLarge: true, accessibilityLabel: String(localized: "widget.a11y.timer", defaultValue: "Timer running at \(timerPropertyName)", table: "Widgets"))
        default:
            return Face(symbol: nil, text: number, isLarge: true, accessibilityLabel: hoursLine)
        }
    }

    /// The to-confirm circular. "Done" only when there are hours and nothing waits.
    var pendingFace: Face {
        if pendingCount > 0 {
            return Face(symbol: "tray.fill", text: "\(pendingCount)", isLarge: true, accessibilityLabel: toConfirmText)
        }
        switch state {
        case .noProperty:
            return Face(symbol: "plus", text: String(localized: "widget.face.add", defaultValue: "Add", table: "Widgets"), isLarge: false,
                        accessibilityLabel: String(localized: "widget.inline.add", defaultValue: "Add a rental", table: "Widgets"))
        case .empty:
            return Face(symbol: "tray", text: "–", isLarge: true, accessibilityLabel: String(localized: "widget.a11y.nothingYet", defaultValue: "Nothing to confirm yet", table: "Widgets"))
        default:
            return Face(symbol: "checkmark", text: String(localized: "widget.face.done", defaultValue: "Done", table: "Widgets"), isLarge: false,
                        accessibilityLabel: String(localized: "widget.a11y.nothing", defaultValue: "Nothing to confirm", table: "Widgets"))
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
        case .noProperty:
            return String(localized: "widget.a11y.empty", defaultValue: "LandlordHours. Add a rental to start counting.", table: "Widgets")
        case .timer:
            return String(localized: "widget.a11y.timer", defaultValue: "Timer running at \(timerPropertyName)", table: "Widgets") + "."
        default:
            var parts = [hoursLine + "."]
            if let s = status { parts.append(s.text + ".") }
            if pendingCount > 0 { parts.append(toConfirmText + ".") }
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
