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
}
