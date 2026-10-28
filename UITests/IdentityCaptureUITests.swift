import XCTest

/// Frames of every package K surface for the visual gate (`TEST_RUNNER_LH_CAPTURE_DIR=<dir>`):
/// light and dark, at the default size, XXL and AX3. Each state is reached with the captured
/// fixtures and the fake zone, never by hand.
final class IdentityCaptureUITests: IdentityJourneyUITests {
    func testCaptureLightDefault() { captureAll(scheme: "light", size: nil) }
    func testCaptureDarkDefault() { captureAll(scheme: "dark", size: nil) }
    func testCaptureLightXXL() { captureAll(scheme: "light", size: "xxl") }
    func testCaptureDarkXXL() { captureAll(scheme: "dark", size: "xxl") }
    func testCaptureLightAX3() { captureAll(scheme: "light", size: "ax3") }
    func testCaptureDarkAX3() { captureAll(scheme: "dark", size: "ax3") }

    // The journey tests are not re-run here.
    override func testFirstRunHasNoSignInAnywhere() {}
    override func testReturning106UserOpensOnTodayWithTheirRecords() {}
    override func testReturning201AppleUserOpensOnTodayWithNoSignIn() {}
    override func testTwoSetsAskOnceCombineAddsTheHours() {}
    override func testTwoSetsAsideIsListedAndCanBeAddedLater() {}
    override func testDecideLaterKeepsTheSetHeldAndListed() {}
    override func testNewPhoneChecksICloudThenContinues() {}
    override func testBulkAbsenceAsksKeepThenRemoveGoesToRecentlyRemoved() {}
    override func testAccountChangedAsks() {}
    override func testZoneDeletedElsewhereAsksAndNeverRecreatesItself() {}
    override func testSettingsStatusOnOffAndCouldntSync() {}
    override func testDeleteAllDataGoesBackToWelcome() {}

    private func shoot(_ name: String, wait: TimeInterval = 1.4) {
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

    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 10) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        // Rest the row in the middle of the screen, not under the tab bar.
        if element.exists, element.frame.maxY > app.frame.height * 0.8 { app.swipeUp() }
    }

    private func captureAll(scheme: String, size: String?) {
        let s = scheme + (size.map { "-\($0)" } ?? "-default")

        // Welcome: P1, P3, P2.
        launch(zone: "empty", scheme: scheme, size: size)
        XCTAssertTrue(element("welcome.records.p1").waitForExistence(timeout: 20))
        shoot("welcome-p1-\(s)")
        launch(zone: "slow", scheme: scheme, size: size)
        if element("welcome.records.checking").waitForExistence(timeout: 10) { shoot("welcome-checking-\(s)", wait: 0.3) }
        XCTAssertTrue(element("welcome.records.found").waitForExistence(timeout: 20))
        shoot("welcome-found-\(s)")

        // The two-sets question and its second step.
        launch(fixture: "D8-201-two-local", zone: "empty", scheme: scheme, size: size)
        XCTAssertTrue(element("identity.mergeQuestion").waitForExistence(timeout: 25))
        shoot("merge-ask-\(s)")
        tap(app.buttons["identity.merge.aside"])
        shoot("merge-aside-\(s)")

        // Bulk absence (P28), account changed (P13), zone deleted elsewhere (P31).
        launch(fixture: "D5-201-local", zone: "bulk", scheme: scheme, size: size)
        XCTAssertTrue(element("identity.bulk").waitForExistence(timeout: 25))
        shoot("bulk-\(s)")
        launch(fixture: "D5-201-local", zone: "accountChanged", scheme: scheme, size: size)
        XCTAssertTrue(element("identity.accountChanged").waitForExistence(timeout: 25))
        shoot("account-changed-\(s)")
        tap(app.buttons["identity.account.later"])
        if element("today.identity.p13").waitForExistence(timeout: 10) { shoot("today-p13-\(s)") }
        launch(fixture: "D5-201-local", zone: "zoneGone", scheme: scheme, size: size)
        XCTAssertTrue(element("identity.zoneGone").waitForExistence(timeout: 30))
        shoot("zone-gone-\(s)")

        // Today notices: P12 (done), P10 (iCloud off after a saved entry).
        launch(fixture: "D2-106-signed-in", zone: "empty", scheme: scheme, size: size)
        if element("today.identity.p12").waitForExistence(timeout: 25) { scrollTo(element("today.identity.p12"), maxSwipes: 3); shoot("today-p12-\(s)") }
        launch(fixture: "D2-106-signed-in", zone: "off", scheme: scheme, size: size)
        if element("today.identity.p10").waitForExistence(timeout: 25) { scrollTo(element("today.identity.p10"), maxSwipes: 3); shoot("today-p10-\(s)") }

        // Settings › iCloud & records: On, Off (this capture's launch is already "off"), Couldn't sync.
        openSettings()
        scrollTo(element("settings.icloud.status"))
        shoot("settings-icloud-off-\(s)")
        launch(fixture: "D3-106-signed-out-two", zone: "empty", scheme: scheme, size: size)
        if element("identity.mergeQuestion").waitForExistence(timeout: 25) { tap(element("sheet.close")) }
        openSettings()
        scrollTo(element("settings.icloud.status"))
        shoot("settings-icloud-on-\(s)")
        tap(reveal("settings.earlierRecords"))
        XCTAssertTrue(element("earlier.list").waitForExistence(timeout: 10))
        shoot("earlier-records-\(s)")
        launch(fixture: "D2-106-signed-in", zone: "fail", scheme: scheme, size: size)
        openSettings()
        scrollTo(element("settings.icloud.status"))
        shoot("settings-icloud-problem-\(s)")
        tap(reveal("settings.icloud.status"))
        XCTAssertTrue(element("icloud.detail").waitForExistence(timeout: 10))
        shoot("icloud-detail-problem-\(s)")

        captureTail(s, scheme: scheme, size: size)
    }

    // Recently removed and Your name only (round re-runs after a fix to those two surfaces).
    func testTailLightDefault() { captureTail("light-default", scheme: "light", size: nil) }
    func testTailDarkDefault() { captureTail("dark-default", scheme: "dark", size: nil) }
    func testTailLightXXL() { captureTail("light-xxl", scheme: "light", size: "xxl") }
    func testTailDarkXXL() { captureTail("dark-xxl", scheme: "dark", size: "xxl") }
    func testTailLightAX3() { captureTail("light-ax3", scheme: "light", size: "ax3") }
    func testTailDarkAX3() { captureTail("dark-ax3", scheme: "dark", size: "ax3") }

    // Today's notice card only (round re-runs after a fix to the card).
    func testNoticeLightDefault() { captureNotices("light-default", scheme: "light", size: nil) }
    func testNoticeDarkDefault() { captureNotices("dark-default", scheme: "dark", size: nil) }
    func testNoticeLightXXL() { captureNotices("light-xxl", scheme: "light", size: "xxl") }
    func testNoticeDarkXXL() { captureNotices("dark-xxl", scheme: "dark", size: "xxl") }
    func testNoticeLightAX3() { captureNotices("light-ax3", scheme: "light", size: "ax3") }
    func testNoticeDarkAX3() { captureNotices("dark-ax3", scheme: "dark", size: "ax3") }

    private func captureNotices(_ s: String, scheme: String, size: String?) {
        launch(fixture: "D2-106-signed-in", zone: "empty", scheme: scheme, size: size)
        if element("today.identity.p12").waitForExistence(timeout: 25) { scrollTo(element("today.identity.p12"), maxSwipes: 3); shoot("today-p12-\(s)") }
        launch(fixture: "D2-106-signed-in", zone: "off", scheme: scheme, size: size)
        if element("today.identity.p10").waitForExistence(timeout: 25) { scrollTo(element("today.identity.p10"), maxSwipes: 3); shoot("today-p10-\(s)") }
    }

    // Screen anatomy frames (standard §S): iCloud, Earlier records, Recently removed on the scaffolds.
    func testCaptureScaffoldLightDefault() { captureScaffold("light-default", scheme: "light", size: nil) }
    func testCaptureScaffoldDarkDefault() { captureScaffold("dark-default", scheme: "dark", size: nil) }
    func testCaptureScaffoldLightXXL() { captureScaffold("light-xxl", scheme: "light", size: "xxl") }
    func testCaptureScaffoldDarkXXL() { captureScaffold("dark-xxl", scheme: "dark", size: "xxl") }

    // The iCloud screen alone (iPad column fix): frames plus the back button's and first row's frames.
    func testICloudOnlyLightDefault() { captureICloudOnly("light-default", scheme: "light", size: nil) }
    func testICloudOnlyDarkDefault() { captureICloudOnly("dark-default", scheme: "dark", size: nil) }
    func testICloudOnlyLightXXL() { captureICloudOnly("light-xxl", scheme: "light", size: "xxl") }
    func testICloudOnlyDarkXXL() { captureICloudOnly("dark-xxl", scheme: "dark", size: "xxl") }

    private func captureICloudOnly(_ s: String, scheme: String, size: String?) {
        launch(fixture: "D2-106-signed-in", zone: "fail", scheme: scheme, size: size)
        openSettings()
        scrollTo(element("settings.icloud.status"))
        tap(reveal("settings.icloud.status"))
        XCTAssertTrue(element("icloud.detail").waitForExistence(timeout: 10))
        shoot("icloud-\(s)")
        let back = element("icloud.back").frame
        let row = element("settings.icloud.status").frame
        print("ICLOUD_FRAMES \(s) back=\(back) row=\(row)")
    }

    private func captureScaffold(_ s: String, scheme: String, size: String?) {
        launch(fixture: "D3-106-signed-out-two", zone: "empty", scheme: scheme, size: size)
        if element("identity.mergeQuestion").waitForExistence(timeout: 25) { tap(element("sheet.close")) }
        openSettings()
        scrollTo(element("settings.earlierRecords"))
        tap(reveal("settings.earlierRecords"))
        XCTAssertTrue(element("earlier.list").waitForExistence(timeout: 10))
        shoot("c-earlier-\(s)")
        launch(fixture: "D2-106-signed-in", zone: "fail", scheme: scheme, size: size)
        openSettings()
        scrollTo(element("settings.icloud.status"))
        tap(reveal("settings.icloud.status"))
        XCTAssertTrue(element("icloud.detail").waitForExistence(timeout: 10))
        shoot("c-icloud-\(s)")
        launch(fixture: "D5-201-local", zone: "bulk", scheme: scheme, size: size)
        tap(app.buttons["identity.bulk.remove"], timeout: 25)
        openSettings()
        scrollTo(element("settings.earlierRecords"))
        tap(reveal("settings.earlierRecords"))
        tap(element("earlier.recentlyRemoved"))
        XCTAssertTrue(element("removed.list").waitForExistence(timeout: 10))
        shoot("c-removed-\(s)")
    }

    private func captureTail(_ s: String, scheme: String, size: String?) {
        // Recently removed (after "Remove them" on the bulk question), Your name.
        launch(fixture: "D5-201-local", zone: "bulk", scheme: scheme, size: size)
        tap(app.buttons["identity.bulk.remove"], timeout: 25)
        openSettings()
        scrollTo(element("settings.earlierRecords"))
        tap(reveal("settings.earlierRecords"))
        tap(element("earlier.recentlyRemoved"))
        XCTAssertTrue(element("removed.list").waitForExistence(timeout: 10))
        shoot("recently-removed-\(s)")
        launch(fixture: "D2-106-signed-in", zone: "empty", scheme: scheme, size: size)
        openSettings()
        scrollTo(element("settings.yourName"))
        tap(reveal("settings.yourName"))
        XCTAssertTrue(element("yourName.field").waitForExistence(timeout: 10))
        shoot("your-name-\(s)")
    }
}
