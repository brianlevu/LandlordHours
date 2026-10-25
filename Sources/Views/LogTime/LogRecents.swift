import Foundation

// MARK: - Recents (Log time, empty state)
//
// "Repairs · Pine Cabin · 1h": the last three distinct (rental, kind, hours) combinations the user
// logged, as one-tap fills. Derived from the saved entries, never stored. Hidden until there are
// at least two past entries (one entry is not a pattern).

struct LogRecent: Identifiable, Equatable {
    let propertyId: UUID
    let category: ActivityCategory
    let hours: Double

    var id: String { "\(propertyId.uuidString)|\(category.analyticsKey)|\(Int((hours * 60).rounded()))" }
}

enum LogRecents {
    static let limit = 3
    static let minimumEntries = 2

    /// Newest first, distinct by (rental, kind, hours), only for rentals that still exist.
    static func derive(entries: [TimeEntry], properties: [RentalProperty], limit: Int = LogRecents.limit) -> [LogRecent] {
        guard entries.count >= minimumEntries else { return [] }
        let live = Set(properties.map(\.id))
        var seen = Set<String>()
        var out: [LogRecent] = []
        for entry in entries.sorted(by: { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }) {
            guard live.contains(entry.propertyId), entry.hours > 0 else { continue }
            let recent = LogRecent(propertyId: entry.propertyId, category: entry.category, hours: LogForm.clampHours(entry.hours))
            guard seen.insert(recent.id).inserted else { continue }
            out.append(recent)
            if out.count == limit { break }
        }
        // One distinct combination is not worth a row of its own.
        return out
    }

    /// "Repairs · Pine Cabin · 1h"; at AX sizes the hours drop out so the chip stays short.
    static func title(_ recent: LogRecent, properties: [RentalProperty], includeHours: Bool = true) -> String {
        let name = properties.first { $0.id == recent.propertyId }?.name ?? ""
        let kind = recent.category.inboxLabel
        return includeHours
            ? lt("\(kind) · \(name) · \(LogTimeFormat.hours(recent.hours))")
            : lt("\(kind) · \(name)")
    }
}

// MARK: - First rental (zero properties)

/// The one field on the first-run Log sheet: "Which rental is this for?". Log creates this rental
/// (name only, long-term, no address) and the entry in one save.
struct FirstPropertyDraft: Equatable {
    var name: String

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isValid: Bool { !trimmedName.isEmpty }

    func makeProperty() -> RentalProperty {
        RentalProperty(name: trimmedName, address: "", propertyType: .ltr)
    }
}
