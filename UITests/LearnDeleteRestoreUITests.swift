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
            XCTAssertTrue(iCloudOff.buttons["Keep"].exists, "Keep (cancel) stays available at every step")
            iCloudOff.buttons["Delete from this iPhone"].tap()
        }
        // On a device signed in to iCloud this deletes real records in batches: give it time.
        XCTAssertTrue(app.buttons["onb-start"].waitForExistence(timeout: 150), "After deleting, the app is back at Welcome")
    }

    // Restore (2.0 profiles) is gone in 2.2: Earlier records replace it (IdentityJourneyUITests).

    // MARK: Capture

    func testCaptureLightDefault() { captureAll(scheme: "light", size: nil) }
    func testCaptureDarkDefault() { captureAll(scheme: "dark", size: nil) }
    func testCaptureLightXXL() { captureAll(scheme: "light", size: "xxl") }
    func testCaptureDarkXXL() { captureAll(scheme: "dark", size: "xxl") }
    func testCaptureLightAX3() { captureAll(scheme: "light", size: "ax3") }
    func testCaptureDarkAX3() { captureAll(scheme: "dark", size: "ax3") }

    /// `TEST_RUNNER_LH_CAPTURE_GROUPS=delete,restore,whatsnew` limits a run to those groups
    /// (re-gates recapture only what changed). Default: every group.
    private func wants(_ group: String) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment["LH_CAPTURE_GROUPS"], !raw.isEmpty else { return true }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(group)
    }

    private func captureAll(scheme: String, size: String?) {
        let suffix = "\(scheme)" + (size.map { "-\($0)" } ?? "")

        if wants("learn") {
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
        }

        if wants("delete") {
            // Idle, then a frozen mid-hold, then the finished hold ("Deleting…", full fill).
            launch(["-LHMockScenario", "frequent", "-LHInitialTab", "4", "-LHOpenDeleteData"], scheme: scheme, size: size)
            XCTAssertTrue(element("delete.screen").waitForExistence(timeout: 20))
            settleAndCapture("delete-hold-\(suffix)")

            for (name, progress) in [("delete-hold-mid", "0.55"), ("delete-hold-done", "1")] {
                launch(["-LHMockScenario", "frequent", "-LHInitialTab", "4", "-LHOpenDeleteData", "-LHDeleteHoldPreview", progress],
                       scheme: scheme, size: size)
                let hold = element("delete.hold")
                XCTAssertTrue(hold.waitForExistence(timeout: 20))
                // At large sizes the button sits below the fold: bring it and Cancel into view.
                if size != nil { _ = scrollTo(app.buttons["delete.cancel"]) }
                XCTAssertTrue(hold.isHittable, "\(name): the hold button is on screen")
                if progress == "1" { XCTAssertTrue(app.staticTexts["Deleting…"].firstMatch.exists, "The finished hold shows Deleting…") }
                settleAndCapture("\(name)-\(suffix)")
            }
        }

        if wants("deletefail"), size != "xxl" {
            // iCloud lost mid-delete: the honest failure, with nothing deleted.
            launch(["-LHMockScenario", "frequent", "-LHInitialTab", "4", "-LHOpenDeleteData", "-LHDeleteFailurePreview"],
                   scheme: scheme, size: size)
            let alert = app.alerts["Couldn’t delete"]
            XCTAssertTrue(alert.waitForExistence(timeout: 20))
            XCTAssertTrue(alert.staticTexts["Couldn’t reach iCloud. Your data hasn’t been deleted. Try again when you’re online."].exists)
            settleAndCapture("delete-failed-\(suffix)")
        }

        if wants("whatsnew") {
            launch(["-LHMockScenario", "occasional", "-LHShowWhatsNew", "-LHInitialTab", "0"], scheme: scheme, size: size)
            XCTAssertTrue(element("onb.whatsNew").waitForExistence(timeout: 20))
            settleAndCapture("whatsnew-house-\(suffix)", wait: 2.0)
            if size == "ax3" {
                // The body scrolls under the pinned Continue: show the rest of it.
                let last = app.staticTexts["Same hours, same PDF. Today now shows your count against your target, and the house shows how far along you are."]
                XCTAssertTrue(last.waitForExistence(timeout: 5))
                element("onb.whatsNew").swipeUp()
                XCTAssertTrue(last.isHittable, "The last line scrolls fully into view above Continue")
                settleAndCapture("whatsnew-house-scrolled-\(suffix)")
            }
        }
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
