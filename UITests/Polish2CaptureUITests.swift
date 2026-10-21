import XCTest

/// Polish pass 2 captures (Settings disabled row, Today setup card and hero subtitle, property edit
/// bottom): light/dark at the default size, XXL and AX3. Runs only when `LH_CAPTURE_DIR` is set.
final class Polish2CaptureUITests: XCTestCase {
    private var app: XCUIApplication!
    private var dir: String { ProcessInfo.processInfo.environment["LH_CAPTURE_DIR"] ?? "" }

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(dir.isEmpty, "Captures only (set LH_CAPTURE_DIR)")
        UITestIsolation.resetStoreKit()
        continueAfterFailure = true
        app = XCUIApplication()
    }

    private let sizes: [(String, String?)] = [("", nil), ("-xxl", "UICTContentSizeCategoryXXL"), ("-ax3", "UICTContentSizeCategoryAccessibilityXL")]

    private func each(_ body: (String, String, [String]) -> Void) {
        for scheme in ["light", "dark"] {
            for (suffix, category) in sizes {
                app.terminate()
                var extra: [String] = []
                if let category { extra = ["-UIPreferredContentSizeCategoryName", category] }
                body(scheme, suffix, extra)
            }
        }
    }

    private func launch(_ scheme: String, tab: Int, _ args: [String]) {
        app.launchArguments = [UITestIsolation.resetProfilesArgument, "-LHNoSwipePeek", "-LHInitialTab", "\(tab)",
                               "-LHColorScheme", scheme, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + args
        app.launch()
    }

    private func write(_ name: String) {
        Thread.sleep(forTimeInterval: 1.2)
        let shot = app.screenshot()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testSettingsDisabledRow() {
        each { scheme, suffix, extra in
            launch(scheme, tab: 4, ["-LHMockScenario", "emptyMainTabs"] + extra)
            let row = app.descendants(matching: .any)["settings.capture.prompts"].firstMatch
            XCTAssertTrue(app.descendants(matching: .any)["settings.profile"].waitForExistence(timeout: 25))
            var n = 0
            let screenH = app.frame.height
            while !(row.exists && row.isHittable && row.frame.maxY < screenH - 240 && row.frame.minY > 160) && n < 24 { app.swipeUp(velocity: .slow); n += 1 }
            write("settings-calendar-off-\(scheme)\(suffix)")
        }
    }

    func testTodaySetupAndHero() {
        each { scheme, suffix, extra in
            let args = ["-LHMockScenario", "emptyMainTabs", "-LHTodayHours", "0", "-LHSeedSuggestions", "empty"] + extra
            launch(scheme, tab: 0, args)
            XCTAssertTrue(app.descendants(matching: .any)["today.hero"].waitForExistence(timeout: 25))
            write("today-setup-top-\(scheme)\(suffix)")
            app.terminate()
            launch(scheme, tab: 0, args + ["-LHTodayScrollTo", "setup"])
            XCTAssertTrue(app.descendants(matching: .any)["home.activation.learn"].waitForExistence(timeout: 25))
            Thread.sleep(forTimeInterval: 1.5)
            write("today-setup-card-\(scheme)\(suffix)")
            for _ in 0..<12 { app.swipeUp() }
            write("today-setup-bottom-\(scheme)\(suffix)")
        }
    }

    func testTodaySetupCardOnly() {
        each { scheme, suffix, extra in
            let args = ["-LHMockScenario", "emptyMainTabs", "-LHTodayHours", "0", "-LHSeedSuggestions", "empty"] + extra
            launch(scheme, tab: 0, args + ["-LHTodayScrollTo", "setup"])
            XCTAssertTrue(app.descendants(matching: .any)["home.activation.learn"].waitForExistence(timeout: 25))
            Thread.sleep(forTimeInterval: 1.5)
            write("today-setup-card-\(scheme)\(suffix)")
            if !suffix.isEmpty {
                app.swipeUp(velocity: .slow)
                write("today-setup-card-b-\(scheme)\(suffix)")
            }
        }
    }

    func testPropertyEditBottom() {
        each { scheme, suffix, extra in
            launch(scheme, tab: 1, ["-LHMockScenario", "occasional", "-LHPropertiesSeed", "four", "-LHOpenFirstPropertyEdit"] + extra)
            XCTAssertTrue(app.descendants(matching: .any)["property.delete"].firstMatch.waitForExistence(timeout: 25))
            let tip = app.buttons["Continue"]
            if tip.exists { tip.tap() }
            write("prop-edit-top-\(scheme)\(suffix)")
            for _ in 0..<10 { app.swipeUp() }
            write("prop-edit-bottom-\(scheme)\(suffix)")
        }
    }
}
