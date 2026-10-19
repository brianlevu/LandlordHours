import XCTest

/// Screens2 lane: real presses and swipes for the three 2.0 redesign recordings.
/// Prints "DEMO_START <epoch>" so the host script can trim the recording.
final class Screens2DemoTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        let appearance = ProcessInfo.processInfo.environment["SANDBOX_APPEARANCE"] ?? "light"
        app.launchArguments = ["-LHScreen", screen, "-appearance", appearance, "-recording", "YES"]
        app.launch()
        return app
    }

    private func mark() { print("DEMO_START \(Date().timeIntervalSince1970)") }

    func testHoldToDelete() {
        let app = launch("delete-hold")
        let hold = app.otherElements["delete.hold"].exists ? app.otherElements["delete.hold"] : app.buttons["delete.hold"]
        XCTAssertTrue(hold.waitForExistence(timeout: 10))
        sleep(1)
        mark()
        sleep(1)
        // A short press fills part-way, then snaps back on release.
        hold.press(forDuration: 0.7)
        sleep(1)
        // A full hold deletes.
        hold.press(forDuration: 1.8)
        sleep(3)
    }

    func testTodaySwipe() {
        let app = launch("today-confirm")
        let row = app.descendants(matching: .any)["today.row.plumber"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        sleep(2)
        mark()
        sleep(1)
        // Leading swipe: log as suggested.
        let a = row.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        let b = row.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: 300, thenHoldForDuration: 0.15)
        sleep(3)
        // Trailing swipe: not work, with the Undo toast.
        let row2 = app.descendants(matching: .any)["today.row.sam"]
        XCTAssertTrue(row2.waitForExistence(timeout: 5))
        let c = row2.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let d = row2.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        c.press(forDuration: 0.05, thenDragTo: d, withVelocity: 300, thenHoldForDuration: 0.15)
        sleep(4)
    }

    func testLogVoiceFill() {
        let app = launch("log-voice-demo")
        XCTAssertTrue(app.descendants(matching: .any)["log.mic"].waitForExistence(timeout: 10))
        mark()
        sleep(12)
    }
}
