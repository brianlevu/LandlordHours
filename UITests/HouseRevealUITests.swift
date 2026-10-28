import XCTest

/// Reveal on return (standard §B.3 `houseReveal`, Brian 2026-10-26): the house plays its change
/// when Today can be seen, once, never under a sheet or on another tab.
///
/// Seeded on the 100-hour test at 45h (`frame70`). 47h is `framing`, so a 2h save plays the timber
/// drop. `-LHRevealProbe` exposes the ordered reveal events as the hidden `today.revealProbe`
/// element ("logSheetDismissed,reveal:timberDrop:45->47").
final class HouseRevealUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        UITestIsolation.resetStoreKit()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    private func launch(extra: [String] = []) {
        app.terminate()
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "emptyMainTabs",
            "-LHGoalChoice", "mp100",
            "-LHTodayHours", "45",
            "-LHRevealProbe",
            "-LHInitialTab", "0",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ] + extra
        app.launch()
    }

    private var probe: XCUIElement { app.descendants(matching: .any)["today.revealProbe"].firstMatch }
    private var hero: XCUIElement { app.descendants(matching: .any)["today.hero"].firstMatch }

    private func waitForProbe(_ label: String, timeout: TimeInterval = 12) -> Bool {
        let match = app.descendants(matching: .any).matching(identifier: "today.revealProbe")
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
        return match.waitForExistence(timeout: timeout)
    }

    private func waitForNumber(_ text: String, timeout: TimeInterval = 12) -> Bool {
        app.descendants(matching: .any).matching(identifier: "today.number")
            .matching(NSPredicate(format: "label == %@", text)).firstMatch.waitForExistence(timeout: timeout)
    }

    private func waitForHero(containing text: String, timeout: TimeInterval = 12) -> Bool {
        app.descendants(matching: .any).matching(identifier: "today.hero")
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.waitForExistence(timeout: timeout)
    }

    /// The ordered events (tab changes, the sheet's dismissal, each reveal), read on Today.
    private func probeLabel() -> String { probe.exists ? probe.label : "<missing>" }

    private func pause(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "pause")], timeout: seconds)
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func tapRetrying(_ element: XCUIElement, until result: XCUIElement, attempts: Int = 5) {
        for _ in 0..<attempts where !result.exists {
            if element.exists, element.isHittable { element.tap() }
            if result.waitForExistence(timeout: 3) { return }
        }
        XCTAssertTrue(result.exists, "Tapping \(element) never showed \(result)")
    }

    private func settledOnToday() {
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        XCTAssertTrue(waitForNumber("45"), "Seeded at 45h")
        XCTAssertTrue(waitForHero(containing: "Frame going up"))
        XCTAssertTrue(waitForProbe("none"), "First sight plays nothing: \(probeLabel())")
    }

    // MARK: Log time sheet

    /// Logging from Today: the drop waits until the sheet has finished dismissing, then plays once.
    func testLoggingThroughTheSheetPlaysTheDropOnlyAfterTheSheetIsGone() {
        launch()
        settledOnToday()

        let logTab = app.buttons["tab.logTime"].exists ? app.buttons["tab.logTime"] : app.tabBars.firstMatch.buttons["Log time"]
        XCTAssertTrue(logTab.waitForExistence(timeout: 8), "The Log time tab")
        logTab.tap()
        let notes = app.descendants(matching: .any)["log.note"].firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 8))
        notes.tap()
        notes.typeText("Fixed the porch steps for 2 hours")
        let save = app.buttons["log.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: save)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(probeLabel(), "none", "Nothing plays while the sheet is up")
        save.tap()

        // The only order allowed: the sheet finishes dismissing, then the drop plays.
        XCTAssertTrue(waitForProbe("logSheetDismissed,reveal:timberDrop:45->47"),
                      "The drop plays after the sheet is gone, once: \(probeLabel())")
        XCTAssertFalse(notes.exists, "The sheet is gone")
        XCTAssertTrue(waitForNumber("47"), "The number rolls as the last timber lands")
        XCTAssertTrue(waitForHero(containing: "Frame finished"))
        pause(4)
        XCTAssertEqual(probeLabel(), "logSheetDismissed,reveal:timberDrop:45->47", "Nothing replays")
        attach("reveal-after-sheet")
    }

    // MARK: Records

    /// An edit in Records plays nothing there; Today plays it once on return, and never again.
    func testEditInRecordsPlaysOnceOnReturnToTodayAndNeverAgain() {
        launch()
        settledOnToday()

        app.buttons["tab.records"].tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "records.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        tapRetrying(row, until: app.buttons["entry.edit"])
        app.buttons["entry.edit"].tap()
        // Package G: the hours are one adjustable LHStepper (its minus and plus are not separate buttons).
        let stepper = app.descendants(matching: .any)["record.hours.stepper"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        // Its plus sits at the trailing end (as InboxUITests.tapStepper taps it).
        for _ in 0..<8 { stepper.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }   // +2h: 45 → 47
        app.buttons["entry.save"].tap()
        XCTAssertTrue(app.buttons["entry.edit"].waitForExistence(timeout: 5), "Saved")
        pause(3)
        app.buttons["entry.back"].tap()                     // back to the list (the record hides the tab bar)
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 5))

        app.buttons["tab.today"].tap()
        // The order proves it: nothing played while Records was showing; the drop plays after the return.
        XCTAssertTrue(waitForProbe("tab.records,tab.today,reveal:timberDrop:45->47"),
                      "Today plays the change once, after the return: \(probeLabel())")
        XCTAssertTrue(waitForNumber("47"))
        XCTAssertTrue(waitForHero(containing: "Frame finished"))
        pause(3.5)
        attach("reveal-after-records")

        // Away and back again: nothing replays.
        app.buttons["tab.records"].tap()
        pause(1.5)
        app.buttons["tab.today"].tap()
        XCTAssertTrue(waitForNumber("47"))
        pause(3.5)
        XCTAssertEqual(probeLabel(), "tab.records,tab.today,reveal:timberDrop:45->47,tab.records,tab.today",
                       "Going back to Today replays nothing")
        XCTAssertTrue(hero.label.contains("Frame finished"), hero.label)

        // A relaunch on the same profile replays nothing either.
        app.terminate()
        app.launchArguments = ["-LHRevealProbe", "-LHInitialTab", "0", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(waitForNumber("47", timeout: 20))
        pause(3)
        XCTAssertEqual(probeLabel(), "none", "Seen before the relaunch: nothing replays")
    }
}
