import XCTest
@testable import LandlordHours

// One-time cleanup (2.2): pending calendar suggestions the old scanner let in are re-checked
// against the new classifier. Synthetic events only.

@MainActor
final class InboxCleanupTests: CalendarCaptureTestCase {
    private let oak = RentalProperty(name: "Oak Street Duplex", address: "412 Oak St, Austin, TX 78704", propertyType: .ltr)
    private let oakAddress = "412 Oak St, Austin, TX 78704"

    private func chain() -> ClassifierChain {
        ClassifierChain(onDevice: OnDeviceClassifier(backend: UnavailableOnDeviceBackend(reason: .osTooOld)))
    }

    private func snapshot(_ id: String, _ title: String, hour: Int, attendees: Int = 0, location: String? = nil) -> CalendarEventSnapshot {
        let start = date(2026, 5, 20, hour)
        return CalendarEventSnapshot(externalId: id, eventIdentifier: "LOCAL-\(id)", title: title, location: location ?? oakAddress,
                                     start: start, end: start.addingTimeInterval(3600), occurrenceDate: start, attendeeCount: attendees)
    }

    /// What the 1.x scanner stored: everything pending, Likely, nothing about attendees.
    private func oldPending(_ s: CalendarEventSnapshot, state: Suggestion.State = .pending) -> Suggestion {
        var suggestion = calendarSuggestion(externalId: s.externalId!, start: s.start, title: s.title!, propertyId: oak.id, hours: 1)
        suggestion.sourceKey = "cal:\(s.externalId!)"   // a one-off event's key
        suggestion.confidence = 0.9
        suggestion.state = state
        return suggestion
    }

    private func run(_ events: [CalendarEventSnapshot], store: SuggestionStore) async -> InboxCleanupResult? {
        await makeCoordinator(FakeCalendarSource(events: events), store: store)
            .cleanUpPendingOnce(chain: chain(), properties: [oak], entries: [])
    }

    func testTeamSyncAtARentalStreetIsRemovedAndAPlumberStays() async throws {
        let sync = snapshot("S", "Team sync", hour: 10, attendees: 6)
        let plumber = snapshot("P", "Plumber", hour: 12)
        let store = makeStore()
        store.ingest([oldPending(sync), oldPending(plumber)], existingEntries: [], calendar: calendar)
        XCTAssertEqual(store.pending.count, 2)

        let result = await run([sync, plumber], store: store)
        XCTAssertEqual(result?.removed, 1)
        XCTAssertEqual(store.pending.map(\.title), ["Plumber"])
        XCTAssertEqual(store.suggestion(forKey: "cal:S"), nil)
        XCTAssertFalse(store.isDismissed("cal:S"), "Not a user dismissal: it must never read as a learning signal")
        XCTAssertTrue(store.contents.dismissedKeys.isEmpty)
        XCTAssertEqual(store.suggestion(forKey: "cal:P")?.confidence, 0.9, "A still-Likely item is left as it was")
    }

    func testAnItemNowBelowLikelyKeepsItsPlaceWithALowerConfidence() async throws {
        let alex = snapshot("A", "Alex", hour: 9)
        let store = makeStore()
        store.ingest([oldPending(alex)], existingEntries: [], calendar: calendar)
        let result = await run([alex], store: store)
        XCTAssertEqual(result?.updated, 1)
        let after = try XCTUnwrap(store.suggestion(forKey: "cal:A"))
        XCTAssertTrue(after.isPending)
        XCTAssertLessThan(after.confidence, ClassifierThresholds.likely)
        XCTAssertTrue(InboxLogic.badges(for: after).notSure)
        XCTAssertEqual(after.tier, .rules)
    }

    func testConfirmedAndDismissedItemsAreNeverTouched() async throws {
        let sync = snapshot("S", "Team sync", hour: 10, attendees: 6)
        let dismissed = snapshot("D", "Team sync", hour: 11, attendees: 6)
        let store = makeStore()
        let entryId = UUID()
        store.ingest([oldPending(sync), oldPending(dismissed)], existingEntries: [], calendar: calendar)
        store.markConfirmed(key: "cal:S", entryId: entryId)
        store.dismiss(key: "cal:D", reason: .notLandlordWork)
        let before = store.contents

        let result = await run([sync, dismissed], store: store)
        XCTAssertEqual(result?.removed, 0)
        XCTAssertEqual(store.contents.suggestions, before.suggestions)
        XCTAssertEqual(store.contents.dismissedKeys, before.dismissedKeys)
    }

    func testManualEntriesAreNeverTouched() async {
        let sync = snapshot("S", "Team sync", hour: 10, attendees: 6)
        let store = makeStore()
        let manual = TimeEntry(propertyId: oak.id, participant: .selfParticipant, category: .repairs, hours: 1, date: date(2026, 5, 20, 10))
        store.ingest([oldPending(sync)], existingEntries: [manual], calendar: calendar)
        let entries = [manual]
        let result = await makeCoordinator(FakeCalendarSource(events: [sync]), store: store)
            .cleanUpPendingOnce(chain: chain(), properties: [oak], entries: entries)
        XCTAssertEqual(result?.removed, 1)
        XCTAssertEqual(entries.map(\.id), [manual.id])
        XCTAssertEqual(entries.first?.hours, 1)
    }

    func testItRunsOncePerInstallAndASecondLaunchDoesNothing() async throws {
        let sync = snapshot("S", "Team sync", hour: 10, attendees: 6)
        let store = makeStore()
        store.ingest([oldPending(sync)], existingEntries: [], calendar: calendar)
        let first = await run([sync], store: store)
        XCTAssertEqual(first?.removed, 1)
        XCTAssertTrue(store.hasRunPendingCleanup)

        // A false item that arrives later is not this cleanup's business.
        store.ingest([oldPending(sync)], existingEntries: [], calendar: calendar)
        let second = await run([sync], store: store)
        XCTAssertNil(second, "Already ran")
        XCTAssertEqual(store.pending.count, 1)

        // The flag survives a relaunch (the store reads its file again).
        let reopened = SuggestionStore(userId: profileId, baseDirectory: baseDir)
        XCTAssertTrue(reopened.hasRunPendingCleanup)
    }

    func testNoCalendarAccessLeavesTheFlagUnsetSoItRunsLater() async {
        let store = makeStore()
        let result = await makeCoordinator(FakeCalendarSource(access: .denied, events: []), store: store)
            .cleanUpPendingOnce(chain: chain(), properties: [oak], entries: [])
        XCTAssertNil(result)
        XCTAssertFalse(store.hasRunPendingCleanup)
    }

    func testAPendingItemWhoseEventIsGoneIsLeftAlone() async {
        let gone = snapshot("G", "Team sync", hour: 10, attendees: 6)
        let store = makeStore()
        store.ingest([oldPending(gone)], existingEntries: [], calendar: calendar)
        let result = await run([], store: store)
        XCTAssertEqual(result?.removed, 0)
        XCTAssertEqual(store.pending.count, 1)
    }

    func testCleanupNeverRemovesAPendingItemWithALandlordWordInItsTitle() async {
        let lease = snapshot("L", "Lease signing - Dr Patel dental practice", hour: 10, attendees: 6)
        let alex = snapshot("A", "Alex", hour: 12, attendees: 4)
        let store = makeStore()
        store.ingest([oldPending(lease), oldPending(alex)], existingEntries: [], calendar: calendar)
        let result = await run([lease, alex], store: store)
        XCTAssertEqual(result?.removed, 0)
        XCTAssertEqual(Set(store.pending.map(\.title)), ["Lease signing - Dr Patel dental practice", "Alex"])
        XCTAssertGreaterThanOrEqual(store.suggestion(forKey: "cal:L")?.confidence ?? 0, ClassifierThresholds.notSure)
    }

    func testCleanupFloorBranchKeepsAHiddenItemWithATitleKeywordAtNotSure() async throws {
        // "Repair" is a landlord word of 1.0+; the wedding noise would drop it, so the rules call it
        // hidden. (2.3 F: a weaker word, "Paint" at 0.8, no longer protects an item in the cleanup.)
        let arch = snapshot("W", "Repair wedding arch", hour: 10, location: "Garden Hall, 3 Rose Ln")
        let outcome = await chain().evaluate(
            CaptureCandidate(sourceKey: "cal:W", kind: .calendar, start: arch.start, end: arch.end, title: "Repair wedding arch",
                             location: arch.location, detectedAt: arch.start),
            properties: [oak])
        guard case .skip = outcome else { return XCTFail("Setup: the rules should call this hidden, got \(outcome)") }

        let store = makeStore()
        store.ingest([oldPending(arch)], existingEntries: [], calendar: calendar)
        let result = await run([arch], store: store)
        XCTAssertEqual(result?.removed, 0)
        XCTAssertEqual(result?.updated, 1)
        let kept = try XCTUnwrap(store.suggestion(forKey: "cal:W"))
        XCTAssertTrue(kept.isPending)
        XCTAssertEqual(kept.confidence, ClassifierThresholds.notSure, accuracy: 0.0001)
    }

    func testTheCleanupAndTheLiveScanDecideAlike() async {
        let events = [
            snapshot("S", "Team sync", hour: 9, attendees: 6),
            snapshot("P", "Plumber", hour: 10),
            snapshot("A", "Alex", hour: 11, attendees: 4),
            snapshot("W", "Repair wedding arch", hour: 12, location: "Garden Hall, 3 Rose Ln"),
            snapshot("H", "HOA meeting", hour: 13, attendees: 8, location: "Community Hall, 55 Pine Rd"),
        ]
        // Live scan on an empty store, cleanup on a store holding the old scanner's pending copies.
        let live = makeStore()
        let liveResult = await makeCoordinator(FakeCalendarSource(events: events.map { later($0) }), store: live, classifier: chain())
            .scanUpcoming(properties: [oak], entries: [])
        let liveTitles = Set(liveResult.added.map(\.title))

        let old = SuggestionStore(userId: profileId + "-old", baseDirectory: baseDir)
        old.ingest(events.map { oldPending($0) }, existingEntries: [], calendar: calendar)
        _ = await makeCoordinator(FakeCalendarSource(events: events), store: old)
            .cleanUpPendingOnce(chain: chain(), properties: [oak], entries: [])
        XCTAssertEqual(Set(old.pending.map(\.title)), liveTitles)
        XCTAssertFalse(liveTitles.contains("Team sync"))
        XCTAssertTrue(liveTitles.isSuperset(of: ["Plumber", "Alex", "Repair wedding arch", "HOA meeting"]))
    }

    /// The same event a week later, inside the 7-day window.
    private func later(_ s: CalendarEventSnapshot) -> CalendarEventSnapshot {
        var copy = s
        let start = calendar.date(byAdding: .day, value: 13, to: s.start)!   // 20 May + 13 d = 2 June, inside the 7 days after `now`
        copy.start = start
        copy.end = start.addingTimeInterval(3600)
        copy.occurrenceDate = start
        return copy
    }

    func testCleanupKeepsAKeywordTitleEvenWhenTheRulesMarkedItNotRental() async throws {
        // The live scan may hide a new "HOA meeting" at a remote place; an item already in the
        // Inbox is never deleted: it drops to Not sure instead.
        let hoa = CalendarEventSnapshot(
            externalId: "HOA", eventIdentifier: "LOCAL-HOA", title: "HOA meeting", location: "Remote",
            start: date(2026, 5, 20, 10), end: date(2026, 5, 20, 11), occurrenceDate: date(2026, 5, 20, 10),
            hasRecurrenceRules: true, attendeeCount: 8)
        let team = snapshot("T", "Weekly team meeting", hour: 14, attendees: 5)
        let store = makeStore()
        var oldHoa = oldPending(hoa)
        oldHoa.sourceKey = SuggestionKey.calendar(externalId: "HOA", occurrence: hoa.start)   // a series' key
        store.ingest([oldHoa, oldPending(team)], existingEntries: [], calendar: calendar)
        let result = await run([hoa, team], store: store)

        let kept = try XCTUnwrap(store.suggestion(forKey: oldHoa.sourceKey))
        XCTAssertTrue(kept.isPending)
        XCTAssertEqual(kept.confidence, ClassifierThresholds.notSure, accuracy: 0.0001)
        XCTAssertNil(store.suggestion(forKey: "cal:T"), "No landlord word: removed")
        XCTAssertEqual(result?.removed, 1)
    }

    // MARK: - 2.3 package F: the second cleanup, series dismissal, calendar choice

    func testTheSecondCleanupRunsAfterTheFirstAndRemovesWhatTheGateHides() async throws {
        // On 2.2 the first pass already ran; a 1:1 and a deck review were kept as "Not sure".
        let oneOnOne = snapshot("O", "Alex / Jordan", hour: 9, location: "")
        let deck = snapshot("K", "2026 Deck Q4R", hour: 10, attendees: 4, location: "")
        let plumber = snapshot("P", "Plumber", hour: 12, location: "")
        let window = snapshot("W", "Window", hour: 13, location: "")
        let store = makeStore()
        store.ingest([oldPending(oneOnOne), oldPending(deck), oldPending(plumber), oldPending(window)], existingEntries: [], calendar: calendar)
        store.markPendingCleanupDone()
        XCTAssertTrue(store.hasRunPendingCleanup)
        XCTAssertFalse(store.hasRunPendingCleanupV2)

        let result = await run([oneOnOne, deck, plumber, window], store: store)
        XCTAssertEqual(result?.removed, 3, "1:1, deck review and a bare weak word leave")
        XCTAssertEqual(store.pending.map(\.title), ["Plumber"])
        XCTAssertTrue(store.hasRunPendingCleanupV2)
        XCTAssertTrue(store.contents.dismissedKeys.isEmpty, "The system's call, never a user dismissal")
        let again = await run([oneOnOne], store: store)
        XCTAssertNil(again, "Once per install")
        XCTAssertTrue(SuggestionStore(userId: profileId, baseDirectory: baseDir).hasRunPendingCleanupV2)
    }

    func testTheSecondCleanupNeverDeletesAnItemWithACarryingTitleWord() async throws {
        // A rental word of 1.0+ in the title, even with every invite signal against it: kept.
        let hoa = snapshot("H", "HOA board", hour: 9, attendees: 8, location: "")
        let lease = snapshot("L", "Lease renewal - team", hour: 10, attendees: 6, location: "Remote")
        let store = makeStore()
        store.ingest([oldPending(hoa), oldPending(lease)], existingEntries: [], calendar: calendar)
        let result = await run([hoa, lease], store: store)
        XCTAssertEqual(result?.removed, 0)
        XCTAssertEqual(Set(store.pending.map(\.title)), ["HOA board", "Lease renewal - team"])
    }

    func testAFreshInstallRunsOnlyOnePass() async {
        let store = makeStore()
        let result = await run([], store: store)
        XCTAssertEqual(result, InboxCleanupResult())
        XCTAssertTrue(store.hasRunPendingCleanup)
        XCTAssertTrue(store.hasRunPendingCleanupV2)
    }

    private func series(_ id: String, _ title: String, days: [Int], container: String = "WORK") -> [Suggestion] {
        days.map { day in
            let start = date(2026, 5, day, 9)
            var s = calendarSuggestion(externalId: id, start: start, title: title, propertyId: nil, hours: 0.5)
            s.containerId = container
            s.confidence = 0.4
            return s
        }
    }

    func testNotRentalWorkOnOneOccurrenceHidesTheWholeSeries() throws {
        let store = makeStore()
        let weekly = series("SER", "Alex / Jordan", days: [4, 11, 18])
        let other = series("ONE", "Plumber", days: [5], container: "HOME")
        store.ingest(weekly + other, existingEntries: [], calendar: calendar)
        XCTAssertEqual(weekly[0].seriesId, "cal:SER")

        store.dismiss(key: weekly[1].sourceKey, reason: .notLandlordWork)
        XCTAssertEqual(store.pending.map(\.title), ["Plumber"], "Every pending occurrence leaves")
        XCTAssertTrue(store.isSeriesDismissed("cal:SER"))

        // A later occurrence is never suggested, and a scan doesn't even classify it.
        let next = series("SER", "Alex / Jordan", days: [25])
        XCTAssertFalse(store.wouldIngest(sourceKey: next[0].sourceKey))
        XCTAssertTrue(store.ingest(next, existingEntries: [], calendar: calendar).isEmpty)
        // The dismissal counts once against the calendar.
        XCTAssertEqual(store.feedback(forCalendar: "WORK").notRental, 1)

        // Undo brings the series back, and the count with it.
        store.restorePending(keys: [weekly[1].sourceKey])
        XCTAssertEqual(store.pending.filter { $0.title == "Alex / Jordan" }.count, 3)
        XCTAssertFalse(store.isSeriesDismissed("cal:SER"))
        XCTAssertEqual(store.feedback(forCalendar: "WORK").notRental, 0)
        XCTAssertTrue(store.wouldIngest(sourceKey: next[0].sourceKey))
    }

    func testAOneOffDismissalHidesOnlyItself() {
        let store = makeStore()
        var one = calendarSuggestion(externalId: "ONEOFF", start: date(2026, 5, 4, 9), title: "Deck", propertyId: nil)
        one.sourceKey = SuggestionKey.calendar(externalId: "ONEOFF")
        XCTAssertNil(one.seriesId)
        store.ingest([one], existingEntries: [], calendar: calendar)
        store.dismiss(key: one.sourceKey, reason: .notLandlordWork)
        XCTAssertTrue(store.contents.dismissedSeries?.isEmpty ?? true)
    }

    func testACalendarWithThreeDismissalsAndNoConfirmsIsOfferedOnce() {
        let store = makeStore()
        let items = (0..<4).flatMap { series("S\($0)", "Sync \($0)", days: [4 + $0]) }
        store.ingest(items, existingEntries: [], calendar: calendar)
        for item in items.prefix(2) { store.dismiss(key: item.sourceKey, reason: .notLandlordWork) }
        XCTAssertTrue(store.calendarsToOfferQuieting(excluded: []).isEmpty, "Two is not enough")
        store.dismiss(key: items[2].sourceKey, reason: .notLandlordWork)
        XCTAssertEqual(store.calendarsToOfferQuieting(excluded: []), ["WORK"])
        XCTAssertTrue(store.calendarsToOfferQuieting(excluded: ["WORK"]).isEmpty, "Already turned off")
        store.markQuietPromptShown(calendar: "WORK")
        XCTAssertTrue(store.calendarsToOfferQuieting(excluded: []).isEmpty, "One time only")
        // Counts are on this device, in the profile's file.
        XCTAssertEqual(SuggestionStore(userId: profileId, baseDirectory: baseDir).feedback(forCalendar: "WORK").notRental, 3)
    }

    func testAConfirmOnTheCalendarMeansItIsNeverOffered() {
        let store = makeStore()
        let items = (0..<4).flatMap { series("S\($0)", "Thing \($0)", days: [4 + $0]) }
        store.ingest(items, existingEntries: [], calendar: calendar)
        store.markConfirmed(key: items[3].sourceKey, entryId: UUID())
        for item in items.prefix(3) { store.dismiss(key: item.sourceKey, reason: .notLandlordWork) }
        XCTAssertEqual(store.feedback(forCalendar: "WORK").confirmed, 1)
        XCTAssertTrue(store.calendarsToOfferQuieting(excluded: []).isEmpty)
        XCTAssertEqual(store.feedback(forCalendar: "WORK").notRental, 3)
    }

    func testTurningACalendarOffRemovesItsPendingItemsWithoutDismissingThem() {
        let store = makeStore()
        store.ingest(series("A", "Sync", days: [4]) + series("B", "Plumber", days: [5], container: "HOME"), existingEntries: [], calendar: calendar)
        XCTAssertEqual(store.removePending(inCalendars: ["WORK"]), 1)
        XCTAssertEqual(store.pending.map(\.title), ["Plumber"])
        XCTAssertTrue(store.contents.dismissedKeys.isEmpty)
    }

    func testTheDetectorSkipsTurnedOffCalendars() async throws {
        let work = CalendarEventSnapshot(externalId: "W", calendarId: "WORK", title: "Plumber", start: date(2026, 5, 20, 9), end: date(2026, 5, 20, 10))
        let home = CalendarEventSnapshot(externalId: "H", calendarId: "HOME", title: "Plumber", start: date(2026, 5, 20, 11), end: date(2026, 5, 20, 12))
        let source = ListingCalendarSource(events: [work, home], calendars: ["WORK", "HOME"])
        let off = CalendarDetector(source: source, excludedCalendars: { ["WORK"] }, clock: { [now] in now! }, calendar: calendar)
        let found = try await off.detect(in: DateInterval(start: date(2026, 5, 1), end: date(2026, 5, 31)))
        XCTAssertEqual(found.map(\.containerId), ["HOME"])
        let allOn = CalendarDetector(source: source, excludedCalendars: { [] }, clock: { [now] in now! }, calendar: calendar)
        XCTAssertNil(allOn.scannedCalendarIds(), "Nothing off: every calendar, new ones included")
    }

    func testCalendarChoiceIsStoredPerProfile() {
        let defaults = UserDefaults(suiteName: "inbox-quiet-\(UUID().uuidString)")!
        InboxQuietCalendars.setChecked(false, calendarId: "WORK", profileId: "p1", defaults: defaults)
        XCTAssertEqual(InboxQuietCalendars.excluded(profileId: "p1", defaults: defaults), ["WORK"])
        XCTAssertTrue(InboxQuietCalendars.excluded(profileId: "p2", defaults: defaults).isEmpty)
        InboxQuietCalendars.setChecked(true, calendarId: "WORK", profileId: "p1", defaults: defaults)
        XCTAssertTrue(InboxQuietCalendars.excluded(profileId: "p1", defaults: defaults).isEmpty)
    }

    func testAWorkCalendarIsAnyAccountThatIsNotAConsumerMailDomain() {
        XCTAssertTrue(WorkCalendarRule.isWork(sourceIsExchange: true, accountTitle: "Exchange"))
        XCTAssertTrue(WorkCalendarRule.isWork(sourceIsExchange: false, accountTitle: "sam@example-corp.com"))
        for personal in ["sam@gmail.com", "Sam@iCloud.com", "iCloud", "Subscribed Calendars", "Other", nil] as [String?] {
            XCTAssertFalse(WorkCalendarRule.isWork(sourceIsExchange: false, accountTitle: personal), personal ?? "nil")
        }
    }

    func testNotSureItemsLeaveTheMainListAndTheCount() {
        var sure = calendarSuggestion(externalId: "S", start: date(2026, 5, 20, 9), propertyId: oak.id)
        sure.confidence = 0.9
        var maybe = calendarSuggestion(externalId: "M", start: date(2026, 5, 20, 11), title: "Install shelves", propertyId: nil)
        maybe.confidence = 0.45
        let later = date(2026, 6, 1)
        XCTAssertEqual(InboxLogic.visible([sure, maybe], now: later).map(\.title), [sure.title])
        XCTAssertEqual(InboxLogic.mainList([sure, maybe]).map(\.title), [sure.title])
        XCTAssertEqual(InboxLogic.maybeList([sure, maybe], now: later).map(\.title), ["Install shelves"])
        XCTAssertEqual(InboxLogic.sections([sure, maybe], now: later, calendar: calendar).flatMap(\.items).count, 1)
        // Today's "To confirm" count reads the same list.
        XCTAssertEqual(TodayConfirm.count(visible: InboxLogic.visible([sure, maybe], now: later), rentalID: nil), 1)
    }
}

/// A calendar source that also lists its calendars (Settings › Calendars).
final class ListingCalendarSource: CalendarEventSource {
    let events: [CalendarEventSnapshot]
    let ids: [String]
    init(events: [CalendarEventSnapshot], calendars: [String]) { self.events = events; self.ids = calendars }
    func accessState() -> CalendarAccess { .fullAccess }
    func requestFullAccess() async -> CalendarAccess { .fullAccess }
    func events(in interval: DateInterval, calendarIds: Set<String>?) -> [CalendarEventSnapshot] {
        events.filter { $0.start < interval.end && $0.end > interval.start && (calendarIds == nil || calendarIds!.contains($0.calendarId)) }
    }
    func calendars() -> [CalendarInfo] { ids.map { CalendarInfo(id: $0, title: $0, account: "test", color: nil, isWork: false) } }
}

