import XCTest

/// Screen anatomy (standard §S): the tab header scrolls away with the content and a compact bar with
/// the title and the screen's one action takes its place; scrolling back brings the header back.
/// `testCapture*` writes frames when run with `TEST_RUNNER_LH_CAPTURE_DIR=<dir>` (captures only).
final class ScreenAnatomyUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(tab: Int, extra: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [UITestIsolation.resetProfilesArgument, "-LHMockScenario", "emptyMainTabs",
                               "-LHPropertiesSeed", "layouts3", "-LHPropertiesGoal", "mp100", "-LHGoalChoice", "mp100",
                               "-LHSeedSuggestions", "inbox", "-LHFakeZone", "empty", "-LHInitialTab", "\(tab)",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
    }

    /// The compact bar's title (a leaf, so a screen-level identifier never renames it).
    private var compactBar: XCUIElement { app.staticTexts["screen.compactTitle"] }

    /// One of the buttons with this identifier (the header's, or the compact bar's) can be tapped.
    private func hittable(_ id: String) -> Bool {
        app.buttons.matching(identifier: id).allElementsBoundByIndex.contains { $0.isHittable }
    }

    func testRecordsHeaderScrollsAwayAndComesBack() {
        launch(tab: 6)
        let export = app.buttons["records.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        XCTAssertFalse(compactBar.exists, "no compact bar at rest")
        app.swipeUp()
        XCTAssertTrue(compactBar.waitForExistence(timeout: 3), "the compact bar shows once the title has left")
        XCTAssertTrue(hittable("records.export"), "the one action stays reachable in the compact bar")
        app.swipeDown()
        app.swipeDown()
        XCTAssertFalse(compactBar.waitForExistence(timeout: 1.5), "the compact bar leaves at rest")
        XCTAssertTrue(app.staticTexts["Records"].firstMatch.isHittable)
    }

    func testSettingsBackStaysReachableWhenScrolled() {
        launch(tab: 4)
        let back = app.buttons["shell.backToToday"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        app.swipeUp()
        XCTAssertTrue(compactBar.waitForExistence(timeout: 3))
        XCTAssertTrue(hittable("shell.backToToday"), "back is in the compact bar")
    }

    func testCaptureScrolledHeaders() {
        for (tab, name) in [(6, "3-records-scrolled"), (5, "2-inbox-scrolled"), (4, "5-settings-scrolled"), (0, "1-today-scrolled")] {
            launch(tab: tab)
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
            sleep(2)
            app.swipeUp()
            sleep(1)
            save(name)
            app.terminate()
        }
    }

    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["LH_CAPTURE_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
