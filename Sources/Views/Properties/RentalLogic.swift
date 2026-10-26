import Foundation

// MARK: - Rentals (v2, plan package F): the pure parts
//
// Everything the Rentals list, the rental page and the edit sheet compute, kept out of the views so
// every state is unit-tested:
//   - `RentalRowModel`: one list row (the 44pt house-only thumbnail, the stage in words, the hours).
//   - `RentalPageFigures`: the rental page's hero, number block, pace sentence and the two tiles.
//   - `RentalsText`: every user-facing string, from `Sources/Resources/Strings/Rentals.xcstrings`.
//   - `RentalHouseLook`: the §F.1 reservation (designed for, not built).
//
// The stage is the one stage function, `CraftStage.stage(hours:goal:)`, against the same goal Today
// uses for a rental's own page, so a rental's thumbnail, its page and its Today page always agree.
// "All rentals" never appears here as a house or a goal: the list title says "N rentals · Nh this
// year" (hours only), and a stage is only ever computed for one rental (§H.1 H10).

/// One row of the Rentals list (`LHRow.Browse` with the 44pt thumbnail, §1.4, §H.5).
struct RentalRowModel: Identifiable, Equatable {
    let id: UUID
    let name: String
    /// This rental's countable hours this year (`propertyCountableHours`).
    let hours: Double
    let stage: CraftStage
    /// Lit when hours were logged at this rental today (`TodayWindowState.loggedToday`).
    let lit: Bool
    let kind: PropertyType

    init(id: UUID, name: String, hours: Double, goal: Double, lit: Bool, kind: PropertyType) {
        self.id = id
        self.name = name
        self.hours = hours.isFinite ? max(0, hours) : 0
        self.stage = CraftStage.stage(hours: self.hours, goal: goal)
        self.lit = lit
        self.kind = kind
    }

    /// Whole hours, rounded down so a row never runs ahead of the records.
    var wholeHours: Int { Int(hours.rounded(.down)) }

    /// The trailing value: "212h" (whole hours; "0h", never "0m", for a rental with none yet).
    var value: String { RentalsText.wholeHours(wholeHours) }

    /// The meta line says the stage in words (identity is the thumbnail, §H.5): "Frame going up". One
    /// short phrase, so it never truncates at default ("Roof on, siding going up" is the longest);
    /// the kind of stay lives on the rental page.
    var meta: String { stage.spokenName }

    /// VoiceOver: "Pine Cabin, 212 hours, Frame going up, Long stays".
    var spoken: String {
        RentalsText.rowSpoken(name: name, hours: LHFormat.spokenHours(Double(wholeHours)),
                              stage: stage.spokenName, kind: RentalsText.kind(kind))
    }
}

/// The rental page's numbers: the medium hero, the number block, and the two stat tiles that left
/// Today (§H.8, plan row 11).
struct RentalPageFigures: Equatable {
    struct Input {
        var hours: Double
        var goal: Double
        var isRecord: Bool
        /// Countable hours this week and last week at this rental (Monday-first per the calendar).
        var thisWeek: Double
        var lastWeek: Double
        var year: Int
        var now: Date
        var calendar: Calendar = .current
        /// Days since this rental's first countable hour this year (pace waits for enough data).
        var daysOfData: Int
    }

    struct Tile: Equatable {
        let value: String
        let label: String
        var trend: LHTile.Stat.Trend? = nil
    }

    let stage: CraftStage
    let pace: TodayPaceSentence
    let weekTile: Tile
    let finishTile: Tile

    static func make(_ i: Input) -> RentalPageFigures {
        let hours = i.hours.isFinite ? max(0, i.hours) : 0
        let pace = pace(hours: hours, goal: i.goal, isRecord: i.isRecord, year: i.year, now: i.now,
                        calendar: i.calendar, daysOfData: i.daysOfData)
        return RentalPageFigures(
            stage: CraftStage.stage(hours: hours, goal: i.goal),
            pace: pace,
            weekTile: weekTile(thisWeek: i.thisWeek, lastWeek: i.lastWeek),
            finishTile: finishTile(hours: hours, goal: i.goal, isRecord: i.isRecord, year: i.year, now: i.now,
                                   calendar: i.calendar, paceReady: TodayHeroCopy.paceIsReady(hours: hours, daysOfData: i.daysOfData)))
    }

    /// Today's pace sentence for one rental (`TodayPaceSentence`, the same words as its Today page).
    static func pace(hours: Double, goal: Double, isRecord: Bool, year: Int, now: Date,
                     calendar: Calendar = .current, daysOfData: Int) -> TodayPaceSentence {
        TodayPaceSentence.make(.init(
            hours: hours, goal: goal, year: year, now: now, calendar: calendar, isRecord: isRecord,
            paceReady: TodayHeroCopy.paceIsReady(hours: hours, daysOfData: daysOfData)))
    }

    /// "6h · This week", with the trend against last week (none when both weeks are empty).
    static func weekTile(thisWeek: Double, lastWeek: Double) -> Tile {
        let this = thisWeek.isFinite ? max(0, thisWeek) : 0
        let last = lastWeek.isFinite ? max(0, lastWeek) : 0
        let trend: LHTile.Stat.Trend?
        if this == 0 && last == 0 {
            trend = nil
        } else if abs(this - last) < 0.25 {
            trend = .flat
        } else {
            trend = this > last ? .up : .down
        }
        return Tile(value: this == 0 ? RentalsText.wholeHours(0) : LHFormat.hours(this), label: RentalsText.thisWeek, trend: trend)
    }

    /// "9h a week · To finish by Dec 31"; "Reached" once the goal is met; "Not yet" while the pace
    /// waits for data; for "just keep a record", the days left in the year.
    static func finishTile(hours: Double, goal: Double, isRecord: Bool, year: Int, now: Date,
                           calendar: Calendar = .current, paceReady: Bool) -> Tile {
        if isRecord || goal <= 0 {
            let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? now
            let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: end).day ?? 0)
            return Tile(value: "\(days)", label: RentalsText.daysLeft(year))
        }
        if hours >= goal {
            return Tile(value: RentalsText.reached, label: RentalsText.goalHours(Int(goal.rounded())))
        }
        guard paceReady, hours > 0 else {
            return Tile(value: RentalsText.notYet, label: RentalsText.toFinish)
        }
        let weeks = TodayPaceCards.weeksLeft(now: now, calendar: calendar)
        let perWeek = max(1, Int((max(goal - hours, 0) / weeks).rounded(.up)))
        return Tile(value: RentalsText.perWeek(perWeek), label: RentalsText.toFinish)
    }
}

// MARK: - Week hours

enum RentalWeek {
    /// Countable hours in the week containing `now` and in the week before it.
    static func hours(entries: [TimeEntry], now: Date, calendar: Calendar = .current) -> (thisWeek: Double, lastWeek: Double) {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now),
              let lastStart = calendar.date(byAdding: .weekOfYear, value: -1, to: week.start) else { return (0, 0) }
        var this = 0.0, last = 0.0
        for entry in entries where entry.hours.isFinite && entry.hours > 0 {
            if week.contains(entry.date) {
                this += entry.hours
            } else if entry.date >= lastStart && entry.date < week.start {
                last += entry.hours
            }
        }
        return (this, last)
    }

    /// Whole days since the earliest entry this year (0 with none).
    static func daysOfData(entries: [TimeEntry], year: Int, now: Date, calendar: Calendar = .current) -> Int {
        guard let first = entries.filter({ calendar.component(.year, from: $0.date) == year }).map(\.date).min() else { return 0 }
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: now)).day ?? 0)
    }
}

// MARK: - §F.1 reservation: a house of their own (designed for, not built)

/// Per-rental house customisation (standard §F.1; plan backlog F1-0 … F1-g, package J later).
///
/// Reserved here, not built:
///   - one `LHRow.Value` "House" in the rental edit sheet and on the rental page's details, which
///     opens the swatch sheet (four swatch rows: roof, siding, trim, door; a live 300pt preview);
///   - the data, `RentalProperty.houseLook: HouseLook { roof, siding, trim, door, style }` (swatch
///     names, never hex; default `.standard`; synced with the rental), is F1-a and does not exist;
///   - the art: neutral base renders and `craft_slots_<stage>` mask packs live in `design/` only and
///     never in the bundle until §F.1 is built (`asset_check.py` FAILs on any `craft_slots_*`).
///
/// Nothing renders while `isBuilt` is false: the slots are `EmptyView`s that take no space. Building
/// §F.1 starts with the required spike (F1-0), not with flipping this flag.
enum RentalHouseLook {
    /// Off until F1-0 passes and F1-a … F1-d land. No setting, flag or launch argument turns it on.
    static let isBuilt = false
    /// The four slots §F.1 allows, in the swatch sheet's order. No more slots, ever (§F.1).
    static let slots = ["roof", "siding", "trim", "door"]
    /// The row's label when built ("House").
    static var rowLabel: String { String(localized: "rentals.houseLook.row", defaultValue: "House", table: "Rentals") }
}

// MARK: - Strings

/// Every user-facing string on the Rentals screens (`Rentals.xcstrings`). Canonical keys from §C.5
/// come from `Localizable`/`Shared`; nothing here restates them.
enum RentalsText {
    // List
    static var title: String { String(localized: "rentals.title", defaultValue: "Rentals", table: "Rentals") }
    static var addRental: String { String(localized: "rentals.add", defaultValue: "Add rental", table: "Rentals") }
    /// "3 rentals" / "1 rental" (plural variations in the catalog).
    static func count(_ n: Int) -> String {
        String(localized: "rentals.count", defaultValue: "\(n) rentals", table: "Rentals")
    }
    /// "212h".
    static func wholeHours(_ whole: Int) -> String {
        String(localized: "rentals.hoursWhole", defaultValue: "\(whole)h", table: "Rentals")
    }
    /// "212h this year".
    static func hoursThisYear(_ whole: Int) -> String {
        String(localized: "rentals.hoursThisYear", defaultValue: "\(whole)h this year", table: "Rentals")
    }
    /// The list subtitle: "3 rentals · 312h this year". Hours only: never a goal for all rentals (§H.1 H10).
    static func subtitle(count n: Int, wholeHours: Int) -> String {
        let c = count(n), h = hoursThisYear(wholeHours)
        return String(localized: "rentals.subtitle", defaultValue: "\(c) · \(h)", table: "Rentals")
    }
    /// The meta line from XXL, where the hours leave the trailing column: "Framing started · 40h".
    static func axMeta(stage: String, hours: String) -> String {
        String(localized: "rentals.row.metaAX", defaultValue: "\(stage) · \(hours)", table: "Rentals")
    }
    static func rowSpoken(name: String, hours: String, stage: String, kind: String) -> String {
        String(localized: "rentals.row.spoken", defaultValue: "\(name), \(hours), \(stage), \(kind)", table: "Rentals")
    }
    static func kind(_ type: PropertyType) -> String {
        type == .ltr
            ? String(localized: "rentals.kind.long", defaultValue: "Long stays", table: "Rentals")
            : String(localized: "rentals.kind.short", defaultValue: "A few nights", table: "Rentals")
    }
    static var searchPrompt: String { String(localized: "rentals.search", defaultValue: "Search rentals", table: "Rentals") }
    static func noMatch(_ query: String) -> String {
        String(localized: "rentals.search.none", defaultValue: "No rentals match “\(query)”.", table: "Rentals")
    }
    static var loading: String { String(localized: "rentals.loading", defaultValue: "Loading your rentals", table: "Rentals") }
    static var emptyHeadline: String { String(localized: "rentals.empty.headline", defaultValue: "Add your first rental", table: "Rentals") }
    static var emptyMessage: String {
        String(localized: "rentals.empty.message", defaultValue: "Your hours start here.", table: "Rentals")
    }
    static var nextRental: String { String(localized: "rentals.lock.next", defaultValue: "Your next rental", table: "Rentals") }
    static var open: String { String(localized: "rentals.menu.open", defaultValue: "Open", table: "Rentals") }
    static var edit: String { String(localized: "rentals.menu.edit", defaultValue: "Edit", table: "Rentals") }
    static var delete: String { String(localized: "rentals.menu.delete", defaultValue: "Delete", table: "Rentals") }
    static var keep: String { String(localized: "rentals.alert.keep", defaultValue: "Keep", table: "Rentals") }

    // Rental page
    static var thisWeek: String { String(localized: "rentals.tile.thisWeek", defaultValue: "This week", table: "Rentals") }
    static var toFinish: String { String(localized: "rentals.tile.toFinish", defaultValue: "To finish by Dec 31", table: "Rentals") }
    static var reached: String { String(localized: "rentals.tile.reached", defaultValue: "Reached", table: "Rentals") }
    static var notYet: String { String(localized: "rentals.tile.notYet", defaultValue: "Not yet", table: "Rentals") }
    static func perWeek(_ n: Int) -> String {
        String(localized: "rentals.tile.perWeek", defaultValue: "\(n)h a week", table: "Rentals")
    }
    static func goalHours(_ goal: Int) -> String {
        String(localized: "rentals.tile.goalHours", defaultValue: "\(goal) hours", table: "Rentals")
    }
    static func daysLeft(_ year: Int) -> String {
        let y = String(year)
        return String(localized: "rentals.tile.daysLeft", defaultValue: "Days left in \(y)", table: "Rentals")
    }
    static var recent: String { String(localized: "rentals.recent", defaultValue: "Recent", table: "Rentals") }
    static func seeAll(_ n: Int) -> String {
        String(localized: "rentals.recent.seeAll", defaultValue: "See all \(n)", table: "Rentals")
    }
    static var details: String { String(localized: "rentals.details", defaultValue: "Details", table: "Rentals") }
    static var address: String { String(localized: "rentals.details.address", defaultValue: "Address", table: "Rentals") }
    static var notAdded: String { String(localized: "rentals.details.notAdded", defaultValue: "Not added", table: "Rentals") }
    static var howGuestsStay: String { String(localized: "rentals.details.stay", defaultValue: "How guests stay", table: "Rentals") }
    static var otherNames: String { String(localized: "rentals.details.otherNames", defaultValue: "Other names", table: "Rentals") }
    static var none: String { String(localized: "rentals.details.none", defaultValue: "None", table: "Rentals") }
    static var liveHere: String { String(localized: "rentals.details.liveHere", defaultValue: "I live here", table: "Rentals") }
    static var yes: String { String(localized: "rentals.details.yes", defaultValue: "Yes", table: "Rentals") }
    static var no: String { String(localized: "rentals.details.no", defaultValue: "No", table: "Rentals") }
    static func mapOf(_ address: String) -> String {
        String(localized: "rentals.map.label", defaultValue: "Map of \(address)", table: "Rentals")
    }
    static var findingMap: String { String(localized: "rentals.map.finding", defaultValue: "Finding the address on the map", table: "Rentals") }
    static var mapNotFound: String {
        String(localized: "rentals.map.notFound", defaultValue: "We couldn’t find this address on the map.", table: "Rentals")
    }
    static func recordMeta(date: String, source: String) -> String {
        String(localized: "rentals.record.meta", defaultValue: "\(date) · \(source)", table: "Rentals")
    }

    // Edit sheet
    static var newRental: String { String(localized: "rentals.sheet.new", defaultValue: "New rental", table: "Rentals") }
    static var editRental: String { String(localized: "rentals.sheet.edit", defaultValue: "Edit rental", table: "Rentals") }
    static var name: String { String(localized: "rentals.field.name", defaultValue: "Name", table: "Rentals") }
    static var namePlaceholder: String { String(localized: "rentals.field.name.placeholder", defaultValue: "Pine Cabin", table: "Rentals") }
    static var addressPlaceholder: String {
        String(localized: "rentals.field.address.placeholder", defaultValue: "Street, city", table: "Rentals")
    }
    static var stayQuestion: String { String(localized: "rentals.stay.question", defaultValue: "How do guests stay?", table: "Rentals") }
    static var stayFootnote: String {
        String(localized: "rentals.stay.footnote", defaultValue: "This changes how hours count for this place.", table: "Rentals")
    }
    static var addAnotherName: String { String(localized: "rentals.alias.placeholder", defaultValue: "Add another name", table: "Rentals") }
    static var add: String { String(localized: "rentals.alias.add", defaultValue: "Add", table: "Rentals") }
    static func removeName(_ alias: String) -> String {
        String(localized: "rentals.alias.remove", defaultValue: "Remove \(alias)", table: "Rentals")
    }
    /// §C.5 line 7.
    static var otherNamesFootnote: String {
        String(localized: "rentals.alias.footnote",
               defaultValue: "What you call this place in your calendar, like “the cabin”. Up to 10 names, 3 letters or more.",
               table: "Rentals")
    }
    static var aliasTooShort: String { String(localized: "rentals.alias.short", defaultValue: "Use 3 letters or more.", table: "Rentals") }
    static var aliasFull: String { String(localized: "rentals.alias.full", defaultValue: "That’s 10 names, the most you can add.", table: "Rentals") }
    static var liveHereSubtitle: String {
        String(localized: "rentals.liveHere.subtitle", defaultValue: "We won’t suggest time spent at home as work.", table: "Rentals")
    }
    static var save: String { String(localized: "rentals.sheet.save", defaultValue: "Save", table: "Rentals") }
    static var deleteRental: String { String(localized: "rentals.sheet.delete", defaultValue: "Delete rental", table: "Rentals") }
    static var duplicateName: String {
        String(localized: "rentals.field.name.duplicate", defaultValue: "You already have a rental with this name. Pick another.", table: "Rentals")
    }

    // Delete alert (§1.21: title ≤ 6 words, ≤ 2 sentences, verbs)
    static var deleteTitle: String { String(localized: "rentals.delete.title", defaultValue: "Delete this rental?", table: "Rentals") }
    static func deleteMessage(name: String, hours: String?) -> String {
        if let hours {
            return String(localized: "rentals.delete.messageHours",
                          defaultValue: "\(name), its \(hours) of logged time and any photos go from this iPhone and iCloud. This can’t be undone.",
                          table: "Rentals")
        }
        return String(localized: "rentals.delete.message",
                      defaultValue: "\(name) goes from this iPhone and iCloud. This can’t be undone.", table: "Rentals")
    }
}
