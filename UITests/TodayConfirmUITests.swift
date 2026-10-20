import XCTest

/// Today's To confirm block (redesign-specs §2): confirm, Not rental work, tap and swipe all go
/// through the Inbox's own model, so the house, the Inbox list and the tab badge move together.
final class TodayConfirmUITests: XCTestCase {
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

    private func launch(limit: Int? = 3, extra: [String] = []) {
        app.terminate()
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "emptyMainTabs",
            "-LHTodayHours", "212",
            "-LHSeedSuggestions", "inbox",
            "-LHNoSwipePeek",
            "-LHInitialTab", "0",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ] + (limit.map { ["-LHTodayConfirmLimit", "\($0)"] } ?? []) + extra
        app.launch()
    }

    private var hero: XCUIElement { app.descendants(matching: .any)["today.hero"] }
    private var count: XCUIElement { app.descendants(matching: .any)["today.confirm.count"] }
    private var inboxTab: XCUIElement { app.buttons["tab.inbox"] }
    private var undo: XCUIElement { app.buttons["inbox.undo"] }
    private func row(_ key: String) -> XCUIElement { app.descendants(matching: .any)["today.row.cal:debug-\(key)"] }

    private func badgeValue() -> String { (inboxTab.value as? String) ?? "" }

    /// "… House built to 213 of 750 hours …" → 213 (the seed adds a hand-logged hour to the 212).
    private func heroHours() -> Int {
        let label = hero.label
        guard let range = label.range(of: #"built to \d+ of"#, options: .regularExpression) else { return -1 }
        return Int(String(label[range].filter(\.isNumber))) ?? -1
    }

    private func waitForHeroHours(_ test: @escaping (Int) -> Bool, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if test(heroHours()) { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    /// Scrolls Today until the element sits clear of the floating tab bar.
    private func bringIntoView(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 20))
        var tries = 0
        while tries < 8 {
            let barTop = inboxTab.frame.minY
            if element.isHittable, element.frame.maxY < barTop - 8, element.frame.minY > 120 { break }
            app.swipeUp(velocity: .slow)
            tries += 1
        }
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func drag(_ element: XCUIElement, right: Bool) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: right ? 0.15 : 0.85, dy: 0.5))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: right ? 0.95 : 0.05, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }

    private func waitFor(_ element: XCUIElement, label predicate: String, timeout: TimeInterval = 8) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func testCountCapsuleMatchesTheInboxBadge() {
        launch(limit: nil)
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        bringIntoView(count)
        XCTAssertEqual(count.label, "8 to confirm")
        XCTAssertEqual(badgeValue(), "8 to confirm", "One number: Today's capsule is the Inbox badge")
        XCTAssertTrue(app.buttons["today.confirm.reviewAll"].exists, "More than three: Review all 8")
        XCTAssertEqual(app.buttons["today.confirm.reviewAll"].label, "Review all 8")
    }

    func testConfirmFromTodayLogsBuildsTheHouseAndDropsTheBadge() {
        launch()
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        let before = heroHours()
        XCTAssertGreaterThanOrEqual(before, 212, hero.label)
        bringIntoView(row("plumber"))
        XCTAssertEqual(count.label, "3 to confirm")
        XCTAssertEqual(badgeValue(), "3 to confirm")

        let confirm = app.buttons["inbox.confirm.cal:debug-plumber"]
        XCTAssertTrue(confirm.exists)
        confirm.tap()

        XCTAssertTrue(undo.waitForExistence(timeout: 4), "The shared Undo toast")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Logged'")).firstMatch.exists)
        XCTAssertTrue(waitFor(count, label: "label == '2 to confirm'"))
        XCTAssertEqual(badgeValue(), "2 to confirm")
        XCTAssertFalse(row("plumber").exists)
        // The hero counts the confirmed hours (after its build plays).
        XCTAssertTrue(waitForHeroHours { $0 > before }, hero.label)

        // The Inbox shows the same list: the plumber is gone there too.
        inboxTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["inbox.screen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["inbox.row.cal:debug-plumber"].waitForExistence(timeout: 2))
        XCTAssertEqual(badgeValue(), "2 to confirm")
    }

    func testNotRentalWorkFromTodayLeavesTheHouseAndUndoRestores() {
        launch()
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        let before = heroHours()
        bringIntoView(row("showing"))
        app.buttons["inbox.notWork.cal:debug-showing"].tap()
        XCTAssertTrue(app.staticTexts["Marked not rental work"].waitForExistence(timeout: 4))
        XCTAssertTrue(waitFor(count, label: "label == '2 to confirm'"))
        XCTAssertEqual(badgeValue(), "2 to confirm")
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(heroHours(), before, "Not rental work never counts: \(hero.label)")
        undo.tap()
        XCTAssertTrue(waitFor(count, label: "label == '3 to confirm'"))
        XCTAssertEqual(badgeValue(), "3 to confirm")
        XCTAssertTrue(row("showing").waitForExistence(timeout: 3))
    }

    func testSwipeRightLogsAndSwipeLeftMarksNotRentalWork() {
        launch()
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        bringIntoView(row("plumber"))
        drag(row("plumber"), right: true)
        XCTAssertTrue(undo.waitForExistence(timeout: 4), "Swipe right logs at once (complete, scheduled item)")
        XCTAssertFalse(app.buttons["confirm.log"].waitForExistence(timeout: 1.5), "A swipe never also opens the sheet")
        XCTAssertTrue(waitFor(count, label: "label == '2 to confirm'"))
        XCTAssertEqual(badgeValue(), "2 to confirm")

        // Let the Undo toast go, so the next row isn't under it.
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: undo)
        _ = XCTWaiter.wait(for: [gone], timeout: 8)
        let showing = row("showing")
        bringIntoView(showing)
        drag(showing, right: false)
        XCTAssertTrue(app.staticTexts["Marked not rental work"].waitForExistence(timeout: 4), "Swipe left: not rental work")
        XCTAssertTrue(waitFor(count, label: "label == '1 to confirm'"))
        XCTAssertEqual(badgeValue(), "1 to confirm")
    }

    func testTapOpensTheConfirmSheetAndLoggingThereUpdatesToday() {
        launch()
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        bringIntoView(row("showing"))
        row("showing").tap()
        let log = app.buttons["confirm.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5), "The Inbox's confirm sheet opens from Today")
        XCTAssertTrue(app.buttons["confirm.dismiss"].exists)
        XCTAssertEqual(app.buttons["confirm.dismiss"].label, "Not rental work")
        log.tap()
        XCTAssertTrue(waitFor(count, label: "label == '2 to confirm'"))
        XCTAssertEqual(badgeValue(), "2 to confirm")
    }

    func testCaughtUpAfterTheLastOne() {
        launch(limit: 1)
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        bringIntoView(row("plumber"))
        app.buttons["inbox.confirm.cal:debug-plumber"].tap()
        let caughtUp = app.descendants(matching: .any)["today.caughtUp"]
        XCTAssertTrue(caughtUp.waitForExistence(timeout: 6))
        XCTAssertFalse(count.exists)
        XCTAssertEqual(badgeValue(), "")
    }

    func testCaughtUpWithSuggestionsOffOffersTurnOn() {
        app.terminate()
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "emptyMainTabs",
            "-LHTodayHours", "212",
            "-LHInitialTab", "0",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        let turnOn = app.buttons["today.confirm.turnOn"]
        bringIntoView(turnOn)
        XCTAssertTrue(app.descendants(matching: .any)["today.caughtUp.off"].exists)
        turnOn.tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.toggle.calendar"].waitForExistence(timeout: 5),
                      "Turn on opens the suggestions setup")
    }

    func testWeekStripReadsEachDay() {
        launch(extra: ["-LHFixedNow", "2026-10-22T15:00", "-LHTodayWeekSample", "1.5,0,3,2"])
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        let total = app.descendants(matching: .any)["today.week.total"]
        bringIntoView(total)
        XCTAssertEqual(total.label, "6 hours 30 minutes this week")
        XCTAssertEqual(app.buttons["today.week.day.0"].label, "Monday, 1 hour 30 minutes")
        XCTAssertEqual(app.buttons["today.week.day.1"].label, "Tuesday, no hours")
        XCTAssertEqual(app.buttons["today.week.day.3"].label, "Thursday, today, 2 hours")
        XCTAssertEqual(app.buttons["today.week.day.4"].label, "Friday, not yet")
    }
}
