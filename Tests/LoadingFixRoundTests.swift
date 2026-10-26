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
        XCTAssertEqual(spoken, ["Couldn’t read your calendar. Turn on calendar access in Settings."])
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
        XCTAssertTrue(BackfillJob.showsEmptyState(visibleIsEmpty: true, phase: .cancelled))
        XCTAssertTrue(BackfillJob.showsEmptyState(visibleIsEmpty: true, phase: .blocked(.denied)))
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

// MARK: - Quiet house updates only for iCloud merges

/// The house mutes its build (no "+Nh" beam) only for changes iCloud merged in. The user's own
/// save right after a merge still builds: there is no time window to swallow it.
@MainActor
final class EntriesChangeOriginTests: CaptureTestCase {
    func testMergeIsRemoteAndTheUsersOwnSaveRightAfterIsLocal() {
        let (app, oak) = makeViewModel()
        XCTAssertEqual(app.lastEntriesChangeOrigin, .local)

        let remote = TimeEntry(propertyId: oak, participant: .selfParticipant, category: .repairs,
                               hours: 3, date: Date())
        app.syncDidReceiveEntries([remote])
        XCTAssertEqual(app.lastEntriesChangeOrigin, .remote, "A late pull updates the house quietly")

        // Immediately after (same instant, well inside any old 1.5 s window): the user confirms.
        app.addTimeEntry(propertyId: oak, participant: .selfParticipant, category: .repairs,
                         hours: 1, date: Date(), notes: "")
        XCTAssertEqual(app.lastEntriesChangeOrigin, .local, "The user's own save is never muted")

        app.syncDidDeleteEntryIds([remote.id])
        XCTAssertEqual(app.lastEntriesChangeOrigin, .remote)
    }
}

// MARK: - Export gate (Create waits for the pull)

final class ExportGateTests: XCTestCase {
    func testCreateIsDisabledWhileTheHoursPlaceholderShows() {
        let gate = ExportGate.resolve(hasEntries: true, isGenerating: false, hoursPlaceholderShowing: true, initialPullRunning: true)
        XCTAssertEqual(gate, .waitingForHours)
        XCTAssertFalse(gate.allowsCreate)
        XCTAssertEqual(gate.title(isStale: false), "Getting your latest hours…")
    }

    func testWaitingComesBeforeNoEntries() {
        // A restored profile mid-pull has no local entries yet: not "No entries to export".
        let gate = ExportGate.resolve(hasEntries: false, isGenerating: false, hoursPlaceholderShowing: true, initialPullRunning: true)
        XCTAssertEqual(gate.title(isStale: false), "Getting your latest hours…")
        let afterCap = ExportGate.resolve(hasEntries: false, isGenerating: false, hoursPlaceholderShowing: false, initialPullRunning: true)
        XCTAssertEqual(afterCap.title(isStale: false), "Still syncing from iCloud")
    }

    func testAfterThePlaceholderCapCreateStillWaitsForThePull() {
        let gate = ExportGate.resolve(hasEntries: true, isGenerating: false, hoursPlaceholderShowing: false, initialPullRunning: true)
        XCTAssertEqual(gate, .stillSyncing)
        XCTAssertFalse(gate.allowsCreate, "No quiet export of a possibly incomplete report")
        XCTAssertEqual(gate.title(isStale: false), "Still syncing from iCloud")
    }

    func testPullLandedOrFailedEnablesCreate() {
        let gate = ExportGate.resolve(hasEntries: true, isGenerating: false, hoursPlaceholderShowing: false, initialPullRunning: false)
        XCTAssertEqual(gate, .ready)
        XCTAssertTrue(gate.allowsCreate)
        XCTAssertEqual(gate.title(isStale: true), "Create again")
        XCTAssertEqual(ExportGate.resolve(hasEntries: false, isGenerating: false, hoursPlaceholderShowing: false, initialPullRunning: false), .noEntries)
        XCTAssertEqual(ExportGate.resolve(hasEntries: true, isGenerating: true, hoursPlaceholderShowing: true, initialPullRunning: true), .generating)
    }
}

/// The view model's pull state that feeds the gate: running until the initial sync ends, by any
/// outcome (landed, failed, no iCloud account).
@MainActor
final class InitialPullRunningTests: CaptureTestCase {
    private func ops(account: Bool, pullOK: Bool, delay: UInt64) -> CloudKitSyncService.InitialSyncOperations {
        CloudKitSyncService.InitialSyncOperations(
            accountAvailable: { try? await Task.sleep(nanoseconds: delay); return account },
            prepare: {},
            push: {},
            pull: { pullOK }
        )
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }

    func testRunningUntilThePullLands() async {
        let (app, _) = makeViewModel()
        app.syncService.operationsOverride = ops(account: true, pullOK: true, delay: 150_000_000)
        app.startInitialSync(showsPlaceholder: false)
        XCTAssertTrue(app.isInitialPullRunning, "Export waits while the pull runs")
        let ended = await waitUntil { !app.isInitialPullRunning }
        XCTAssertTrue(ended)
    }

    func testFailedPullOrNoAccountEnablesExportNormally() async {
        let (app, _) = makeViewModel()
        app.syncService.operationsOverride = ops(account: true, pullOK: false, delay: 10_000_000)
        app.startInitialSync(showsPlaceholder: false)
        let afterFail = await waitUntil { !app.isInitialPullRunning }
        XCTAssertTrue(afterFail, "A failed pull doesn't keep export waiting")

        app.syncService.operationsOverride = ops(account: false, pullOK: true, delay: 10_000_000)
        app.startInitialSync(showsPlaceholder: false)
        let noAccount = await waitUntil { !app.isInitialPullRunning }
        XCTAssertTrue(noAccount, "No iCloud account: export works normally")
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

    func testResetDeletesTheOutgoingProfilesReportFiles() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("LandlordHoursExport-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let job = ExportJob(writer: { r, y in AuditExportFiles.write(report: r, year: y, directory: base) })
        job.start(report: report(), year: 2026, fingerprint: "A")
        await job.waitUntilDone()
        guard let files = job.readyFiles(for: 2026) else { return XCTFail("ready") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.pdfURL.path))
        job.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.pdfURL.path), "PDF deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.csvURL.path), "CSV deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.path), "Our temp folder deleted")
    }
}

private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

// MARK: - Profile switch during a slow first pull (review blocker)

@MainActor
private final class PullRecorder {
    var pulledFor: [String?] = []
    /// Profiles whose pull has finished (appended after the slow pull returns).
    var finishedFor: [String?] = []
}

@MainActor
final class InitialSyncSwitchMidPullTests: CaptureTestCase {
    private func slowOps(_ recorder: PullRecorder, pullOK: Bool = true) -> CloudKitSyncService.InitialSyncOperations {
        CloudKitSyncService.InitialSyncOperations(
            accountAvailable: { true },
            prepare: {},
            push: {},
            pull: {
                let profile = UserScope.userId
                recorder.pulledFor.append(profile)
                try? await Task.sleep(nanoseconds: 120_000_000)
                recorder.finishedFor.append(profile)
                return pullOK
            }
        )
    }

    /// A start() for profile B that arrives while A's pull runs returns only after B is pulled.
    func testRepeatStartWaitsForThePullOfTheCurrentProfile() async {
        let service = CloudKitSyncService()
        let recorder = PullRecorder()
        service.operationsOverride = slowOps(recorder)
        let first = Task { await service.start() }
        try? await Task.sleep(nanoseconds: 30_000_000)          // A's pull is in flight
        let profileB = "local-switch-\(UUID().uuidString.prefix(6))"
        UserDefaults.standard.set(profileB, forKey: ProfileKeys.localProfileId)
        defer { AppViewModel.clearScopedAccountData(for: profileB) }

        await service.start()                                     // B's request
        XCTAssertEqual(recorder.pulledFor, [profileId, profileB], "B's pull ran before start() returned")
        XCTAssertEqual(service.initialSyncCompletedFor, profileB)
        await first.value
    }

    /// The view model keeps the export gate closed until the new profile's pull has landed.
    func testExportGateStaysClosedAcrossASwitchMidPull() async {
        let (app, _) = makeViewModel()
        let recorder = PullRecorder()
        app.syncService.operationsOverride = slowOps(recorder)
        app.startInitialSync(showsPlaceholder: false)
        try? await Task.sleep(nanoseconds: 30_000_000)
        let profileB = "local-switch-\(UUID().uuidString.prefix(6))"
        UserDefaults.standard.set(profileB, forKey: ProfileKeys.localProfileId)
        defer { AppViewModel.clearScopedAccountData(for: profileB) }
        let second = app.startInitialSync(showsPlaceholder: false)

        // The second (profile B) sync finishes only after B's pull finished. Before the fix,
        // start() returned at once for a request made mid-pull, so this await came back while
        // B hadn't been pulled at all.
        await second.value
        XCTAssertTrue(recorder.finishedFor.contains(profileB), "B pulled before B's sync reported done")

        let deadline = Date().addingTimeInterval(5)
        while app.isInitialPullRunning && Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertFalse(app.isInitialPullRunning)
        XCTAssertEqual(recorder.pulledFor.last ?? nil, profileB)
        XCTAssertFalse(app.initialPullFailed)
    }

    /// A retry outside startInitialSync (Sync Now, iCloud coming back, a notification action)
    /// that succeeds clears the stale "Couldn't reach iCloud" note.
    func testAnySuccessfulRetryClearsTheFailedNote() async {
        let (app, _) = makeViewModel()
        app.syncService.operationsOverride = slowOps(PullRecorder(), pullOK: false)
        await app.startInitialSync(showsPlaceholder: false).value
        XCTAssertTrue(app.initialPullFailed)

        app.syncService.operationsOverride = slowOps(PullRecorder(), pullOK: true)
        await app.syncService.start()           // a direct retry, not startInitialSync
        XCTAssertFalse(app.initialPullFailed, "The note goes away once iCloud is reached")
    }

    func testFailedPullOpensTheGateWithANote() async {
        let (app, _) = makeViewModel()
        app.syncService.operationsOverride = slowOps(PullRecorder(), pullOK: false)
        app.startInitialSync(showsPlaceholder: false)
        let deadline = Date().addingTimeInterval(5)
        while app.isInitialPullRunning && Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertFalse(app.isInitialPullRunning, "A failed pull doesn't block export")
        XCTAssertTrue(app.initialPullFailed, "But the sheet says the report may miss hours")
        XCTAssertFalse(AppViewModel.initialPullFailed(accountAvailable: false, completedFor: nil, activeProfile: "x"),
                       "No iCloud account is not a failure")
        XCTAssertFalse(AppViewModel.initialPullFailed(accountAvailable: true, completedFor: "x", activeProfile: "x"))
    }
}

@MainActor
final class ExportJobReplaceTests: XCTestCase {
    func testStartingANewReportDeletesThePreviousFiles() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ExportReplace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let job = ExportJob(writer: { r, y in
            AuditExportFiles.write(report: r, year: y, directory: base.appendingPathComponent(UUID().uuidString))
        })
        let report = AuditReportBuilder.build(AuditReportBuilder.inputFromTaxProfile(
            entries: [], properties: [], taxYear: 2026, spouseTracking: false,
            nonREWorkHours: 0, groupingElection: false, noOneParticipatedMore: false))
        job.start(report: report, year: 2026, fingerprint: "A")
        await job.waitUntilDone()
        guard let first = job.readyFiles(for: 2026) else { return XCTFail("ready") }
        job.start(report: report, year: 2026, fingerprint: "B")
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.pdfURL.path), "Old PDF removed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.csvURL.path), "Old CSV removed")
        await job.waitUntilDone()
        XCTAssertNotNil(job.readyFiles(for: 2026, fingerprint: "B"))
    }
}
