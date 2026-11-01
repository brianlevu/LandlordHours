import XCTest

/// 2.3 care plan A (package B): Today's "This season" section, the pushed plan, a row opening Log
/// time with How long empty, one chip tap setting the hours, the done row, and the free-plan lock.
/// Asserts identifiers and states, never English wording (standard C.1a). With `LH_CAPTURE_DIR`
/// set, `testCaptureFrames` writes the c1–c4 frames named after the approved ids.
final class CarePlanUITests: XCTestCase {
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

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func launch(pro: Bool = true, extra: [String] = [], scheme: String = "light") {
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "emptyMainTabs",
            "-LHTodayHours", "420",
            "-LHGoalChoice", "reps750",
            "-LHFixedNow", "2026-10-31T09:41",
            "-LHInitialTab", "0",
            "-LHCraftScroll",
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ] + (pro ? ["-LHCarePro"] : []) + extra
        app.launch()
        // `-LHCareOpen` pushes the plan (no tab bar) or opens Log time soon after Today draws.
        let opens = extra.contains("-LHCareOpen")
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 20) || (opens && (element("care.screen").exists || element("log.sheet").exists)))
        Thread.sleep(forTimeInterval: 1.5)
    }

    /// Scrolls Today until `target` sits above the tab bar.
    private func reveal(_ target: XCUIElement) {
        let bar = app.buttons["tab.today"].frame.minY
        var tries = 0
        while (!target.exists || target.frame.maxY > bar - 8) && tries < 8 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 0.4)
            tries += 1
        }
    }

    // MARK: Journeys

    func testTodayShowsThreeCareRowsAndTheRule() {
        launch()
        let section = element("today.care")
        XCTAssertTrue(section.waitForExistence(timeout: 8), "the This season section is on Today")
        reveal(element("today.care.rule"))
        let rows = section.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'care.row.'"))
        XCTAssertEqual(rows.count, 3, "the 3 most timely items")
        XCTAssertTrue(element("care.row.gutters").exists, "the general plan's first fall item")
        XCTAssertTrue(element("today.care.rule").exists)
        XCTAssertFalse(element("today.care.locked").exists)
    }

    func testARowOpensLogTimeWithHowLongEmptyAndOneChipSetsIt() {
        launch()
        let row = element("care.row.gutters")
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        reveal(row)
        row.tap()
        XCTAssertTrue(element("log.sheet").waitForExistence(timeout: 6))
        let hours = app.buttons["log.hours"]
        XCTAssertTrue(hours.waitForExistence(timeout: 4))
        XCTAssertTrue(hours.label.contains("not chosen"), "How long starts empty: \(hours.label)")
        XCTAssertTrue(app.buttons["log.property"].label.contains("Pine Cabin"), app.buttons["log.property"].label)
        XCTAssertFalse(app.buttons["log.category"].label.contains("not chosen"), "the kind is filled")
        XCTAssertTrue(element("log.careChips").exists, "the chips sit under How long")
        XCTAssertFalse(element("log.careChip.lastTime").exists, "no history, no Last time chip")

        // The Log button never logs a guessed number: tapping it opens the hours instead.
        app.buttons["log.save"].tap()
        XCTAssertFalse(element("shell.toast").waitForExistence(timeout: 1.5), "nothing was saved")
        XCTAssertTrue(element("log.sheet").exists)
        if app.buttons["log.done"].exists { app.buttons["log.done"].tap() }
        app.buttons["log.hours"].tap()   // close the editor the gap opened; the chips come back
        let chip = app.buttons["log.careChip.fixed-30"]
        XCTAssertTrue(chip.waitForExistence(timeout: 4))
        chip.tap()
        XCTAssertFalse(app.buttons["log.hours"].label.contains("not chosen"), app.buttons["log.hours"].label)
        XCTAssertTrue(chip.isSelected, "the tapped chip shows as picked")
        app.buttons["log.save"].tap()
        XCTAssertTrue(element("shell.toast").waitForExistence(timeout: 5), "logged")

        // Today moves on to what's next; the plan shows the item done and it opens the entry.
        XCTAssertTrue(element("care.row.gutters").waitForNonExistence(timeout: 5), "a done item leaves Today's three")
        let header = element("today.care.header")
        reveal(header)
        header.buttons.firstMatch.tap()
        XCTAssertTrue(element("care.screen").waitForExistence(timeout: 5))
        let done = element("care.row.gutters")
        XCTAssertTrue(done.waitForExistence(timeout: 4))
        done.tap()
        XCTAssertTrue(element("entry.detail").waitForExistence(timeout: 5), "a done row opens what was logged")
    }

    func testTheChipsComeFromTheOwnHistory() {
        launch(extra: ["-LHCareHistory", "1.3333333,1,2", "-LHCareOpen", "log"])
        XCTAssertTrue(element("log.sheet").waitForExistence(timeout: 8))
        let last = app.buttons["log.careChip.lastTime"]
        XCTAssertTrue(last.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["log.careChip.typical"].exists)
        XCTAssertTrue(app.buttons["log.hours"].label.contains("not chosen"), "history never prefills the hours")
        last.tap()
        XCTAssertTrue(last.isSelected, "one tap sets the hours")
        XCTAssertFalse(app.buttons["log.hours"].label.contains("not chosen"), app.buttons["log.hours"].label)
    }

    func testSeePlanPushesTheChecklistAndBackReturns() {
        launch(extra: ["-LHCareSeed", "hifi"])
        let header = element("today.care.header")
        XCTAssertTrue(header.waitForExistence(timeout: 8))
        reveal(header)
        header.buttons.firstMatch.tap()
        XCTAssertTrue(element("care.screen").waitForExistence(timeout: 5))
        XCTAssertTrue(element("care.section.now-3").exists, "this season (fall) leads")
        XCTAssertTrue(element("care.section.later-0").exists, "then winter")
        XCTAssertFalse(element("care.section.stays").exists, "no Between stays for long stays")
        XCTAssertTrue(element("care.row.furnaceFilter").exists, "the done item is listed")
        app.buttons["care.back"].tap()
        XCTAssertTrue(element("today.care").waitForExistence(timeout: 5))
    }

    func testShortStaysGetBetweenStays() {
        launch(extra: ["-LHCareSeed", "hifi-str", "-LHCareOpen", "plan-str"])
        XCTAssertTrue(element("care.screen").waitForExistence(timeout: 8))
        XCTAssertTrue(element("care.section.stays").exists)
        XCTAssertTrue(element("care.row.hotTub").exists, "a short-stay, snowy item")
    }

    func testAFreeUserSeesTheLockAndItOpensThePaywall() {
        launch(pro: false)
        let locked = element("today.care.locked")
        XCTAssertTrue(locked.waitForExistence(timeout: 8))
        XCTAssertFalse(element("today.care").exists)
        let unlock = locked.buttons["lock.unlock"]
        reveal(unlock)
        unlock.tap()
        XCTAssertTrue(element("paywall.close").waitForExistence(timeout: 6), "the paywall opens")
    }

    // MARK: Frames (c1–c4 and the extra states)

    func testCaptureFrames() throws {
        let dir = ProcessInfo.processInfo.environment["LH_CAPTURE_DIR"] ?? ""
        try XCTSkipIf(dir.isEmpty, "Captures only (set LH_CAPTURE_DIR)")
        let scheme = ProcessInfo.processInfo.environment["LH_CAPTURE_SCHEME"] ?? "light"
        let shots: [(String, Bool, [String], String)] = [
            ("c1-today-care", true, ["-LHCareSeed", "hifi"], "today.care.rule"),
            ("c2-care-plan", true, ["-LHCareSeed", "hifi", "-LHCareOpen", "plan"], "care.screen"),
            ("c3-care-plan-str", true, ["-LHCareSeed", "hifi-str", "-LHCareOpen", "plan-str"], "care.screen"),
            ("c4-logtime-prefilled", true, ["-LHCareSeed", "hifi", "-LHCareOpen", "log"], "log.careChips"),
            ("c4b-logtime-chips", true, ["-LHCareSeed", "hifi", "-LHCareHistory", "1.3333333,1,2", "-LHCareOpen", "log"], "log.careChip.lastTime"),
            ("c5-today-care-free", false, ["-LHCareSeed", "hifi"], "today.care.locked"),
        ]
        for (name, pro, extra, anchor) in shots {
            app.terminate()
            launch(pro: pro, extra: extra + ["-LHSeedSuggestions", "inbox", "-LHTodayConfirmLimit", "1"], scheme: scheme)
            XCTAssertTrue(element(anchor).waitForExistence(timeout: 10), name)
            Thread.sleep(forTimeInterval: 1.5)
            let shot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(scheme).png"))
        }
    }
}
