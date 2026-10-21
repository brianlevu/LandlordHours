import XCTest

/// WP-Learn: the 2.0 Learning center, the hold-to-delete page, the restore sheet and the What's
/// new house screen. Behaviour checks plus frame capture for the visual gate
/// (`TEST_RUNNER_LH_CAPTURE_DIR=<dir>`): every state, light and dark, at default, XXL and AX3.
final class LearnDeleteRestoreUITests: XCTestCase {
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

    // MARK: Behaviour

    func testLearningCenterListsTheReadsAndOpensAnArticle() {
        launch(["-LHMockScenario", "frequent", "-LHInitialTab", "4", "-LHOpenLearningCenterFromSettings"])
        XCTAssertTrue(element("learn.screen").waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Learning center"].exists)
        XCTAssertTrue(element("learn.row.goal-750").exists)
        XCTAssertTrue(element("learn.row.stays").exists)
        XCTAssertFalse(app.images["LearningHero"].exists, "No stock photos")
        element("learn.row.goal-750").tap()
        XCTAssertTrue(element("learn.article.goal-750").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What the 750-hour goal means"].exists)
        let disclaimer = app.staticTexts["General information, not tax advice. Your tax pro has the final word."]
        XCTAssertTrue(scrollTo(disclaimer), "Every article ends with the disclaimer")
    }

    func testDeleteNeedsAHoldCancelLeavesAndAFullHoldDeletes() {
        launch(["-LHMockScenario", "frequent", "-LHInitialTab", "4", "-LHOpenDeleteData"])
        let screen = element("delete.screen")
        XCTAssertTrue(screen.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["This can’t be undone."].exists)
        let hold = element("delete.hold")
        XCTAssertTrue(hold.exists)
        XCTAssertEqual(hold.label, "Delete everything")

        // A tap, or a hold that lets go early, deletes nothing.
        hold.tap()
        hold.press(forDuration: 0.6)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(screen.exists, "A short press never deletes")
        XCTAssertFalse(app.alerts.firstMatch.exists)

        // Cancel is always there and goes back to Settings with everything kept.
        let cancel = app.buttons["delete.cancel"]
        XCTAssertTrue(scrollTo(cancel))
        cancel.tap()
        XCTAssertTrue(screen.waitForNonExistence(timeout: 5))
        XCTAssertTrue(element("settings.screen").waitForExistence(timeout: 5), "Cancel goes back to Settings")

        // Back in, a full hold runs the real deletion path.
        let row = app.buttons["settings.deleteData"]
        XCTAssertTrue(scrollTo(row, maxSwipes: 12))
        for _ in 0..<4 where !screen.exists {
            if row.exists, row.isHittable { row.tap() }
            _ = screen.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(screen.exists)
        element("delete.hold").press(forDuration: 2.2)

        // The simulator usually has no iCloud account: the kept iCloud-off alert is the next step.
        let iCloudOff = app.alerts["iCloud is off"]
        if iCloudOff.waitForExistence(timeout: 8) {
            XCTAssertTrue(iCloudOff.buttons["Cancel"].exists, "Cancel stays available at every step")
            iCloudOff.buttons["Delete from this iPhone"].tap()
        }
        // On a device signed in to iCloud this deletes real records in batches: give it time.
        XCTAssertTrue(app.buttons["onb-start"].waitForExistence(timeout: 150), "After deleting, the app is back at Welcome")
    }

    func testRestoreAsksBeforeOpeningAndCloseKeepsYourRecords() {
        launch(["-LHSeedLegacyEmailProfile", "-LHInitialTab", "4", "-LHOpenRestoreSheet"])
        let row = app.buttons["restore.profile.email-old.profile@example.com"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Your other records"].exists)
        row.tap()
        let alert = app.alerts["Open these records?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(row.exists, "Cancel leaves the sheet as it was")
        app.buttons["restore.close"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
    }

    // MARK: Capture

    func testCaptureLightDefault() { captureAll(scheme: "light", size: nil) }
    func testCaptureDarkDefault() { captureAll(scheme: "dark", size: nil) }
    func testCaptureLightXXL() { captureAll(scheme: "light", size: "xxl") }
    func testCaptureDarkXXL() { captureAll(scheme: "dark", size: "xxl") }
    func testCaptureLightAX3() { captureAll(scheme: "light", size: "ax3") }
    func testCaptureDarkAX3() { captureAll(scheme: "dark", size: "ax3") }

    private func captureAll(scheme: String, size: String?) {
        let suffix = "\(scheme)" + (size.map { "-\($0)" } ?? "")

        launch(["-LHMockScenario", "frequent", "-LHInitialTab", "4", "-LHOpenLearningCenterFromSettings"], scheme: scheme, size: size)
        XCTAssertTrue(element("learn.screen").waitForExistence(timeout: 20))
        settleAndCapture("learn-\(suffix)")
        app.swipeUp()
        app.swipeUp()
        settleAndCapture("learn-end-\(suffix)")

        launch(["-LHMockScenario", "frequent", "-LHInitialTab", "4", "-LHOpenLearningCenterFromSettings",
                "-LHOpenLearningArticle", "goal-750"], scheme: scheme, size: size)
        XCTAssertTrue(element("learn.article.goal-750").waitForExistence(timeout: 20))
        settleAndCapture("learn-article-\(suffix)")

        launch(["-LHMockScenario", "frequent", "-LHInitialTab", "4", "-LHOpenLearningCenterFromSettings",
                "-LHOpenLearningArticle", "spouse-hours"], scheme: scheme, size: size)
        XCTAssertTrue(element("learn.article.spouse-hours").waitForExistence(timeout: 20))
        settleAndCapture("learn-article-topic-\(suffix)")

        launch(["-LHMockScenario", "frequent", "-LHInitialTab", "4", "-LHOpenDeleteData"], scheme: scheme, size: size)
        XCTAssertTrue(element("delete.screen").waitForExistence(timeout: 20))
        settleAndCapture("delete-hold-\(suffix)")
        if size != nil {
            app.swipeUp()
            settleAndCapture("delete-hold-end-\(suffix)")
        }

        launch(["-LHMockScenario", "frequent", "-LHInitialTab", "4", "-LHOpenDeleteData", "-LHDeleteHoldPreview", "0.55"],
               scheme: scheme, size: size)
        XCTAssertTrue(element("delete.screen").waitForExistence(timeout: 20))
        if size != nil { _ = scrollTo(element("delete.hold")) }
        settleAndCapture("delete-hold-mid-\(suffix)")

        launch(["-LHSeedLegacyEmailProfile", "-LHInitialTab", "4", "-LHOpenRestoreSheet"], scheme: scheme, size: size)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "restore.profile.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        settleAndCapture("restore-\(suffix)")
        row.tap()
        XCTAssertTrue(app.alerts["Open these records?"].waitForExistence(timeout: 5))
        settleAndCapture("restore-confirm-\(suffix)")

        launch(["-LHMockScenario", "occasional", "-LHShowWhatsNew", "-LHInitialTab", "0"], scheme: scheme, size: size)
        XCTAssertTrue(element("onb.whatsNew").waitForExistence(timeout: 20))
        settleAndCapture("whatsnew-house-\(suffix)", wait: 2.0)
    }

    // MARK: Helpers

    private func launch(_ extra: [String], scheme: String = "light", size: String? = nil) {
        app.terminate()
        var args = [UITestIsolation.resetProfilesArgument, "-LHColorScheme", scheme,
                    "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        switch size {
        case "xxl": args += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"]
        case "ax3": args += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        default: break
        }
        app.launchArguments = args + extra
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @discardableResult
    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) -> Bool {
        var swipes = 0
        while (!element.exists || !element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.exists && element.isHittable
    }

    private func settleAndCapture(_ name: String, wait: TimeInterval = 1.2) {
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
