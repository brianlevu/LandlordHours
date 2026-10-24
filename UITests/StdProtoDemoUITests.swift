import XCTest

/// Drives the design-standard mockups for the motion videos (DEBUG screens, -LHStdProto).
/// Not part of any gate: it records today-confirm.mp4 (row confirm, then a system swipe decline).
final class StdProtoDemoUITests: XCTestCase {
    func testTodayConfirmThenSwipeDecline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-LHStdProto", "today", "-LHHomeSeed", "brian", "-LHStdDemo", "confirm", "-LHStdMotionLog",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        // The demo taps the first row's control at 2.0s; let the confirm, the count-up and the toast play.
        Thread.sleep(forTimeInterval: 5.5)
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Showing at Delaney'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: -0.15, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 900, thenHoldForDuration: 0.05)
        Thread.sleep(forTimeInterval: 4.0)
    }

    func testTodayScrollMinimizesTabBar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-LHStdProto", "today", "-LHHomeSeed", "brian", "-LHSkyTime", "day",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        Thread.sleep(forTimeInterval: 2.5)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)),
                    withVelocity: 600, thenHoldForDuration: 0.1)
        Thread.sleep(forTimeInterval: 2.0)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)),
                   withVelocity: 600, thenHoldForDuration: 0.1)
        Thread.sleep(forTimeInterval: 2.0)
        app.buttons["Log time"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2.0)
    }

    /// Scrolls down so the tab bar minimizes, then writes a screenshot to STD_SHOT (host path).
    /// Launch arguments come from STD_ARGS (space separated).
    func testMinimizedBarShot() throws {
        let env = ProcessInfo.processInfo.environment
        let app = XCUIApplication()
        app.launchArguments = (env["STD_ARGS"] ?? "-LHStdProto today").split(separator: " ").map(String.init)
        app.launch()
        Thread.sleep(forTimeInterval: 3.0)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)),
                   withVelocity: 500, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 2.0)
        if let path = env["STD_SHOT"] {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
        }
    }
}
