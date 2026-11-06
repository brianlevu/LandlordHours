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

    /// The header sits in the centred column: the screen title's leading edge is the column inset plus the
    /// 20 gutter. The title is the tallest text with the tab's name (the tab bar carries a smaller copy).
    private func assertTitleInColumn(_ title: String, _ label: String, afterBack: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        let matches = app.staticTexts.matching(identifier: title)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 10), "\(label): title", file: file, line: line)
        let screenTitle = matches.allElementsBoundByIndex.max { $0.frame.height < $1.frame.height }!
        let window = app.windows.firstMatch.frame
        let inset = max(0, ((window.width - 672) / 2).rounded(.down))
        // A back button (44, pulled 8 into the gutter, then 8 of spacing) leads the title by 44.
        XCTAssertEqual(screenTitle.frame.minX, inset + 20 + (afterBack ? 44 : 0), accuracy: 1.5, "\(label): title leading edge", file: file, line: line)
        XCTAssertLessThanOrEqual(screenTitle.frame.maxX, window.width - inset - 20 + 1.5, "\(label): title within the column",
                                 file: file, line: line)
    }

    func testTabHeadersSitInTheCentredColumnInBothOrientations() throws {
        try requireIPad()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            for (tab, name) in [(0, "Today"), (5, "Inbox"), (6, "Records"), (1, "Rentals"), (4, "Settings")] {
                launch(tab: tab)
                assertTitleInColumn(name, "\(name) \(orientation == .portrait ? "portrait" : "landscape")", afterBack: name == "Settings")
                app.terminate()
            }
        }
    }

    /// §1.27 IP4: Today's hero side is H1's share of the scene height under the 200pt header allowance,
    /// clamped 290…480 (13" portrait 480, 11" portrait 450, 13" landscape 371, 11" landscape 290).
    func testTodayHeroScalesWithTheWindowHeight() throws {
        try requireIPad()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            launch(tab: 0)
            let hero = app.descendants(matching: .any)["today.hero"].firstMatch
            XCTAssertTrue(hero.waitForExistence(timeout: 15))
            sleep(2)
            let window = app.windows.firstMatch.frame
            let expected = min(480, max(290, (0.446 * (window.height - 200)).rounded()))
            XCTAssertEqual(hero.frame.height, expected, accuracy: 1,
                           "hero side at \(Int(window.width))×\(Int(window.height))")
            app.terminate()
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
