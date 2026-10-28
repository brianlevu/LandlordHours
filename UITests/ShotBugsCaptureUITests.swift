import XCTest

/// Shot-bugs (2026-10-27) frames and journeys: the Log time header day, and the tag contrast frames.
/// Frames go to `TEST_RUNNER_LH_CAPTURE_DIR` as PNGs.
final class ShotBugsCaptureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        UITestIsolation.resetStoreKit()
        continueAfterFailure = true
        app = XCUIApplication()
    }

    private func launch(scheme: String, size: String?, seed: String = "four") {
        app.terminate()
        var args = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "occasional",
            "-LHPropertiesSeed", seed,
            "-LHInitialTab", "0",
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-LHNoteModel", "fake",
        ]
        if let size { args += ["-UIPreferredContentSizeCategoryName", size] }
        app.launchArguments = args
        app.launch()
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 2.5)
        let tip = app.buttons["Continue"]
        if tip.exists { tip.tap() }
    }

    private func element(_ id: String) -> XCUIElement {
        let button = app.buttons[id].firstMatch
        return button.exists ? button : app.descendants(matching: .any)[id].firstMatch
    }

    private func write(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["LH_CAPTURE_DIR"], !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        Thread.sleep(forTimeInterval: 1.0)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    /// A note that says "yesterday" sets the day. The header must say "Yesterday" with the date once,
    /// matching the Date row, and no second date line may appear above it.
    func testLogHeaderNamesYesterdayWhenTheNoteSaysYesterday() {
        for (size, category) in [("default", nil), ("xxl", "UICTContentSizeCategoryXXL")] as [(String, String?)] {
            for scheme in ["light", "dark"] {
                launch(scheme: scheme, size: category)
                app.buttons["tab.logTime"].tap()
                let note = element("log.note")
                XCTAssertTrue(note.waitForExistence(timeout: 8))
                note.tap()
                note.typeText("fixed the sink at Oak St with Mike, about 2 hours yesterday")
                XCTAssertTrue(element("log.description").waitForExistence(timeout: 8), "note read \(size) \(scheme)")
                XCTAssertTrue(app.buttons["log.date"].label.contains("Yesterday"), app.buttons["log.date"].label)
                app.buttons["log.done"].tap()
                Thread.sleep(forTimeInterval: 0.6)
                let header = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Yesterday'")).firstMatch
                XCTAssertTrue(header.waitForExistence(timeout: 4), "header says Yesterday (\(size) \(scheme))")
                let bareDates = app.staticTexts.matching(NSPredicate(format: "label MATCHES '^(Mon|Tue|Wed|Thu|Fri|Sat|Sun), [A-Z][a-z]{2} [0-9]{1,2}$'"))
                XCTAssertEqual(bareDates.count, 0, "no bare weekday date line beside the Yesterday header (\(size) \(scheme))")
                write("logheader-yesterday-\(size)-\(scheme)")
            }
        }
    }

    /// Rentals with no hours yet draw the first stage the house system defines (`started`): the frames
    /// record it at default and XXL, light and dark.
    func testCaptureRentalsGalleryWithZeroHours() {
        for (size, category) in [("default", nil), ("xxl", "UICTContentSizeCategoryXXL")] as [(String, String?)] {
            for scheme in ["light", "dark"] {
                launch(scheme: scheme, size: category, seed: "brian")
                let tab = app.buttons["tab.properties"].firstMatch
                XCTAssertTrue(tab.waitForExistence(timeout: 10))
                tab.tap()
                Thread.sleep(forTimeInterval: 1.5)
                write("rentals-zero-hours-\(size)-\(scheme)")
            }
        }
    }
}
