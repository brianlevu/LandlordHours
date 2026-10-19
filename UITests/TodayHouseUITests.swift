import XCTest

/// Today's Blueprint house hero, seeded through the DEBUG `-LHTodayHours` hook (TodayHouse.swift)
/// on a one-property REPS profile with no other work hours entered.
final class TodayHouseUITests: XCTestCase {
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

    private func launch(hours: String, extra: [String] = []) {
        app.terminate()
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "emptyMainTabs",
            "-LHTodayHours", hours,
            "-LHInitialTab", "0",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ] + extra
        app.launch()
    }

    private var hero: XCUIElement { app.descendants(matching: .any)["today.hero"] }

    private func waitForHeroLabel(containing text: String, timeout: TimeInterval = 15) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let match = app.descendants(matching: .any).matching(identifier: "today.hero").matching(predicate).firstMatch
        return match.waitForExistence(timeout: timeout)
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTodayAtZeroHoursShowsEmptyLotAndUncheckedRule() {
        launch(hours: "0")
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        XCTAssertTrue(hero.label.contains("House built to 0 of 750 hours"), hero.label)
        XCTAssertTrue(hero.label.contains("An empty lot"), hero.label)
        XCTAssertTrue(hero.label.contains("No hours logged yet"), hero.label)
        let rule = app.descendants(matching: .any)["dashboard.fiftyPercent"]
        XCTAssertTrue(rule.waitForExistence(timeout: 5))
        XCTAssertTrue(rule.label.contains("Not checked"), rule.label)
        attach("today-0h")
    }

    func testTodayAt212HoursShowsFrameAndNextMilestone() {
        launch(hours: "212")
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        XCTAssertTrue(hero.label.contains("212 of 750 hours"), hero.label)
        XCTAssertTrue(hero.label.contains("Frame going up"), hero.label)
        XCTAssertTrue(hero.label.contains("roof at 500 hours"), hero.label)
        XCTAssertTrue(hero.label.contains("Behind by") || hero.label.contains("On pace"), hero.label)
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.fiftyPercent"].label.contains("Not checked"))
        XCTAssertFalse(app.buttons["milestone-continue"].waitForExistence(timeout: 3), "No milestone at 212h")
        attach("today-212h")
    }

    func testCrossing500CelebratesOnceAndNeverAgain() {
        launch(hours: "498", extra: ["-LHTodayConfirmHours", "2"])
        let cont = app.buttons["milestone-continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 20), "Crossing 500h presents the roof celebration")
        attach("today-500h-celebration")
        cont.tap()
        XCTAssertTrue(waitForHeroLabel(containing: "500 of 750 hours"))
        XCTAssertTrue(hero.label.contains("Roof on"), hero.label)

        // Relaunch on the same profile without reseeding: the roof never celebrates again.
        app.terminate()
        app.launchArguments = ["-LHInitialTab", "0", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["milestone-continue"].waitForExistence(timeout: 5))
    }

    func testTodayAt751HoursShowsFinishedHouseAndGoalHours() {
        launch(hours: "751")
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        XCTAssertTrue(hero.label.contains("751 of 750 hours"), hero.label)
        XCTAssertTrue(hero.label.contains("House finished"), hero.label)
        XCTAssertTrue(hero.label.contains("Goal hours reached"), hero.label)
        // Hours alone never claim REPS: the 50% rule is still "Not checked".
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.fiftyPercent"].label.contains("Not checked"))
        attach("today-751h")
    }

    func testScrolledToBottomTheLastCardClearsTheTabBar() {
        for scheme in ["light", "dark"] {
            launch(hours: "212", extra: ["-LHColorScheme", scheme])
            XCTAssertTrue(hero.waitForExistence(timeout: 20))
            for _ in 0..<6 { app.swipeUp() }
            let lastCard = app.buttons["dashboard.unlockPro"]
            XCTAssertTrue(lastCard.waitForExistence(timeout: 5))
            let bar = app.buttons["tab.logTime"]
            XCTAssertTrue(bar.exists)
            XCTAssertLessThanOrEqual(lastCard.frame.maxY, bar.frame.minY - 8,
                                     "The last card rests fully above the floating tab bar (\(scheme))")
            attach("today-scrolled-bottom-\(scheme)")
        }
    }

    func testLoggingTwoHoursViaPlusBuildsTheHouseOnReturn() {
        launch(hours: "212")
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        XCTAssertTrue(hero.label.contains("212 of 750 hours"), hero.label)

        app.buttons["tab.logTime"].tap()
        let notes = app.textViews["track.entryNotes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 8))
        notes.tap()
        notes.typeText("Fixed the porch steps for 2 hours")
        let logTime = app.buttons["track.logTime"]
        if !logTime.waitForExistence(timeout: 6) {
            let review = app.buttons["track.reviewEvidence"]
            XCTAssertTrue(review.waitForExistence(timeout: 3))
            review.tap()
        }
        XCTAssertTrue(logTime.waitForExistence(timeout: 5))
        logTime.tap()
        XCTAssertTrue(app.staticTexts["Time logged"].waitForExistence(timeout: 6))

        app.buttons["tab.today"].tap()
        // No loading skeleton: the real hero is there at once, building from 212.
        XCTAssertTrue(hero.waitForExistence(timeout: 1.5), "Today renders its hero without a skeleton")
        XCTAssertTrue(waitForHeroLabel(containing: "214 of 750 hours"), hero.label)
        // Let the confirm build (beam, count-up, crossfade) play out before the frame, so the
        // attachment (and any screen recording of this test) shows the settled 214.
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: 5)
        XCTAssertFalse(app.buttons["milestone-continue"].exists, "214h crosses no milestone")
        attach("today-after-log")
    }
}
