import XCTest

/// 2.0 onboarding journeys with real taps. System permission prompts are replaced by the DEBUG
/// fakes (`-LHFakeCalendar`, `-LHFakeNotifications`); the 90-day look-back runs the fixture scan
/// through the real inbox store (22 items, 35h).
final class OnboardingUITests: XCTestCase {
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

    private func launchFresh(_ extra: [String] = []) {
        app.terminate()
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ] + extra
        app.launch()
    }

    private func tap(_ element: XCUIElement, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "missing \(element)", file: file, line: line)
        let deadline = Date().addingTimeInterval(timeout)
        while !element.isHittable && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        element.tap()
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (element.value as? String) == value { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return (element.value as? String) == value
    }

    // MARK: Happy path

    func testHappyPathFindsHoursAndReviewOpensTheInbox() {
        launchFresh(["-LHFakeCalendar", "granted", "-LHFakeNotifications", "granted"])
        tap(app.buttons["onb-start"], timeout: 20)                 // Welcome → a profile on this iPhone
        tap(app.buttons["goal-750"])
        tap(app.buttons["onb-primary"])                            // Build toward 750h
        let look = app.buttons["onb-primary"]
        XCTAssertTrue(look.waitForExistence(timeout: 5))
        XCTAssertEqual(look.label, "Look at my calendar")
        tap(look)                                                  // fake "Allow Full Access"
        tap(app.buttons["who-both"])
        XCTAssertTrue(app.descendants(matching: .any)["who-note"].waitForExistence(timeout: 3))
        tap(app.buttons["onb-primary"])                            // Continue
        let hint = app.descendants(matching: .any)["property-hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 10), "The look-back count shows while naming the rental")
        let field = app.textFields["property-name"]
        tap(field)
        field.typeText("Oak Street duplex")
        tap(app.buttons["onb-primary"])                            // Save it: one tap, moves on by itself
        let yes = app.buttons["onb-primary"]
        XCTAssertTrue(app.staticTexts["Want a note when a visit ends?"].waitForExistence(timeout: 6))
        tap(yes)                                                   // fake notifications "Allow"
        let found = app.staticTexts["staked-found"]
        XCTAssertTrue(found.waitForExistence(timeout: 10))
        XCTAssertEqual(found.label, "35h found", "The fixture look-back: 22 items, 35h")
        let review = app.buttons["onb-today"]
        XCTAssertEqual(review.label, "Review 22 suggestions")
        tap(review)
        XCTAssertTrue(app.buttons["tab.inbox"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForValue(app.buttons["tab.inbox"], "22 to confirm"),
                      "Every hour found is in the Inbox: \(app.buttons["tab.inbox"].value ?? "nil")")
        // The count was shown once on Staked: Today does not replay it, and keeps "35h found".
        tap(app.buttons["tab.today"])
        XCTAssertFalse(app.buttons["backfill-review"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["today.hero.found"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["guidedSetup.overlay"].exists, "No coach mark")
        tap(app.buttons["tab.inbox"])
        // Found before the property existed, placed on it when it was saved: Confirm logs in one tap.
        let confirm = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "inbox.confirm.")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Every Inbox row shows Confirm")
        XCTAssertGreaterThanOrEqual(confirm.frame.height, 44)
        XCTAssertEqual(confirm.label, "Confirm", "The word is on the button, not only a checkmark")
        XCTAssertFalse(app.staticTexts["Pick a property"].exists, "The only property was attached to every suggestion")
        tap(confirm)
        XCTAssertFalse(app.buttons["confirm.log"].waitForExistence(timeout: 2), "No sheet: nothing was missing")
        XCTAssertTrue(waitForValue(app.buttons["tab.inbox"], "21 to confirm"), "Confirm logged the row")
    }

    // MARK: Skip path: six taps to Today

    func testSkipPathIsSixTapsToTheEmptyLot() {
        launchFresh()
        tap(app.buttons["onb-start"], timeout: 20)                 // 1
        tap(app.buttons["goal-750"])                               // 2
        tap(app.buttons["onb-primary"])                            // 3 Build toward 750h
        tap(app.buttons["onb-link"])                               // 4 Not now
        tap(app.buttons["onb-primary"])                            // 5 Continue
        tap(app.buttons["onb-link"])                               // 6 I'll add it later
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["today.hero.addProperty"].waitForExistence(timeout: 5), "The empty lot carries Add property")
        XCTAssertTrue(app.buttons["today-find-hours"].exists, "Look at my calendar waits on Today")
        XCTAssertFalse(app.descendants(matching: .any)["guidedSetup.overlay"].exists, "No coach mark")
        XCTAssertEqual(app.staticTexts["today.header.title"].label, "Add your first property")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "skip-today"; shot.lifetime = .keepAlways; add(shot)
        tap(app.buttons["today.hero.addProperty"].firstMatch)
        let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); after.name = "skip-after-tap"; after.lifetime = .keepAlways; add(after)
        XCTAssertTrue(app.textFields["property.name"].waitForExistence(timeout: 6), "The empty lot's Add property opens the form")
    }

    // MARK: Permission denied

    func testCalendarDeniedSkipsTheNoteAndStakesQuietly() {
        launchFresh(["-LHFakeCalendar", "denied"])
        tap(app.buttons["onb-start"], timeout: 20)
        tap(app.buttons["goal-record"])
        XCTAssertEqual(app.buttons["onb-primary"].label, "Keep a record")
        tap(app.buttons["onb-primary"])
        tap(app.buttons["onb-primary"])                            // Look at my calendar → denied
        tap(app.buttons["onb-primary"])                            // Who: Continue
        let field = app.textFields["property-name"]
        tap(field)
        field.typeText("Pine")
        XCTAssertFalse(app.descendants(matching: .any)["property-hint"].exists, "No count without the calendar")
        tap(app.buttons["onb-primary"])                            // Save it
        XCTAssertTrue(app.staticTexts["Your house is staked."].waitForExistence(timeout: 8), "No visit-end note without the calendar")
        XCTAssertEqual(app.buttons["onb-today"].label, "Go to Today")
        tap(app.buttons["onb-today"])
        XCTAssertTrue(app.buttons["today-find-hours"].waitForExistence(timeout: 8))
    }

    func testNotificationsDeclinedInAppNeverPrompts() {
        launchFresh(["-LHFakeCalendar", "granted", "-LHFakeNotifications", "granted"])
        tap(app.buttons["onb-start"], timeout: 20)
        tap(app.buttons["goal-750"])
        tap(app.buttons["onb-primary"])
        tap(app.buttons["onb-primary"])
        tap(app.buttons["onb-primary"])
        let field = app.textFields["property-name"]
        tap(field)
        field.typeText("Oak")
        tap(app.buttons["onb-primary"])
        tap(app.buttons["onb-secondary"])                          // Not now
        XCTAssertTrue(app.buttons["onb-today"].waitForExistence(timeout: 8))
    }

    func testBackGoesToThePreviousStep() {
        launchFresh()
        tap(app.buttons["onb-start"], timeout: 20)
        tap(app.buttons["goal-750"])
        tap(app.buttons["onb-primary"])
        XCTAssertTrue(app.buttons["onb-link"].waitForExistence(timeout: 5))
        tap(app.buttons["onb-back"])
        XCTAssertTrue(app.staticTexts["What are you building toward?"].waitForExistence(timeout: 5))
    }

    // MARK: Upgraders

    func testWhatsNewHoldsTheRevealUntilItCloses() {
        launchFresh(["-LHMockScenario", "occasional", "-LHShowWhatsNew", "-LHInitialTab", "0",
                     "-LHFakeCalendar", "granted", "-LHFakeNotifications", "granted"])
        XCTAssertTrue(app.descendants(matching: .any)["onb.whatsNew"].waitForExistence(timeout: 20))
        tap(app.buttons["onb-primary"])                            // the house → Continue
        tap(app.buttons["onb-primary"])                            // Look at my calendar (fake allow)
        let notNow = app.buttons["onb-secondary"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 5), "The visit-end note follows a calendar grant")
        Thread.sleep(forTimeInterval: 3)                           // the fixture look-back finishes
        XCTAssertTrue(notNow.exists && notNow.isHittable, "Nothing covers What's new while it is open")
        XCTAssertFalse(app.buttons["backfill-review"].exists)
        tap(notNow)
        XCTAssertTrue(app.buttons["backfill-review"].waitForExistence(timeout: 10), "Today's reveal plays once What's new closes")
    }

    // MARK: The REAL iOS calendar prompt (no DEBUG fake), on a fresh permission state

    private func walkToCalendarWithRealPrompt() -> XCUIElement {
        app.terminate()
        app.resetAuthorizationStatus(for: .calendar)                // iOS will ask again
        launchFresh()
        tap(app.buttons["onb-start"], timeout: 20)
        tap(app.buttons["goal-750"])
        tap(app.buttons["onb-primary"])
        let look = app.buttons["onb-primary"]
        XCTAssertTrue(look.waitForExistence(timeout: 5))
        XCTAssertEqual(look.label, "Look at my calendar")
        tap(look)
        // iOS hosts its permission prompts in SpringBoard; check the app too, to be safe.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline && springboard.alerts.count == 0 && app.alerts.count == 0 {
            Thread.sleep(forTimeInterval: 0.3)
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "real-prompt"; shot.lifetime = .keepAlways; add(shot)
        let alert = springboard.alerts.count > 0 ? springboard.alerts.firstMatch : app.alerts.firstMatch
        XCTAssertTrue(alert.exists, "iOS shows its own calendar prompt. SpringBoard: \(springboard.debugDescription.prefix(1500))")
        return alert
    }

    private func tapAlertButton(_ alert: XCUIElement, _ labels: [String]) {
        for label in labels where alert.buttons[label].exists {
            alert.buttons[label].tap()
            return
        }
        XCTFail("No \(labels) button on the prompt: \(alert.buttons.allElementsBoundByIndex.map(\.label))")
    }

    private func nameRental(_ name: String) {
        tap(app.buttons["onb-primary"])                            // Who: Continue
        let field = app.textFields["property-name"]
        tap(field)
        field.typeText(name)
        tap(app.buttons["onb-primary"])                            // Save it
    }

    func testRealCalendarPromptAllowLeadsToTheVisitNote() {
        let alert = walkToCalendarWithRealPrompt()
        tapAlertButton(alert, ["Allow Full Access", "Allow"])
        XCTAssertTrue(app.buttons["who-me"].waitForExistence(timeout: 8), "Allowed: on to Who does the work")
        nameRental("Oak")
        XCTAssertTrue(app.staticTexts["Want a note when a visit ends?"].waitForExistence(timeout: 8),
                      "The visit-end note is asked only after a real calendar grant")
        tap(app.buttons["onb-secondary"])                          // Not now
        XCTAssertTrue(app.buttons["onb-today"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["0h found"].exists, "Never 0h found")
    }

    func testRealCalendarPromptDontAllowContinuesQuietly() {
        let alert = walkToCalendarWithRealPrompt()
        tapAlertButton(alert, ["Don’t Allow", "Don't Allow"])
        XCTAssertTrue(app.buttons["who-me"].waitForExistence(timeout: 8), "Denied: on to Who does the work, no scolding")
        nameRental("Pine")
        XCTAssertTrue(app.staticTexts["Your house is staked."].waitForExistence(timeout: 8), "No visit-end note without the calendar")
        XCTAssertEqual(app.buttons["onb-today"].label, "Go to Today")
        tap(app.buttons["onb-today"])
        XCTAssertTrue(app.buttons["today-find-hours"].waitForExistence(timeout: 8), "Today keeps a way back to the calendar")
    }

    // MARK: Only non-countable work found

    func testOnlyNonCountableWorkFoundSaysSoInsteadOfHours() {
        launchFresh(["-LHFakeCalendar", "granted", "-LHFakeNotifications", "granted", "-LHBackfillNonCountable"])
        tap(app.buttons["onb-start"], timeout: 20)
        tap(app.buttons["goal-750"])
        tap(app.buttons["onb-primary"])                            // Build toward 750h
        tap(app.buttons["onb-primary"])                            // Look at my calendar (fake allow)
        tap(app.buttons["onb-primary"])                            // Who: Continue
        let field = app.textFields["property-name"]
        tap(field)
        field.typeText("Oak")
        tap(app.buttons["onb-primary"])                            // Save it
        tap(app.buttons["onb-secondary"])                          // note: Not now
        let line = app.staticTexts["staked-nothing-countable"]
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        XCTAssertEqual(line.label.lowercased(), "we found 22 things, but none count toward your hours yet.")
        XCTAssertTrue(app.staticTexts["Your house is staked."].exists)
        XCTAssertFalse(app.staticTexts["staked-found"].exists, "Never a found-hours headline")
        XCTAssertEqual(app.buttons["onb-today"].label, "Review 22 suggestions", "They still wait in the Inbox")
        tap(app.buttons["onb-today"])
        tap(app.buttons["tab.today"])
        XCTAssertFalse(app.staticTexts["today.hero.found"].waitForExistence(timeout: 3), "Today shows no found hours either")
        XCTAssertFalse(app.buttons["backfill-review"].exists, "No reveal for work that never counts")
    }
}
