import XCTest

/// Visual-gate frames for WP3 (attachments; exported from the xcresult). Run one theme per boot:
/// `-only-testing:LandlordHoursUITests/InboxCaptureUITests/testCaptureLight` with the simulator
/// appearance pinned to light, then the dark one.
final class InboxCaptureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        UITestIsolation.resetStoreKit()
        continueAfterFailure = true
        app = XCUIApplication()
    }

    func testCaptureLight() { capture(scheme: "light") }
    func testCaptureDark() { capture(scheme: "dark") }

    /// Swipe-right log + Undo, then swipe-left dismiss, for the 30 fps video. The run script
    /// records the simulator and trims to the VIDEO_MARK lines, so the clip starts on the inbox.
    func testRecordSwipeLogUndo() {
        launch(seed: "inbox", scheme: "light")
        let showing = app.descendants(matching: .any)["inbox.row.cal:debug-showing"]
        XCTAssertTrue(showing.waitForExistence(timeout: 20))
        let tab = app.buttons["tab.inbox"]
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '8 to confirm'"), object: tab)
        XCTAssertEqual(XCTWaiter().wait(for: [settled], timeout: 10), .completed)
        Thread.sleep(forTimeInterval: 1.0)
        print("VIDEO_MARK_START \(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 1.0)

        // Swipe right: log (saved at once, Undo for 5 s).
        drag(showing, right: true)
        let undo = app.buttons["inbox.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "Swipe-right logged")
        Thread.sleep(forTimeInterval: 1.8)
        undo.tap()
        XCTAssertTrue(showing.waitForExistence(timeout: 5), "Undo brought it back")
        Thread.sleep(forTimeInterval: 1.8)

        // Swipe left: not landlord work.
        let sam = app.descendants(matching: .any)["inbox.row.cal:debug-call-sam"]
        XCTAssertTrue(sam.waitForExistence(timeout: 5))
        drag(sam, right: false)
        XCTAssertTrue(app.staticTexts["Marked not landlord work"].waitForExistence(timeout: 3), "Swipe-left dismissed")
        Thread.sleep(forTimeInterval: 2.0)
        print("VIDEO_MARK_END \(Date().timeIntervalSince1970)")
    }

    private func drag(_ element: XCUIElement, right: Bool) {
        let from = element.coordinate(withNormalizedOffset: CGVector(dx: right ? 0.08 : 0.92, dy: 0.5))
        let to = element.coordinate(withNormalizedOffset: CGVector(dx: right ? 1.1 : -0.1, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0)
    }

    private func launch(seed: String, scheme: String, extra: [String] = [], tab: String = "5") {
        app.terminate()
        var args = InboxUITests.arguments(seed: seed, scheme: scheme, extra: extra)
        if let index = args.firstIndex(of: "-LHInitialTab") { args[index + 1] = tab }
        app.launchArguments = args
        app.launch()
    }

    private func shoot(_ name: String, _ scheme: String) {
        Thread.sleep(forTimeInterval: 1.2)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(name)-\(scheme)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func capture(scheme: String) {
        // 1. Inbox with items.
        launch(seed: "inbox", scheme: scheme)
        XCTAssertTrue(app.descendants(matching: .any)["inbox.row.cal:debug-showing"].waitForExistence(timeout: 20))
        shoot("inbox", scheme)
        app.swipeUp()
        shoot("inbox-scrolled", scheme)

        // 2. Confirm sheet (scheduled hours, spouse on).
        app.swipeDown()
        let plumber = app.descendants(matching: .any)["inbox.row.cal:debug-plumber"]
        if plumber.waitForExistence(timeout: 5) { Thread.sleep(forTimeInterval: 1.0); plumber.tap() }
        XCTAssertTrue(app.buttons["confirm.log"].waitForExistence(timeout: 5))
        shoot("confirm-sheet", scheme)

        // 2b. Confirm sheet for a not-sure, no-property item.
        launch(seed: "inbox", scheme: scheme)
        let sam = app.descendants(matching: .any)["inbox.row.cal:debug-call-sam"]
        if sam.waitForExistence(timeout: 20) { Thread.sleep(forTimeInterval: 2.0); sam.tap() }
        XCTAssertTrue(app.buttons["confirm.log"].waitForExistence(timeout: 5))
        shoot("confirm-sheet-notsure", scheme)

        // 3. Empty inbox (calendar on).
        launch(seed: "empty", scheme: scheme)
        XCTAssertTrue(app.descendants(matching: .any)["inbox.empty"].waitForExistence(timeout: 20))
        shoot("inbox-empty", scheme)

        // 4. What's new opt-in (upgraders), with the notification preview on.
        launch(seed: "backfill", scheme: scheme, extra: ["-LHShowWhatsNew", "-LHFakeCalendar", "granted", "-LHHoldBackfillScan"], tab: "0")
        XCTAssertTrue(app.descendants(matching: .any)["capture.whatsNew"].waitForExistence(timeout: 20))
        shoot("whatsnew", scheme)
        app.descendants(matching: .any)["capture.toggle.calendar"].tap()
        app.descendants(matching: .any)["capture.toggle.eventPrompts"].tap()
        shoot("whatsnew-prompts-on", scheme)

        // 5. Backfill intro: scanning (held halfway), then results.
        app.buttons["capture.priming.continue"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["backfill.progress"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.0)
        shoot("backfill-scanning", scheme)
        launch(seed: "backfill", scheme: scheme, extra: ["-LHFakeCalendar", "granted"])
        let setup = app.buttons["inbox.empty.setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 2.0)
        setup.tap()
        XCTAssertTrue(app.buttons["capture.priming.continue"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["capture.toggle.calendar"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        app.buttons["capture.priming.continue"].tap()
        let review = app.buttons["backfill-review"]
        if review.waitForExistence(timeout: 15) {
            Thread.sleep(forTimeInterval: 2.8)
            shoot("backfill-reveal", scheme)
            review.tap()
        }
        XCTAssertTrue(app.staticTexts["backfill.headline"].waitForExistence(timeout: 20))
        shoot("backfill-results", scheme)
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.buttons["backfill.showMore"].waitForExistence(timeout: 5))
        shoot("backfill-results-showmore", scheme)

        // 6. Onboarding priming (new users).
        app.terminate()
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "firstTime",
            "-LHOnboardingStep", "calendar",
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["capture.onboarding"].waitForExistence(timeout: 20))
        shoot("onboarding-priming", scheme)
    }
}
