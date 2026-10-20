import XCTest

/// 2.0 Properties: journeys (free limit → paywall, delete with Cancel) and capture frames for
/// every state in light/dark at the default size, XXL and AX3. Frames go to `LH_CAPTURE_DIR`
/// when the runner gets it (`TEST_RUNNER_LH_CAPTURE_DIR=<dir>`).
final class PropertiesUITests: XCTestCase {
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

    // MARK: Journeys

    func testFreeUserAtTheLimitPreviewsAndUnlockOpensThePropertyPaywall() {
        launch(seed: "limit", extra: [])
        let lock = app.buttons["lock.unlock"]
        XCTAssertTrue(lock.waitForExistence(timeout: 12), "At the free limit the locked row shows")
        XCTAssertTrue(app.staticTexts["Free covers one rental."].exists)
        XCTAssertTrue(app.staticTexts["Pine Cabin keeps tracking. Nothing is lost."].exists, "says what stays active")
        lock.tap()
        XCTAssertTrue(app.descendants(matching: .any)["paywall.secondProperty"].waitForExistence(timeout: 8), "one unlock action, paywall for this context")
        let close = app.buttons["paywall.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(lock.waitForExistence(timeout: 5), "clean back-out")
        // The header's Add property goes to the same paywall.
        app.buttons["properties.add"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["paywall.secondProperty"].waitForExistence(timeout: 8))
    }

    func testProUserSeesNoLockAndAddOpensTheSheet() {
        launch(seed: "four", extra: [])
        XCTAssertTrue(app.buttons["properties.row.0"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["lock.unlock"].exists)
        app.buttons["properties.add"].firstMatch.tap()
        XCTAssertTrue(app.textFields["property.name"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["property.save"].isEnabled, "disabled until there's a name")
    }

    func testDeleteAsksWithCancelAndRemovesTheRental() {
        launch(seed: "four", extra: ["-LHOpenFirstPropertyDelete"])
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 12))
        XCTAssertTrue(alert.label.hasPrefix("Delete Pine Cabin and its"), alert.label)
        XCTAssertTrue(alert.buttons["Cancel"].exists)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["property.delete"].waitForExistence(timeout: 5), "Cancel keeps the sheet and the rental")
        app.buttons["property.delete"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.firstMatch.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["properties.row.0"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Pine Cabin"].exists)
        XCTAssertTrue(app.staticTexts["properties.subtitle"].label.hasPrefix("3 rentals"))
    }

    func testDetailShowsTheRentalsOwnHoursAndSeeAllOpensRecords() {
        launch(seed: "four", extra: ["-LHOpenFirstPropertyDetail"])
        let hero = app.descendants(matching: .any)["property.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 12))
        XCTAssertTrue(hero.label.contains("212 hours this year"), hero.label)
        XCTAssertTrue(hero.label.contains("Frame going up"), hero.label)
        app.buttons["property.seeAllRecords"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["records.total"].waitForExistence(timeout: 8))
    }

    // MARK: Frames

    func testCaptureLightDefault() { captureAll(scheme: "light", size: nil) }
    func testCaptureDarkDefault() { captureAll(scheme: "dark", size: nil) }
    func testCaptureLightXXL() { captureAll(scheme: "light", size: "xxl") }
    func testCaptureDarkXXL() { captureAll(scheme: "dark", size: "xxl") }
    func testCaptureLightAX3() { captureAll(scheme: "light", size: "ax3") }
    func testCaptureDarkAX3() { captureAll(scheme: "dark", size: "ax3") }

    private struct Shot {
        let name: String
        let seed: String
        var extra: [String] = []
        let waitFor: String
    }

    private let shots: [Shot] = [
        Shot(name: "props-list", seed: "four", waitFor: "properties.row.0"),
        Shot(name: "props-list-mp", seed: "four", extra: ["-LHPropertiesGoal", "mp100"], waitFor: "properties.row.0"),
        Shot(name: "props-list-info", seed: "four", extra: ["-LHPropertiesInfo"], waitFor: "properties.infoNote"),
        Shot(name: "props-12", seed: "twelve", waitFor: "properties.search"),
        Shot(name: "props-12-bottom", seed: "twelve", extra: ["-LHPropertiesScrollBottom"], waitFor: "properties.row.11"),
        Shot(name: "props-empty", seed: "empty", waitFor: "properties.empty"),
        Shot(name: "props-loading", seed: "four", extra: ["-LHPropertiesLoading"], waitFor: "properties.loading"),
        Shot(name: "props-limit", seed: "limit", waitFor: "lock.unlock"),
        Shot(name: "prop-detail", seed: "four", extra: ["-LHOpenFirstPropertyDetail", "-LHPropertiesMapLoading"], waitFor: "property.hero"),
        Shot(name: "prop-detail-lower", seed: "four", extra: ["-LHOpenFirstPropertyDetailLower"], waitFor: "property.details"),
        Shot(name: "prop-detail-520", seed: "four", extra: ["-LHOpenSecondPropertyDetail", "-LHPropertiesMapLoading"], waitFor: "property.hero"),
        Shot(name: "prop-detail-maploading", seed: "four", extra: ["-LHOpenFirstPropertyDetailLower", "-LHPropertiesMapLoading"], waitFor: "property.mapLoading"),
        Shot(name: "prop-add", seed: "four", extra: ["-LHOpenAddProperty"], waitFor: "property.name"),
        Shot(name: "prop-edit", seed: "four", extra: ["-LHOpenFirstPropertyEdit"], waitFor: "property.delete"),
        Shot(name: "prop-edit-delete", seed: "four", extra: ["-LHOpenFirstPropertyDelete"], waitFor: "ALERT"),
    ]

    private func captureAll(scheme: String, size: String?) {
        var sizeArgs: [String] = []
        switch size {
        case "xxl": sizeArgs = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"]
        case "ax3": sizeArgs = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        default: break
        }
        for shot in shots {
            app.terminate()
            launch(seed: shot.seed, scheme: scheme, extra: shot.extra + sizeArgs)
            if shot.waitFor == "ALERT" {
                XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 15), "\(shot.name): alert")
            } else {
                XCTAssertTrue(app.descendants(matching: .any)[shot.waitFor].firstMatch.waitForExistence(timeout: 15), "\(shot.name): \(shot.waitFor)")
            }
            let tip = app.buttons["Continue"]
            if tip.exists { tip.tap(); Thread.sleep(forTimeInterval: 0.6) }
            Thread.sleep(forTimeInterval: 1.0)
            capture("\(shot.name)-\(scheme)\(size.map { "-\($0)" } ?? "")")
        }
    }

    /// The re-rendered keyframes on Today: the hero at each early stage (the readable slab) and
    /// the confirm board frames over the k14 base, to check they still line up.
    func testCaptureTodayHeroWithTheNewKeyframes() {
        for scheme in ["light", "dark"] {
            for hours in ["0", "60", "120", "212", "600", "760"] {
                app.terminate()
                app.launchArguments = ["-LHHousePreview", hours, "reps", scheme, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
                app.launch()
                XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "hero \(hours)")
                Thread.sleep(forTimeInterval: 2.5)
                capture("today-hero-\(hours)h-\(scheme)")
            }
            for still in [0, 4, 8, 12] {
                app.terminate()
                app.launchArguments = ["-LHHousePreview", "600", "reps", scheme, "-LHHouseScene", "confirm",
                                       "-LHHouseConfirmStill", "\(still)", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
                app.launch()
                XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "confirm still \(still)")
                Thread.sleep(forTimeInterval: 2.5)
                capture("today-confirm-board\(still)-\(scheme)")
            }
        }
    }

    // MARK: Helpers

    private func launch(seed: String, scheme: String = "light", extra: [String]) {
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "occasional",
            "-LHPropertiesSeed", seed,
            "-LHInitialTab", "1",
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ] + extra
        app.launch()
        // The launch bridge fades out over the first seconds and swallows taps until it's gone.
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 3)
        // First keyboard on a fresh simulator shows a one-time typing tip.
        let tip = app.buttons["Continue"]
        if tip.exists { tip.tap() }
    }

    private func capture(_ name: String) {
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
