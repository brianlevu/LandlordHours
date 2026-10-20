import SwiftUI

// Mock data for the Screens2 render. "Today" is Sun, Oct 19 2026.

enum S2Data {
    static let pine = S2Property(id: "prop-pine-cabin", name: "Pine Cabin", address: "88 Ridge Rd, Big Bear", longStays: false, hours: 212, entries: 41, last: "Oct 18", aliases: ["Cabin", "Big Bear"], order: 0)
    static let oak = S2Property(id: "prop-oak-duplex", name: "Oak Street Duplex", address: "214 Oak St, Pasadena", longStays: true, hours: 520, entries: 96, last: "Oct 16", liveHere: true, aliases: ["Oak St", "The duplex"], order: 1)
    static let maple = S2Property(id: "prop-maple-new", name: "Maple Court", address: "12 Maple Ct, Glendale", longStays: true, hours: 0, entries: 0, last: "—", order: 3)
    static let long = S2Property(id: "prop-long-name", name: "The Arroyo Seco Schoolhouse Lofts, Unit 4B", address: "1 Arroyo Blvd, Pasadena", longStays: true, hours: 128, entries: 26, last: "Oct 12", order: 2)

    static let four: [S2Property] = [pine, oak, long, maple]

    static let twelve: [S2Property] = [
        pine, oak, long, maple,
        S2Property(id: "p5", name: "Birch Lane House", address: "5 Birch Ln", hours: 148, entries: 22, order: 4),
        S2Property(id: "p6", name: "Harbor View 2", address: "40 Harbor Dr", longStays: false, hours: 336, entries: 51, order: 5),
        S2Property(id: "p7", name: "Cedar Triplex", address: "77 Cedar Ave", hours: 91, entries: 18, order: 6),
        S2Property(id: "p8", name: "Lakeside A-Frame", address: "3 Shore Rd", longStays: false, hours: 455, entries: 70, order: 7),
        S2Property(id: "p9", name: "Elm St Fourplex", address: "908 Elm St", hours: 27, entries: 6, order: 8),
        S2Property(id: "p10", name: "Sunset Bungalow", address: "19 Sunset Pl", hours: 503, entries: 88, order: 9),
        S2Property(id: "p11", name: "Granite Flats", address: "2 Quarry Rd", hours: 12, entries: 3, order: 10),
        S2Property(id: "p12", name: "Willow Cottage", address: "61 Willow Way", longStays: false, hours: 240, entries: 37, order: 11),
    ]

    struct Suggestion: Identifiable, Hashable {
        let id: String
        var hours: Double?
        var cat: S2Cat?
        var source: String
        var symbol: String = "calendar"
        var title: String
        var place: String?
        var badge: String? = nil
        var newPlace = false
    }

    static let pending: [Suggestion] = [
        Suggestion(id: "plumber", hours: 2, cat: .repairs, source: "Calendar · Today 12–2", title: "Plumber", place: "Pine Cabin"),
        Suggestion(id: "showing", hours: 1, cat: .leasing, source: "Calendar · Sat 5:30–6:30", title: "Showing", place: "Pine Cabin"),
        Suggestion(id: "sam", hours: 0.5, cat: .management, source: "Calendar · Fri 4–4:30", title: "Call with Sam", place: "Pine Cabin"),
        Suggestion(id: "depot", hours: nil, cat: .repairs, source: "Receipt · Thu", symbol: "doc.text", title: "Home Depot", place: "Pine Cabin", badge: "Needs hours"),
        Suggestion(id: "inspect", hours: 1.5, cat: .legal, source: "Calendar · Thu 9–10:30", title: "City inspection", place: "Pine Cabin"),
        Suggestion(id: "books", hours: 1, cat: .bookkeeping, source: "Calendar · Wed 8–9", title: "Monthly books", place: "Pine Cabin"),
        Suggestion(id: "drive", hours: 1.25, cat: .travel, source: "Location · Tue", symbol: "location", title: "Drive", place: "Pine Cabin"),
        Suggestion(id: "keys", hours: 0.5, cat: .management, source: "Calendar · Mon 6–6:30", title: "Key handoff", place: "Pine Cabin"),
    ]

    /// Free user at the limit: Pine Cabin only, a suggestion at a place they don't have.
    static let limitSuggestion = Suggestion(id: "oak-showing", hours: 1, cat: .leasing, source: "Calendar · Sat 5:30–6:30", title: "Showing", place: nil, newPlace: true)

    /// This week (Mon–Sun), confirmed hours; nil = future.
    static let week: [Double?] = [1.5, 0, 3, 2, 0, 3, 0]
    static let weekLetters = ["M", "T", "W", "T", "F", "S", "S"]
    static let todayIndex = 6

    struct Entry: Identifiable { let id = UUID(); let cat: S2Cat; let title: String; let hours: Double; let date: String; let source: String }

    /// Nine distinct entries for the export preview.
    static let exportSample: [Entry] = [
        Entry(cat: .repairs, title: "Plumber", hours: 2, date: "Oct 18", source: "From calendar"),
        Entry(cat: .leasing, title: "Showing", hours: 1, date: "Oct 16", source: "From calendar"),
        Entry(cat: .management, title: "Key handoff", hours: 0.5, date: "Oct 12", source: "From calendar"),
        Entry(cat: .bookkeeping, title: "Monthly books", hours: 1.5, date: "Oct 8", source: "Typed"),
        Entry(cat: .renovations, title: "Gutter repair", hours: 3, date: "Oct 4", source: "Receipt"),
        Entry(cat: .management, title: "Tenant call", hours: 0.5, date: "Sep 30", source: "From calendar"),
        Entry(cat: .travel, title: "Drive to the cabin", hours: 2.5, date: "Sep 27", source: "Location"),
        Entry(cat: .legal, title: "Lease review", hours: 1, date: "Sep 22", source: "Typed"),
        Entry(cat: .repairs, title: "Smoke detectors", hours: 1, date: "Sep 19", source: "From calendar"),
    ]

    /// Hours by kind of work for one property; always sums to the property's hours.
    static func kinds(for p: S2Property) -> [(S2Cat, Double)] {
        let mix: [(S2Cat, Double)] = p.longStays
            ? [(.repairs, 0.38), (.management, 0.27), (.leasing, 0.2), (.bookkeeping, 0.15)]
            : [(.repairs, 0.42), (.management, 0.27), (.leasing, 0.18), (.bookkeeping, 0.13)]
        var out = mix.dropLast().map { ($0.0, (p.hours * $0.1).rounded()) }
        out.append((mix.last!.0, p.hours - out.reduce(0) { $0 + $1.1 }))
        return out
    }

    /// Recent entries belong to the property they are shown on.
    static func recent(for p: S2Property) -> [Entry] {
        switch p.id {
        case oak.id: [
            Entry(cat: .repairs, title: "HVAC service", hours: 1.5, date: "Oct 16", source: "From calendar"),
            Entry(cat: .leasing, title: "Lease signing", hours: 1, date: "Oct 11", source: "From calendar"),
            Entry(cat: .management, title: "Tenant call", hours: 0.5, date: "Oct 9", source: "Typed"),
        ]
        default: recent
        }
    }
    static let recent: [Entry] = [
        Entry(cat: .repairs, title: "Plumber", hours: 2, date: "Oct 16", source: "From calendar"),
        Entry(cat: .leasing, title: "Showing", hours: 1, date: "Oct 12", source: "From calendar"),
        Entry(cat: .bookkeeping, title: "Monthly books", hours: 1.5, date: "Oct 8", source: "Typed"),
    ]
}
