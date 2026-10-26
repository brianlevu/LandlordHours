import XCTest

/// Package J (§1.27): the two-pane layout on a real iPad, and the frames for the gate.
///
/// `testRightPaneBarTwoPane` is must-prove 12 on the OS it runs on: the right pane's hosted
/// `TabView` draws the system's compact bottom bar at the right pane's foot, with five items and
/// the Inbox badge, no sidebar toggle, and "Log time" opens in the pane and restores the tab, in
/// portrait and landscape. It skips in a window under 800 × 645 (compact). The capture tests write
/// screenshots as kept attachments (`xcresulttool export attachments`).
final class AdaptiveUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private func launch(_ extra: [String] = [], select: Int = 3) {
        app = XCUIApplication()
        app.launchArguments = [UITestIsolation.resetProfilesArgument, "-LHMockScenario", "emptyMainTabs",
                               "-LHSeedSuggestions", "inbox", "-LHCraftSeed", "craft", "-LHCraftWindows", "lit",
                               "-LHAdaptiveSelect", "\(select)", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
    }

    private func isTwoPane() -> Bool {
        app.descendants(matching: .any)["pane.house"].waitForExistence(timeout: 10)
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func assertBarInRightPane(_ label: String) {
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "\(label): no tab bar")
        for item in ["Today", "Inbox", "Records", "Rentals", "Log time"] {
            XCTAssertTrue(bar.buttons[item].exists, "\(label): missing tab \(item)")
        }
        let window = app.windows.firstMatch.frame
        let house = app.descendants(matching: .any)["pane.house"].frame
        XCTAssertGreaterThanOrEqual(bar.frame.minX, house.maxX, "\(label): the bar must sit in the right pane, not over the house")
        XCTAssertGreaterThan(bar.frame.minY, window.height * 0.75, "\(label): the bar must sit at the pane's foot")
        XCTAssertFalse(app.buttons["ToggleSidebar"].exists, "\(label): .tabBarOnly shows no sidebar toggle")
        XCTAssertFalse(app.buttons["Show Sidebar"].exists, "\(label): .tabBarOnly shows no sidebar toggle")
    }

    func testRightPaneBarTwoPane() throws {
        launch()
        guard isTwoPane() else { throw XCTSkip("compact window: no right pane here") }
        assertBarInRightPane("portrait")
        let bar = app.tabBars.firstMatch
        let inbox = bar.buttons["Inbox"]
        XCTAssertTrue((inbox.value as? String)?.isEmpty == false || inbox.label.contains("8"), "Inbox badge missing: \(inbox.label) \(String(describing: inbox.value))")
        attach("mp12-portrait-bar")

        // Log time opens in the pane and the selected tab stays.
        bar.buttons["Records"].tap()
        XCTAssertTrue(bar.buttons["Records"].isSelected)
        bar.buttons["Log time"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pane.logTime"].waitForExistence(timeout: 5), "Log time did not open in the pane")
        XCTAssertTrue(app.descendants(matching: .any)["pane.house"].exists, "the house pane must stay beside Log time")
        XCTAssertTrue(bar.buttons["Records"].isSelected, "Log time must restore the previous tab")
        attach("mp12-portrait-logtime")

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCTAssertTrue(isTwoPane(), "landscape must stay two-pane")
        assertBarInRightPane("landscape")
        attach("mp12-landscape-bar")
    }

    func testShelfFiltersTodayOnly() throws {
        launch(select: 0)
        guard isTwoPane() else { throw XCTSkip("compact window") }
        let count = app.descendants(matching: .any)["pane.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["pane.filter"].exists, "All rentals shows no filter chip")
        let pine = app.buttons["shelf.Pine Cabin"]
        // The shelf scrolls inside the house pane: a slot past the pane's edge still reports
        // hittable (the scroll view does not clip it for accessibility), so check the frame.
        let shelf = app.descendants(matching: .any)["house.shelf"]
        for _ in 0..<3 where pine.frame.maxX > shelf.frame.maxX + 1 { shelf.swipeLeft(); sleep(1) }
        XCTAssertLessThanOrEqual(pine.frame.maxX, shelf.frame.maxX + 1, "Pine Cabin scrolls into the shelf")
        pine.tap()
        XCTAssertTrue(app.descendants(matching: .any)["pane.filter"].waitForExistence(timeout: 5), "picking a rental filters To confirm")
        app.descendants(matching: .any)["pane.filter"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["pane.filter"].waitForExistence(timeout: 2), "clearing the chip shows every rental")
    }

    // MARK: Captures (the gate's frames on the real iPad; run with -only-testing)

    private static let sizes: [(String, String)] = [("L", "UICTContentSizeCategoryL"), ("XXL", "UICTContentSizeCategoryXXL"),
                                                    ("AX3", "UICTContentSizeCategoryAccessibilityXXXL")]

    private func captureSet(orientation: UIDeviceOrientation, tag: String) {
        for theme in ["light", "dark"] {
            for (size, category) in Self.sizes {
                for (state, select, route) in [("3rentals", 3, ""), ("allrentals", 0, ""), ("detail", 3, "detail"), ("logtime", 3, "log")] {
                    if size != "L" && (state == "detail" || state == "logtime") { continue }
                    var extra = ["-LHColorScheme", theme, "-UIPreferredContentSizeCategoryName", category]
                    if !route.isEmpty { extra += ["-LHAdaptiveRoute", route] }
                    launch(extra, select: select)
                    XCUIDevice.shared.orientation = orientation
                    _ = isTwoPane()
                    sleep(route.isEmpty ? 3 : 4)
                    attach("ipad-\(tag)-\(state)-\(theme)-\(size)")
                }
            }
        }
    }

    func testCapturePortrait() { captureSet(orientation: .portrait, tag: "portrait") }
    func testCaptureLandscape() { captureSet(orientation: .landscapeLeft, tag: "landscape") }
}
