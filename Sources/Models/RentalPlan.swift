import Foundation

// MARK: - How each rental is tracked (2.1)
//
// Every rental is tracked one of three ways, in the owner's words:
//   - it has its own target (100 or 500 hours, set for that rental),
//   - it is record only (the hours are kept, nothing is aimed at), or
//   - it counts toward one shared total (the 750, a grouped activity).
//
// The app picks a default from the goal and the kind of rental. The owner can override it for
// one rental, and an override is KEPT when the goal changes: only rentals the owner has not
// touched are worked out again. Everything here is a plain rule on stored answers (no AI, no
// advice): each line the app prints can be traced to an answer the owner gave.
//
// Pure value logic first (`RentalPlanning`), then the per-profile store the views read.

// MARK: Who does most of the hands-on work

/// The owner's answer to "Who does most of the hands-on work here?", asked per rental.
enum WhoDoesMost: String, CaseIterable, Codable, Hashable, Sendable {
    case me, meAndSpouse, someoneElse, notSure

    /// 100 hours and more than anyone else only makes sense when nobody else does more here.
    var allowsHundred: Bool { self == .me || self == .meAndSpouse }
}

// MARK: Tracks

/// Why a rental is record only, in words the row can print.
enum RecordReason: String, Codable, Hashable, Sendable {
    /// Long stays have no target under a short-stay goal, when the owner also has short stays.
    case longStays
    /// Someone else does most of the work here (a manager, cleaner or contractor).
    case someoneElse
    /// The owner switched this rental to record only.
    case yourChoice
    /// The goal is "just keep a record": every rental is.
    case goalIsRecord
}

enum RentalTrack: Equatable, Hashable, Sendable {
    /// Its own target: 100 or 500 hours.
    case ownTarget(hours: Int)
    /// Hours kept, no target.
    case recordOnly(RecordReason)
    /// Counts toward the shared total. `hours` is the shared target (750, or the grouped 100/500).
    case sharedTotal(hours: Int)

    var hasOwnTarget: Bool { if case .ownTarget = self { return true }; return false }
    var isRecordOnly: Bool { if case .recordOnly = self { return true }; return false }
    var isShared: Bool { if case .sharedTotal = self { return true }; return false }

    /// The target this rental is measured against, nil when it has none of its own.
    var targetHours: Int? {
        switch self {
        case .ownTarget(let h), .sharedTotal(let h): return h
        case .recordOnly: return nil
        }
    }

    /// The house goal behind a target of 100, 500 or 750 hours.
    static func houseGoal(forHours hours: Int) -> HouseGoal {
        hours >= 750 ? .reps750 : (hours >= 500 ? .mp500 : .mp100)
    }
}

/// What the owner set by hand for one rental.
enum RentalOverride: Codable, Hashable, Sendable {
    /// "Track a goal for this rental", with the target the app works out (100 or 500).
    case track
    /// "Track a goal for this rental", pinned to this many hours (Check my goal's "Keep").
    case trackPinned(hours: Int)
    /// "Record only".
    case record

    private enum CodingKeys: String, CodingKey { case kind, hours }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "record": self = .record
        case "pinned": self = .trackPinned(hours: try c.decode(Int.self, forKey: .hours))
        default: self = .track
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .track: try c.encode("track", forKey: .kind)
        case .record: try c.encode("record", forKey: .kind)
        case .trackPinned(let h):
            try c.encode("pinned", forKey: .kind)
            try c.encode(h, forKey: .hours)
        }
    }
}

struct RentalPlan: Equatable, Sendable {
    var track: RentalTrack
    /// The owner set this by hand (it survives a goal change).
    var isOverride: Bool
}

/// How the whole profile is tracked, which decides the shape of Today.
enum RentalPlanMode: Equatable, Sendable {
    /// 100 or 500 hours, each rental on its own.
    case perRental
    /// 750, or 100/500 with the grouping election: one total. `hours` is that total's target.
    case shared(hours: Int)
    /// "Just keep a record": no targets anywhere.
    case record
}

// MARK: Resolver

struct RentalPlanContext: Sendable {
    var goal: GoalChoice
    var grouping: Bool
    var properties: [RentalProperty]
    var overrides: [UUID: RentalOverride] = [:]
    var whoDoesMost: [UUID: WhoDoesMost] = [:]
}

enum RentalPlanning {
    static func mode(_ ctx: RentalPlanContext) -> RentalPlanMode {
        switch ctx.goal {
        case .record: return .record
        case .reps750: return .shared(hours: 750)
        case .mp100, .mp500: return ctx.grouping ? .shared(hours: Int(ctx.goal.targetHours)) : .perRental
        }
    }

    /// The target a rental gets when it has its own: the goal's number, except that 100 hours
    /// and more than anyone else cannot be tracked where someone else does more (or the owner
    /// is not sure who does), so that rental gets 500, which compares nobody.
    static func ownTargetHours(goal: GoalChoice, whoDoesMost: WhoDoesMost?) -> Int {
        let base = Int(goal.targetHours)
        if goal == .mp100, let who = whoDoesMost, !who.allowsHundred { return 500 }
        return base
    }

    /// Rentals that have their own target by default: the short-stay rentals when stays are
    /// mixed (a long stay's hours never stand in for one), otherwise every rental.
    static func countsByDefault(_ property: RentalProperty, in properties: [RentalProperty]) -> Bool {
        TaxQualificationEngine.countedProperties(properties).contains { $0.id == property.id }
    }

    static func plan(for property: RentalProperty, _ ctx: RentalPlanContext) -> RentalPlan {
        switch mode(ctx) {
        case .record:
            return RentalPlan(track: .recordOnly(.goalIsRecord), isOverride: false)
        case .shared(let hours):
            return RentalPlan(track: .sharedTotal(hours: hours), isOverride: false)
        case .perRental:
            let who = ctx.whoDoesMost[property.id]
            if let override = ctx.overrides[property.id] {
                switch override {
                case .record: return RentalPlan(track: .recordOnly(.yourChoice), isOverride: true)
                case .track: return RentalPlan(track: .ownTarget(hours: ownTargetHours(goal: ctx.goal, whoDoesMost: who)), isOverride: true)
                case .trackPinned(let h): return RentalPlan(track: .ownTarget(hours: h), isOverride: true)
                }
            }
            if countsByDefault(property, in: ctx.properties) {
                return RentalPlan(track: .ownTarget(hours: ownTargetHours(goal: ctx.goal, whoDoesMost: who)), isOverride: false)
            }
            return RentalPlan(track: .recordOnly(who == .someoneElse ? .someoneElse : .longStays), isOverride: false)
        }
    }

    static func plans(_ ctx: RentalPlanContext) -> [UUID: RentalPlan] {
        Dictionary(uniqueKeysWithValues: ctx.properties.map { ($0.id, plan(for: $0, ctx)) })
    }

    /// The rental Today starts on when the owner has not picked one: the rental with its own
    /// target that has the most hours (list order breaks a tie). nil in a shared or record
    /// profile (Today starts on "All rentals") and when no rental has a target.
    static func defaultFocus(_ ctx: RentalPlanContext, hours: (UUID) -> Double) -> UUID? {
        guard mode(ctx) == .perRental else { return nil }
        let plans = Self.plans(ctx)
        var best: (UUID, Double)?
        for p in ctx.properties where plans[p.id]?.track.hasOwnTarget == true {
            let h = hours(p.id)
            if best == nil || h > best!.1 { best = (p.id, h) }
        }
        return best?.0 ?? ctx.properties.first?.id
    }
}

// MARK: The one stage function

/// The house a rental shows. The hero and every tile ask this, so a rental never shows one
/// house in the hero and another in its tile.
///  - own target: builds with its hours, pinned at the 500 line (a rental's house never runs
///    past its roof, owner decision 2026-10-19);
///  - shared total (the "All rentals" tile, 750): builds with the total, unpinned;
///  - record only: a plain lot (no target, nothing is being built).
enum RentalStage {
    static func hours(track: RentalTrack, hours: Double) -> Double {
        let h = hours.isFinite ? max(0, hours) : 0
        switch track {
        case .ownTarget: return min(h, 500)
        case .sharedTotal: return h
        case .recordOnly: return 0
        }
    }

    static func keyframe(track: RentalTrack, hours: Double) -> HouseKeyframe {
        HouseProgress.keyframe(for: Self.hours(track: track, hours: hours))
    }

    /// True when the art is a plain lot (a record-only rental).
    static func isPlainLot(_ track: RentalTrack) -> Bool { track.isRecordOnly }
}

// MARK: Words

/// Every line the plan prints. One place, all in the String Catalog (`Home` table).
enum RentalPlanWords {
    static let cpaLine = String(localized: "Reaching a number is based on your records; your CPA decides what it means.", table: "Home")

    /// "Hours kept, no target".
    static var hoursKept: String { String(localized: "Hours kept, no target", table: "Home") }

    static func reason(_ r: RecordReason) -> String {
        switch r {
        case .longStays: return String(localized: "Long stays have no target under your goal", table: "Home")
        case .someoneElse: return String(localized: "Someone else does most of the work here", table: "Home")
        case .yourChoice: return String(localized: "You chose to keep a record here", table: "Home")
        case .goalIsRecord: return String(localized: "Your goal is to keep a record", table: "Home")
        }
    }

    /// The Properties row's second part: "Long stays: hours kept, no target".
    static func rowRoleLine(_ track: RentalTrack, kindLabel: String) -> String {
        switch track {
        case .ownTarget(let h): return String(localized: "\(h)-hour target", table: "Home")
        case .sharedTotal(let h): return String(localized: "Counts toward your \(h)", table: "Home")
        case .recordOnly(let r):
            switch r {
            case .longStays: return String(localized: "Long stays: hours kept, no target", table: "Home")
            case .someoneElse: return String(localized: "Someone else does most: hours kept, no target", table: "Home")
            case .yourChoice: return String(localized: "\(kindLabel): hours kept, no target", table: "Home")
            case .goalIsRecord: return String(localized: "Hours kept, no target", table: "Home")
            }
        }
    }

    /// The tile's small line.
    static func tileLine(_ track: RentalTrack) -> String {
        switch track {
        case .ownTarget(let h): return String(localized: "\(h)-hour target", table: "Home")
        case .recordOnly: return String(localized: "Record only", table: "Home")
        case .sharedTotal(let h): return String(localized: "Counts toward \(h)", table: "Home")
        }
    }

    /// The rental page's control labels.
    static var trackAGoal: String { String(localized: "Track a goal for this rental", table: "Home") }
    static var recordOnly: String { String(localized: "Record only", table: "Home") }

    /// Under "Check my goal": the reason a rental moves to or stays at a target.
    static func targetReason(whoDoesMost: WhoDoesMost?, hours: Int) -> String {
        switch whoDoesMost {
        case .me, .meAndSpouse:
            return hours == 100
                ? String(localized: "You do most of the work, so 100 hours and more than anyone else still fits", table: "Home")
                : String(localized: "You do most of the work here. Your goal is 500 hours, which compares nobody", table: "Home")
        case .someoneElse:
            return String(localized: "Someone else does more hours here, so the app can’t track 100 here. 500 doesn’t compare you with anyone", table: "Home")
        case .notSure:
            return String(localized: "Not sure who does most, so the app can’t track 100 here. 500 doesn’t compare you with anyone", table: "Home")
        case nil:
            return String(localized: "This is your goal’s own number", table: "Home")
        }
    }
}

// MARK: Change summary (the toast)

enum RentalPlanChange {
    /// One toast sentence for what changed between two sets of plans, or nil when nothing did.
    /// A rental the owner set by hand is named as kept.
    static func summary(before: [UUID: RentalPlan], after: [UUID: RentalPlan], properties: [RentalProperty]) -> String? {
        let changed = properties.filter { before[$0.id] != nil && after[$0.id] != nil && before[$0.id]!.track != after[$0.id]!.track }
        guard !changed.isEmpty else { return nil }
        let kept = properties.filter { after[$0.id]?.isOverride == true }
        var sentence: String
        if changed.allSatisfy({ after[$0.id]?.track.isShared == true }), let h = after[changed[0].id]?.track.targetHours {
            sentence = String(localized: "Every rental now counts toward one \(h)-hour total.", table: "Home")
        } else if changed.allSatisfy({ after[$0.id]?.track.isRecordOnly == true && after[$0.id]?.track != .recordOnly(.yourChoice) }),
                  changed.count == properties.count {
            sentence = String(localized: "Your rentals now keep hours with no target.", table: "Home")
        } else if changed.count == 1, let t = after[changed[0].id]?.track {
            let name = changed[0].name
            switch t {
            case .ownTarget(let h): sentence = String(localized: "\(name) now has its own \(h)-hour target.", table: "Home")
            case .recordOnly: sentence = String(localized: "\(name) is now record only.", table: "Home")
            case .sharedTotal(let h): sentence = String(localized: "\(name) now counts toward your \(h).", table: "Home")
            }
        } else {
            sentence = String(localized: "\(changed.count) rentals changed with your new goal.", table: "Home")
        }
        if !kept.isEmpty, !changed.allSatisfy({ after[$0.id]?.isOverride == true }) {
            sentence += " " + String(localized: "Rentals you set yourself stayed as they were.", table: "Home")
        }
        return sentence
    }
}

// MARK: Check my goal (rules)

/// One row of the Keep/Switch diff.
struct GoalCheckRow: Equatable, Identifiable, Sendable {
    let propertyId: UUID
    let name: String
    let current: RentalTrack
    let proposed: RentalTrack
    let whoDoesMost: WhoDoesMost?
    var id: UUID { propertyId }
    var changes: Bool { current != proposed }
}

enum GoalCheck {
    /// What the app tracks now against what it would track with the answers in `draft`.
    /// Overrides are honoured on both sides, so a rental the owner pinned does not move.
    static func rows(_ ctx: RentalPlanContext, draft: [UUID: WhoDoesMost]) -> [GoalCheckRow] {
        var proposedCtx = ctx
        for (id, who) in draft { proposedCtx.whoDoesMost[id] = who }
        return ctx.properties.map { p in
            GoalCheckRow(
                propertyId: p.id, name: p.name,
                current: RentalPlanning.plan(for: p, ctx).track,
                proposed: RentalPlanning.plan(for: p, proposedCtx).track,
                whoDoesMost: draft[p.id] ?? ctx.whoDoesMost[p.id])
        }
    }

    /// Per-rental questions apply only where each rental can have its own target.
    static func asksPerRental(_ ctx: RentalPlanContext) -> Bool { RentalPlanning.mode(ctx) == .perRental }

    /// Whether to show "Check my goal" at all: at least one rental.
    static func isAvailable(_ ctx: RentalPlanContext) -> Bool { !ctx.properties.isEmpty }
}

// MARK: Calendar facts (stub hook)

/// A fact the calendar suggests, which the owner confirms before anything changes. The detector
/// that reads cleaner and turnover events is a later piece; this is the seam it plugs into, and
/// the stub returns nothing, so the Inbox card never appears in a shipped build.
struct CleanerFact: Equatable, Identifiable, Sendable {
    let propertyId: UUID
    let propertyName: String
    /// The calendar title behind it, e.g. "Turnover clean".
    let eventTitle: String
    var id: UUID { propertyId }
}

protocol CleanerFactSource: Sendable {
    func facts(for properties: [RentalProperty]) -> [CleanerFact]
}

struct StubCleanerFactSource: CleanerFactSource {
    func facts(for properties: [RentalProperty]) -> [CleanerFact] { [] }
}

// MARK: - Per-profile store

/// The owner's answers and overrides, per profile, plus the rental Today is focused on.
/// Everything is local to this device, scoped like the other 2.0 setup answers.
@MainActor
final class RentalPlanStore: ObservableObject {
    static let shared = RentalPlanStore()

    static let overridesBaseKey = "LandlordHours.rentalPlan.overrides"
    static let whoBaseKey = "LandlordHours.rentalPlan.whoDoesMost"
    static let focusBaseKey = "LandlordHours.rentalPlan.todayFocus"
    static let snapshotBaseKey = "LandlordHours.rentalPlan.lastTracks"
    static let allKeys = [overridesBaseKey, whoBaseKey, focusBaseKey, snapshotBaseKey]

    /// The source of "Today is on All rentals".
    static let allFocusToken = "all"

    private let defaults: UserDefaults
    private let userIdProvider: () -> String?
    var cleanerFacts: CleanerFactSource = StubCleanerFactSource()

    init(defaults: UserDefaults = .standard, userId: @escaping () -> String? = { UserScope.userId }) {
        self.defaults = defaults
        self.userIdProvider = userId
        reload()
    }

    private func key(_ base: String) -> String { UserScope.key(base, userId: userIdProvider()) }

    @Published private(set) var overrides: [UUID: RentalOverride] = [:]
    @Published private(set) var whoDoesMost: [UUID: WhoDoesMost] = [:]
    /// nil: not chosen (Today uses its default). `allFocusToken`, or a rental's id.
    @Published private(set) var focusToken: String?
    private var lastTracks: [String: String] = [:]

    func reload() {
        overrides = Self.decode([String: RentalOverride].self, defaults.data(forKey: key(Self.overridesBaseKey)))
            .reduce(into: [:]) { if let id = UUID(uuidString: $1.key) { $0[id] = $1.value } }
        whoDoesMost = Self.decode([String: WhoDoesMost].self, defaults.data(forKey: key(Self.whoBaseKey)))
            .reduce(into: [:]) { if let id = UUID(uuidString: $1.key) { $0[id] = $1.value } }
        focusToken = defaults.string(forKey: key(Self.focusBaseKey))
        lastTracks = Self.decode([String: String].self, defaults.data(forKey: key(Self.snapshotBaseKey)))
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T where T: ExpressibleByDictionaryLiteral {
        guard let data, let value = try? JSONDecoder().decode(T.self, from: data) else { return [:] }
        return value
    }

    private func persist() {
        let o = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.uuidString, $0.value) })
        let w = Dictionary(uniqueKeysWithValues: whoDoesMost.map { ($0.key.uuidString, $0.value) })
        defaults.set(try? JSONEncoder().encode(o), forKey: key(Self.overridesBaseKey))
        defaults.set(try? JSONEncoder().encode(w), forKey: key(Self.whoBaseKey))
        if let focusToken { defaults.set(focusToken, forKey: key(Self.focusBaseKey)) } else { defaults.removeObject(forKey: key(Self.focusBaseKey)) }
        defaults.set(try? JSONEncoder().encode(lastTracks), forKey: key(Self.snapshotBaseKey))
    }

    // MARK: Mutations

    func setOverride(_ value: RentalOverride?, for id: UUID) {
        if let value { overrides[id] = value } else { overrides.removeValue(forKey: id) }
        persist()
    }

    func setWhoDoesMost(_ value: WhoDoesMost?, for id: UUID) {
        if let value { whoDoesMost[id] = value } else { whoDoesMost.removeValue(forKey: id) }
        persist()
    }

    func setFocus(rental id: UUID?) {
        focusToken = id?.uuidString
        persist()
    }

    func setFocusAll() {
        focusToken = Self.allFocusToken
        persist()
    }

    /// A deleted rental leaves nothing behind.
    func forget(_ id: UUID) {
        overrides.removeValue(forKey: id)
        whoDoesMost.removeValue(forKey: id)
        if focusToken == id.uuidString { focusToken = nil }
        lastTracks.removeValue(forKey: id.uuidString)
        persist()
    }

    /// Profile reset / sign-out.
    func resetAll() {
        overrides = [:]; whoDoesMost = [:]; focusToken = nil; lastTracks = [:]
        for base in Self.allKeys { defaults.removeObject(forKey: key(base)) }
    }

    // MARK: Reading

    func context(properties: [RentalProperty], goal: GoalChoice, grouping: Bool) -> RentalPlanContext {
        RentalPlanContext(goal: goal, grouping: grouping, properties: properties, overrides: overrides, whoDoesMost: whoDoesMost)
    }

    /// The focus the owner chose, if it still points at something (a deleted rental falls back).
    func chosenFocus(in properties: [RentalProperty]) -> TodayFocusChoice? {
        guard let focusToken else { return nil }
        if focusToken == Self.allFocusToken { return .all }
        if let id = UUID(uuidString: focusToken), properties.contains(where: { $0.id == id }) { return .rental(id) }
        return nil
    }

    // MARK: Telling the owner what changed

    /// Compares the tracks now with the tracks last time the app looked, saves the new ones and
    /// returns the toast sentence (nil: nothing changed, or this is the first look). Call after
    /// any change that can move a rental: the goal, grouping, a rental added or edited, an answer.
    @discardableResult
    func reconcile(_ ctx: RentalPlanContext, announce: Bool = true) -> String? {
        let now = RentalPlanning.plans(ctx)
        let nowStrings = Dictionary(uniqueKeysWithValues: now.map { ($0.key.uuidString, Self.describe($0.value.track)) })
        defer { lastTracks = nowStrings; persist() }
        guard announce, !lastTracks.isEmpty else { return nil }
        var before: [UUID: RentalPlan] = [:]
        for p in ctx.properties {
            guard let s = lastTracks[p.id.uuidString], let t = Self.parse(s), let n = now[p.id] else { continue }
            before[p.id] = RentalPlan(track: t, isOverride: n.isOverride)
        }
        return RentalPlanChange.summary(before: before, after: now, properties: ctx.properties)
    }

    static func describe(_ t: RentalTrack) -> String {
        switch t {
        case .ownTarget(let h): return "own:\(h)"
        case .sharedTotal(let h): return "shared:\(h)"
        case .recordOnly(let r): return "record:\(r.rawValue)"
        }
    }

    static func parse(_ s: String) -> RentalTrack? {
        let p = s.split(separator: ":", maxSplits: 1).map(String.init)
        guard p.count == 2 else { return nil }
        switch p[0] {
        case "own": return Int(p[1]).map { .ownTarget(hours: $0) }
        case "shared": return Int(p[1]).map { .sharedTotal(hours: $0) }
        case "record": return RecordReason(rawValue: p[1]).map { .recordOnly($0) }
        default: return nil
        }
    }
}

/// What Today is focused on.
enum TodayFocusChoice: Equatable, Hashable, Sendable {
    case all
    case rental(UUID)
}
