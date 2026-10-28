import XCTest

/// The band-B content column (standard §1.27 interim, 2026-10-27): on a window at least 600 wide the
/// scaffold puts every tab's header and content in one centred 672pt column, in portrait and landscape.
/// iPad only; skipped on iPhone, where band A is unchanged.
final class IPadColumnUITests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDown() {
        // A capture run (`testOrientDeviceForCapture`) leaves the orientation it set.
        if ProcessInfo.processInfo.environment["LH_ORIENT"]?.isEmpty ?? true {
            XCUIDevice.shared.orientation = .portrait
        }
        super.tearDown()
    }

    private func launch(tab: Int) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [UITestIsolation.resetProfilesArgument, "-LHMockScenario", "emptyMainTabs",
                               "-LHPropertiesSeed", "layouts3", "-LHPropertiesGoal", "mp100", "-LHGoalChoice", "mp100",
                               "-LHSeedSuggestions", "inbox", "-LHFakeZone", "empty", "-LHInitialTab", "\(tab)",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    private func requireIPad() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("band B needs an iPad-width window") }
    }

    /// The header sits in the centred column: its text edge is the column inset plus the 20 gutter.
    private func assertHeaderInColumn(_ tab: String, file: StaticString = #filePath, line: UInt = #line) {
        let header = app.otherElements["screen.header"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10), "\(tab): header", file: file, line: line)
        let window = app.windows.firstMatch.frame
        let frame = header.frame
        let inset = max(0, ((window.width - 672) / 2).rounded(.down))
        XCTAssertEqual(frame.minX, inset + 20, accuracy: 1.5, "\(tab): header leading edge", file: file, line: line)
        XCTAssertEqual(frame.midX, window.midX, accuracy: 1.5, "\(tab): header centred", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.width, 632 + 1, "\(tab): header within the column", file: file, line: line)
    }

    func testTabHeadersSitInTheCentredColumnInBothOrientations() throws {
        try requireIPad()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            for (tab, name) in [(0, "Today"), (5, "Inbox"), (6, "Records"), (1, "Rentals"), (4, "Settings")] {
                launch(tab: tab)
                assertHeaderInColumn("\(name) \(orientation == .portrait ? "portrait" : "landscape")")
                app.terminate()
            }
        }
    }

    func testInboxRowsSitInTheColumn() throws {
        try requireIPad()
        launch(tab: 5)
        let cell = app.cells.element(boundBy: 1)
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        let window = app.windows.firstMatch.frame
        let inset = max(0, ((window.width - 672) / 2).rounded(.down))
        XCTAssertGreaterThanOrEqual(cell.frame.minX, inset + 20 - 1, "rows start at the column's gutter")
        XCTAssertLessThanOrEqual(cell.frame.maxX, window.width - inset - 20 + 1, "rows end at the column's gutter")
    }

    /// Capture helper, not a check: leaves the simulator in the orientation named by
    /// `TEST_RUNNER_LH_ORIENT` (`portrait` or `landscape`) for a `simctl` capture run. Skipped otherwise.
    func testOrientDeviceForCapture() throws {
        guard let want = ProcessInfo.processInfo.environment["LH_ORIENT"], !want.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_LH_ORIENT to use")
        }
        XCUIDevice.shared.orientation = want == "landscape" ? .landscapeLeft : .portrait
    }
}
