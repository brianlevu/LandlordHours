import XCTest

/// Package A: the native tab shell (standard §1.25, §H.7). Five tabs; the fifth reads "Log time"
/// to VoiceOver (not "Search"), opens the Log time sheet, and never becomes the selected tab.
final class ShellTabUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [UITestIsolation.resetProfilesArgument, "-LHMockScenario", "frequent", "-LHInitialTab", "0",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testFiveTabsAndLogTimeLabel() {
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        for label in ["Today", "Inbox", "Records", "Rentals", "Log time"] {
            XCTAssertTrue(bar.buttons[label].exists, "missing tab \(label)")
        }
        XCTAssertFalse(bar.buttons["Search"].exists, "the fifth tab must not read as Search")
        XCTAssertTrue(bar.buttons["Today"].isSelected)
    }

    func testLogTimeOpensSheetAndKeepsTheTab() {
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        bar.buttons["Records"].tap()
        XCTAssertTrue(bar.buttons["Records"].isSelected)
        bar.buttons["Log time"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["log.sheet"].waitForExistence(timeout: 5), "Log time sheet did not open")
        XCTAssertFalse(bar.buttons["Log time"].isSelected)
        XCTAssertTrue(bar.buttons["Records"].isSelected, "selecting Log time must restore the previous tab")
    }
}
