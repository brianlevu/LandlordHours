import XCTest

final class LandlordHoursUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testFirstRunPropertySetupCTARequiresNameAndAddressForSaveCopy() {
        launch(scenario: "firstTime", tab: 0)

        let goalTitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "main goal")).firstMatch
        XCTAssertTrue(goalTitle.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["750h + 50% rule"].exists)
        XCTAssertTrue(app.staticTexts["100h STR test"].exists)
        XCTAssertTrue(app.staticTexts["Records first"].exists)
        XCTAssertTrue(app.staticTexts["Guided setup"].exists)
        waitAndTap(app.buttons["onboarding.goalPrimaryCTA"])

        let propertyTitle = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Add your first")).firstMatch
        XCTAssertTrue(propertyTitle.waitForExistence(timeout: 5))
        let propertyCTA = app.buttons["onboarding.propertyPrimaryCTA"]
        XCTAssertTrue(propertyCTA.waitForExistence(timeout: 3))
        XCTAssertTrue(propertyCTA.label.contains("Continue without property"))

        let nameField = app.textFields["onboarding.propertyName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Oak Street Duplex")
        XCTAssertTrue(propertyCTA.label.contains("Continue without property"))

        let addressField = app.textFields["onboarding.streetAddress"]
        XCTAssertTrue(addressField.waitForExistence(timeout: 3))
        addressField.tap()
        addressField.typeText("123 Main Street")
        XCTAssertTrue(propertyCTA.label.contains("Save property"))
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
        app.buttons["Export report"].tap()

        let generateButton = app.buttons["export.generatePDF"]
        assertVisibleText("Export report", timeout: 5)
        scrollToElement(generateButton)
        generateButton.tap()

        XCTAssertTrue(app.staticTexts["PDF ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["export.sharePDF"].exists)
    }

    func testSettingsSecondaryFlowsOpenWithoutSwitchingTabs() {
        launch(scenario: "frequent", tab: 4)

        assertVisibleText("Settings", timeout: 12)
        let taxProfile = app.buttons["settings.taxProfile"]
        XCTAssertTrue(taxProfile.waitForExistence(timeout: 5))
        taxProfile.tap()

        XCTAssertTrue(app.staticTexts["Tax profile"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Track"].isHittable)
    }

    func testAppearancePreferenceShowsSavedStateAndPersists() {
        launch(scenario: "emptyMainTabs", tab: 0)
        _ = app.staticTexts.firstMatch.waitForExistence(timeout: 8)
        app.terminate()

        launch(scenario: "frequent", tab: 4)

        assertVisibleText("Settings", timeout: 12)
        scrollToElement(app.buttons["Dark appearance"])
        app.buttons["Dark appearance"].tap()

        XCTAssertTrue(app.staticTexts["Saved - dark mode"].waitForExistence(timeout: 5))

        app.terminate()
        launch(scenario: "frequent", tab: 4)

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 8))
        scrollToElement(app.staticTexts["Saved - dark mode"])
        XCTAssertTrue(app.staticTexts["Saved - dark mode"].exists)
    }

    func testMainTabVisualSmokeMatrix() {
        let matrix: [(scenario: String, tab: Int, expectedText: String, attachment: String)] = [
            ("emptyMainTabs", 0, "Add your first property", "empty-home"),
            ("emptyMainTabs", 1, "Create the property record", "empty-properties"),
            ("emptyMainTabs", 2, "Add a property first", "empty-track"),
            ("emptyMainTabs", 3, "Reports", "empty-reports"),
            ("emptyMainTabs", 4, "Upgrade to Pro", "empty-settings"),
            ("occasional", 0, "Today's work", "occasional-home"),
            ("occasional", 1, "Portfolio evidence", "occasional-properties"),
            ("occasional", 2, "Log your time", "occasional-track"),
            ("occasional", 3, "Reports", "occasional-reports"),
            ("occasional", 4, "Settings", "occasional-settings"),
            ("frequent", 0, "750 hour target", "frequent-home"),
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

        XCTAssertTrue(app.staticTexts["Finish your tax-ready setup"].waitForExistence(timeout: 8))

        let propertyTile = app.buttons["home.activation.property"]
        XCTAssertTrue(propertyTile.waitForExistence(timeout: 5))
        propertyTile.tap()

        let propertyName = app.textFields["property.name"]
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

        app.buttons["Home"].tap()
        let firstHourTile = app.buttons["home.activation.firstHour"]
        XCTAssertTrue(firstHourTile.waitForExistence(timeout: 5))
        firstHourTile.tap()

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

        app.buttons["Home"].tap()
        XCTAssertFalse(app.staticTexts["Finish your tax-ready setup"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["home.activation.firstHour"].exists)
    }

    private func launch(scenario: String, tab: Int, extraArguments: [String] = []) {
        app.terminate()
        app.launchArguments = [
            "-LHMockScenario", scenario,
            "-LHInitialTab", "\(tab)",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ] + extraArguments
        app.launch()
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
