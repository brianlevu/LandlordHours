import Foundation
import CoreGraphics

// MARK: - House progress (pure logic)
//
// The Blueprint house is "a chart with a roof": height is confirmed, countable hours and nothing
// else (docs/design/2.0-concepts-blueprint.md §1). This file maps those hours to one of the 19
// rendered keyframes in Assets.xcassets/Blueprint/House (manifest:
// design/blueprint-house/exports/manifest.json) and to the next-milestone words.
//
// Thresholds (one scale for every goal):
//   < 1h            empty lot (no hours yet)
//   1h ..< 100h     lot, ground being broken (the lot keyframe; the slab is not poured yet)
//   100h            slab poured (MP test 3 hours)
//   100h ..< 500h   framing rises through its keyframes, never ahead of the hours (floor)
//   500h            roof on (MP test 1 hours)
//   500h ... 750h   siding goes up through its keyframes (floor); exactly 750h = siding complete
//   > 750h          finished: windows lit, keys in the door. The IRS test is MORE than 750.
//
// MP goals (decision, 2026-10-19, WP-H): the house keeps ONE absolute scale for every goal. The
// stages are the law's thresholds (100 = MP test 3, 500 = MP test 1, 750 = REPS), so the same
// picture always means the same hours to the owner, a spouse and a CPA. Rescaling the house to a
// goal would put a roof on at 50h for an MP-100 owner, which mislabels the thresholds. The goal
// changes only: the target the copy measures against ("of 500h"), which milestone is flagged as
// the goal, and the goal-met state. After the goal the house keeps building toward the next stage.
//
// Floor rule: a keyframe is shown only once its full share of hours is confirmed ("a graphic never
// shows an unconfirmed hour"). Consequence: k11_frame100 (frame complete, no roof) is never a
// resting state; it is the "before" frame the 500h celebration lands the roof on.

/// The goal the house measures against. Hours that count differ per goal (see `countableHours`).
enum HouseGoal: String, CaseIterable, Codable, Sendable {
    /// Real estate professional status: more than 750 hours (plus the 50% rule, tracked elsewhere).
    case reps750 = "reps"
    /// Material participation test 1: more than 500 hours.
    case mp500 = "mp500"
    /// Material participation test 3: more than 100 hours (and no one else did more).
    case mp100 = "mp100"

    var targetHours: Double {
        switch self {
        case .reps750: return 750
        case .mp500: return 500
        case .mp100: return 100
        }
    }

    /// The construction milestone that matches this goal's hour threshold.
    var milestone: HouseMilestone {
        switch self {
        case .reps750: return .keys750
        case .mp500: return .roof500
        case .mp100: return .foundation100
        }
    }

    /// Short words for labels: "REPS goal", "material participation goal".
    var spokenName: String {
        switch self {
        case .reps750: return "REPS"
        case .mp500: return "material participation, 500 hours"
        case .mp100: return "material participation, 100 hours"
        }
    }

    /// Hero eyebrow in plain words, e.g. "750-hour goal" (no "REPS"/"MP" jargon on screen).
    var eyebrow: String {
        switch self {
        case .reps750: return "750-hour goal"
        case .mp500: return "500-hour goal"
        case .mp100: return "100-hour goal"
        }
    }

    /// Bridges the 1.x settings goal. `.both` keeps REPS as the primary (higher) target, as 1.x did.
    init(_ legacy: HourGoalType) {
        switch legacy {
        case .reps, .both: self = .reps750
        case .str: self = .mp100
        }
    }

    /// Parses launch-argument and test spellings: "reps", "reps750", "mp500", "500", "mp100", "100".
    init?(argument: String) {
        switch argument.lowercased() {
        case "reps", "reps750", "750": self = .reps750
        case "mp500", "mp1", "500": self = .mp500
        case "mp100", "mp3", "100", "str": self = .mp100
        default: return nil
        }
    }
}

/// The construction milestones. Each is celebrated once when a confirm crosses it.
enum HouseMilestone: Int, CaseIterable, Comparable, Codable, Sendable {
    case foundation100 = 100
    case roof500 = 500
    case keys750 = 750

    var thresholdHours: Double { Double(rawValue) }

    /// The roof and slab land AT their hours; the keys need MORE than 750 (the IRS wording).
    func isReached(by hours: Double) -> Bool {
        switch self {
        case .foundation100, .roof500: return hours >= thresholdHours
        case .keys750: return hours > thresholdHours
        }
    }


    static func < (lhs: HouseMilestone, rhs: HouseMilestone) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One step on the way to the goal, for the "next" label: a building stage or the goal's keys.
struct HouseStep: Equatable, Sendable {
    let thresholdHours: Double
    /// True for "more than" tests (the keys, the finish); false for stages that land AT the hours.
    let isStrict: Bool
    let label: String
    let spokenLabel: String

    func isReached(by hours: Double) -> Bool { isStrict ? hours > thresholdHours : hours >= thresholdHours }

    static let foundation = HouseStep(thresholdHours: 100, isStrict: false, label: "Foundation at 100h", spokenLabel: "foundation at 100 hours")
    static let roof = HouseStep(thresholdHours: 500, isStrict: false, label: "Roof at 500h", spokenLabel: "roof at 500 hours")
    static let finished = HouseStep(thresholdHours: 750, isStrict: true, label: "Finished after 750h", spokenLabel: "house finished after 750 hours")

    static func keys(for goal: HouseGoal) -> HouseStep {
        let t = Int(goal.targetHours)
        return HouseStep(thresholdHours: goal.targetHours, isStrict: true, label: "Keys after \(t)h", spokenLabel: "keys after \(t) hours")
    }

    /// The steps in hour order. REPS: its keys are the finish.
    static func steps(for goal: HouseGoal) -> [HouseStep] {
        switch goal {
        case .reps750: return [.foundation, .roof, keys(for: goal)]
        case .mp500: return [.foundation, .roof, keys(for: goal), .finished]
        case .mp100: return [.foundation, keys(for: goal), .roof, .finished]
        }
    }
}

/// A celebration screen: a building stage, or the goal's keys-in-the-door moment.
enum HouseCelebration: Hashable, Identifiable, Sendable {
    case stage(HouseMilestone)
    case goalMet(HouseGoal)

    var id: String {
        switch self {
        case .stage(let m): return "stage-\(m.rawValue)"
        case .goalMet(let g): return "goal-\(g.rawValue)"
        }
    }

    var thresholdHours: Double {
        switch self {
        case .stage(let m): return m.thresholdHours
        case .goalMet(let g): return g.targetHours
        }
    }
}

/// The construction stage, for words and accessibility. Derived from the keyframe.
enum HouseStage: Int, CaseIterable, Comparable, Sendable {
    case emptyLot, groundwork, slab, framing, roofed, siding, finished

    var spokenName: String {
        switch self {
        case .emptyLot: return "An empty lot"
        case .groundwork: return "Breaking ground"
        case .slab: return "Foundation poured"
        case .framing: return "Frame going up"
        case .roofed: return "Roof on"
        case .siding: return "Siding going up"
        case .finished: return "House finished"
        }
    }

    static func < (lhs: HouseStage, rhs: HouseStage) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One rendered keyframe pair (built pass + linework), in draw order. Raw values are the manifest
/// keys; asset names follow `bp_house_<key>_built` / `bp_house_<key>_lines`.
enum HouseKeyframe: String, CaseIterable, Sendable {
    case k00_lot, k01_slab
    case k02_frame010, k03_frame020, k04_frame030, k05_frame040, k06_frame050
    case k07_frame060, k08_frame070, k09_frame080, k10_frame090, k11_frame100
    case k12_roof
    case k13_siding020, k14_siding040, k15_siding060, k16_siding080, k17_siding100
    case k18_finished

    var builtImageName: String { "bp_house_\(rawValue)_built" }
    var linesImageName: String { "bp_house_\(rawValue)_lines" }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// Manifest stage number: 0 lot, 1 slab, 2 frame, 3 roof, 4 siding, 5 finished.
    var manifestStage: Int {
        switch self {
        case .k00_lot: return 0
        case .k01_slab: return 1
        case .k02_frame010, .k03_frame020, .k04_frame030, .k05_frame040, .k06_frame050,
             .k07_frame060, .k08_frame070, .k09_frame080, .k10_frame090, .k11_frame100: return 2
        case .k12_roof: return 3
        case .k13_siding020, .k14_siding040, .k15_siding060, .k16_siding080, .k17_siding100: return 4
        case .k18_finished: return 5
        }
    }

    /// Framing keyframes k02...k11 in order (10% to 100% of the frame).
    static let framing: [HouseKeyframe] = [
        .k02_frame010, .k03_frame020, .k04_frame030, .k05_frame040, .k06_frame050,
        .k07_frame060, .k08_frame070, .k09_frame080, .k10_frame090, .k11_frame100,
    ]
    /// Siding keyframes k13...k17 in order (20% to 100% of the siding).
    static let siding: [HouseKeyframe] = [.k13_siding020, .k14_siding040, .k15_siding060, .k16_siding080, .k17_siding100]

    /// The keyframe the confirm board sequence was registered against (manifest `confirm_row.base`).
    static let confirmSequenceBase: HouseKeyframe = .k14_siding040

    /// Where the newest course of this keyframe sits in the 320 pt camera (unit coordinates):
    /// the densest band of pixels that changed from the previous keyframe (measured from the
    /// @3x light built passes, 2026-10-19). The confirm beam lands here and the glow pulses here.
    var courseAnchor: CGPoint {
        switch self {
        case .k00_lot: return CGPoint(x: 0.50, y: 0.80)
        case .k01_slab: return CGPoint(x: 0.39, y: 0.79)
        case .k02_frame010: return CGPoint(x: 0.51, y: 0.65)
        case .k03_frame020: return CGPoint(x: 0.53, y: 0.47)
        case .k04_frame030: return CGPoint(x: 0.31, y: 0.53)
        case .k05_frame040: return CGPoint(x: 0.31, y: 0.69)
        case .k06_frame050: return CGPoint(x: 0.40, y: 0.52)
        case .k07_frame060: return CGPoint(x: 0.54, y: 0.41)
        case .k08_frame070: return CGPoint(x: 0.51, y: 0.31)
        case .k09_frame080: return CGPoint(x: 0.32, y: 0.41)
        case .k10_frame090: return CGPoint(x: 0.36, y: 0.48)
        case .k11_frame100: return CGPoint(x: 0.40, y: 0.28)
        case .k12_roof: return CGPoint(x: 0.42, y: 0.27)
        case .k13_siding020: return CGPoint(x: 0.44, y: 0.67)
        case .k14_siding040: return CGPoint(x: 0.44, y: 0.59)
        case .k15_siding060: return CGPoint(x: 0.42, y: 0.53)
        case .k16_siding080: return CGPoint(x: 0.57, y: 0.43)
        case .k17_siding100: return CGPoint(x: 0.61, y: 0.57)
        case .k18_finished: return CGPoint(x: 0.48, y: 0.65)
        }
    }

    /// The board sequence rests at y ≈ 0.577 of the camera (its densest row). When a confirm
    /// crosses INTO a siding keyframe, the board is shifted by this much (unit height) so it lands
    /// on that keyframe's new course; nil where a siding board would be the wrong material
    /// (lot, slab, framing, roof, the porch at 100% and the finish).
    var confirmBoardOffset: CGFloat? {
        switch self {
        case .k13_siding020, .k14_siding040, .k15_siding060, .k16_siding080:
            return courseAnchor.y - 0.577
        default:
            return nil
        }
    }
}

/// Maps countable hours + goal to everything the house views need. Pure value type.
struct HouseProgress: Equatable, Sendable {
    let hours: Double
    let goal: HouseGoal

    init(hours: Double, goal: HouseGoal) {
        // Negative or non-finite input never draws anything.
        self.hours = hours.isFinite ? max(0, hours) : 0
        self.goal = goal
    }

    // MARK: Keyframe

    var keyframe: HouseKeyframe { Self.keyframe(for: hours) }

    static func keyframe(for rawHours: Double) -> HouseKeyframe {
        let h = rawHours.isFinite ? max(0, rawHours) : 0
        if h < 100 { return .k00_lot }
        if h < 500 {
            // Floor: the slab until the first 10% of framing (40h) is fully confirmed.
            let slot = Int(((h - 100) / 400 * 10).rounded(.down))     // 0...9
            return slot <= 0 ? .k01_slab : HouseKeyframe.framing[min(slot, 9) - 1]
        }
        if h <= 750 {
            if h == 750 { return .k17_siding100 }
            let slot = Int(((h - 500) / 250 * 5).rounded(.down))      // 0...4
            return slot <= 0 ? .k12_roof : HouseKeyframe.siding[min(slot, 5) - 1]
        }
        return .k18_finished
    }

    // MARK: Stage

    var stage: HouseStage {
        if hours < 1 { return .emptyLot }
        switch keyframe.manifestStage {
        case 0: return .groundwork
        case 1: return .slab
        case 2: return .framing
        case 3: return .roofed
        case 4: return .siding
        default: return .finished
        }
    }

    // MARK: Milestones and the goal's keys
    //
    // Building stages stay on the IRS thresholds (slab 100, roof 500, finished > 750) for every
    // goal. The KEYS moment (keys in the door, windows lit) celebrates the owner's OWN goal: REPS
    // gets it with the finished house (> 750), an MP-500 owner on the roofed house (> 500), an
    // MP-100 owner at the slab (> 100). The house keeps building afterwards.

    /// The next step on the way, in the order this goal meets them; nil when everything is done.
    var nextStep: HouseStep? {
        HouseStep.steps(for: goal).first { !$0.isReached(by: hours) }
    }

    /// The next construction milestone not yet reached, or nil when the house is finished.
    var nextMilestone: HouseMilestone? {
        HouseMilestone.allCases.first { !$0.isReached(by: hours) }
    }

    /// "Roof at 500h", "Keys after 500h", or "House finished" when every step is done.
    var nextMilestoneLabel: String {
        nextStep?.label ?? "House finished"
    }

    /// Hours still to confirm before the next step; nil when done. A "more than" step at exactly
    /// its threshold still needs an hour ("1h to go").
    var hoursToNextMilestone: Double? {
        guard let next = nextStep else { return nil }
        let gap = next.thresholdHours - hours
        return next.isStrict ? max(gap, 0) + (gap <= 0 ? 1 : 0) : max(gap, 0)
    }

    /// The goal's hour test, in the law's words: MORE than the target (750 / 500 / 100). The stage
    /// art lands AT 100 and 500, but the copy only says a goal's hours are reached once passed.
    var isGoalMet: Bool { hours > goal.targetHours }

    /// Milestones a change from `old` to `new` hours crosses, lowest first. Only upward crossings
    /// celebrate; deleting hours never replays a milestone.
    static func milestonesCrossed(from old: Double, to new: Double) -> [HouseMilestone] {
        guard new > old else { return [] }
        return HouseMilestone.allCases.filter { !$0.isReached(by: old) && $0.isReached(by: new) }
    }

    /// Celebrations a confirm earns, lowest first. The goal's keys replace the stage celebration
    /// at the same threshold (REPS: the 750 finish IS the keys). The hero shows only the last.
    static func celebrations(from old: Double, to new: Double, goal: HouseGoal) -> [HouseCelebration] {
        guard new > old else { return [] }
        var result: [HouseCelebration] = milestonesCrossed(from: old, to: new).map { .stage($0) }
        if old <= goal.targetHours && new > goal.targetHours {
            result.removeAll { $0 == .stage(goal.milestone) }
            result.append(.goalMet(goal))
        }
        return result.sorted { $0.thresholdHours < $1.thresholdHours }
    }

    /// True when the change moves the house to a different keyframe.
    static func crossesKeyframe(from old: Double, to new: Double) -> Bool {
        keyframe(for: old) != keyframe(for: new)
    }

    // MARK: Words

    /// Whole hours, rounded down so the number never runs ahead of the records.
    var wholeHours: Int { Int(hours.rounded(.down)) }

    /// VoiceOver: hours, goal and next milestone in words.
    /// "House built to 212 of 750 hours, REPS goal. Frame going up. Next, roof at 500 hours, 288 hours to go."
    var accessibilityLabel: String { accessibilityLabel(claimsGoalReached: true) }

    /// `claimsGoalReached: false` leaves out "Goal hours reached" while a test still has an open
    /// question (the 100-hour test before "did anyone do more?" is answered, the 750 before the half test).
    func accessibilityLabel(claimsGoalReached: Bool) -> String {
        var parts: [String] = []
        parts.append("House built to \(wholeHours) of \(Int(goal.targetHours)) hours, \(goal.spokenName) goal.")
        parts.append("\(stage.spokenName).")
        if isGoalMet && claimsGoalReached {
            parts.append("Goal hours reached, based on your records.")
        }
        if let next = nextStep, let toGo = hoursToNextMilestone {
            let toGoWords = Self.hoursWords(toGo)
            parts.append("Next, \(next.spokenLabel), \(toGoWords) to go.")
        } else {
            parts.append("Every stage is built.")
        }
        return parts.joined(separator: " ")
    }

    static func hoursWords(_ hours: Double) -> String {
        let whole = Int(hours.rounded(.up))
        return whole == 1 ? "1 hour" : "\(whole) hours"
    }

    // MARK: Countable hours

    /// Countable hours for a tax year (the same rule for every goal today). Only categories that count for real estate
    /// participation (investor-only tasks such as investing, financing and deal negotiation never
    /// count). Spouse hours count only when the household tracks them jointly. Suggestions are
    /// not entries, so unconfirmed hours never reach the house.
    static func countableHours(
        entries: [TimeEntry],
        year: Int,
        includeSpouse: Bool,
        calendar: Calendar = .current
    ) -> Double {
        entries
            .filter { calendar.component(.year, from: $0.date) == year }
            .filter { $0.countsForREPS }
            .filter { $0.participant == .selfParticipant || (includeSpouse && $0.participant == .spouse) }
            .reduce(0) { $0 + max(0, $1.hours) }
    }
}
