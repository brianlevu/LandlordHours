import XCTest

/// 2.0 onboarding journeys with real taps. System permission prompts are replaced by the DEBUG
/// fakes (`-LHFakeCalendar`, `-LHFakeNotifications`); the 90-day look-back runs the fixture scan
/// through the real inbox store (22 items, 35h).
final class OnboardingUITests: XCTestCase {

    // The staked title is the scaffold header's Text (no per-screen identifier): find it by its words.
    private var stakedSetup: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "You’re set up")).firstMatch
    }
    private var stakedFound: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", " found. ")).firstMatch
    }
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

    private var tabBar: XCUIElement { app.tabBars.firstMatch }
    private var todayTab: XCUIElement { tabBar.buttons["Today"] }
    private var inboxTab: XCUIElement { tabBar.buttons["Inbox"] }

    /// The Inbox tab's badge is the system's ("22 items"): the number is what matters.
    private func waitForInboxBadge(_ count: Int, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let text = (inboxTab.value as? String) ?? ""
            if Int(text.prefix(while: \.isNumber)) == count { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (element.value as? String) == value { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return (element.value as? String) == value
    }

    // Welcome's sign-in and Restore tests moved to IdentityJourneyUITests (package K: no sign-in in 2.2).

    // MARK: One tap on Welcome

    /// Regression (fix/onb-start): making the profile flipped isSignedIn before showOnboarding,
    /// so the shell mounted for a frame and onboarding restarted on Welcome. The first tap
    /// looked ignored in about 3 of 4 launches. One tap, no retry, on three fresh launches.
    func testOneStartBuildingTapLeavesWelcome() {
        for attempt in 1...3 {
            launchFresh()
            let start = app.buttons["onb-start"]
            XCTAssertTrue(start.waitForExistence(timeout: 20), "launch \(attempt): Welcome")
            start.tap()                                            // exactly one tap
            XCTAssertTrue(app.buttons["rental-short"].waitForExistence(timeout: 8),
                          "launch \(attempt): one Get started tap reaches the goal step")
            XCTAssertFalse(start.exists, "launch \(attempt): Welcome never comes back")
        }
    }

    /// iCloud never answers (signed out, restricted, hung daemon): Start still proceeds at once
    /// and the flow reaches Staked on local data.
    func testStartProceedsWhenICloudNeverAnswers() {
        launchFresh(["-LHFakeICloudHang", "-LHFakeCalendar", "denied", "-LHFakeNotifications", "denied"])
        let start = app.buttons["onb-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()                                                // exactly one tap
        XCTAssertTrue(app.buttons["rental-short"].waitForExistence(timeout: 8), "Start never waits on iCloud")
        UITestIsolation.answerGoalQuestions(app)                   // short stays, real estate is my main job
        tap(app.buttons["onb-primary"])                            // Aim for 750 hours
        tap(app.buttons["onb-primary"])                            // Look at my calendar (fake deny)
        XCTAssertTrue(app.buttons["who-me"].waitForExistence(timeout: 8))
        tap(app.buttons["onb-primary"])                            // Who: Continue
        let field = app.textFields["property-name"]
        tap(field)
        field.typeText("Elm")
        tap(app.buttons["onb-primary"])                            // Save it
        let setUp = stakedSetup
        XCTAssertTrue(setUp.waitForExistence(timeout: 10))
        XCTAssertEqual(setUp.label, "You’re set up for 750 hours.")
    }

    // MARK: Happy path

    func testHappyPathFindsHoursAndReviewOpensTheInbox() {
        launchFresh(["-LHFakeCalendar", "granted", "-LHFakeNotifications", "granted"])
        tap(app.buttons["onb-start"], timeout: 20)                 // Welcome → a profile on this iPhone
        UITestIsolation.answerGoalQuestions(app, rental: "rental-short", pro: "pro-none")
        XCTAssertTrue(app.staticTexts["Based on your answers, start here"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["onb-primary"].label, "Aim for 100 hours", "Short stays and no real estate pro: 100 hours, already selected")
        XCTAssertTrue(app.buttons["goal-100"].isSelected)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Most common")).firstMatch.exists)
        tap(app.buttons["onb-primary"])
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
        XCTAssertTrue(app.staticTexts["Want a nudge to log it while it’s fresh?"].waitForExistence(timeout: 6))
        tap(yes)                                                   // fake notifications "Allow"
        let found = stakedFound
        XCTAssertTrue(found.waitForExistence(timeout: 10))
        XCTAssertEqual(found.label, "35 hours found. 0 counted.", "The fixture look-back: 22 items, 35h")
        let review = app.buttons["onb-today"]
        XCTAssertEqual(review.label, "Review 22 suggestions")
        tap(review)
        XCTAssertTrue(inboxTab.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForInboxBadge(22),
                      "Every hour found is in the Inbox: \(inboxTab.value ?? "nil")")
        // The count was shown once on Staked: Today does not replay it, and keeps the 22 under "To confirm".
        tap(todayTab)
        XCTAssertFalse(app.buttons["backfill-review"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["today.confirm.count"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["today.confirm.count"].label, "To confirm · 22", "Today keeps what was found")
        XCTAssertFalse(app.descendants(matching: .any)["guidedSetup.overlay"].exists, "No coach mark")
        tap(inboxTab)
        // Found before the property existed, placed on it when it was saved: Confirm logs in one tap.
        // Package D: each row is an LHRow.Action whose leading circle is the confirm control (§1.3);
        // the row's own height carries the 44pt target, and the control speaks "Confirm".
        // ("inbox.confirm.batch" is the card foot's "Confirm N likely", not a row.)
        let firstRow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "inbox.row.")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "The Inbox lists what was found")
        XCTAssertGreaterThanOrEqual(firstRow.frame.height, 44)
        let confirm = firstRow.buttons.firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Every Inbox row carries the confirm control")
        XCTAssertTrue(confirm.label.hasPrefix("Confirm"), "The control says Confirm, not only a checkmark: \(confirm.label)")
        XCTAssertFalse(app.staticTexts["Pick a property"].exists, "The only property was attached to every suggestion")
        tap(confirm)
        XCTAssertFalse(app.buttons["confirm.log"].waitForExistence(timeout: 2), "No sheet: nothing was missing")
        XCTAssertTrue(waitForInboxBadge(21), "Confirm logged the row")
    }

    // MARK: Skip path: seven taps to Today

    func testSkipPathIsSevenTapsToTheEmptyLot() {
        launchFresh()
        tap(app.buttons["onb-start"], timeout: 20)                 // 1
        UITestIsolation.answerGoalQuestions(app)                   // 2, 3 (750 is suggested)
        tap(app.buttons["onb-primary"])                            // 4 Aim for 750 hours
        tap(app.buttons["onb-link"])                               // 5 Not now
        tap(app.buttons["onb-primary"])                            // 6 Continue
        tap(app.buttons["onb-link"])                               // 7 I'll add it later
        XCTAssertTrue(todayTab.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["today.addRental"].waitForExistence(timeout: 5), "The empty lot carries Add a rental")
        // With no rental the hero's own action carries the screen: the To confirm block (and with it
        // the way back to the calendar) waits for the first rental.
        XCTAssertFalse(app.descendants(matching: .any)["today.confirm"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["guidedSetup.overlay"].exists, "No coach mark")
        XCTAssertTrue(app.staticTexts["today.pace"].label.hasPrefix("Add a rental."), "The empty lot says what to do")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "skip-today"; shot.lifetime = .keepAlways; add(shot)
        tap(app.buttons["today.addRental"].firstMatch)
        let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); after.name = "skip-after-tap"; after.lifetime = .keepAlways; add(after)
        XCTAssertTrue(app.textFields["property.name"].waitForExistence(timeout: 6), "The empty lot's Add property opens the form")
    }

    // MARK: Permission denied

    func testCalendarDeniedSkipsTheNoteAndStakesQuietly() {
        launchFresh(["-LHFakeCalendar", "denied"])
        tap(app.buttons["onb-start"], timeout: 20)
        UITestIsolation.answerGoalQuestions(app, rental: "rental-long", pro: "pro-none")
        XCTAssertEqual(app.buttons["onb-primary"].label, "Aim for 500 hours", "Long-term and no real estate pro: 500 hours")
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
        XCTAssertTrue(stakedSetup.waitForExistence(timeout: 8), "No visit-end note without the calendar")
        XCTAssertEqual(stakedSetup.label, "You’re set up to keep a record.")
        XCTAssertEqual(app.buttons["onb-today"].label, "Go to Today")
        tap(app.buttons["onb-today"])
        XCTAssertTrue(app.buttons["today.confirm.turnOn"].waitForExistence(timeout: 8), "Today keeps a way back to the calendar")
    }

    func testNotificationsDeclinedInAppNeverPrompts() {
        launchFresh(["-LHFakeCalendar", "granted", "-LHFakeNotifications", "granted"])
        tap(app.buttons["onb-start"], timeout: 20)
        UITestIsolation.answerGoalQuestions(app)
        tap(app.buttons["onb-primary"])                            // Aim for 750 hours
        tap(app.buttons["onb-primary"])                            // Look at my calendar
        tap(app.buttons["onb-primary"])                            // Who: Continue
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
        UITestIsolation.answerGoalQuestions(app)
        tap(app.buttons["onb-primary"])
        XCTAssertTrue(app.buttons["onb-link"].waitForExistence(timeout: 5))
        tap(app.buttons["onb-back"])
        XCTAssertTrue(app.staticTexts["Based on your answers, start here"].waitForExistence(timeout: 5))
        tap(app.buttons["onb-back"])                               // back through the questions
        XCTAssertTrue(app.staticTexts["Is real estate your main job, or your spouse’s?"].waitForExistence(timeout: 5))
        tap(app.buttons["onb-back"])
        XCTAssertTrue(app.staticTexts["What do you rent out?"].waitForExistence(timeout: 5))
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
        UITestIsolation.answerGoalQuestions(app)
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
        XCTAssertTrue(app.staticTexts["Want a nudge to log it while it’s fresh?"].waitForExistence(timeout: 8),
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
        XCTAssertTrue(stakedSetup.waitForExistence(timeout: 8), "No visit-end note without the calendar")
        XCTAssertEqual(app.buttons["onb-today"].label, "Go to Today")
        tap(app.buttons["onb-today"])
        XCTAssertTrue(app.buttons["today.confirm.turnOn"].waitForExistence(timeout: 8), "Today keeps a way back to the calendar")
    }

    // MARK: Only non-countable work found

    func testOnlyNonCountableWorkFoundSaysSoInsteadOfHours() {
        launchFresh(["-LHFakeCalendar", "granted", "-LHFakeNotifications", "granted", "-LHBackfillNonCountable"])
        tap(app.buttons["onb-start"], timeout: 20)
        UITestIsolation.answerGoalQuestions(app)
        tap(app.buttons["onb-primary"])                            // Aim for 750 hours
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
        XCTAssertTrue(stakedSetup.exists)
        XCTAssertFalse(stakedFound.exists, "Never a found-hours headline")
        XCTAssertEqual(app.buttons["onb-today"].label, "Review 22 suggestions", "They still wait in the Inbox")
        tap(app.buttons["onb-today"])
        tap(todayTab)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'found'")).firstMatch.waitForExistence(timeout: 3), "Today shows no found hours either")
        XCTAssertFalse(app.buttons["backfill-review"].exists, "No reveal for work that never counts")
    }
}
