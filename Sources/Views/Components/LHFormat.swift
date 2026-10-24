import Foundation

// MARK: - LHFormat (standard §1.2)
//
// One hours formatter for every screen: "2h", "30m", "1h 30m", "12h 30m", and "—" when the hours
// are unknown. Decimal hours ("14.5") belong only in the PDF and CSV tables. Replaces
// `InboxFormat.hours` and `AppFormat.hours` ("1.5h") as each package moves its callers.

enum LHFormat {
    /// The dash shown for unknown hours.
    static let unknown = "—"

    /// Whole minutes for `hours`, rounded to the nearest minute. nil for unknown (nil, NaN,
    /// infinite or negative).
    static func minutes(_ hours: Double?) -> Int? {
        guard let hours, hours.isFinite, hours >= 0 else { return nil }
        return Int((hours * 60).rounded())
    }

    /// "2h", "30m", "1h 30m", "12h 30m"; "0m" for zero; "—" for unknown.
    static func hours(_ hours: Double?) -> String {
        guard let total = minutes(hours) else { return unknown }
        let h = total / 60
        let m = total % 60
        switch (h, m) {
        case (0, _):
            return String(localized: "format.minutes", defaultValue: "\(m)m", table: "Foundations",
                          comment: "Minutes only, e.g. 30m")
        case (_, 0):
            return String(localized: "format.hours", defaultValue: "\(h)h", table: "Foundations",
                          comment: "Whole hours, e.g. 2h")
        default:
            return String(localized: "format.hoursMinutes", defaultValue: "\(h)h \(m)m", table: "Foundations",
                          comment: "Hours and minutes, e.g. 1h 30m")
        }
    }

    /// The spoken form for VoiceOver: "2 hours", "30 minutes", "1 hour 30 minutes", "unknown".
    static func spokenHours(_ hours: Double?) -> String {
        guard let total = minutes(hours) else {
            return String(localized: "format.unknown.spoken", defaultValue: "unknown", table: "Foundations")
        }
        if total == 0 {
            return String(localized: "format.zero.spoken", defaultValue: "0 minutes", table: "Foundations")
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = total >= 60 ? [.hour, .minute] : [.minute]
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(total * 60)) ?? Self.hours(hours)
    }
}
