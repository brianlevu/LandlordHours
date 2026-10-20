import XCTest
@testable import LandlordHours

// WP-L fix round: review must-fixes (export staleness, inbox dead end, Today loading copy,
// Run again counting) and should-fixes (announcements, export reset).

private struct NothingNewScanner: BackfillScanning {
    var access: CalendarAccess = .fullAccess
    func scan(
        progress: @escaping @MainActor (ClassifierBatchProgress) -> Void,
        found: @escaping @MainActor ([Suggestion]) -> Void
    ) async -> BackfillScanOutcome {
        // A re-run: every item already streamed before the cancel, so nothing is new.
        progress(ClassifierBatchProgress(completed: 3, total: 3))
        return BackfillScanOutcome(access: access, foundCount: 0)
    }
}

private func backfillItem(_ i: Int, hours: Double) -> Suggestion {
    let start = Date(timeIntervalSince1970: 1_780_000_000 + Double(i) * 86_400)
    return Suggestion(sourceKey: "cal:fix-\(i)", kind: .calendar, detectedAt: start, start: start,
                      end: start.addingTimeInterval(hours * 3600), title: "Fix \(i)", containerId: "CAL",
                      proposedCategory: .repairs, proposedHours: hours, hoursBasis: .scheduled,
                      confidence: 0.9, isBackfill: true)
}

@MainActor
final class BackfillJobFixRoundTests: XCTestCase {
    /// Run again after a cancel: the items found earlier are updated in place (not "new"), but
    /// they are still the look-back's result, so the count and the reveal include them.
    func testRunAgainCountsBackfillItemsStillPendingWhenItFinishes() async {
        var finished: [(Int, Double)] = []
        let pending = [backfillItem(1, hours: 2), backfillItem(2, hours: 1.5), backfillItem(3, hours: 1)]
        let job = BackfillJob(
            onItems: { _ in },
            onFinished: { finished.append(($0, $1)) },
            markCompleted: {},
            pendingBackfill: { pending },
            announce: { _ in }
        )
        job.start(NothingNewScanner())
        await job.waitUntilDone()
        XCTAssertEqual(job.phase, .finished(found: 3))
        XCTAssertEqual(job.foundCount, 3)
        XCTAssertEqual(finished.first?.0, 3, "The reveal is not skipped on a re-run")
        XCTAssertEqual(finished.first?.1, 4.5)
    }

    func testEndOfLookBackIsAnnouncedOnce() async {
        var spoken: [String] = []
        let job = BackfillJob(onItems: { _ in }, onFinished: { _, _ in }, markCompleted: {},
                              pendingBackfill: { [backfillItem(1, hours: 1)] }, announce: { spoken.append($0) })
        job.start(NothingNewScanner())
        await job.waitUntilDone()
        XCTAssertEqual(spoken, ["Finished looking through your calendar. 1 suggestion to confirm."])

        spoken = []
        job.start(NothingNewScanner(access: .denied))
        await job.waitUntilDone()
        XCTAssertEqual(spoken, ["Couldn't read your calendar. Turn on calendar access in Settings."])
    }

    func testCancelIsAnnounced() async {
        var spoken: [String] = []
        let job = BackfillJob(onItems: { _ in }, onFinished: { _, _ in }, markCompleted: {},
                              pendingBackfill: { [] }, announce: { spoken.append($0) })
        job.start(SlowForeverScanner())
        job.cancel()
        await job.waitUntilDone()
        XCTAssertEqual(spoken, ["Stopped looking through your calendar."])
    }

    /// The Inbox never dead-ends: a stopped or blocked look-back keeps its header (Run again or
    /// Settings) even when it found nothing.
    func testEmptyInboxDoesNotHideAStoppedOrBlockedLookBack() {
        XCTAssertTrue(BackfillJob.showsEmptyState(visibleIsEmpty: true, phase: .idle))
        XCTAssertTrue(BackfillJob.showsEmptyState(visibleIsEmpty: true, phase: .finished(found: 0)))
        XCTAssertFalse(BackfillJob.showsEmptyState(visibleIsEmpty: true, phase: .scanning(completed: 0, total: 0)))
        XCTAssertFalse(BackfillJob.showsEmptyState(visibleIsEmpty: true, phase: .cancelled))
        XCTAssertFalse(BackfillJob.showsEmptyState(visibleIsEmpty: true, phase: .blocked(.denied)))
        XCTAssertFalse(BackfillJob.showsEmptyState(visibleIsEmpty: false, phase: .idle))
    }
}

private struct SlowForeverScanner: BackfillScanning {
    func scan(
        progress: @escaping @MainActor (ClassifierBatchProgress) -> Void,
        found: @escaping @MainActor ([Suggestion]) -> Void
    ) async -> BackfillScanOutcome {
        while !Task.isCancelled { try? await Task.sleep(nanoseconds: 5_000_000) }
        return BackfillScanOutcome(access: .fullAccess, foundCount: 0, cancelled: true)
    }
}

// MARK: - Today copy while loading

final class TodayPresentationTests: XCTestCase {
    func testLoadingNeverReadsAsANewUser() {
        // Mid-pull with nothing local yet: not "Add your first property" / "Log your first hour".
        XCTAssertEqual(TodayPresentation.mode(hoursPending: true, backfillScanning: false, hasProperties: false, hasEntries: false), .loading)
        XCTAssertEqual(TodayPresentation.mode(hoursPending: true, backfillScanning: true, hasProperties: true, hasEntries: false), .loading)
        XCTAssertFalse(TodayPresentation.Mode.loading.showsActivationCard)
        XCTAssertEqual(TodayPresentation.Mode.loading.title, "Today’s work")
        XCTAssertEqual(TodayPresentation.Mode.loading.compactSubtitle, "Bringing in your latest hours")
    }

    func testLookBackRunningIsItsOwnState() {
        let mode = TodayPresentation.mode(hoursPending: false, backfillScanning: true, hasProperties: true, hasEntries: false)
        XCTAssertEqual(mode, .lookingBack)
        XCTAssertFalse(mode.showsActivationCard)
        XCTAssertEqual(mode.title, "Looking through your calendar")
    }

    func testSettledStates() {
        XCTAssertEqual(TodayPresentation.mode(hoursPending: false, backfillScanning: false, hasProperties: true, hasEntries: false), .newUser)
        XCTAssertTrue(TodayPresentation.Mode.newUser.showsActivationCard)
        XCTAssertEqual(TodayPresentation.mode(hoursPending: false, backfillScanning: true, hasProperties: true, hasEntries: true), .normal)
        XCTAssertNil(TodayPresentation.Mode.normal.compactSubtitle, "Normal uses the live pace line")
    }
}

// MARK: - Quiet house updates for iCloud merges

@MainActor
final class RemoteMergeQuietTests: XCTestCase {
    func testHoursChangeRightAfterAMergeIsQuiet() {
        let merge = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(AppViewModel.isRemoteMerge(lastMergeAt: nil, now: merge))
        XCTAssertTrue(AppViewModel.isRemoteMerge(lastMergeAt: merge, now: merge.addingTimeInterval(0.2)),
                      "A late pull after the loading cap updates in place, no +Nh beam")
        XCTAssertFalse(AppViewModel.isRemoteMerge(lastMergeAt: merge, now: merge.addingTimeInterval(5)),
                       "A later save by the user still builds")
    }
}

// MARK: - Export staleness and reset

private struct ExportFixFailure: Error {}

@MainActor
final class ExportJobFixRoundTests: XCTestCase {
    private func report() -> AuditReport {
        AuditReportBuilder.build(AuditReportBuilder.inputFromTaxProfile(
            entries: [], properties: [], taxYear: 2026, spouseTracking: false,
            nonREWorkHours: 0, groupingElection: false, noOneParticipatedMore: false
        ))
    }

    func testReadyReportGoesStaleWhenRecordsChange() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ExportFix-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let job = ExportJob(writer: { r, y in AuditExportFiles.write(report: r, year: y, directory: dir) })
        job.start(report: report(), year: 2026, fingerprint: "A")
        await job.waitUntilDone()
        XCTAssertNotNil(job.readyFiles(for: 2026, fingerprint: "A"))
        XCTAssertNil(job.readyFiles(for: 2026, fingerprint: "B"), "Records changed: create again")
        XCTAssertTrue(job.isStale(year: 2026, fingerprint: "B"))
        XCTAssertEqual(job.banner(currentFingerprint: "A"), .ready)
        XCTAssertNil(job.banner(currentFingerprint: "B"), "No banner for an out-of-date report")
    }

    func testFingerprintChangesWhenAnEntryChanges() {
        let property = RentalProperty(name: "Oak", address: "1 Oak", propertyType: .ltr)
        var entry = TimeEntry(propertyId: property.id, participant: .selfParticipant, category: .repairs,
                              hours: 2, date: Date(timeIntervalSince1970: 1_780_000_000))
        let before = ExportFingerprint.make(entries: [entry], properties: [property], year: 2026, profile: "x")
        XCTAssertEqual(before, ExportFingerprint.make(entries: [entry], properties: [property], year: 2026, profile: "x"))
        entry.hours = 3
        XCTAssertNotEqual(before, ExportFingerprint.make(entries: [entry], properties: [property], year: 2026, profile: "x"))
        XCTAssertNotEqual(before, ExportFingerprint.make(entries: [], properties: [property], year: 2026, profile: "x"))
        XCTAssertNotEqual(before, ExportFingerprint.make(entries: [entry], properties: [property], year: 2026, profile: "y"))
    }

    func testResetCancelsTheRunningExport() async {
        let observed = CancelFlag()
        let job = ExportJob(writer: { _, _ in
            while !Task.isCancelled { try? await Task.sleep(nanoseconds: 5_000_000) }
            observed.set()
            return .failure(ExportFixFailure())
        })
        job.start(report: report(), year: 2026)
        try? await Task.sleep(nanoseconds: 30_000_000)
        job.reset()
        await job.waitUntilDone()
        XCTAssertTrue(observed.value, "The writer sees the cancel")
        XCTAssertEqual(job.state, .idle)
    }
}

private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
