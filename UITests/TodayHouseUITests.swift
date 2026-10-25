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

    /// The crafted house: one image whose label is the stage and the lights ("House, Frame going up, lights off").
    private var hero: XCUIElement { app.descendants(matching: .any)["today.hero"] }
    /// The numeral, "of N hours" and the pace sentence under the house (package C's number block).
    private var number: XCUIElement { app.descendants(matching: .any)["today.number"].firstMatch }
    private var block: XCUIElement { app.descendants(matching: .any)["today.numberBlock"].firstMatch }
    private var pace: XCUIElement { app.descendants(matching: .any)["today.pace"].firstMatch }

    private func waitForHeroLabel(containing text: String, timeout: TimeInterval = 15) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let match = app.descendants(matching: .any).matching(identifier: "today.hero").matching(predicate).firstMatch
        return match.waitForExistence(timeout: timeout)
    }

    private func waitForBlock(containing text: String, timeout: TimeInterval = 15) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return app.descendants(matching: .any).matching(identifier: "today.numberBlock").matching(predicate).firstMatch
            .waitForExistence(timeout: timeout)
    }

    private func waitForNumber(_ text: String, timeout: TimeInterval = 15) -> Bool {
        let predicate = NSPredicate(format: "label == %@", text)
        return app.descendants(matching: .any).matching(identifier: "today.number").matching(predicate).firstMatch
            .waitForExistence(timeout: timeout)
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

    func testTodayAtZeroHoursShowsTheStartedHouseAndNoPace() {
        launch(hours: "0")
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        XCTAssertTrue(hero.label.contains("Framing started"), hero.label)
        XCTAssertEqual(number.label, "0")
        XCTAssertTrue(block.label.contains("of 750 hours"), block.label)
        XCTAssertEqual(pace.label, "No hours yet. Log your first one while it’s fresh.", "No hours yet: no pace, and no \"a week\"")
        XCTAssertFalse(block.label.contains("a week"), block.label)
        attach("today-0h")
    }

    func testTodayAt212HoursShowsFrameAndPace() {
        launch(hours: "212", extra: Self.pinned)
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        XCTAssertTrue(hero.label.contains("Frame going up"), hero.label)
        XCTAssertEqual(number.label, "212")
        XCTAssertTrue(block.label.contains("of 750 hours"), block.label)
        XCTAssertEqual(pace.label, "Behind by 390h. 53h a week gets you to 750.", "Pinned to Oct 20: the weekly hours to finish by Dec 31")
        XCTAssertFalse(app.buttons["milestone-continue"].waitForExistence(timeout: 3), "No milestone at 212h")
        attach("today-212h")
    }

    func testCrossing500CelebratesOnceAndNeverAgain() {
        launch(hours: "498", extra: ["-LHTodayConfirmHours", "2"])
        let cont = app.buttons["milestone-continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 20), "Crossing 500h presents the roof celebration")
        attach("today-500h-celebration")
        cont.tap()
        XCTAssertTrue(waitForNumber("500"), number.label)
        XCTAssertTrue(hero.label.contains("Roof on"), hero.label)

        // Relaunch on the same profile without reseeding: the roof never celebrates again.
        app.terminate()
        app.launchArguments = ["-LHInitialTab", "0", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["milestone-continue"].waitForExistence(timeout: 5))
    }

    func testTodayAt751HoursShowsFinishedHouseAndTheOpenHalfRule() {
        launch(hours: "751")
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        XCTAssertEqual(number.label, "751")
        XCTAssertTrue(block.label.contains("of 750 hours"), block.label)
        XCTAssertTrue(hero.label.contains("House finished"), hero.label)
        // Hours alone never claim REPS: the half test is still open, and the pace line says so.
        XCTAssertEqual(pace.label, "750 reached. Add your other work hours to check the half rule.")
        XCTAssertFalse(block.label.contains("Done for"), "The half test is still open, so Today does not claim it. \(block.label)")
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
        XCTAssertEqual(number.label, "212")

        app.tabBars.firstMatch.buttons["Log time"].tap()
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
        XCTAssertTrue(waitForNumber("214"), number.label)
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
        XCTAssertTrue(waitForNumber("420"), number.label)
        XCTAssertTrue(block.label.contains("of 500 hours"), block.label)
        XCTAssertEqual(pace.label, "On pace. 8h a week gets you to 500.")
    }

    func testHeroBehindSaysTheHoursAWeek() {
        launch(hours: "210", extra: ["-LHGoalChoice", "mp500"] + Self.pinned)
        XCTAssertTrue(waitForNumber("210"), number.label)
        XCTAssertTrue(block.label.contains("of 500 hours"), block.label)
        XCTAssertEqual(pace.label, "Behind by 191h. 29h a week gets you to 500.")
    }

    /// The 750 follows the real estate pro's own hours; the spouse's hours never join yours.
    /// (Today no longer prints the words "your own count" / "spouse’s own count"; the number is the proof.)
    func test750NeverAddsTheSpousesHoursToYours() {
        launch(hours: "212", extra: ["-LHGoalChoice", "reps750", "-LHGoalPro", "me", "-LHTodaySpouseHours", "300"] + Self.pinned)
        XCTAssertTrue(waitForNumber("212"), "Spouse hours never join your 750. \(number.label)")
        XCTAssertTrue(block.label.contains("of 750 hours"), block.label)
    }

    /// BUG (found repairing these tests): when the spouse is the real estate professional, Today's
    /// number must follow the spouse's own 300 hours. It shows the owner's 212, because the
    /// per-rental figure Today now reads (`propertyCountableHours`, PropertyFigures.swift) hardcodes
    /// `participant: .selfParticipant` for REPS, where `houseCountableHours` honours `repsParticipant`.
    /// Strict: when the figure is fixed this starts passing, and the expectation must go.
    func test750FollowsTheSpouseWhenTheSpouseIsThePro() {
        launch(hours: "212", extra: ["-LHGoalChoice", "reps750", "-LHGoalPro", "spouse", "-LHTodaySpouseHours", "300"] + Self.pinned)
        XCTAssertTrue(number.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForNumber("300", timeout: 3), "The spouse is the pro: their own hours, not ours. \(number.label)")
    }

    func testShortStayHeroShowsTheCabinsOwnCount() {
        launch(hours: "212", extra: ["-LHGoalChoice", "mp100", "-LHTodayStrHours", "86", "-LHTodayNoOneMore", "unanswered"] + Self.pinned)
        XCTAssertTrue(waitForNumber("86"),
                      "Both kinds of rental: the short-term rental's own count, not the duplex's 212. \(number.label)")
        XCTAssertTrue(block.label.contains("of 100 hours"), block.label)
    }

    func testOver100HoursAsksWhetherAnyoneDidMoreBeforeSayingReached() {
        launch(hours: "104", extra: ["-LHGoalChoice", "mp100", "-LHTodayNoOneMore", "unanswered"] + Self.pinned)
        XCTAssertTrue(waitForNumber("104"), number.label)
        XCTAssertTrue(block.label.contains("of 100 hours"), block.label)
        XCTAssertTrue(pace.label.contains("Did anyone do more?"), pace.label)
        XCTAssertFalse(block.label.contains("Done for"), "Never done until it is confirmed. \(block.label)")
        pace.tap()
        let yes = app.buttons["participation.answer.yes"]
        XCTAssertTrue(yes.waitForExistence(timeout: 8), "The pace line opens the existing question")
        yes.tap()
        XCTAssertTrue(waitForBlock(containing: "Done for"), "Answered: the 100 is done. \(block.label)")
    }
}
