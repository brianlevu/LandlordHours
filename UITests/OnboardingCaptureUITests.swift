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
        XCTAssertTrue(app.buttons["goal-750"].waitForExistence(timeout: 5))
        shot("01a-goal-empty", scheme, suffix)
        tap(app.buttons["goal-750"])
        shot("01-goal", scheme, suffix)
        // Large text: the 500 or 100 card sits below the fold; scroll to it first.
        let mpCard = app.buttons["goal-mp"]
        let pinnedTop = app.buttons["onb-primary"].frame.minY
        // Clear of the pinned button (a tap there would land on the pinned area, not the card).
        for _ in 0..<5 where !mpCard.exists || mpCard.frame.minY + 60 > pinnedTop { app.swipeUp(velocity: .slow) }
        mpCard.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.0)).withOffset(CGVector(dx: 0, dy: 30)).tap()
        let mp500 = app.buttons["goal-mp500"]
        for _ in 0..<3 where !(mp500.exists && mp500.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertEqual(app.buttons["onb-primary"].label, "Build toward 500h", "The 500h goal is selected")
        shot("01b-goal-mp", scheme, suffix)
        let repsCard = app.buttons["goal-750"]
        for _ in 0..<4 where !repsCard.isHittable { app.swipeDown(velocity: .slow) }
        tap(repsCard)
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
        XCTAssertTrue(app.staticTexts["Want a note when a visit ends?"].waitForExistence(timeout: 6))
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
        tap(app.buttons["goal-750"])
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
        XCTAssertEqual(none.label.lowercased(), "we found 22 things, but none count toward your hours yet")
        XCTAssertFalse(app.staticTexts["staked-found"].exists, "Never 0h found")
        shot("06c-staked-none-count", scheme, suffix)

        // Record goal, staked without the calendar.
        launch(scheme: scheme, size: size, ["-LHOnboardingStep", "staked", "-LHOnbGoal", "record"])
        XCTAssertTrue(app.buttons["onb-today"].waitForExistence(timeout: 20))
        shot("06b-staked-record", scheme, suffix)

        // Skip path → Today's empty lot.
        launch(scheme: scheme, size: size, [])
        tap(app.buttons["onb-start"], timeout: 20)
        tap(app.buttons["goal-750"])
        tap(app.buttons["onb-primary"])
        tap(app.buttons["onb-link"])
        tap(app.buttons["onb-primary"])
        tap(app.buttons["onb-link"])
        XCTAssertTrue(app.buttons["today.hero.addProperty"].waitForExistence(timeout: 10))
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

    private func shot(_ name: String, _ scheme: String, _ suffix: String?) {
        Thread.sleep(forTimeInterval: 1.1)                      // let the morph settle
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = [name, scheme, suffix].compactMap { $0 }.joined(separator: "-")
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
