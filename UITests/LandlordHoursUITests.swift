import XCTest

final class LandlordHoursUITests: XCTestCase {
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

    /// 2.0: the first property needs only a name; the address is folded away.
    func testFirstRunPropertyNeedsOnlyAName() {
        launch(scenario: "firstTime", tab: 0)
        waitAndTap(app.buttons["onb-start"])
        XCTAssertTrue(app.staticTexts["What do you rent out?"].waitForExistence(timeout: 8))
        waitAndTap(app.buttons["rental-both"])
        waitAndTap(app.buttons["pro-none"])
        let goalCTA = app.buttons["onb-primary"]
        XCTAssertTrue(goalCTA.waitForExistence(timeout: 5))
        XCTAssertEqual(goalCTA.label, "Aim for 100 hours", "Both kinds, no real estate pro: 100 hours is suggested and selected")
        waitAndTap(app.buttons["goal-500"])
        XCTAssertEqual(goalCTA.label, "Aim for 500 hours")
        waitAndTap(goalCTA)
        waitAndTap(app.buttons["onb-link"])                    // Calendar: Not now
        waitAndTap(app.buttons["who-both"])
        XCTAssertTrue(app.descendants(matching: .any)["who-note"].waitForExistence(timeout: 3))
        waitAndTap(app.buttons["onb-primary"])

        let save = app.buttons["onb-primary"]
        XCTAssertTrue(app.staticTexts["Which rental first?"].waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "Save waits for a name")
        XCTAssertFalse(app.textFields["property-address"].exists, "Address folded away")
        let nameField = app.textFields["property-name"]
        nameField.tap()
        nameField.typeText("Oak Street Duplex")
        XCTAssertTrue(save.isEnabled)
        waitAndTap(app.buttons["property-add-address"])
        XCTAssertTrue(app.textFields["property-address"].waitForExistence(timeout: 3))
    }

    /// 2.0: the old Track tab index opens the Log time sheet; every detail row is right there.
    func testTrackManualDetailsFlowIsReachable() {
        launch(scenario: "frequent", tab: 2)

        XCTAssertTrue(app.buttons["log.close"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["log.property"].exists)
        XCTAssertTrue(app.buttons["log.category"].exists)
        XCTAssertTrue(app.buttons["log.date"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["log.hours.value"].exists)
    }

    func testTrackNoteTypingStaysInComposer() {
        launch(scenario: "occasional", tab: 2)

        let noteEditor = app.descendants(matching: .any)["log.note"].firstMatch
        XCTAssertTrue(noteEditor.waitForExistence(timeout: 8))

        noteEditor.tap()
        noteEditor.typeText("painted porch for 1 hour")

        XCTAssertFalse(app.staticTexts["Top Hit"].exists)
        XCTAssertEqual(noteEditor.value as? String, "painted porch for 1 hour")
        XCTAssertTrue(app.descendants(matching: .any)["log.fill.caption"].waitForExistence(timeout: 5))
    }

    func testReportsExportGeneratesShareablePDFState() {
        launch(scenario: "frequent", tab: 3)

        XCTAssertTrue(app.staticTexts["Reports"].waitForExistence(timeout: 8))
        // The launch splash fades out over ~1s while the Reports tree already exists;
        // tapping before the button is hittable lands on the splash overlay.
        // The accessibility tree reports the button hittable while the splash still
        // covers it, so retry the tap until the export sheet actually opens.
        let exportTitle = app.staticTexts["Export report"]
        for _ in 0..<5 where !exportTitle.exists {
            let exportButton = app.buttons["Export report"]
            if exportButton.waitForExistence(timeout: 3), exportButton.isHittable {
                exportButton.tap()
            }
            _ = exportTitle.waitForExistence(timeout: 3)
        }

        let generateButton = app.buttons["export.generatePDF"]
        assertVisibleText("Export report", timeout: 5)
        scrollToElement(generateButton)
        generateButton.tap()

        XCTAssertTrue(app.staticTexts["Report ready"].waitForExistence(timeout: 8), "Export view shows Report ready")
        XCTAssertTrue(app.buttons["export.sharePDF"].exists)
    }

    func testMaterialParticipation100HourConfirmationStates() {
        launch(scenario: "frequent", tab: 3)

        XCTAssertTrue(app.staticTexts["Reports"].waitForExistence(timeout: 8))

        // Switch to the 100-hour material participation goal.
        let mp100Pill = app.buttons["100h"]
        XCTAssertTrue(mp100Pill.waitForExistence(timeout: 5))
        mp100Pill.tap()

        // State 1: conditional prompt (hours over 100, confirmation unanswered).
        let confirmRow = app.buttons["reports.mp100.confirmRow"]
        XCTAssertTrue(confirmRow.waitForExistence(timeout: 5))
        assertStanding(contains: "100 hours reached")
        attachScreenshot(named: "mp100-1-conditional-reports")

        // State 2: the confirmation question sheet.
        confirmRow.tap()
        let answerYes = app.buttons["participation.answer.yes"]
        XCTAssertTrue(answerYes.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["participation.answer.no"].exists)
        attachScreenshot(named: "mp100-2-confirmation-ui")

        // State 3: confirmed — the 100-hour test passes.
        answerYes.tap()
        XCTAssertTrue(app.staticTexts["No one participated more"].waitForExistence(timeout: 5))
        assertStanding(contains: "Goal met")
        attachScreenshot(named: "mp100-3-confirmed-reports")
    }

    /// Reports' standing card speaks its status in its accessibility value.
    private func assertStanding(contains text: String, timeout: TimeInterval = 5) {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@ AND value CONTAINS %@", "reports.standing.", text)
        let card = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: timeout), "Expected a standing card saying: \(text)")
    }

    func testSettingsSecondaryFlowsOpenWithoutSwitchingTabs() {
        launch(scenario: "frequent", tab: 4)

        assertVisibleText("Settings", timeout: 12)
        // Settings is a lazy List: rows below the fold exist only once scrolled to.
        let taxProfile = app.buttons["settings.taxProfile"]
        _ = app.buttons["settings.profile"].waitForExistence(timeout: 5)
        scrollToElement(taxProfile)
        let tabBar = app.buttons["tab.today"]
        if tabBar.exists, taxProfile.frame.maxY > tabBar.frame.minY - 8 { app.swipeUp() }
        taxProfile.tap()

        XCTAssertTrue(app.staticTexts["Tax profile"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tab.logTime"].isHittable)
    }

    func testAppearancePreferenceShowsSavedStateAndPersists() {
        launch(scenario: "emptyMainTabs", tab: 0)
        _ = app.staticTexts.firstMatch.waitForExistence(timeout: 8)
        app.terminate()

        launch(scenario: "frequent", tab: 4)

        assertVisibleText("Settings", timeout: 12)
        scrollToElement(app.buttons["Dark appearance"])
        app.buttons["Dark appearance"].tap()

        XCTAssertTrue(app.staticTexts["Saved: dark mode"].waitForExistence(timeout: 5))

        app.terminate()
        launch(scenario: "frequent", tab: 4)

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 8))
        scrollToElement(app.staticTexts["Saved: dark mode"])
        XCTAssertTrue(app.staticTexts["Saved: dark mode"].exists)
    }

    func testMainTabVisualSmokeMatrix() {
        let matrix: [(scenario: String, tab: Int, expectedText: String, attachment: String)] = [
            ("emptyMainTabs", 0, "Add your first property", "empty-home"),
            ("emptyMainTabs", 1, "Once we know where your rentals are", "empty-properties"),
            ("emptyMainTabs", 2, "Add a property to log this.", "empty-track"),
            ("emptyMainTabs", 3, "Reports", "empty-reports"),
            ("emptyMainTabs", 4, "LandlordHours\u{00A0}Pro", "empty-settings"),
            ("occasional", 0, "Today’s work", "occasional-home"),
            ("occasional", 1, "1 rental ·", "occasional-properties"),
            ("occasional", 2, "Log time", "occasional-track"),
            ("occasional", 3, "Reports", "occasional-reports"),
            ("occasional", 4, "Settings", "occasional-settings"),
            ("frequent", 0, "counted toward 750 hours", "frequent-home"),
            ("frequent", 1, "3 rentals ·", "frequent-properties"),
            ("frequent", 2, "Log time", "frequent-track"),
            ("frequent", 3, "Reports", "frequent-reports"),
            ("frequent", 4, "Pro is active", "frequent-settings")
        ]

        for item in matrix {
            XCTContext.runActivity(named: "\(item.attachment)") { _ in
                app.terminate()
                launch(scenario: item.scenario, tab: item.tab)
                assertVisibleText(item.expectedText, timeout: 8)
                attachScreenshot(named: item.attachment)
                XCTAssertFalse(app.staticTexts["Welcome to LandlordHours"].exists)
            }
        }
    }

    func testTrackEmptyStateAddPropertyCTAOpensPropertySheet() {
        launch(scenario: "emptyMainTabs", tab: 2)

        assertVisibleText("Add a property to log this.", timeout: 8)
        app.buttons["log.property"].tap()
        let addProperty = app.buttons["picker.addProperty"]
        XCTAssertTrue(addProperty.waitForExistence(timeout: 5))
        addProperty.tap()

        let propertyName = app.textFields["property.name"]
        XCTAssertTrue(propertyName.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["property.address"].exists)
        attachScreenshot(named: "track-empty-add-property-route")
    }

    func testTimerLaunchStatesRemainReviewable() {
        launch(scenario: "frequent", tab: 0, extraArguments: ["-LHOpenLog", "timerIdle"])
        XCTAssertTrue(app.buttons["timer.start"].waitForExistence(timeout: 8))
        attachScreenshot(named: "timer-idle-state")

        app.terminate()
        launch(scenario: "frequent", tab: 0, extraArguments: ["-LHOpenLog", "timerRunning"])
        XCTAssertTrue(app.buttons["timer.stop"].waitForExistence(timeout: 8))
        attachScreenshot(named: "timer-running-state")

        app.terminate()
        launch(scenario: "frequent", tab: 0, extraArguments: ["-LHOpenLog", "timerReview"])
        XCTAssertTrue(app.buttons["log.save"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["log.timer.ran"].exists)
        attachScreenshot(named: "timer-review-state")
    }

    func testEngagementLabSurfacesStayReviewable() {
        launch(scenario: "frequent", tab: 4, extraArguments: ["-LHOpenEngagementLab", "-LHEngagementSurface", "widget"])
        assertVisibleText("Engagement Intelligence", timeout: 12)
        scrollToText("Persistent memory without interruption.", timeout: 8)
        attachScreenshot(named: "engagement-lab-widget")

        app.terminate()
        launch(scenario: "frequent", tab: 4, extraArguments: ["-LHOpenEngagementLab", "-LHEngagementSurface", "liveActivity"])
        assertVisibleText("Engagement Intelligence", timeout: 12)
        scrollToText("Use only for bounded work in progress.", timeout: 8)
        attachScreenshot(named: "engagement-lab-live-activity")

        app.terminate()
        launch(scenario: "frequent", tab: 4, extraArguments: ["-LHOpenEngagementLab", "-LHEngagementSurface", "siri"])
        assertVisibleText("Engagement Intelligence", timeout: 12)
        scrollToText("A concise answer plus the next useful action.", timeout: 8)
        attachScreenshot(named: "engagement-lab-siri")
    }

    func testFirstTimeActivationFlowAddsPropertyAndLogsFirstHour() {
        launch(scenario: "emptyMainTabs", tab: 0)

        // 2.0: an owner with no property sees the empty lot; its "Add property" is the one action.
        let addProperty = app.buttons["today.hero.addProperty"].firstMatch
        XCTAssertTrue(addProperty.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Finish your tax-ready setup"].exists, "Setup card follows the first property")
        let propertyName = app.textFields["property.name"]
        // The launch splash fades over ~1s and can swallow the first tap.
        for _ in 0..<3 where !propertyName.exists {
            tapWhenHittable(addProperty, scrollIfNeeded: true)
            _ = propertyName.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(propertyName.waitForExistence(timeout: 5))
        propertyName.tap()
        propertyName.typeText("Oak Street Duplex")

        let propertyAddress = app.textFields["property.address"]
        XCTAssertTrue(propertyAddress.waitForExistence(timeout: 5))
        if app.keyboards.buttons["Next"].waitForExistence(timeout: 2) {
            app.keyboards.buttons["Next"].tap()
        } else {
            app.typeText("\n")
        }
        app.typeText("123 Main Street")

        let saveProperty = app.buttons["property.save"]
        XCTAssertTrue(saveProperty.waitForExistence(timeout: 5))
        XCTAssertTrue(saveProperty.isEnabled)
        saveProperty.tap()

        XCTAssertTrue(app.staticTexts["Oak Street Duplex"].waitForExistence(timeout: 5))

        app.buttons["tab.today"].tap()
        let firstHourTile = app.buttons["home.activation.firstHour"]
        scrollToElement(firstHourTile)
        tapWhenHittable(firstHourTile, scrollIfNeeded: true)

        let noteEditor = app.descendants(matching: .any)["log.note"].firstMatch
        XCTAssertTrue(noteEditor.waitForExistence(timeout: 5))
        noteEditor.tap()
        noteEditor.typeText("Reviewed tenant message at Oak Street Duplex for 1 hour")

        let logTime = app.buttons["log.save"]
        XCTAssertTrue(logTime.waitForExistence(timeout: 5))
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: logTime)
        waitForExpectations(timeout: 5)
        logTime.tap()

        XCTAssertTrue(app.descendants(matching: .any)["shell.toast"].waitForExistence(timeout: 5))

        XCTAssertFalse(app.staticTexts["Finish your tax-ready setup"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["home.activation.firstHour"].exists)
    }

    func testAttachmentPhotoSurvivesForceQuitAndRelaunch() {
        // Launch 1: seed an entry that carries a real, file-backed attachment.
        // 2.0: Today no longer lists recent entries (Records owns them), so open Records.
        launch(scenario: "occasional", tab: 6, extraArguments: ["-LHSeedAttachment"])

        // Scroll until the row is hittable before tapping.
        let entryRow = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Called tenant")).firstMatch
        XCTAssertTrue(entryRow.waitForExistence(timeout: 20))
        tapWhenHittable(entryRow, scrollIfNeeded: true)

        XCTAssertTrue(app.staticTexts["Attachments (1)"].waitForExistence(timeout: 6),
                      "Seeded attachment should render before relaunch")
        attachScreenshot(named: "attachment-before-relaunch")

        // Force-quit and relaunch WITHOUT reseeding: the entry and its photo must
        // load from disk (the user stays signed in via the persisted scope keys).
        app.terminate()
        app.launchArguments = [
            "-LHInitialTab", "6",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        let entryRowAgain = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Called tenant")).firstMatch
        XCTAssertTrue(entryRowAgain.waitForExistence(timeout: 20),
                      "Persisted entry should still be present after relaunch")
        tapWhenHittable(entryRowAgain, scrollIfNeeded: true)

        XCTAssertTrue(app.staticTexts["Attachments (1)"].waitForExistence(timeout: 6),
                      "Attachment must still render after a true process restart")
        attachScreenshot(named: "attachment-after-relaunch")
    }

    private func launch(scenario: String, tab: Int, extraArguments: [String] = []) {
        app.terminate()
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", scenario,
            "-LHInitialTab", "\(tab)",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ] + extraArguments
        app.launch()
    }

    /// Waits until `element` is actually hittable (not under the splash overlay or the
    /// floating tab bar), optionally scrolling, then taps it.
    private func tapWhenHittable(_ element: XCUIElement, scrollIfNeeded: Bool = false, timeout: TimeInterval = 20) {
        let deadline = Date().addingTimeInterval(timeout)
        var swipes = 0
        while Date() < deadline {
            // The floating tab bar overlays scroll content; XCUI can report a row under it as
            // hittable, and the tap then lands on a tab. Require the row to clear the bar.
            let tabBar = app.buttons["tab.today"]
            let clearsTabBar = !tabBar.exists || element.frame.maxY < tabBar.frame.minY - 8
            if element.exists && element.isHittable && clearsTabBar {
                element.tap()
                return
            }
            if scrollIfNeeded && element.exists && swipes < 6 && app.buttons["tab.today"].isHittable {
                app.swipeUp()
                swipes += 1
            } else {
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        XCTFail("Element never became hittable: \(element)")
    }

    private func assertVisibleText(_ text: String, timeout: TimeInterval = 5) {
        let exact = app.staticTexts[text]
        if exact.waitForExistence(timeout: timeout) {
            return
        }

        let contains = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        XCTAssertTrue(contains.waitForExistence(timeout: 1), "Expected visible text containing: \(text)")
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Since WP-L removed the launch splash, the first screen is still settling when a test
    /// starts: wait for the element, let each swipe's scroll come to rest, then wait for it to
    /// become hittable instead of reading `isHittable` once.
    private func scrollToElement(_ element: XCUIElement, maxSwipes: Int = 10) {
        _ = element.waitForExistence(timeout: 8)
        var swipes = 0
        while !(waitUntilHittable(element, timeout: 1) && clearsTabBar(element)) && swipes < maxSwipes {
            // Scroll toward the element: it can sit above the fold when a tab keeps its old
            // scroll offset after the content above it shrank.
            // Short, slow drags (about a third of the screen) so the target can't jump from under
            // the floating tab bar to above the fold in one swipe.
            let up = !(element.exists && element.frame.maxY < app.windows.firstMatch.frame.midY)
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.62 : 0.32))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.32 : 0.62))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
            swipes += 1
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 2))
        XCTAssertTrue(waitUntilHittable(element, timeout: 4), "Not hittable after scrolling: \(element)")
    }

    /// The floating tab bar overlays content: a row under it reports hittable but a tap hits a tab.
    private func clearsTabBar(_ element: XCUIElement) -> Bool {
        let tabBar = app.buttons["tab.today"]
        return !tabBar.exists || element.frame.maxY < tabBar.frame.minY - 8
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND isHittable == true"), object: element)
        return XCTWaiter().wait(for: [hittable], timeout: timeout) == .completed
    }

    private func scrollToText(_ text: String, timeout: TimeInterval = 5, maxSwipes: Int = 8) {
        let predicate = NSPredicate(format: "label == %@", text)
        let element = app.staticTexts.matching(predicate).firstMatch
        var swipes = 0
        while (!element.exists || !element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Expected visible text: \(text)")
        XCTAssertTrue(element.isHittable, "Expected hittable text: \(text)")
    }

    private func waitAndTap(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        let hittable = NSPredicate(format: "isHittable == true")
        expectation(for: hittable, evaluatedWith: element)
        waitForExpectations(timeout: timeout)
        element.tap()
    }
}
