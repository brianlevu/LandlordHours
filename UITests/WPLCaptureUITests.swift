import XCTest

/// WP-L capture journeys for the review videos and stills. Skipped unless
/// `TEST_RUNNER_LH_WPL_CAPTURE=<dir>` is set; each journey writes `<name>.marks` (epoch seconds
/// when the state is on screen, and when it ends) next to the stills, so the host can cut the
/// simulator recording to start on the state with no launch frames.
final class WPLCaptureUITests: XCTestCase {
    private var app: XCUIApplication!
    private var dir: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard let dir = ProcessInfo.processInfo.environment["LH_WPL_CAPTURE"], !dir.isEmpty else {
            throw XCTSkip("Capture run only")
        }
        self.dir = dir
        UITestIsolation.resetStoreKit()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func mark(_ name: String, _ label: String) {
        let line = "\(label) \(Date().timeIntervalSince1970)\n"
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).marks")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func still(_ name: String) {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    /// "light" / "dark", plus an optional suffix (e.g. "-reducemotion") for the still names.
    private var scheme: String {
        (ProcessInfo.processInfo.environment["LH_WPL_SCHEME"] ?? "light") + (ProcessInfo.processInfo.environment["LH_WPL_SUFFIX"] ?? "")
    }
    private var schemeArg: String { ProcessInfo.processInfo.environment["LH_WPL_SCHEME"] ?? "light" }

    // (a) Cold launch with a pending pull: Today loads the Blueprint way, then settles.
    func testCaptureA_TodayColdLaunchPendingPull() {
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "emptyMainTabs",
            "-LHTodayHours", "212",
            "-LHSimulatePendingPull", "7",
            "-LHInitialTab", "0",
            "-LHColorScheme", schemeArg,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["today.hero"].waitForExistence(timeout: 20))
        mark("a", "start")
        Thread.sleep(forTimeInterval: 1.6)
        still("today-loading-\(scheme)")
        let settled = NSPredicate(format: "label CONTAINS %@", "212 of 750 hours")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "today.hero").matching(settled)
            .firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2.0)
        still("today-settled-\(scheme)")
        mark("a", "end")
    }

    // (b) The backfill streams into the Inbox while the user taps around.
    func testCaptureB_BackfillStreamingWhileTappingAround() {
        app.launchArguments = InboxUITests.arguments(seed: "backfill", scheme: schemeArg, extra: [
            "-LHFakeCalendar", "granted", "-LHBackfillStepMs", "700",
        ])
        app.launch()
        let setup = app.buttons["inbox.empty.setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 1.5)
        setup.tap()
        let toggle = app.descendants(matching: .any)["capture.toggle.calendar"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        Thread.sleep(forTimeInterval: 1.0)
        app.buttons["capture.priming.continue"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        mark("b", "start")
        Thread.sleep(forTimeInterval: 1.6)
        still("inbox-backfill-streaming-\(scheme)")
        app.buttons["tab.today"].tap()
        Thread.sleep(forTimeInterval: 1.2)
        still("today-lookingback-\(scheme)")
        Thread.sleep(forTimeInterval: 0.4)
        app.buttons["tab.records"].tap()
        Thread.sleep(forTimeInterval: 1.2)
        app.buttons["tab.inbox"].tap()
        Thread.sleep(forTimeInterval: 1.8)
        still("inbox-backfill-back-\(scheme)")
        mark("b", "end")
        // The house reveal plays when the look-back finishes.
        let review = app.buttons["backfill-review"]
        if review.waitForExistence(timeout: 20) {
            Thread.sleep(forTimeInterval: 2.6)
            still("inbox-backfill-reveal-\(scheme)")
            review.tap()
            Thread.sleep(forTimeInterval: 1.0)
        }
        still("inbox-backfill-done-\(scheme)")
    }

    // (c) The export generates in the background; the "ready" banner opens the share sheet.
    func testCaptureC_ExportInBackgroundThenReadyBanner() {
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "frequent",
            "-LHInitialTab", "3",
            "-LHSlowExport", "3.2",
            "-LHColorScheme", schemeArg,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        let exportButton = app.buttons["reports.export"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 1.5)
        exportButton.tap()
        let generate = app.buttons["export.generatePDF"]
        XCTAssertTrue(generate.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1.0)
        mark("c", "start")
        Thread.sleep(forTimeInterval: 0.6)
        generate.tap()
        Thread.sleep(forTimeInterval: 1.4)
        still("export-generating-\(scheme)")
        app.buttons["Cancel"].firstMatch.tap()
        let banner = app.buttons["export.readyBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "Ready banner after leaving the sheet")
        Thread.sleep(forTimeInterval: 1.4)
        still("export-ready-banner-\(scheme)")
        banner.tap()
        Thread.sleep(forTimeInterval: 2.0)
        still("export-share-\(scheme)")
        mark("c", "end")
    }
}
