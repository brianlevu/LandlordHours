import XCTest

/// WP3 inbox journeys. Suggestions are seeded by the DEBUG `-LHSeedSuggestions <scenario>` hook;
/// `-LHFakeCalendar` / `-LHFakeNotifications` stand in for the system permission alerts.
final class InboxUITests: XCTestCase {
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

    static func arguments(seed: String, scheme: String = "light", extra: [String] = []) -> [String] {
        [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "emptyMainTabs",
            "-LHSeedSuggestions", seed,
            "-LHInitialTab", "5",
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            // Pin the inbox clock so times and groups don't depend on when tests run.
            "-LHFixedNow", "2026-10-16T15:00",
        ] + extra
    }

    private func launch(_ seed: String, extra: [String] = []) {
        app.terminate()
        app.launchArguments = Self.arguments(seed: seed, extra: extra)
        app.launch()
    }

    private func row(_ key: String) -> XCUIElement {
        app.descendants(matching: .any)["inbox.row.cal:debug-\(key)"]
    }

    private var undo: XCUIElement { app.buttons["inbox.undo"] }

    /// Waits for an element, then for the launch bridge and seed reload to settle, so the next
    /// tap or swipe is not swallowed by a transition.
    @discardableResult
    private func settle(_ element: XCUIElement, timeout: TimeInterval = 20) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        let deadline = Date().addingTimeInterval(5)
        while !element.isHittable, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        Thread.sleep(forTimeInterval: 1.0)
        return element.exists
    }

    /// Full swipe right; falls back to tapping the revealed action.
    /// Scrolls the inbox until a below-the-fold row is on screen (the list is lazy).
    @discardableResult
    private func scrollTo(_ element: XCUIElement) -> Bool {
        _ = settle(row("plumber"))
        var tries = 0
        while !isClearOfTabBar(element), tries < 6 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
        Thread.sleep(forTimeInterval: 0.6)
        return isClearOfTabBar(element)
    }

    /// On screen and not under the floating tab bar (XCUI calls covered rows "hittable").
    private func isClearOfTabBar(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let barTop = app.buttons["tab.inbox"].frame.minY
        return element.frame.maxY < barTop - 8 && element.frame.minY > 90
    }

    /// Full-width fast drag: a full swipe fires the row's first action without a reveal stop.
    private func fullSwipe(_ element: XCUIElement, right: Bool) {
        let from = element.coordinate(withNormalizedOffset: CGVector(dx: right ? 0.08 : 0.92, dy: 0.5))
        let to = element.coordinate(withNormalizedOffset: CGVector(dx: right ? 1.1 : -0.1, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0)
    }

    private func waitForBadge(_ value: String, timeout: TimeInterval = 6) -> Bool {
        let tab = app.buttons["tab.inbox"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (tab.value as? String) == value { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return (tab.value as? String) == value
    }

    /// Both opt-in switches start off; turning calendar on is the explicit choice.
    private func turnOnCalendar() {
        let calendarSwitch = app.descendants(matching: .any)["capture.toggle.calendar"]
        XCTAssertTrue(calendarSwitch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["capture.priming.continue"].isEnabled, "Turn on waits for a choice")
        calendarSwitch.tap()
    }

    /// WP-H's house reveal shows first when the backfill found anything; continue to the list.
    private func passReveal() {
        let review = app.buttons["backfill-review"]
        if review.waitForExistence(timeout: 15) {
            Thread.sleep(forTimeInterval: 0.5)
            review.tap()
        }
    }

    private func swipeLog(_ element: XCUIElement) {
        fullSwipe(element, right: true)
        if !undo.waitForExistence(timeout: 2), !app.buttons["confirm.log"].exists {
            let action = app.buttons["inbox.swipe.log"]
            if action.exists, isClearOfTabBar(action) { action.tap() }
        }
    }

    private func swipeDismiss(_ element: XCUIElement) {
        fullSwipe(element, right: false)
        if !undo.waitForExistence(timeout: 2) {
            let action = app.buttons["inbox.swipe.dismiss"]
            if action.exists, isClearOfTabBar(action) { action.tap() }
        }
    }

    func testInboxGroupsBadgesAndTabCount() {
        launch("inbox")
        XCTAssertTrue(settle(row("showing")))
        XCTAssertTrue(app.staticTexts["Today"].exists || app.staticTexts["TODAY"].exists)
        XCTAssertTrue(app.staticTexts["This week"].exists || app.staticTexts["THIS WEEK"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["inbox.backfillBanner"].exists)
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Earlier"].waitForExistence(timeout: 3) || app.staticTexts["EARLIER"].exists)
        XCTAssertTrue(row("call-sam").label.contains("Not sure"), row("call-sam").label)
        XCTAssertEqual(app.buttons["tab.inbox"].value as? String, "8 to confirm")
        XCTAssertTrue(row("hardware").exists)
        XCTAssertTrue(row("hardware").label.contains("Might already be logged"), row("hardware").label)
        XCTAssertEqual(app.buttons["tab.inbox"].value as? String, "8 to confirm")
    }

    func testSwipeLogThenUndoThenCommit() {
        launch("inbox")
        let showing = row("showing")
        XCTAssertTrue(settle(showing))
        swipeLog(showing)
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "Undo toast after a swipe-log")
        XCTAssertFalse(row("showing").exists, "Row leaves at once")
        undo.tap()
        XCTAssertTrue(waitForBadge("8 to confirm"), "Undo puts it back in the count")
        XCTAssertTrue(row("showing").waitForExistence(timeout: 6), "Undo brings the row back")

        Thread.sleep(forTimeInterval: 1.0)
        swipeLog(row("showing"))
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForBadge("7 to confirm"))
        XCTAssertTrue(undo.waitForNonExistence(timeout: 9), "Toast times out and the log is written")
        XCTAssertFalse(row("showing").exists)
        // The confirmed entry is in Records.
        app.buttons["tab.records"].tap()
        let oakEntry = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Oak Street Duplex'")).firstMatch
        XCTAssertTrue(oakEntry.waitForExistence(timeout: 5), "Only the confirmed Showing is recorded on Oak Street Duplex")
    }

    func testSwipeOnAlreadyLoggedItemOpensSheetInstead() {
        launch("inbox")
        let hardware = row("hardware")
        XCTAssertTrue(scrollTo(hardware))
        swipeLog(hardware)
        XCTAssertTrue(app.descendants(matching: .any)["confirm.mightAlreadyBeLogged"].waitForExistence(timeout: 5))
        XCTAssertFalse(undo.exists, "Nothing logged without the sheet")
    }

    func testSwipeLeftMarksNotLandlordWork() {
        launch("inbox")
        let turnover = row("turnover")
        XCTAssertTrue(scrollTo(turnover))
        swipeDismiss(turnover)
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Marked not landlord work"].exists)
        XCTAssertFalse(row("turnover").exists)
    }

    func testConfirmSheetLogsWithSpouse() {
        launch("inbox")
        let plumber = row("plumber")
        XCTAssertTrue(settle(plumber))
        plumber.tap()
        XCTAssertTrue(app.buttons["confirm.log"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["confirm.who"].exists, "Spouse is tracked in this seed")
        app.descendants(matching: .any)["confirm.who"].buttons["Spouse"].tap()
        app.buttons["confirm.hours.plus"].tap()
        XCTAssertTrue(app.buttons["confirm.log"].label.hasPrefix("Log"))
        app.buttons["confirm.log"].tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertFalse(row("plumber").exists)
    }

    func testReceiptNeedsHoursBeforeLogging() {
        launch("inbox")
        let depot = app.descendants(matching: .any)["inbox.row.rcpt:homedepot"]
        XCTAssertTrue(settle(depot))
        depot.tap()
        let log = app.buttons["confirm.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        XCTAssertFalse(log.isEnabled, "Hours are required when there are none to propose")
        XCTAssertTrue(app.staticTexts["confirm.missing"].exists)
        app.buttons["confirm.hours.plus"].tap()
        app.buttons["confirm.hours.plus"].tap()
        XCTAssertTrue(log.isEnabled)
        XCTAssertEqual(log.label, "Log 30m")
    }

    func testMuteFromSheet() {
        launch("inbox")
        let sam = row("call-sam")
        XCTAssertTrue(settle(sam))
        sam.tap()
        XCTAssertTrue(app.descendants(matching: .any)["confirm.notSure"].waitForExistence(timeout: 5))
        let mute = app.buttons["confirm.mute"]
        if !mute.isHittable { app.swipeUp() }
        mute.tap()
        let option = app.buttons["Events named \u{201C}Call with Sam\u{201D}"]
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
        XCTAssertTrue(app.staticTexts["We won't suggest events like this"].waitForExistence(timeout: 3))
        XCTAssertFalse(row("call-sam").exists)
    }

    func testNotLandlordWorkFromSheet() {
        launch("inbox")
        let inspection = row("inspection")
        XCTAssertTrue(scrollTo(inspection))
        inspection.tap()
        let dismiss = app.buttons["confirm.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        if !dismiss.isHittable { app.swipeUp() }
        dismiss.tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        XCTAssertFalse(row("inspection").exists)
    }

    func testEmptyInboxThenBackfillFromSetup() {
        launch("backfill", extra: ["-LHFakeCalendar", "granted", "-LHFakeNotifications", "granted"])
        let setup = app.buttons["inbox.empty.setup"]
        XCTAssertTrue(settle(setup))
        setup.tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.privacyFooter"].waitForExistence(timeout: 5))
        turnOnCalendar()
        app.descendants(matching: .any)["capture.toggle.eventPrompts"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.notificationPreview"].waitForExistence(timeout: 3))
        app.buttons["capture.priming.continue"].tap()
        passReveal()
        let headline = app.staticTexts["backfill.headline"]
        XCTAssertTrue(settle(headline))
        XCTAssertEqual(headline.label, "We found 22 visits that look like landlord work")
        XCTAssertTrue(app.buttons["backfill.row.14"].exists || app.buttons["backfill.row.0"].exists)
        app.swipeUp(); app.swipeUp(); app.swipeUp()
        let more = app.buttons["backfill.showMore"]
        XCTAssertTrue(more.waitForExistence(timeout: 3))
        XCTAssertEqual(more.label, "Show 7 more")
        more.tap()
        XCTAssertTrue(app.buttons["backfill.row.20"].waitForExistence(timeout: 3) || app.descendants(matching: .any)["backfill.row.20"].exists)
        app.buttons["backfill.done"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["inbox.backfillBanner"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["tab.inbox"].value as? String, "22 to confirm")
    }

    func testBackfillRowOpensConfirmSheet() {
        launch("backfill", extra: ["-LHFakeCalendar", "granted"])
        let setup = app.buttons["inbox.empty.setup"]
        XCTAssertTrue(settle(setup))
        setup.tap()
        turnOnCalendar()
        app.buttons["capture.priming.continue"].tap()
        passReveal()
        let first = app.buttons["backfill.row.0"]
        XCTAssertTrue(settle(first))
        first.tap()
        let log = app.buttons["confirm.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        log.tap()
        XCTAssertTrue(app.staticTexts["We found 22 visits that look like landlord work"].waitForNonExistence(timeout: 5),
                      "Count drops to 21 after a confirm")
        XCTAssertTrue(app.staticTexts["We found 21 visits that look like landlord work"].exists)
    }

    func testCancelledBackfillCanRunAgain() {
        launch("backfill", extra: ["-LHFakeCalendar", "granted", "-LHHoldBackfillScan"])
        let setup = app.buttons["inbox.empty.setup"]
        XCTAssertTrue(settle(setup))
        setup.tap()
        turnOnCalendar()
        app.buttons["capture.priming.continue"].tap()
        let cancel = app.buttons["backfill.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "Cancel is visible while scanning")
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        let again = app.buttons["inbox.empty.backfill"]
        XCTAssertTrue(again.waitForExistence(timeout: 5), "Not marked done: the look-back can run again")
        XCTAssertFalse(app.descendants(matching: .any)["inbox.backfillBanner"].exists, "Nothing ingested")
    }

    func testWhatsNewNotNowKeepsEverythingOff() {
        launch("backfill", extra: ["-LHShowWhatsNew", "-LHInitialTab", "0"])
        let whatsNew = app.descendants(matching: .any)["capture.whatsNew"]
        XCTAssertTrue(settle(whatsNew), "Upgraders see the intro once")
        app.buttons["capture.priming.notNow"].tap()
        XCTAssertTrue(whatsNew.waitForNonExistence(timeout: 5))
        app.buttons["tab.inbox"].tap()
        XCTAssertTrue(app.buttons["inbox.empty.setup"].waitForExistence(timeout: 5), "Calendar suggestions stay off")
    }

    func testWhatsNewDeniedCalendarShowsSettingsPath() {
        launch("backfill", extra: ["-LHShowWhatsNew", "-LHFakeCalendar", "denied"])
        XCTAssertTrue(settle(app.descendants(matching: .any)["capture.whatsNew"]))
        turnOnCalendar()
        app.buttons["capture.priming.continue"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.denied"].waitForExistence(timeout: 5))
        app.buttons["capture.denied.continue"].tap()
        XCTAssertTrue(app.buttons["inbox.empty.setup"].waitForExistence(timeout: 5))
    }

    func testOnboardingCaptureStepIsOptIn() {
        app.terminate()
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "firstTime",
            "-LHOnboardingStep", "calendar",
            "-LHFakeCalendar", "granted",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        XCTAssertTrue(settle(app.descendants(matching: .any)["capture.onboarding"]))
        XCTAssertTrue(app.descendants(matching: .any)["capture.privacyFooter"].exists)
        let calendarSwitch = app.descendants(matching: .any)["capture.toggle.calendar"]
        XCTAssertTrue(["0", "Off"].contains(calendarSwitch.value as? String ?? ""), "Calendar starts off")
        let prompts = app.descendants(matching: .any)["capture.toggle.eventPrompts"]
        XCTAssertTrue(["0", "Off"].contains(prompts.value as? String ?? ""), "End-of-event prompts start off")
        app.buttons["capture.priming.notNow"].tap()
        XCTAssertTrue(app.buttons["tab.inbox"].waitForExistence(timeout: 10), "Onboarding finished")
    }
}
