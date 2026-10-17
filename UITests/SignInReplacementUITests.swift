import XCTest

/// 1.1 sign-in replacement journeys. The app's DEBUG fixture writes UserDefaults exactly
/// as LandlordHours 1.0.6 left them (see `LegacyProfileFixture`) before launch-time
/// migration runs, so these tests exercise the real upgrade path.
final class SignInReplacementUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Upgrade from 1.0.6

    func testUpgradeFrom106EmailProfileShowsDataWithNoSignInWall() {
        launch(["-LHSeedLegacyEmailProfile", "-LHInitialTab", "1"], scheme: "light")

        // No welcome / sign-in wall anywhere.
        XCTAssertFalse(app.buttons["welcome.continueWithoutAccount"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["welcome.signInWithApple"].exists)

        // Profile A's properties are visible straight away.
        XCTAssertTrue(app.staticTexts["Oak Street Duplex"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Pine Lake Cabin"].exists)
        XCTAssertFalse(app.staticTexts["Elm Court"].exists, "Profile B must not leak into A")

        // No email login form survives anywhere in the app.
        XCTAssertFalse(app.secureTextFields.firstMatch.exists)
    }

    func testUpgradeThenRestoreOtherDataSwitchesToSignedOutEmailProfile() {
        launch(["-LHSeedLegacyEmailProfile", "-LHInitialTab", "4"], scheme: "light")

        let restoreRow = app.buttons["settings.restoreOtherData"]
        XCTAssertTrue(restoreRow.waitForExistence(timeout: 8))
        restoreRow.tap()

        let profileB = app.buttons["restore.profile.email-old.profile@example.com"]
        XCTAssertTrue(profileB.waitForExistence(timeout: 5))
        profileB.tap()

        let confirm = app.alerts.buttons["Switch"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        // The sheet closes and Settings now shows profile B's identity.
        XCTAssertTrue(profileB.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["old.profile@example.com"].waitForExistence(timeout: 5))
        settle()

        let propertiesTab = app.buttons["Properties"].firstMatch
        propertiesTab.tap()
        if !app.staticTexts["Elm Court"].waitForExistence(timeout: 4) {
            propertiesTab.tap()
        }
        XCTAssertTrue(app.staticTexts["Elm Court"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Oak Street Duplex"].exists)
    }

    func testSignedOutUpgradeShowsWelcomeWithRestoreAndRestoresProfile() {
        launch(["-LHSeedLegacySignedOut"], scheme: "light")

        XCTAssertTrue(app.buttons["welcome.continueWithoutAccount"].waitForExistence(timeout: 8))
        let restore = app.buttons["welcome.restoreEarlierData"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Log in"].exists)
        XCTAssertFalse(app.buttons["Create account"].exists)
        restore.tap()

        let profileA = app.buttons["restore.profile.email-upgrade.tester@example.com"]
        XCTAssertTrue(profileA.waitForExistence(timeout: 5))
        profileA.tap()

        app.buttons["Properties"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Oak Street Duplex"].waitForExistence(timeout: 8))
    }

    // MARK: - Frames for the visual gate (light + dark)

    func testCaptureSignInFramesLight() {
        captureFrames(scheme: "light")
    }

    func testCaptureSignInFramesDark() {
        captureFrames(scheme: "dark")
    }

    private func captureFrames(scheme: String) {
        // 1. Welcome — fresh device (no earlier data).
        launch(["-LHFreshWelcome"], scheme: scheme, resetDefaults: true)
        XCTAssertTrue(app.buttons["welcome.continueWithoutAccount"].waitForExistence(timeout: 8))
        settle()
        attach("01-welcome-fresh-\(scheme)")

        // 2. Welcome — signed-out 1.0.6 user with earlier data → Restore row.
        launch(["-LHSeedLegacySignedOut"], scheme: scheme)
        XCTAssertTrue(app.buttons["welcome.restoreEarlierData"].waitForExistence(timeout: 8))
        settle()
        attach("02-welcome-restore-\(scheme)")

        // 3. Welcome › Restore earlier data sheet.
        app.buttons["welcome.restoreEarlierData"].tap()
        XCTAssertTrue(app.buttons["restore.profile.email-upgrade.tester@example.com"].waitForExistence(timeout: 5))
        settle()
        attach("03-welcome-restore-sheet-\(scheme)")

        // 4. Settings (upgraded email user) — Account group with Restore other data.
        launch(["-LHSeedLegacyEmailProfile", "-LHInitialTab", "4"], scheme: scheme)
        let restoreRow = app.buttons["settings.restoreOtherData"]
        XCTAssertTrue(restoreRow.waitForExistence(timeout: 8))
        settle()
        attach("04a-settings-top-\(scheme)")
        // Bring the "Account" group header to the top of the screen (not under the status bar).
        let accountHeader = app.staticTexts["Account"].firstMatch
        if accountHeader.exists {
            let start = accountHeader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let delta = accountHeader.frame.midY - 140
            let end = start.withOffset(CGVector(dx: 0, dy: -delta))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
        }
        settle()
        attach("04-settings-account-restore-\(scheme)")
        scrollTo(restoreRow)

        // 5. Settings › Restore other data sheet.
        restoreRow.tap()
        XCTAssertTrue(app.buttons["restore.profile.email-old.profile@example.com"].waitForExistence(timeout: 5))
        settle()
        attach("05-settings-restore-sheet-\(scheme)")
        app.buttons["Cancel"].firstMatch.tap()

        // 6. Settings › Switch profile + Delete All Data rows.
        let switchRow = app.buttons["settings.switchProfile"]
        scrollTo(switchRow)
        XCTAssertTrue(switchRow.exists)
        XCTAssertTrue(app.buttons["settings.deleteData"].exists)
        settle()
        attach("06-settings-switch-profile-\(scheme)")

        // 7. Switch profile confirmation.
        switchRow.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        settle()
        attach("07-settings-switch-confirm-\(scheme)")
        app.alerts.buttons["Cancel"].tap()
    }

    // MARK: - Helpers

    private func launch(_ arguments: [String], scheme: String, resetDefaults: Bool = false) {
        app.terminate()
        var args = arguments + [
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        if resetDefaults {
            args.append("-LHResetProfilesForTesting")
        }
        app.launchArguments = args
        app.launch()
    }

    private func settle() {
        Thread.sleep(forTimeInterval: 1.0)
    }

    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while (!element.exists || !element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
