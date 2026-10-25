import XCTest

/// Package H frames for the visual gate: Settings (free and Pro), Filing and goal and its sheets,
/// Muted, the Learning center and an article, Export (locked, Pro, generating), Contact support and
/// Delete all data. Run with `TEST_RUNNER_LH_CAPTURE_DIR=<dir>`; writes
/// `<screen>-<size>-<scheme>.png`. `TEST_RUNNER_LH_CAPTURE_SIZES=default` limits the size set.
final class SettingsLongTailCaptureUITests: XCTestCase {
    private var app: XCUIApplication!

    private static let allSizes: [(tag: String, category: String?)] = [
        ("default", nil),
        ("xxl", "UICTContentSizeCategoryXXL"),
        ("ax3", "UICTContentSizeCategoryAccessibilityXL")
    ]

    private static var sizes: [(tag: String, category: String?)] {
        guard let only = ProcessInfo.processInfo.environment["LH_CAPTURE_SIZES"], !only.isEmpty else { return allSizes }
        let wanted = only.split(separator: ",").map(String.init)
        return allSizes.filter { wanted.contains($0.tag) }
    }

    private static var schemes: [String] {
        guard let only = ProcessInfo.processInfo.environment["LH_CAPTURE_SCHEMES"], !only.isEmpty else { return ["light", "dark"] }
        return only.split(separator: ",").map(String.init)
    }

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

    // MARK: Settings

    func testCaptureSettings() {
        forEachCombo { tag, size, scheme in
            // Pro: the plan row says Pro is active.
            launch(scenario: "frequent", scheme: scheme, category: size, extra: [])
            XCTAssertTrue(element("settings.profile").waitForExistence(timeout: 25))
            settleAndCapture("settings-pro-\(tag)")
            scrollCapture("settings-pro-\(tag)", stopAt: "settings.version", maxPages: 9)

            // Free: the Pro card and the locked export row.
            launch(scenario: "occasional", scheme: scheme, category: size, extra: [])
            XCTAssertTrue(element("settings.profile").waitForExistence(timeout: 25))
            settleAndCapture("settings-free-\(tag)")
            if size == nil || tag.hasPrefix("ax3") {
                scrollCapture("settings-free-\(tag)", stopAt: "settings.version", maxPages: 9)
            }
        }
    }

    func testCaptureFiling() {
        forEachCombo { tag, size, scheme in
            launch(scenario: "frequent", scheme: scheme, category: size, extra: ["-LHOpenFilingFromSettings"])
            XCTAssertTrue(element("taxProfile.screen").waitForExistence(timeout: 25))
            settleAndCapture("filing-\(tag)")
            scrollCapture("filing-\(tag)", stopAt: "taxProfile.addRental", maxPages: 5)

            if tag.hasPrefix("default") || tag.hasPrefix("ax3") {
                let hours = element("taxProfile.otherWorkHours")
                if scrollTo(hours) {
                    hours.tap()
                    if element("taxProfile.otherWorkHours.save").waitForExistence(timeout: 5) {
                        settleAndCapture("filing-hours-sheet-\(tag)")
                        element("sheet.close").tap()
                    }
                }
                let add = element("taxProfile.addRental")
                if scrollTo(add) {
                    add.tap()
                    if element("taxProfile.addRental.save").waitForExistence(timeout: 5) {
                        settleAndCapture("filing-add-sheet-\(tag)")
                    }
                }
            }
        }
    }

    func testCaptureMuted() {
        forEachCombo { tag, size, scheme in
            launch(scenario: "frequent", scheme: scheme, category: size, extra: ["-LHOpenMutedFromSettings"])
            XCTAssertTrue(element("settings.muted.screen").waitForExistence(timeout: 25))
            settleAndCapture("muted-\(tag)")
        }
    }

    // MARK: Learn

    func testCaptureLearn() {
        forEachCombo { tag, size, scheme in
            launch(scenario: "frequent", scheme: scheme, category: size, extra: ["-LHOpenLearningCenterFromSettings"])
            XCTAssertTrue(element("learn.screen").waitForExistence(timeout: 25))
            settleAndCapture("learn-\(tag)")
            scrollCapture("learn-\(tag)", stopAt: "learn.row.driving", maxPages: 4)

            launch(scenario: "frequent", scheme: scheme, category: size,
                   extra: ["-LHOpenLearningCenterFromSettings", "-LHOpenLearningArticle", "goal-750"])
            XCTAssertTrue(element("learn.article.goal-750").waitForExistence(timeout: 25))
            settleAndCapture("learn-article-\(tag)")
            if !tag.hasPrefix("ax3") { scrollCapture("learn-article-\(tag)", stopAt: nil, maxPages: 1) }
        }
    }

    // MARK: Contact support

    func testCaptureSupport() {
        forEachCombo { tag, size, scheme in
            launch(scenario: "frequent", scheme: scheme, category: size, extra: ["-LHOpenSupportFromSettings"])
            XCTAssertTrue(element("support.screen").waitForExistence(timeout: 25))
            settleAndCapture("support-\(tag)")
            if tag.hasPrefix("default") {
                let message = element("support.message")
                message.tap()
                message.typeText("How do I add a rental to the PDF?")
                let subject = element("support.subject")
                subject.tap()
                subject.typeText("Export question\n")
                settleAndCapture("support-filled-\(tag)")
            }
        }
    }

    // MARK: Delete all data

    func testCaptureDelete() {
        forEachCombo { tag, size, scheme in
            launch(scenario: "frequent", scheme: scheme, category: size, extra: ["-LHOpenDeleteData"])
            XCTAssertTrue(element("delete.screen").waitForExistence(timeout: 25))
            settleAndCapture("delete-\(tag)")
            if !tag.hasPrefix("default") { scrollCapture("delete-\(tag)", stopAt: "delete.cancel", maxPages: 3) }
            if tag.hasPrefix("default") {
                launch(scenario: "frequent", scheme: scheme, category: size, extra: ["-LHOpenDeleteData", "-LHDeleteHoldPreview", "0.55"])
                XCTAssertTrue(element("delete.screen").waitForExistence(timeout: 25))
                settleAndCapture("delete-hold-\(tag)")
                launch(scenario: "frequent", scheme: scheme, category: size, extra: ["-LHOpenDeleteData", "-LHDeleteHoldPreview", "1"])
                XCTAssertTrue(element("delete.screen").waitForExistence(timeout: 25))
                settleAndCapture("delete-deleting-\(tag)")
                launch(scenario: "frequent", scheme: scheme, category: size, extra: ["-LHOpenDeleteData", "-LHDeleteFailurePreview"])
                XCTAssertTrue(element("delete.screen").waitForExistence(timeout: 25))
                settleAndCapture("delete-failure-\(tag)")
                // A full hold on a simulator without iCloud asks the second question.
                launch(scenario: "frequent", scheme: scheme, category: size, extra: ["-LHOpenDeleteData"])
                XCTAssertTrue(element("delete.hold").waitForExistence(timeout: 25))
                element("delete.hold").press(forDuration: 2.2)
                let alert = app.alerts["iCloud is off"]
                if alert.waitForExistence(timeout: 10) {
                    settleAndCapture("delete-icloud-alert-\(tag)", wait: 1.0)
                    alert.buttons["Keep"].tap()
                }
            }
        }
    }

    // MARK: Export

    func testCaptureExport() {
        forEachCombo { tag, size, scheme in
            // Free: the locked preview. The Records tab carries the export button.
            launch(scenario: "occasional", scheme: scheme, category: size, extra: [], tab: 6)
            let export = element("records.export")
            XCTAssertTrue(export.waitForExistence(timeout: 25))
            tapRetrying(export, until: element("export.summary"))
            settleAndCapture("export-free-\(tag)", wait: 2.5)

            // Pro: ready to create, then generating, then ready.
            launch(scenario: "frequent", scheme: scheme, category: size, extra: ["-LHSlowExport", "2.5"], tab: 6)
            let proExport = element("records.export")
            XCTAssertTrue(proExport.waitForExistence(timeout: 25))
            tapRetrying(proExport, until: element("export.generatePDF"))
            settleAndCapture("export-pro-\(tag)", wait: 2.5)
            if tag.hasPrefix("default") || tag.hasPrefix("ax3") {
                let generate = element("export.generatePDF")
                generate.tap()
                settleAndCapture("export-generating-\(tag)", wait: 0.8)
                if element("export.sharePDF").waitForExistence(timeout: 20) {
                    settleAndCapture("export-ready-\(tag)", wait: 1.0)
                }
            }
        }
    }

    // MARK: Helpers

    private func forEachCombo(_ body: (_ tag: String, _ size: String?, _ scheme: String) -> Void) {
        for (sizeTag, category) in Self.sizes {
            for scheme in Self.schemes {
                body("\(sizeTag)-\(scheme)", category, scheme)
            }
        }
    }

    private func launch(scenario: String, scheme: String, category: String?, extra: [String], tab: Int = 4) {
        app.terminate()
        var args = [UITestIsolation.resetProfilesArgument, "-LHMockScenario", scenario,
                    "-LHInitialTab", "\(tab)", "-LHColorScheme", scheme,
                    "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let category { args += ["-UIPreferredContentSizeCategoryName", category] }
        app.launchArguments = args + extra
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func tapRetrying(_ element: XCUIElement, until result: XCUIElement, attempts: Int = 5) {
        for _ in 0..<attempts where !result.exists {
            if element.exists, element.isHittable { element.tap() }
            if result.waitForExistence(timeout: 3) { return }
        }
        XCTAssertTrue(result.exists, "Tapping \(element) never showed \(result)")
    }

    @discardableResult
    private func scrollTo(_ target: XCUIElement, maxSwipes: Int = 10) -> Bool {
        var swipes = 0
        while !(target.exists && target.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return target.exists && target.isHittable
    }

    /// Swipes up and captures `<name>-p2`, `-p3`, … until `stopAt` shows or `maxPages` is reached.
    private func scrollCapture(_ name: String, stopAt: String?, maxPages: Int) {
        for page in 2...max(2, maxPages) {
            if let stopAt, element(stopAt).exists, element(stopAt).isHittable { return }
            app.swipeUp()
            settleAndCapture("\(name)-p\(page)", wait: 0.9)
        }
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
