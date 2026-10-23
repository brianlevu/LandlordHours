import Foundation

// MARK: - Today with several rentals (2.1, option E): the rules, pure and unit-tested
//
// The hero shows ONE focus: "All rentals" (a shared total or a record) or one rental. Under the
// hero, a row of tiles lets the owner change it. Everything Today draws for the focus (number,
// eyebrow, flag, stage, pace) comes from `HomeHero.make`, and every house (the hero and each
// tile) comes from `HomeStage`, so a rental never shows one house in the hero and another in
// its tile. The views only draw what these return.
//
// Spec: AgentScratch/landlordhours/2026-10-23/home-options/options.md (option E).

/// The one stage function for Today (hero and tiles). It reads `RentalStage` for a rental:
///  - "All rentals" builds with the total, unpinned;
///  - a rental with its own target builds with its hours, pinned at the 500 line;
///  - a record-only rental, and a rental's part of a shared total, is a plain lot.
enum HomeStage {
    static func hours(track: RentalTrack, hours: Double, isAll: Bool) -> Double {
        if isAll { return RentalStage.hours(track: .sharedTotal(hours: 0), hours: hours) }
        if track.isShared { return 0 }
        return RentalStage.hours(track: track, hours: hours)
    }

    static func keyframe(track: RentalTrack, hours: Double, isAll: Bool) -> HouseKeyframe {
        HouseProgress.keyframe(for: Self.hours(track: track, hours: hours, isAll: isAll))
    }
}

/// One tile in the row: "All rentals" or one rental.
struct HomeRentalTile: Identifiable, Equatable {
    let focus: TodayFocusChoice
    let name: String
    /// The rental's own hours (counted the way its plan counts them), or the total for "All rentals".
    let hours: Double
    /// The rental's plan. For "All rentals": the shared total (or a record, with no target).
    let track: RentalTrack

    var id: TodayFocusChoice { focus }
    var isAll: Bool { focus == .all }
    var propertyId: UUID? { if case .rental(let id) = focus { return id }; return nil }
    var wholeHours: Int { Int((hours.isFinite ? max(0, hours) : 0).rounded(.down)) }

    var stageHours: Double { HomeStage.hours(track: track, hours: hours, isAll: isAll) }
    var keyframe: HouseKeyframe { HomeStage.keyframe(track: track, hours: hours, isAll: isAll) }

    /// Progress toward the tile's own target; nil when it has none (no bar is drawn).
    var fraction: Double? {
        switch track {
        case .ownTarget(let t): return t > 0 ? min(1, max(0, hours / Double(t))) : nil
        case .sharedTotal(let t): return isAll && t > 0 ? min(1, max(0, hours / Double(t))) : nil
        case .recordOnly: return nil
        }
    }

    /// "12 of 100", or "84h" when the tile has no target of its own.
    var hoursLine: String {
        switch track {
        case .ownTarget(let t): return String(localized: "\(wholeHours) of \(t)", table: "Home")
        case .sharedTotal(let t) where isAll: return String(localized: "\(wholeHours) of \(t)", table: "Home")
        default: return String(localized: "\(wholeHours)h", table: "Home")
        }
    }

    /// "100-hour target", "Record only", "Counts toward 750", "One shared total".
    var tileLine: String {
        if isAll {
            return track.isShared ? String(localized: "One shared total", table: "Home")
                                  : String(localized: "Hours kept, no target", table: "Home")
        }
        return RentalPlanWords.tileLine(track)
    }

    /// What VoiceOver says: "Santa Ray Ave, 12 of 100 hours, has its own target".
    var spoken: String {
        if isAll {
            if let t = track.targetHours, t > 0 {
                return String(localized: "All rentals, \(wholeHours) of \(t) hours, one shared total", table: "Home")
            }
            return String(localized: "All rentals, \(wholeHours) hours", table: "Home")
        }
        switch track {
        case .ownTarget(let t):
            return String(localized: "\(name), \(wholeHours) of \(t) hours, has its own target", table: "Home")
        case .recordOnly(let r):
            return String(localized: "\(name), \(wholeHours) hours, record only. \(RentalPlanWords.reason(r))", table: "Home")
        case .sharedTotal:
            return String(localized: "\(name), \(wholeHours) hours, counts toward the shared total", table: "Home")
        }
    }

    /// The spoken label with the selection state, for the tile button.
    func spoken(selected: Bool, picked: Bool = false) -> String {
        if picked { return String(localized: "\(spoken), added", table: "Home") }
        return selected ? String(localized: "\(spoken), selected", table: "Home") : spoken
    }
}

/// The row under the hero: every rental in the Properties list order, "All rentals" first when
/// the profile has one shared total or a record.
struct HomeRentals: Equatable {
    let mode: RentalPlanMode
    let tiles: [HomeRentalTile]

    /// From the live plans. `hours` is each rental's own count (`AppViewModel.rentalHours`);
    /// `totalHours` is the goal's countable total (Today's house before 2.1).
    static func make(properties: [RentalProperty], mode: RentalPlanMode, plans: [UUID: RentalPlan],
                     hours: (RentalProperty) -> Double, totalHours: Double) -> HomeRentals {
        var tiles: [HomeRentalTile] = []
        switch mode {
        case .shared(let h):
            tiles.append(HomeRentalTile(focus: .all, name: allRentalsName, hours: totalHours, track: .sharedTotal(hours: h)))
        case .record:
            tiles.append(HomeRentalTile(focus: .all, name: allRentalsName, hours: totalHours, track: .recordOnly(.goalIsRecord)))
        case .perRental:
            break
        }
        for p in properties {
            let track = plans[p.id]?.track ?? .recordOnly(.longStays)
            tiles.append(HomeRentalTile(focus: .rental(p.id), name: p.name, hours: hours(p), track: track))
        }
        return HomeRentals(mode: mode, tiles: tiles)
    }

    static var allRentalsName: String { String(localized: "All rentals", table: "Home") }

    var rentalTiles: [HomeRentalTile] { tiles.filter { !$0.isAll } }
    var rentalCount: Int { rentalTiles.count }
    /// One rental: Today is 2.0.1, no row.
    var showsRow: Bool { rentalCount >= 2 }
    /// Six or more rentals: a "See all" tile opens the grid.
    var showsSeeAll: Bool { rentalCount >= 6 }
    /// "96h logged this year": every rental's own hours, added.
    var loggedHours: Double { rentalTiles.reduce(0) { $0 + max(0, $1.hours) } }

    var order: [TodayFocusChoice] { tiles.map(\.focus) }

    func tile(_ focus: TodayFocusChoice) -> HomeRentalTile? { tiles.first { $0.focus == focus } }

    /// The swipe on the hero: the next or previous tile, nil at either end.
    func step(from focus: TodayFocusChoice, by delta: Int) -> TodayFocusChoice? {
        guard let i = order.firstIndex(of: focus), order.indices.contains(i + delta) else { return nil }
        return order[i + delta]
    }

    /// The nth tile (DEBUG `-LHHomeFocus n`), clamped to the row.
    func focus(at index: Int) -> TodayFocusChoice? {
        order.isEmpty ? nil : order[min(max(0, index), order.count - 1)]
    }

    /// "Santa Ray Ave + Delaney Ct", "A + B + 2 more".
    static func names(_ picked: [HomeRentalTile]) -> String {
        switch picked.count {
        case 0: return ""
        case 1: return picked[0].name
        case 2: return String(localized: "\(picked[0].name) + \(picked[1].name)", table: "Home")
        default: return String(localized: "\(picked[0].name) + \(picked[1].name) + \(picked.count - 2) more", table: "Home")
        }
    }
}

// MARK: - Tapping tiles: focus, or "Add up rentals"

/// What the row is doing: focusing one tile, or adding rentals up. Tapping a tile while adding
/// up picks or unpicks it; "All rentals" leaves adding up and focuses the total.
struct HomeSelection: Equatable {
    var summing = false
    /// Picked rentals in tap order.
    var summed: [UUID] = []

    enum Effect: Equatable {
        /// Set Today's focus (persisted).
        case focus(TodayFocusChoice)
        /// Only the picked set changed.
        case picked
    }

    mutating func tap(_ tile: TodayFocusChoice) -> Effect {
        switch tile {
        case .all:
            summing = false; summed = []
            return .focus(.all)
        case .rental(let id):
            guard summing else { return .focus(tile) }
            if let i = summed.firstIndex(of: id) { summed.remove(at: i) } else { summed.append(id) }
            return .picked
        }
    }

    /// "Add up rentals" / "Done". Starting picks the focused rental first.
    mutating func toggleSum(focus: TodayFocusChoice) {
        if summing { summing = false; summed = []; return }
        summing = true
        if case .rental(let id) = focus { summed = [id] } else { summed = [] }
    }

    /// The rentals the hero adds up (two or more), else empty.
    var sumIds: [UUID] { summing && summed.count >= 2 ? summed : [] }

    func isPicked(_ tile: TodayFocusChoice) -> Bool {
        if summing, case .rental(let id) = tile { return summed.contains(id) }
        return false
    }

    /// The ring: the focused tile, or every picked tile while adding up.
    func isSelected(_ tile: TodayFocusChoice, focus: TodayFocusChoice) -> Bool {
        summing ? isPicked(tile) : tile == focus
    }

    /// Only the focused tile draws the full house (none while adding up).
    func showsFullHouse(_ tile: TodayFocusChoice, focus: TodayFocusChoice) -> Bool { !summing && tile == focus }
}

// MARK: - The hero for the focus

/// Everything the hero card draws for the focus.
struct HomeHeroState: Equatable {
    enum Kind: Equatable {
        /// The goal's total (2.0.1's hero): "All rentals", or the only rental.
        case total
        case ownTarget(UUID)
        case recordOnly(UUID)
        /// One rental's part of the shared total.
        case sharedPart(UUID)
        /// Rentals added up: the sum and the names, no target.
        case sum([UUID])
    }

    let kind: Kind
    /// Changes when the hero should cross-fade (a new focus).
    let key: String
    let copy: TodayHeroCopy
    /// The goal the house and pace measure against.
    let goal: HouseGoal
    /// The number.
    let hours: Double
    /// The house (from `HomeStage`).
    let stageHours: Double
    /// Replaces the stage name when nothing is being built ("Hours kept, no target").
    let stageTitle: String?
    /// The words on the flag; nil: no flag.
    let flag: String?
    /// The rental the 100-hour "did anyone do more?" question is about; nil: the grouped activity.
    let participationPropertyId: UUID?

    /// Pace cards follow the hero only when it has a target.
    var hasTarget: Bool { copy.targetHours != nil }
    var isTotal: Bool { kind == .total }
}

enum HomeHero {
    struct Input {
        var year: Int
        var now: Date
        var daysOfData: Int = .max
        var hasPendingToConfirm = false
        /// This year's "did anyone do more?" answer for a rental (nil id: the grouped activity).
        var answer: (UUID?) -> Bool? = { _ in nil }
        /// The total hero (2.0.1's words, hours and goal).
        var totalCopy: TodayHeroCopy
        var totalHours: Double
        var totalGoal: HouseGoal
        /// The flag on the total hero; nil: none.
        var totalFlag: String?
    }

    /// The hero for the focus, or for the rentals added up when two or more are picked.
    static func make(_ rentals: HomeRentals, focus: TodayFocusChoice, summed: [UUID] = [], _ i: Input) -> HomeHeroState {
        let picked = summed.compactMap { id in rentals.tile(.rental(id)) }
        if picked.count >= 2 { return sum(picked, i) }
        guard case .rental = focus, let tile = rentals.tile(focus), let id = tile.propertyId else { return total(rentals, i) }
        let yearText = String(i.year)
        switch tile.track {
        case .ownTarget(let target):
            let goal = RentalTrack.houseGoal(forHours: target)
            let copy = TodayHeroCopy.make(.init(
                goal: goal, hours: tile.hours, year: i.year, now: i.now,
                noOneParticipatedMore: i.answer(id), propertyName: tile.name,
                daysOfData: i.daysOfData, hasPendingToConfirm: i.hasPendingToConfirm))
            return HomeHeroState(kind: .ownTarget(id), key: "own-\(id)", copy: copy, goal: goal, hours: tile.hours,
                                 stageHours: tile.stageHours, stageTitle: nil, flag: tile.name, participationPropertyId: id)
        case .recordOnly(let reason):
            let tag = String(localized: "Record only", table: "Home")
            let copy = TodayHeroCopy(
                eyebrow: String(localized: "\(yearText) · \(tile.name) · \(tag)", table: "Home"),
                eyebrowYear: yearText, eyebrowTarget: tag, propertyName: tile.name, targetHours: nil,
                qualifier: RentalPlanWords.reason(reason),
                caption: String(localized: "hours logged in \(yearText)", table: "Home"),
                phrase: nil, tone: .neutral, needsConfirmation: false, claimsReached: false)
            return HomeHeroState(kind: .recordOnly(id), key: "record-\(id)", copy: copy, goal: .mp500, hours: tile.hours,
                                 stageHours: tile.stageHours, stageTitle: RentalPlanWords.hoursKept, flag: tile.name,
                                 participationPropertyId: nil)
        case .sharedTotal(let shared):
            let tag = String(localized: "Counts toward \(shared)", table: "Home")
            let total = Int(i.totalHours.rounded(.down))
            let copy = TodayHeroCopy(
                eyebrow: String(localized: "\(yearText) · \(tile.name) · \(tag)", table: "Home"),
                eyebrowYear: yearText, eyebrowTarget: tag, propertyName: tile.name, targetHours: nil,
                qualifier: nil,
                caption: String(localized: "hours at this rental", table: "Home"),
                phrase: String(localized: "\(total) of \(shared) in all", table: "Home"),
                tone: .neutral, needsConfirmation: false, claimsReached: false)
            return HomeHeroState(kind: .sharedPart(id), key: "part-\(id)", copy: copy, goal: .mp500, hours: tile.hours,
                                 stageHours: tile.stageHours,
                                 stageTitle: String(localized: "Counts toward the shared total", table: "Home"),
                                 flag: tile.name, participationPropertyId: nil)
        }
    }

    private static func total(_ rentals: HomeRentals, _ i: Input) -> HomeHeroState {
        let stage = HomeStage.hours(track: .sharedTotal(hours: Int(i.totalGoal.targetHours)), hours: i.totalHours, isAll: true)
        return HomeHeroState(kind: .total, key: "total", copy: i.totalCopy, goal: i.totalGoal, hours: i.totalHours,
                             stageHours: stage, stageTitle: nil, flag: i.totalFlag, participationPropertyId: nil)
    }

    private static func sum(_ picked: [HomeRentalTile], _ i: Input) -> HomeHeroState {
        let yearText = String(i.year)
        let total = picked.reduce(0) { $0 + max(0, $1.hours) }
        let tag = String(localized: "Added up", table: "Home")
        let copy = TodayHeroCopy(
            eyebrow: String(localized: "\(yearText) · \(tag)", table: "Home"),
            eyebrowYear: yearText, eyebrowTarget: tag, propertyName: nil, targetHours: nil,
            qualifier: nil,
            caption: String(localized: "hours combined", table: "Home"),
            phrase: HomeRentals.names(picked), tone: .neutral, needsConfirmation: false, claimsReached: false)
        let ids = picked.compactMap(\.propertyId)
        return HomeHeroState(kind: .sum(ids), key: "sum-" + ids.map(\.uuidString).joined(separator: "-"), copy: copy,
                             goal: .mp500, hours: total, stageHours: 0,
                             stageTitle: String(localized: "Added up, no target", table: "Home"),
                             flag: String(localized: "\(picked.count) rentals", table: "Home"),
                             participationPropertyId: nil)
    }

    /// The line under Today's title for the focus: "12h toward 100 at Santa Ray Ave.",
    /// "84h logged at Delaney Ct this year.", "96h across 2 rentals."; nil: the total's line.
    static func headerLine(_ hero: HomeHeroState) -> String? {
        let hours = OnbFormat.hours(hero.hours)
        switch hero.kind {
        case .ownTarget:
            guard let target = hero.copy.targetHours, let name = hero.copy.propertyName else { return nil }
            return String(localized: "\(hours) toward \(target) at \(name).", table: "Home")
        case .recordOnly:
            guard let name = hero.copy.propertyName else { return nil }
            return String(localized: "\(hours) logged at \(name) this year.", table: "Home")
        case .sum(let ids):
            return String(localized: "\(hours) across \(ids.count) rentals.", table: "Home")
        case .total, .sharedPart:
            return nil
        }
    }
}

// MARK: - Layout

enum HomeLayout {
    /// Tile width so the last visible tile is always cut by the screen edge (it peeks), never
    /// exactly aligned: about 3.4 tiles across the row's width.
    static func tileWidth(rowWidth: CGFloat, spacing: CGFloat = 10) -> CGFloat {
        let w = max(rowWidth, 200)
        let raw = (w - 3 * spacing) / 3.4
        return min(max(raw, 96), 132).rounded(.down)
    }

    /// At accessibility text sizes the row becomes a vertical list: up to three rows, then "See all".
    static let listLimit = 3

    static func usesList(isAccessibilitySize: Bool) -> Bool { isAccessibilitySize }
}

#if DEBUG
// MARK: - DEBUG launch hooks (compiled out of Release)
//
//   -LHHomeFocus <n>          focus the nth tile (0 = the first tile, "All rentals" when present)
//   -LHHomeSum <name>,<name>  start in "Add up" mode with these rentals picked by name
//   -LHHomeSheet grid         open "See all" at launch
//   -LHHomeAutoplay           a scripted tour for a video (rentals, Add up, See all)
enum HomeDebugLaunch {
    private static var args: [String] { ProcessInfo.processInfo.arguments }
    private static func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
    static var focusIndex: Int? { value("-LHHomeFocus").flatMap(Int.init) }
    static var sumNames: [String] {
        (value("-LHHomeSum") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    static var opensGrid: Bool { value("-LHHomeSheet") == "grid" }
    static var autoplay: Bool { args.contains("-LHHomeAutoplay") }
}
#endif
