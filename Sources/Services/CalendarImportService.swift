import Foundation
import EventKit

/// A detected calendar event ready for user review before import.
struct DetectedCalendarEntry: Identifiable {
    let id: UUID = UUID()
    let eventTitle: String
    let eventDate: Date
    var propertyId: UUID?
    var category: ActivityCategory
    var hours: Double
    var isSelected: Bool = true
}

/// Scans device calendars for property-related events and produces
/// DetectedCalendarEntry items for user review.
class CalendarImportService {
    static let shared = CalendarImportService()

    private let propertyKeywords = [
        "property", "tenant", "landlord", "repair", "maintenance",
        "plumber", "electrician", "inspection", "lease", "rent",
        "showing", "walkthrough", "contractor", "hvac", "cleaning",
        "move-in", "move-out", "appraisal", "realtor", "closing"
    ]

    private init() {}

    /// Request calendar access. Returns true if granted.
    func requestAccess() async -> Bool {
        let store = EKEventStore()
        if #available(iOS 17.0, *) {
            return (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            return await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Returns all available calendars sorted by title.
    func availableCalendars() -> [EKCalendar] {
        EKEventStore().calendars(for: .event).sorted { $0.title < $1.title }
    }

    /// Scans the given calendars for the last `days` days and returns
    /// detected property-related entries for user review.
    func scanCalendars(
        _ calendarIds: Set<String>,
        properties: [RentalProperty],
        days: Int = 90
    ) -> [DetectedCalendarEntry] {
        let store = EKEventStore()
        let allCalendars = store.calendars(for: .event)
        let selected = allCalendars.filter { calendarIds.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { return [] }

        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) else { return [] }

        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: selected)
        let events = store.events(matching: predicate)
        let defaultPropertyId = properties.first?.id

        var results: [DetectedCalendarEntry] = []
        for event in events {
            let title = event.title?.lowercased() ?? ""
            let location = event.location?.lowercased() ?? ""
            let eventNotes = event.notes?.lowercased() ?? ""
            let combined = title + " " + location + " " + eventNotes

            let isPropertyRelated = propertyKeywords.contains { combined.contains($0) }
            guard isPropertyRelated,
                  let start = event.startDate,
                  let end = event.endDate else { continue }

            let hours = end.timeIntervalSince(start) / 3600.0
            guard hours > 0 && hours < 24 else { continue }

            let matchedProperty = matchProperty(from: combined, properties: properties)

            results.append(DetectedCalendarEntry(
                eventTitle: event.title ?? "Calendar Event",
                eventDate: start,
                propertyId: matchedProperty?.id ?? defaultPropertyId,
                category: categorizeEvent(title: title),
                hours: min(hours, 24)
            ))
        }
        return results.sorted { $0.eventDate > $1.eventDate }
    }

    /// Categorize an event title into an ActivityCategory.
    func categorizeEvent(title: String) -> ActivityCategory {
        let t = title.lowercased()
        if t.contains("repair") || t.contains("fix") || t.contains("plumber") || t.contains("electrician") || t.contains("hvac") || t.contains("clean") || t.contains("maintenance") || t.contains("lawn") {
            return .repairs
        } else if t.contains("tenant") || t.contains("lease") || t.contains("rent") || t.contains("showing") {
            return .leasing
        } else if t.contains("inspect") || t.contains("walkthrough") || t.contains("appraisal") || t.contains("travel") {
            return .travel
        } else if t.contains("closing") || t.contains("realtor") || t.contains("contractor") || t.contains("renovati") {
            return .renovations
        } else if t.contains("insurance") || t.contains("claim") {
            return .insurance
        } else if t.contains("legal") || t.contains("compliance") || t.contains("evict") {
            return .legal
        }
        return .management
    }

    // MARK: - Private

    private func matchProperty(from text: String, properties: [RentalProperty]) -> RentalProperty? {
        // Try name match first
        for property in properties {
            if text.contains(property.name.lowercased()) {
                return property
            }
        }
        // Try address parts (words > 3 chars)
        for property in properties {
            let addressWords = property.address.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 3 }
            for word in addressWords {
                if text.contains(word) { return property }
            }
        }
        return nil
    }
}
