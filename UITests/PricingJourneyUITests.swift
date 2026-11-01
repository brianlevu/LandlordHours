import XCTest

/// Package A (2.3): a FREE install, played through the local StoreKit config (LandlordHours.storekit:
/// the yearly plan with a 14-day free trial). Every 2.3 Pro entry point reports its taps to the
/// paywall and to the purchase (`TAPS_TO_PURCHASE | <entry> | paywall after N | purchase after N+1`,
/// attached for the release verifier), then buys, and the journey checks what Pro opened.
/// FreeUserPaywallUITests reports the 2.2 entry points the same way. Also: Restore after a
/// purchase, and the second rental's view-only state (locked in the Log time picker, refused at
/// save, its hours still on the page).
final class PricingJourneyUITests: XCTestCase {
    private var app: XCUIApplication!
    private var taps = 0

    override func setUp() {
        super.setUp()
        UITestIsolation.resetStoreKit()
        continueAfterFailure = false
        app = XCUIApplication()
        taps = 0
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: Entry points new in 2.3

    func testViewOnlyRentalSeeProToPurchase() {
        launchFreeWithTwoRentals()
        tap(app.buttons["tab.properties"].firstMatch)
        tap(tile("Oak Street Duplex"))
        let card = app.descendants(matching: .any)["rental.viewOnly"]
        XCTAssertTrue(card.waitForExistence(timeout: 8), "A free user's second rental is view-only")
        tap(app.buttons["viewOnly.seePro"])
        purchase(entryPoint: "Rental page > View only > See Pro")
        XCTAssertTrue(card.waitForNonExistence(timeout: 8), "Pro: the rental logs again, the card goes")
    }

    func testLogTimePickerLockedRentalToPurchase() {
        launchFreeWithTwoRentals()
        tap(app.buttons["tab.logTime"].firstMatch)
        let enter = app.buttons["log.enterDetails"]
        if enter.waitForExistence(timeout: 6) { tap(enter) }
        tap(app.buttons["log.property"])
        let locked = lockedChip()
        XCTAssertTrue(locked.waitForExistence(timeout: 6), "Oak Street Duplex shows locked in the picker")
        XCTAssertTrue(app.staticTexts["log.pick.freeRentalNote"].exists, "It names the free rental")
        tap(locked)
        purchase(entryPoint: "Log time > Rental picker > locked rental")
        XCTAssertTrue(app.buttons["log.property"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["log.property"].label.contains("Oak Street Duplex"),
                      "After Pro the locked rental is picked: \(app.buttons["log.property"].label)")
    }

    func testSettingsFreeRentalProRowToPurchase() {
        launchFreeWithTwoRentals()
        openSettings()
        let row = app.buttons["settings.freeRental"]
        scrollTo(row)
        tap(row)
        XCTAssertTrue(app.descendants(matching: .any)["plan.freeRental"].waitForExistence(timeout: 8))
        tap(app.buttons["freeRental.seePro"])
        purchase(entryPoint: "Settings > Free rental > Log at every rental")
    }

    func testPickSheetSeeProToPurchase() {
        launch(extra: ["-LHPlanSeed", "d23", "-LHPlanLastKind", "trial"])
        let sheet = app.descendants(matching: .any)["plan.pickFree"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        taps = 0
        tap(app.buttons["pickFree.seePro"])
        purchase(entryPoint: "Pick your free rental > See Pro")
    }

    // MARK: Restore, and the view-only state

    func testRestoreFindsTheTrialAfterAPurchase() {
        launchFreeWithTwoRentals()
        openSettings()
        tap(app.buttons["settings.proCard"])
        purchase(entryPoint: "Settings > See Pro")
        let restore = app.buttons["settings.restorePurchase"]
        scrollTo(restore)
        restore.tap()
        let found = NSPredicate(format: "label CONTAINS[c] %@", "back")
        expectation(for: found, evaluatedWith: restore)
        waitForExpectations(timeout: 20)
        XCTAssertTrue(app.buttons["settings.manageSubscriptions"].exists, "the trial is the plan on this device")
    }

    func testTheSecondRentalIsViewOnlyAndKeepsItsHours() {
        launchFreeWithTwoRentals()
        tap(app.buttons["tab.properties"].firstMatch)
        tap(tile("Oak Street Duplex"))
        let body = app.staticTexts["viewOnly.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 8))
        XCTAssertTrue(body.label.contains("46"), "The hours stay: \(body.label)")
        XCTAssertTrue(body.label.contains("Pine Cabin"), "Names the free rental")
        XCTAssertTrue(app.buttons["viewOnly.switch"].exists)
        // The free rental's page has no card.
        tap(app.buttons["property.back"])
        tap(tile("Pine Cabin"))
        XCTAssertFalse(app.descendants(matching: .any)["rental.viewOnly"].waitForExistence(timeout: 3))
        // Log time on the view-only rental is refused in the picker: the paywall, not a save.
        tap(app.buttons["tab.logTime"].firstMatch)
        let enter = app.buttons["log.enterDetails"]
        if enter.waitForExistence(timeout: 6) { enter.tap() }
        app.buttons["log.property"].tap()
        let locked = lockedChip()
        XCTAssertTrue(locked.waitForExistence(timeout: 6))
        locked.tap()
        XCTAssertTrue(app.staticTexts["paywall.title"].waitForExistence(timeout: 8))
        app.buttons["paywall.close"].tap()
        XCTAssertTrue(app.buttons["log.property"].waitForExistence(timeout: 6), "Back in Log time, nothing saved")
        XCTAssertFalse(app.buttons["log.property"].label.contains("Oak Street Duplex"), "The locked rental was not picked")
    }

    // MARK: Helpers

    private func launch(extra: [String]) {
        app.terminate()
        app.launchArguments = [UITestIsolation.resetProfilesArgument, "-LHMockScenario", "emptyMainTabs", "-LHInitialTab", "0",
                               "-LHColorScheme", "light", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["tab.today"].firstMatch.waitForExistence(timeout: 15), "The shell loads")
        taps = 0
    }

    /// Pine Cabin 420h (the free rental, picked yesterday) and Oak Street Duplex 46h.
    private func launchFreeWithTwoRentals() {
        launch(extra: ["-LHPlanSeed", "d23", "-LHFreeRentalPick", "Pine Cabin", "-LHFreeRentalPickedDaysAgo", "1"])
    }

    private func openSettings() {
        tap(app.buttons["today.account"])
        tap(app.buttons["Settings"].firstMatch)
    }

    private func tile(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "properties.tile.", name)).firstMatch
    }

    private func lockedChip() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "log.pick.property.", "Oak Street Duplex")).firstMatch
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), "Missing \(element)", file: file, line: line)
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 5), .completed, "Not hittable: \(element)", file: file, line: line)
        element.tap()
        taps += 1
    }

    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while (!element.exists || !element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3), "Could not reach \(element)")
    }

    /// On the paywall: the trial offer, then buy. Reports the taps, checks the trial-start moment
    /// and leaves through its Done (the next step).
    private func purchase(entryPoint: String) {
        let tapsToPaywall = taps
        let title = app.staticTexts["paywall.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8), "Paywall for \(entryPoint)")
        XCTAssertTrue(app.descendants(matching: .any)["paywall.price"].waitForExistence(timeout: 12), "Price from StoreKit")
        XCTAssertTrue(app.descendants(matching: .any)["paywall.timeline"].exists, "The trial offer leads with the timeline")
        let buy = app.buttons["paywall.buy"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true AND isHittable == true"), object: buy)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 15), .completed, "Start free trial is ready")
        buy.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let start = app.descendants(matching: .any)["trial.start"]
        let deadline = Date().addingTimeInterval(30)
        var sheetSeen = false
        while Date() < deadline && !start.exists {
            for candidate in [app!, springboard] where !sheetSeen {
                let confirm = candidate.buttons.matching(NSPredicate(format: "label IN %@", ["Subscribe", "Confirm", "Purchase", "Buy"])).firstMatch
                if confirm.exists && confirm.isHittable { sheetSeen = true; confirm.tap() }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let summary = "TAPS_TO_PURCHASE | \(entryPoint) | paywall after \(tapsToPaywall) | purchase after \(tapsToPaywall + 1) | StoreKit sheet seen: \(sheetSeen) | trial started: \(start.exists)"
        print(summary)
        let note = XCTAttachment(string: summary)
        note.name = "taps-\(entryPoint)"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertTrue(start.exists, "The purchase starts the trial (trial.start)")
        let done = app.buttons["paywall.continue"]
        XCTAssertTrue(done.waitForExistence(timeout: 4))
        done.tap()
        XCTAssertTrue(start.waitForNonExistence(timeout: 8), "The paywall closes")
    }
}
