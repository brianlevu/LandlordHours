import XCTest

/// Frames of every onboarding step for the visual gate: light / dark at the default size, XXL
/// and AX3, plus Today after the skip and the found landing, and the upgraders' What's new.
/// Each frame is an XCTAttachment named `<frame>-<scheme>[-xxl|-ax3]`; export with
/// `xcrun xcresulttool export attachments`. Reduce Motion frames: the host turns the simulator's
/// Reduce Motion on and runs `testCaptureReduceMotionWelcome*`.
final class OnboardingCaptureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        UITestIsolation.resetStoreKit()
        continueAfterFailure = true
        app = XCUIApplication()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testCaptureLightDefault() { captureAll(scheme: "light", size: nil) }
    func testCaptureDarkDefault() { captureAll(scheme: "dark", size: nil) }
    func testCaptureLightXXL() { captureAll(scheme: "light", size: "xxl") }
    func testCaptureDarkXXL() { captureAll(scheme: "dark", size: "xxl") }
    func testCaptureLightAX3() { captureAll(scheme: "light", size: "ax3") }
    func testCaptureDarkAX3() { captureAll(scheme: "dark", size: "ax3") }

    /// The real iOS calendar prompt over the calendar step (the host resets calendar privacy
    /// first so iOS asks). Answers "Don't Allow" after the frame.
    func testCaptureCalendarSystemPromptLight() { captureSystemPrompt(scheme: "light") }
    func testCaptureCalendarSystemPromptDark() { captureSystemPrompt(scheme: "dark") }

    private func captureSystemPrompt(scheme: String) {
        app.resetAuthorizationStatus(for: .calendar)
        launch(scheme: scheme, size: nil, ["-LHOnboardingStep", "calendar"])
        let look = app.buttons["onb-primary"]
        XCTAssertTrue(look.waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 1.6)
        tap(look)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "iOS shows its calendar prompt")
        shot("02b-calendar-system-prompt", scheme, nil)
        for label in ["Don’t Allow", "Don't Allow"] where alert.buttons[label].exists {
            alert.buttons[label].tap(); break
        }
    }

    func testCaptureReduceMotionWelcomeLight() { captureWelcome(scheme: "light", suffix: "rm") }
    func testCaptureReduceMotionWelcomeDark() { captureWelcome(scheme: "dark", suffix: "rm") }

    // MARK: Runs

    private func sizeArguments(_ size: String?) -> [String] {
        switch size {
        case "xxl": return ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"]
        case "ax3": return ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        default: return ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        }
    }

    private func launch(scheme: String, size: String?, _ extra: [String]) {
        app.terminate()
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ] + sizeArguments(size) + extra
        app.launch()
    }

    private func captureWelcome(scheme: String, suffix: String) {
        launch(scheme: scheme, size: nil, [])
        XCTAssertTrue(app.buttons["onb-start"].waitForExistence(timeout: 20))
        shot("00-welcome", scheme, suffix)
    }

    private func captureAll(scheme: String, size: String?) {
        let suffix = size
        let perms = ["-LHFakeCalendar", "granted", "-LHFakeNotifications", "granted"]

        // Happy path, real taps.
        launch(scheme: scheme, size: size, perms)
        XCTAssertTrue(app.buttons["onb-start"].waitForExistence(timeout: 20))
        shot("00-welcome", scheme, suffix)
        tap(app.buttons["onb-start"])
        XCTAssertTrue(app.buttons["rental-short"].waitForExistence(timeout: 5))
        shot("01a-goal-rent", scheme, suffix); shotScrolled("01a-goal-rent", scheme, suffix)
        tap(app.buttons["rental-both"])
        XCTAssertTrue(app.buttons["pro-none"].waitForExistence(timeout: 5))
        shot("01b-goal-pro", scheme, suffix); shotScrolled("01b-goal-pro", scheme, suffix)
        tap(app.buttons["pro-none"])
        XCTAssertTrue(app.buttons["goal-100"].waitForExistence(timeout: 5))
        shot("01c-goal-target-100", scheme, suffix); shotScrolled("01c-goal-target-100", scheme, suffix)
        // The other targets: 500 selected, then the 750 (which says what it counts).
        let pinnedTop = app.buttons["onb-primary"].frame.minY
        let c500 = app.buttons["goal-500"]
        for _ in 0..<5 where !c500.exists || !c500.isHittable || c500.frame.maxY > pinnedTop { app.swipeUp(velocity: .slow) }
        tap(c500)
        XCTAssertEqual(app.buttons["onb-primary"].label, "Aim for 500 hours")
        shot("01d-goal-target-500", scheme, suffix)
        let repsCard = app.buttons["goal-750"]
        for _ in 0..<5 where !repsCard.exists || !repsCard.isHittable || repsCard.frame.maxY > pinnedTop { app.swipeUp(velocity: .slow) }
        tap(repsCard)
        shot("01e-goal-target-750", scheme, suffix)
        for _ in 0..<6 { app.swipeDown(velocity: .fast) }
        tap(app.buttons["onb-primary"])
        XCTAssertTrue(app.buttons["onb-link"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.6)                      // rows + hatched storeys
        shot("02-calendar", scheme, suffix)
        tap(app.buttons["onb-primary"])                         // fake Allow
        XCTAssertTrue(app.buttons["who-me"].waitForExistence(timeout: 5))
        shot("03-who", scheme, suffix)
        tap(app.buttons["who-both"])
        shot("03b-who-both", scheme, suffix)
        tap(app.buttons["onb-primary"])
        XCTAssertTrue(app.textFields["property-name"].waitForExistence(timeout: 5))
        _ = app.descendants(matching: .any)["property-hint"].waitForExistence(timeout: 6)
        shot("04-property", scheme, suffix)
        let field = app.textFields["property-name"]
        tap(field)
        field.typeText("Oak Street duplex")
        shot("04d-property-keyboard", scheme, suffix)
        tap(app.buttons["onb-primary"])                         // Save it
        XCTAssertTrue(app.staticTexts["Want a nudge to log it while it’s fresh?"].waitForExistence(timeout: 6))
        shot("05-notify", scheme, suffix)
        tap(app.buttons["onb-primary"])                         // fake Allow
        XCTAssertTrue(app.staticTexts["staked-found"].waitForExistence(timeout: 10))
        shot("06-staked", scheme, suffix)
        tap(app.buttons["onb-today"])                           // Review → Inbox
        XCTAssertTrue(app.buttons["tab.inbox"].waitForExistence(timeout: 10))
        shot("07d-inbox-review", scheme, suffix)
        let confirm = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "inbox.confirm.")).firstMatch
        if confirm.waitForExistence(timeout: 5) {
            tap(confirm)
            shot("07e-inbox-confirmed", scheme, suffix)
        }
        tap(app.buttons["tab.today"])
        shot("07-today-landing", scheme, suffix)

        // A look-back that finds only work that never counts: no "0h found", the honest words.
        launch(scheme: scheme, size: size, perms + ["-LHBackfillNonCountable"])
        tap(app.buttons["onb-start"], timeout: 20)
        UITestIsolation.answerGoalQuestions(app)
        tap(app.buttons["onb-primary"])
        tap(app.buttons["onb-primary"])                         // fake Allow
        tap(app.buttons["onb-primary"])                         // Who: Continue
        let rental = app.textFields["property-name"]
        tap(rental)
        rental.typeText("Oak Street duplex")
        tap(app.buttons["onb-primary"])                         // Save it
        tap(app.buttons["onb-secondary"])                       // note: Not now
        let none = app.staticTexts["staked-nothing-countable"]
        XCTAssertTrue(none.waitForExistence(timeout: 10))
        XCTAssertEqual(none.label.lowercased(), "we found 22 things, but none count toward your hours yet.")
        XCTAssertFalse(app.staticTexts["staked-found"].exists, "Never 0h found")
        shot("06c-staked-none-count", scheme, suffix)

        // Record goal, staked without the calendar.
        launch(scheme: scheme, size: size, ["-LHOnboardingStep", "staked", "-LHOnbGoal", "record"])
        XCTAssertTrue(app.buttons["onb-today"].waitForExistence(timeout: 20))
        shot("06b-staked-record", scheme, suffix)

        // The goal screen with each suggestion first: 500 (long-term, no pro), 750 (me, spouse).
        for (name, rental, pro, first) in [("01f-goal-500-first", "long", "none", "goal-500"),
                                           ("01g-goal-750-me-first", "short", "me", "goal-750"),
                                           ("01h-goal-750-spouse-first", "both", "spouse", "goal-750")] {
            launch(scheme: scheme, size: size, ["-LHOnboardingStep", "goal", "-LHOnbRental", rental, "-LHOnbPro", pro, "-LHOnbGoalPhase", "target"])
            XCTAssertTrue(app.buttons[first].waitForExistence(timeout: 20), name)
            shot(name, scheme, suffix); shotScrolled(name, scheme, suffix)
        }

        // Skip path → Today's empty lot.
        launch(scheme: scheme, size: size, [])
        tap(app.buttons["onb-start"], timeout: 20)
        UITestIsolation.answerGoalQuestions(app)
        tap(app.buttons["onb-primary"])
        tap(app.buttons["onb-link"])
        tap(app.buttons["onb-primary"])
        tap(app.buttons["onb-link"])
        XCTAssertTrue(app.buttons["today.addRental"].waitForExistence(timeout: 10), "The empty lot carries Add a rental")
        shot("08-today-skip", scheme, suffix)

        // Upgraders: What's new.
        launch(scheme: scheme, size: size, ["-LHMockScenario", "occasional", "-LHShowWhatsNew", "-LHInitialTab", "0"] + perms)
        XCTAssertTrue(app.descendants(matching: .any)["onb.whatsNew"].waitForExistence(timeout: 20))
        shot("09-whatsnew-1-house", scheme, suffix)
        tap(app.buttons["onb-primary"])
        XCTAssertTrue(app.buttons["onb-link"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.6)
        shot("09-whatsnew-2-calendar", scheme, suffix)
        tap(app.buttons["onb-primary"])
        XCTAssertTrue(app.buttons["onb-secondary"].waitForExistence(timeout: 5))
        shot("09-whatsnew-3-notify", scheme, suffix)
    }

    // MARK: Helpers

    private func tap(_ element: XCUIElement, timeout: TimeInterval = 10) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "missing \(element)")
        let deadline = Date().addingTimeInterval(timeout)
        while !element.isHittable && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        element.tap()
    }

    /// Large text: the cards scroll. Scroll to the end and shoot again so every line is seen.
    private func shotScrolled(_ name: String, _ scheme: String, _ suffix: String?) {
        guard suffix == "ax3" else { return }
        // Three looks down the page, so no card falls between the first screen and the last.
        for step in 1...3 {
            for _ in 0..<2 { app.swipeUp(velocity: .slow) }
            shot("\(name)-scrolled\(step)", scheme, suffix)
        }
        for _ in 0..<8 { app.swipeDown(velocity: .fast) }
    }

    private func shot(_ name: String, _ scheme: String, _ suffix: String?) {
        Thread.sleep(forTimeInterval: 1.1)                      // let the morph settle
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = [name, scheme, suffix].compactMap { $0 }.joined(separator: "-")
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
