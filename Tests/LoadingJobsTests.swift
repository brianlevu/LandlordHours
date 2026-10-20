import XCTest
import SwiftUI
@testable import LandlordHours

// MARK: - Fakes

/// Streams `count` items, one every `stepNanos`, until done or cancelled.
private struct StreamingScanner: BackfillScanning {
    var count = 6
    var stepNanos: UInt64 = 25_000_000
    var access: CalendarAccess = .fullAccess
    var hoursEach: Double = 2

    func scan(
        progress: @escaping @MainActor (ClassifierBatchProgress) -> Void,
        found: @escaping @MainActor ([Suggestion]) -> Void
    ) async -> BackfillScanOutcome {
        guard access == .fullAccess else { return BackfillScanOutcome(access: access, foundCount: 0) }
        var added = 0
        for i in 1...count {
            try? await Task.sleep(nanoseconds: stepNanos)
            if Task.isCancelled { return BackfillScanOutcome(access: .fullAccess, foundCount: added, cancelled: true) }
            found([Self.item(i, hours: hoursEach)])
            added += 1
            progress(ClassifierBatchProgress(completed: i, total: count))
        }
        return BackfillScanOutcome(access: .fullAccess, foundCount: added)
    }

    static func item(_ i: Int, hours: Double) -> Suggestion {
        let start = Date(timeIntervalSince1970: 1_780_000_000 + Double(i) * 86_400)
        return Suggestion(sourceKey: "cal:stream-\(i)", kind: .calendar, detectedAt: start, start: start,
                          end: start.addingTimeInterval(hours * 3600), title: "Item \(i)", containerId: "CAL",
                          proposedPropertyId: nil, proposedCategory: .repairs, proposedHours: hours,
                          hoursBasis: .scheduled, confidence: 0.9, isBackfill: true, mightAlreadyBeLogged: false)
    }
}

@MainActor
private final class JobRecorder {
    var streamed: [String] = []
    var finished: [(Int, Double)] = []
    var completedMarks = 0

    func makeJob() -> BackfillJob {
        BackfillJob(
            onItems: { [unowned self] items in self.streamed += items.map(\.title) },
            onFinished: { [unowned self] count, hours in self.finished.append((count, hours)) },
            markCompleted: { [unowned self] in self.completedMarks += 1 }
        )
    }
}

@MainActor
private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return true
}

// MARK: - Backfill streaming state machine

@MainActor
final class BackfillJobTests: XCTestCase {
    /// start → progress → items appear → cancel → retry → complete.
    func testStreamingLifecycleStartProgressCancelRetryComplete() async {
        let recorder = JobRecorder()
        let job = recorder.makeJob()
        XCTAssertEqual(job.phase, .idle)

        // Start: scanning at once, before any progress.
        job.start(StreamingScanner(count: 40, stepNanos: 20_000_000))
        XCTAssertEqual(job.phase, .scanning(completed: 0, total: 0))
        XCTAssertTrue(job.isScanning)

        // Progress and streamed items arrive while it runs.
        let streamedSome = await waitUntil { job.foundCount >= 3 }
        XCTAssertTrue(streamedSome, "Items stream in while scanning")
        guard case .scanning(let completed, let total) = job.phase else { return XCTFail("Still scanning: \(job.phase)") }
        XCTAssertEqual(total, 40)
        XCTAssertGreaterThanOrEqual(completed, 3)
        XCTAssertEqual(recorder.streamed.count, job.foundCount, "Each streamed batch reaches the inbox hook")
        XCTAssertEqual(job.foundHours, Double(job.foundCount) * 2)

        // A second start while scanning is ignored (no second scan).
        job.start(StreamingScanner(count: 1))
        XCTAssertTrue(job.isScanning)

        // Cancel: stops, never marked complete, no reveal; what streamed is kept.
        let keptBeforeCancel = job.foundCount
        job.cancel()
        XCTAssertEqual(job.phase, .cancelled)
        await job.waitUntilDone()
        XCTAssertEqual(job.phase, .cancelled, "The ended scan doesn't overwrite the cancel")
        XCTAssertEqual(recorder.completedMarks, 0, "A cancelled look-back is never marked done")
        XCTAssertTrue(recorder.finished.isEmpty, "No house reveal for a cancelled run")
        XCTAssertEqual(job.foundCount, keptBeforeCancel, "No items stream in after the cancel")

        // Retry: a fresh run that finishes.
        job.start(StreamingScanner(count: 5, stepNanos: 1_000_000))
        XCTAssertEqual(job.foundCount, 0, "A new run counts from zero")
        await job.waitUntilDone()
        XCTAssertEqual(job.phase, .finished(found: 5))
        XCTAssertEqual(recorder.completedMarks, 1, "Only a finished scan is marked done")
        XCTAssertEqual(recorder.finished.count, 1)
        XCTAssertEqual(recorder.finished.first?.0, 5)
        XCTAssertEqual(recorder.finished.first?.1, 10)
    }

    func testBlockedCalendarIsNotMarkedComplete() async {
        let recorder = JobRecorder()
        let job = recorder.makeJob()
        job.start(StreamingScanner(access: .denied))
        await job.waitUntilDone()
        XCTAssertEqual(job.phase, .blocked(.denied))
        XCTAssertEqual(recorder.completedMarks, 0)
        XCTAssertTrue(recorder.finished.isEmpty)
        // It can run again once access is back.
        job.start(StreamingScanner(count: 2, stepNanos: 1_000_000))
        await job.waitUntilDone()
        XCTAssertEqual(job.phase, .finished(found: 2))
    }

    func testResetStopsARunAndForgetsIt() async {
        let recorder = JobRecorder()
        let job = recorder.makeJob()
        job.start(StreamingScanner(count: 50, stepNanos: 20_000_000))
        _ = await waitUntil { job.foundCount >= 1 }
        job.reset()
        XCTAssertEqual(job.phase, .idle)
        XCTAssertEqual(job.foundCount, 0)
        await job.waitUntilDone()
        XCTAssertEqual(job.phase, .idle, "A reset run never comes back as finished")
        XCTAssertEqual(recorder.completedMarks, 0)
    }

    func testFinishedRunCanBeAcknowledged() async {
        let recorder = JobRecorder()
        let job = recorder.makeJob()
        job.start(StreamingScanner(count: 1, stepNanos: 1_000_000, hoursEach: 0))
        await job.waitUntilDone()
        XCTAssertEqual(job.phase, .finished(found: 1))
        job.acknowledge()
        XCTAssertEqual(job.phase, .idle)
    }

    func testHeaderDetailCopy() {
        XCTAssertEqual(BackfillProgressHeader.detail(completed: 0, total: 0, found: 0), "Getting your events")
        XCTAssertEqual(BackfillProgressHeader.detail(completed: 12, total: 80, found: 0), "12 of 80 events")
        XCTAssertEqual(BackfillProgressHeader.detail(completed: 12, total: 80, found: 5), "12 of 80 events · 5 found so far")
    }
}

/// The default job marks the real per-profile flag only for a finished run (WP3 rule).
@MainActor
final class BackfillJobCompletionFlagTests: CaptureTestCase {
    func testDefaultJobMarksCaptureOptInOnlyWhenFinished() async {
        let job = BackfillJob(onItems: { _ in }, onFinished: { _, _ in })
        job.start(StreamingScanner(count: 30, stepNanos: 20_000_000))
        _ = await waitUntil { job.foundCount >= 1 }
        job.cancel()
        await job.waitUntilDone()
        XCTAssertFalse(CaptureOptIn.backfillCompleted(), "Cancel leaves the look-back not done")

        job.start(StreamingScanner(count: 2, stepNanos: 1_000_000))
        await job.waitUntilDone()
        XCTAssertTrue(CaptureOptIn.backfillCompleted())
    }
}

// MARK: - Export background job

private struct ExportFailure: Error {}

@MainActor
final class ExportJobTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ExportJobTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    private func report(_ year: Int = 2026) -> AuditReport {
        AuditReportBuilder.build(AuditReportBuilder.inputFromTaxProfile(
            entries: [], properties: [], taxYear: year, spouseTracking: false,
            nonREWorkHours: 0, groupingElection: false, noOneParticipatedMore: false
        ))
    }

    func testReadyWhileSheetClosedShowsBannerThenOpensShare() async {
        let dir = directory!
        let job = ExportJob(writer: { report, year in AuditExportFiles.write(report: report, year: year, directory: dir) })
        job.isSheetVisible = true
        job.start(report: report(), year: 2026)
        XCTAssertEqual(job.state, .generating(year: 2026))
        XCTAssertTrue(job.isGenerating)
        // The user leaves the export sheet while it runs.
        job.isSheetVisible = false
        XCTAssertNil(job.banner, "No banner while generating")
        await job.waitUntilDone()

        guard case .ready(let files, let year) = job.state else { return XCTFail("Ready: \(job.state)") }
        XCTAssertEqual(year, 2026)
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.pdfURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.csvURL.path))
        XCTAssertEqual(job.banner, .ready)
        XCTAssertTrue(job.showsReadyBanner)
        XCTAssertEqual(job.readyFiles(for: 2026), files)
        XCTAssertNil(job.readyFiles(for: 2025), "A report is for its own year")

        // Tap the banner: the share sheet gets the files and the banner goes away.
        XCTAssertEqual(job.takeReadyForSharing(), files)
        XCTAssertNil(job.banner)
    }

    func testReadyWhileSheetOpenShowsNoBannerLater() async {
        let dir = directory!
        let job = ExportJob(writer: { report, year in AuditExportFiles.write(report: report, year: year, directory: dir) })
        job.isSheetVisible = true
        job.start(report: report(), year: 2026)
        await job.waitUntilDone()
        XCTAssertNotNil(job.readyFiles(for: 2026), "The sheet shows Report ready itself")
        job.isSheetVisible = false
        XCTAssertNil(job.banner, "Already seen in the sheet: no banner after closing it")
    }

    func testFailureSaysSoInSheetAndBanner() async {
        let job = ExportJob(writer: { _, _ in .failure(ExportFailure()) })
        job.start(report: report(), year: 2026)
        await job.waitUntilDone()
        XCTAssertEqual(job.state, .failed(year: 2026, message: ExportJob.failureMessage))
        XCTAssertEqual(job.failureMessage(for: 2026), "Could not create the report. Please try again.")
        XCTAssertEqual(job.banner, .failed, "Closed sheet: the failure shows in the banner slot")
        XCTAssertNil(job.takeReadyForSharing(), "Nothing to share after a failure")
        job.dismissBanner()
        XCTAssertNil(job.banner)

        // Try again: generating replaces the failure.
        let dir = directory!
        let retry = ExportJob(writer: { report, year in AuditExportFiles.write(report: report, year: year, directory: dir) })
        retry.start(report: report(), year: 2026)
        await retry.waitUntilDone()
        XCTAssertNotNil(retry.readyFiles(for: 2026))
    }

    func testSecondStartWhileGeneratingIsIgnoredAndResetDropsResult() async {
        let job = ExportJob(writer: { _, _ in
            try? await Task.sleep(nanoseconds: 80_000_000)
            return .failure(ExportFailure())
        })
        job.start(report: report(), year: 2026)
        job.start(report: report(2025), year: 2025)
        XCTAssertEqual(job.state, .generating(year: 2026))
        job.reset()
        await job.waitUntilDone()
        XCTAssertEqual(job.state, .idle, "A reset export never comes back")
    }
}

// MARK: - Drafting loader timing

final class DraftingLoaderTimingTests: XCTestCase {
    func testLoopDrawsHoldsErasesAndRests() {
        let start = DraftingLoaderTiming.trim(at: 0)
        XCTAssertEqual(start.from, 0)
        XCTAssertEqual(start.to, 0, accuracy: 0.001)
        let drawing = DraftingLoaderTiming.trim(at: DraftingLoaderTiming.drawEnd / 2)
        XCTAssertEqual(drawing.from, 0)
        XCTAssertGreaterThan(drawing.to, 0.3)
        XCTAssertLessThan(drawing.to, 0.7)
        let held = DraftingLoaderTiming.trim(at: (DraftingLoaderTiming.drawEnd + DraftingLoaderTiming.holdEnd) / 2)
        XCTAssertEqual(held.from, 0)
        XCTAssertEqual(held.to, 1)
        let erasing = DraftingLoaderTiming.trim(at: (DraftingLoaderTiming.holdEnd + DraftingLoaderTiming.eraseEnd) / 2)
        XCTAssertGreaterThan(erasing.from, 0)
        XCTAssertEqual(erasing.to, 1)
        let rest = DraftingLoaderTiming.trim(at: DraftingLoaderTiming.cycle - 0.05)
        XCTAssertEqual(rest.from, rest.to, "Nothing visible in the rest beat")
        // Loops.
        XCTAssertEqual(DraftingLoaderTiming.trim(at: DraftingLoaderTiming.cycle + 0.4).to,
                       DraftingLoaderTiming.trim(at: 0.4).to, accuracy: 0.0001)
    }

    func testReduceMotionPulseStaysGentle() {
        for i in 0..<100 {
            let value = DraftingLoaderTiming.pulse(at: Double(i) * 0.05)
            XCTAssertGreaterThanOrEqual(value, 0.55 - 0.0001)
            XCTAssertLessThanOrEqual(value, 0.9 + 0.0001)
        }
    }

    func testDraftingTintsAreTheBrandTokens() {
        XCTAssertEqual(DraftingSurface.blueprint.lineHex(for: .light), "8FD3FF")
        XCTAssertEqual(DraftingSurface.blueprint.lineHex(for: .dark), "8FD3FF")
        XCTAssertEqual(DraftingSurface.adaptive.lineHex(for: .light), "2369B5")
        XCTAssertEqual(DraftingSurface.adaptive.lineHex(for: .dark), "60A8E6")
    }
}
