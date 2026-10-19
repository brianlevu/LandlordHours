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

    /// Full swipe right; falls back to tapping the revealed action.
    private func swipeLog(_ element: XCUIElement) {
        element.swipeRight(velocity: .fast)
        if !undo.waitForExistence(timeout: 2) {
            let action = app.buttons["inbox.swipe.log"]
            if action.exists { action.tap() }
        }
    }

    private func swipeDismiss(_ element: XCUIElement) {
        element.swipeLeft(velocity: .fast)
        if !undo.waitForExistence(timeout: 2) {
            let action = app.buttons["inbox.swipe.dismiss"]
            if action.exists { action.tap() }
        }
    }

    func testInboxGroupsBadgesAndTabCount() {
        launch("inbox")
        XCTAssertTrue(row("showing").waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Today"].exists || app.staticTexts["TODAY"].exists)
        XCTAssertTrue(app.staticTexts["Earlier"].exists || app.staticTexts["EARLIER"].exists)
        XCTAssertTrue(row("call-sam").label.contains("Not sure"), row("call-sam").label)
        XCTAssertTrue(row("hardware").label.contains("Might already be logged"), row("hardware").label)
        XCTAssertTrue(app.descendants(matching: .any)["inbox.backfillBanner"].exists)
        XCTAssertEqual(app.buttons["tab.inbox"].value as? String, "8 to confirm")
    }

    func testSwipeLogThenUndoThenCommit() {
        launch("inbox")
        let showing = row("showing")
        XCTAssertTrue(showing.waitForExistence(timeout: 15))
        swipeLog(showing)
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "Undo toast after a swipe-log")
        XCTAssertFalse(row("showing").exists, "Row leaves at once")
        XCTAssertEqual(app.buttons["tab.inbox"].value as? String, "7 to confirm")
        undo.tap()
        XCTAssertTrue(row("showing").waitForExistence(timeout: 3), "Undo brings it back")
        XCTAssertEqual(app.buttons["tab.inbox"].value as? String, "8 to confirm")

        swipeLog(row("showing"))
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        XCTAssertTrue(undo.waitForNonExistence(timeout: 8), "Toast times out and the log is written")
        XCTAssertFalse(row("showing").exists)
        // The confirmed entry is in Records.
        app.buttons["tab.records"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Showing'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testSwipeOnAlreadyLoggedItemOpensSheetInstead() {
        launch("inbox")
        let hardware = row("hardware")
        XCTAssertTrue(hardware.waitForExistence(timeout: 15))
        app.swipeUp()
        swipeLog(hardware)
        XCTAssertTrue(app.descendants(matching: .any)["confirm.mightAlreadyBeLogged"].waitForExistence(timeout: 5))
        XCTAssertFalse(undo.exists, "Nothing logged without the sheet")
    }

    func testSwipeLeftMarksNotLandlordWork() {
        launch("inbox")
        let turnover = row("turnover")
        XCTAssertTrue(turnover.waitForExistence(timeout: 15))
        swipeDismiss(turnover)
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Marked not landlord work"].exists)
        XCTAssertFalse(row("turnover").exists)
    }

    func testConfirmSheetLogsWithSpouse() {
        launch("inbox")
        let plumber = row("plumber")
        XCTAssertTrue(plumber.waitForExistence(timeout: 15))
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
        XCTAssertTrue(depot.waitForExistence(timeout: 15))
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
        XCTAssertTrue(sam.waitForExistence(timeout: 15))
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
        XCTAssertTrue(inspection.waitForExistence(timeout: 15))
        app.swipeUp()
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
        XCTAssertTrue(setup.waitForExistence(timeout: 15))
        setup.tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.privacyFooter"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["capture.toggle.eventPrompts"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.notificationPreview"].waitForExistence(timeout: 3))
        app.buttons["capture.priming.continue"].tap()
        let headline = app.staticTexts["backfill.headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 15))
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
        XCTAssertTrue(setup.waitForExistence(timeout: 15))
        setup.tap()
        app.buttons["capture.priming.continue"].tap()
        let first = app.buttons["backfill.row.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        first.tap()
        let log = app.buttons["confirm.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        log.tap()
        XCTAssertTrue(app.staticTexts["We found 22 visits that look like landlord work"].waitForNonExistence(timeout: 5),
                      "Count drops to 21 after a confirm")
        XCTAssertTrue(app.staticTexts["We found 21 visits that look like landlord work"].exists)
    }

    func testWhatsNewNotNowKeepsEverythingOff() {
        launch("backfill", extra: ["-LHShowWhatsNew", "-LHInitialTab", "0"])
        let whatsNew = app.descendants(matching: .any)["capture.whatsNew"]
        XCTAssertTrue(whatsNew.waitForExistence(timeout: 15), "Upgraders see the intro once")
        app.buttons["capture.priming.notNow"].tap()
        XCTAssertTrue(whatsNew.waitForNonExistence(timeout: 5))
        app.buttons["tab.inbox"].tap()
        XCTAssertTrue(app.buttons["inbox.empty.setup"].waitForExistence(timeout: 5), "Calendar suggestions stay off")
    }

    func testWhatsNewDeniedCalendarShowsSettingsPath() {
        launch("backfill", extra: ["-LHShowWhatsNew", "-LHFakeCalendar", "denied"])
        XCTAssertTrue(app.descendants(matching: .any)["capture.whatsNew"].waitForExistence(timeout: 15))
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
        XCTAssertTrue(app.descendants(matching: .any)["capture.onboarding"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["capture.privacyFooter"].exists)
        let prompts = app.descendants(matching: .any)["capture.toggle.eventPrompts"]
        XCTAssertEqual(prompts.value as? String, "Off", "End-of-event prompts start off")
        app.buttons["capture.priming.notNow"].tap()
        XCTAssertTrue(app.buttons["tab.inbox"].waitForExistence(timeout: 10), "Onboarding finished")
    }
}
