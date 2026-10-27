import XCTest

/// 2.0 Properties: journeys (free limit → paywall, delete with Cancel) and capture frames for
/// every state in light/dark at the default size, XXL and AX3. Frames go to `LH_CAPTURE_DIR`
/// when the runner gets it (`TEST_RUNNER_LH_CAPTURE_DIR=<dir>`).
final class PropertiesUITests: XCTestCase {
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

    // MARK: Journeys

    /// Two rentals on a free plan (a downgrade): the gallery shows, with the one locked preview below it.
    func testFreeUserAtTheLimitPreviewsAndUnlockOpensThePropertyPaywall() {
        launch(seed: "limit2", extra: [])
        let lock = app.buttons["lock.unlock"]
        XCTAssertTrue(lock.waitForExistence(timeout: 12), "At the free limit the locked row shows")
        XCTAssertTrue(app.staticTexts["Free covers one rental."].exists)
        XCTAssertTrue(app.staticTexts["Pine Cabin keeps tracking. Nothing is lost."].exists, "says what stays active")
        lock.tap()
        XCTAssertTrue(app.descendants(matching: .any)["paywall.secondProperty"].waitForExistence(timeout: 8), "one unlock action, paywall for this context")
        let close = app.buttons["paywall.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(lock.waitForExistence(timeout: 5), "clean back-out")
        // The toolbar's Add rental goes to the same paywall.
        app.buttons["properties.add"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["paywall.secondProperty"].waitForExistence(timeout: 8))
    }

    /// Exactly one rental on the free plan: the tab IS that rental's page, and its Add rental opens
    /// the paywall about adding a rental, with a clean back-out.
    func testOneRentalOpensStraightToItsPageAndAddRentalHitsTheLimit() {
        launch(seed: "limit", extra: [])
        let hero = app.descendants(matching: .any)["property.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 12), "one rental: the page, not a gallery")
        XCTAssertFalse(app.descendants(matching: .any)["properties.gallery"].exists)
        XCTAssertTrue(hero.label.contains("Frame going up"), hero.label)
        let add = app.buttons["properties.add"].firstMatch
        XCTAssertTrue(add.exists, "Add rental is on the page")
        add.tap()
        XCTAssertTrue(app.descendants(matching: .any)["paywall.secondProperty"].waitForExistence(timeout: 8))
        let close = app.buttons["paywall.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(hero.waitForExistence(timeout: 5), "clean back-out to the page")
    }

    /// A Pro owner with one rental: Add rental opens the sheet, and a second rental turns the tab
    /// into the gallery.
    func testOneRentalAddRentalOpensTheSheetForProAndTwoRentalsMakeAGallery() {
        launch(seed: "layouts1", extra: ["-LHPropertiesGoal", "mp100"])
        XCTAssertTrue(app.descendants(matching: .any)["property.hero"].waitForExistence(timeout: 12))
        app.buttons["properties.add"].firstMatch.tap()
        let name = app.textFields["property.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Cedar Court")
        let save = app.buttons["property.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.descendants(matching: .any)["properties.tile.1"].waitForExistence(timeout: 10), "two rentals: the gallery")
        XCTAssertTrue(app.descendants(matching: .any)["properties.tile.0"].exists)
    }

    /// The gallery's words: name, "46 of 100h", one pace line; a tap opens that rental's page.
    func testGalleryTilesSayTheirWordsAndOpenTheRentalPage() {
        launch(seed: "layouts3", extra: ["-LHPropertiesGoal", "mp100"])
        let first = app.descendants(matching: .any)["properties.tile.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 12))
        XCTAssertTrue(first.label.hasPrefix("Santa Ray Ave, 88 of 100h, "), first.label)
        let second = app.descendants(matching: .any)["properties.tile.1"]
        XCTAssertTrue(second.label.hasPrefix("Delaney Ct, 46 of 100h, "), second.label)
        let third = app.descendants(matching: .any)["properties.tile.2"]
        XCTAssertTrue(third.label.hasPrefix("Pine Cabin, 8 of 100h, "), third.label)
        XCTAssertTrue(third.label.hasSuffix("a week to go"), third.label)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "3 rentals")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "to confirm")).firstMatch.exists, "no per-rental confirm count")
        second.tap()
        let hero = app.descendants(matching: .any)["property.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 8))
        let title = app.descendants(matching: .any)["property.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.contains("Delaney Ct"), "that rental's page: \(title.label)")
    }

    func testProUserSeesNoLockAndAddOpensTheSheet() {
        launch(seed: "four", extra: [])
        XCTAssertTrue(app.buttons["properties.tile.0"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["lock.unlock"].exists)
        app.buttons["properties.add"].firstMatch.tap()
        XCTAssertTrue(app.textFields["property.name"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["property.save"].isEnabled, "disabled until there's a name")
    }

    func testDeleteAsksWithKeepAndRemovesTheRental() {
        launch(seed: "four", extra: ["-LHOpenFirstPropertyDelete"])
        // "Delete rental" closes the sheet; the one alert asks (§1.21: verbs, ≤ 6 words).
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 12))
        XCTAssertEqual(alert.label, "Delete this rental?")
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Pine Cabin, its")).firstMatch.exists)
        XCTAssertTrue(alert.buttons["Keep"].exists)
        alert.buttons["Keep"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["properties.tile.0"].waitForExistence(timeout: 5), "Keep keeps the rental")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "4 rentals")).firstMatch.exists)

        // Again, from the rental page: Edit, Delete rental, Delete.
        app.descendants(matching: .any)["properties.tile.0"].tap()
        let edit = app.buttons["property.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let delete = app.buttons["property.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        bringIntoView(delete)
        delete.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 8))
        app.alerts.firstMatch.buttons["Delete"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["properties.tile.0"].waitForExistence(timeout: 8), "back on the list")
        XCTAssertFalse(app.staticTexts["Pine Cabin"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "3 rentals")).firstMatch.exists)
    }

    func testDetailShowsTheRentalsOwnHoursAndSeeAllOpensRecords() {
        launch(seed: "four", extra: ["-LHOpenFirstPropertyDetail"])
        let hero = app.descendants(matching: .any)["property.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 12))
        XCTAssertTrue(hero.label.contains("Frame going up"), hero.label)
        let number = app.descendants(matching: .any)["house.numberBlock"]
        XCTAssertTrue(number.waitForExistence(timeout: 5))
        XCTAssertTrue(number.label.contains("212"), number.label)
        XCTAssertTrue(number.label.contains("of 750 hours"), number.label)
        XCTAssertTrue(app.descendants(matching: .any)["property.tile.finish"].exists, "the pace tiles live here now")
        let seeAll = app.buttons["property.seeAllRecords"]
        bringIntoView(seeAll)
        seeAll.tap()
        XCTAssertTrue(app.descendants(matching: .any)["records.total"].waitForExistence(timeout: 8))
    }

    private func bringIntoView(_ element: XCUIElement) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<6 {
            let frame = element.frame, screen = app.windows.firstMatch.frame
            if element.exists, element.isHittable, frame.maxY < screen.maxY - 120 { return }
            scroll.swipeUp(velocity: .slow)
        }
    }

    // MARK: Frames

    /// Text fields and the pinned sheet button (placeholder token, footer scrim), every size.
    func testCaptureFieldStates() {
        let only: Set<String> = ["props-12", "prop-add", "prop-edit"]
        for scheme in ["light", "dark"] {
            for size in [nil, "xxl", "ax3"] as [String?] { captureAll(scheme: scheme, size: size, only: only) }
        }
    }

    /// The gallery at 1, 3 and 8 rentals (goal 100; Santa Ray Ave lit today), light and dark, default,
    /// XXL and AX3. 8 is also shot scrolled to the end, to check the last tile clears the tab bar.
    func testCaptureGallery() {
        for scheme in ["light", "dark"] {
            for size in [nil, "xxl", "ax3"] as [String?] {
                var sizeArgs: [String] = []
                if size == "xxl" { sizeArgs = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"] }
                if size == "ax3" { sizeArgs = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"] }
                let suffix = "-\(scheme)\(size.map { "-\($0)" } ?? "")"
                let base = ["-LHPropertiesGoal", "mp100", "-LHPropertiesLitToday", "0"] + sizeArgs
                for (name, seed, wait, extra) in [("gallery-1", "layouts1", "property.hero", [String]()),
                                                  ("gallery-3", "layouts3", "properties.tile.2", [String]()),
                                                  ("gallery-8", "layouts8", "properties.tile.0", [String]()),
                                                  ("gallery-8-bottom", "layouts8", "properties.gallery", ["-LHPropertiesScrollBottom"])] {
                    app.terminate()
                    launch(seed: seed, scheme: scheme, extra: base + extra)
                    XCTAssertTrue(app.descendants(matching: .any)[wait].firstMatch.waitForExistence(timeout: 15), "\(name)\(suffix): \(wait)")
                    Thread.sleep(forTimeInterval: 1.5)
                    capture(name + suffix)
                }
            }
        }
    }

    /// All five stages at once (the `stages` seed), every window unlit then every window lit, dark and
    /// light: the frames the tile-art contrast measure reads (standard §1.4 tile recipe).
    func testCaptureGalleryStages() {
        for scheme in ["dark", "light"] {
            for (state, lit) in [("unlit", ""), ("lit", "0,1,2,3,4")] {
                app.terminate()
                launch(seed: "stages", scheme: scheme, extra: lit.isEmpty ? [] : ["-LHPropertiesLitToday", lit])
                XCTAssertTrue(app.descendants(matching: .any)["properties.tile.4"].firstMatch.waitForExistence(timeout: 15))
                Thread.sleep(forTimeInterval: 1.5)
                capture("stages-\(state)-\(scheme)")
            }
        }
    }

    func testCaptureLightDefault() { captureAll(scheme: "light", size: nil) }
    func testCaptureDarkDefault() { captureAll(scheme: "dark", size: nil) }
    func testCaptureLightXXL() { captureAll(scheme: "light", size: "xxl") }
    func testCaptureDarkXXL() { captureAll(scheme: "dark", size: "xxl") }
    func testCaptureLightAX3() { captureAll(scheme: "light", size: "ax3") }
    func testCaptureDarkAX3() { captureAll(scheme: "dark", size: "ax3") }

    private struct Shot {
        let name: String
        let seed: String
        var extra: [String] = []
        let waitFor: String
    }

    private let shots: [Shot] = [
        Shot(name: "props-list", seed: "four", waitFor: "properties.tile.0"),
        Shot(name: "props-list-mp", seed: "four", extra: ["-LHPropertiesGoal", "mp100"], waitFor: "properties.tile.0"),
        Shot(name: "props-stages", seed: "stages", extra: ["-LHPropertiesLitToday", "1,3"], waitFor: "properties.tile.0"),
        Shot(name: "props-12", seed: "twelve", waitFor: "properties.search"),
        Shot(name: "props-12-bottom", seed: "twelve", extra: ["-LHPropertiesScrollBottom"], waitFor: "properties.gallery"),
        Shot(name: "props-empty", seed: "empty", waitFor: "properties.empty"),
        Shot(name: "props-loading", seed: "four", extra: ["-LHPropertiesLoading"], waitFor: "properties.loading"),
        Shot(name: "props-limit", seed: "limit2", waitFor: "lock.unlock"),
        Shot(name: "props-single", seed: "limit", waitFor: "property.hero"),
        Shot(name: "prop-detail", seed: "four", extra: ["-LHOpenFirstPropertyDetail", "-LHPropertiesMapLoading"], waitFor: "property.hero"),
        Shot(name: "prop-detail-lower", seed: "four", extra: ["-LHOpenFirstPropertyDetailLower"], waitFor: "property.details"),
        Shot(name: "prop-detail-520", seed: "four", extra: ["-LHOpenSecondPropertyDetail", "-LHPropertiesMapLoading"], waitFor: "property.hero"),
        Shot(name: "prop-detail-maploading", seed: "four", extra: ["-LHOpenFirstPropertyDetailLower", "-LHPropertiesMapLoading"], waitFor: "property.mapLoading"),
        Shot(name: "prop-add", seed: "four", extra: ["-LHOpenAddProperty"], waitFor: "property.name"),
        Shot(name: "prop-edit", seed: "four", extra: ["-LHOpenFirstPropertyEdit"], waitFor: "property.delete"),
        Shot(name: "prop-edit-delete", seed: "four", extra: ["-LHOpenFirstPropertyDelete"], waitFor: "ALERT"),
    ]

    private func captureAll(scheme: String, size: String?, only: Set<String>? = nil) {
        var sizeArgs: [String] = []
        switch size {
        case "xxl": sizeArgs = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"]
        case "ax3": sizeArgs = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        default: break
        }
        for shot in shots where only?.contains(shot.name) ?? true {
            app.terminate()
            launch(seed: shot.seed, scheme: scheme, extra: shot.extra + sizeArgs)
            if shot.waitFor == "ALERT" {
                XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 15), "\(shot.name): alert")
            } else {
                XCTAssertTrue(app.descendants(matching: .any)[shot.waitFor].firstMatch.waitForExistence(timeout: 15), "\(shot.name): \(shot.waitFor)")
            }
            let tip = app.buttons["Continue"]
            if tip.exists { tip.tap(); Thread.sleep(forTimeInterval: 0.6) }
            Thread.sleep(forTimeInterval: 1.0)
            capture("\(shot.name)-\(scheme)\(size.map { "-\($0)" } ?? "")")
        }
    }

    /// The add sheet scrolled to its end (keyboard down): the last field clears the pinned button.
    func testCaptureAddSheetScrolledToBottom() {
        for scheme in ["light", "dark"] {
            for size in [nil, "xxl", "ax3"] as [String?] {
                var sizeArgs: [String] = []
                if size == "xxl" { sizeArgs = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"] }
                if size == "ax3" { sizeArgs = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"] }
                app.terminate()
                launch(seed: "four", scheme: scheme, extra: ["-LHOpenAddProperty", "-LHPropertySheetScrollBottom"] + sizeArgs)
                XCTAssertTrue(app.textFields["property.alias.field"].waitForExistence(timeout: 15))
                Thread.sleep(forTimeInterval: 1.5)
                let last = app.descendants(matching: .any)["property.ownerOccupied"].firstMatch.frame
                let save = app.buttons["property.save"].frame
                XCTAssertLessThanOrEqual(last.maxY, save.minY - 12, "the last field clears the pinned button by 12pt")
                capture("prop-add-bottom-\(scheme)\(size.map { "-\($0)" } ?? "")")
            }
        }
    }

    /// The re-rendered keyframes on Today: the hero at each early stage (the readable slab) and
    /// the confirm board frames over the k14 base, to check they still line up.
    func testCaptureTodayHeroWithTheNewKeyframes() {
        for scheme in ["light", "dark"] {
            for hours in ["0", "60", "120", "212", "600", "751", "760"] {
                app.terminate()
                app.launchArguments = ["-LHHousePreview", hours, "reps", scheme, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
                app.launch()
                XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "hero \(hours)")
                // Let the hero settle (entrance and any count-up finish) before the shot.
                Thread.sleep(forTimeInterval: 5)
                capture("today-hero-\(hours)h-\(scheme)")
            }
            for still in [0, 4, 8, 12] {
                app.terminate()
                app.launchArguments = ["-LHHousePreview", "600", "reps", scheme, "-LHHouseScene", "confirm",
                                       "-LHHouseConfirmStill", "\(still)", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
                app.launch()
                XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "confirm still \(still)")
                Thread.sleep(forTimeInterval: 2.5)
                capture("today-confirm-board\(still)-\(scheme)")
            }
        }
    }

    // MARK: Helpers

    private func launch(seed: String, scheme: String = "light", extra: [String]) {
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "occasional",
            "-LHPropertiesSeed", seed,
            "-LHInitialTab", "1",
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ] + extra
        app.launch()
        // The launch bridge fades out over the first seconds and swallows taps until it's gone.
        // A launch that opens a sheet or the delete alert hides the tab bar from accessibility
        // (the presentation is modal), so any of the three counts as "launched".
        let deadline = Date().addingTimeInterval(15)
        var ready = false
        while Date() < deadline && !ready {
            ready = app.buttons["tab.today"].exists || app.alerts.firstMatch.exists || app.buttons["sheet.close"].exists
            if !ready { Thread.sleep(forTimeInterval: 0.25) }
        }
        XCTAssertTrue(ready, "the app launched to the tab bar, a sheet or an alert")
        Thread.sleep(forTimeInterval: 3)
        // First keyboard on a fresh simulator shows a one-time typing tip.
        let tip = app.buttons["Continue"]
        if tip.exists { tip.tap() }
    }

    private func capture(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["LH_CAPTURE_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
