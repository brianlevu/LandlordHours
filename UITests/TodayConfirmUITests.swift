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

    private static var todayAt3pm: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'15:00"
        return f.string(from: Date())
    }

    private func launch(limit: Int? = 3, extra: [String] = []) {
        app.terminate()
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "emptyMainTabs",
            "-LHTodayHours", "212",
            "-LHSeedSuggestions", "inbox",
            "-LHNoSwipePeek",
            // The inbox seed is relative to "now" (the plumber is today 8-10): pin the clock to 15:00
            // on the real day so the list is the same at any hour. Run at 00:30 the plumber was still
            // in the future and the list had 7 items, not 8. (A fixed past date breaks logging.)
            "-LHFixedNow", Self.todayAt3pm,
            "-LHInitialTab", "0",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ] + (limit.map { ["-LHTodayConfirmLimit", "\($0)"] } ?? []) + extra
        app.launch()
    }

    private var hero: XCUIElement { app.descendants(matching: .any)["today.hero"] }
    private var number: XCUIElement { app.descendants(matching: .any)["today.number"].firstMatch }
    private var count: XCUIElement { app.descendants(matching: .any)["today.confirm.count"] }
    private var tabBar: XCUIElement { app.tabBars.firstMatch }
    private var inboxTab: XCUIElement { tabBar.buttons["Inbox"] }
    private var undo: XCUIElement { app.buttons["inbox.undo"].firstMatch }
    private func row(_ key: String) -> XCUIElement { app.descendants(matching: .any)["today.row.cal:debug-\(key)"] }
    /// The row's leading circle: a button inside the row (its label is "Confirm 2 hours" or "Review and confirm").
    private func control(_ key: String) -> XCUIElement { row(key).buttons.firstMatch }

    /// The Inbox tab's badge is the system's ("8 items"): the number is what must match Today's.
    private func badgeCount() -> Int {
        // The native tab bar tucks away while Today scrolls down (§1.25), taking its buttons out of the
        // tree; bring it back before reading the badge.
        var tries = 0
        while !inboxTab.exists && tries < 3 { app.swipeDown(velocity: .fast); tries += 1 }
        let text = (inboxTab.value as? String) ?? ""
        return Int(text.prefix(while: \.isNumber)) ?? 0
    }

    /// "To confirm · 8" → 8; the title alone ("To confirm") → 0.
    private func countedOnToday() -> Int {
        Int(count.label.split(separator: "·").last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? "") ?? 0
    }

    /// The hero number ("213"): the seed adds a hand-logged hour to the 212.
    private func heroHours() -> Int { Int(number.label) ?? -1 }

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
            let barTop = tabBar.frame.minY
            if element.isHittable, element.frame.maxY < barTop - 8, element.frame.minY > 120 { break }
            app.swipeUp(velocity: .slow)
            tries += 1
        }
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func waitFor(_ element: XCUIElement, label predicate: String, timeout: TimeInterval = 8) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func testCountCapsuleMatchesTheInboxBadge() {
        launch(limit: nil)
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        bringIntoView(count)
        XCTAssertEqual(count.label, "To confirm · 8")
        XCTAssertEqual(badgeCount(), 8, "One number: Today's count is the Inbox badge (\(inboxTab.value ?? "nil"))")
        XCTAssertTrue(app.buttons["today.confirm.seeAll"].exists, "More than the rows hold: See all 8")
        XCTAssertEqual(app.buttons["today.confirm.seeAll"].label, "See all 8")
    }

    func testConfirmFromTodayLogsBuildsTheHouseAndDropsTheBadge() {
        launch()
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        let before = heroHours()
        XCTAssertGreaterThanOrEqual(before, 212, number.label)
        bringIntoView(row("plumber"))
        XCTAssertEqual(count.label, "To confirm · 3")
        XCTAssertEqual(badgeCount(), 3)

        let confirm = control("plumber")
        XCTAssertTrue(confirm.exists)
        confirm.tap()

        XCTAssertTrue(undo.waitForExistence(timeout: 4), "The shared Undo toast")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Logged'")).firstMatch.exists)
        XCTAssertTrue(waitFor(count, label: "label == 'To confirm · 2'"))
        XCTAssertEqual(badgeCount(), 2)
        XCTAssertFalse(row("plumber").exists)
        // The hero counts the confirmed hours (after its build plays).
        XCTAssertTrue(waitForHeroHours { $0 > before }, number.label)

        // The Inbox shows the same list: the plumber is gone there too.
        inboxTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["inbox.screen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["inbox.row.cal:debug-plumber"].waitForExistence(timeout: 2))
        XCTAssertEqual(badgeCount(), 2)
    }

    /// Today's rows have no swipe (the Inbox keeps its own): "Not rental work" is on the row's
    /// context menu (and VoiceOver's actions).
    /// The toast under a "Not rental work": the inbox's own ("Marked not rental work") takes the slot first
    /// and Today's shared one ("Marked not rental work.") queues behind it, so either wording counts.
    private var markedNotWorkToast: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Marked not rental work'")).firstMatch
    }

    private func markNotRentalWork(_ key: String) {
        row(key).press(forDuration: 1.0)
        let notWork = app.buttons["Not rental work"].firstMatch
        XCTAssertTrue(notWork.waitForExistence(timeout: 5), "The row's menu offers Not rental work")
        notWork.tap()
    }

    func testNotRentalWorkFromTodayLeavesTheHouseAndUndoRestores() {
        launch()
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        let before = heroHours()
        bringIntoView(row("inspection"))
        markNotRentalWork("inspection")
        XCTAssertTrue(markedNotWorkToast.waitForExistence(timeout: 4))
        XCTAssertTrue(waitFor(count, label: "label == 'To confirm · 2'"))
        XCTAssertFalse(row("inspection").exists)
        XCTAssertEqual(heroHours(), before, "Not rental work never counts: \(number.label)")
        // The badge needs the tab bar, which may have tucked away; Undo must still land inside the
        // toast's 5 s, so read the badge last and undo straight after.
        XCTAssertEqual(badgeCount(), 2)
        undo.tap()
        XCTAssertTrue(waitFor(count, label: "label == 'To confirm · 3'"))
        XCTAssertEqual(badgeCount(), 3)
        XCTAssertTrue(row("inspection").waitForExistence(timeout: 3))
    }

    func testControlLogsAtOnceAndContextMenuMarksNotRentalWork() {
        launch()
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        bringIntoView(row("plumber"))
        control("plumber").tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 4), "The control logs at once (complete, scheduled item)")
        XCTAssertFalse(app.buttons["confirm.log"].waitForExistence(timeout: 1.5), "Logging from the control never opens the sheet")
        XCTAssertTrue(waitFor(count, label: "label == 'To confirm · 2'"))
        XCTAssertEqual(badgeCount(), 2)

        // Toasts queue one at a time and one with Undo stays 8 s (§1.19): let it go before the next action.
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: undo)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 12), .completed, "The Undo toast goes after its 8 s")
        let inspection = row("inspection")
        bringIntoView(inspection)
        markNotRentalWork("inspection")
        XCTAssertTrue(markedNotWorkToast.waitForExistence(timeout: 4), "Not rental work")
        XCTAssertTrue(waitFor(count, label: "label == 'To confirm · 1'"))
        XCTAssertEqual(badgeCount(), 1)
    }

    func testTapOpensTheConfirmSheetAndLoggingThereUpdatesToday() {
        launch()
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        bringIntoView(row("inspection"))
        row("inspection").tap()
        let log = app.buttons["confirm.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5), "The Inbox's confirm sheet opens from Today")
        XCTAssertTrue(app.buttons["confirm.dismiss"].exists)
        XCTAssertEqual(app.buttons["confirm.dismiss"].label, "Not rental work")
        log.tap()
        XCTAssertTrue(waitFor(count, label: "label == 'To confirm · 2'"))
        XCTAssertEqual(badgeCount(), 2)
    }

    func testCaughtUpAfterTheLastOne() {
        launch(limit: 1)
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        bringIntoView(row("plumber"))
        control("plumber").tap()
        let caughtUp = app.descendants(matching: .any)["today.caughtUp"]
        XCTAssertTrue(caughtUp.waitForExistence(timeout: 6))
        XCTAssertEqual(count.label, "To confirm", "The title stays, with no count")
        XCTAssertEqual(badgeCount(), 0)
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

    // MARK: Show the result where it happened (DESIGN-STANDARD §E.1)

    private var chip: XCUIElement { app.descendants(matching: .any)["today.chip"].firstMatch }
    private var revealProbe: XCUIElement { app.descendants(matching: .any)["today.revealProbe"].firstMatch }

    private func launchTwoRentals(extra: [String] = []) {
        app.terminate()
        app.launchArguments = extra + [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "emptyMainTabs",
            "-LHSeedSuggestions", "inbox",
            "-LHNoSwipePeek",
            "-LHRevealProbe",
            "-LHFixedNow", Self.todayAt3pm,
            "-LHInitialTab", "0",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
    }

    /// Confirms the "Showing" suggestion (Oak Street Duplex) in the Inbox, the way a person does.
    private func confirmShowingInInbox() {
        inboxTab.tap()
        let showing = app.descendants(matching: .any)["inbox.row.cal:debug-showing"]
        XCTAssertTrue(showing.waitForExistence(timeout: 10))
        showing.tap()
        let log = app.buttons["confirm.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 8))
        log.tap()
        XCTAssertTrue(log.waitForNonExistence(timeout: 8), "the confirm sheet closes")
    }

    func testTodayOpensOnTheRentalTheUserJustConfirmedThenRespectsAManualPick() {
        launchTwoRentals()
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        let before = chip.label
        XCTAssertNotEqual(before, "Rental: Oak Street Duplex", "Today starts somewhere else")

        confirmShowingInInbox()
        app.tabBars.firstMatch.buttons["Today"].tap()

        XCTAssertTrue(waitFor(chip, label: "label == 'Rental: Oak Street Duplex'", timeout: 10),
                      "Today opens on the rental that gained hours (was \(before), now \(chip.label))")
        XCTAssertTrue(revealProbe.label.contains("arrive:confirmed"), "the switch came from the user's own confirm: \(revealProbe.label)")
        XCTAssertEqual(revealProbe.label.components(separatedBy: "arrive:").count - 1, 1, "once")

        // A manual pick sticks: leave and come back with nothing new changed.
        chip.tap()
        let other = app.buttons.matching(NSPredicate(format: "label == 'Pine Cabin'")).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 5), "the chip menu lists the other rental")
        other.tap()
        XCTAssertTrue(waitFor(chip, label: "label == 'Rental: Pine Cabin'", timeout: 8))
        inboxTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["inbox.screen"].waitForExistence(timeout: 5))
        app.tabBars.firstMatch.buttons["Today"].tap()
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(chip.label, "Rental: Pine Cabin", "switch once, then respect the pick")
        XCTAssertEqual(revealProbe.label.components(separatedBy: "arrive:").count - 1, 1, "no second switch")
    }

    /// Frames for the gate: Today right after the switch, light and dark, default and XXL.
    /// Runs only with `TEST_RUNNER_LH_CAPTURE_DIR` set (the PNGs are written there too).
    func testCaptureArrivalFrames() throws {
        let dir = ProcessInfo.processInfo.environment["LH_CAPTURE_DIR"] ?? ""
        try XCTSkipIf(dir.isEmpty, "capture-only: set TEST_RUNNER_LH_CAPTURE_DIR")
        for scheme in ["light", "dark"] {
            for size in ["default", "xxl"] {
                let sizeArgs = size == "xxl" ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"] : []
                launchTwoRentals(extra: ["-LHColorScheme", scheme] + sizeArgs)
                XCTAssertTrue(hero.waitForExistence(timeout: 20))
                let beforeShot = app.screenshot()
                try? beforeShot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("today-before-\(scheme)-\(size).png"))
                confirmShowingInInbox()
                app.tabBars.firstMatch.buttons["Today"].tap()
                XCTAssertTrue(waitFor(chip, label: "label == 'Rental: Oak Street Duplex'", timeout: 10))
                Thread.sleep(forTimeInterval: 4.0)   // the catch-up has played
                let shot = app.screenshot()
                try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("today-arrive-\(scheme)-\(size).png"))
                let attachment = XCTAttachment(screenshot: shot)
                attachment.name = "today-arrive-\(scheme)-\(size)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
