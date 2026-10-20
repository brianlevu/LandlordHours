import XCTest

/// WP-R: Records, Reports and Settings on the Blueprint 2.0 language. Behaviour checks plus the
/// frame capture for the visual gate (`TEST_RUNNER_LH_CAPTURE_DIR=<dir>` writes PNGs there).
final class RecordsReportsSettingsUITests: XCTestCase {
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

    // MARK: Behaviour

    func testRecordsTotalCarriesTheCountsYourHoursLabel() {
        launch(tab: 6)
        let label = element("records.totalLabel")
        XCTAssertTrue(label.waitForExistence(timeout: 20), "Records shows the label under its total")
        XCTAssertEqual(label.label, "All logged hours. The 750h test counts your hours only.")
        XCTAssertTrue(element("records.total").exists)
        let monthHeader = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "records.month.")).firstMatch
        XCTAssertTrue(monthHeader.waitForExistence(timeout: 5), "Records are grouped by month")
    }

    func testRecordsRowOpensTheRecordAndEditsInPlace() {
        launch(tab: 6)
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "records.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        tapRetrying(row, until: app.buttons["entry.edit"])
        XCTAssertFalse(app.buttons["tab.logTime"].isHittable, "The record hides the tab bar")
        app.buttons["entry.edit"].tap()
        XCTAssertTrue(app.buttons["Fifteen minutes more"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["entry.save"].exists)
    }

    func testRecordsSourceFilterNarrowsTheList() {
        launch(tab: 6)
        let source = app.buttons["records.filter.source"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 20))
        let manual = app.buttons.matching(NSPredicate(format: "label == %@", "Manual")).firstMatch
        tapRetrying(source, until: manual)
        manual.tap()
        let narrowed = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "records.filter.source", "Manual")).firstMatch
        XCTAssertTrue(narrowed.waitForExistence(timeout: 5), "The Source chip shows the chosen source")
    }

    func testReportsLeadWithEachPersonsStanding() {
        launch(tab: 3)
        let you = element("reports.standing.you")
        XCTAssertTrue(you.waitForExistence(timeout: 20))
        XCTAssertTrue(you.label.contains("You"), you.label)
        XCTAssertTrue(you.value.map { "\($0)".contains("of 750 hours") } ?? false)
        XCTAssertTrue(element("reports.monthChart").exists || scrollTo(element("reports.monthChart")))
    }

    func testSettingsShowsAutoCaptureWithTheAppleAIDisclosure() {
        launch(tab: 4)
        let calendarSwitch = element("settings.capture.calendar")
        XCTAssertTrue(scrollTo(calendarSwitch), "Auto-capture section is in Settings")
        XCTAssertTrue(element("settings.capture.prompts").exists)
        let disclosure = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Apple's on-device model. Nothing is sent to us or any third party.")).firstMatch
        XCTAssertTrue(scrollTo(disclosure), "Apple AI disclosure is shown")
        element("settings.capture.muted").tap()
        XCTAssertTrue(element("settings.muted.screen").waitForExistence(timeout: 5))
    }

    func testReportsAndSettingsLeadBackToToday() {
        for tab in [3, 4] {
            launch(tab: tab)
            let back = app.buttons["shell.backToToday"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 20))
            XCTAssertTrue(app.buttons["tab.today"].isSelected, "Reports and Settings sit under Today")
            tapRetrying(back, until: element("today.hero"))
        }
    }

    // MARK: Frames

    func testCaptureWPRFramesLight() { captureAll(scheme: "light") }
    func testCaptureWPRFramesDark() { captureAll(scheme: "dark") }
    func testCaptureWPRFramesLargeText() {
        for (size, tag) in [("UICTContentSizeCategoryXXL", "xxl"), ("UICTContentSizeCategoryAccessibilityXXL", "axxxl")] {
            for scheme in ["light", "dark"] {
                launch(tab: 6, scheme: scheme, extra: ["-UIPreferredContentSizeCategoryName", size])
                XCTAssertTrue(element("records.screen").waitForExistence(timeout: 20))
                settleAndCapture("records-\(tag)-\(scheme)")
                app.swipeUp()
                app.swipeUp()
                settleAndCapture("records-\(tag)-\(scheme)-scrolled")
                launch(tab: 3, scheme: scheme, extra: ["-UIPreferredContentSizeCategoryName", size])
                XCTAssertTrue(element("reports.standing.you").waitForExistence(timeout: 20))
                settleAndCapture("reports-\(tag)-\(scheme)")
                app.swipeUp()
                settleAndCapture("reports-\(tag)-\(scheme)-scrolled")
            }
        }
    }

    /// Follow-up frames: Settings with Dark chosen ("Saved: dark mode") and Reports' branded switcher.
    func testCaptureFollowUpFrames() {
        for scheme in ["light", "dark"] {
            launch(tab: 4, scheme: scheme)
            let dark = app.buttons["Dark appearance"]
            XCTAssertTrue(scrollTo(dark), "Dark appearance pill")
            dark.tap()
            let saved = app.staticTexts["Saved: dark mode"]
            XCTAssertTrue(saved.waitForExistence(timeout: 5))
            settleAndCapture("settings-appearance-dark-selected-\(scheme)")
            // Restore so the choice does not leak into later runs.
            let auto = app.buttons["Auto appearance"]
            if auto.exists { auto.tap() }

            launch(tab: 4, scheme: scheme)
            tapWhenReady(element("settings.learningCenter"))
            XCTAssertTrue(app.staticTexts["Learning center"].waitForExistence(timeout: 5))
            settleAndCapture("settings-learning-center-\(scheme)")

            launch(tab: 3, scheme: scheme)
            let goal = element("reports.goal")
            XCTAssertTrue(goal.waitForExistence(timeout: 20))
            settleAndCapture("reports-goal-switcher-\(scheme)")
        }
    }

    /// Contact support with both fields filled: "Send email" is enabled only in this state.
    func testCaptureContactSupportFilled() {
        for scheme in ["light", "dark"] {
            launch(tab: 4, scheme: scheme)
            tapWhenReady(element("settings.contactSupport"))
            XCTAssertTrue(element("support.screen").waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["support.send"].isEnabled, "Send email starts disabled")
            let message = element("support.message")
            message.tap()
            message.typeText("How do I add a property to the PDF?")
            let subject = element("support.subject")
            subject.tap()
            // Return on the one-line subject field ends editing, so the keyboard is gone.
            subject.typeText("Export question\n")
            XCTAssertTrue(app.buttons["support.send"].isEnabled, "Send email enables once both fields are filled")
            settleAndCapture("settings-contact-support-filled-\(scheme)")
        }
    }

    private func captureAll(scheme: String) {
        // Records + record detail + edit.
        launch(tab: 6, scheme: scheme)
        XCTAssertTrue(element("records.totalLabel").waitForExistence(timeout: 20))
        settleAndCapture("records-\(scheme)")
        app.swipeUp()
        settleAndCapture("records-\(scheme)-scrolled")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "records.row.")).firstMatch
        app.swipeDown()
        app.swipeDown()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        tapRetrying(row, until: app.buttons["entry.edit"])
        settleAndCapture("record-detail-\(scheme)")
        app.buttons["entry.edit"].tap()
        settleAndCapture("record-edit-\(scheme)")

        // Records export sheet.
        launch(tab: 6, scheme: scheme)
        let export = app.buttons["records.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 20))
        tapRetrying(export, until: element("export.preview"))
        settleAndCapture("export-\(scheme)", wait: 2.5)

        // Reports.
        launch(tab: 3, scheme: scheme)
        XCTAssertTrue(element("reports.standing.you").waitForExistence(timeout: 20))
        settleAndCapture("reports-\(scheme)")
        app.swipeUp()
        settleAndCapture("reports-\(scheme)-scrolled-1")
        app.swipeUp()
        settleAndCapture("reports-\(scheme)-scrolled-2")
        // 100-hour goal with the participation question.
        app.swipeDown(); app.swipeDown()
        let mp100 = app.buttons["100h"]
        if mp100.waitForExistence(timeout: 5) {
            mp100.tap()
            settleAndCapture("reports-mp100-\(scheme)")
            let confirmRow = app.buttons["reports.mp100.confirmRow"]
            if confirmRow.waitForExistence(timeout: 3) {
                confirmRow.tap()
                XCTAssertTrue(app.buttons["participation.answer.yes"].waitForExistence(timeout: 5))
                // Pull the sheet to its large detent so the whole question and both answers show.
                let grabber = app.otherElements["participation.sheet"].firstMatch
                (grabber.exists ? grabber : app.buttons["participation.answer.yes"]).swipeUp()
                settleAndCapture("reports-participation-sheet-\(scheme)")
            }
        }

        // Settings and its sub-screens.
        launch(tab: 4, scheme: scheme)
        XCTAssertTrue(element("settings.proCard").waitForExistence(timeout: 20))
        settleAndCapture("settings-\(scheme)")
        for page in 1...4 {
            app.swipeUp()
            settleAndCapture("settings-\(scheme)-page\(page + 1)")
        }

        launch(tab: 4, scheme: scheme)
        tapWhenReady(element("settings.taxProfile"))
        XCTAssertTrue(app.staticTexts["Tax profile"].waitForExistence(timeout: 5))
        settleAndCapture("settings-tax-profile-\(scheme)")
        app.swipeUp()
        settleAndCapture("settings-tax-profile-\(scheme)-scrolled")

        launch(tab: 4, scheme: scheme)
        tapWhenReady(element("settings.capture.muted"))
        XCTAssertTrue(element("settings.muted.screen").waitForExistence(timeout: 5))
        settleAndCapture("settings-muted-\(scheme)")

        launch(tab: 4, scheme: scheme)
        tapWhenReady(element("settings.contactSupport"))
        XCTAssertTrue(element("support.screen").waitForExistence(timeout: 5))
        settleAndCapture("settings-contact-support-\(scheme)")

        launch(tab: 4, scheme: scheme)
        tapWhenReady(element("settings.learningCenter"))
        XCTAssertTrue(app.staticTexts["Learning center"].waitForExistence(timeout: 5))
        settleAndCapture("settings-learning-center-\(scheme)")

        launch(tab: 4, scheme: scheme)
        tapWhenReady(element("settings.deleteData"), maxSwipes: 12)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        settleAndCapture("settings-delete-data-\(scheme)")
        app.alerts.firstMatch.buttons["Cancel"].tap()

        launch(tab: 4, scheme: scheme)
        tapWhenReady(element("settings.profile"))
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        settleAndCapture("settings-profile-edit-\(scheme)")

        // Profiles / restore (needs an earlier profile on the device).
        launch(tab: 4, scheme: scheme, scenario: nil, extra: ["-LHSeedLegacyEmailProfile"])
        let restore = element("settings.restoreOtherData")
        if restore.waitForExistence(timeout: 10) {
            tapWhenReady(restore)
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "restore.profile.")).firstMatch.waitForExistence(timeout: 5))
            settleAndCapture("settings-restore-\(scheme)")
        }
    }

    // MARK: Helpers

    private func launch(tab: Int, scheme: String = "light", scenario: String? = "frequent", extra: [String] = []) {
        app.terminate()
        var args = [UITestIsolation.resetProfilesArgument]
        if let scenario { args += ["-LHMockScenario", scenario] }
        args += [
            "-LHInitialTab", "\(tab)",
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launchArguments = args + extra
        app.launch()
    }

    /// The launch splash fades over ~1s while the tree already exists, so a first tap can land on
    /// it. Tap until the expected result appears.
    private func tapRetrying(_ element: XCUIElement, until result: XCUIElement, attempts: Int = 5) {
        for _ in 0..<attempts where !result.exists {
            if element.exists, element.isHittable { element.tap() }
            if result.waitForExistence(timeout: 3) { return }
        }
        XCTAssertTrue(result.exists, "Tapping \(element) never showed \(result)")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @discardableResult
    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 10) -> Bool {
        var swipes = 0
        while (!element.exists || !element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.exists
    }

    private func tapWhenReady(_ element: XCUIElement, maxSwipes: Int = 10) {
        _ = element.waitForExistence(timeout: 15)
        XCTAssertTrue(scrollTo(element, maxSwipes: maxSwipes), "Missing \(element)")
        // Keep clear of the floating tab bar.
        let tabBar = app.buttons["tab.today"]
        if tabBar.exists, element.frame.maxY > tabBar.frame.minY - 8 {
            app.swipeUp()
        }
        element.tap()
    }

    private func settleAndCapture(_ name: String, wait: TimeInterval = 1.2) {
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
