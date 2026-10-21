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
        let screenshot = app.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        // Captures: `TEST_RUNNER_LH_CAPTURE_DIR=<dir> xcodebuild test ...` also writes the PNG there.
        if let dir = ProcessInfo.processInfo.environment["LH_CAPTURE_DIR"], !dir.isEmpty {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    func testTodayAtZeroHoursShowsEmptyLotAndUncheckedRule() {
        launch(hours: "0")
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        XCTAssertTrue(hero.label.contains("House built to 0 of 750 hours"), hero.label)
        XCTAssertTrue(hero.label.contains("An empty lot"), hero.label)
        XCTAssertTrue(hero.label.contains("Log a few weeks to see your pace") || hero.label.contains("Confirm your found hours to see your pace"), "No hours yet: no pace, and no \"74h a week\". \(hero.label)")
        XCTAssertFalse(hero.label.contains("a week to finish"), hero.label)
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
        XCTAssertTrue(hero.label.contains("a week to finish by Dec 31") || hero.label.contains("on pace for Dec 31"), hero.label)
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
        XCTAssertTrue(hero.label.contains("750 reached. Add your other work hours to check the half rule."), hero.label)
        XCTAssertFalse(hero.label.contains("Goal hours reached"), "The half test is still open, so the hero does not claim it. \(hero.label)")
        // Hours alone never claim REPS: the 50% rule is still "Not checked".
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.fiftyPercent"].label.contains("Not checked"))
        attach("today-751h")
    }

    func testScrolledToBottomTheLastCardClearsTheTabBar() {
        for scheme in ["light", "dark"] {
            launch(hours: "212", extra: ["-LHColorScheme", scheme])
            XCTAssertTrue(hero.waitForExistence(timeout: 20))
            for _ in 0..<6 { app.swipeUp() }
            let lastCard = app.descendants(matching: .any)["today.yourRecord"].firstMatch
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
        let notes = app.descendants(matching: .any)["log.note"].firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 8))
        notes.tap()
        notes.typeText("Fixed the porch steps for 2 hours")
        let logTime = app.buttons["log.save"]
        XCTAssertTrue(logTime.waitForExistence(timeout: 5))
        if !logTime.isEnabled {
            // More than one rental: pick the first.
            app.buttons["log.property"].tap()
            let first = app.buttons["picker.property.0"]
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            first.tap()
        }
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: logTime)
        waitForExpectations(timeout: 5)
        logTime.tap()
        XCTAssertTrue(app.descendants(matching: .any)["shell.toast"].waitForExistence(timeout: 6))

        // No loading skeleton: the real hero is there at once, building from 212.
        XCTAssertTrue(hero.waitForExistence(timeout: 1.5), "Today renders its hero without a skeleton")
        XCTAssertTrue(waitForHeroLabel(containing: "214 of 750 hours"), hero.label)
        // Let the confirm build (beam, count-up, crossfade) play out before the frame, so the
        // attachment (and any screen recording of this test) shows the settled 214.
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: 5)
        XCTAssertFalse(app.buttons["milestone-continue"].exists, "214h crosses no milestone")
        attach("today-after-log")
    }

    // MARK: Goal-first hero words (2.0 messaging)

    private static let pinned = ["-LHFixedNow", "2026-10-20T15:00"]

    func testHeroSaysTheTargetAndThatYouAreOnPace() {
        launch(hours: "420", extra: ["-LHGoalChoice", "mp500"] + Self.pinned)
        XCTAssertTrue(waitForHeroLabel(containing: "of 500 hours · on pace for Dec 31"), hero.label)
    }

    func testHeroBehindSaysTheHoursAWeek() {
        launch(hours: "210", extra: ["-LHGoalChoice", "mp500"] + Self.pinned)
        XCTAssertTrue(waitForHeroLabel(containing: "of 500 hours · 29h a week to finish by Dec 31"), hero.label)
    }

    func test750SaysWhoseCountItIs() {
        launch(hours: "212", extra: ["-LHGoalChoice", "reps750", "-LHGoalPro", "spouse", "-LHTodaySpouseHours", "300"] + Self.pinned)
        XCTAssertTrue(waitForHeroLabel(containing: "spouse’s own count"), hero.label)
        XCTAssertTrue(hero.label.contains("House built to 300 of 750 hours"), "The spouse is the pro: their own hours, not ours. \(hero.label)")
        launch(hours: "212", extra: ["-LHGoalChoice", "reps750", "-LHGoalPro", "me", "-LHTodaySpouseHours", "300"] + Self.pinned)
        XCTAssertTrue(waitForHeroLabel(containing: "your own count"), hero.label)
        XCTAssertTrue(hero.label.contains("House built to 212 of 750 hours"), "Spouse hours never join your 750. \(hero.label)")
    }

    func testShortStayHeroShowsTheCabinsOwnCount() {
        launch(hours: "212", extra: ["-LHGoalChoice", "mp100", "-LHTodayStrHours", "86", "-LHTodayNoOneMore", "unanswered"] + Self.pinned)
        XCTAssertTrue(waitForHeroLabel(containing: "House built to 86 of 100 hours"),
                      "Both kinds of rental: the short-term rental's own count, not the duplex's 212. \(hero.label)")
        XCTAssertTrue(hero.label.contains("more than anyone else"), hero.label)
        XCTAssertTrue(hero.label.contains("2026 · Tahoe cabin · 100-hour target"), "The hero says which rental it counts. \(hero.label)")
    }

    func testOver100HoursAsksWhetherAnyoneDidMoreBeforeSayingReached() {
        launch(hours: "104", extra: ["-LHGoalChoice", "mp100", "-LHTodayNoOneMore", "unanswered"] + Self.pinned)
        XCTAssertTrue(waitForHeroLabel(containing: "of 100 hours · confirm no one did more"), hero.label)
        XCTAssertFalse(hero.label.contains("reached"), "Never reached until it is confirmed. \(hero.label)")
        hero.tap()
        let yes = app.buttons["participation.answer.yes"]
        XCTAssertTrue(yes.waitForExistence(timeout: 8), "The hero opens the existing question")
        yes.tap()
        XCTAssertTrue(waitForHeroLabel(containing: "reached · no one did more, based on your records"), hero.label)
    }
}
