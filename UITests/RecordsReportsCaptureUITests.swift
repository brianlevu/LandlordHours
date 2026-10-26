import XCTest

/// Package G frames for the visual gate: Records, the record page, Reports, the 100-hour sheet.
/// Run with `TEST_RUNNER_LH_CAPTURE_DIR=<dir>`; writes `<screen>-<size>-<scheme>.png`.
final class RecordsReportsCaptureUITests: XCTestCase {
    private var app: XCUIApplication!

    private static let sizes: [(tag: String, category: String?)] = [
        ("default", nil),
        ("xxl", "UICTContentSizeCategoryXXL"),
        ("ax3", "UICTContentSizeCategoryAccessibilityXL")
    ]

    override func setUp() {
        super.setUp()
        UITestIsolation.resetStoreKit()
        continueAfterFailure = true
        app = XCUIApplication()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testCaptureRecords() {
        for (size, category) in Self.sizes {
            for scheme in ["light", "dark"] {
                let tag = "\(size)-\(scheme)"
                launch(tab: 6, scheme: scheme, category: category)
                XCTAssertTrue(element("records.screen").waitForExistence(timeout: 25))
                XCTAssertTrue(element("records.total").waitForExistence(timeout: 10))
                settleAndCapture("records-\(tag)")
                app.swipeUp()
                settleAndCapture("records-\(tag)-scrolled")
                // A search with no match: the empty state.
                if size == "default" {
                    let search = element("records.search")
                    app.swipeDown(); app.swipeDown()
                    if search.waitForExistence(timeout: 5) {
                        search.tap()
                        search.typeText("zzzz")
                        settleAndCapture("records-nomatch-\(tag)")
                    }
                }
            }
        }
    }

    func testCaptureRecordDetail() {
        for (size, category) in Self.sizes {
            for scheme in ["light", "dark"] {
                let tag = "\(size)-\(scheme)"
                launch(tab: 6, scheme: scheme, category: category)
                let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "records.row.")).firstMatch
                XCTAssertTrue(row.waitForExistence(timeout: 25))
                var swipes = 0
                while !row.isHittable && swipes < 4 { app.swipeUp(); swipes += 1 }
                tapRetrying(row, until: app.buttons["entry.edit"])
                settleAndCapture("record-\(tag)")
                app.swipeUp()
                settleAndCapture("record-\(tag)-scrolled")
                app.swipeDown()
                app.buttons["entry.edit"].tap()
                settleAndCapture("record-edit-\(tag)")
                app.swipeUp()
                settleAndCapture("record-edit-\(tag)-scrolled1")
                app.swipeUp()
                settleAndCapture("record-edit-\(tag)-scrolled2")
            }
        }
    }

    func testCaptureReports() {
        for (size, category) in Self.sizes {
            for scheme in ["light", "dark"] {
                let tag = "\(size)-\(scheme)"
                launch(tab: 3, scheme: scheme, category: category)
                XCTAssertTrue(element("reports.standing.you").waitForExistence(timeout: 25))
                settleAndCapture("reports-\(tag)")
                app.swipeUp()
                settleAndCapture("reports-\(tag)-scrolled1")
                app.swipeUp()
                settleAndCapture("reports-\(tag)-scrolled2")
                app.swipeUp()
                settleAndCapture("reports-\(tag)-scrolled3")
                if size == "default" {
                    for _ in 0..<4 { app.swipeDown() }
                    let mp100 = app.buttons["100h"]
                    if mp100.waitForExistence(timeout: 5) {
                        mp100.tap()
                        settleAndCapture("reports-mp100-\(tag)")
                        let confirmRow = app.buttons["reports.mp100.confirmRow"]
                        if confirmRow.waitForExistence(timeout: 3) {
                            confirmRow.tap()
                            if app.buttons["participation.answer.yes"].waitForExistence(timeout: 5) {
                                settleAndCapture("reports-sheet-\(tag)")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private func launch(tab: Int, scheme: String, category: String?) {
        app.terminate()
        var args = [UITestIsolation.resetProfilesArgument, "-LHMockScenario", "frequent",
                    "-LHInitialTab", "\(tab)", "-LHColorScheme", scheme,
                    "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let category { args += ["-UIPreferredContentSizeCategoryName", category] }
        app.launchArguments = args
        app.launch()
    }

    private func tapRetrying(_ element: XCUIElement, until result: XCUIElement, attempts: Int = 5) {
        for _ in 0..<attempts where !result.exists {
            if element.exists, element.isHittable { element.tap() }
            if result.waitForExistence(timeout: 3) { return }
        }
        XCTAssertTrue(result.exists, "Tapping \(element) never showed \(result)")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func settleAndCapture(_ name: String, wait: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: wait)
        let screenshot = XCUIScreen.main.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        if let dir = ProcessInfo.processInfo.environment["LH_CAPTURE_DIR"], !dir.isEmpty {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
