import XCTest

/// Classifier v2 property fields, now in the 2.0 Edit property sheet: "Other names" chips and
/// the "I live here" toggle. Always asserts the flow; also writes frames for the visual gate when the runner gets
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
    /// Accessibility Dynamic Type AX3 (UICTContentSizeCategoryAccessibilityXL) with 3 aliases.
    func testAliasesAtAccessibilitySizeLight() { runLargeType(scheme: "light") }
    func testAliasesAtAccessibilitySizeDark() { runLargeType(scheme: "dark") }

    private func launch(scheme: String, extra: [String] = []) {
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "occasional",
            "-LHInitialTab", "1",
            "-LHOpenFirstPropertyEdit",
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ] + extra
        app.launch()
    }

    private func run(scheme: String) {
        launch(scheme: scheme)

        let field = app.textFields["property.alias.field"]
        let toggle = app.switches["property.ownerOccupied"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15), "Edit property should open")
        bringIntoView(field)
        XCTAssertTrue(toggle.isHittable, "toggle and alias card share the frame")
        XCTAssertEqual(toggle.value as? String, "0", "I live here starts off")
        XCTAssertFalse(app.buttons["Remove Lake House"].exists)
        capture("\(scheme)-1-livehere-off-aliases-empty")

        // Under 3 characters: explained, and Add stays off.
        field.tap()
        field.typeText("ab")
        XCTAssertTrue(app.staticTexts["property.alias.hint"].waitForExistence(timeout: 3), "short-name hint")
        XCTAssertFalse(app.buttons["property.alias.add"].isEnabled)
        capture("\(scheme)-2-alias-too-short")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        XCTAssertFalse(app.staticTexts["property.alias.hint"].exists)

        // A valid name: Add turns on.
        field.typeText("Lake House")
        XCTAssertTrue(app.buttons["property.alias.add"].isEnabled, "Add is enabled for a valid name")
        XCTAssertFalse(app.staticTexts["property.alias.hint"].exists)
        capture("\(scheme)-3-add-enabled")
        field.typeText("\n")
        if app.keyboards.count > 0 { dismissKeyboard() }

        for alias in ["Sunny Loft listing", "Ridgeline Plumbing"] { add(alias, field: field) }
        for alias in ["Lake House", "Sunny Loft listing", "Ridgeline Plumbing"] {
            XCTAssertTrue(app.buttons["Remove \(alias)"].waitForExistence(timeout: 3), "chip for \(alias)")
        }
        bringIntoView(field)
        capture("\(scheme)-4-aliases-three")

        add(longAlias, field: field)
        XCTAssertTrue(app.buttons["Remove \(longAlias)"].waitForExistence(timeout: 3))
        bringIntoView(field)
        capture("\(scheme)-5-aliases-long")

        // Duplicates (any case) are not added twice.
        add("lake house", field: field)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Remove Lake House")).count, 1)

        bringIntoView(toggle)
        toggle.tap()
        if toggle.value as? String != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, "1", "I live here turns on")
        capture("\(scheme)-6-livehere-on")

        let save = app.buttons["property.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "Saved")

        // Saved aliases and "I live here" show on the detail page.
        app.buttons["properties.row.0"].tap()
        let details = app.descendants(matching: .any)["property.details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        bringIntoView(details)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Ridgeline Plumbing")).firstMatch.waitForExistence(timeout: 3), "aliases saved")
    }

    private func runLargeType(scheme: String) {
        launch(scheme: scheme, extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        let field = app.textFields["property.alias.field"]
        let toggle = app.switches["property.ownerOccupied"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15), "Edit property should open")
        bringIntoView(toggle)
        capture("\(scheme)-7-ax3-livehere-off")
        let names = ["Lake House", "Sunny Loft listing", "Ridgeline Plumbing"]
        for alias in names { add(alias, field: field) }
        for alias in names {
            XCTAssertTrue(app.buttons["Remove \(alias)"].waitForExistence(timeout: 3), "chip for \(alias)")
        }
        let chip = app.buttons["Remove Lake House"]
        bringIntoView(chip)
        capture("\(scheme)-8-ax3-aliases-three")
        // The field itself, being typed in (a 2-letter name shows the hint).
        bringIntoView(field)
        field.tap()
        field.typeText("Ri")
        XCTAssertTrue(app.staticTexts["property.alias.hint"].waitForExistence(timeout: 3), "hint at AX3")
        capture("\(scheme)-9-ax3-alias-field")
    }

    private func add(_ alias: String, field: XCUIElement) {
        bringIntoView(field)
        field.tap()
        field.typeText(alias + "\n")
        if app.keyboards.count > 0 {
            dismissKeyboard()
        }
    }

    private func dismissKeyboard() {
        if app.keyboards.count > 0 {
            let done = app.keyboards.buttons["done"]
            if done.exists { done.tap() } else { app.staticTexts["Edit property"].tap() }
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
