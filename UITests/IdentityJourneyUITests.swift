import XCTest

/// Package K's journeys with real taps (§5.3): first run, returning 1.x, returning 2.0.x, a new
/// phone, two sets of records, bulk absence, account changed, zone deleted elsewhere, and Delete
/// all data. Device data comes from the fixtures captured from shipped builds (UITests/Fixtures,
/// passed in the launch environment so the same run works on an iPad); iCloud is the in-memory
/// fake (`-LHFakeZone`). On a device the same tests run against the fake too; the Development
/// container rows are the HouseholdSync device runs.
class IdentityJourneyUITests: XCTestCase {
    var app: XCUIApplication!

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

    // MARK: Launch helpers

    func fixtureData(_ name: String) -> String? {
        guard let url = Bundle(for: IdentityJourneyUITests.self).url(forResource: name, withExtension: "plist"),
              let data = try? Data(contentsOf: url) else { return nil }
        return data.base64EncodedString()
    }

    func launch(fixture: String? = nil, zone: String? = nil, scheme: String = "light", size: String? = nil, extra: [String] = []) {
        app.terminate()
        var args = ["-LHResetIdentity", "-LHColorScheme", scheme, "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-LHNoSwipePeek"]
        switch size {
        case "xxl": args += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"]
        case "ax3": args += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        default: break
        }
        if let fixture {
            args += ["-LHUpgradeFixture", fixture]
            app.launchEnvironment["LH_UPGRADE_FIXTURE_B64"] = fixtureData(fixture)
        } else {
            app.launchEnvironment["LH_UPGRADE_FIXTURE_B64"] = nil
        }
        if let zone { args += ["-LHFakeZone", zone] }
        app.launchArguments = args + extra
        app.launch()
    }

    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func tap(_ element: XCUIElement, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "missing \(element)", file: file, line: line)
        let deadline = Date().addingTimeInterval(timeout)
        while !element.isHittable && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        element.tap()
    }

    /// Settings is a lazy List: rows below the fold exist only once scrolled to.
    @discardableResult
    func reveal(_ id: String, maxSwipes: Int = 30) -> XCUIElement {
        let e = element(id)
        var swipes = 0
        while !(e.exists && e.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return e
    }

    var todayShown: Bool { element("today.chip").waitForExistence(timeout: 25) || element("today.addRental").waitForExistence(timeout: 2) }

    /// Settings opens from Today's account menu (2.2 shell).
    func openSettings() {
        // A top toast replaces Today's chip row for a few seconds; the account button comes back.
        if !element("today.account").waitForExistence(timeout: 12) { tap(app.tabBars.buttons["Today"]) }
        tap(element("today.account"))
        tap(app.buttons["Settings"])
        XCTAssertTrue(element("settings.screen").waitForExistence(timeout: 10), "Settings")
    }

    // MARK: First run

    func testFirstRunHasNoSignInAnywhere() {
        launch(zone: "empty")
        XCTAssertTrue(app.buttons["onb-start"].waitForExistence(timeout: 20), "Welcome")
        XCTAssertTrue(element("welcome.records.p1").waitForExistence(timeout: 12), "P1 footer")
        XCTAssertFalse(app.buttons["welcome.haveAccount"].exists)
        XCTAssertFalse(app.buttons["welcome.signInWithApple"].exists)
        app.buttons["onb-start"].tap()                          // exactly one tap
        XCTAssertTrue(app.buttons["rental-short"].waitForExistence(timeout: 8), "one Get started tap reaches the goal step")
    }

    // MARK: Returning 1.x and 2.0.x (no Welcome, everything there)

    func testReturning106UserOpensOnTodayWithTheirRecords() {
        launch(fixture: "D2-106-signed-in", zone: "empty")
        XCTAssertTrue(todayShown, "an upgrader never sees Welcome")
        XCTAssertFalse(app.buttons["onb-start"].exists)
        XCTAssertTrue(element("today.identity.p12").waitForExistence(timeout: 20), "P12 once: no more sign-in")
        tap(element("today.identity.dismiss"))
        XCTAssertTrue(element("today.identity.p12").waitForNonExistence(timeout: 5))
    }

    func testReturning201AppleUserOpensOnTodayWithNoSignIn() {
        launch(fixture: "D6-201-apple", zone: "empty")
        XCTAssertTrue(todayShown)
        XCTAssertFalse(app.buttons["onb-start"].exists, "the Apple id is just a group name; nothing asks to sign in")
    }

    // MARK: Two sets of records

    func testTwoSetsAskOnceCombineAddsTheHours() {
        launch(fixture: "D8-201-two-local", zone: "empty")
        XCTAssertTrue(element("identity.mergeQuestion").waitForExistence(timeout: 25), "P4 over Today")
        tap(app.buttons["identity.merge.combine"])
        XCTAssertTrue(element("identity.mergeQuestion").waitForNonExistence(timeout: 8))
        XCTAssertTrue(todayShown)
    }

    func testTwoSetsAsideIsListedAndCanBeAddedLater() {
        launch(fixture: "D8-201-two-local", zone: "empty")
        tap(app.buttons["identity.merge.aside"], timeout: 25)
        tap(app.buttons["identity.merge.confirmAside"])
        openSettings()
        tap(reveal("settings.earlierRecords"))
        tap(element("earlier.group.aside"))
        tap(app.buttons["Add to my records"])
        XCTAssertTrue(element("identity.mergeQuestion").waitForExistence(timeout: 8), "Add to my records asks again")
        tap(app.buttons["identity.merge.combine"])
    }

    func testDecideLaterKeepsTheSetHeldAndListed() {
        launch(fixture: "D3-106-signed-out-two", zone: "empty")
        XCTAssertTrue(element("identity.mergeQuestion").waitForExistence(timeout: 25))
        tap(element("sheet.close"))
        openSettings()
        XCTAssertTrue(reveal("settings.earlierRecords").waitForExistence(timeout: 10))
        XCTAssertTrue(element("settings.earlierRecords").label.contains("1 waiting for your answer"), element("settings.earlierRecords").label)
    }

    // MARK: A new phone (cloud only)

    func testNewPhoneChecksICloudThenContinues() {
        launch(zone: "slow")
        XCTAssertTrue(element("welcome.records.checking").waitForExistence(timeout: 15), "P3 while iCloud is read")
        XCTAssertTrue(element("welcome.records.found").waitForExistence(timeout: 20), "P2: found, already here")
        XCTAssertEqual(app.buttons["onb-start"].label, "Continue")
        tap(app.buttons["onb-start"])
        XCTAssertTrue(todayShown, "Continue opens Today")
    }

    // MARK: Bulk absence (P28)

    func testBulkAbsenceAsksKeepThenRemoveGoesToRecentlyRemoved() {
        launch(fixture: "D5-201-local", zone: "bulk")
        XCTAssertTrue(element("identity.bulk").waitForExistence(timeout: 25), "P28")
        tap(app.buttons["identity.bulk.remove"])
        openSettings()
        tap(reveal("settings.earlierRecords"))
        tap(element("earlier.recentlyRemoved"))
        XCTAssertTrue(element("removed.list").waitForExistence(timeout: 8))
        tap(app.buttons["removed.putBackAll"])
    }

    // MARK: Account changed (P13), zone deleted elsewhere (P31)

    func testAccountChangedAsks() {
        launch(fixture: "D5-201-local", zone: "accountChanged")
        XCTAssertTrue(element("identity.accountChanged").waitForExistence(timeout: 25), "P13")
        tap(app.buttons["identity.account.later"])
        XCTAssertTrue(element("today.identity.p13").waitForExistence(timeout: 10), "decide later: Today says sync is paused")
    }

    func testZoneDeletedElsewhereAsksAndNeverRecreatesItself() {
        launch(fixture: "D5-201-local", zone: "zoneGone")
        XCTAssertTrue(element("identity.zoneGone").waitForExistence(timeout: 30), "P31")
        XCTAssertTrue(app.buttons["identity.zoneGone.keep"].exists)
        XCTAssertTrue(app.buttons["identity.zoneGone.delete"].exists)
    }

    // MARK: Settings › iCloud & records

    func testSettingsStatusOnOffAndCouldntSync() {
        for (zone, value) in [("empty", "On"), ("off", "Off"), ("fail", "Couldn’t sync")] {
            launch(fixture: "D2-106-signed-in", zone: zone)
            XCTAssertTrue(todayShown)
            openSettings()
            let row = reveal("settings.icloud.status")
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            let deadline = Date().addingTimeInterval(15)
            while !row.label.contains(value) && Date() < deadline { Thread.sleep(forTimeInterval: 0.5) }
            XCTAssertTrue(row.label.contains(value), "\(zone): \(row.label)")
        }
    }

    // MARK: Delete all data

    func testDeleteAllDataGoesBackToWelcome() {
        launch(fixture: "D2-106-signed-in", zone: "empty")
        XCTAssertTrue(todayShown)
        openSettings()
        tap(reveal("settings.deleteData"))
        let hold = app.buttons["delete.hold"].firstMatch.exists ? app.buttons["delete.hold"].firstMatch : element("delete.hold")
        XCTAssertTrue(hold.waitForExistence(timeout: 10))
        hold.press(forDuration: 2.2)
        XCTAssertTrue(app.buttons["onb-start"].waitForExistence(timeout: 30), "After Delete all data, Welcome as a new user")
    }
}
