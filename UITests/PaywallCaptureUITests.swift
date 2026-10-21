import XCTest

/// Frames for the visual gate: every paywall state and every lock, light and dark, at the
/// default text size, XXL and AX3. PNGs go straight to the host's
/// `~/AgentScratch/landlordhours/<LH_CAPTURE_DATE or 2026-10-19>/paywall-prod-frames-r3/raw/`.
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
            .appendingPathComponent("AgentScratch/landlordhours/\(date)/paywall-prod-frames-r3/raw", isDirectory: true)
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

    // MARK: r3: only the frames whose states changed

    /// The lock's "Unlock Pro" must end fully above the floating tab bar (or the sheet's bottom
    /// edge) at full opacity: scroll until it does, assert it, then capture.
    private func scrollUnlockClear(_ lockID: String) {
        let unlock = app.descendants(matching: .any)[lockID].firstMatch.buttons["lock.unlock"].firstMatch
        let tabBar = app.buttons["tab.today"]
        func clearLine() -> CGFloat {
            tabBar.exists && tabBar.isHittable ? tabBar.frame.minY - 12 : app.frame.maxY - 40
        }
        var swipes = 0
        while (!unlock.exists || !unlock.isHittable || unlock.frame.maxY > clearLine()) && swipes < 14 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(unlock.exists && unlock.frame.maxY <= clearLine(), "\(lockID): Unlock Pro clears the tab bar / sheet edge")
    }

    func testCaptureR3ChangedFrames() {
        for scheme in Self.schemes {
            // AX3: each lock scrolled so its Unlock Pro sits clear and at full opacity.
            let ax3 = "UICTContentSizeCategoryAccessibilityXL"
            launch(scenario: "occasional", scheme: scheme, size: ax3)
            tapButton("Properties")
            scrollUnlockClear("lock.properties_limit")
            save("lock-properties-\(scheme)-ax3")

            launch(scenario: "occasional", scheme: scheme, size: ax3)
            scrollUnlockClear("lock.today_record")
            save("lock-today-record-\(scheme)-ax3")

            launch(scenario: "occasional", scheme: scheme, size: ax3)
            tapButton("Open reports")
            scrollUnlockClear("lock.reports_export")
            save("lock-reports-\(scheme)-ax3")

            for (sizeName, size) in Self.sizes {
                // Export page: the PREVIEW stamp over the blur; at AX3 also scrolled to the CTA.
                launch(scenario: "occasional", scheme: scheme, size: size)
                tapButton("Open reports")
                tapButton("reports.export")
                waitFor("lock.export_page")
                save("lock-export-\(scheme)-\(sizeName)")
                if sizeName == "ax3" {
                    scrollUnlockClear("lock.export_page")
                    save("lock-export-\(scheme)-ax3-bottom")
                }

                // Sample page: the stamp sits in the page header.
                launch(scenario: "occasional", scheme: scheme, size: size, extra: ["-LHPaywallPreview", "export", "-LHPaywallSample"])
                XCTAssertTrue(app.staticTexts["paywall.title"].waitForExistence(timeout: 12))
                Thread.sleep(forTimeInterval: 1.4)
                save("paywall-sample-\(scheme)-\(sizeName)")
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

    // MARK: Restore that fails (DEBUG -LHRestoreOutcome)

    private var restoreOutDir: URL {
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSHomeDirectory()
        let date = ProcessInfo.processInfo.environment["LH_CAPTURE_DATE"] ?? "2026-10-22"
        let url = URL(fileURLWithPath: home)
            .appendingPathComponent("AgentScratch/landlordhours/\(date)/storekit-frames-r2", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The paywall and Settings after a restore that timed out or failed, light and dark, at the
    /// default size and AX3. Restore is tapped for real; only the App Store call is forced to fail.
    /// Each frame also proves the retry: the Restore control is enabled again afterwards.
    func testCaptureRestoreFailureStates() {
        let restoreSizes = Self.sizes.filter { $0.0 != "xxl" }
        for outcome in ["timeout", "failure"] {
            for (sizeName, size) in restoreSizes {
                for scheme in Self.schemes {
                    let suffix = "\(outcome)-\(scheme)-\(sizeName)"

                    // Paywall (Settings entry).
                    launch(scenario: "occasional", scheme: scheme, size: size,
                           extra: ["-LHPaywallPreview", "settings", "-LHRestoreOutcome", outcome])
                    XCTAssertTrue(app.staticTexts["paywall.title"].waitForExistence(timeout: 12), "\(suffix): paywall missing")
                    scrollTo("paywall.restore")
                    let restore = app.buttons["paywall.restore"].firstMatch
                    restore.tap()
                    let message = app.descendants(matching: .any)["paywall.restoreNone"].firstMatch
                    XCTAssertTrue(message.waitForExistence(timeout: 10), "\(suffix): no restore message")
                    scrollTo("paywall.restoreNone")
                    Thread.sleep(forTimeInterval: 0.8)
                    XCTAssertTrue(restore.isEnabled, "\(suffix): Restore can be tried again")
                    XCTAssertTrue(message.label.hasPrefix(outcome == "timeout" ? "The App Store didn't answer" : "Couldn't reach the App Store"),
                                  "\(suffix): wrong message '\(message.label)'")
                    save("paywall-restore-\(suffix)")
                    // Scrolled: body text passes the close button's row; nothing may sit under it.
                    app.swipeUp(velocity: .slow); app.swipeUp(velocity: .slow)
                    Thread.sleep(forTimeInterval: 0.6)
                    save("paywall-restore-\(suffix)-scrolled")

                    // Settings.
                    launch(scenario: "occasional", scheme: scheme, size: size, extra: ["-LHRestoreOutcome", outcome])
                    // Two controls carry this label (the AX header has its own); tap the visible one.
                    let openSettings = app.buttons.matching(NSPredicate(format: "label == %@", "Open profile and settings"))
                    XCTAssertTrue(openSettings.firstMatch.waitForExistence(timeout: 8), "\(suffix): no Settings entry")
                    let visible = openSettings.allElementsBoundByIndex.first { $0.isHittable } ?? openSettings.firstMatch
                    visible.tap()
                    XCTAssertTrue(app.descendants(matching: .any)["settings.profile"].waitForExistence(timeout: 10), "\(suffix): Settings did not open")
                    scrollTo("settings.restorePurchase")
                    let row = app.buttons["settings.restorePurchase"].firstMatch
                    // At AX3 the row can sit under the floating tab bar; lift it clear before tapping.
                    let tabBar = app.buttons["tab.today"]
                    var lifts = 0
                    while tabBar.exists && row.frame.maxY > tabBar.frame.minY - 12 && lifts < 6 {
                        app.swipeUp(velocity: .slow); lifts += 1
                    }
                    row.tap()
                    // The result shows inline under the row; the row stays tappable to retry.
                    let expected = outcome == "timeout" ? "The App Store didn't answer" : "Couldn't reach the App Store"
                    let shown = NSPredicate(format: "label CONTAINS %@", expected)
                    XCTAssertTrue(app.descendants(matching: .any).matching(shown).firstMatch.waitForExistence(timeout: 10),
                                  "\(suffix): no inline restore message")
                    XCTAssertFalse(app.alerts.firstMatch.exists, "\(suffix): no system alert")
                    var settle = 0
                    while tabBar.exists && row.frame.maxY > tabBar.frame.minY - 12 && settle < 4 {
                        app.swipeUp(velocity: .slow); settle += 1
                    }
                    Thread.sleep(forTimeInterval: 0.8)
                    XCTAssertTrue(row.isEnabled, "\(suffix): Restore can be tried again")
                    save("settings-restore-\(suffix)")
                }
            }
        }
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
        let dir = name.contains("-restore-") ? restoreOutDir : outDir
        try? shot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
