import XCTest

/// Classifier v2 property screen: "Other names for this property" chips and the "I live here"
/// toggle. Always asserts the flow; also writes frames for the visual gate when the runner gets
/// `LH_CAPTURE_DIR` (pass `TEST_RUNNER_LH_CAPTURE_DIR=<dir>` to xcodebuild).
final class PropertyAliasUITests: XCTestCase {
    private var app: XCUIApplication!
    private let longAlias = "Bright Corner Studio with Garden View near the Lake and Downtown Shops"

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

    func testAliasesAndLivesHereLight() { run(scheme: "light") }
    func testAliasesAndLivesHereDark() { run(scheme: "dark") }

    private func run(scheme: String) {
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "occasional",
            "-LHInitialTab", "1",
            "-LHOpenFirstPropertyDetail",
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        let field = app.textFields["property.alias.field"]
        let toggle = app.switches["property.ownerOccupied"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15), "Property detail should open")
        bringIntoView(toggle)
        XCTAssertEqual(toggle.value as? String, "0", "I live here starts off")
        capture("\(scheme)-1-livehere-off")

        bringIntoView(field)
        XCTAssertFalse(app.buttons["Remove Lake House"].exists)
        capture("\(scheme)-2-aliases-empty")

        // Under 3 characters: explained, and Add stays off.
        bringIntoView(field)
        field.tap()
        field.typeText("ab")
        XCTAssertTrue(app.staticTexts["property.alias.hint"].waitForExistence(timeout: 3), "short-name hint")
        XCTAssertFalse(app.buttons["property.alias.add"].isEnabled)
        capture("\(scheme)-2b-alias-too-short")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        XCTAssertFalse(app.staticTexts["property.alias.hint"].exists)

        for alias in ["Lake House", "Sunny Loft listing", "Ridgeline Plumbing"] { add(alias, field: field) }
        for alias in ["Lake House", "Sunny Loft listing", "Ridgeline Plumbing"] {
            XCTAssertTrue(app.buttons["Remove \(alias)"].waitForExistence(timeout: 3), "chip for \(alias)")
        }
        bringIntoView(field)
        capture("\(scheme)-3-aliases-three")

        add(longAlias, field: field)
        XCTAssertTrue(app.buttons["Remove \(longAlias)"].waitForExistence(timeout: 3))
        bringIntoView(field)
        capture("\(scheme)-4-aliases-long")

        // Duplicates (any case) are not added twice.
        add("lake house", field: field)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Remove Lake House")).count, 1)

        bringIntoView(toggle)
        toggle.tap()
        if toggle.value as? String != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, "1", "I live here turns on")
        capture("\(scheme)-5-livehere-on")

        let save = app.buttons["Save changes"]
        bringIntoView(save)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "Saved")
    }

    private func add(_ alias: String, field: XCUIElement) {
        bringIntoView(field)
        field.tap()
        field.typeText(alias + "\n")
        if app.keyboards.count > 0 {
            app.staticTexts["Other names for this property"].tap()
        }
    }

    private func bringIntoView(_ element: XCUIElement) {
        let scroll = app.scrollViews.firstMatch
        var tries = 0
        while tries < 8 {
            let frame = element.frame
            let screen = app.windows.firstMatch.frame
            if element.exists, element.isHittable, frame.minY > screen.minY + 120, frame.maxY < screen.maxY - 180 { return }
            if element.exists, frame.minY <= screen.minY + 120 {
                scroll.swipeDown(velocity: .slow)
            } else {
                scroll.swipeUp(velocity: .slow)
            }
            tries += 1
        }
    }

    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["LH_CAPTURE_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
