import XCTest

/// Free-to-paid journeys (Brian's release law): every Pro entry point is driven as a FREE
/// install. Each test counts taps from Home to the StoreKit sheet, asserts the paywall is
/// about the thing tapped, and that closing it returns cleanly to where the user was.
///
/// Free fixture: `-LHMockScenario occasional` (one or more properties, entries, no Pro).
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

    // MARK: Journeys

    func testReportsExportOpensExportPaywall() {
        launchFree()
        tapTab("Reports")
        let origin = app.buttons["reports.export"]
        tap(origin)
        assertPaywall("export", titleContains: "Export your")
        closeThenPurchase(entryPoint: "Reports > Export", origin: origin,
                          continuation: app.buttons["export.generatePDF"])
    }

    func testAddSecondPropertyOpensPropertyPaywall() {
        launchFree()
        tapTab("Properties")
        let origin = app.buttons["properties.add"]
        tap(origin)
        assertPaywall("secondProperty", titleContains: "Track every rental")
        closeThenPurchase(entryPoint: "Properties > Add property", origin: origin,
                          continuation: app.textFields["property.name"])
    }

    func testDashboardNudgeOpensGenericPaywall() {
        launchFree()
        let nudge = app.buttons["dashboard.unlockPro"]
        scrollTo(nudge)
        tap(nudge)
        assertPaywall("dashboardUnlock", titleContains: "every rental")
        closeThenPurchase(entryPoint: "Home > Unlock Pro card", origin: nudge, continuation: nil)
    }

    func testSettingsProCardOpensGenericPaywall() {
        launchFree()
        tapTab("Settings")
        let origin = app.buttons["settings.proCard"]
        tap(origin)
        assertPaywall("settingsUpgrade", titleContains: "LandlordHours Pro")
        closeThenPurchase(entryPoint: "Settings > Pro card", origin: origin, continuation: nil)
    }

    func testSettingsExportRowOpensExportPaywall() {
        launchFree()
        tapTab("Settings")
        let row = app.buttons["settings.exportReportsLocked"]
        scrollTo(row)
        tap(row)
        assertPaywall("export", titleContains: "Export your")
        closeThenPurchase(entryPoint: "Settings > Export Reports", origin: row,
                          continuation: app.buttons["export.generatePDF"])
    }

    func testOnboardingEndsWithoutAPaywall() {
        app.launchArguments = baseArguments(scenario: "firstTime", tab: 0, scheme: "light")
        app.launch()
        walkOnboarding(captureScheme: "light")
    }

    // MARK: Frames for the visual gate

    func testCaptureLaneCFramesLight() { captureAll(scheme: "light") }
    func testCaptureLaneCFramesDark() { captureAll(scheme: "dark") }

    private func captureAll(scheme: String) {
        // Paywall from each context.
        launchFree(scheme: scheme)
        tapTab("Reports")
        tap(app.buttons["reports.export"])
        capturePaywall("paywall-export", scheme: scheme)

        launchFree(scheme: scheme)
        tapTab("Properties")
        tap(app.buttons["properties.add"])
        capturePaywall("paywall-secondProperty", scheme: scheme)

        launchFree(scheme: scheme)
        let nudge = app.buttons["dashboard.unlockPro"]
        scrollTo(nudge)
        tap(nudge)
        capturePaywall("paywall-dashboardUnlock", scheme: scheme)

        launchFree(scheme: scheme)
        tapTab("Settings")
        let exportRow = app.buttons["settings.exportReportsLocked"]
        scrollTo(exportRow)
        tap(exportRow)
        capturePaywall("paywall-settingsExport", scheme: scheme)

        launchFree(scheme: scheme)
        tapTab("Settings")
        tap(app.buttons["settings.proCard"])
        capturePaywall("paywall-settingsUpgrade", scheme: scheme)

        // Settings disclaimer.
        launchFree(scheme: scheme)
        tapTab("Settings")
        let note = app.descendants(matching: .any)["settings.notTaxAdvice"].firstMatch
        scrollTo(note, maxSwipes: 14)
        app.swipeUp()
        settleAndCapture("settings-not-tax-advice", scheme: scheme, waitFor: note)

        // Dashboard: REPS goal, 750 h met, other work hours not entered.
        app.terminate()
        app.launchArguments = baseArguments(scenario: "frequent", tab: 0, scheme: scheme) + ["-LHOtherWorkHours", "0"]
        app.launch()
        // The progress card combines its children for VoiceOver, so match the prompt text.
        let metric = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Add your other work hours to check this")).firstMatch
        XCTAssertTrue(metric.waitForExistence(timeout: 12), "Dashboard asks for other work hours")
        settleAndCapture("dashboard-add-other-work-hours", scheme: scheme, waitFor: metric)

        // Onboarding end.
        app.terminate()
        app.launchArguments = baseArguments(scenario: "firstTime", tab: 0, scheme: scheme)
        app.launch()
        walkOnboarding(captureScheme: scheme)
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

    /// Today, Inbox, Records and Properties live in the tab bar (Log time is the round +);
    /// Reports and Settings are reached from Today's header buttons. Each is one tap from Today.
    private func tapTab(_ title: String) {
        let label: String
        switch title {
        case "Reports": label = "Open reports"
        case "Settings": label = "Open profile and settings"
        default: label = title
        }
        tap(app.buttons[label])
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), "Missing \(element)", file: file, line: line)
        let hittable = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: hittable, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed, "Not hittable: \(element)", file: file, line: line)
        element.tap()
        taps += 1
    }

    private func assertPaywall(_ context: String, titleContains: String) {
        let paywall = app.descendants(matching: .any)["paywall.\(context)"]
        XCTAssertTrue(paywall.waitForExistence(timeout: 8), "Paywall for \(context) should appear")
        let title = app.staticTexts["paywall.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertTrue(title.label.contains(titleContains), "Title '\(title.label)' should speak to \(context)")
        XCTAssertTrue(app.buttons["paywall.buy"].exists, "Unlock Pro button")
        XCTAssertTrue(app.buttons["paywall.restore"].exists, "Restore purchases sits under the buy button")
        let buyFrame = app.buttons["paywall.buy"].frame
        let restoreFrame = app.buttons["paywall.restore"].frame
        XCTAssertGreaterThan(restoreFrame.minY, buyFrame.minY, "Restore is below Unlock Pro")
        XCTAssertLessThan(restoreFrame.minY - buyFrame.maxY, 40, "Restore is directly under Unlock Pro")
    }

    /// 1. Close returns cleanly to where the user was.
    /// 2. Reopen, tap Unlock Pro: logs taps from Home to the purchase step.
    /// 3. After purchase the paywall shows "Pro is active" and carries on with the action.
    private func closeThenPurchase(entryPoint: String, origin: XCUIElement, continuation: XCUIElement?) {
        let tapsToPaywall = taps
        let close = app.buttons["paywall.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 6), "Paywall closes cleanly")
        XCTAssertTrue(origin.waitForExistence(timeout: 5), "Back where the user started")
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: origin)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 5), .completed, "Origin is usable again after close")

        origin.tap()
        XCTAssertTrue(app.staticTexts["paywall.title"].waitForExistence(timeout: 8), "Paywall reopens")
        let priceLoaded = app.descendants(matching: .any)["paywall.price"].waitForExistence(timeout: 10)
        XCTAssertTrue(priceLoaded, "$29.99 from the StoreKit config is shown")
        app.buttons["paywall.buy"].tap()

        // Local StoreKit testing may show its confirm sheet or complete straight away, and
        // "Pro is active" shows for about a second before the sheet carries on: watch both.
        var sheetSeen = false
        var sawActive = false
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let confirmLabels = ["Purchase", "Buy", "Confirm", "Subscribe"]
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if app.staticTexts["Pro is active"].exists { sawActive = true; break }
            if !sheetSeen {
                for candidate in [app!, springboard] {
                    let buy = candidate.buttons.matching(NSPredicate(format: "label IN %@", confirmLabels)).firstMatch
                    if buy.exists && buy.isHittable { sheetSeen = true; buy.tap(); break }
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "after-purchase-\(entryPoint)"
        shot.lifetime = .keepAlways
        add(shot)

        let summary = "TAPS_TO_PURCHASE | \(entryPoint) | paywall after \(tapsToPaywall) | purchase after \(tapsToPaywall + 1) | StoreKit sheet seen: \(sheetSeen) | Pro is active: \(sawActive)"
        print(summary)
        let note = XCTAttachment(string: summary)
        note.name = "taps-\(entryPoint)"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertTrue(sawActive, "Purchase shows the Pro is active state")

        // The sheet carries on by itself with what the user was doing.
        XCTAssertTrue(close.waitForNonExistence(timeout: 8), "Paywall dismisses after purchase")
        if let continuation {
            XCTAssertTrue(continuation.waitForExistence(timeout: 8), "Continues to \(continuation)")
        }
    }

    private func waitForStoreKitSheet() -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            for candidate in [app!, springboard] {
                let buy = candidate.buttons.matching(NSPredicate(format: "label IN %@", ["Purchase", "Buy", "Confirm", "Subscribe"])).firstMatch
                if buy.exists { return true }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    private func confirmStoreKitSheet() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for candidate in [app!, springboard] {
            for label in ["Purchase", "Buy", "Confirm", "OK"] {
                let button = candidate.buttons[label]
                if button.exists && button.isHittable {
                    button.tap()
                    return
                }
            }
        }
    }

    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while (!element.exists || !element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3), "Could not reach \(element)")
    }

    private func walkOnboarding(captureScheme scheme: String) {
        tap(app.buttons["onboarding.goalPrimaryCTA"])
        tap(app.buttons["onboarding.propertyPrimaryCTA"])
        // Straight from property to reminders: no paywall step in between.
        XCTAssertTrue(app.buttons["Allow reminders"].waitForExistence(timeout: 6), "Reminders follow property setup")
        XCTAssertFalse(app.descendants(matching: .any)["paywall.title"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "lifetime")).firstMatch.exists)
        tap(app.buttons["Skip for now"])
        XCTAssertTrue(app.buttons["Connect Calendar"].waitForExistence(timeout: 6))
        settleAndCapture("onboarding-last-step", scheme: scheme, waitFor: app.buttons["Connect Calendar"])
        tap(app.buttons["Skip for now"])
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
