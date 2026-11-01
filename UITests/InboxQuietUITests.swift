import XCTest

/// 2.3 package F: the quiet Inbox. "Not sure" items sit behind one collapsed row and are not counted;
/// a calendar the user keeps calling "Not rental work" gets a one-time prompt; Settings lists the
/// calendars. Seeded by the DEBUG hooks (`-LHSeedSuggestions inbox`: two "Not sure" items,
/// `call-sam` and `hoa`; `-LHInboxQuietPrompt`; `-LHInboxQuietCalendars`). Synthetic data only.
/// Identifiers and keys only, never English wording (standard C.1a).
final class InboxQuietUITests: XCTestCase {
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

    private func launch(tab: Int = 5, scheme: String = "light", size: String? = nil, extra: [String] = []) {
        app.terminate()
        var args = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "emptyMainTabs",
            "-LHSeedSuggestions", "inbox",
            "-LHInitialTab", "\(tab)",
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-LHFixedNow", "2026-10-16T15:00",
            "-LHInboxQuietCalendars",
        ]
        if let size { args += ["-UIPreferredContentSizeCategoryName", size] }
        app.launchArguments = args + extra
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func row(_ key: String) -> XCUIElement { element("inbox.row.cal:debug-\(key)") }

    @discardableResult
    private func settle(_ element: XCUIElement, timeout: TimeInterval = 20) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        let deadline = Date().addingTimeInterval(5)
        while !element.isHittable, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        Thread.sleep(forTimeInterval: 1.0)
        return element.exists
    }

    @discardableResult
    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) -> Bool {
        var swipes = 0
        let tabBar = app.buttons["tab.today"]
        while swipes < maxSwipes {
            if element.exists, element.isHittable, !(tabBar.exists && element.frame.maxY > tabBar.frame.minY - 8) { return true }
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        return element.exists && element.isHittable
    }

    /// The count after "To confirm · N" (the header reads "To confirm, N" or similar to VoiceOver).
    private func headerCount() -> Int? {
        let header = element("inbox.section.count")
        guard header.waitForExistence(timeout: 10) else { return nil }
        let digits = header.label.split(whereSeparator: { !$0.isNumber })
        return digits.last.flatMap { Int($0) }
    }

    // MARK: Behaviour

    func testNotSureItemsSitBehindOneCollapsedRowAndAreNotCounted() {
        launch()
        XCTAssertTrue(settle(row("plumber")), "The main list shows the sure items")
        XCTAssertFalse(row("call-sam").exists, "A Not sure item is not in the main list")
        XCTAssertFalse(row("hoa").exists)
        // Seed: 8 items, 2 of them Not sure → 6 to confirm.
        XCTAssertEqual(headerCount(), 6, element("inbox.section.count").label)

        let maybe = element("inbox.maybe.row")
        XCTAssertTrue(scrollTo(maybe), "One collapsed Not sure row under the card")
        XCTAssertTrue(maybe.label.contains("2"), maybe.label)
        maybe.tap()
        XCTAssertTrue(element("inbox.maybe.screen").waitForExistence(timeout: 5))
        XCTAssertTrue(settle(row("call-sam")))
        XCTAssertTrue(row("hoa").exists || scrollTo(row("hoa")))
        XCTAssertFalse(row("plumber").exists, "Only Not sure items behind the row")
    }

    func testNotRentalWorkInsideNotSureLeavesTheList() {
        launch()
        XCTAssertTrue(settle(row("plumber")))
        XCTAssertTrue(scrollTo(element("inbox.maybe.row")))
        element("inbox.maybe.row").tap()
        let sam = row("call-sam")
        XCTAssertTrue(settle(sam))
        sam.swipeLeft()
        let dismiss = app.buttons["inbox.swipe.dismiss"]
        if dismiss.waitForExistence(timeout: 2), dismiss.isHittable { dismiss.tap() }
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: sam)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["inbox.undo"].waitForExistence(timeout: 5), "Undo is offered")
    }

    func testACalendarPromptAsksOnceAndStopCheckingTakesItsItemsOut() {
        let gone = NSPredicate(format: "exists == false")
        // Keep checking: the prompt goes, the items stay.
        launch(extra: ["-LHInboxQuietPrompt"])
        XCTAssertTrue(settle(element("inbox.quiet.prompt")), "Three Not rental work answers, no confirms: the prompt shows")
        element("inbox.quiet.prompt.keep").tap()
        expectation(for: gone, evaluatedWith: element("inbox.quiet.prompt"))
        waitForExpectations(timeout: 5)
        XCTAssertTrue(row("plumber").exists, "Keep checking leaves the items")

        // Stop checking (the DEBUG seed re-arms the prompt on launch): the calendar's items leave.
        launch(extra: ["-LHInboxQuietPrompt"])
        let prompt = element("inbox.quiet.prompt")
        XCTAssertTrue(settle(prompt))
        element("inbox.quiet.prompt.stop").tap()
        expectation(for: gone, evaluatedWith: prompt)
        waitForExpectations(timeout: 5)
        // Every seeded calendar item was on that calendar: only the receipt is left.
        XCTAssertTrue(element("inbox.row.rcpt:homedepot").waitForExistence(timeout: 5))
        XCTAssertFalse(row("plumber").exists)
    }

    func testSettingsListsTheCalendarsAndTurnsOneOff() {
        launch(tab: 4)
        let calendars = element("settings.capture.calendars")
        XCTAssertTrue(scrollTo(calendars, maxSwipes: 10), "Settings › Auto-capture lists Calendars")
        calendars.tap()
        XCTAssertTrue(element("calendars.sheet").waitForExistence(timeout: 5))
        // "Home" is never turned off by another test (the prompt test turns off the work calendar).
        let home = app.switches["calendars.toggle.debug-home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        XCTAssertEqual(home.value as? String, "1", "A calendar is checked until the user turns it off")
        tapSwitch(home)
        XCTAssertEqual(home.value as? String, "0")
        tapSwitch(home)   // leave it as found: the choice is stored per profile on the device
        XCTAssertEqual(home.value as? String, "1")
    }

    private func tapSwitch(_ element: XCUIElement) {
        let inner = element.switches.firstMatch
        (inner.exists ? inner : element).coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: Frames for the gates (LH_CAPTURE_DIR)

    func testCaptureQuietFrames() throws {
        guard ProcessInfo.processInfo.environment["LH_CAPTURE_DIR"] != nil else {
            throw XCTSkip("Frames only when LH_CAPTURE_DIR is set")
        }
        let sizes: [(String, String?)] = [("default", nil), ("xxl", "UICTContentSizeCategoryXXL"),
                                          ("ax3", "UICTContentSizeCategoryAccessibilityXXXL")]
        for scheme in ["light", "dark"] {
            for (sizeName, size) in sizes {
                let suffix = "\(scheme)-\(sizeName)"
                // The Inbox without the prompt, at rest: the density baseline for f1.
                launch(scheme: scheme, size: size)
                _ = settle(row("plumber"))
                capture("f0-inbox-\(suffix)")
                launch(scheme: scheme, size: size, extra: ["-LHInboxQuietPrompt"])
                _ = settle(element("inbox.quiet.prompt"))
                capture("f1-inbox-prompt-\(suffix)")
                _ = scrollTo(element("inbox.maybe.row"))
                // Settle at the end of the list so the row sits clear of the fade and the tab bar.
                for _ in 0..<3 { app.swipeUp(velocity: .slow) }
                capture("f2-inbox-maybe-row-\(suffix)")
                element("inbox.maybe.row").tap()
                _ = settle(row("call-sam"))
                capture("f3-maybe-screen-\(suffix)")

                launch(tab: 4, scheme: scheme, size: size)
                let calendars = element("settings.capture.calendars")
                _ = scrollTo(calendars, maxSwipes: 10)
                capture("f4-settings-calendars-row-\(suffix)")
                calendars.tap()
                _ = settle(element("calendars.sheet"))
                capture("f5-calendars-sheet-\(suffix)")
            }
        }
    }

    private func capture(_ name: String, wait: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: wait)
        let screenshot = XCUIScreen.main.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        if let dir = ProcessInfo.processInfo.environment["LH_CAPTURE_DIR"], !dir.isEmpty {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
