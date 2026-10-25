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

    /// The hours stepper is one adjustable element (`LHStepper`): its minus and plus sit at its ends.
    private func tapStepper(plus: Bool) {
        let stepper = app.descendants(matching: .any)["confirm.hours.value"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        stepper.coordinate(withNormalizedOffset: CGVector(dx: plus ? 0.93 : 0.07, dy: 0.5)).tap()
    }

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
        // The native tab bar shrinks away while the list scrolls down (§1.25), taking its buttons out of
        // the tree: then the bar's top is the screen's bottom edge less the bar's height.
        let bar = app.tabBars.firstMatch.buttons["Inbox"]
        let barTop = bar.exists ? bar.frame.minY : app.frame.maxY - 90
        return element.frame.maxY < barTop - 8 && element.frame.minY > 90
    }

    /// Full-width fast drag: a full swipe fires the row's first action without a reveal stop.
    private func fullSwipe(_ element: XCUIElement, right: Bool) {
        let from = element.coordinate(withNormalizedOffset: CGVector(dx: right ? 0.08 : 0.92, dy: 0.5))
        let to = element.coordinate(withNormalizedOffset: CGVector(dx: right ? 1.1 : -0.1, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0)
    }

    /// The Inbox tab's badge as a number. The native tab bar speaks it as "8 items" (the system's
    /// wording), so the tests compare the count, not the words.
    private var badgeNumber: Int? {
        let tab = app.tabBars.firstMatch.buttons["Inbox"]
        guard tab.exists, let text = tab.value as? String else { return nil }
        return Int(text.split(separator: " ").first ?? "")
    }

    private func waitForBadge(_ value: String, timeout: TimeInterval = 6) -> Bool {
        let wanted = Int(value.split(separator: " ").first ?? "")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if badgeNumber == wanted { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return badgeNumber == wanted
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
        XCTAssertTrue(waitForBadge("8 to confirm", timeout: 12))
        // One header per day (standard §1.15a), newest first.
        XCTAssertTrue(app.staticTexts["Today"].exists)
        XCTAssertTrue(app.staticTexts["Wed Oct 14"].exists)
        // Rows carry Confirm / Not work, so they are taller: scroll to each one.
        XCTAssertTrue(scrollTo(row("call-sam")))
        XCTAssertTrue(row("call-sam").label.contains("Not sure"), row("call-sam").label)
        XCTAssertTrue(scrollTo(row("hardware")))
        XCTAssertTrue(row("hardware").label.contains("Might already be logged"), row("hardware").label)
        XCTAssertTrue(scrollTo(row("inspection")))
        XCTAssertTrue(app.staticTexts["Oct 4"].waitForExistence(timeout: 3), "Older days drop the weekday")
        // Scrolling down tucks the native tab bar away (§1.25); back at the top it returns.
        for _ in 0..<5 { app.swipeDown() }
        XCTAssertTrue(waitForBadge("8 to confirm"))
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
        app.tabBars.firstMatch.buttons["Records"].tap()
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
        XCTAssertTrue(app.staticTexts["Marked not rental work"].exists)
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
        tapStepper(plus: true)
        XCTAssertTrue(app.buttons["confirm.log"].label.hasPrefix("Log"))
        app.buttons["confirm.log"].tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertFalse(row("plumber").exists)
    }

    func testReceiptNeedsHoursBeforeLogging() {
        launch("inbox")
        let depot = app.descendants(matching: .any)["inbox.row.rcpt:homedepot"]
        XCTAssertTrue(scrollTo(depot), "The receipt row is below the fold (rows carry Confirm)")
        depot.tap()
        let log = app.buttons["confirm.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        XCTAssertFalse(log.isEnabled, "Hours are required when there are none to propose")
        XCTAssertTrue(app.staticTexts["confirm.missing"].exists)
        tapStepper(plus: true)
        tapStepper(plus: true)
        XCTAssertTrue(log.isEnabled)
        XCTAssertEqual(log.label, "Log 30m")
    }

    func testMuteFromSheet() {
        launch("inbox")
        let sam = row("call-sam")
        XCTAssertTrue(settle(sam))
        XCTAssertTrue(scrollTo(sam))
        sam.tap()
        XCTAssertTrue(app.descendants(matching: .any)["confirm.notSure"].waitForExistence(timeout: 5))
        // The mute link scrolls under the pinned Log / Not rental work bar: bring it clear first.
        let mute = app.buttons["confirm.mute"]
        let pinnedTop = app.buttons["confirm.log"].frame.minY
        var swipes = 0
        while (!mute.exists || mute.frame.maxY > pinnedTop - 8), swipes < 4 {
            app.descendants(matching: .any)["confirm.sheet"].swipeUp()
            swipes += 1
        }
        XCTAssertLessThan(mute.frame.maxY, pinnedTop, "Mute link is above the pinned actions")
        mute.tap()
        let option = app.buttons["Events named \u{201C}Call with Sam\u{201D}"]
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
        XCTAssertTrue(app.staticTexts["We won’t suggest events like this"].waitForExistence(timeout: 3))
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

    /// WP-L: the look-back runs in the background. Setup closes straight to the Inbox, where
    /// suggestions stream in under a compact header; the house reveal plays once when it ends.
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
        XCTAssertTrue(row("bf-0").waitForExistence(timeout: 10), "The look-back's items are rows now")
        XCTAssertTrue(waitForBadge("22 to confirm", timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["inbox.backfill.header"].exists, "Header leaves when done")
        XCTAssertFalse(app.buttons["inbox.empty.backfill"].exists, "A finished look-back is done")
    }

    func testBackfillRowOpensConfirmSheet() {
        launch("backfill", extra: ["-LHFakeCalendar", "granted"])
        let setup = app.buttons["inbox.empty.setup"]
        XCTAssertTrue(settle(setup))
        setup.tap()
        turnOnCalendar()
        app.buttons["capture.priming.continue"].tap()
        passReveal()
        let first = row("bf-0")
        XCTAssertTrue(settle(first))
        first.tap()
        let log = app.buttons["confirm.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        log.tap()
        XCTAssertTrue(waitForBadge("21 to confirm", timeout: 6), "Count drops to 21 after a confirm")
    }

    /// Cancel stays available from the header; a stopped look-back is not done and runs again.
    func testCancelledBackfillCanRunAgain() {
        launch("backfill", extra: ["-LHFakeCalendar", "granted", "-LHHoldBackfillScan"])
        let setup = app.buttons["inbox.empty.setup"]
        XCTAssertTrue(settle(setup))
        setup.tap()
        turnOnCalendar()
        app.buttons["capture.priming.continue"].tap()
        let cancel = app.buttons["backfill.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "Cancel is visible while scanning")
        XCTAssertTrue(row("bf-0").waitForExistence(timeout: 5), "Found items stream in before the end")
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        let again = app.buttons["inbox.backfill.retry"]
        XCTAssertTrue(again.waitForExistence(timeout: 5), "Not marked done: the look-back can run again")
        again.tap()
        XCTAssertTrue(app.buttons["backfill.cancel"].waitForExistence(timeout: 5), "Running again")
    }

    /// Nothing found and calendar access gone: the Inbox keeps the look-back header with the
    /// Settings path instead of a plain empty state (no dead end).
    func testBlockedLookBackWithNothingFoundShowsSettingsPath() {
        launch("backfill", extra: ["-LHFakeCalendar", "granted", "-LHFakeScanBlocked"])
        let setup = app.buttons["inbox.empty.setup"]
        XCTAssertTrue(settle(setup))
        setup.tap()
        turnOnCalendar()
        app.buttons["capture.priming.continue"].tap()
        let blocked = app.descendants(matching: .any)["inbox.backfill.blocked"]
        XCTAssertTrue(blocked.waitForExistence(timeout: 10), "Blocked look-back says so")
        XCTAssertTrue(app.buttons["Settings"].exists, "With a path to Settings")
        XCTAssertFalse(app.descendants(matching: .any)["inbox.empty"].exists, "Not a silent empty state")
    }

    /// Cancelled before anything was found: the header with Run again stays.
    func testCancelledLookBackWithNothingFoundKeepsRunAgain() {
        launch("backfill", extra: ["-LHFakeCalendar", "granted", "-LHBackfillStepMs", "4000"])
        let setup = app.buttons["inbox.empty.setup"]
        XCTAssertTrue(settle(setup))
        setup.tap()
        turnOnCalendar()
        app.buttons["capture.priming.continue"].tap()
        let cancel = app.buttons["backfill.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        XCTAssertTrue(app.buttons["inbox.backfill.retry"].waitForExistence(timeout: 5), "Run again is still offered")
        XCTAssertFalse(app.descendants(matching: .any)["inbox.empty"].exists)
    }

    /// The user can leave the look-back, use the app, and come back to live progress.
    func testLeaveBackfillAndComeBackToStreamingProgress() {
        launch("backfill", extra: ["-LHFakeCalendar", "granted", "-LHHoldBackfillScan"])
        let setup = app.buttons["inbox.empty.setup"]
        XCTAssertTrue(settle(setup))
        setup.tap()
        turnOnCalendar()
        app.buttons["capture.priming.continue"].tap()
        let header = app.descendants(matching: .any)["inbox.backfill.header"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        let halfway = NSPredicate(format: "label CONTAINS %@", "11 of 22 events")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "inbox.backfill.header")
            .matching(halfway).firstMatch.waitForExistence(timeout: 10), header.label)

        // Leave: Today is fully usable while the scan runs.
        app.tabBars.firstMatch.buttons["Today"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["today.hero"].waitForExistence(timeout: 5))
        // Package C's Today shows the scan row until items stream in, then the items themselves.
        let scanning = app.descendants(matching: .any)["today.lookingBack"]
        let streamed = app.descendants(matching: .any)["today.confirm"]
        XCTAssertTrue(scanning.waitForExistence(timeout: 5) || streamed.waitForExistence(timeout: 5),
                      "Today says the look-back is running, not \"Log your first hour\"")
        app.tabBars.firstMatch.buttons["Log time"].tap()
        let close = app.buttons["log.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Log time"].waitForExistence(timeout: 3))

        // Come back: the same run, still streaming, with what it found so far.
        app.tabBars.firstMatch.buttons["Inbox"].tap()
        XCTAssertTrue(header.waitForExistence(timeout: 5), "Progress header is still there")
        XCTAssertTrue(header.label.contains("11 of 22 events"), header.label)
        XCTAssertTrue(header.label.contains("11 found so far"), header.label)
        XCTAssertTrue(app.buttons["backfill.cancel"].exists, "Cancel is still available")
        XCTAssertTrue(row("bf-0").exists, "Streamed items are in the list")
    }

    func testWhatsNewNotNowKeepsEverythingOff() {
        launch("backfill", extra: ["-LHShowWhatsNew", "-LHInitialTab", "0"])
        let whatsNew = app.descendants(matching: .any)["onb.whatsNew"]
        XCTAssertTrue(settle(whatsNew), "Upgraders see the intro once")
        app.buttons["onb-primary"].tap()                       // Your hours now build a house → Continue
        let notNow = app.buttons["onb-link"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 5))
        notNow.tap()                                           // Calendar → Not now: no prompt spent
        XCTAssertTrue(whatsNew.waitForNonExistence(timeout: 5))
        app.tabBars.firstMatch.buttons["Inbox"].tap()
        XCTAssertTrue(app.buttons["inbox.empty.setup"].waitForExistence(timeout: 5), "Calendar suggestions stay off")
    }

    func testWhatsNewDeniedCalendarClosesWithoutTheNote() {
        launch("backfill", extra: ["-LHShowWhatsNew", "-LHFakeCalendar", "denied"])
        let whatsNew = app.descendants(matching: .any)["onb.whatsNew"]
        XCTAssertTrue(settle(whatsNew))
        app.buttons["onb-primary"].tap()
        let look = app.buttons["onb-primary"]
        XCTAssertTrue(look.waitForExistence(timeout: 5))
        XCTAssertEqual(look.label, "Look at my calendar")
        look.tap()
        XCTAssertTrue(whatsNew.waitForNonExistence(timeout: 5), "Denied: no visit-end note, back to Today")
        app.tabBars.firstMatch.buttons["Inbox"].tap()
        XCTAssertTrue(app.buttons["inbox.empty.setup"].waitForExistence(timeout: 5))
    }

    func testOnboardingCalendarStepIsOptIn() {
        app.terminate()
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "firstTime",
            "-LHOnboardingStep", "calendar",
            "-LHFakeCalendar", "granted",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        let look = app.buttons["onb-primary"]
        XCTAssertTrue(settle(look))
        XCTAssertEqual(look.label, "Look at my calendar")
        app.buttons["onb-link"].tap()                          // Not now
        XCTAssertTrue(app.buttons["who-me"].waitForExistence(timeout: 5), "On to Who does the work")
    }
}
