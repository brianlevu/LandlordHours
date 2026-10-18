import XCTest

/// Drives real taps and swipes for the three motion recordings. Prints a wall-clock marker
/// ("DEMO_START <epoch>") so the host script can trim the screen recording to the action.
final class SandboxDemoTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        let appearance = ProcessInfo.processInfo.environment["SANDBOX_APPEARANCE"] ?? "light"
        app.launchArguments = ["-screen", screen, "-appearance", appearance]
        app.launch()
        return app
    }

    private func mark() {
        print("DEMO_START \(Date().timeIntervalSince1970)")
    }

    func testConfirmInInbox() {
        let app = launch("inbox")
        let row = app.buttons["row-plumber"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        sleep(1)
        mark()
        sleep(1)
        row.tap()
        let plus = app.buttons["hours-plus"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        sleep(1)
        plus.tap()
        usleep(600_000)
        app.buttons["confirm-log"].tap()
        sleep(3)
        // Leading full swipe confirms the next one
        let showing = app.buttons["row-showing"]
        XCTAssertTrue(showing.waitForExistence(timeout: 5))
        showing.swipeRight(velocity: .slow)
        sleep(1)
        if app.buttons["Log"].exists { app.buttons["Log"].tap() }
        sleep(3)
    }

    func testSwipeToDismiss() {
        let app = launch("inbox")
        let row = app.buttons["row-showing"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        sleep(1)
        mark()
        sleep(1)
        // Slow partial drag reveals the trailing action, then tap it.
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 250, thenHoldForDuration: 0.4)
        sleep(1)
        let notWork = app.buttons["Not work"]
        if notWork.waitForExistence(timeout: 2) { notWork.tap() }
        sleep(2)
        // A second one with a full flick
        let row2 = app.buttons["row-insurance"]
        if row2.waitForExistence(timeout: 3) {
            row2.swipeLeft(velocity: .fast)
        }
        sleep(3)
    }

    func testReceiptCapture() {
        let app = launch("share")
        let plus = app.buttons["receipt-plus"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        mark()
        sleep(2)
        plus.tap()
        usleep(700_000)
        plus.tap()
        usleep(700_000)
        plus.tap()
        sleep(1)
        app.buttons["receipt-save"].tap()
        sleep(3)
    }
}
