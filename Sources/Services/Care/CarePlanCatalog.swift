import Foundation

// MARK: - Care plan A: the seasonal checklist (2.3, package B)
//
// A per-rental list of upkeep a well-run rental needs, grouped by season. It is picked for the
// rental's type (long stays or short stays) and its climate, read from the address's US state.
// Pure and unit-tested (`CarePlanTests`): no views, no storage. What was logged lives in
// `CareDoneLog`; the chips for how long live in `CareHourChips`.
//
// The guardrail (build plan B.6): nothing here suggests work in order to add hours. The plan says
// what a rental needs and when; the person logs it when it's done and sets the hours themselves.

/// The weather a rental's plan is picked for.
enum CareClimate: String, CaseIterable, Codable, Sendable {
    /// Cold winters with snow and hard freezes.
    case snowy
    /// Mild, rainy winters with the odd frost.
    case wet
    /// Hot, dry summers; little frost.
    case hotDry
    /// Hot, humid summers and storm seasons.
    case humid
    /// The address doesn't say: a plan that fits most places.
    case general

    /// "Snowy winters", or nil when the address doesn't say.
    var label: String? {
        switch self {
        case .snowy: return CareText.climateSnowy
        case .wet: return CareText.climateWet
        case .hotDry: return CareText.climateHotDry
        case .humid: return CareText.climateHumid
        case .general: return nil
        }
    }

    /// The climate for a rental's address: the US state it names (a 2-letter code after a comma, or
    /// the state's name). Anything else is `.general`.
    static func from(address: String) -> CareClimate {
        guard let state = USState.find(in: address) else { return .general }
        return byState[state] ?? .general
    }

    private static let byState: [String: CareClimate] = {
        var map: [String: CareClimate] = [:]
        for s in ["AK", "CO", "CT", "IA", "ID", "IL", "IN", "MA", "ME", "MI", "MN", "MT", "ND", "NE", "NH",
                  "NY", "OH", "PA", "RI", "SD", "UT", "VT", "WI", "WY", "WV"] { map[s] = .snowy }
        for s in ["CA", "OR", "WA", "DE", "DC", "KY", "MD", "MO", "NC", "NJ", "TN", "VA", "KS", "AR"] { map[s] = .wet }
        for s in ["AZ", "NV", "NM", "TX", "OK"] { map[s] = .hotDry }
        for s in ["FL", "LA", "MS", "AL", "GA", "SC", "HI", "PR"] { map[s] = .humid }
        return map
    }()
}

/// The four seasons, northern hemisphere, by meteorological months (Dec–Feb is winter).
enum CareSeason: Int, CaseIterable, Codable, Sendable {
    case winter, spring, summer, fall

    var label: String {
        switch self {
        case .winter: return CareText.seasonWinter
        case .spring: return CareText.seasonSpring
        case .summer: return CareText.seasonSummer
        case .fall: return CareText.seasonFall
        }
    }

    var next: CareSeason { CareSeason(rawValue: (rawValue + 1) % 4) ?? .winter }

    static func of(_ date: Date, calendar: Calendar = .current) -> CareSeason {
        switch calendar.component(.month, from: date) {
        case 12, 1, 2: return .winter
        case 3, 4, 5: return .spring
        case 6, 7, 8: return .summer
        default: return .fall
        }
    }

    /// When the season that holds `date` began (Dec 1, Mar 1, Jun 1 or Sep 1, at midnight).
    static func start(of date: Date, calendar: Calendar = .current) -> Date {
        let month = calendar.component(.month, from: date)
        var year = calendar.component(.year, from: date)
        let startMonth: Int
        switch month {
        case 12: startMonth = 12
        case 1, 2: startMonth = 12; year -= 1
        case 3, 4, 5: startMonth = 3
        case 6, 7, 8: startMonth = 6
        default: startMonth = 9
        }
        return calendar.date(from: DateComponents(year: year, month: startMonth, day: 1)) ?? calendar.startOfDay(for: date)
    }
}

/// When a task comes round: once in a season, or on every stay (short stays only).
enum CareTiming: Equatable, Sendable {
    case seasons(Set<CareSeason>)
    case everyStay
}

/// One thing a rental needs.
struct CareTask: Identifiable, Equatable, Sendable {
    /// Stable id (stored in `CareDoneLog`; never shown).
    let id: String
    let timing: CareTiming
    /// Nil: every climate.
    let climates: Set<CareClimate>?
    /// Nil: both rental types.
    let types: Set<PropertyType>?
    /// The SF Symbol in the row's 36pt tile.
    let symbol: String
    /// What Log time fills in as the kind of work.
    let kind: ActivityCategory
    /// The meta line names a cadence ("Once a year"), so the current season adds "due now".
    let isCadence: Bool

    func applies(to type: PropertyType, climate: CareClimate) -> Bool {
        (types?.contains(type) ?? true) && (climates?.contains(climate) ?? true)
    }

    func inSeason(_ season: CareSeason) -> Bool {
        if case .seasons(let set) = timing { return set.contains(season) }
        return false
    }

    var title: String { CareText.title(id) }
    /// What Log time's note starts with ("Cleared the gutters").
    var doneNote: String { CareText.doneNote(id) }
    /// The meta line for a rental type ("Twice a year", "Between stays").
    func when(for type: PropertyType) -> String { CareText.when(id, type: type) }
}

/// The catalog. Order is the order rows appear in, most timely first within a season.
enum CarePlanCatalog {
    private static let cold: Set<CareClimate> = [.snowy]
    private static let rainy: Set<CareClimate> = [.wet, .general]
    private static let mildWinters: Set<CareClimate> = [.wet, .general, .humid, .hotDry]
    private static let hot: Set<CareClimate> = [.hotDry, .humid]

    static let tasks: [CareTask] = [
        // Fall
        CareTask(id: "gutters", timing: .seasons([.fall]), climates: [.wet, .general, .humid], types: nil,
                 symbol: "cloud.rain", kind: .repairs, isCadence: false),
        CareTask(id: "iceMelt", timing: .seasons([.fall]), climates: cold, types: nil,
                 symbol: "snowflake", kind: .management, isCadence: false),
        CareTask(id: "hotTub", timing: .seasons([.fall]), climates: cold, types: [.str],
                 symbol: "thermometer.snowflake", kind: .repairs, isCadence: false),
        CareTask(id: "outdoorTaps", timing: .seasons([.fall]), climates: rainy, types: nil,
                 symbol: "spigot", kind: .repairs, isCadence: false),
        CareTask(id: "alarms", timing: .seasons([.fall, .spring]), climates: nil, types: nil,
                 symbol: "sensor", kind: .repairs, isCadence: true),
        CareTask(id: "furnaceFilter", timing: .seasons([.fall]), climates: [.wet, .general, .hotDry, .humid], types: nil,
                 symbol: "wind", kind: .repairs, isCadence: false),
        CareTask(id: "heatTape", timing: .seasons([.fall]), climates: cold, types: nil,
                 symbol: "bolt", kind: .repairs, isCadence: false),
        CareTask(id: "stormPrep", timing: .seasons([.summer]), climates: [.humid], types: nil,
                 symbol: "hurricane", kind: .repairs, isCadence: false),
        // Every stay (short stays)
        CareTask(id: "walkThrough", timing: .everyStay, climates: nil, types: [.str],
                 symbol: "figure.walk", kind: .management, isCadence: false),
        CareTask(id: "firstAid", timing: .everyStay, climates: nil, types: [.str],
                 symbol: "cross.case", kind: .management, isCadence: false),
        // Winter
        CareTask(id: "sinkLeaks", timing: .seasons([.winter]), climates: rainy, types: nil,
                 symbol: "pipe.and.drop", kind: .repairs, isCadence: false),
        CareTask(id: "roofSnow", timing: .seasons([.winter]), climates: cold, types: nil,
                 symbol: "house", kind: .repairs, isCadence: false),
        CareTask(id: "waterHeater", timing: .seasons([.winter]), climates: mildWinters, types: nil,
                 symbol: "flame", kind: .repairs, isCadence: true),
        CareTask(id: "furnaceService", timing: .seasons([.winter]), climates: cold, types: nil,
                 symbol: "flame", kind: .repairs, isCadence: true),
        CareTask(id: "atticDamp", timing: .seasons([.winter]), climates: [.wet, .humid], types: nil,
                 symbol: "house", kind: .repairs, isCadence: false),
        // Spring
        CareTask(id: "acService", timing: .seasons([.spring]), climates: hot, types: nil,
                 symbol: "air.conditioner.horizontal", kind: .repairs, isCadence: false),
        CareTask(id: "roofCheck", timing: .seasons([.spring]), climates: [.snowy, .general], types: nil,
                 symbol: "house", kind: .repairs, isCadence: false),
        CareTask(id: "dryerVent", timing: .seasons([.spring]), climates: nil, types: nil,
                 symbol: "fan", kind: .repairs, isCadence: true),
        CareTask(id: "reseal", timing: .seasons([.spring]), climates: nil, types: nil,
                 symbol: "bathtub", kind: .repairs, isCadence: false),
        // Summer
        CareTask(id: "irrigation", timing: .seasons([.summer]), climates: [.hotDry], types: nil,
                 symbol: "drop", kind: .repairs, isCadence: false),
        CareTask(id: "trimTrees", timing: .seasons([.summer]), climates: [.wet, .general, .snowy, .humid], types: nil,
                 symbol: "tree", kind: .repairs, isCadence: true),
        CareTask(id: "pests", timing: .seasons([.summer]), climates: nil, types: nil,
                 symbol: "ant", kind: .management, isCadence: true),
    ]

    static func task(id: String) -> CareTask? { tasks.first { $0.id == id } }
}

// MARK: - A rental's plan

/// One row: a task, its meta line, and what was logged for it this season.
struct CarePlanItem: Identifiable, Equatable {
    let task: CareTask
    /// "Before the rains", "Twice a year · due now", or "Logged 1h · Oct 4" once done.
    let meta: String
    /// The latest log of this task at this rental since the season began (nil: still to do).
    let done: CareLog?
    var id: String { task.id }
    var isDone: Bool { done != nil }
}

/// One group on the plan: "This season · Fall", "Between stays", "Winter".
struct CarePlanSection: Identifiable, Equatable {
    enum Kind: Equatable { case thisSeason(CareSeason), betweenStays, later(CareSeason) }
    let kind: Kind
    let items: [CarePlanItem]

    var id: String {
        switch kind {
        case .thisSeason(let s): return "now-\(s.rawValue)"
        case .betweenStays: return "stays"
        case .later(let s): return "later-\(s.rawValue)"
        }
    }

    var title: String {
        switch kind {
        case .thisSeason(let s): return CareText.thisSeason(s.label)
        case .betweenStays: return CareText.betweenStays
        case .later(let s): return s.label
        }
    }
}

struct CarePlan: Equatable {
    let rentalID: UUID
    let type: PropertyType
    let climate: CareClimate
    let season: CareSeason
    let sections: [CarePlanSection]

    /// "Long stays · Wet winters" (the climate is left off when the address doesn't say).
    var basis: String {
        let stays = type == .str ? CareText.shortStays : CareText.longStays
        guard let climate = climate.label else { return stays }
        // The dot stays at the end of a line when the subtitle wraps ("Long stays ·" / "Wet winters").
        return "\(stays)\u{00A0}\u{00B7} \(climate)"
    }

    /// "Picked for long stays in a place with wet winters. Log it when it's done. You set the hours."
    var footnote: String { CareText.footnote(type: type, climate: climate) }

    /// Today's three: this season's open items first (catalog order), then its done ones, so
    /// Today always shows what is next and never runs empty while the plan has rows.
    var todayItems: [CarePlanItem] {
        let now = sections.first?.items ?? []
        return Array((now.filter { !$0.isDone } + now.filter(\.isDone)).prefix(3))
    }

    /// The open items of this season (what a care nudge may name).
    var dueNow: [CarePlanItem] { (sections.first?.items ?? []).filter { !$0.isDone } }

    /// Builds a rental's plan for `now`: this season, then "Between stays" for short stays, then the
    /// next two seasons (the season just past is 9 months away and left off). Inside a season the
    /// done rows go last. A task already listed this season is not listed again in a later one.
    static func make(rental: RentalProperty, logs: [CareLog], now: Date, calendar: Calendar = .current,
                     climate override: CareClimate? = nil) -> CarePlan {
        let climate = override ?? CareClimate.from(address: rental.address)
        let season = CareSeason.of(now, calendar: calendar)
        let seasonStart = CareSeason.start(of: now, calendar: calendar)
        let fits = CarePlanCatalog.tasks.filter { $0.applies(to: rental.propertyType, climate: climate) }

        func item(_ task: CareTask, current: Bool) -> CarePlanItem {
            let done = current ? CareDoneLog.latest(task: task.id, rental: rental.id, since: seasonStart, in: logs) : nil
            let meta: String
            if let done {
                meta = CareText.logged(hours: done.hours, on: done.date, calendar: calendar)
            } else if current && task.isCadence {
                meta = CareText.dueNow(task.when(for: rental.propertyType))
            } else {
                meta = task.when(for: rental.propertyType)
            }
            return CarePlanItem(task: task, meta: meta, done: done)
        }

        var sections: [CarePlanSection] = []
        let current = fits.filter { $0.inSeason(season) }.map { item($0, current: true) }
        sections.append(CarePlanSection(kind: .thisSeason(season),
                                        items: current.filter { !$0.isDone } + current.filter(\.isDone)))
        let stays = fits.filter { $0.timing == .everyStay }
        if !stays.isEmpty {
            sections.append(CarePlanSection(kind: .betweenStays, items: stays.map { item($0, current: false) }))
        }
        // A task twice a year (the alarms) is listed once: in this season, not again further down.
        let shownNow = Set(current.map(\.id))
        var later = season.next
        for _ in 0..<2 {
            let items = fits.filter { $0.inSeason(later) && !shownNow.contains($0.id) }.map { item($0, current: false) }
            if !items.isEmpty { sections.append(CarePlanSection(kind: .later(later), items: items)) }
            later = later.next
        }
        return CarePlan(rentalID: rental.id, type: rental.propertyType, climate: climate, season: season, sections: sections)
    }
}

// MARK: - US states in an address

enum USState {
    static let codes: Set<String> = ["AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI", "ID", "IL",
                                     "IN", "IA", "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE",
                                     "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "PR", "RI", "SC",
                                     "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"]

    private static let names: [String: String] = [
        "alabama": "AL", "alaska": "AK", "arizona": "AZ", "arkansas": "AR", "california": "CA", "colorado": "CO",
        "connecticut": "CT", "delaware": "DE", "florida": "FL", "georgia": "GA", "hawaii": "HI", "idaho": "ID",
        "illinois": "IL", "indiana": "IN", "iowa": "IA", "kansas": "KS", "kentucky": "KY", "louisiana": "LA",
        "maine": "ME", "maryland": "MD", "massachusetts": "MA", "michigan": "MI", "minnesota": "MN",
        "mississippi": "MS", "missouri": "MO", "montana": "MT", "nebraska": "NE", "nevada": "NV",
        "new hampshire": "NH", "new jersey": "NJ", "new mexico": "NM", "new york": "NY", "north carolina": "NC",
        "north dakota": "ND", "ohio": "OH", "oklahoma": "OK", "oregon": "OR", "pennsylvania": "PA",
        "rhode island": "RI", "south carolina": "SC", "south dakota": "SD", "tennessee": "TN", "texas": "TX",
        "utah": "UT", "vermont": "VT", "virginia": "VA", "washington": "WA", "west virginia": "WV",
        "wisconsin": "WI", "wyoming": "WY", "puerto rico": "PR",
    ]

    /// The state an address names: a 2-letter code in a comma part ("…, Portland, OR 97201"), else a
    /// full name in one ("…, Oregon"). The street part (before the first comma) is never read, so
    /// "12 Oregon St" alone says nothing.
    static func find(in address: String) -> String? {
        let parts = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 2 else { return nil }
        for part in parts.dropFirst().reversed() {
            let words = part.split(whereSeparator: { $0 == " " }).map(String.init)
            if let code = words.first(where: { $0.count == 2 && $0 == $0.uppercased() && codes.contains($0) }) { return code }
            let lower = part.lowercased()
            // Longest names first so "west virginia" wins over "virginia".
            for name in names.keys.sorted(by: { $0.count > $1.count }) where lower.contains(name) {
                if name == "washington", lower.contains("washington dc") || lower.contains("washington, dc") { return "DC" }
                return names[name]
            }
        }
        return nil
    }
}

// MARK: - Words (String Catalog table `CarePlan`)

enum CareText {
    static let table = "CarePlan"

    /// A catalog string by key, with its English as the fallback.
    static func text(_ key: String, _ english: String) -> String {
        Bundle.main.localizedString(forKey: key, value: english, table: table)
    }

    // Seasons and climates
    static var seasonWinter: String { String(localized: "care.season.winter", defaultValue: "Winter", table: "CarePlan") }
    static var seasonSpring: String { String(localized: "care.season.spring", defaultValue: "Spring", table: "CarePlan") }
    static var seasonSummer: String { String(localized: "care.season.summer", defaultValue: "Summer", table: "CarePlan") }
    static var seasonFall: String { String(localized: "care.season.fall", defaultValue: "Fall", table: "CarePlan") }
    static var climateSnowy: String { String(localized: "care.climate.snowy", defaultValue: "Snowy winters", table: "CarePlan") }
    static var climateWet: String { String(localized: "care.climate.wet", defaultValue: "Wet winters", table: "CarePlan") }
    static var climateHotDry: String { String(localized: "care.climate.hotDry", defaultValue: "Hot, dry summers", table: "CarePlan") }
    static var climateHumid: String { String(localized: "care.climate.humid", defaultValue: "Humid summers", table: "CarePlan") }
    static var longStays: String { String(localized: "care.stays.long", defaultValue: "Long stays", table: "CarePlan") }
    static var shortStays: String { String(localized: "care.stays.short", defaultValue: "Short stays", table: "CarePlan") }

    // Sections and screens
    static func thisSeason(_ season: String) -> String {
        String(localized: "care.section.thisSeason", defaultValue: "This season · \(season)", table: "CarePlan")
    }
    static var betweenStays: String { String(localized: "care.section.betweenStays", defaultValue: "Between stays", table: "CarePlan") }
    static func todayTitle(_ rental: String) -> String {
        String(localized: "care.today.title", defaultValue: "This season · \(rental)", table: "CarePlan")
    }
    static var seePlan: String { String(localized: "care.today.seePlan", defaultValue: "See plan", table: "CarePlan") }
    static var rule: String { String(localized: "care.rule", defaultValue: "Log it when it’s done. You set the hours.", table: "CarePlan") }
    static var planTitle: String { String(localized: "care.plan.title", defaultValue: "Care plan", table: "CarePlan") }
    static var back: String { String(localized: "care.plan.back", defaultValue: "Back", table: "CarePlan") }
    static func planSubtitle(_ rental: String, _ basis: String) -> String {
        String(localized: "care.plan.subtitle", defaultValue: "\(rental)\u{00A0}· \(basis)", table: "CarePlan")
    }
    static var openHint: String { String(localized: "care.row.hint", defaultValue: "Opens Log time with this filled in", table: "CarePlan") }
    static var doneHint: String { String(localized: "care.row.doneHint", defaultValue: "Opens what you logged", table: "CarePlan") }
    static var lockLine: String { String(localized: "care.lock.line", defaultValue: "The care plan is part of Pro.", table: "CarePlan") }
    static var lockKeeps: String { String(localized: "care.lock.keeps", defaultValue: "Logging stays free.", table: "CarePlan") }

    static func footnote(type: PropertyType, climate: CareClimate) -> String {
        let picked: String
        switch (type, climate) {
        case (.ltr, .snowy): picked = String(localized: "care.picked.ltr.snowy", defaultValue: "Picked for long stays in a place with snowy winters.", table: "CarePlan")
        case (.ltr, .wet): picked = String(localized: "care.picked.ltr.wet", defaultValue: "Picked for long stays in a place with wet winters.", table: "CarePlan")
        case (.ltr, .hotDry): picked = String(localized: "care.picked.ltr.hotDry", defaultValue: "Picked for long stays in a place with hot, dry summers.", table: "CarePlan")
        case (.ltr, .humid): picked = String(localized: "care.picked.ltr.humid", defaultValue: "Picked for long stays in a place with humid summers.", table: "CarePlan")
        case (.ltr, .general): picked = String(localized: "care.picked.ltr.general", defaultValue: "Picked for long stays.", table: "CarePlan")
        case (.str, .snowy): picked = String(localized: "care.picked.str.snowy", defaultValue: "Picked for short stays in a place with snowy winters.", table: "CarePlan")
        case (.str, .wet): picked = String(localized: "care.picked.str.wet", defaultValue: "Picked for short stays in a place with wet winters.", table: "CarePlan")
        case (.str, .hotDry): picked = String(localized: "care.picked.str.hotDry", defaultValue: "Picked for short stays in a place with hot, dry summers.", table: "CarePlan")
        case (.str, .humid): picked = String(localized: "care.picked.str.humid", defaultValue: "Picked for short stays in a place with humid summers.", table: "CarePlan")
        case (.str, .general): picked = String(localized: "care.picked.str.general", defaultValue: "Picked for short stays.", table: "CarePlan")
        }
        return "\(picked) \(rule)"
    }

    // Meta lines
    static func dueNow(_ when: String) -> String {
        String(localized: "care.meta.dueNow", defaultValue: "\(when) · due now", table: "CarePlan")
    }

    /// "Logged 1h · Oct 4".
    static func logged(hours: Double, on date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        let day = formatter.string(from: date)
        return String(localized: "care.meta.logged", defaultValue: "Logged \(LHFormat.hours(hours)) · \(day)", table: "CarePlan")
    }

    // Chips
    static func lastTime(_ hours: String) -> String {
        String(localized: "care.chip.lastTime", defaultValue: "Last time \(hours)", table: "CarePlan")
    }
    static func typical(_ range: String) -> String {
        String(localized: "care.chip.typical", defaultValue: "Typical \(range)", table: "CarePlan")
    }
    static var setHowLong: String { String(localized: "care.log.setHowLong", defaultValue: "Set how long", table: "CarePlan") }
    static var chipsLabel: String { String(localized: "care.log.chipsLabel", defaultValue: "How long, from your own logs", table: "CarePlan") }

    // Tasks: title, the note Log time starts with, and the meta line
    private static let titles: [String: String] = [
        "gutters": "Clear the gutters",
        "iceMelt": "Stock ice melt and shovels",
        "hotTub": "Winterize the hot tub",
        "outdoorTaps": "Shut off the outdoor taps",
        "alarms": "Test smoke and CO alarms",
        "furnaceFilter": "Swap the furnace filter",
        "heatTape": "Check the heat tape on pipes",
        "stormPrep": "Get ready for storm season",
        "walkThrough": "Walk through after checkout",
        "firstAid": "Restock the first aid kit",
        "sinkLeaks": "Check under sinks for leaks",
        "roofSnow": "Clear snow from the roof edge",
        "waterHeater": "Service the water heater",
        "furnaceService": "Service the furnace",
        "atticDamp": "Look in the attic for damp",
        "acService": "Service the air conditioning",
        "roofCheck": "Check the roof after winter",
        "dryerVent": "Clean the dryer vent",
        "reseal": "Reseal the tub and windows",
        "irrigation": "Check the sprinklers for leaks",
        "trimTrees": "Trim branches off the roof",
        "pests": "Look for signs of pests",
    ]

    private static let notes: [String: String] = [
        "gutters": "Cleared the gutters",
        "iceMelt": "Stocked ice melt and shovels",
        "hotTub": "Winterized the hot tub",
        "outdoorTaps": "Shut off the outdoor taps",
        "alarms": "Tested the smoke and CO alarms",
        "furnaceFilter": "Swapped the furnace filter",
        "heatTape": "Checked the heat tape on the pipes",
        "stormPrep": "Got ready for storm season",
        "walkThrough": "Walked through after checkout",
        "firstAid": "Restocked the first aid kit",
        "sinkLeaks": "Checked under the sinks for leaks",
        "roofSnow": "Cleared snow from the roof edge",
        "waterHeater": "Serviced the water heater",
        "furnaceService": "Serviced the furnace",
        "atticDamp": "Checked the attic for damp",
        "acService": "Serviced the air conditioning",
        "roofCheck": "Checked the roof after winter",
        "dryerVent": "Cleaned the dryer vent",
        "reseal": "Resealed the tub and windows",
        "irrigation": "Checked the sprinklers for leaks",
        "trimTrees": "Trimmed branches off the roof",
        "pests": "Looked for signs of pests",
    ]

    /// The meta line; a short-stay variant where the timing differs ("Between stays").
    private static let whens: [String: String] = [
        "gutters": "Before the rains",
        "iceMelt": "Before the first snow",
        "hotTub": "When guests stop using it",
        "outdoorTaps": "Before the first frost",
        "alarms": "Twice a year",
        "alarms.str": "Between stays",
        "furnaceFilter": "Before the heat goes on",
        "heatTape": "Before the first freeze",
        "stormPrep": "Before the storms",
        "walkThrough": "Every stay",
        "firstAid": "Every few stays",
        "sinkLeaks": "After a hard freeze",
        "roofSnow": "After heavy snow",
        "waterHeater": "Once a year",
        "furnaceService": "Once a year",
        "atticDamp": "After a big storm",
        "acService": "Before the heat",
        "roofCheck": "After the thaw",
        "dryerVent": "Once a year",
        "reseal": "When the caulk cracks",
        "irrigation": "In the dry months",
        "trimTrees": "Once a year",
        "pests": "Once a year",
    ]

    static func title(_ id: String) -> String { text("care.task.\(id).title", titles[id] ?? id) }
    static func doneNote(_ id: String) -> String { text("care.task.\(id).note", notes[id] ?? titles[id] ?? id) }
    static func when(_ id: String, type: PropertyType) -> String {
        if type == .str, let short = whens["\(id).str"] { return text("care.task.\(id).when.str", short) }
        return text("care.task.\(id).when", whens[id] ?? "")
    }

    /// Every task key and its English (the catalog generator and the unit tests read this).
    static var taskStrings: [(key: String, value: String)] {
        var out: [(String, String)] = []
        for (id, v) in titles { out.append(("care.task.\(id).title", v)) }
        for (id, v) in notes { out.append(("care.task.\(id).note", v)) }
        for (id, v) in whens {
            if id.hasSuffix(".str") { out.append(("care.task.\(id.dropLast(4)).when.str", v)) } else { out.append(("care.task.\(id).when", v)) }
        }
        return out.sorted { $0.0 < $1.0 }
    }
}
