import XCTest

/// WP-L: Today renders and works at once while the first iCloud pull is pending. Only the hours
/// wait (placeholder bar + the drafting line sketching the house), then settle in. Driven by the
/// DEBUG `-LHSimulatePendingPull <seconds>` hook on a one-property REPS profile at 212 hours.
final class TodayLoadingUITests: XCTestCase {
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

    private func launch(pendingSeconds: String, scheme: String = "light") {
        app.terminate()
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "emptyMainTabs",
            "-LHTodayHours", "212",
            "-LHSimulatePendingPull", pendingSeconds,
            "-LHInitialTab", "0",
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
    }

    private var hero: XCUIElement { app.descendants(matching: .any)["today.hero"] }

    private func heroLabel(containing text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return app.descendants(matching: .any).matching(identifier: "today.hero").matching(predicate)
            .firstMatch.waitForExistence(timeout: timeout)
    }

    private func attach(_ name: String) {
        let screenshot = app.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        if let dir = ProcessInfo.processInfo.environment["LH_CAPTURE_DIR"], !dir.isEmpty {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    /// The pull is still pending (60 s), yet "+" and the tabs work right away.
    func testTodayIsInteractiveWhileInitialPullIsPending() {
        launch(pendingSeconds: "60")
        XCTAssertTrue(hero.waitForExistence(timeout: 15), "Today renders at once: no splash, no loading screen")
        XCTAssertTrue(heroLabel(containing: "Loading your hours", timeout: 3), hero.label)
        XCTAssertFalse(hero.label.contains("212 of 750"), "The number waits for the pull")
        XCTAssertTrue(app.staticTexts["today.header.title"].exists, "The rest of Today is there")
        attach("today-loading-light")

        // "+" works while the hours are still loading.
        let plus = app.buttons["tab.logTime"]
        XCTAssertTrue(plus.isHittable)
        plus.tap()
        XCTAssertTrue(app.buttons["log.close"].waitForExistence(timeout: 5),
                      "Log time opens while the pull is pending")
        app.buttons["log.close"].tap()

        // Back on Today it is still loading the Blueprint way, not blocked.
        app.buttons["tab.today"].tap()
        XCTAssertTrue(heroLabel(containing: "Loading your hours", timeout: 5), hero.label)
        XCTAssertTrue(app.buttons["Open reports"].isHittable, "Header actions stay tappable")
    }

    /// When the pull lands the real house and number settle in.
    func testHoursSettleInWhenThePullLands() {
        launch(pendingSeconds: "2.5")
        XCTAssertTrue(hero.waitForExistence(timeout: 15))
        XCTAssertTrue(heroLabel(containing: "212 of 750 hours", timeout: 12), hero.label)
        XCTAssertFalse(hero.label.contains("Loading"), "No loader once settled")
    }

    func testLoadingStateDark() {
        launch(pendingSeconds: "60", scheme: "dark")
        XCTAssertTrue(heroLabel(containing: "Loading your hours", timeout: 15), hero.label)
        Thread.sleep(forTimeInterval: 1.0)
        attach("today-loading-dark")
    }
}
