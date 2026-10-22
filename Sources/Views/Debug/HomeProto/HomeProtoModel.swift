import SwiftUI

#if DEBUG
// MARK: - Home-screen prototypes (throwaway, DEBUG only)
//
//   -LHHomeProto E|A|B|goalcheck      which screen
//   -LHHomeSeed brian|reps750|eight   which sample owner
//   -LHHomeFocus <n>                  start with item n focused (E/A/B)
//   -LHHomeStep inbox|check|diff      goalcheck: the Inbox card, the questions, or scrolled to the diff
//
// Spec: AgentScratch/landlordhours/2026-10-23/home-options/options.md. Nothing here ships:
// the real HouseHeroCard, PropertyHouseTile and tokens are reused, never redrawn.

struct HomeProtoLaunch {
    enum Screen: String { case e = "E", a = "A", b = "B", goalcheck }
    enum Step: String { case inbox, check, diff }

    let screen: Screen
    let seed: HomeProtoSeed
    let focusIndex: Int
    let step: Step

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
            step: Step(rawValue: value("-LHHomeStep") ?? "") ?? .check)
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

    var isRecord: Bool { if case .record = target { return true }; return false }

    /// The mini-house stage hours: the rental's house completes at its own target, pinned at 500.
    var houseHours: Double {
        if case .own(100) = target { return min(hours * 5, 500) }
        return hours
    }
}

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
                HomeProtoRental(id: "tahoe", name: "Tahoe Cabin", shortStay: true, hours: 64, target: .own(100)),
                HomeProtoRental(id: "lake", name: "Lake House", shortStay: true, hours: 112, target: .own(100)),
                HomeProtoRental(id: "palm", name: "Palm Studio", shortStay: true, hours: 230, target: .own(500)),
                HomeProtoRental(id: "birch", name: "Birch Flat", shortStay: true, hours: 310, target: .own(500)),
                HomeProtoRental(id: "maple", name: "Maple Duplex", shortStay: false, hours: 140, target: .own(500)),
                HomeProtoRental(id: "oak", name: "Oak Street", shortStay: false, hours: 40, target: .record(reason: manager)),
                HomeProtoRental(id: "cedar", name: "Cedar Row", shortStay: false, hours: 22, target: .record(reason: longStay)),
                HomeProtoRental(id: "pine", name: "Pine Court", shortStay: false, hours: 0, target: .record(reason: manager)),
            ], sharedTarget: nil)
        default:
            return HomeProtoSeed(id: "brian", rentals: [
                HomeProtoRental(id: "santa", name: "Santa Ray Ave", shortStay: true, hours: 12, target: .own(100)),
                HomeProtoRental(id: "delaney", name: "Delaney Ct", shortStay: false, hours: 84,
                                target: .record(reason: String(localized: "A manager does most of the work here", table: "HomeProto"))),
                HomeProtoRental(id: "yeandle", name: "Yeandle Ave", shortStay: false, hours: 0,
                                target: .record(reason: String(localized: "Long stays have no target under your goal", table: "HomeProto"))),
            ], sharedTarget: nil)
        }
    }

    // MARK: Hero model

    struct Hero {
        let progress: HouseProgress
        let copy: TodayHeroCopy
        let flag: String
    }

    static let now: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 12)) ?? Date()

    func hero(_ focus: HomeProtoFocus) -> Hero {
        let year = 2026
        let yearText = String(year)
        switch focus {
        case .all:
            let goal: HouseGoal = .reps750
            let copy = TodayHeroCopy.make(.init(goal: goal, hours: totalHours, year: year, now: Self.now, daysOfData: 200))
            return Hero(progress: HouseProgress(hours: totalHours, goal: goal), copy: copy, flag: name(.all))
        case .rental(let id):
            guard let r = rental(id) else { return hero(.all) }
            switch r.target {
            case .own(let target):
                let goal: HouseGoal = target == 100 ? .mp100 : .mp500
                let copy = TodayHeroCopy.make(.init(goal: goal, hours: r.hours, year: year, now: Self.now,
                                                    propertyName: r.name, daysOfData: 200))
                return Hero(progress: HouseProgress(hours: r.hours, goal: goal), copy: copy, flag: r.name)
            case .record(let reason):
                let tag = String(localized: "Record only", table: "HomeProto")
                let copy = TodayHeroCopy(
                    eyebrow: String(localized: "\(yearText) · \(r.name) · \(tag)", table: "HomeProto"), eyebrowYear: yearText, eyebrowTarget: tag,
                    propertyName: r.name, targetHours: nil, qualifier: reason,
                    caption: String(localized: "hours logged in \(yearText)", table: "HomeProto"),
                    phrase: nil, tone: .neutral, needsConfirmation: false, claimsReached: false)
                return Hero(progress: HouseProgress(hours: r.hours, goal: .mp500), copy: copy, flag: r.name)
            case .counts:
                let shared = sharedTarget ?? 750
                let tag = String(localized: "Counts toward \(shared)", table: "HomeProto")
                let copy = TodayHeroCopy(
                    eyebrow: String(localized: "\(yearText) · \(r.name) · \(tag)", table: "HomeProto"), eyebrowYear: yearText, eyebrowTarget: tag,
                    propertyName: r.name, targetHours: nil, qualifier: nil,
                    caption: String(localized: "hours at this rental", table: "HomeProto"),
                    phrase: String(localized: "\(Int(totalHours)) of \(shared) in all", table: "HomeProto"),
                    tone: .neutral, needsConfirmation: false, claimsReached: false)
                return Hero(progress: HouseProgress(hours: r.hours, goal: .mp500), copy: copy, flag: r.name)
            }
        }
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
#endif
