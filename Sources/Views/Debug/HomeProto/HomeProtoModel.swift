import SwiftUI

#if DEBUG
// MARK: - Home-screen prototypes (throwaway, DEBUG only)
//
//   -LHHomeProto E|seeall|goalcheck|stages   which screen
//   -LHHomeSeed brian|reps750|eight   which sample owner
//   -LHHomeFocus <n>                  start with item n focused (E)
//   -LHHomeSum a,b                    E: start in "Add up" mode with these rental ids
//   -LHHomeSheet grid                 E: open the "See all" grid at launch
//   -LHHomeAutoplay                   E: scripted tour (for the video)
//   -LHHomeStep inbox|q1..qN|r1..rN|summary   goalcheck: the Inbox card, rental n's question or result, the summary
//   -LHHomeAnswers other,me,...       goalcheck: preset answers (me|spouse|other|notsure) per rental
//   -LHHomeSlow 4                     goalcheck: quarter-speed choreography
//
// Spec: AgentScratch/landlordhours/2026-10-23/home-options/options.md. Nothing here ships:
// the real HouseHeroCard, PropertyHouseTile and tokens are reused, never redrawn.

struct HomeProtoLaunch {
    enum Screen: String { case e = "E", seeall, goalcheck, stages }

    /// Where the Check my goal flow starts: the Inbox card, rental n's question (q), its result (r), or the summary.
    enum Step: Equatable {
        case inbox
        case question(Int)
        case result(Int)
        case summary

        init(_ raw: String) {
            let n = Int(raw.dropFirst()) ?? 1
            switch raw.first {
            case "q": self = .question(max(1, n) - 1)
            case "r": self = .result(max(1, n) - 1)
            case "s": self = .summary
            default: self = raw == "inbox" ? .inbox : .question(0)
            }
        }
    }

    let screen: Screen
    let seed: HomeProtoSeed
    let focusIndex: Int
    let step: Step
    let sum: [String]
    let grid: Bool
    /// -LHHomeAnswers other,me,...  one answer per rental, in order (me|spouse|other|notsure).
    let answers: [String]
    /// -LHHomeSlow 4  multiplies every duration in the Check my goal choreography (4 = quarter speed).
    let slow: Double
    let autoplay: Bool
    /// -LHHomeScroll rentals|end: scroll to the row of rentals (Today) or the bottom of the card (Check my goal).
    let scroll: String?

    static let current: HomeProtoLaunch? = {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let j = args.firstIndex(of: flag), args.indices.contains(j + 1) else { return nil }
            return args[j + 1]
        }
        guard let raw = value("-LHHomeProto") else { return nil }
        let screen = Screen(rawValue: raw) ?? Screen(rawValue: raw.uppercased()) ?? .e
        return HomeProtoLaunch(
            screen: screen,
            seed: HomeProtoSeed.make(value("-LHHomeSeed") ?? "brian"),
            focusIndex: Int(value("-LHHomeFocus") ?? "") ?? 0,
            step: Step(value("-LHHomeStep") ?? "q1"),
            sum: (value("-LHHomeSum") ?? "").split(separator: ",").map(String.init),
            grid: value("-LHHomeSheet") == "grid" || screen == .seeall,
            answers: (value("-LHHomeAnswers") ?? "").split(separator: ",").map(String.init),
            slow: Double(value("-LHHomeSlow") ?? "") ?? 1,
            autoplay: args.contains("-LHHomeAutoplay"),
            scroll: value("-LHHomeScroll"))
    }()
}

enum HomeProtoTarget: Equatable {
    /// Its own 100 or 500 hour target.
    case own(Int)
    /// Hours are kept, nothing is aimed at; the reason is printed in plain words.
    case record(reason: String)
    /// Counts toward the shared total (the 750).
    case counts
}

struct HomeProtoRental: Identifiable, Equatable {
    let id: String
    let name: String
    let shortStay: Bool
    let hours: Double
    let target: HomeProtoTarget
    /// Pace against its own target. Nil for record-only and shared-total rentals.
    var pace: HomeProtoPace? = nil
    /// Whole hours a week still needed (behind rentals only).
    var weeklyNeed: Int? = nil
    /// "July": the month the target was reached.
    var reached: String? = nil

    var isRecord: Bool { if case .record = target { return true }; return false }

    var hasOwnTarget: Bool { if case .own = target { return true }; return false }
}

enum HomeProtoPace { case behind, onPace, done }

enum HomeProtoFocus: Hashable {
    case all
    case rental(String)
}

struct HomeProtoSeed {
    let id: String
    let rentals: [HomeProtoRental]
    /// 750: every rental counts toward one shared total.
    let sharedTarget: Int?

    var totalHours: Double { rentals.reduce(0) { $0 + $1.hours } }
    var focusOrder: [HomeProtoFocus] { (sharedTarget != nil ? [.all] : []) + rentals.map { .rental($0.id) } }

    func rental(_ id: String) -> HomeProtoRental? { rentals.first { $0.id == id } }

    func name(_ focus: HomeProtoFocus) -> String {
        switch focus {
        case .all: return String(localized: "All rentals", table: "HomeProto")
        case .rental(let id): return rental(id)?.name ?? ""
        }
    }

    // MARK: Seeds

    static func make(_ id: String) -> HomeProtoSeed {
        switch id {
        case "reps750":
            let names = [("Maple Duplex", 71.0), ("Oak Street", 58), ("Birch Flat", 40), ("Cedar Row", 22), ("Pine Court", 14), ("Elm Lane", 7)]
            return HomeProtoSeed(id: id, rentals: names.map {
                HomeProtoRental(id: $0.0, name: $0.0, shortStay: false, hours: $0.1, target: .counts)
            }, sharedTarget: 750)
        case "eight":
            let manager = String(localized: "A manager does most of the work here", table: "HomeProto")
            let longStay = String(localized: "Long stays have no target under your goal", table: "HomeProto")
            return HomeProtoSeed(id: id, rentals: [
                HomeProtoRental(id: "tahoe", name: "Tahoe Cabin", shortStay: true, hours: 64, target: .own(100), pace: .behind, weeklyNeed: 4),
                HomeProtoRental(id: "lake", name: "Lake House", shortStay: true, hours: 112, target: .own(100), pace: .done, reached: "July"),
                HomeProtoRental(id: "palm", name: "Palm Studio", shortStay: true, hours: 230, target: .own(500), pace: .onPace),
                HomeProtoRental(id: "birch", name: "Birch Flat", shortStay: true, hours: 310, target: .own(500), pace: .onPace),
                HomeProtoRental(id: "maple", name: "Maple Duplex", shortStay: false, hours: 140, target: .own(500), pace: .behind, weeklyNeed: 36),
                HomeProtoRental(id: "oak", name: "Oak Street", shortStay: false, hours: 40, target: .record(reason: manager)),
                HomeProtoRental(id: "cedar", name: "Cedar Row", shortStay: false, hours: 22, target: .record(reason: longStay)),
                HomeProtoRental(id: "pine", name: "Pine Court", shortStay: false, hours: 0, target: .record(reason: manager)),
            ], sharedTarget: nil)
        default:
            return HomeProtoSeed(id: "brian", rentals: [
                HomeProtoRental(id: "santa", name: "Santa Ray Ave", shortStay: true, hours: 12, target: .own(100), pace: .behind, weeklyNeed: 9),
                HomeProtoRental(id: "delaney", name: "Delaney Ct", shortStay: false, hours: 84,
                                target: .record(reason: String(localized: "A manager does most of the work here", table: "HomeProto"))),
                HomeProtoRental(id: "yeandle", name: "Yeandle Ave", shortStay: false, hours: 0,
                                target: .record(reason: String(localized: "Long stays have no target under your goal", table: "HomeProto"))),
            ], sharedTarget: nil)
        }
    }

    // MARK: Hero model

    static let now: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 12)) ?? Date()

    /// Everything the hero card draws. The house stage comes from `HomeProtoStage`, the same
    /// function the tiles use, so a rental's hero and its tile always show the same house.
    struct HeroVM {
        let key: String
        let year: String
        let name: String?
        let tag: String
        let qualifier: String?
        let number: Int
        let caption: String
        let status: String?
        let tone: HouseStatusTone
        let goal: HouseGoal
        let stageHours: Double
        let stageTitle: String
        let stageSub: String?
        let flag: String
        let spoken: String
    }

    private func stageWords(_ goal: HouseGoal, hours stageHours: Double, target: Int?) -> (String, String?) {
        let progress = HouseProgress(hours: stageHours, goal: goal)
        let showsNext = progress.nextStep != nil && (target.map { $0 > 100 || stageHours < 100 } ?? false)
        return (progress.stage.spokenName, showsNext ? progress.nextMilestoneLabel : nil)
    }

    func hero(_ focus: HomeProtoFocus) -> HeroVM {
        let yearText = "2026"
        switch focus {
        case .all:
            let goal: HouseGoal = .reps750
            let copy = TodayHeroCopy.make(.init(goal: goal, hours: totalHours, year: 2026, now: Self.now, daysOfData: 200))
            let words = stageWords(goal, hours: totalHours, target: 750)
            return HeroVM(key: "all", year: yearText, name: nil, tag: copy.eyebrowTarget, qualifier: copy.qualifier,
                          number: Int(totalHours.rounded(.down)), caption: copy.caption, status: copy.status, tone: copy.tone,
                          goal: goal, stageHours: totalHours, stageTitle: words.0, stageSub: words.1, flag: name(.all),
                          spoken: copy.spoken)
        case .rental(let id):
            guard let r = rental(id) else { return hero(.all) }
            let whole = Int(r.hours.rounded(.down))
            switch r.target {
            case .own(let target):
                let goal: HouseGoal = target == 100 ? .mp100 : .mp500
                let copy = TodayHeroCopy.make(.init(goal: goal, hours: r.hours, year: 2026, now: Self.now, propertyName: r.name, daysOfData: 200))
                let stageHours = HomeProtoStage.hours(for: r)
                let words = stageWords(goal, hours: stageHours, target: target)
                return HeroVM(key: id, year: yearText, name: r.name, tag: copy.eyebrowTarget, qualifier: copy.qualifier,
                              number: whole, caption: copy.caption, status: copy.status, tone: copy.tone, goal: goal,
                              stageHours: stageHours, stageTitle: words.0, stageSub: words.1, flag: r.name, spoken: copy.spoken)
            case .record(let reason):
                // No target, so no building stage: a plain lot.
                return HeroVM(key: id, year: yearText, name: r.name, tag: String(localized: "Record only", table: "HomeProto"),
                              qualifier: reason, number: whole,
                              caption: String(localized: "hours logged in \(yearText)", table: "HomeProto"),
                              status: nil, tone: .neutral, goal: .mp500, stageHours: 0,
                              stageTitle: String(localized: "Hours kept, no target", table: "HomeProto"), stageSub: nil,
                              flag: r.name, spoken: spoken(r))
            case .counts:
                let shared = sharedTarget ?? 750
                return HeroVM(key: id, year: yearText, name: r.name, tag: String(localized: "Counts toward \(shared)", table: "HomeProto"),
                              qualifier: nil, number: whole,
                              caption: String(localized: "hours at this rental", table: "HomeProto"),
                              status: String(localized: "\(Int(totalHours)) of \(shared) in all", table: "HomeProto"), tone: .neutral,
                              goal: .mp500, stageHours: 0,
                              stageTitle: String(localized: "Part of your \(shared)", table: "HomeProto"), stageSub: nil,
                              flag: r.name, spoken: spoken(r))
            }
        }
    }

    /// Two or more rentals added up: just the sum and the names, no target and no stage.
    func combined(_ ids: [String]) -> HeroVM {
        let picked = ids.compactMap { rental($0) }
        let total = picked.reduce(0) { $0 + $1.hours }
        let names: String
        switch picked.count {
        case 0, 1: names = picked.first?.name ?? ""
        case 2: names = "\(picked[0].name) + \(picked[1].name)"
        default: names = String(localized: "\(picked[0].name) + \(picked[1].name) + \(picked.count - 2) more", table: "HomeProto")
        }
        let tag = String(localized: "Added up", table: "HomeProto")
        let whole = Int(total.rounded(.down))
        return HeroVM(key: "sum-" + ids.joined(separator: "-"), year: "2026", name: nil, tag: tag, qualifier: nil, number: whole,
                      caption: String(localized: "hours combined", table: "HomeProto"), status: names, tone: .neutral,
                      goal: .mp500, stageHours: 0,
                      stageTitle: String(localized: "Added up, no target", table: "HomeProto"), stageSub: nil,
                      flag: String(localized: "\(picked.count) rentals", table: "HomeProto"),
                      spoken: String(localized: "\(whole) hours combined, \(names)", table: "HomeProto"))
    }

    // MARK: Words for tiles and rows

    func targetLine(_ r: HomeProtoRental) -> String {
        switch r.target {
        case .own(let t): return String(localized: "\(t)-hour target", table: "HomeProto")
        case .record: return String(localized: "Record only", table: "HomeProto")
        case .counts: return String(localized: "Counts toward \(sharedTarget ?? 750)", table: "HomeProto")
        }
    }

    func hoursLine(_ r: HomeProtoRental) -> String {
        let whole = Int(r.hours.rounded(.down))
        if case .own(let t) = r.target { return String(localized: "\(whole) of \(t)", table: "HomeProto") }
        return String(localized: "\(whole)h", table: "HomeProto")
    }

    /// "12 of 100 hours, 100-hour target" for VoiceOver.
    func spoken(_ r: HomeProtoRental) -> String {
        let whole = Int(r.hours.rounded(.down))
        switch r.target {
        case .own(let t): return String(localized: "\(r.name), \(whole) of \(t) hours, has its own target", table: "HomeProto")
        case .record(let reason): return String(localized: "\(r.name), \(whole) hours, record only. \(reason)", table: "HomeProto")
        case .counts: return String(localized: "\(r.name), \(whole) hours, counts toward the shared total", table: "HomeProto")
        }
    }
}

/// The ONE stage function. The hero and every tile ask it, so a rental never shows one house
/// in the hero and another in its tile. A rental with its own target builds on ITS OWN scale
/// (100 of 100 hours is the roof, like 500 of 500); a record-only or shared rental is a plain lot.
enum HomeProtoStage {
    static func hours(for r: HomeProtoRental) -> Double {
        guard case .own(let t) = r.target, t > 0 else { return 0 }
        return min(r.hours / Double(t) * 500, 500)
    }
    /// The same house after a target change: the rental's hours on the new target's scale.
    static func hours(for r: HomeProtoRental, target t: Int) -> Double {
        guard t > 0, r.hasOwnTarget || t > 0 else { return 0 }
        return min(r.hours / Double(t) * 500, 500)
    }
    static func keyframe(hours: Double) -> HouseKeyframe { HouseProgress.keyframe(for: hours) }
    static func keyframe(for r: HomeProtoRental) -> HouseKeyframe { keyframe(hours: hours(for: r)) }
}
#endif

#if DEBUG
// MARK: - Words for the See-all list and the tiles

extension HomeProtoSeed {
    func tileHours(_ r: HomeProtoRental) -> String {
        let whole = Int(r.hours.rounded(.down))
        if case .own(let t) = r.target {
            return r.hours >= Double(t) ? String(localized: "\(whole)h ✓", table: "HomeProto")
                                        : String(localized: "\(whole) of \(t)", table: "HomeProto")
        }
        return String(localized: "\(whole)h", table: "HomeProto")
    }

    func tilePlan(_ r: HomeProtoRental) -> String {
        switch r.target {
        case .own(let t): return String(localized: "\(t)-hour target", table: "HomeProto")
        case .record: return String(localized: "Record", table: "HomeProto")
        case .counts: return String(localized: "Counts toward \(sharedTarget ?? 750)", table: "HomeProto")
        }
    }

    /// The second line of a See-all row.
    func planLine(_ r: HomeProtoRental) -> String {
        switch r.target {
        case .own(let t):
            let base = String(localized: "\(t)-hour target", table: "HomeProto")
            if r.pace == .done, let month = r.reached { return String(localized: "\(base) · reached in \(month)", table: "HomeProto") }
            if r.pace == .behind, let n = r.weeklyNeed { return String(localized: "\(base) · \(n)h a week to finish", table: "HomeProto") }
            return base
        case .record(let reason):
            return reason.hasPrefix("Long") ? String(localized: "Long stays · no target", table: "HomeProto")
                                            : String(localized: "Record only", table: "HomeProto")
        case .counts:
            return String(localized: "Counts toward \(sharedTarget ?? 750)", table: "HomeProto")
        }
    }

    enum Section: CaseIterable { case needsAttention, onPace, done, recordOnly, counts }

    func section(_ r: HomeProtoRental) -> Section {
        switch r.target {
        case .counts: return .counts
        case .record: return .recordOnly
        case .own: return r.pace == .behind ? .needsAttention : (r.pace == .done ? .done : .onPace)
        }
    }

    func rentals(in s: Section) -> [HomeProtoRental] {
        let list = rentals.filter { section($0) == s }
        func pct(_ r: HomeProtoRental) -> Double { if case .own(let t) = r.target { return r.hours / Double(t) }; return 0 }
        switch s {
        case .needsAttention: return list.sorted { ($0.weeklyNeed ?? 0) > ($1.weeklyNeed ?? 0) }
        case .onPace: return list.sorted { pct($0) > pct($1) }
        case .done, .recordOnly, .counts: return list.sorted { $0.hours > $1.hours }
        }
    }

    var behindCount: Int { rentals.filter { section($0) == .needsAttention }.count }
    var onPaceCount: Int { rentals.filter { [.onPace, .done].contains(section($0)) }.count }
}

enum HomeProtoPaceStyle {
    /// caution when behind, positive when on pace or done, action when pace is not known.
    static func color(_ r: HomeProtoRental, _ colors: AdaptiveColors) -> Color {
        switch r.pace {
        case .behind: return colors.caution
        case .onPace, .done: return colors.positive
        case nil: return colors.action
        }
    }
}
#endif
