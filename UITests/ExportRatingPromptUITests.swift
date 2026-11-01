import XCTest

/// The ratings prompt after the first PDF export (2.2.1 carry-in, plan package E).
///
/// `-LHRatingProbe` (DEBUG) turns the coordinator on, starts the install 8 days back, and shows what
/// the policy accepted as the hidden `rating.probe` element ("none" or the trigger). The system
/// prompt itself is never queued in this mode, so nothing covers the app. The guards (paywall,
/// failed export, once per version, entry count) are pinned by `RatingPromptPolicyTests` and
/// `RatingPromptCoordinatorTests`; this class checks the wiring through the real export screen.
final class ExportRatingPromptUITests: XCTestCase {
    private var app: XCUIApplication!

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

    private func launch() {
        app.terminate()
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "frequent",
            "-LHRatingProbe",
            "-LHInitialTab", "3",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
    }

    private var probe: XCUIElement { app.descendants(matching: .any)["rating.probe"].firstMatch }

    private func probeValue() -> String { probe.label }

    private func openExportAndMakeReport() {
        XCTAssertTrue(app.staticTexts["Reports"].waitForExistence(timeout: 20))
        let title = app.staticTexts["Export the record"]
        for _ in 0..<5 where !title.exists {
            let button = app.buttons["Export report"]
            if button.waitForExistence(timeout: 3), button.isHittable { button.tap() }
            _ = title.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(title.exists, "export sheet")
        let generate = app.buttons["export.generatePDF"]
        var tries = 0
        while !generate.isHittable && tries < 6 { app.swipeUp(); tries += 1 }
        generate.tap()
        XCTAssertTrue(app.staticTexts["Report ready"].waitForExistence(timeout: 20), "report ready")
    }

    /// Shares through the system sheet with "Copy", which reports `completed == true`.
    private func share(_ button: XCUIElement) {
        button.tap()
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Copy'")).firstMatch
        if !copy.waitForExistence(timeout: 15) {
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        }
        XCTAssertTrue(copy.exists, "share sheet shows Copy")
        copy.tap()
        // The sheet closes itself; the export screen is back.
        XCTAssertTrue(app.buttons["export.sharePDF"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.0)
    }

    func testCSVShareNeverAsksAndTheFirstPDFShareDoes() {
        launch()
        openExportAndMakeReport()
        XCTAssertTrue(probe.waitForExistence(timeout: 5), "probe is present under -LHRatingProbe")
        XCTAssertEqual(probeValue(), "none", "nothing asked yet")

        // The CSV link sits under the pinned Share PDF foot until the sheet is scrolled.
        app.swipeUp(velocity: .slow)
        let csv = app.buttons["export.shareCSV"]
        XCTAssertTrue(csv.waitForExistence(timeout: 5))
        XCTAssertLessThan(csv.frame.maxY, app.buttons["export.sharePDF"].frame.minY - 4, "CSV link is clear of the foot")
        share(csv)
        XCTAssertEqual(probeValue(), "none", "a CSV share is not the first export and never asks")

        share(app.buttons["export.sharePDF"])
        XCTAssertEqual(probeValue(), "export_shared", "the first PDF share asks, even after a CSV")
    }
}
