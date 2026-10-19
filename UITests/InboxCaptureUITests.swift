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

    /// Slow swipe-log + undo for the 30 fps video (recorded outside the test with simctl).
    func testRecordSwipeLogUndo() {
        launch(seed: "inbox", scheme: "light")
        let showing = app.descendants(matching: .any)["inbox.row.cal:debug-showing"]
        XCTAssertTrue(showing.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1.5)
        let start = showing.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        let end = showing.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 600, thenHoldForDuration: 0.1)
        let undo = app.buttons["inbox.undo"]
        if !undo.waitForExistence(timeout: 2), app.buttons["inbox.swipe.log"].exists {
            app.buttons["inbox.swipe.log"].tap()
        }
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 1.6)
        undo.tap()
        XCTAssertTrue(showing.waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 2.0)
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
        XCTAssertTrue(app.descendants(matching: .any)["inbox.row.cal:debug-showing"].waitForExistence(timeout: 15))
        shoot("inbox", scheme)
        app.swipeUp()
        shoot("inbox-scrolled", scheme)

        // 2. Confirm sheet (scheduled hours, spouse on).
        app.swipeDown()
        let plumber = app.descendants(matching: .any)["inbox.row.cal:debug-plumber"]
        if plumber.waitForExistence(timeout: 5) { plumber.tap() }
        XCTAssertTrue(app.buttons["confirm.log"].waitForExistence(timeout: 5))
        shoot("confirm-sheet", scheme)

        // 2b. Confirm sheet for a not-sure, no-property item.
        launch(seed: "inbox", scheme: scheme)
        let sam = app.descendants(matching: .any)["inbox.row.cal:debug-call-sam"]
        if sam.waitForExistence(timeout: 15) { sam.tap() }
        XCTAssertTrue(app.buttons["confirm.log"].waitForExistence(timeout: 5))
        shoot("confirm-sheet-notsure", scheme)

        // 3. Empty inbox (calendar on).
        launch(seed: "empty", scheme: scheme)
        XCTAssertTrue(app.descendants(matching: .any)["inbox.empty"].waitForExistence(timeout: 15))
        shoot("inbox-empty", scheme)

        // 4. What's new opt-in (upgraders), with the notification preview on.
        launch(seed: "backfill", scheme: scheme, extra: ["-LHShowWhatsNew", "-LHFakeCalendar", "granted", "-LHHoldBackfillScan"], tab: "0")
        XCTAssertTrue(app.descendants(matching: .any)["capture.whatsNew"].waitForExistence(timeout: 15))
        shoot("whatsnew", scheme)
        app.descendants(matching: .any)["capture.toggle.eventPrompts"].tap()
        shoot("whatsnew-prompts-on", scheme)

        // 5. Backfill intro: scanning (held halfway), then results.
        app.buttons["capture.priming.continue"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["backfill.progress"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.0)
        shoot("backfill-scanning", scheme)
        launch(seed: "backfill", scheme: scheme, extra: ["-LHFakeCalendar", "granted"])
        let setup = app.buttons["inbox.empty.setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 15))
        setup.tap()
        app.buttons["capture.priming.continue"].tap()
        XCTAssertTrue(app.staticTexts["backfill.headline"].waitForExistence(timeout: 15))
        shoot("backfill-results", scheme)

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
        XCTAssertTrue(app.descendants(matching: .any)["capture.onboarding"].waitForExistence(timeout: 15))
        shoot("onboarding-priming", scheme)
    }
}
