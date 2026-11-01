import XCTest

/// Performance baseline for Dormer (LandlordHours): launch, tab switches, Records scrolling,
/// Log time and the PDF export, measured with XCTApplicationLaunchMetric, scroll-hitch signposts
/// (XCTOSSignpostMetric), XCTMemoryMetric and XCTClockMetric.
///
/// Run it through `scripts/qa/perf_check.sh` so the result bundle is summarised the same way
/// every time. Iteration count comes from `TEST_RUNNER_PERF_ITERATIONS` (default 5).
///
/// This class never edits app code. It drives the DEBUG launch fixtures that every other UI test
/// uses (`-LHMockScenario`, `-LHInitialTab`), so numbers are Debug-build numbers: compare a
/// release to a release on the same device, never to a Release or App Store build.
final class PerfMetricsUITests: XCTestCase {
    private var app: XCUIApplication!

    private var iterations: Int {
        Int(ProcessInfo.processInfo.environment["PERF_ITERATIONS"] ?? "") ?? 5
    }

    /// `manual: true` lets a test call startMeasuring()/stopMeasuring() once per iteration, so
    /// set-up and tear-down (closing a sheet, terminating the app) stay out of the numbers.
    private func options(manual: Bool = false) -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = max(iterations, 1)
        if manual { options.invocationOptions = [.manuallyStart, .manuallyStop] }
        return options
    }

    override func setUp() {
        super.setUp()
        // No StoreKit reset: the perf run never buys anything and the shared helper fails with
        // "notEntitled" on a plain simulator, which would mark every perf test failed.
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    // MARK: Cold launch to Today

    func testColdLaunchToToday() {
        // Warm-up: the first launch after an install pays for dyld and the keychain/StoreKit
        // set-up; it is not the number users feel on a second launch.
        launch(scenario: "occasional", tab: 0)
        XCTAssertTrue(waitForTab("tab.today", "Today", selected: true))
        app.terminate()

        // Two launch metrics: first frame (what the user sees) and "responsive" (first frame plus
        // the app accepting input). Clock is launch + Today selected, XCUITest idle waits included.
        measure(metrics: [XCTApplicationLaunchMetric(),
                          XCTApplicationLaunchMetric(waitUntilResponsive: true),
                          XCTClockMetric(),
                          XCTMemoryMetric(application: app)],
                options: options(manual: true)) {
            startMeasuring()
            launch(scenario: "occasional", tab: 0)
            XCTAssertTrue(waitForTab("tab.today", "Today", selected: true), "Today did not come up")
            stopMeasuring()
            app.terminate()
        }
    }

    // MARK: Idle Today (sustained CPU)

    /// Today sits still for 20 s. An ambient animation or a runaway update loop shows up here as
    /// CPU time, which is how iPad cpu_resource reports (SwiftUI update cycle, 90 s at high CPU)
    /// would be caught before a release instead of in the field.
    func testIdleTodayCPU() {
        launch(scenario: "occasional", tab: 0)
        XCTAssertTrue(waitForTab("tab.today", "Today", selected: true))
        Thread.sleep(forTimeInterval: 3)   // let the launch splash and first-run work finish
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app)],
                options: options()) {
            Thread.sleep(forTimeInterval: 20)
        }
    }

    // MARK: Today -> Inbox -> Records -> Rentals

    func testTabSwitches() {
        launch(scenario: "occasional", tab: 0)
        XCTAssertTrue(waitForTab("tab.today", "Today", selected: true))
        // One lap first so lazy tabs are built; the measured laps are the steady state.
        lap()

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(application: app)] + hitchMetrics(),
                options: options()) {
            lap()
        }
    }

    private func lap() {
        for (id, label) in [("tab.inbox", "Inbox"), ("tab.records", "Records"),
                            ("tab.properties", "Rentals"), ("tab.today", "Today")] {
            tapTab(id, label)
            XCTAssertTrue(waitForTab(id, label, selected: true), "\(label) did not become selected")
        }
    }

    // MARK: Records scroll (hitches)

    /// The spec's seed: 'occasional' (one rental, light monthly logging).
    func testRecordsScrollOccasional() {
        scrollRecords(scenario: "occasional")
    }

    /// A longer list, so the scroll has real distance. Same metrics; reported separately.
    func testRecordsScrollFrequent() {
        scrollRecords(scenario: "frequent")
    }

    private func scrollRecords(scenario: String) {
        launch(scenario: scenario, tab: 6)
        let screen = element("records.screen")
        XCTAssertTrue(screen.waitForExistence(timeout: 20), "Records did not open")
        // Wait for rows so the list is populated before the first measured drag.
        _ = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "records.row.")).firstMatch
            .waitForExistence(timeout: 10)

        measure(metrics: [XCTOSSignpostMetric.scrollDraggingMetric,
                          XCTOSSignpostMetric.scrollDecelerationMetric,
                          XCTClockMetric(),
                          XCTMemoryMetric(application: app)] + hitchMetrics(),
                options: options()) {
            // The window, not the screen element: on iPad the Records container reports an empty
            // visible frame and cannot be swiped directly.
            let list = app.windows.firstMatch
            list.swipeUp(velocity: .fast)
            list.swipeUp(velocity: .fast)
            list.swipeDown(velocity: .fast)
            list.swipeDown(velocity: .fast)
        }
    }

    // MARK: Log time

    func testOpenLogTime() {
        launch(scenario: "occasional", tab: 0)
        XCTAssertTrue(waitForTab("tab.today", "Today", selected: true))
        // Warm the sheet once.
        openAndCloseLogTime()

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(application: app)] + hitchMetrics(),
                options: options(manual: true)) {
            startMeasuring()
            tapTab("tab.logTime", "Log time")
            XCTAssertTrue(element("log.note").waitForExistence(timeout: 10), "Log time did not open")
            stopMeasuring()
            closeSheet()
        }
    }

    private func openAndCloseLogTime() {
        tapTab("tab.logTime", "Log time")
        XCTAssertTrue(element("log.note").waitForExistence(timeout: 10))
        closeSheet()
    }

    // MARK: Export PDF

    /// Needs Pro, so it runs on the 'frequent' seed (the free 'occasional' seed opens the paywall).
    func testExportPDF() {
        launch(scenario: "frequent", tab: 6)
        XCTAssertTrue(element("records.screen").waitForExistence(timeout: 20))
        // Warm the export once.
        exportOnce()
        closeSheet()

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(application: app)], options: options(manual: true)) {
            startMeasuring()
            exportOnce()
            stopMeasuring()
            closeSheet()
        }
    }

    private func exportOnce() {
        let export = app.buttons["records.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 20), "Records export button missing")
        for _ in 0..<5 where !element("export.preview").exists && !element("export.generatePDF").exists {
            if export.isHittable { export.tap() }
            _ = element("export.generatePDF").waitForExistence(timeout: 3)
        }
        let create = element("export.generatePDF")
        let local = element("export.createLocal")
        if create.waitForExistence(timeout: 8), create.isEnabled {
            create.tap()
        } else if local.exists {
            local.tap()
        }
        XCTAssertTrue(element("export.sharePDF").waitForExistence(timeout: 60), "PDF was not produced")
    }

    // MARK: Helpers

    /// Whole-app hitch time (XCTHitchMetric) needs the iOS 26 SDK runtime; older OSes still get
    /// the scroll signpost durations.
    private func hitchMetrics() -> [XCTMetric] {
        if #available(iOS 26.0, *) { return [XCTHitchMetric(application: app)] }
        return []
    }

    private func launch(scenario: String, tab: Int) {
        app.terminate()
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", scenario,
            "-LHInitialTab", "\(tab)",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// A tab control by identifier, falling back to the visible label (iPad can lay the shell
    /// out as a floating bar or a sidebar).
    private func tabControl(_ id: String, _ label: String) -> XCUIElement {
        let byId = app.buttons[id].firstMatch
        if byId.exists { return byId }
        let byLabel = app.tabBars.buttons[label].firstMatch
        if byLabel.exists { return byLabel }
        return element(id)
    }

    private func tapTab(_ id: String, _ label: String) {
        let control = tabControl(id, label)
        XCTAssertTrue(control.waitForExistence(timeout: 10), "tab \(label) missing")
        control.tap()
    }

    private func waitForTab(_ id: String, _ label: String, selected: Bool) -> Bool {
        let control = tabControl(id, label)
        guard control.waitForExistence(timeout: 20) else { return false }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if control.isSelected == selected { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    private func closeSheet() {
        let close = app.buttons["sheet.close"].firstMatch
        if close.waitForExistence(timeout: 3) {
            close.tap()
        } else {
            app.swipeDown(velocity: .fast)
        }
        let deadline = Date().addingTimeInterval(5)
        while close.exists && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    }
}
