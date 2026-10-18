// LHDesignSandbox — mock data only. No persistence, no real model.
import SwiftUI
import Observation

enum SourceKind: String, Hashable {
    case calendar, receipt, location, timer, manual

    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .receipt: "doc.text"
        case .location: "location.fill"
        case .timer: "timer"
        case .manual: "pencil"
        }
    }
    var label: String {
        switch self {
        case .calendar: "Calendar"
        case .receipt: "Receipt"
        case .location: "Location"
        case .timer: "Timer"
        case .manual: "Added by you"
        }
    }
    var tint: Color {
        switch self {
        case .calendar: LH.srcCalendar
        case .receipt: LH.srcReceipt
        case .location: LH.srcLocation
        case .timer, .manual: LH.action
        }
    }
}

struct Suggestion: Identifiable, Hashable {
    enum State: Hashable { case pending, logged }
    let id: String
    let kind: SourceKind
    let group: String
    let when: String          // "Tue 9–11"
    let noun: String          // "Plumber"
    let joiner: String        // "at" / "for"
    let property: String
    var hours: Double?        // nil for receipts: never guess hours
    var capMinutes: Int?      // location dwell cap
    let detail: String        // third line
    var amount: String?
    var state: State = .pending
}

struct RecordEntry: Identifiable {
    let id = UUID()
    let kind: SourceKind
    let title: String
    let property: String
    let status: String
    let hours: Double
    let date: String
}

struct RecordGroup: Identifiable {
    let id: String
    let total: Double
    let entries: [RecordEntry]
}

enum Scenario: String {
    case behind, onPace, empty, emptyInbox, conceptConfirm, milestone
}

@MainActor
@Observable
final class MockStore {
    var suggestions: [Suggestion]
    var hoursLogged: Double
    let goal: Double = 750
    let expectedToday: Double = 218
    var hasProperties: Bool
    var isPro = false
    var confirmTick = 0
    var dismissTick = 0

    var pending: [Suggestion] { suggestions.filter { $0.state == .pending } }
    var pendingCount: Int { pending.count }
    var pace: Double { hoursLogged - expectedToday }

    init(scenario: Scenario) {
        switch scenario {
        case .behind:
            suggestions = MockStore.backfill
            hoursLogged = 212
            hasProperties = true
        case .onPace:
            suggestions = Array(MockStore.backfill.prefix(1))
            hoursLogged = 236
            hasProperties = true
        case .empty:
            suggestions = []
            hoursLogged = 0
            hasProperties = false
        case .emptyInbox:
            suggestions = []
            hoursLogged = 236
            hasProperties = true
        case .conceptConfirm:
            suggestions = MockStore.backfill
            // Porchlight starts 2h short of a lamp so the confirm visibly lights one.
            hoursLogged = LHConcept.current == .porchlight ? 248 : 212
            hasProperties = true
        case .milestone:
            suggestions = []
            hoursLogged = 500
            hasProperties = true
        }
    }

    func confirm(_ id: String, hours: Double? = nil, reduceMotion: Bool) {
        guard let i = suggestions.firstIndex(where: { $0.id == id }) else { return }
        let h = hours ?? suggestions[i].hours ?? 0
        withAnimation(Motion.snappy(reduceMotion)) {
            suggestions[i].state = .logged
            suggestions[i].hours = h
            hoursLogged += h
        }
        confirmTick += 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(Motion.collapse(reduceMotion)) {
                self.suggestions.removeAll { $0.id == id }
            }
        }
    }

    func dismiss(_ id: String, reduceMotion: Bool) {
        withAnimation(Motion.collapse(reduceMotion)) {
            suggestions.removeAll { $0.id == id }
        }
        dismissTick += 1
    }

    // 14 things from the last 90 days (backfill). Receipts carry no hours.
    static let backfill: [Suggestion] = [
        Suggestion(id: "plumber", kind: .calendar, group: "This week", when: "Tue 9–11",
                   noun: "Plumber", joiner: "at", property: "Pine Cabin", hours: 2,
                   detail: "Repairs · Me"),
        Suggestion(id: "showing", kind: .calendar, group: "This week", when: "Mon 5:30–6:30",
                   noun: "Showing", joiner: "at", property: "Oak Street Duplex", hours: 1,
                   detail: "Leasing · Me"),
        Suggestion(id: "homedepot", kind: .receipt, group: "This week", when: "Thu, Oct 16",
                   noun: "Home Depot", joiner: "for", property: "Pine Cabin", hours: nil,
                   detail: "$212.40", amount: "$212.40"),
        Suggestion(id: "oakvisit", kind: .location, group: "This week", when: "Sun 1:10–2:50",
                   noun: "Visit", joiner: "at", property: "Oak Street Duplex", hours: nil, capMinutes: 100,
                   detail: "Up to 1h 40m"),
        Suggestion(id: "turnover", kind: .calendar, group: "Earlier in October", when: "Thu, Oct 9 · 10–1",
                   noun: "Turnover clean", joiner: "at", property: "Pine Cabin", hours: 3,
                   detail: "Cleaning · Spouse"),
        Suggestion(id: "books", kind: .calendar, group: "Earlier in October", when: "Mon, Oct 6 · 7–8:30 pm",
                   noun: "Bookkeeping", joiner: "for", property: "Both properties", hours: 1.5,
                   detail: "Admin · Me"),
        Suggestion(id: "insurance", kind: .calendar, group: "Earlier in October", when: "Thu, Oct 2 · 2–3",
                   noun: "Insurance review", joiner: "for", property: "Oak Street Duplex", hours: 1,
                   detail: "Admin · Me"),
        Suggestion(id: "hoa", kind: .calendar, group: "September", when: "Tue, Sep 23 · 6–8 pm",
                   noun: "HOA meeting", joiner: "for", property: "Oak Street Duplex", hours: 2,
                   detail: "Management · Me"),
        Suggestion(id: "roof", kind: .calendar, group: "September", when: "Fri, Sep 12 · 8–9:30",
                   noun: "Roof inspection", joiner: "at", property: "Pine Cabin", hours: 1.5,
                   detail: "Repairs · Me"),
        Suggestion(id: "lease", kind: .calendar, group: "September", when: "Mon, Sep 8 · 4–5",
                   noun: "Lease signing", joiner: "at", property: "Oak Street Duplex", hours: 1,
                   detail: "Leasing · Spouse"),
        Suggestion(id: "appliance", kind: .calendar, group: "September", when: "Wed, Sep 3 · 12–2",
                   noun: "Fridge delivery", joiner: "at", property: "Pine Cabin", hours: 2,
                   detail: "Repairs · Me"),
        Suggestion(id: "lowes", kind: .receipt, group: "August", when: "Sat, Aug 30",
                   noun: "Lowe's", joiner: "for", property: "Oak Street Duplex", hours: nil,
                   detail: "$86.17", amount: "$86.17"),
        Suggestion(id: "paint", kind: .calendar, group: "August", when: "Sat, Aug 23 · 9–3",
                   noun: "Painting", joiner: "at", property: "Oak Street Duplex", hours: 6,
                   detail: "Repairs · Me + Spouse"),
        Suggestion(id: "tax", kind: .calendar, group: "August", when: "Tue, Aug 19 · 11–12",
                   noun: "Property tax call", joiner: "for", property: "Pine Cabin", hours: 1,
                   detail: "Admin · Me"),
    ]

    static let records: [RecordGroup] = [
        RecordGroup(id: "October 2026", total: 41, entries: [
            RecordEntry(kind: .calendar, title: "Plumber", property: "Pine Cabin", status: "From calendar · confirmed", hours: 2, date: "Oct 14"),
            RecordEntry(kind: .receipt, title: "Home Depot run", property: "Pine Cabin", status: "From receipt · confirmed", hours: 1.5, date: "Oct 16"),
            RecordEntry(kind: .location, title: "Visit", property: "Oak Street Duplex", status: "From location · confirmed", hours: 1.25, date: "Oct 12"),
            RecordEntry(kind: .timer, title: "Unit 2 repairs", property: "Oak Street Duplex", status: "Timer", hours: 3.5, date: "Oct 11"),
            RecordEntry(kind: .manual, title: "Tenant calls", property: "Oak Street Duplex", status: "Added by you", hours: 0.75, date: "Oct 10"),
            RecordEntry(kind: .calendar, title: "Turnover clean", property: "Pine Cabin", status: "From calendar · confirmed", hours: 3, date: "Oct 9"),
        ]),
        RecordGroup(id: "September 2026", total: 63.5, entries: [
            RecordEntry(kind: .calendar, title: "HOA meeting", property: "Oak Street Duplex", status: "From calendar · confirmed", hours: 2, date: "Sep 23"),
            RecordEntry(kind: .manual, title: "Bookkeeping", property: "Both properties", status: "Added by you", hours: 2.5, date: "Sep 21"),
            RecordEntry(kind: .calendar, title: "Roof inspection", property: "Pine Cabin", status: "From calendar · confirmed 9 days later", hours: 1.5, date: "Sep 12"),
        ]),
    ]
}
