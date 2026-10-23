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
}
