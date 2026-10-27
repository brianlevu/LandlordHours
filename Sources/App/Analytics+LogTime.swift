import Foundation

// MARK: - Log time events (2.1 note-first sheet)
//
// Fixed enums and counts only. Never the note, a rental name, or any free text.

extension Analytics {
    /// The Log sheet opened. `mode`: log, timer, timer_review, recovery.
    static func logOpened(mode: String, hasRentals: Bool, recentsShown: Bool) {
        capture("log_opened", properties: ["mode": mode, "has_rentals": hasRentals, "recents_shown": recentsShown])
    }

    /// A note filled at least one field. `tier`: rules or model.
    static func noteFilled(tier: LogFillTier, fields: Int, voice: Bool) {
        capture("note_filled", properties: ["tier": tier == .model ? "model" : "rules", "fields": fields, "voice": voice])
    }

    /// "Undo" on the fill caption.
    static func fillUndone() { capture("fill_undone") }

    /// The model changed rows after the rules' answer was on screen.
    static func fillUpdatedAfterSeen(fields: Int) { capture("fill_updated_after_seen", properties: ["fields": fields]) }

    /// The user set a field by hand (which field, never its value).
    static func fieldEdited(field: LogField) { capture("field_edited", properties: ["field": field.analyticsKey]) }

    /// A recent chip was used.
    static func recentUsed() { capture("recent_used") }

    /// "Enter details yourself".
    static func manualPathOpened() { capture("manual_path_opened") }

    /// The first log created the rental with the entry.
    static func propertyCreatedInline() { capture("property_created_inline") }

    /// Log was tapped while the model was still reading.
    static func logTappedWhileReading() { capture("log_tapped_while_reading") }

    /// The Timer button on the Log sheet.
    static func logTimerOpened() { capture("log_timer_opened") }

    /// A model read ended without an answer. `reason` is an enum name, never text.
    static func readFailed(reason: NoteReaderChain.Attempt) {
        let key: String
        switch reason {
        case .timedOut: key = "timed_out"
        case .rateLimited: key = "rate_limited"
        case .refused: key = "refused"
        case .cannotRead: key = "cannot_read"
        case .capped: key = "capped"
        case .unavailable: key = "unavailable"
        default: key = "failed"
        }
        capture("read_failed", properties: ["reason": key])
    }
}

extension LogField {
    var analyticsKey: String {
        switch self {
        case .property: return "rental"
        case .category: return "kind"
        case .hours: return "hours"
        case .participant: return "who"
        case .date: return "date"
        case .description: return "record"
        }
    }
}
