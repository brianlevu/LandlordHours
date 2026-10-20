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
        XCTAssertTrue(app.staticTexts["What are you building toward?"].waitForExistence(timeout: 8))
        let goalCTA = app.buttons["onb-primary"]
        XCTAssertFalse(goalCTA.isEnabled, "The goal button waits for a choice")
        waitAndTap(app.buttons["goal-mp"])
        XCTAssertTrue(app.buttons["goal-mp100"].waitForExistence(timeout: 3), "500 or 100 reveals its two chips")
        XCTAssertEqual(goalCTA.label, "Build toward 500h")
        waitAndTap(goalCTA)
        waitAndTap(app.buttons["onb-link"])                    // Calendar: Not now
        waitAndTap(app.buttons["who-both"])
        XCTAssertTrue(app.descendants(matching: .any)["who-note"].waitForExistence(timeout: 3))
        waitAndTap(app.buttons["onb-primary"])

        let save = app.buttons["onb-primary"]
        XCTAssertTrue(app.staticTexts["Name your first rental."].waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "Save waits for a name")
        XCTAssertFalse(app.textFields["property-address"].exists, "Address folded away")
        let nameField = app.textFields["property-name"]
        nameField.tap()
        nameField.typeText("Oak Street Duplex")
        XCTAssertTrue(save.isEnabled)
        waitAndTap(app.buttons["property-add-address"])
        XCTAssertTrue(app.textFields["property-address"].waitForExistence(timeout: 3))
    }

    func testTrackManualDetailsFlowIsReachable() {
        launch(scenario: "frequent", tab: 2)

        XCTAssertTrue(app.staticTexts["Log your time"].waitForExistence(timeout: 8))
        let manualButton = app.buttons["Set details manually, Property, category, hours"]
        XCTAssertTrue(manualButton.waitForExistence(timeout: 5))
        manualButton.tap()

        XCTAssertTrue(app.staticTexts["Set details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Category"].exists)
        XCTAssertTrue(app.staticTexts["Property"].exists)
        XCTAssertTrue(app.staticTexts["Hours"].exists)
    }

    func testTrackNoteTypingStaysInComposer() {
        launch(scenario: "occasional", tab: 2)

        XCTAssertTrue(app.staticTexts["Log your time"].waitForExistence(timeout: 8))
        let noteEditor = app.textViews.firstMatch
        XCTAssertTrue(noteEditor.waitForExistence(timeout: 5))

        noteEditor.tap()
        noteEditor.typeText("painted porch for 1 hour")

        XCTAssertFalse(app.staticTexts["Top Hit"].exists)
        XCTAssertTrue(noteEditor.value as? String == "painted porch for 1 hour")
        XCTAssertTrue(app.staticTexts["Evidence draft"].waitForExistence(timeout: 5))
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
        _ = app.buttons["settings.proCard"].waitForExistence(timeout: 5)
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
            ("emptyMainTabs", 1, "Create the property record", "empty-properties"),
            ("emptyMainTabs", 2, "Add a property first", "empty-track"),
            ("emptyMainTabs", 3, "Reports", "empty-reports"),
            ("emptyMainTabs", 4, "Upgrade to Pro", "empty-settings"),
            ("occasional", 0, "Today’s work", "occasional-home"),
            ("occasional", 1, "Portfolio evidence", "occasional-properties"),
            ("occasional", 2, "Log your time", "occasional-track"),
            ("occasional", 3, "Reports", "occasional-reports"),
            ("occasional", 4, "Settings", "occasional-settings"),
            ("frequent", 0, "counted toward 750 hours", "frequent-home"),
            ("frequent", 1, "Portfolio evidence", "frequent-properties"),
            ("frequent", 2, "Log your time", "frequent-track"),
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

        assertVisibleText("Add a property first", timeout: 8)
        assertVisibleText("Why this comes first")

        let addProperty = app.buttons["Add first property"]
        XCTAssertTrue(addProperty.waitForExistence(timeout: 5))
        addProperty.tap()

        let propertyName = app.textFields["property.name"]
        XCTAssertTrue(propertyName.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["property.address"].exists)
        attachScreenshot(named: "track-empty-add-property-route")
    }

    func testTimerLaunchStatesRemainReviewable() {
        launch(scenario: "frequent", tab: 2, extraArguments: ["-LHInitialTrackMode", "timer"])

        assertVisibleText("Timer")
        XCTAssertTrue(app.buttons["track.timer.start"].waitForExistence(timeout: 5))
        attachScreenshot(named: "timer-idle-state")

        app.terminate()
        launch(scenario: "frequent", tab: 2, extraArguments: ["-LHInitialTrackMode", "timer", "-LHStartTimer"])
        XCTAssertTrue(app.buttons["track.timer.stop"].waitForExistence(timeout: 8))
        assertVisibleText("Evidence in progress")
        attachScreenshot(named: "timer-running-state")

        app.terminate()
        launch(scenario: "frequent", tab: 2, extraArguments: ["-LHInitialTrackMode", "timer", "-LHShowTimerReview"])
        XCTAssertTrue(app.buttons["track.timer.save"].waitForExistence(timeout: 8))
        assertVisibleText("Notes")
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

        XCTAssertTrue(app.staticTexts["Log your time"].waitForExistence(timeout: 5))
        let noteEditor = app.textViews["track.entryNotes"]
        XCTAssertTrue(noteEditor.waitForExistence(timeout: 5))
        noteEditor.tap()
        noteEditor.typeText("Reviewed tenant message for 1 hour")

        let logTime = app.buttons["track.logTime"]
        if !logTime.waitForExistence(timeout: 6) {
            let reviewButton = app.buttons["track.reviewEvidence"]
            XCTAssertTrue(reviewButton.waitForExistence(timeout: 2))
            reviewButton.tap()
        }
        XCTAssertTrue(logTime.waitForExistence(timeout: 5))
        XCTAssertTrue(logTime.isEnabled)
        logTime.tap()

        XCTAssertTrue(app.staticTexts["Time logged"].waitForExistence(timeout: 5))

        app.buttons["tab.today"].tap()
        XCTAssertFalse(app.staticTexts["Finish your tax-ready setup"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["home.activation.firstHour"].exists)
    }

    func testAttachmentPhotoSurvivesForceQuitAndRelaunch() {
        // Launch 1: seed an entry that carries a real, file-backed attachment.
        launch(scenario: "occasional", tab: 0, extraArguments: ["-LHSeedAttachment"])

        // Recent Activity sits below the fold on the redesigned Home, and the splash
        // can still be fading: scroll until the row is hittable before tapping.
        let entryRow = app.staticTexts["Property Management"]
        XCTAssertTrue(entryRow.waitForExistence(timeout: 20))
        tapWhenHittable(entryRow, scrollIfNeeded: true)

        XCTAssertTrue(app.staticTexts["Attachments (1)"].waitForExistence(timeout: 6),
                      "Seeded attachment should render before relaunch")
        attachScreenshot(named: "attachment-before-relaunch")

        // Force-quit and relaunch WITHOUT reseeding: the entry and its photo must
        // load from disk (the user stays signed in via the persisted scope keys).
        app.terminate()
        app.launchArguments = [
            "-LHInitialTab", "0",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        let entryRowAgain = app.staticTexts["Property Management"]
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

    private func scrollToElement(_ element: XCUIElement, maxSwipes: Int = 6) {
        var swipes = 0
        while (!element.exists || !element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.waitForExistence(timeout: 2))
        XCTAssertTrue(element.isHittable)
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
