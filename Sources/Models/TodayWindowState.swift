import Foundation

/// Whether the house's windows are lit on Today: lit when any hours were logged today, dark when none.
///
/// Pure over `TimeEntry` so Today (and the CRAFT mock) pass `AppViewModel.timeEntries` straight in.
/// "Today" is the user's calendar day, not a 24-hour window.
enum TodayWindowState {
    /// True when at least one entry with hours falls on today's calendar day.
    /// - Parameter rentalIDs: the selected rental(s). `nil` means all rentals.
    static func loggedToday(entries: [TimeEntry],
                            rentalIDs: Set<UUID>? = nil,
                            now: Date = Date(),
                            calendar: Calendar = .current) -> Bool {
        entries.contains { entry in
            guard entry.hours > 0 else { return false }
            if let rentalIDs, !rentalIDs.contains(entry.propertyId) { return false }
            return calendar.isDate(entry.date, inSameDayAs: now)
        }
    }
}
