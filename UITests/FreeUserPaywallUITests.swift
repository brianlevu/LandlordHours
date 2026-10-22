import XCTest

/// Free-to-paid journeys (Brian's release law): every Pro entry point is driven as a FREE
/// install. Each journey counts taps from Today to the paywall and to the purchase, checks the
/// locked preview says what stays free, that the paywall is about the thing tapped, that closing
/// it returns cleanly to the lock, and that after a purchase the action carries on.
///
/// Every journey prints a `TAPS_TO_PURCHASE | <entry> | paywall after N | purchase after N+1`
/// line and attaches it, so the release verifier can read taps-to-purchase per entry point.
final class FreeUserPaywallUITests: XCTestCase {
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

    // MARK: Journeys (one per entry point)

    func testReportsExportCardLock() {
        launchFree()
        tapTab("Reports")
        let lock = lockContainer("reports_export")
        scrollTo(lock, maxSwipes: 12)
        // The floating tab bar sits over the end of the scroll: bring the card clear of it.
        app.swipeUp(); app.swipeUp()
        assertLockSaysWhatStays(lock)
        let origin = lock.buttons["lock.unlock"]
        tap(origin)
        assertPaywall("export", headline: "The record your accountant gets")
        closeThenPurchase(entryPoint: "Reports > Export card", origin: origin,
                          continuation: exportReady)
    }

    func testReportsExportPageLock() {
        launchFree()
        tapTab("Reports")
        tap(app.buttons["reports.export"])
        let origin = exportPageUnlock()
        tap(origin)
        assertPaywall("export", headline: "The record your accountant gets")
        closeThenPurchase(entryPoint: "Reports > Export page", origin: origin,
                          continuation: exportReady, continuationIsLockLifted: true)
    }

    func testRecordsExportPageLock() {
        launchFree()
        tap(app.buttons["Records"].firstMatch)
        tap(app.buttons["records.export"])
        let origin = exportPageUnlock()
        tap(origin)
        assertPaywall("export", headline: "The record your accountant gets")
        closeThenPurchase(entryPoint: "Records > Export", origin: origin,
                          continuation: exportReady, continuationIsLockLifted: true)
    }

    func testSettingsExportRowLock() {
        launchFree()
        tapTab("Settings")
        let lock = lockContainer("settings_export")
        scrollTo(lock)
        assertLockSaysWhatStays(lock)
        let origin = lock.buttons["lock.unlock"]
        tap(origin)
        assertPaywall("export", headline: "The record your accountant gets")
        closeThenPurchase(entryPoint: "Settings > Export row", origin: origin, continuation: exportReady)
    }

    func testSettingsProCard() {
        launchFree()
        tapTab("Settings")
        let origin = app.buttons["settings.proCard"]
        scrollTo(origin)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay once")).firstMatch.exists,
                      "The card says it's paid once, with the App Store price")
        tap(origin)
        assertPaywall("settingsUpgrade", headline: "LandlordHours Pro")
        closeThenPurchase(entryPoint: "Settings > See Pro", origin: origin, continuation: nil)
    }

    func testPropertiesSecondRental() {
        launchFree()
        tap(app.buttons["Properties"].firstMatch)
        let lock = lockContainer("properties_limit")
        scrollTo(lock)
        assertLockSaysWhatStays(lock)
        let origin = lock.buttons["lock.unlock"]
        tap(origin)
        assertPaywall("secondProperty", headline: "Track every rental")
        closeThenPurchase(entryPoint: "Properties > Your next rental", origin: origin,
                          continuation: app.textFields["property.name"])
    }

    func testTodayYourRecordLock() {
        launchFree()
        let lock = lockContainer("today_record")
        scrollTo(lock, maxSwipes: 12)
        assertLockSaysWhatStays(lock)
        let origin = lock.buttons["lock.unlock"]
        scrollTo(origin, maxSwipes: 4)
        tap(origin)
        assertPaywall("dashboardUnlock", headline: "Your hours, on paper")
        closeThenPurchase(entryPoint: "Today > Your record", origin: origin,
                          continuation: exportReady)
    }

    func testInboxNewRentalAtTheFreeLimit() {
        launchInboxLimit()
        let row = app.buttons["inbox.row.cal:debug-limit-showing"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("New place"), "The row reads normally, with New place")
        tap(row)
        let line = app.descendants(matching: .any)["confirm.limitLine"]
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertTrue(line.label.contains("Pine Cabin keeps tracking"), "Says what stays active")
        let origin = app.buttons["confirm.unlockPro"]
        tap(origin)
        assertPaywall("secondProperty", headline: "Track every rental")
        closeThenPurchase(entryPoint: "Inbox > New place", origin: origin,
                          continuation: app.textFields["property.name"])
    }

    func testInboxKeepForProWaitsAndBacksOutCleanly() {
        launchInboxLimit()
        let row = app.buttons["inbox.row.cal:debug-limit-showing"]
        tap(row)
        // "Was this at Pine Cabin?" — the picker offers the user's rental and the locked new one.
        tap(app.buttons["confirm.property"])
        XCTAssertTrue(app.descendants(matching: .any)["limitPicker"].waitForExistence(timeout: 5))
        XCTAssertTrue(lockContainer("inbox_limit").exists, "A .row lock for the new rental")
        app.buttons["Close"].firstMatch.tap()
        tap(app.buttons["confirm.keepForPro"])
        XCTAssertTrue(app.staticTexts["Kept in your inbox"].waitForExistence(timeout: 4))
        let waiting = app.buttons["inbox.row.cal:debug-limit-showing"]
        XCTAssertTrue(waiting.waitForExistence(timeout: 4))
        XCTAssertTrue(waiting.label.contains("Waiting on Pro"), "Never expires silently")
    }

    func testAskToBuyShowsWaitingForApproval() {
        UITestIsolation.setAskToBuy(true)
        defer { UITestIsolation.setAskToBuy(false) }
        launchFree()
        tapTab("Settings")
        tap(app.buttons["settings.proCard"])
        buyWhenReady()
        let waiting = app.descendants(matching: .any)["paywall.askToBuy"]
        XCTAssertTrue(waiting.waitForExistence(timeout: 20), "Ask to Buy: waiting for approval")
        XCTAssertEqual(app.buttons["paywall.buy"].label, "Done", "The button becomes Done")
        app.buttons["paywall.buy"].tap()
        XCTAssertTrue(app.buttons["paywall.close"].waitForNonExistence(timeout: 6), "Done closes the paywall")
        XCTAssertTrue(app.buttons["settings.proCard"].waitForExistence(timeout: 5), "Still free until approval")
    }

    func testFailedPurchaseCanBeRetried() {
        UITestIsolation.setFailTransactions(true)
        launchFree()
        tapTab("Settings")
        tap(app.buttons["settings.proCard"])
        buyWhenReady()
        XCTAssertTrue(app.descendants(matching: .any)["paywall.failed"].waitForExistence(timeout: 20), "That didn't go through")
        UITestIsolation.setFailTransactions(false)
        buyWhenReady()
        XCTAssertTrue(app.descendants(matching: .any)["paywall.success"].waitForExistence(timeout: 30), "Retry succeeds")
    }

    func testOnboardingEndsWithoutAPaywall() {
        app.launchArguments = baseArguments(scenario: "firstTime", tab: 0, scheme: "light")
        app.launch()
        walkOnboarding(captureScheme: "light")
    }

    // MARK: Helpers

    private func baseArguments(scenario: String, tab: Int, scheme: String) -> [String] {
        [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", scenario,
            "-LHInitialTab", "\(tab)",
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
    }

    private func launchFree(scheme: String = "light") {
        app.terminate()
        app.launchArguments = baseArguments(scenario: "occasional", tab: 0, scheme: scheme)
        app.launch()
        taps = 0
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 12), "Home tab bar should load")
    }

    private func launchInboxLimit() {
        app.terminate()
        app.launchArguments = baseArguments(scenario: "emptyMainTabs", tab: 0, scheme: "light")
            + ["-LHSeedSuggestions", "limit"]
        app.launch()
        taps = 0
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 12))
        tap(app.buttons["Inbox"].firstMatch)
    }

    /// Reports and Settings are reached from Today's header buttons; each is one tap.
    private func tapTab(_ title: String) {
        let label: String
        switch title {
        case "Reports": label = "Open reports"
        case "Settings": label = "Open profile and settings"
        default: label = title
        }
        tap(app.buttons[label].firstMatch)
    }

    /// The unlocked Export page: create (or, when it already ran, share) the report.
    private var exportReady: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier IN %@", ["export.generatePDF", "export.sharePDF"])).firstMatch
    }

    private func lockContainer(_ entry: String) -> XCUIElement {
        app.descendants(matching: .any)["lock.\(entry)"].firstMatch
    }

    private func exportPageUnlock() -> XCUIElement {
        let lock = lockContainer("export_page")
        XCTAssertTrue(lock.waitForExistence(timeout: 8), "The export page is a locked preview for a free user")
        assertLockSaysWhatStays(lock)
        let unlock = lock.buttons["lock.unlock"]
        scrollTo(unlock, maxSwipes: 4)
        return unlock
    }

    private func assertLockSaysWhatStays(_ lock: XCUIElement) {
        XCTAssertTrue(lock.waitForExistence(timeout: 8), "Lock missing")
        XCTAssertTrue(lock.descendants(matching: .any)["lock.line"].exists, "One line says what is locked")
        XCTAssertTrue(lock.descendants(matching: .any)["lock.keeps"].exists, "One line says what stays free")
        XCTAssertTrue(lock.buttons["lock.unlock"].exists, "One Unlock Pro action")
        XCTAssertEqual(lock.buttons["lock.unlock"].label, "Unlock Pro")
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), "Missing \(element)", file: file, line: line)
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 5), .completed, "Not hittable: \(element)", file: file, line: line)
        element.tap()
        taps += 1
    }

    private func assertPaywall(_ context: String, headline: String) {
        let paywall = app.descendants(matching: .any)["paywall.\(context)"]
        XCTAssertTrue(paywall.waitForExistence(timeout: 8), "Paywall for \(context) should appear")
        let title = app.staticTexts["paywall.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertEqual(title.label, headline, "The paywall speaks to \(context)")
        XCTAssertTrue(app.buttons["paywall.buy"].exists, "Unlock button")
        XCTAssertTrue(app.buttons["paywall.restore"].exists, "Restore purchase sits under the buy button")
        XCTAssertTrue(app.buttons["paywall.terms"].isHittable && app.buttons["paywall.privacy"].isHittable, "Terms and Privacy are visible and tappable")
        let buy = app.buttons["paywall.buy"].frame
        let restore = app.buttons["paywall.restore"].frame
        XCTAssertGreaterThan(restore.minY, buy.minY, "Restore is below the buy button")
        XCTAssertLessThan(restore.minY - buy.maxY, 40, "Restore is directly under the buy button")
    }

    /// 1. Close returns cleanly to the lock. 2. Reopen and buy: logs taps from Today.
    /// 3. "Pro is yours", then the next-step button carries on with what the user was doing.
    private func closeThenPurchase(entryPoint: String, origin: XCUIElement, continuation: XCUIElement?,
                                   continuationIsLockLifted: Bool = false) {
        let tapsToPaywall = taps
        let close = app.buttons["paywall.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 6), "Paywall closes cleanly")
        XCTAssertTrue(origin.waitForExistence(timeout: 5), "Back at the lock")
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: origin)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 5), .completed, "The lock is usable again after close")

        origin.tap()
        XCTAssertTrue(app.staticTexts["paywall.title"].waitForExistence(timeout: 8), "Paywall reopens")
        XCTAssertTrue(app.descendants(matching: .any)["paywall.price"].waitForExistence(timeout: 12), "Price from StoreKit")
        let buy = app.buttons["paywall.buy"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true AND isHittable == true"), object: buy)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 15), .completed, "Unlock is ready")
        buy.tap()

        var sheetSeen = false
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let confirmLabels = ["Purchase", "Buy", "Confirm", "Subscribe"]
        let success = app.descendants(matching: .any)["paywall.success"]
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if success.exists { break }
            if !sheetSeen {
                for candidate in [app!, springboard] {
                    let confirm = candidate.buttons.matching(NSPredicate(format: "label IN %@", confirmLabels)).firstMatch
                    if confirm.exists && confirm.isHittable { sheetSeen = true; confirm.tap(); break }
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let summary = "TAPS_TO_PURCHASE | \(entryPoint) | paywall after \(tapsToPaywall) | purchase after \(tapsToPaywall + 1) | StoreKit sheet seen: \(sheetSeen) | Pro is yours: \(success.exists)"
        print(summary)
        let note = XCTAttachment(string: summary)
        note.name = "taps-\(entryPoint)"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertTrue(success.exists, "Purchase shows Pro is yours")

        let next = app.buttons["paywall.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 4), "The button becomes the next step")
        next.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 8), "Paywall closes after the next step")
        if continuationIsLockLifted {
            XCTAssertTrue(origin.waitForNonExistence(timeout: 6), "The blur lifts: the lock is gone")
        }
        if let continuation {
            XCTAssertTrue(continuation.waitForExistence(timeout: 10), "Continues to \(continuation)")
        }
    }

    private func buyWhenReady() {
        XCTAssertTrue(app.descendants(matching: .any)["paywall.price"].waitForExistence(timeout: 12), "Price from StoreKit")
        let buy = app.buttons["paywall.buy"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true AND isHittable == true"), object: buy)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 15), .completed)
        buy.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            let confirm = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["Purchase", "Buy", "Confirm"])).firstMatch
            if confirm.exists && confirm.isHittable { confirm.tap(); break }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while (!element.exists || !element.isHittable || isUnderTabBar(element)) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3), "Could not reach \(element)")
    }

    /// The floating tab bar is an overlay the accessibility tree still calls hittable through, so a tap
    /// on a lock sitting under it lands on a tab (Today's "Your record" sits last, right above it).
    private func isUnderTabBar(_ element: XCUIElement) -> Bool {
        let tabBar = app.buttons["tab.today"]
        guard element.exists, tabBar.exists, tabBar.isHittable else { return false }
        return element.frame.maxY > tabBar.frame.minY - 8
    }

    /// 2.0 onboarding, the quickest way through: no calendar, no property (six taps to Today).
    private func walkOnboarding(captureScheme scheme: String) {
        tap(app.buttons["onb-start"])
        UITestIsolation.answerGoalQuestions(app)
        tap(app.buttons["onb-primary"])                        // Aim for 750 hours
        tap(app.buttons["onb-link"])                           // Calendar: Not now
        tap(app.buttons["onb-primary"])                        // Who: Continue
        // No paywall step anywhere in onboarding.
        XCTAssertFalse(app.descendants(matching: .any)["paywall.title"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "lifetime")).firstMatch.exists)
        XCTAssertTrue(app.buttons["onb-link"].waitForExistence(timeout: 6))
        settleAndCapture("onboarding-last-step", scheme: scheme, waitFor: app.buttons["onb-link"])
        tap(app.buttons["onb-link"])                           // I’ll add it later
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 10), "Onboarding lands on the app, not a paywall")
        XCTAssertFalse(app.descendants(matching: .any)["paywall.title"].exists)
        settleAndCapture("onboarding-finished-home", scheme: scheme, waitFor: app.buttons["tab.today"])
    }

    private func capturePaywall(_ name: String, scheme: String) {
        XCTAssertTrue(app.staticTexts["paywall.title"].waitForExistence(timeout: 8), "\(name): paywall missing")
        // The price comes from StoreKit; give it time, but capture either way.
        _ = app.descendants(matching: .any)["paywall.price"].waitForExistence(timeout: 8)
        settleAndCapture(name, scheme: scheme, waitFor: app.staticTexts["paywall.title"])
    }

    private func settleAndCapture(_ name: String, scheme: String, waitFor element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(name): \(element) never appeared")
        Thread.sleep(forTimeInterval: 1.0)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(name)-\(scheme)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
