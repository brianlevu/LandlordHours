import XCTest
@testable import LandlordHours

// MARK: - Fake calendar

final class FakeCalendarSource: CalendarEventSource {
    var access: CalendarAccess
    /// What the system prompt resolves to when access is undetermined.
    var accessAfterPrompt: CalendarAccess
    var events: [CalendarEventSnapshot]
    private(set) var promptCount = 0
    private(set) var fetchCount = 0

    init(access: CalendarAccess = .fullAccess, accessAfterPrompt: CalendarAccess = .fullAccess, events: [CalendarEventSnapshot] = []) {
        self.access = access
        self.accessAfterPrompt = accessAfterPrompt
        self.events = events
    }

    func accessState() -> CalendarAccess { access }

    func requestFullAccess() async -> CalendarAccess {
        if access == .notDetermined {
            promptCount += 1
            access = accessAfterPrompt
        }
        return access
    }

    /// Like EventKit: everything overlapping the window.
    func events(in interval: DateInterval, calendarIds: Set<String>?) -> [CalendarEventSnapshot] {
        fetchCount += 1
        return events.filter { event in
            event.start < interval.end && event.end > interval.start
                && (calendarIds == nil || calendarIds!.contains(event.calendarId))
        }
    }
}

// MARK: - Detector

@MainActor
class CalendarCaptureTestCase: CaptureTestCase {
    var now: Date!

    override func setUp() async throws {
        try await super.setUp()
        now = date(2026, 6, 1, 12)
    }

    func event(
        _ externalId: String? = "EVT-1",
        recurring: Bool = false,
        detached: Bool = false,
        floating: Bool = false,
        localId: String? = nil,
        start: Date,
        hours: Double = 1.5,
        title: String? = "Showing - Oak St",
        occurrence: Date? = nil,
        allDay: Bool = false,
        declined: Bool = false,
        canceled: Bool = false
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            externalId: externalId, eventIdentifier: localId ?? "LOCAL-\(externalId ?? "NONE")", title: title,
            start: start, end: start.addingTimeInterval(hours * 3600),
            // EventKit: a series occurrence keeps its ORIGINAL start; a one-off's occurrenceDate
            // is simply its current start and moves with it.
            occurrenceDate: (recurring || detached) ? (occurrence ?? start) : start,
            isAllDay: allDay, isDeclined: declined, isCanceled: canceled,
            hasRecurrenceRules: recurring, isDetached: detached, isFloating: floating
        )
    }

    func makeDetector(_ source: FakeCalendarSource) -> CalendarDetector {
        CalendarDetector(source: source, clock: { [now] in now! }, calendar: calendar)
    }

    func makeCoordinator(
        _ source: FakeCalendarSource,
        store: SuggestionStore,
        classifier: CaptureClassifier = PlaceholderCalendarClassifier()
    ) -> CalendarCaptureCoordinator {
        CalendarCaptureCoordinator(
            detector: makeDetector(source), classifier: classifier, store: store,
            clock: { [now] in now! }, calendar: calendar
        )
    }

    /// Accepts every event and proposes `propertyId`; category from 1.x rules.
    func acceptAll(propertyId: UUID?) -> FakeCaptureClassifier {
        FakeCaptureClassifier { candidate in
            CaptureClassification(
                isLandlordWork: true, confidence: 0.9, propertyId: propertyId, category: .leasing,
                hours: 99, hoursBasis: .none, tier: .rules, evidence: []
            )
        }
    }
}

final class CalendarDetectorTests: CalendarCaptureTestCase {
    func testRecurringEventProducesOneKeyPerOccurrence() async throws {
        let weekly = (0..<3).map { event("SERIES", recurring: true, start: date(2026, 5, 4 + 7 * $0, 10)) }
        let candidates = try await makeDetector(FakeCalendarSource(events: weekly))
            .detect(in: DateInterval(start: date(2026, 5, 1), end: now))
        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(Set(candidates.map(\.sourceKey)).count, 3)
        for candidate in candidates {
            XCTAssertTrue(candidate.sourceKey.hasPrefix("cal:SERIES:"), candidate.sourceKey)
            XCTAssertEqual(candidate.externalId, "SERIES")
            XCTAssertEqual(candidate.legacyEventIdentifier, "LOCAL-SERIES")
        }
    }

    func testMovedOccurrenceKeepsKeyOfOriginalOccurrence() async throws {
        let original = date(2026, 5, 4, 10)
        let moved = event("SERIES", recurring: true, start: date(2026, 5, 5, 15), occurrence: original)
        let candidates = try await makeDetector(FakeCalendarSource(events: [moved]))
            .detect(in: DateInterval(start: date(2026, 5, 1), end: now))
        XCTAssertEqual(candidates.first?.sourceKey, SuggestionKey.calendar(externalId: "SERIES", occurrence: original))
        XCTAssertEqual(candidates.first?.start, date(2026, 5, 5, 15))
    }

    func testOneOffKeyIgnoresStartSoRescheduleKeepsKey() async throws {
        let window = DateInterval(start: date(2026, 5, 1), end: now)
        let before = try await makeDetector(FakeCalendarSource(events: [event("ONE", start: date(2026, 5, 4, 10))])).detect(in: window)
        let after = try await makeDetector(FakeCalendarSource(events: [event("ONE", start: date(2026, 5, 6, 15))])).detect(in: window)
        XCTAssertEqual(before[0].sourceKey, "cal:ONE")
        XCTAssertEqual(before[0].sourceKey, after[0].sourceKey)
    }

    func testDetachedOccurrenceKeysOnOriginalOccurrenceDate() async throws {
        let original = date(2026, 5, 4, 10)
        let detached = event("SERIES", detached: true, start: date(2026, 5, 7, 16), occurrence: original)
        let found = try await makeDetector(FakeCalendarSource(events: [detached]))
            .detect(in: DateInterval(start: date(2026, 5, 1), end: now))
        XCTAssertEqual(found.first?.sourceKey, SuggestionKey.calendar(externalId: "SERIES", occurrence: original))
    }

    func testRecurringEventWithoutOccurrenceDateIsSkippedNotKeyedOnMovingStart() async throws {
        var broken = event("SERIES", recurring: true, start: date(2026, 5, 4, 10))
        broken.occurrenceDate = nil
        let detector = makeDetector(FakeCalendarSource(events: [broken, event("OK", start: date(2026, 5, 5, 10))]))
        let found = try await detector.detect(in: DateInterval(start: date(2026, 5, 1), end: now))
        XCTAssertEqual(found.compactMap(\.externalId), ["OK"])
        XCTAssertEqual(detector.lastSkipCounts.missingOccurrence, 1)
    }

    func testFloatingRecurringEventKeysIdenticallyInEveryTimeZone() async throws {
        // 10:00 wall-clock on 4 May: a different instant on each device.
        func wallClock(_ tz: String) -> (Calendar, Date) {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: tz)!
            return (cal, cal.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 10))!)
        }
        var keys: [String] = []
        for tz in ["America/Los_Angeles", "America/New_York", "Asia/Tokyo"] {
            let (cal, start) = wallClock(tz)
            let floating = event("FLOAT", recurring: true, floating: true, start: start)
            let detector = CalendarDetector(source: FakeCalendarSource(events: [floating]), clock: { [now] in now! }, calendar: cal)
            let found = try await detector.detect(in: DateInterval(start: start.addingTimeInterval(-86_400), end: start.addingTimeInterval(86_400)))
            keys.append(try XCTUnwrap(found.first?.sourceKey))
        }
        XCTAssertEqual(Set(keys).count, 1, "\(keys)")
        XCTAssertEqual(keys[0], "cal:FLOAT:f2026-05-04T10:00")

        // A fixed-zone event still keys on the absolute instant.
        let (_, start) = wallClock("America/Los_Angeles")
        let fixed = try await makeDetector(FakeCalendarSource(events: [event("FIXED", recurring: true, start: start)]))
            .detect(in: DateInterval(start: start.addingTimeInterval(-86_400), end: start.addingTimeInterval(86_400)))
        XCTAssertEqual(fixed.first?.sourceKey, SuggestionKey.calendar(externalId: "FIXED", occurrence: start))
    }

    func testMissingSharedIdUsesMarkedDeviceLocalKey() async throws {
        let local = event(nil, localId: "LOCAL-ONLY", start: date(2026, 5, 4, 10))
        let found = try await makeDetector(FakeCalendarSource(events: [local]))
            .detect(in: DateInterval(start: date(2026, 5, 1), end: now))
        XCTAssertEqual(found.first?.sourceKey, "cal-local:LOCAL-ONLY")
        XCTAssertNil(found.first?.externalId)
        XCTAssertEqual(found.first?.legacyEventIdentifier, "LOCAL-ONLY")

        let tenant = event(nil, localId: "LOCAL-2", start: date(2026, 5, 5, 10), title: "Tenant call")
        let result = await makeCoordinator(FakeCalendarSource(events: [tenant]), store: makeStore())
            .scanBackfill(properties: [], entries: [])
        XCTAssertTrue(result.added[0].evidence.contains { $0.contains("shared event id") })
    }

    func testSkipsAllDayLongDeclinedCanceledAndEmptyEvents() async throws {
        let source = FakeCalendarSource(events: [
            event("OK", start: date(2026, 5, 4, 10)),
            event("ALLDAY", start: date(2026, 5, 5, 0), hours: 24, allDay: true),
            event("LONG", start: date(2026, 5, 6, 9), hours: 30),
            event("EXACT24", start: date(2026, 5, 7, 9), hours: 24),
            event("DECLINED", start: date(2026, 5, 8, 9), declined: true),
            event("CANCELED", start: date(2026, 5, 9, 9), canceled: true),
            event("EMPTY", start: date(2026, 5, 10, 9), hours: 0),
            event("ALMOST", start: date(2026, 5, 11, 9), hours: 23.5),
        ])
        let detector = makeDetector(source)
        let candidates = try await detector.detect(in: DateInterval(start: date(2026, 5, 1), end: now))
        XCTAssertEqual(candidates.compactMap(\.externalId), ["OK", "ALMOST"])
        XCTAssertEqual(detector.lastSkipCounts, CalendarSkipCounts(allDay: 1, tooLong: 2, invalidDuration: 1, declined: 1, canceled: 1))
    }

    func testIntervalsAndBackfillFlag() async throws {
        let detector = makeDetector(FakeCalendarSource())
        let backfill = detector.backfillInterval(now: now, calendar: calendar)
        XCTAssertEqual(backfill.end, now)
        XCTAssertEqual(calendar.dateComponents([.day], from: backfill.start, to: now).day, 90)
        let upcoming = detector.upcomingInterval(now: now, calendar: calendar)
        XCTAssertEqual(upcoming.start, now)
        XCTAssertEqual(calendar.dateComponents([.day], from: now, to: upcoming.end).day, 7)

        let past = event("PAST", start: date(2026, 5, 20, 10))
        let soon = event("SOON", start: date(2026, 6, 3, 10))
        let source = FakeCalendarSource(events: [past, soon])
        let back = try await makeDetector(source).detect(in: backfill)
        XCTAssertEqual(back.map(\.externalId), ["PAST"])
        XCTAssertTrue(back[0].isBackfill)
        let up = try await makeDetector(source).detect(in: upcoming)
        XCTAssertEqual(up.map(\.externalId), ["SOON"])
        XCTAssertFalse(up[0].isBackfill)
    }

    func testDetectedAtIsLaterOfNowAndEventEnd() async throws {
        let past = event("PAST", start: date(2026, 5, 20, 10))
        let soon = event("SOON", start: date(2026, 6, 3, 10))
        let found = try await makeDetector(FakeCalendarSource(events: [past, soon]))
            .detect(in: DateInterval(start: date(2026, 5, 1), end: date(2026, 6, 10)))
        XCTAssertEqual(found.first { $0.externalId == "PAST" }?.detectedAt, now)
        XCTAssertEqual(found.first { $0.externalId == "SOON" }?.detectedAt, soon.end)
    }

    func testEventOverlappingWindowStartIsLeftToThePreviousScan() async throws {
        let straddling = event("STRADDLE", start: now.addingTimeInterval(-3600), hours: 3)
        let found = try await makeDetector(FakeCalendarSource(events: [straddling]))
            .detect(in: DateInterval(start: now, end: now.addingTimeInterval(7 * 86_400)))
        XCTAssertTrue(found.isEmpty)
    }

    func testMissingTitleUsesSame1xFallback() async throws {
        let found = try await makeDetector(FakeCalendarSource(events: [event(start: date(2026, 5, 4, 10), title: nil)]))
            .detect(in: DateInterval(start: date(2026, 5, 1), end: now))
        XCTAssertEqual(found.first?.title, "Calendar event")
    }

    // MARK: Permissions

    func testNoReadAccessThrowsForEveryNonFullState() async {
        for state in [CalendarAccess.notDetermined, .denied, .limited, .restricted] {
            let source = FakeCalendarSource(access: state, events: [event(start: date(2026, 5, 4, 10))])
            do {
                _ = try await makeDetector(source).detect(in: DateInterval(start: date(2026, 5, 1), end: now))
                XCTFail("Should throw for \(state)")
            } catch {
                XCTAssertEqual(error as? CalendarCaptureError, .noAccess(state))
            }
            XCTAssertEqual(source.fetchCount, 0, "Never reads events without full access")
        }
    }

    func testScanNeverPromptsAndReportsBlockedState() async {
        for state in [CalendarAccess.notDetermined, .denied, .limited, .restricted] {
            let source = FakeCalendarSource(access: state, events: [event(start: date(2026, 5, 4, 10))])
            let store = makeStore()
            let result = await makeCoordinator(source, store: store).scanBackfill(properties: [], entries: [])
            XCTAssertEqual(result, .blocked(state))
            XCTAssertEqual(source.promptCount, 0)
            XCTAssertTrue(store.suggestions.isEmpty)
        }
    }

    func testRequestAccessPromptsOnlyWhenUndetermined() async {
        let source = FakeCalendarSource(access: .notDetermined, accessAfterPrompt: .fullAccess)
        let coordinator = makeCoordinator(source, store: makeStore())
        let granted = await coordinator.requestAccessIfNeeded()
        XCTAssertEqual(granted, .fullAccess)
        XCTAssertEqual(source.promptCount, 1)
        _ = await coordinator.requestAccessIfNeeded()
        XCTAssertEqual(source.promptCount, 1)

        for state in [CalendarAccess.denied, .limited, .restricted] {
            let blocked = FakeCalendarSource(access: state)
            let result = await makeCoordinator(blocked, store: makeStore()).requestAccessIfNeeded()
            XCTAssertEqual(result, state)
            XCTAssertEqual(blocked.promptCount, 0, "Can't re-prompt once decided")
        }

        let refused = FakeCalendarSource(access: .notDetermined, accessAfterPrompt: .denied)
        let afterRefusal = await makeCoordinator(refused, store: makeStore()).requestAccessIfNeeded()
        XCTAssertEqual(afterRefusal, .denied)
    }
}

// MARK: - Coordinator, dedupe and legacy matching

final class CalendarCaptureCoordinatorTests: CalendarCaptureTestCase {
    private func legacyImport(propertyId: UUID, start: Date, hours: Double = 1.5, title: String = "Showing - Oak St") -> TimeEntry {
        TimeEntry(propertyId: propertyId, participant: .selfParticipant, category: .leasing, hours: hours,
                  date: start, notes: title, importSource: "calendar",
                  importExternalId: "LOCAL-EVT-1", importCalendarId: "CAL-1")
    }

    func testBackfillBuildsScheduledSuggestionsWith1xValues() async throws {
        let (_, propertyId) = makeViewModel()
        let properties = [RentalProperty(id: propertyId, name: "Oak", address: "1 Oak St", propertyType: .ltr)]
        let start = date(2026, 5, 4, 10)
        let source = FakeCalendarSource(events: [event(start: start, hours: 1.25)])
        let store = makeStore()
        let result = await makeCoordinator(source, store: store).scanBackfill(properties: properties, entries: [])

        XCTAssertEqual(result.access, .fullAccess)
        let s = try XCTUnwrap(result.added.first)
        XCTAssertEqual(s.kind, .calendar)
        XCTAssertEqual(s.hoursBasis, .scheduled)
        XCTAssertEqual(s.proposedHours, 1.25)
        XCTAssertEqual(s.start, start)
        XCTAssertEqual(s.proposedCategory, CalendarImportService.shared.categorizeEvent(title: "showing - oak st"))
        XCTAssertEqual(s.proposedPropertyId, propertyId)
        XCTAssertTrue(s.isBackfill)
        XCTAssertEqual(s.containerId, "CAL-1")
        XCTAssertEqual(s.legacyEventIdentifier, "LOCAL-EVT-1")
    }

    func testClassifierCannotChangeHoursFrom1x() async throws {
        let (_, propertyId) = makeViewModel()
        let start = date(2026, 5, 4, 10)
        let store = makeStore()
        let result = await makeCoordinator(FakeCalendarSource(events: [event(start: start, hours: 2)]), store: store,
                                           classifier: acceptAll(propertyId: propertyId))
            .scanBackfill(properties: [RentalProperty(id: propertyId, name: "Oak", address: "1 Oak St", propertyType: .ltr)], entries: [])
        XCTAssertEqual(result.added.first?.proposedHours, 2)
        XCTAssertEqual(result.added.first?.hoursBasis, .scheduled)
    }

    func testNonLandlordEventsAreNotSuggestedByPlaceholderRules() async {
        let source = FakeCalendarSource(events: [
            event("A", start: date(2026, 5, 4, 10), title: "Dentist"),
            event("B", start: date(2026, 5, 5, 10), title: "Tenant call"),
        ])
        let store = makeStore()
        let result = await makeCoordinator(source, store: store).scanBackfill(properties: [], entries: [])
        XCTAssertEqual(result.added.map(\.title), ["Tenant call"])
    }

    func testUnknownPropertyFromClassifierIsDropped() async {
        let source = FakeCalendarSource(events: [event(start: date(2026, 5, 4, 10))])
        let store = makeStore()
        let result = await makeCoordinator(source, store: store, classifier: acceptAll(propertyId: UUID()))
            .scanBackfill(properties: [], entries: [])
        XCTAssertNil(result.added.first?.proposedPropertyId)
    }

    func testRescanAddsNothingNewAndKeepsIds() async throws {
        let source = FakeCalendarSource(events: [event(start: date(2026, 5, 4, 10))])
        let store = makeStore()
        let coordinator = makeCoordinator(source, store: store)
        let first = await coordinator.scanBackfill(properties: [], entries: [])
        let second = await coordinator.scanBackfill(properties: [], entries: [])
        XCTAssertEqual(first.added.count, 1)
        XCTAssertTrue(second.added.isEmpty)
        XCTAssertEqual(store.suggestions.count, 1)
        XCTAssertEqual(store.suggestions.first?.id, first.added.first?.id)
    }

    func testDismissedKeyIsNeverSuggestedAgain() async {
        let source = FakeCalendarSource(events: [
            event("A", start: date(2026, 5, 4, 10)),
            event("B", start: date(2026, 5, 5, 10)),
        ])
        let store = makeStore()
        let coordinator = makeCoordinator(source, store: store)
        let first = await coordinator.scanBackfill(properties: [], entries: [])
        let dismissed = first.added[0]
        store.dismiss(key: dismissed.sourceKey, reason: .notLandlordWork)

        // Same store, and a fresh store loaded from disk (relaunch).
        for candidateStore in [store, SuggestionStore(userId: profileId, baseDirectory: baseDir)] {
            let again = await makeCoordinator(source, store: candidateStore).scanBackfill(properties: [], entries: [])
            XCTAssertFalse(again.added.contains { $0.sourceKey == dismissed.sourceKey })
            XCTAssertFalse(candidateStore.pending.contains { $0.sourceKey == dismissed.sourceKey })
        }
    }

    func testOneRecurringOccurrenceDismissedOthersStay() async {
        let weekly = (0..<3).map { event("SERIES", recurring: true, start: date(2026, 5, 4 + 7 * $0, 10), title: "Tenant call") }
        let store = makeStore()
        let coordinator = makeCoordinator(FakeCalendarSource(events: weekly), store: store)
        let first = await coordinator.scanBackfill(properties: [], entries: [])
        store.dismiss(key: first.added[1].sourceKey, reason: .notLandlordWork)
        _ = await coordinator.scanBackfill(properties: [], entries: [])
        XCTAssertEqual(store.pending.count, 2)
    }

    func testSameEventOnTwoDevicesGetsSameKeyAndEntryId() async {
        let events = [event("SHARED", start: date(2026, 5, 4, 10), title: "Tenant call")]
        let phone = makeStore()
        let padDir = baseDir.appendingPathComponent("ipad")
        let pad = SuggestionStore(userId: profileId, baseDirectory: padDir)
        // Each device has its own device-local eventIdentifier.
        var padEvents = events
        padEvents[0].eventIdentifier = "OTHER-DEVICE-LOCAL-ID"
        let a = await makeCoordinator(FakeCalendarSource(events: events), store: phone).scanBackfill(properties: [], entries: [])
        let b = await makeCoordinator(FakeCalendarSource(events: padEvents), store: pad).scanBackfill(properties: [], entries: [])
        XCTAssertEqual(a.added[0].sourceKey, b.added[0].sourceKey)
        XCTAssertEqual(a.added[0].entryId(profileId: profileId), b.added[0].entryId(profileId: profileId))
    }

    func testEntryConfirmedOnOtherDeviceResolvesDuringScan() async {
        let source = FakeCalendarSource(events: [event("SHARED", start: date(2026, 5, 4, 10), title: "Tenant call")])
        let probe = await makeCoordinator(source, store: makeStore()).scanBackfill(properties: [], entries: [])
        let s = probe.added[0]
        let pulled = TimeEntry(id: s.entryId(profileId: profileId), propertyId: UUID(), participant: .selfParticipant,
                               category: .management, hours: 1.5, date: s.start, importSource: "calendar",
                               confirmedAt: now, sourceKey: s.sourceKey)
        let freshStore = SuggestionStore(userId: profileId, baseDirectory: baseDir.appendingPathComponent("fresh"))
        let result = await makeCoordinator(source, store: freshStore).scanBackfill(properties: [], entries: [pulled])
        XCTAssertTrue(result.added.isEmpty)
        XCTAssertEqual(freshStore.suggestion(forKey: s.sourceKey)?.state, .confirmed(entryId: pulled.id))
    }

    // MARK: Legacy 1.x matching

    func testLegacyImportCoversExactlyThatOccurrence() async {
        let (_, propertyId) = makeViewModel()
        let properties = [RentalProperty(id: propertyId, name: "Oak", address: "1 Oak St", propertyType: .ltr)]
        let weekly = (0..<2).map { event("SERIES", recurring: true, start: date(2026, 5, 4 + 7 * $0, 10)) }
        let legacy = legacyImport(propertyId: propertyId, start: date(2026, 5, 4, 10))
        let store = makeStore()
        let result = await makeCoordinator(FakeCalendarSource(events: weekly), store: store)
            .scanBackfill(properties: properties, entries: [legacy])
        XCTAssertEqual(result.added.count, 1, "Only the repeat 1.x never imported is new")
        XCTAssertEqual(result.added.first?.start, date(2026, 5, 11, 10))
        let covered = store.suggestions.first { $0.start == date(2026, 5, 4, 10) }
        XCTAssertEqual(covered?.state, .confirmed(entryId: legacy.id))
    }

    func testTwoOccurrencesOnOneDayMatchByStartTime() async {
        let (_, propertyId) = makeViewModel()
        let properties = [RentalProperty(id: propertyId, name: "Oak", address: "1 Oak St", propertyType: .ltr)]
        let morning = event("M", start: date(2026, 5, 4, 9))
        let afternoon = event("A", start: date(2026, 5, 4, 15))
        let legacy = legacyImport(propertyId: propertyId, start: date(2026, 5, 4, 15))
        let store = makeStore()
        let result = await makeCoordinator(FakeCalendarSource(events: [morning, afternoon]), store: store)
            .scanBackfill(properties: properties, entries: [legacy])
        XCTAssertEqual(result.added.map(\.start), [date(2026, 5, 4, 9)], "Same title and hours, different time")
    }

    func testOneLegacyImportCoversOnlyOneSuggestion() async {
        let (_, propertyId) = makeViewModel()
        let properties = [RentalProperty(id: propertyId, name: "Oak", address: "1 Oak St", propertyType: .ltr)]
        // Two different events at the same time with the same title and hours.
        let events = [event("E1", start: date(2026, 5, 4, 10)), event("E2", start: date(2026, 5, 4, 10))]
        let legacy = legacyImport(propertyId: propertyId, start: date(2026, 5, 4, 10))
        let store = makeStore()
        let result = await makeCoordinator(FakeCalendarSource(events: events), store: store)
            .scanBackfill(properties: properties, entries: [legacy])
        XCTAssertEqual(result.added.count, 1)
        XCTAssertEqual(store.suggestions.filter { $0.state == .confirmed(entryId: legacy.id) }.count, 1)

        // And again after a rescan and a reconcile: the claim holds.
        _ = await makeCoordinator(FakeCalendarSource(events: events), store: store)
            .scanBackfill(properties: properties, entries: [legacy])
        store.reconcile(with: [legacy], calendar: calendar)
        XCTAssertEqual(store.suggestions.filter { $0.state == .confirmed(entryId: legacy.id) }.count, 1)
        XCTAssertEqual(store.pending.count, 1)
    }

    func testTwoLegacyImportsPairWithTheirOwnOccurrences() {
        let propertyId = UUID()
        let a = legacyImport(propertyId: propertyId, start: date(2026, 5, 4, 10))
        let b = legacyImport(propertyId: propertyId, start: date(2026, 5, 4, 10).addingTimeInterval(30))
        let first = calendarSuggestion(externalId: "E1", start: date(2026, 5, 4, 10), propertyId: propertyId)
        let second = calendarSuggestion(externalId: "E2", start: date(2026, 5, 4, 10), propertyId: propertyId)
        let store = makeStore()
        store.ingest([first, second], existingEntries: [a, b], calendar: calendar)
        let ids = Set(store.suggestions.compactMap { s -> UUID? in
            if case .confirmed(let id) = s.state { return id }
            return nil
        })
        XCTAssertEqual(ids, [a.id, b.id])
    }

    func testEditedTitleOnLegacyImportIsNotHiddenButFlagged() async {
        let (_, propertyId) = makeViewModel()
        let properties = [RentalProperty(id: propertyId, name: "Oak", address: "1 Oak St", propertyType: .ltr)]
        let legacy = legacyImport(propertyId: propertyId, start: date(2026, 5, 4, 10), title: "Oak showing (renamed by me)")
        let store = makeStore()
        let result = await makeCoordinator(FakeCalendarSource(events: [event(start: date(2026, 5, 4, 10))]), store: store)
            .scanBackfill(properties: properties, entries: [legacy])
        let s = result.added.first
        XCTAssertNotNil(s, "Real hours are never hidden by a fuzzy match")
        XCTAssertEqual(s?.mightAlreadyBeLogged, true)
        XCTAssertEqual(s?.isPreselectable, false)
    }

    func testLegacyMatchNeedsStartWithin60SecondsAndSameHours() {
        let propertyId = UUID()
        let legacy = legacyImport(propertyId: propertyId, start: date(2026, 5, 4, 10))
        func match(startOffset: TimeInterval, hours: Double = 1.5) -> TimeEntry? {
            let s = calendarSuggestion(start: date(2026, 5, 4, 10).addingTimeInterval(startOffset), propertyId: propertyId, hours: hours)
            return CaptureReconciler.legacyImportMatch(for: s, in: [legacy], calendar: calendar)
        }
        XCTAssertNotNil(match(startOffset: 0))
        XCTAssertNotNil(match(startOffset: 59))
        XCTAssertNotNil(match(startOffset: -60))
        XCTAssertNil(match(startOffset: 61))
        XCTAssertNil(match(startOffset: 3600), "Same day and title, different time")
        XCTAssertNil(match(startOffset: 0, hours: 1.0))
    }

    func testLegacyMatchWithProposedPropertyRequiresThatProperty() {
        let propertyId = UUID()
        let legacy = legacyImport(propertyId: propertyId, start: date(2026, 5, 4, 10))
        let other = calendarSuggestion(start: date(2026, 5, 4, 10), propertyId: UUID())
        XCTAssertNil(CaptureReconciler.legacyImportMatch(for: other, in: [legacy], calendar: calendar))
        let same = calendarSuggestion(start: date(2026, 5, 4, 10), propertyId: propertyId)
        XCTAssertEqual(CaptureReconciler.legacyImportMatch(for: same, in: [legacy], calendar: calendar)?.id, legacy.id)
    }

    func testSuggestionWithoutPropertyStillMatchesOnStartHoursTitle() {
        // 1.x only ever imported with a property, so a legacy entry always has one; an
        // unclassified suggestion that agrees on start, hours and title is the same event.
        let legacy = legacyImport(propertyId: UUID(), start: date(2026, 5, 4, 10))
        let noProperty = calendarSuggestion(start: date(2026, 5, 4, 10), propertyId: nil)
        XCTAssertEqual(CaptureReconciler.legacyImportMatch(for: noProperty, in: [legacy], calendar: calendar)?.id, legacy.id)
        let otherTime = calendarSuggestion(start: date(2026, 5, 4, 14), propertyId: nil)
        XCTAssertNil(CaptureReconciler.legacyImportMatch(for: otherTime, in: [legacy], calendar: calendar))
    }

    func testConfirmedEntriesAreNotLegacyMatches() {
        let propertyId = UUID()
        var entry = legacyImport(propertyId: propertyId, start: date(2026, 5, 4, 10))
        entry.confirmedAt = now
        let s = calendarSuggestion(start: date(2026, 5, 4, 10), propertyId: propertyId)
        XCTAssertNil(CaptureReconciler.legacyImportMatch(for: s, in: [entry], calendar: calendar))
    }

    // MARK: Might already be logged

    func testManualEntryOnSamePropertyAndDayFlagsAndNeverPreselects() async {
        let (_, propertyId) = makeViewModel()
        let properties = [RentalProperty(id: propertyId, name: "Oak", address: "1 Oak St", propertyType: .ltr)]
        let manual = TimeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs,
                               hours: 1.5, date: date(2026, 5, 4, 16))
        let otherProperty = TimeEntry(propertyId: UUID(), participant: .selfParticipant, category: .repairs,
                                      hours: 1.5, date: date(2026, 5, 5, 16))
        let source = FakeCalendarSource(events: [
            event("A", start: date(2026, 5, 4, 10)),
            event("B", start: date(2026, 5, 5, 10)),
            event("C", start: date(2026, 5, 6, 10)),
        ])
        let store = makeStore()
        _ = await makeCoordinator(source, store: store).scanBackfill(properties: properties, entries: [manual, otherProperty])
        func suggestion(_ id: String) -> Suggestion { store.suggestions.first { $0.externalId == id }! }
        XCTAssertTrue(suggestion("A").mightAlreadyBeLogged)
        XCTAssertFalse(suggestion("A").isPreselectable)
        XCTAssertTrue(suggestion("A").isPending, "Still shown")
        XCTAssertFalse(suggestion("B").mightAlreadyBeLogged, "Different property")
        XCTAssertFalse(suggestion("C").mightAlreadyBeLogged, "Different day")
        XCTAssertTrue(suggestion("C").isPreselectable)
    }

    func testLegacyImportDoesNotCountAsOtherConfirmedSuggestionsButFlagsLooseMatch() {
        // An unmatched 1.x import on the same property/day is "might already be logged".
        let propertyId = UUID()
        let legacy = legacyImport(propertyId: propertyId, start: date(2026, 5, 4, 10), title: "Something else")
        let s = calendarSuggestion(start: date(2026, 5, 4, 13), propertyId: propertyId)
        XCTAssertTrue(CaptureReconciler.mightAlreadyBeLogged(s, in: [legacy], calendar: calendar))
    }

    func testRescheduledConfirmedOneOffDoesNotReturn() async throws {
        let (viewModel, _) = makeViewModel()
        let store = makeStore()
        let original = FakeCalendarSource(events: [event("ONE", start: date(2026, 5, 4, 10))])
        let first = await makeCoordinator(original, store: store)
            .scanBackfill(properties: viewModel.properties, entries: viewModel.timeEntries)
        let s = try XCTUnwrap(first.added.first)
        XCTAssertNotNil(viewModel.confirm(s, store: store, profileId: profileId).entryId)

        // The organizer moves the showing to another day.
        let moved = FakeCalendarSource(events: [event("ONE", start: date(2026, 5, 6, 15))])
        let again = await makeCoordinator(moved, store: store)
            .scanBackfill(properties: viewModel.properties, entries: viewModel.timeEntries)
        XCTAssertTrue(again.added.isEmpty)
        XCTAssertEqual(store.suggestions.count, 1)
        XCTAssertTrue(store.pending.isEmpty)
    }

    func testRescheduledPendingOneOffUpdatesInPlace() async throws {
        let store = makeStore()
        let first = await makeCoordinator(FakeCalendarSource(events: [event("ONE", start: date(2026, 5, 4, 10), title: "Tenant call")]), store: store)
            .scanBackfill(properties: [], entries: [])
        _ = await makeCoordinator(FakeCalendarSource(events: [event("ONE", start: date(2026, 5, 6, 15), title: "Tenant call")]), store: store)
            .scanBackfill(properties: [], entries: [])
        XCTAssertEqual(store.suggestions.count, 1)
        XCTAssertEqual(store.suggestions[0].id, first.added[0].id)
        XCTAssertEqual(store.suggestions[0].start, date(2026, 5, 6, 15))
    }

    func testSeriesTimeEditedForAllEventsDoesNotResurrectConfirmedOccurrence() async throws {
        let (viewModel, _) = makeViewModel()
        let store = makeStore()
        let before = (0..<2).map { event("SERIES", recurring: true, start: date(2026, 5, 4 + 7 * $0, 10)) }
        let first = await makeCoordinator(FakeCalendarSource(events: before), store: store)
            .scanBackfill(properties: viewModel.properties, entries: [])
        // The user confirms the first occurrence.
        XCTAssertNotNil(viewModel.confirm(first.added[0], store: store, profileId: profileId).entryId)

        // "All events" edit: 10:00 becomes 14:00, so every original occurrence date shifts.
        let after = (0..<2).map { event("SERIES", recurring: true, start: date(2026, 5, 4 + 7 * $0, 14)) }
        _ = await makeCoordinator(FakeCalendarSource(events: after), store: store)
            .scanBackfill(properties: viewModel.properties, entries: viewModel.timeEntries)
        let reappeared = try XCTUnwrap(store.suggestions.first { $0.start == date(2026, 5, 4, 14) })
        XCTAssertTrue(reappeared.isPending)
        XCTAssertTrue(reappeared.mightAlreadyBeLogged)
        XCTAssertFalse(reappeared.isPreselectable)
        let nextWeek = try XCTUnwrap(store.suggestions.first { $0.start == date(2026, 5, 11, 14) })
        XCTAssertFalse(nextWeek.mightAlreadyBeLogged, "Different day: a genuinely new occurrence")
    }

    func testSameSeriesFlagIsExactOnExternalId() {
        let propertyId = UUID()
        let s = calendarSuggestion(externalId: "SERIES", start: date(2026, 5, 4, 14), propertyId: propertyId)
        func confirmed(_ key: String) -> TimeEntry {
            TimeEntry(propertyId: UUID(), participant: .selfParticipant, category: .leasing, hours: 9, date: date(2026, 5, 4, 10),
                      importSource: "calendar", confirmedAt: now, sourceKey: key)
        }
        XCTAssertTrue(CaptureReconciler.mightAlreadyBeLogged(s, in: [confirmed("cal:SERIES:2026-05-04T17:00:00Z")], calendar: calendar))
        XCTAssertFalse(CaptureReconciler.mightAlreadyBeLogged(s, in: [confirmed("cal:SERIES2:2026-05-04T17:00:00Z")], calendar: calendar))
        XCTAssertFalse(CaptureReconciler.mightAlreadyBeLogged(s, in: [confirmed("cal:OTHER")], calendar: calendar))
    }

    // MARK: Might already be logged, v2

    func testLegacyImportWithDifferentPropertyStillFlagsOnTitleAndStart() async {
        let (_, propertyId) = makeViewModel()
        let properties = [RentalProperty(id: propertyId, name: "Oak", address: "1 Oak St", propertyType: .ltr)]
        // 1.x derived another property (e.g. from notes) or the user edited it later.
        let legacy = legacyImport(propertyId: UUID(), start: date(2026, 5, 4, 10).addingTimeInterval(45))
        let store = makeStore()
        let result = await makeCoordinator(FakeCalendarSource(events: [event(start: date(2026, 5, 4, 10))]), store: store)
            .scanBackfill(properties: properties, entries: [legacy])
        XCTAssertEqual(result.added.first?.mightAlreadyBeLogged, true)
        XCTAssertEqual(result.added.first?.isPreselectable, false)

        let otherTitle = legacyImport(propertyId: UUID(), start: date(2026, 5, 4, 10), title: "Different")
        let s = calendarSuggestion(externalId: "X", start: date(2026, 5, 20, 10), propertyId: propertyId)
        let sameStartOtherTitle = calendarSuggestion(externalId: "Y", start: date(2026, 5, 4, 10), propertyId: nil, hours: 4)
        XCTAssertFalse(CaptureReconciler.mightAlreadyBeLogged(sameStartOtherTitle, in: [otherTitle], calendar: calendar))
        XCTAssertFalse(CaptureReconciler.mightAlreadyBeLogged(s, in: [legacy], calendar: calendar))
    }

    func testEventCrossingMidnightFlagsEntriesOnEitherDayAndByWindow() {
        let propertyId = UUID()
        // 23:00 on 4 May to 01:00 on 5 May (device timezone).
        let s = calendarSuggestion(start: date(2026, 5, 4, 23), propertyId: propertyId, hours: 2)
        func manual(_ date: Date, hours: Double = 1) -> TimeEntry {
            TimeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs, hours: hours, date: date)
        }
        XCTAssertTrue(CaptureReconciler.mightAlreadyBeLogged(s, in: [manual(date(2026, 5, 4, 8))], calendar: calendar), "Same first day")
        XCTAssertTrue(CaptureReconciler.mightAlreadyBeLogged(s, in: [manual(date(2026, 5, 5, 9))], calendar: calendar), "Second day the event touches")
        XCTAssertTrue(CaptureReconciler.mightAlreadyBeLogged(s, in: [manual(date(2026, 5, 4, 22).addingTimeInterval(1800), hours: 2)], calendar: calendar),
                      "Entry window runs into the event window")
        XCTAssertFalse(CaptureReconciler.mightAlreadyBeLogged(s, in: [manual(date(2026, 5, 6, 9))], calendar: calendar))
        XCTAssertFalse(CaptureReconciler.mightAlreadyBeLogged(s, in: [manual(date(2026, 5, 3, 9))], calendar: calendar))
    }

    func testEventEndingExactlyAtMidnightDoesNotTouchNextDay() {
        let propertyId = UUID()
        let s = calendarSuggestion(start: date(2026, 5, 4, 22), propertyId: propertyId, hours: 2)
        let nextDay = TimeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs, hours: 1, date: date(2026, 5, 5, 9))
        XCTAssertFalse(CaptureReconciler.mightAlreadyBeLogged(s, in: [nextDay], calendar: calendar))
    }

    // MARK: 1.1 compatibility

    func testConfirmStoresSeriesWideEventIdentifierLike1x() async throws {
        let (viewModel, _) = makeViewModel()
        let store = makeStore()
        let weekly = (0..<2).map { event("SERIES", recurring: true, start: date(2026, 5, 4 + 7 * $0, 10)) }
        let result = await makeCoordinator(FakeCalendarSource(events: weekly), store: store)
            .scanBackfill(properties: viewModel.properties, entries: [])
        let entryId = try XCTUnwrap(viewModel.confirm(result.added[0], store: store, profileId: profileId).entryId)
        let entry = try XCTUnwrap(viewModel.timeEntries.first { $0.id == entryId })
        XCTAssertEqual(entry.importExternalId, "LOCAL-SERIES", "Same value 1.x writes; see the trade-off note in confirm()")
        XCTAssertNil(entry.importCalendarId)
    }

    func testConfirmedCalendarSuggestionIsSkippedBy1xImport() async throws {
        let (viewModel, propertyId) = makeViewModel()
        let start = date(2026, 5, 4, 10)
        let store = makeStore()
        let result = await makeCoordinator(FakeCalendarSource(events: [event(start: start, hours: 1.25)]), store: store)
            .scanBackfill(properties: viewModel.properties, entries: viewModel.timeEntries)
        let s = try XCTUnwrap(result.added.first)
        XCTAssertEqual(viewModel.confirm(s, store: store, profileId: profileId).entryId != nil, true)

        // What a 1.1 device would derive from the same event.
        let detected = DetectedCalendarEntry(
            sourceExternalId: "LOCAL-OTHER-DEVICE", sourceCalendarId: "CAL-ON-OTHER-DEVICE",
            eventTitle: "Showing - Oak St", eventDate: start, propertyId: propertyId,
            category: CalendarImportService.shared.categorizeEvent(title: "showing - oak st"),
            hours: 1.25
        )
        let before = viewModel.timeEntries.count
        XCTAssertEqual(viewModel.importCalendarEntries([detected]), 0)
        XCTAssertEqual(viewModel.timeEntries.count, before)
    }
}
