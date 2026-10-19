import Foundation

enum CalendarCaptureError: Error, Equatable {
    /// Calendar can't be read: not asked yet, denied, restricted, or "add events only".
    case noAccess(CalendarAccess)
}

/// Why events were left out of the last scan. Diagnostics and a future "N events skipped" hint.
struct CalendarSkipCounts: Equatable {
    var allDay = 0
    var tooLong = 0
    var invalidDuration = 0
    var declined = 0
    var canceled = 0
}

// MARK: - Detector
//
// Turns calendar events into capture candidates. One candidate per OCCURRENCE: a recurring
// event produces one `cal:<externalId>:<occurrenceStartISO>` key for each repeat. Nothing here
// classifies; the classifier proposes property and category.
//
// Skipped: all-day events, canceled events, events the user declined, and events whose length
// is not between 0 and 24 hours (1.x skipped those too, and a 1.1 device would not recognise
// the entry otherwise).
final class CalendarDetector: CaptureDetector {
    /// Same bound as 1.x (`hours < 24`).
    static let maxEventDuration: TimeInterval = 24 * 3600
    static let backfillDays = 90
    static let upcomingDays = 7

    let kind: Suggestion.Kind = .calendar
    private let source: CalendarEventSource
    private let clock: () -> Date
    private let calendarIds: () -> Set<String>?
    private(set) var lastSkipCounts = CalendarSkipCounts()

    init(
        source: CalendarEventSource,
        calendarIds: @escaping () -> Set<String>? = { nil },
        clock: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.calendarIds = calendarIds
        self.clock = clock
    }

    var access: CalendarAccess { source.accessState() }

    func requestAccess() async -> CalendarAccess { await source.requestFullAccess() }

    /// The last 90 days up to `now`.
    func backfillInterval(now: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.date(byAdding: .day, value: -Self.backfillDays, to: now) ?? now.addingTimeInterval(-90 * 86_400)
        return DateInterval(start: start, end: now)
    }

    /// From `now` to 7 days ahead.
    func upcomingInterval(now: Date, calendar: Calendar = .current) -> DateInterval {
        let end = calendar.date(byAdding: .day, value: Self.upcomingDays, to: now) ?? now.addingTimeInterval(7 * 86_400)
        return DateInterval(start: now, end: end)
    }

    func detect(in interval: DateInterval) async throws -> [CaptureCandidate] {
        let access = source.accessState()
        guard access.canReadEvents else { throw CalendarCaptureError.noAccess(access) }

        let now = clock()
        // A window that has fully passed is the backfill; anything reaching forward is live.
        let isBackfill = interval.end <= now
        var counts = CalendarSkipCounts()
        var candidates: [CaptureCandidate] = []

        for event in source.events(in: interval, calendarIds: calendarIds()) {
            // Only events that start inside the window; others belong to a neighbouring scan.
            guard event.start >= interval.start, event.start < interval.end else { continue }
            if event.isCanceled { counts.canceled += 1; continue }
            if event.isAllDay { counts.allDay += 1; continue }
            if event.isDeclined { counts.declined += 1; continue }
            let duration = event.end.timeIntervalSince(event.start)
            if duration <= 0 { counts.invalidDuration += 1; continue }
            if duration >= Self.maxEventDuration { counts.tooLong += 1; continue }

            let occurrence = event.occurrenceDate ?? event.start
            candidates.append(CaptureCandidate(
                sourceKey: SuggestionKey.calendar(externalId: event.externalId, occurrence: occurrence),
                kind: .calendar,
                start: event.start,
                end: event.end,
                // Same fallback title 1.x used, so notes match on a 1.1 device.
                title: event.title ?? "Calendar Event",
                externalId: event.externalId,
                legacyEventIdentifier: event.eventIdentifier,
                containerId: event.calendarId,
                location: event.location,
                isBackfill: isBackfill,
                detectedAt: max(now, event.end)
            ))
        }
        lastSkipCounts = counts
        return candidates.sorted { $0.start < $1.start }
    }
}
