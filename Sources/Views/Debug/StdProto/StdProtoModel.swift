import SwiftUI

#if DEBUG
// MARK: - Sample owners for the standard mockups
//
// Rentals come from HomeProtoSeed (Santa Ray Ave / Delaney Ct / Yeandle Ave for "brian").
// The items are what a real calendar and reminder list would offer.

struct StdEntry: Identifiable {
    let id: String
    let title: String
    let rental: String
    let category: ActivityCategory
    let day: String
    let hours: Double
}

struct StdSeed {
    let id: String
    let rentals: HomeProtoSeed
    let suggestions: [StdSuggestion]
    let week: [StdEntry]

    static func make(_ id: String) -> StdSeed {
        let rentals = HomeProtoSeed.make(id)
        switch id {
        case "reps750":
            return StdSeed(id: id, rentals: rentals, suggestions: [
                StdSuggestion(id: "s1", title: L("Plumber at Maple Duplex"), source: .calendar, when: L("Today 12–2"), category: .repairs, status: .none, hours: 2, rental: "Maple Duplex"),
                StdSuggestion(id: "s2", title: L("Monthly mortgage payment"), source: .reminder, when: L("Nov 1"), category: .bookkeeping, status: .none, hours: 0.25),
                StdSuggestion(id: "s3", title: L("Showing at Oak Street"), source: .calendar, when: L("Oct 19 9–10:30"), category: .leasing, status: .notSure, hours: 1.5),
                StdSuggestion(id: "s4", title: L("Tenant call about the lease renewal"), source: .calendar, when: L("Oct 18 4–4:30"), category: .leasing, status: .none, hours: 0.5),
                StdSuggestion(id: "s5", title: L("Gutter cleaning at Birch Flat"), source: .calendar, when: L("Oct 16 8–10"), category: .repairs, status: .mightBeLogged, hours: 2),
            ], week: [
                StdEntry(id: "w1", title: L("Paid the mortgage"), rental: "Maple Duplex", category: .bookkeeping, day: L("Mon"), hours: 0.25),
                StdEntry(id: "w2", title: L("Furnace service visit"), rental: "Cedar Row", category: .repairs, day: L("Tue"), hours: 1.5),
                StdEntry(id: "w3", title: L("Lease signing"), rental: "Oak Street", category: .leasing, day: L("Wed"), hours: 1),
            ])
        case "eight":
            return StdSeed(id: id, rentals: rentals, suggestions: [
                StdSuggestion(id: "s1", title: L("Turnover clean at Tahoe Cabin"), source: .calendar, when: L("Today 10–11:30"), category: .management, status: .none, hours: 1.5, rental: "tahoe"),
                StdSuggestion(id: "s2", title: L("Monthly mortgage payment"), source: .reminder, when: L("Nov 1"), category: .bookkeeping, status: .none, hours: 0.25),
                StdSuggestion(id: "s3", title: L("Hot tub repair at Lake House"), source: .calendar, when: L("Oct 21 1–3"), category: .repairs, status: .notSure, hours: 2),
            ], week: [
                StdEntry(id: "w1", title: L("Paid the mortgage"), rental: "Palm Studio", category: .bookkeeping, day: L("Mon"), hours: 0.25),
                StdEntry(id: "w2", title: L("Guest check-in"), rental: "Tahoe Cabin", category: .management, day: L("Wed"), hours: 0.5),
            ])
        default:
            return StdSeed(id: "brian", rentals: rentals, suggestions: [
                StdSuggestion(id: "s1", title: L("Plumber at Santa Ray Ave"), source: .calendar, when: L("Today 12–2"), category: .repairs, status: .none, hours: 2, rental: "santa"),
                StdSuggestion(id: "s2", title: L("Monthly mortgage payment"), source: .reminder, when: L("Nov 1"), category: .bookkeeping, status: .none, hours: 0.25),
                StdSuggestion(id: "s4", title: L("Showing at Delaney Ct"), source: .calendar, when: L("Oct 19 9–10:30"), category: .leasing, status: .notSure, hours: 1.5),
                StdSuggestion(id: "s3", title: L("Turnover clean at Santa Ray Ave"), source: .calendar, when: L("Yesterday 10–11:30"), category: .management, status: .none, hours: 1.5, rental: "santa"),
                StdSuggestion(id: "s5", title: L("Tenant call about the lease renewal"), source: .calendar, when: L("Oct 18 4–4:30"), category: .leasing, status: .none, hours: 0.5),
                StdSuggestion(id: "s6", title: L("Hardware store run for Yeandle Ave"), source: .reminder, when: L("Oct 17"), category: .repairs, status: .needsHours, hours: nil),
                StdSuggestion(id: "s7", title: L("Gutter cleaning at Delaney Ct"), source: .calendar, when: L("Oct 16 8–10"), category: .repairs, status: .mightBeLogged, hours: 2),
            ], week: [
                StdEntry(id: "w1", title: L("Paid the mortgage"), rental: "Delaney Ct", category: .bookkeeping, day: L("Mon"), hours: 0.25),
                StdEntry(id: "w2", title: L("Smoke alarm batteries"), rental: "Santa Ray Ave", category: .repairs, day: L("Tue"), hours: 0.75),
                StdEntry(id: "w3", title: L("Rent reminder texts"), rental: "Yeandle Ave", category: .management, day: L("Wed"), hours: 0.25),
            ])
        }
    }

    // MARK: Hero words (§C.2 Progress / Behind pace)

    struct Hero: Equatable {
        let key: String
        let eyebrow: String
        let number: Double
        let label: String
        let status: String?
        let tone: HouseStatusTone
        let stageHours: Double
        let flag: String
    }

    static let daysLeft = 69   // Oct 23 → Dec 31, 2026

    func hero(_ focus: HomeProtoFocus) -> Hero {
        switch focus {
        case .all:
            let total = rentals.totalHours, target = Double(rentals.sharedTarget ?? 750)
            let weekly = Int(((target - total) / (Double(Self.daysLeft) / 7)).rounded(.up))
            return Hero(key: "all", eyebrow: L("2026 · All rentals"), number: total.rounded(.down),
                        label: L("of \(Int(target)) hours"), status: L("\(weekly)h a week to reach \(Int(target))"),
                        tone: .caution, stageHours: min(total / target * 500, 500), flag: L("All rentals"))
        case .rental(let id):
            guard let r = rentals.rental(id) else { return hero(.all) }
            switch r.target {
            case .own(let t):
                let status: String
                let tone: HouseStatusTone
                switch r.pace {
                case .done:
                    status = L("Reached \(t)"); tone = .positive
                case .behind:
                    status = L("\(r.weeklyNeed ?? 0)h a week to reach \(t)"); tone = .caution
                default:
                    status = L("On pace for \(t)"); tone = .positive
                }
                return Hero(key: id, eyebrow: L("2026 · \(r.name)"), number: r.hours.rounded(.down), label: L("of \(t) hours"),
                            status: status, tone: tone, stageHours: HomeProtoStage.hours(for: r), flag: r.name)
            case .record:
                return Hero(key: id, eyebrow: L("2026 · \(r.name)"), number: r.hours.rounded(.down), label: L("hours logged"),
                            status: L("Record only, no target"), tone: .neutral, stageHours: 0, flag: r.name)
            case .counts:
                let shared = rentals.sharedTarget ?? 750
                return Hero(key: id, eyebrow: L("2026 · \(r.name)"), number: r.hours.rounded(.down), label: L("hours here"),
                            status: L("Counts toward \(shared)"), tone: .neutral, stageHours: 0, flag: r.name)
            }
        }
    }

    /// Two stat tiles under the pace header.
    func paceTiles(_ focus: HomeProtoFocus) -> [(String, String, String?)] {
        let days = (L("\(Self.daysLeft)"), L("days left in 2026"), nil as String?)
        switch focus {
        case .all:
            let total = rentals.totalHours, target = Double(rentals.sharedTarget ?? 750)
            let weekly = Int(((target - total) / (Double(Self.daysLeft) / 7)).rounded(.up))
            return [(L("\(weekly)h"), L("a week to reach \(Int(target))"), "exclamationmark.circle.fill"), days]
        case .rental(let id):
            guard let r = rentals.rental(id) else { return [days] }
            if case .own(let t) = r.target {
                if r.pace == .done { let month = r.reached ?? ""; return [(L("\(t)h"), L("reached in \(month)"), "checkmark.circle.fill"), days] }
                return [(L("\(r.weeklyNeed ?? 0)h"), L("a week to reach \(t)"), "exclamationmark.circle.fill"), days]
            }
            return [(StdFormat.hours(r.hours), L("logged this year"), nil), days]
        }
    }
}
#endif
