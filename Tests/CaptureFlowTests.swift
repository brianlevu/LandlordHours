import XCTest
@testable import LandlordHours

// MARK: - Fakes for the capture seams

final class FakeCaptureDetector: CaptureDetector {
    let kind: Suggestion.Kind
    var candidates: [CaptureCandidate]
    private(set) var calls = 0

    init(kind: Suggestion.Kind = .calendar, candidates: [CaptureCandidate]) {
        self.kind = kind
        self.candidates = candidates
    }

    func detect(in interval: DateInterval) async throws -> [CaptureCandidate] {
        calls += 1
        return candidates.filter { interval.contains($0.start) }
    }
}

final class FakeCaptureClassifier: CaptureClassifier {
    var result: (CaptureCandidate) -> CaptureClassification

    init(result: @escaping (CaptureCandidate) -> CaptureClassification) {
        self.result = result
    }

    func classify(_ candidate: CaptureCandidate, properties: [RentalProperty]) async -> CaptureClassification {
        result(candidate)
    }
}

final class FakeCaptureNotifier: CaptureNotifier {
    private(set) var scheduled: [(keys: [String], profileId: String)] = []
    private(set) var cancelled: [String] = []

    func schedule(_ suggestions: [Suggestion], profileId: String) async {
        scheduled.append((suggestions.map(\.sourceKey), profileId))
    }

    func cancel(sourceKeys: [String]) async {
        cancelled.append(contentsOf: sourceKeys)
    }
}

final class FakeBackgroundTasks: BackgroundTaskRunning {
    private(set) var begun: [String] = []
    private(set) var ended: [Int] = []
    private var next = 1

    @MainActor func beginTask(named name: String, expiration: @escaping @MainActor () -> Void) -> Int {
        begun.append(name)
        defer { next += 1 }
        return next
    }

    @MainActor func endTask(_ id: Int) { ended.append(id) }
}

// MARK: - Shared fixture

@MainActor
class CaptureTestCase: XCTestCase {
    var authSnapshot: AuthStateSnapshot!
    var profileId = ""
    var baseDir: URL!
    var calendar = Calendar(identifier: .gregorian)

    override func setUp() async throws {
        try await super.setUp()
        authSnapshot = AuthStateSnapshot.capture()
        AuthStateSnapshot.clearAll()
        profileId = "local-capture-\(UUID().uuidString.prefix(8))"
        UserDefaults.standard.set(profileId, forKey: ProfileKeys.localProfileId)
        baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("capture-\(UUID().uuidString)")
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: UserScope.key("LandlordHours.celebratedMilestones", userId: profileId))
        UserDefaults.standard.removeObject(forKey: UserScope.key("LandlordHours.properties", userId: profileId))
        UserDefaults.standard.removeObject(forKey: UserScope.key("LandlordHours.entries", userId: profileId))
        UserDefaults.standard.removeObject(forKey: CaptureNotificationAction.pendingEditKey)
        AppViewModel.clearScopedAccountData(for: profileId)
        try? FileManager.default.removeItem(at: baseDir)
        authSnapshot.restore()
        try await super.tearDown()
    }

    func makeViewModel() -> (AppViewModel, UUID) {
        let viewModel = AppViewModel()
        viewModel.suppressCelebrations = true
        viewModel.addProperty(name: "Oak", address: "1 Oak St", type: .ltr)
        return (viewModel, viewModel.properties[0].id)
    }

    func makeStore() -> SuggestionStore {
        SuggestionStore(userId: profileId, baseDirectory: baseDir)
    }

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func calendarSuggestion(
        externalId: String = "EVT-1",
        start: Date,
        title: String = "Showing - Oak St",
        propertyId: UUID?,
        hours: Double? = 1.5,
        category: ActivityCategory? = .leasing,
        backfill: Bool = false
    ) -> Suggestion {
        Suggestion(
            sourceKey: SuggestionKey.calendar(externalId: externalId, occurrence: start),
            kind: .calendar,
            detectedAt: start.addingTimeInterval(3600),
            start: start,
            end: start.addingTimeInterval((hours ?? 1) * 3600),
            title: title,
            externalId: externalId,
            containerId: "CAL-1",
            proposedPropertyId: propertyId,
            proposedCategory: category,
            proposedHours: hours,
            hoursBasis: .scheduled,
            confidence: 0.9,
            tier: .rules,
            isBackfill: backfill
        )
    }
}

// MARK: - Suggestion store

@MainActor
final class SuggestionStoreTests: CaptureTestCase {
    func testFileLivesPerProfileUnderCaptureAndPersists() {
        let store = makeStore()
        XCTAssertEqual(store.fileURL.lastPathComponent, "suggestions.json")
        XCTAssertEqual(store.fileURL.deletingLastPathComponent().lastPathComponent, profileId)
        XCTAssertEqual(SuggestionStore.defaultBaseDirectory.lastPathComponent, "Capture")
        XCTAssertEqual(SuggestionStore.defaultBaseDirectory.deletingLastPathComponent().lastPathComponent, "Application Support")

        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: UUID())
        store.ingest([s], existingEntries: [], calendar: calendar)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))

        let reopened = makeStore()
        XCTAssertEqual(reopened.pending.map(\.sourceKey), [s.sourceKey])

        SuggestionStore.removeAll(forUserId: profileId, baseDirectory: baseDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testDedupeByKeyKeepsIdAndUpdatesPendingCopy() {
        let store = makeStore()
        let first = calendarSuggestion(start: date(2026, 3, 2), propertyId: UUID())
        XCTAssertEqual(store.ingest([first, first], existingEntries: [], calendar: calendar).count, 1)
        var moved = first
        moved.id = UUID()
        moved.title = "Showing - Oak St (moved)"
        XCTAssertTrue(store.ingest([moved], existingEntries: [], calendar: calendar).isEmpty, "Not new")
        XCTAssertEqual(store.suggestions.count, 1)
        XCTAssertEqual(store.suggestions[0].id, first.id)
        XCTAssertEqual(store.suggestions[0].title, "Showing - Oak St (moved)")
    }

    func testDismissedKeysAreRememberedAndPruned() {
        let store = makeStore()
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: UUID())
        store.ingest([s], existingEntries: [], calendar: calendar)
        store.dismiss(key: s.sourceKey, reason: .notLandlordWork, now: date(2026, 3, 3))
        store.dismiss(key: s.sourceKey, reason: .notLandlordWork, now: date(2026, 3, 4)) // repeat is safe
        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertTrue(store.ingest([s], existingEntries: [], calendar: calendar).isEmpty, "A dismissed event never comes back")
        XCTAssertTrue(makeStore().isDismissed(s.sourceKey), "Remembered on disk")

        store.pruneResolved(olderThan: date(2027, 1, 1))
        XCTAssertFalse(store.isDismissed(s.sourceKey))
        XCTAssertTrue(store.suggestions.isEmpty)
    }

    func testMuteRulesSkipAndDismissMatchingItems() {
        let store = makeStore()
        let dentist = calendarSuggestion(externalId: "D", start: date(2026, 3, 2), title: "Dentist", propertyId: nil)
        store.ingest([dentist], existingEntries: [], calendar: calendar)
        store.addMuteRule(CaptureMuteRule(match: .titleContains, value: "dentist"))
        XCTAssertTrue(store.pending.isEmpty)
        let again = calendarSuggestion(externalId: "D2", start: date(2026, 3, 9), title: "DENTIST cleaning", propertyId: nil)
        XCTAssertTrue(store.ingest([again], existingEntries: [], calendar: calendar).isEmpty)
        let otherCal = Suggestion(sourceKey: "cal:X:1", kind: .calendar, detectedAt: Date(), start: date(2026, 3, 10),
                                  title: "Anything", containerId: "WORK")
        store.addMuteRule(CaptureMuteRule(match: .containerId, value: "WORK"))
        XCTAssertTrue(store.ingest([otherCal], existingEntries: [], calendar: calendar).isEmpty)
        XCTAssertEqual(makeStore().muteRules.count, 2)
    }

    func testUnreadableFileStartsCleanAndKeepsCopy() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        let reopened = makeStore()
        XCTAssertTrue(reopened.suggestions.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: store.fileURL.deletingLastPathComponent().path)
        XCTAssertTrue(files.contains { $0.hasPrefix("suggestions.corrupt-") })
    }

    func testFakePipelineDetectClassifyIngestNotify() async throws {
        let propertyId = UUID()
        let start = date(2026, 3, 2)
        let detector = FakeCaptureDetector(candidates: [
            CaptureCandidate(sourceKey: SuggestionKey.calendar(externalId: "A", occurrence: start), kind: .calendar,
                             start: start, end: start.addingTimeInterval(7200), title: "Repair - Oak", detectedAt: start),
            CaptureCandidate(sourceKey: SuggestionKey.calendar(externalId: "B", occurrence: start), kind: .calendar,
                             start: start, title: "Lunch", detectedAt: start)
        ])
        let classifier = FakeCaptureClassifier { candidate in
            let work = candidate.title.contains("Oak")
            return CaptureClassification(isLandlordWork: work, confidence: work ? 0.9 : 0.1,
                                         propertyId: work ? propertyId : nil, category: work ? .repairs : nil,
                                         hours: work ? 2 : nil, hoursBasis: work ? .scheduled : .none,
                                         tier: .rules, evidence: work ? ["title mentions property"] : [])
        }
        let notifier = FakeCaptureNotifier()
        let store = makeStore()

        let found = try await detector.detect(in: DateInterval(start: date(2026, 3, 1), end: date(2026, 3, 3)))
        var suggestions: [Suggestion] = []
        for candidate in found {
            let classification = await classifier.classify(candidate, properties: [])
            guard classification.isLandlordWork else { continue }
            suggestions.append(Suggestion(candidate: candidate, classification: classification))
        }
        let added = store.ingest(suggestions, existingEntries: [], calendar: calendar)
        await notifier.schedule(added, profileId: profileId)

        XCTAssertEqual(detector.calls, 1)
        XCTAssertEqual(notifier.scheduled.first?.keys, [found[0].sourceKey])
        XCTAssertEqual(notifier.scheduled.first?.profileId, profileId)
        XCTAssertEqual(store.pending.first?.proposedHours, 2)
        XCTAssertEqual(store.pending.first?.isPreselectable, true)
    }
}

// MARK: - Reconciliation: legacy imports and hand-logged hours

@MainActor
final class CaptureReconciliationTests: CaptureTestCase {
    private func legacyImport(propertyId: UUID, date: Date, hours: Double = 1.5, notes: String = "Showing - Oak St") -> TimeEntry {
        // Exactly what 1.x `importCalendarEntries` writes: device-local eventIdentifier, title in notes.
        TimeEntry(propertyId: propertyId, participant: .selfParticipant, category: .leasing, hours: hours,
                  date: date, notes: notes, importSource: "calendar",
                  importExternalId: "LOCAL-EVENT-ID-SHARED-BY-REPEATS", importCalendarId: "CAL-1")
    }

    func testLegacyImportOnPropertyDayHoursTitleIsAlreadyRecorded() {
        let propertyId = UUID()
        let start = date(2026, 3, 2, 10)
        let legacy = legacyImport(propertyId: propertyId, date: date(2026, 3, 2, 10))
        let store = makeStore()
        let s = calendarSuggestion(start: start, title: "  showing -  OAK st ", propertyId: propertyId)
        XCTAssertTrue(store.ingest([s], existingEntries: [legacy], calendar: calendar).isEmpty)
        XCTAssertEqual(store.suggestion(forKey: s.sourceKey)?.state, .confirmed(entryId: legacy.id))
    }

    func testLegacyMatchNeedsSameDayHoursTitleAndProperty() {
        let propertyId = UUID()
        let legacy = legacyImport(propertyId: propertyId, date: date(2026, 3, 2))
        let entries = [legacy]
        // Next occurrence of the recurring event: 1.x imported only the first.
        let nextWeek = calendarSuggestion(start: date(2026, 3, 9), propertyId: propertyId)
        let otherHours = calendarSuggestion(externalId: "E2", start: date(2026, 3, 2), propertyId: propertyId, hours: 3)
        let otherTitle = calendarSuggestion(externalId: "E3", start: date(2026, 3, 2), title: "Inspection", propertyId: propertyId)
        let otherProperty = calendarSuggestion(externalId: "E4", start: date(2026, 3, 2), propertyId: UUID())
        for s in [nextWeek, otherHours, otherTitle, otherProperty] {
            XCTAssertNil(CaptureReconciler.legacyImportMatch(for: s, in: entries, calendar: calendar), s.sourceKey)
        }
        // A confirmed 2.0 calendar entry is not a legacy import.
        var confirmed = legacy
        confirmed.confirmedAt = Date()
        let same = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId)
        XCTAssertNil(CaptureReconciler.legacyImportMatch(for: same, in: [confirmed], calendar: calendar))
        XCTAssertNotNil(CaptureReconciler.legacyImportMatch(for: same, in: entries, calendar: calendar))
    }

    func testBackfillMatchingManualHoursIsMarkedAndNeverPreselected() {
        let propertyId = UUID()
        let manual = TimeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs,
                               hours: 2, date: date(2026, 2, 10, 16))
        let store = makeStore()
        let sameDay = calendarSuggestion(externalId: "B1", start: date(2026, 2, 10, 9), title: "Plumber visit",
                                         propertyId: propertyId, backfill: true)
        let otherDay = calendarSuggestion(externalId: "B2", start: date(2026, 2, 11, 9), title: "Plumber visit",
                                          propertyId: propertyId, backfill: true)
        store.ingest([sameDay, otherDay], existingEntries: [manual], calendar: calendar)
        let marked = store.suggestion(forKey: sameDay.sourceKey)!
        XCTAssertTrue(marked.isPending, "Still shown — the user decides")
        XCTAssertTrue(marked.mightAlreadyBeLogged)
        XCTAssertFalse(marked.isPreselectable)
        let clean = store.suggestion(forKey: otherDay.sourceKey)!
        XCTAssertFalse(clean.mightAlreadyBeLogged)
        XCTAssertTrue(clean.isPreselectable)

        // A manual entry logged later is picked up by reconcile.
        let later = TimeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs,
                              hours: 1, date: date(2026, 2, 11, 18))
        store.reconcile(with: [manual, later], calendar: calendar)
        XCTAssertTrue(store.suggestion(forKey: otherDay.sourceKey)!.mightAlreadyBeLogged)
    }

    func testEntryConfirmedOnAnotherDeviceResolvesSuggestion() {
        let propertyId = UUID()
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId)
        let store = makeStore()
        store.ingest([s], existingEntries: [], calendar: calendar)
        let fromOtherDevice = TimeEntry(id: s.entryId(profileId: profileId), propertyId: propertyId, participant: .selfParticipant,
                                        category: .leasing, hours: 1.5, date: s.start, importSource: "calendar",
                                        confirmedAt: Date(), sourceKey: s.sourceKey)
        store.reconcile(with: [fromOtherDevice], calendar: calendar)
        XCTAssertEqual(store.suggestion(forKey: s.sourceKey)?.state, .confirmed(entryId: s.entryId(profileId: profileId)))
    }
}

// MARK: - confirm()

@MainActor
final class CaptureConfirmTests: CaptureTestCase {
    func testConfirmSavesProvenanceAndDerivedId() throws {
        let (viewModel, propertyId) = makeViewModel()
        let store = makeStore()
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId, backfill: true)
        store.ingest([s], existingEntries: viewModel.timeEntries, calendar: calendar)
        let now = date(2026, 3, 5)

        let result = viewModel.confirm(s, store: store, now: now)
        XCTAssertEqual(result, .created(entryId: s.entryId(profileId: profileId)))
        let entry = try XCTUnwrap(viewModel.timeEntries.first { $0.id == s.entryId(profileId: profileId) })
        XCTAssertEqual(entry.importSource, "calendar")
        XCTAssertEqual(entry.source.displayName, "Calendar import")
        XCTAssertEqual(entry.confirmedAt, now)
        XCTAssertEqual(entry.detectedAt, s.detectedAt)
        XCTAssertEqual(entry.sourceKey, s.sourceKey)
        XCTAssertEqual(entry.sourceDetail, "backfill")
        XCTAssertEqual(entry.importExternalId, "EVT-1")
        XCTAssertNil(entry.importCalendarId, "Device-local calendar ids would defeat 1.1's title check")
        XCTAssertEqual(entry.notes, "Showing - Oak St", "Title kept so a 1.1 import recognises the event")
        XCTAssertEqual(store.suggestion(forKey: s.sourceKey)?.state, .confirmed(entryId: s.entryId(profileId: profileId)))

        // Persisted to the profile's store.
        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: UserScope.key("LandlordHours.entries", userId: profileId)))
        let saved = try JSONDecoder().decode([TimeEntry].self, from: data)
        XCTAssertEqual(saved.filter { $0.id == s.entryId(profileId: profileId) }.count, 1)
    }

    func testDoubleConfirmIsIdempotent() {
        let (viewModel, propertyId) = makeViewModel()
        let store = makeStore()
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId)
        store.ingest([s], existingEntries: [], calendar: calendar)
        XCTAssertEqual(viewModel.confirm(s, store: store), .created(entryId: s.entryId(profileId: profileId)))
        XCTAssertEqual(viewModel.confirm(s, store: store), .alreadyRecorded(entryId: s.entryId(profileId: profileId)))
        XCTAssertEqual(viewModel.confirm(s, edits: SuggestionEdits(hours: 9), store: store), .alreadyRecorded(entryId: s.entryId(profileId: profileId)))
        XCTAssertEqual(viewModel.timeEntries.filter { $0.sourceKey == s.sourceKey }.count, 1)
        XCTAssertEqual(viewModel.timeEntries.first { $0.id == s.entryId(profileId: profileId) }?.hours, 1.5)
    }

    func testInterruptedConfirmRepairsSuggestionWithoutSecondEntry() {
        let (viewModel, propertyId) = makeViewModel()
        let store = makeStore()
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId)
        store.ingest([s], existingEntries: [], calendar: calendar)
        viewModel.confirm(s, store: nil) // entry saved, suggestion never marked (crash between writes)
        XCTAssertTrue(store.suggestion(forKey: s.sourceKey)!.isPending)
        XCTAssertEqual(viewModel.confirm(s, store: store), .alreadyRecorded(entryId: s.entryId(profileId: profileId)))
        XCTAssertEqual(store.suggestion(forKey: s.sourceKey)?.state, .confirmed(entryId: s.entryId(profileId: profileId)))
        XCTAssertEqual(viewModel.timeEntries.count, 1)
    }

    func testTwoDevicesConfirmingOneEventMergeToOneEntry() {
        let (deviceA, propertyId) = makeViewModel()
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId)
        deviceA.confirm(s, now: date(2026, 3, 2, 12))

        // Device B: same event, same iCloud calendar, confirmed independently (different edits).
        var entryOnB = TimeEntry(id: s.entryId(profileId: profileId), propertyId: propertyId, participant: .selfParticipant,
                                 category: .leasing, hours: 2, date: s.start, importSource: "calendar",
                                 detectedAt: s.detectedAt, confirmedAt: date(2026, 3, 2, 13), sourceKey: s.sourceKey)
        entryOnB.modifiedAt = Date().addingTimeInterval(60)
        XCTAssertEqual(entryOnB.id, deviceA.timeEntries.first?.id, "Same key → same id → same CloudKit record")

        deviceA.syncDidReceiveEntries([entryOnB])
        XCTAssertEqual(deviceA.timeEntries.filter { $0.sourceKey == s.sourceKey }.count, 1, "Merged, not double-counted")
        XCTAssertEqual(deviceA.timeEntries.count, 1)
        XCTAssertEqual(deviceA.confirm(s), .alreadyRecorded(entryId: s.entryId(profileId: profileId)))
    }

    func testConfirmCoveredByLegacyImportDoesNotDoubleCount() {
        let (viewModel, propertyId) = makeViewModel()
        let start = date(2026, 3, 2)
        let legacy = TimeEntry(propertyId: propertyId, participant: .selfParticipant, category: .leasing, hours: 1.5,
                               date: start, notes: "Showing - Oak St", importSource: "calendar", importExternalId: "LOCAL")
        viewModel.syncDidReceiveEntries([legacy])
        let s = calendarSuggestion(start: start, propertyId: propertyId)
        XCTAssertEqual(viewModel.confirm(s), .alreadyRecorded(entryId: legacy.id))
        XCTAssertEqual(viewModel.timeEntries.count, 1)
    }

    func testMissingValuesNeedInputAndSaveNothing() {
        let (viewModel, propertyId) = makeViewModel()
        let receipt = Suggestion(sourceKey: SuggestionKey.receipt(data: Data("r".utf8)), kind: .receipt,
                                 detectedAt: Date(), start: date(2026, 3, 2), title: "Hardware store",
                                 proposedPropertyId: propertyId, proposedCategory: .repairs)
        XCTAssertEqual(viewModel.confirm(receipt), .needsInput(missing: [.hours]))
        let unknownProperty = calendarSuggestion(start: date(2026, 3, 2), propertyId: UUID())
        XCTAssertEqual(viewModel.confirm(unknownProperty), .needsInput(missing: [.property]))
        XCTAssertTrue(viewModel.timeEntries.isEmpty)

        XCTAssertEqual(viewModel.confirm(receipt, edits: SuggestionEdits(hours: 1)), .created(entryId: receipt.entryId(profileId: profileId)))
        XCTAssertEqual(viewModel.timeEntries.first?.importSource, "receipt")
    }

    /// Runs the real 1.x calendar import (`importCalendarEntries`, unchanged in 2.0) over the
    /// same event after a 2.0 confirm: a 1.1 iPad with every row pre-selected must import nothing.
    func test11CalendarImportSkipsA20ConfirmedEvent() {
        let (viewModel, propertyId) = makeViewModel()
        var s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId)
        s.legacyEventIdentifier = "IPHONE-LOCAL-EVENT-ID"
        XCTAssertEqual(viewModel.confirm(s), .created(entryId: s.entryId(profileId: profileId)))

        // Same device: 1.x matches on eventIdentifier (importExternalId), title differs on purpose.
        let sameDevice = DetectedCalendarEntry(sourceExternalId: "IPHONE-LOCAL-EVENT-ID", sourceCalendarId: "IPHONE-CAL",
                                               eventTitle: "Renamed later", eventDate: s.start,
                                               propertyId: propertyId, category: .repairs, hours: 7)
        XCTAssertEqual(viewModel.importCalendarEntries([sameDevice]), 0, "already imported (eventIdentifier)")

        // Another device: different device-local ids, so 1.x falls back to property/category/
        // hours/start/title — which the 2.0 entry carries.
        let otherDevice = DetectedCalendarEntry(sourceExternalId: "IPAD-LOCAL-EVENT-ID", sourceCalendarId: "IPAD-CAL",
                                                eventTitle: "showing - oak st", eventDate: s.start,
                                                propertyId: propertyId, category: .leasing, hours: 1.5)
        XCTAssertEqual(viewModel.importCalendarEntries([otherDevice]), 0, "already imported (title match)")
        XCTAssertEqual(viewModel.timeEntries.count, 1)
    }

    func testRecordIdsArePerProfileAndStableAcrossDevices() {
        let key = SuggestionKey.calendar(externalId: "SHARED", occurrence: date(2026, 3, 2))
        let profileA = CaptureIdentity.entryId(profileId: "local-a", sourceKey: key)
        let profileB = CaptureIdentity.entryId(profileId: "local-b", sourceKey: key)
        XCTAssertNotEqual(profileA, profileB, "Two profiles in one iCloud zone never share a record")
        // Same profile, two devices: computed independently, identical.
        XCTAssertEqual(CaptureIdentity.entryId(profileId: "local-a", sourceKey: key), profileA)

        // End to end: profile B confirming the same event does not collide with profile A's entry.
        let (viewModel, propertyId) = makeViewModel()
        let s = calendarSuggestion(externalId: "SHARED", start: date(2026, 3, 2), propertyId: propertyId)
        let entryOfOtherProfile = TimeEntry(id: s.entryId(profileId: "local-other"), propertyId: propertyId,
                                            participant: .selfParticipant, category: .leasing, hours: 1.5,
                                            date: date(2026, 4, 1), importSource: "calendar",
                                            confirmedAt: Date())
        XCTAssertNotEqual(entryOfOtherProfile.id, s.entryId(profileId: profileId))
        XCTAssertEqual(viewModel.confirm(s), .created(entryId: s.entryId(profileId: profileId)))
    }

    func testDismissNeverTouchesEntries() {
        let (viewModel, propertyId) = makeViewModel()
        let store = makeStore()
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId)
        store.ingest([s], existingEntries: [], calendar: calendar)
        viewModel.dismiss(s, store: store)
        XCTAssertTrue(viewModel.timeEntries.isEmpty)
        XCTAssertTrue(store.isDismissed(s.sourceKey))
    }
}

// MARK: - Single writer: host + notification actions with no scene

@MainActor
final class AppModelHostTests: CaptureTestCase {
    private func makeHost() -> (AppModelHost, AppViewModel, UUID, FakeBackgroundTasks) {
        let viewModel = AppViewModel()
        viewModel.addProperty(name: "Oak", address: "1 Oak St", type: .ltr)
        viewModel.activeCelebration = nil
        let tasks = FakeBackgroundTasks()
        let host = AppModelHost(viewModel: viewModel, backgroundTasks: tasks, suggestionBaseDirectory: baseDir)
        return (host, viewModel, viewModel.properties[0].id, tasks)
    }

    private func logItRequest(_ s: Suggestion, profileId: String) -> NotificationActionRequest {
        NotificationActionRequest(
            actionIdentifier: CaptureNotificationAction.logIt,
            categoryIdentifier: CaptureNotificationAction.categoryIdentifier,
            userInfo: CaptureNotificationAction.userInfo(profileId: profileId, sourceKey: s.sourceKey)
        )
    }

    func testBackgroundLogItWritesThroughHostWithNoSceneAndCompletesAfterSave() async throws {
        let (host, viewModel, propertyId, tasks) = makeHost()
        XCTAssertFalse(host.isSceneActive, "No scene in this test")
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId, hours: 12, category: .repairs)
        host.suggestionStore!.ingest([s], existingEntries: [], calendar: calendar)

        let router = NotificationActionRouter(host: host, environment: .testing(defaults: .standard))
        var order: [String] = []
        router.onWriteFinished = { order.append("write") }
        let entriesKey = UserScope.key("LandlordHours.entries", userId: profileId)
        var savedAtCompletion = false
        let outcome = await router.handle(logItRequest(s, profileId: profileId)) {
            order.append("completion")
            let data = UserDefaults.standard.data(forKey: entriesKey) ?? Data()
            let saved = (try? JSONDecoder().decode([TimeEntry].self, from: data)) ?? []
            savedAtCompletion = saved.contains { $0.id == s.entryId(profileId: self.profileId) }
        }

        XCTAssertEqual(outcome, .confirmed(entryId: s.entryId(profileId: profileId)))
        XCTAssertEqual(order, ["write", "completion"])
        XCTAssertTrue(savedAtCompletion, "The completion handler runs only after the entry is on disk")
        XCTAssertEqual(viewModel.timeEntries.filter { $0.id == s.entryId(profileId: profileId) }.count, 1)
        XCTAssertEqual(host.suggestionStore?.suggestion(forKey: s.sourceKey)?.state, .confirmed(entryId: s.entryId(profileId: profileId)))
        XCTAssertEqual(Set(tasks.begun), ["LandlordHours.capture.confirm", "LandlordHours.capture.push"])
        XCTAssertEqual(tasks.ended.count, tasks.begun.count, "Every background-task assertion is ended")

        // 12 h crossed the 10 h milestone with no scene: queued, not shown and not lost.
        XCTAssertNil(viewModel.activeCelebration)
        XCTAssertEqual(PendingCelebrationQueue.pending(), [.hoursLogged(milestone: 10)])
        host.sceneDidChange(isActive: true)
        XCTAssertEqual(viewModel.activeCelebration, .hoursLogged(milestone: 10))
        XCTAssertTrue(PendingCelebrationQueue.pending().isEmpty)

        // A repeated action (double tap / redelivered) records nothing new.
        var completed = false
        let again = await router.handle(logItRequest(s, profileId: profileId)) { completed = true }
        XCTAssertEqual(again, .alreadyRecorded(entryId: s.entryId(profileId: profileId)))
        XCTAssertTrue(completed)
        XCTAssertEqual(viewModel.timeEntries.filter { $0.id == s.entryId(profileId: profileId) }.count, 1)
    }

    func testActionForAnotherProfileIsRejected() async {
        let (host, viewModel, propertyId, _) = makeHost()
        let s = calendarSuggestion(start: date(2026, 3, 2), propertyId: propertyId)
        host.suggestionStore!.ingest([s], existingEntries: [], calendar: calendar)
        var completed = false
        let outcome = await NotificationActionRouter(host: host, environment: .testing(defaults: .standard)).handle(logItRequest(s, profileId: "someone-else")) { completed = true }
        XCTAssertEqual(outcome, .rejectedWrongProfile)
        XCTAssertTrue(completed, "The system handler is always called")
        XCTAssertTrue(viewModel.timeEntries.isEmpty)

        let missing = NotificationActionRequest(actionIdentifier: CaptureNotificationAction.logIt,
                                                userInfo: [NotificationPayload.sourceKeyKey: s.sourceKey])
        let noProfile = await NotificationActionRouter(host: host, environment: .testing(defaults: .standard)).handle(missing) {}
        XCTAssertEqual(noProfile, .rejectedWrongProfile)
    }

    func testNotLandlordWorkAndEditActions() async {
        let (host, viewModel, propertyId, _) = makeHost()
        let a = calendarSuggestion(externalId: "A", start: date(2026, 3, 2), propertyId: propertyId)
        let b = calendarSuggestion(externalId: "B", start: date(2026, 3, 2), propertyId: propertyId)
        host.suggestionStore!.ingest([a, b], existingEntries: [], calendar: calendar)
        let router = NotificationActionRouter(host: host, environment: .testing(defaults: .standard))

        let dismissed = await router.handle(NotificationActionRequest(
            actionIdentifier: CaptureNotificationAction.notLandlordWork,
            userInfo: CaptureNotificationAction.userInfo(profileId: profileId, sourceKey: a.sourceKey))) {}
        XCTAssertEqual(dismissed, .dismissed)
        XCTAssertTrue(host.suggestionStore!.isDismissed(a.sourceKey))

        let edit = await router.handle(NotificationActionRequest(
            actionIdentifier: CaptureNotificationAction.edit,
            userInfo: CaptureNotificationAction.userInfo(profileId: profileId, sourceKey: b.sourceKey))) {}
        XCTAssertEqual(edit, .openedForEdit)
        XCTAssertEqual(UserDefaults.standard.string(forKey: CaptureNotificationAction.pendingEditKey), b.sourceKey)
        XCTAssertTrue(viewModel.timeEntries.isEmpty)
    }

    func testEngagementNotificationRoutingUnchanged() async {
        let (host, _, _, _) = makeHost()
        let previous = UserDefaults.standard.string(forKey: AppIntentNavigationRequest.pendingDestinationKey)
        defer { UserDefaults.standard.set(previous, forKey: AppIntentNavigationRequest.pendingDestinationKey) }
        var completed = false
        let outcome = await NotificationActionRouter(host: host, environment: .testing(defaults: .standard)).handle(NotificationActionRequest(
            actionIdentifier: "LANDLORDHOURS_ACTION_EXPORT",
            categoryIdentifier: "LANDLORDHOURS_EXPORT",
            userInfo: ["reason": "x", "destination": EngagementDestination.export.rawValue])) { completed = true }
        XCTAssertEqual(outcome, .navigated(.reports))
        XCTAssertTrue(completed)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppIntentNavigationRequest.pendingDestinationKey), "reports")
    }

    func testForegroundCelebrationsStillShowImmediately() {
        let viewModel = AppViewModel()
        XCTAssertFalse(viewModel.queuesCelebrations, "A model outside the host behaves as in 1.1")
        viewModel.triggerCelebration(.propertyAdded)
        XCTAssertEqual(viewModel.activeCelebration, .propertyAdded)
    }

    func testSharedHostOwnsTheAppModel() {
        // The running test host app created the shared host at launch (didFinishLaunching).
        XCTAssertTrue(AppModelHost.shared.viewModel === AppModelHost.shared.viewModel)
    }
}
