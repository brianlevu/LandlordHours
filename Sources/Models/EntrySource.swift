import Foundation

// MARK: - Entry Source
//
// How a time entry was captured. Persisted in `TimeEntry.importSource` so it rides the
// existing CloudKit field (no schema change): nil = manual entry, "timer", "voice",
// "calendar". Entries logged before 1.1 by timer or voice carry nil and read as manual.
//
// 2.0 (auto-capture) rules:
// - Calendar entries keep the stored value "calendar", whether they came from a 1.x bulk
//   import or a 2.0 confirmed suggestion. A confirmed suggestion is told apart by
//   `TimeEntry.confirmedAt != nil`, so 1.1 devices still label it "Calendar import".
// - New sources (receipt, location, shortcut, gmail) are new stored values. 1.1 builds map
//   them to Manual (acceptable, see plan risk 9); 2.0+ maps any value it does not know to
//   `.other`, never to `.manual`, so a future source is never mislabelled as hand-entered.
enum EntrySource: String, CaseIterable {
    case manual
    case timer
    case voice
    case calendar
    case receipt
    case location
    case shortcut
    case gmail
    /// A stored value this build does not recognise (written by a newer build).
    case other

    init(importSource: String?) {
        guard let importSource else {
            self = .manual
            return
        }
        // "manual" is never stored (manual stores nil), so a literal "manual" is unknown data.
        if importSource != EntrySource.manual.rawValue, let known = EntrySource(rawValue: importSource) {
            self = known
        } else {
            self = .other
        }
    }

    /// Value stored in `TimeEntry.importSource`. Manual entries store nil.
    var storedValue: String? {
        self == .manual ? nil : rawValue
    }

    var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .timer: return "Timer"
        case .voice: return "Voice"
        case .calendar: return "Calendar import"
        case .receipt: return "Receipt"
        case .location: return "Location"
        case .shortcut: return "Shortcut"
        case .gmail: return "Gmail"
        case .other: return "Other"
        }
    }
}

extension TimeEntry {
    var source: EntrySource { EntrySource(importSource: importSource) }

    /// True only for entries imported from the calendar (timer/voice entries are not imports).
    var isCalendarImport: Bool { source == .calendar }

    /// True for entries that came from a 2.0 suggestion the user confirmed (any source).
    var isConfirmedSuggestion: Bool { confirmedAt != nil }

    /// A 1.x calendar bulk import: calendar source with no confirm-first timestamp.
    var isLegacyCalendarImport: Bool { source == .calendar && confirmedAt == nil }
}
