import XCTest

/// Recovered timer drafts on Today (the generic draft card that replaced the Track card).
/// Drafts are seeded by the DEBUG `-LHSeedTimerDraft <scenario>` fixture.
final class TimerDraftUITests: XCTestCase {
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

    private func launch(_ scenario: String, scheme: String = "light") {
        app.terminate()
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHSeedTimerDraft", scenario,
            "-LHInitialTab", "0",
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
    }

    private var summary: XCUIElement { app.descendants(matching: .any)["draft.summary"].firstMatch }

    func testShortDraftLogsInOneTapAndDiscardIsSeparate() {
        launch("pausedShort")
        XCTAssertTrue(summary.waitForExistence(timeout: 12))
        XCTAssertTrue(summary.label.contains("stopped when you switched profiles"), summary.label)
        let log = app.buttons["draft.primary"]
        let discard = app.buttons["draft.discard"]
        XCTAssertTrue(log.isHittable)
        XCTAssertTrue(discard.isHittable)
        XCTAssertEqual(log.label, "Log 2m")
        log.tap()
        XCTAssertTrue(log.waitForNonExistence(timeout: 5), "Draft saved and card gone")
        XCTAssertTrue(app.descendants(matching: .any)["shell.toast"].waitForExistence(timeout: 3))
    }

    func testDeletedPropertyAsksWhereItGoes() {
        launch("deletedProperty")
        XCTAssertTrue(summary.waitForExistence(timeout: 12))
        XCTAssertTrue(summary.label.contains("pick where it goes"), summary.label)
        let review = app.buttons["draft.primary"]
        XCTAssertEqual(review.label, "Review")
        review.tap()
        let save = app.buttons["log.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["log.property"].label.contains("Pine Lake Cabin"), "the only rental left is preselected")
        XCTAssertEqual(save.label, "Log 45m")
    }

    func testNoPropertiesShowsTheRunTimeAndDiscard() {
        launch("noProperties")
        XCTAssertTrue(summary.waitForExistence(timeout: 12))
        XCTAssertTrue(summary.label.contains("Timer ran 45 min"), summary.label)
        XCTAssertTrue(app.buttons["draft.discard"].isHittable)
        app.buttons["draft.discard"].tap()
        XCTAssertTrue(summary.waitForNonExistence(timeout: 5))
    }

    func testCappedDraftOffersReviewNotOneTapLog() {
        launch("forgotten24h")
        XCTAssertTrue(summary.waitForExistence(timeout: 12))
        XCTAssertTrue(summary.label.contains("We stopped counting at 24h"), summary.label)
        let review = app.buttons["draft.primary"]
        XCTAssertEqual(review.label, "Review", "No one-tap log for a capped draft")
        review.tap()
        let ran = app.descendants(matching: .any)["log.timer.ran"]
        XCTAssertTrue(ran.waitForExistence(timeout: 6))
        XCTAssertTrue(ran.label.contains("We stopped counting at 24h"), ran.label)
        XCTAssertTrue(app.buttons["log.save"].isEnabled)
    }

    func testTwoDraftsSayThereIsMore() {
        launch("twoPending")
        XCTAssertTrue(summary.waitForExistence(timeout: 12))
        XCTAssertTrue(summary.label.contains("+1 more"), summary.label)
    }
}
