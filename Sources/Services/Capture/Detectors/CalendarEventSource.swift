import Foundation
import EventKit

// MARK: - Calendar access and events behind a protocol
//
// The detector never touches EventKit directly, so tests run with fixtures and no real
// calendar. `EventKitCalendarSource` is the production adapter.

/// Calendar permission as the capture pipeline cares about it.
enum CalendarAccess: Equatable {
    case notDetermined
    /// Full read access (iOS 17 `fullAccess`).
    case fullAccess
    /// iOS 17 "add events only" (`writeOnly`). Events can't be read, so nothing is detected;
    /// the user must switch to Full Access in Settings.
    case limited
    case denied
    /// Blocked by Screen Time or a profile.
    case restricted

    var canReadEvents: Bool { self == .fullAccess }
}

/// One calendar event (one occurrence, for a recurring series) as the detector needs it.
struct CalendarEventSnapshot: Equatable {
    /// `calendarItemExternalIdentifier`: shared across devices, and across repeats of a series.
    var externalId: String
    /// Device-local `eventIdentifier`; what 1.x stored as `importExternalId`.
    var eventIdentifier: String?
    var calendarId: String
    var title: String?
    var location: String?
    var start: Date
    var end: Date
    /// The original start of this occurrence, which stays fixed if the occurrence is moved.
    var occurrenceDate: Date?
    var isAllDay: Bool
    var isDeclined: Bool
    var isCanceled: Bool

    init(
        externalId: String,
        eventIdentifier: String? = nil,
        calendarId: String = "CAL-1",
        title: String? = nil,
        location: String? = nil,
        start: Date,
        end: Date,
        occurrenceDate: Date? = nil,
        isAllDay: Bool = false,
        isDeclined: Bool = false,
        isCanceled: Bool = false
    ) {
        self.externalId = externalId
        self.eventIdentifier = eventIdentifier
        self.calendarId = calendarId
        self.title = title
        self.location = location
        self.start = start
        self.end = end
        self.occurrenceDate = occurrenceDate
        self.isAllDay = isAllDay
        self.isDeclined = isDeclined
        self.isCanceled = isCanceled
    }
}

protocol CalendarEventSource {
    func accessState() -> CalendarAccess
    /// Shows the system prompt when access is undetermined; returns the resulting state.
    func requestFullAccess() async -> CalendarAccess
    /// Events overlapping `interval`. `calendarIds` nil means every calendar.
    func events(in interval: DateInterval, calendarIds: Set<String>?) -> [CalendarEventSnapshot]
}

/// Production adapter over EventKit (iOS 17+).
final class EventKitCalendarSource: CalendarEventSource {
    private let store: EKEventStore

    /// Shares the 1.x import's store so there is one authorization-bearing instance.
    init(store: EKEventStore = CalendarImportService.shared.store) {
        self.store = store
    }

    func accessState() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .fullAccess
        case .writeOnly: return .limited
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    func requestFullAccess() async -> CalendarAccess {
        if accessState() == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        }
        return accessState()
    }

    func events(in interval: DateInterval, calendarIds: Set<String>?) -> [CalendarEventSnapshot] {
        guard accessState().canReadEvents else { return [] }
        var calendars: [EKCalendar]?
        if let calendarIds {
            let selected = store.calendars(for: .event).filter { calendarIds.contains($0.calendarIdentifier) }
            guard !selected.isEmpty else { return [] }
            calendars = selected
        }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
        return store.events(matching: predicate).compactMap { event in
            guard let start = event.startDate, let end = event.endDate else { return nil }
            let externalId = event.calendarItemExternalIdentifier ?? ""
            let id = externalId.isEmpty ? (event.eventIdentifier ?? "") : externalId
            guard !id.isEmpty else { return nil }
            let declined = event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
            return CalendarEventSnapshot(
                externalId: id,
                eventIdentifier: event.eventIdentifier,
                calendarId: event.calendar.calendarIdentifier,
                title: event.title,
                location: event.location,
                start: start,
                end: end,
                occurrenceDate: event.occurrenceDate,
                isAllDay: event.isAllDay,
                isDeclined: declined,
                isCanceled: event.status == .canceled
            )
        }
    }
}
