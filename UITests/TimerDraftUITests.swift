import XCTest

/// Track timer-draft card: accessibility of Save/Discard and visual-gate captures.
/// Drafts are seeded by the DEBUG `-LHSeedTimerDraft <scenario>` fixture.
final class TimerDraftUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
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
            "-LHSeedTimerDraft", scenario,
            "-LHInitialTab", "2",
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
    }

    func testSaveAndDiscardAreSeparateHittableButtons() {
        launch("pausedShort")
        let summary = app.descendants(matching: .any)["timerDraft.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.label.contains("paused when you switched profiles"), summary.label)

        let save = app.buttons["timerDraft.save"]
        let discard = app.buttons["timerDraft.discard"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(discard.exists)
        XCTAssertTrue(save.isHittable)
        XCTAssertTrue(discard.isHittable)
        XCTAssertTrue(save.label.contains("Save 2 min"), save.label)

        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "Draft saved and card dismissed")
    }

    func testDeletedPropertyOffersPicker() {
        launch("deletedProperty")
        XCTAssertTrue(app.buttons["timerDraft.pickProperty"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["timerDraft.discard"].isHittable)
    }

    func testCaptureTimerDraftFramesLight() { captureAll(scheme: "light") }
    func testCaptureTimerDraftFramesDark() { captureAll(scheme: "dark") }

    private func captureAll(scheme: String) {
        let scenarios = [
            ("a-paused-2min", "pausedShort"),
            ("b-forgotten-24h", "forgotten24h"),
            ("c-two-pending", "twoPending"),
            ("d-deleted-property", "deletedProperty"),
            ("e-no-properties", "noProperties"),
            ("f-paused-over-24h", "pausedOver24h")
        ]
        for (name, scenario) in scenarios {
            launch(scenario, scheme: scheme)
            XCTAssertTrue(app.descendants(matching: .any)["timerDraft.summary"].waitForExistence(timeout: 10), name)
            Thread.sleep(forTimeInterval: 1.0)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "\(name)-\(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
