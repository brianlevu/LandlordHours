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
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        generateButton.tap()

        XCTAssertTrue(app.staticTexts["PDF ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["export.sharePDF"].exists)
    }

    func testSettingsSecondaryFlowsOpenWithoutSwitchingTabs() {
        launch(scenario: "frequent", tab: 4)

        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 8))
        let taxProfile = app.buttons["settings.taxProfile"]
        XCTAssertTrue(taxProfile.waitForExistence(timeout: 5))
        taxProfile.tap()

        XCTAssertTrue(app.staticTexts["Tax profile"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Track"].isHittable)
    }

    private func launch(scenario: String, tab: Int) {
        app.launchArguments = [
            "-LHMockScenario", scenario,
            "-LHInitialTab", "\(tab)",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
    }

    private func waitAndTap(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        let hittable = NSPredicate(format: "isHittable == true")
        expectation(for: hittable, evaluatedWith: element)
        waitForExpectations(timeout: timeout)
        element.tap()
    }
}
