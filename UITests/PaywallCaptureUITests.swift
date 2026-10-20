import XCTest

/// Frames for the visual gate: every paywall state and every lock, light and dark, at the
/// default text size, XXL and AX3. PNGs go straight to the host's
/// `~/AgentScratch/landlordhours/<LH_CAPTURE_DATE or 2026-10-19>/paywall-prod-frames-r2/raw/`.
/// Run with `-only-testing:LandlordHoursUITests/PaywallCaptureUITests`.
final class PaywallCaptureUITests: XCTestCase {
    private var app: XCUIApplication!

    private static let sizes: [(String, String?)] = [
        ("default", nil),
        ("xxl", "UICTContentSizeCategoryXXL"),
        ("ax3", "UICTContentSizeCategoryAccessibilityXL"),
    ]
    private static let schemes = ["light", "dark"]

    override func setUp() {
        super.setUp()
        UITestIsolation.resetStoreKit()
        continueAfterFailure = true
        app = XCUIApplication()
    }

    private var outDir: URL {
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSHomeDirectory()
        let date = ProcessInfo.processInfo.environment["LH_CAPTURE_DATE"] ?? "2026-10-19"
        let url = URL(fileURLWithPath: home)
            .appendingPathComponent("AgentScratch/landlordhours/\(date)/paywall-prod-frames-r2/raw", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Paywall states

    private static let paywallStates: [(name: String, args: [String])] = [
        ("paywall-export", ["-LHPaywallPreview", "export"]),
        ("paywall-export-below", ["-LHPaywallPreview", "export", "-LHPaywallBelowFold"]),
        ("paywall-second", ["-LHPaywallPreview", "secondProperty", "-LHPaywallProperty", "Pine Cabin"]),
        ("paywall-today", ["-LHPaywallPreview", "todayUnlock", "-LHPaywallHours", "14.5"]),
        ("paywall-settings", ["-LHPaywallPreview", "settings"]),
        ("paywall-sample", ["-LHPaywallPreview", "export", "-LHPaywallSample"]),
        ("paywall-pageloading", ["-LHPaywallPreview", "export", "-LHPaywallPageLoading"]),
        ("paywall-price-loading", ["-LHPaywallPreview", "export", "-LHPaywallPhase", "priceLoading"]),
        ("paywall-price-failed", ["-LHPaywallPreview", "export", "-LHPaywallPhase", "priceFailed"]),
        ("paywall-buying", ["-LHPaywallPreview", "export", "-LHPaywallPhase", "buying"]),
        ("paywall-asktobuy", ["-LHPaywallPreview", "export", "-LHPaywallPhase", "askToBuy"]),
        ("paywall-failed", ["-LHPaywallPreview", "export", "-LHPaywallPhase", "failed"]),
        ("paywall-success", ["-LHPaywallPreview", "export", "-LHPaywallPhase", "success"]),
        ("paywall-success-second", ["-LHPaywallPreview", "secondProperty", "-LHPaywallProperty", "Pine Cabin", "-LHPaywallPhase", "success"]),
        ("paywall-restoring", ["-LHPaywallPreview", "settings", "-LHPaywallPhase", "restoring"]),
        ("paywall-restore-none", ["-LHPaywallPreview", "settings", "-LHPaywallPhase", "restoreNone"]),
    ]

    func testCapturePaywallStates() {
        for state in Self.paywallStates {
            for (sizeName, size) in Self.sizes {
                for scheme in Self.schemes {
                    launch(scenario: "occasional", scheme: scheme, size: size, extra: state.args)
                    let title = app.staticTexts["paywall.title"]
                    XCTAssertTrue(title.waitForExistence(timeout: 12), "\(state.name): paywall missing")
                    Thread.sleep(forTimeInterval: state.name.contains("below") ? 2.0 : 1.4)
                    // Large sizes push a state's status line below the fold: bring it into view
                    // so every state is captured for real (the r1 gate found identical frames).
                    for id in ["paywall.restoreNone", "paywall.failed", "paywall.askToBuy", "paywall.priceFailed", "paywall.success"] {
                        let status = app.descendants(matching: .any)[id].firstMatch
                        var swipes = 0
                        while status.exists && !status.isHittable && swipes < 4 { app.swipeUp(velocity: .slow); swipes += 1 }
                        if swipes > 0 { Thread.sleep(forTimeInterval: 0.8) }
                    }
                    save("\(state.name)-\(scheme)-\(sizeName)")
                }
            }
        }
    }

    /// The status band follows the scroll: blueprint over the hero, canvas below it.
    func testStatusBandFollowsScroll() {
        launch(scenario: "occasional", scheme: "light", size: "UICTContentSizeCategoryXXL", extra: ["-LHPaywallPreview", "export"])
        XCTAssertTrue(app.staticTexts["paywall.title"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.descendants(matching: .any)["paywall.band.hero"].waitForExistence(timeout: 3), "Blue band over the hero")
        app.swipeUp(velocity: .fast); app.swipeUp(velocity: .fast)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(app.descendants(matching: .any)["paywall.band.canvas"].waitForExistence(timeout: 3), "Canvas band once scrolled past the hero")
        app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.descendants(matching: .any)["paywall.band.hero"].waitForExistence(timeout: 3), "Blue again at the top")
    }

    /// Properties at the free limit: the shared `.row` lock (entry properties_limit).
    func testCapturePropertiesLock() {
        for (sizeName, size) in Self.sizes {
            for scheme in Self.schemes {
                launch(scenario: "occasional", scheme: scheme, size: size)
                tapButton("Properties")
                scrollTo("lock.properties_limit")
                save("lock-properties-\(scheme)-\(sizeName)")
            }
        }
    }

    // MARK: Locks

    func testCaptureLocks() {
        for (sizeName, size) in Self.sizes {
            for scheme in Self.schemes {
                let suffix = "\(scheme)-\(sizeName)"

                launch(scenario: "occasional", scheme: scheme, size: size)
                tapButton("Open reports")
                tapButton("reports.export")
                waitFor("lock.export_page")
                save("lock-export-\(suffix)")

                launch(scenario: "occasional", scheme: scheme, size: size)
                tapButton("Open reports")
                scrollTo("lock.reports_export")
                save("lock-reports-\(suffix)")

                launch(scenario: "occasional", scheme: scheme, size: size)
                scrollTo("lock.today_record")
                save("lock-today-record-\(suffix)")

                launch(scenario: "occasional", scheme: scheme, size: size)
                tapButton("Open profile and settings")
                waitFor("settings.proCard")
                save("lock-settings-\(suffix)")

                launch(scenario: "emptyMainTabs", scheme: scheme, size: size, extra: ["-LHSeedSuggestions", "limit"])
                tapButton("Inbox")
                waitFor("inbox.row.cal:debug-limit-showing")
                save("limit-row-\(suffix)")
                app.buttons["inbox.row.cal:debug-limit-showing"].tap()
                waitFor("confirm.unlockPro")
                Thread.sleep(forTimeInterval: 0.8)
                save("limit-sheet-\(suffix)")
                // At AX sizes the pinned "Unlock Pro" covers the lower sheet: scroll the Property
                // row clear of it before tapping.
                let property = app.buttons["confirm.property"]
                let pinned = app.buttons["confirm.unlockPro"]
                var swipes = 0
                while (!property.isHittable || property.frame.maxY > pinned.frame.minY - 8) && swipes < 8 {
                    app.descendants(matching: .any)["confirm.sheet"].firstMatch.swipeUp(velocity: .slow)
                    swipes += 1
                }
                property.tap()
                waitFor("limitPicker")
                Thread.sleep(forTimeInterval: 0.8)
                save("limit-picker-\(suffix)")

                // The full-width Inbox toast inside the at-limit flow ("Keep it in my inbox").
                app.terminate()
                launch(scenario: "emptyMainTabs", scheme: scheme, size: size, extra: ["-LHSeedSuggestions", "limit"])
                tapButton("Inbox")
                waitFor("inbox.row.cal:debug-limit-showing")
                app.buttons["inbox.row.cal:debug-limit-showing"].tap()
                let keep = app.buttons["confirm.keepForPro"]
                var tries = 0
                while !keep.isHittable && tries < 6 { app.swipeUp(velocity: .slow); tries += 1 }
                keep.tap()
                XCTAssertTrue(app.descendants(matching: .any)["inbox.toast"].waitForExistence(timeout: 5), "toast")
                Thread.sleep(forTimeInterval: 0.6)
                save("limit-toast-\(suffix)")
                // Then "Not rental work" from the same at-limit sheet.
                Thread.sleep(forTimeInterval: 5.5)
                app.buttons["inbox.row.cal:debug-limit-showing"].tap()
                let notWork = app.buttons["confirm.dismiss"]
                tries = 0
                while !notWork.isHittable && tries < 6 { app.swipeUp(velocity: .slow); tries += 1 }
                notWork.tap()
                XCTAssertTrue(app.staticTexts["Marked not rental work"].waitForExistence(timeout: 5), "rental-work toast")
                Thread.sleep(forTimeInterval: 0.6)
                save("limit-toast-notwork-\(suffix)")

                launch(scenario: "emptyMainTabs", scheme: scheme, size: size, extra: ["-LHSeedSuggestions", "limit-waiting"])
                tapButton("Inbox")
                waitFor("inbox.row.cal:debug-limit-showing")
                save("limit-waiting-\(suffix)")
            }
        }
    }

    // MARK: Helpers

    private func launch(scenario: String, scheme: String, size: String?, extra: [String] = []) {
        app.terminate()
        var args = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", scenario,
            "-LHInitialTab", "0",
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-LHFixedNow", "2026-10-19T09:41",
        ]
        if let size { args += ["-UIPreferredContentSizeCategoryName", size] }
        app.launchArguments = args + extra
        app.launch()
        _ = app.buttons["tab.today"].waitForExistence(timeout: 12)
    }

    private func element(_ id: String) -> XCUIElement {
        let button = app.buttons[id].firstMatch
        return button.exists ? button : app.descendants(matching: .any)[id].firstMatch
    }

    private func tapButton(_ id: String) {
        let target = app.buttons[id].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 8), "Missing \(id)")
        target.tap()
    }

    private func waitFor(_ id: String) {
        XCTAssertTrue(app.descendants(matching: .any)[id].firstMatch.waitForExistence(timeout: 10), "Missing \(id)")
        Thread.sleep(forTimeInterval: 1.0)
    }

    private func scrollTo(_ id: String) {
        let target = app.descendants(matching: .any)[id].firstMatch
        var swipes = 0
        while (!target.exists || !target.isHittable) && swipes < 14 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        let unlock = target.buttons["lock.unlock"].firstMatch
        if unlock.exists && !unlock.isHittable { app.swipeUp(velocity: .slow) }
        Thread.sleep(forTimeInterval: 1.0)
    }

    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: outDir.appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
