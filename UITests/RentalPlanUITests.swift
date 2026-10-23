import XCTest

/// 2.1 home screen, package PROPS: Properties rows by plan, the rental page's goal card, Check my
/// goal and the Inbox cleaner card. Journeys plus capture frames (`LH_CAPTURE_DIR` when the
/// runner gets `TEST_RUNNER_LH_CAPTURE_DIR=<dir>`).
final class RentalPlanUITests: XCTestCase {
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

    // MARK: Properties rows

    func testBrianSeedShowsTwoSectionsWithTheRightLines() {
        launch(seed: "brian", tab: 1)
        XCTAssertTrue(element("properties.section.tracking").waitForExistence(timeout: 12))
        XCTAssertTrue(element("properties.section.record").exists)
        XCTAssertEqual(app.staticTexts["properties.subtitle"].label, "3 rentals · 96h this year")
        let santa = app.buttons["properties.row.1"]
        XCTAssertTrue(santa.label.contains("Santa Ray Ave, 12h of 100h · A few nights"), santa.label)
        let delaney = app.buttons["properties.row.0"]
        XCTAssertTrue(delaney.label.contains("84h this year · Someone else does most: hours kept, no target"), delaney.label)
        let yeandle = app.buttons["properties.row.2"]
        XCTAssertTrue(yeandle.label.contains("0h this year · Long stays: hours kept, no target"), yeandle.label)
        // "Tracking a target" comes first: Santa Ray Ave sits above Delaney Ct on screen.
        XCTAssertLessThan(santa.frame.minY, delaney.frame.minY)
    }

    func testSharedGoalHasOneListAndAReadOnlyCard() {
        launch(seed: "reps750", tab: 1, extra: ["-LHOpenPropertyNamed", "Maple Duplex"])
        let readOnly = element("plan.readOnly")
        XCTAssertTrue(readOnly.waitForExistence(timeout: 12))
        XCTAssertEqual(readOnly.label, "Counts toward your 750. Every rental’s hours go into one total.")
        XCTAssertFalse(app.buttons["plan.track"].exists)
        XCTAssertTrue(app.buttons["plan.changeGoal"].exists)
        back()
        XCTAssertTrue(app.staticTexts["properties.subtitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["properties.subtitle"].label, "6 rentals · 212h toward 750")
        XCTAssertFalse(element("properties.section.tracking").exists)
        XCTAssertTrue(app.buttons["properties.row.0"].label.contains("71h this year · Long stays"), app.buttons["properties.row.0"].label)
    }

    // MARK: Rental page

    func testRentalPageSwitchesSantaRayToRecordOnlyAndBack() {
        launch(seed: "brian", tab: 1, extra: ["-LHOpenPropertyNamed", "Santa Ray Ave"])
        let track = app.buttons["plan.track"]
        let record = app.buttons["plan.record"]
        XCTAssertTrue(track.waitForExistence(timeout: 12))
        XCTAssertTrue(track.isSelected)
        XCTAssertTrue(element("plan.explanation").label.hasPrefix("It has its own 100-hour target."), element("plan.explanation").label)
        record.tap()
        let toast = element("plan.toast")
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertTrue(toast.label.contains("Santa Ray Ave is now record only."), toast.label)
        XCTAssertTrue(record.isSelected)
        XCTAssertTrue(element("plan.explanation").label.contains("it will have its own 100-hour target"), element("plan.explanation").label)
        back()
        let row = app.buttons["properties.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("12h this year · A few nights: hours kept, no target"), row.label)
        XCTAssertFalse(element("properties.section.tracking").exists, "every rental is record only: one list")
        row.tap()
        XCTAssertTrue(track.waitForExistence(timeout: 8))
        track.tap()
        XCTAssertTrue(track.isSelected)
        back()
        XCTAssertTrue(app.buttons["properties.row.1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["properties.row.1"].label.contains("12h of 100h · A few nights"), app.buttons["properties.row.1"].label)
        XCTAssertTrue(element("properties.section.tracking").exists)
    }

    // MARK: Check my goal

    func testCheckMyGoalDiffUpdatesAndKeepPinsTheTarget() {
        launch(seed: "brian", tab: 4, extra: ["-LHOpenGoalCheck"])
        XCTAssertTrue(element("goalCheck.screen").waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["goalCheck.done"].exists || scrollTo(app.buttons["goalCheck.done"]), "no change yet: only Done")
        scrollTo(app.buttons["goalCheck.change.1"], up: true)
        app.buttons["goalCheck.change.1"].tap()
        let someoneElse = app.buttons["goalCheck.answer.1.someoneElse"]
        XCTAssertTrue(someoneElse.waitForExistence(timeout: 5))
        someoneElse.tap()
        XCTAssertTrue(someoneElse.isSelected)
        let diffRow = element("goalCheck.diff.1")
        scrollTo(diffRow)
        XCTAssertTrue(diffRow.label.contains("From 100 hours to 500 hours"), diffRow.label)
        XCTAssertTrue(diffRow.label.contains("the app can’t track 100 here"), diffRow.label)
        XCTAssertTrue(element("goalCheck.diff.2").label.contains("Record only · no change"), element("goalCheck.diff.2").label)
        let keep = app.buttons["goalCheck.keep"]
        scrollTo(keep)
        XCTAssertEqual(app.buttons["goalCheck.switch"].label, "Switch Santa Ray Ave to 500")
        XCTAssertFalse(app.buttons["goalCheck.done"].exists)
        keep.tap()
        XCTAssertTrue(element("goalCheck.screen").waitForNonExistence(timeout: 5), "Keep closes the check")
        // Back in through Settings > Tax profile > Check my goal: the answer is saved and the
        // target is pinned, so nothing would change now.
        reopenFromSettings()
        let row = element("goalCheck.diff.1")
        scrollTo(row)
        XCTAssertTrue(row.label.contains("100 hours · no change"), "Keep pins 100: \(row.label)")
        scrollTo(app.buttons["goalCheck.change.1"], up: true)
        XCTAssertTrue(app.buttons["goalCheck.change.1"].label.contains("Someone else"), app.buttons["goalCheck.change.1"].label)
    }

    private func reopenFromSettings() {
        let taxProfile = app.buttons["settings.taxProfile"]
        XCTAssertTrue(scrollTo(taxProfile))
        taxProfile.tap()
        let entry = app.buttons["taxProfile.checkMyGoal"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5) || scrollTo(entry))
        scrollTo(entry)
        XCTAssertTrue(element("taxProfile.cpaLine").exists || scrollTo(element("taxProfile.cpaLine")), "the CPA line on the goal section")
        entry.tap()
        XCTAssertTrue(element("goalCheck.screen").waitForExistence(timeout: 5))
    }

    func testCheckMyGoalSwitchMovesSantaRayTo500() {
        launch(seed: "brian", tab: 4, extra: ["-LHOpenGoalCheck"])
        XCTAssertTrue(element("goalCheck.screen").waitForExistence(timeout: 12))
        app.buttons["goalCheck.change.1"].tap()
        let notSure = app.buttons["goalCheck.answer.1.notSure"]
        XCTAssertTrue(notSure.waitForExistence(timeout: 5))
        notSure.tap()
        let switchButton = app.buttons["goalCheck.switch"]
        scrollTo(switchButton)
        switchButton.tap()
        let toast = element("plan.toast")
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertTrue(toast.label.contains("Santa Ray Ave now has its own 500-hour target."), toast.label)
        reopenFromSettings()
        let row = element("goalCheck.diff.1")
        scrollTo(row)
        XCTAssertTrue(row.label.contains("500 hours · no change"), row.label)
    }

    func testCheckMyGoalUnderASharedGoalExplainsInsteadOfAsking() {
        launch(seed: "reps750", tab: 4, extra: ["-LHOpenGoalCheck"])
        XCTAssertTrue(element("goalCheck.screen").waitForExistence(timeout: 12))
        XCTAssertTrue(element("goalCheck.shared").exists)
        XCTAssertFalse(app.buttons["goalCheck.change.0"].exists)
        XCTAssertTrue(element("goalCheck.cpa").exists)
    }

    // MARK: Inbox cleaner card

    func testCleanerCardShowsOnlyWithAFactAndAnswerSavesIt() {
        launch(seed: "brian", tab: 5)
        XCTAssertTrue(element("inbox.screen").waitForExistence(timeout: 12))
        XCTAssertFalse(element("cleanerFact.card").exists, "the shipped stub returns nothing")
        app.terminate()
        launch(seed: "brian", tab: 5, extra: ["-LHCleanerFact"])
        let title = element("cleanerFact.title")
        XCTAssertTrue(title.waitForExistence(timeout: 12))
        XCTAssertEqual(title.label, "A cleaner seems to work at Santa Ray Ave")
        XCTAssertTrue(app.buttons["cleanerFact.iDoMore"].exists)
        XCTAssertTrue(app.buttons["cleanerFact.notSure"].exists)
        app.buttons["cleanerFact.theyDoMore"].tap()
        XCTAssertTrue(element("cleanerFact.card").waitForNonExistence(timeout: 5), "answered: the card goes")
        app.buttons["tab.properties"].firstMatch.tap()
        let row = app.buttons["properties.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertTrue(row.label.contains("12h of 500h"), "they do more: 500 at Santa Ray Ave: \(row.label)")
    }

    // MARK: Frames

    func testCaptureLightDefault() { captureAll(scheme: "light", size: nil) }
    func testCaptureDarkDefault() { captureAll(scheme: "dark", size: nil) }
    func testCaptureLightAX3() { captureAll(scheme: "light", size: "ax3") }
    func testCaptureDarkAX3() { captureAll(scheme: "dark", size: "ax3") }

    private struct Shot {
        let name: String
        let seed: String
        let tab: Int
        var extra: [String] = []
        let waitFor: String
    }

    private let shots: [Shot] = [
        Shot(name: "props", seed: "brian", tab: 1, waitFor: "properties.row.0"),
        Shot(name: "props", seed: "reps750", tab: 1, waitFor: "properties.row.0"),
        Shot(name: "props", seed: "eight", tab: 1, waitFor: "properties.row.0"),
        Shot(name: "rental-record", seed: "brian", tab: 1, extra: ["-LHOpenPropertyNamed", "Delaney Ct"], waitFor: "property.plan"),
        Shot(name: "rental-target", seed: "brian", tab: 1, extra: ["-LHOpenPropertyNamed", "Santa Ray Ave"], waitFor: "property.plan"),
        Shot(name: "rental-shared", seed: "reps750", tab: 1, extra: ["-LHOpenPropertyNamed", "Maple Duplex"], waitFor: "property.plan"),
        Shot(name: "rental-record", seed: "eight", tab: 1, extra: ["-LHOpenPropertyNamed", "Oak Street"], waitFor: "property.plan"),
        Shot(name: "rental-target", seed: "eight", tab: 1, extra: ["-LHOpenPropertyNamed", "Palm Studio"], waitFor: "property.plan"),
        Shot(name: "goalcheck", seed: "brian", tab: 4, extra: ["-LHOpenGoalCheck"], waitFor: "goalCheck.screen"),
        Shot(name: "goalcheck-diff", seed: "brian", tab: 4, extra: ["-LHOpenGoalCheck", "-LHGoalCheckScrollDiff"], waitFor: "goalCheck.diff"),
        Shot(name: "goalcheck", seed: "reps750", tab: 4, extra: ["-LHOpenGoalCheck"], waitFor: "goalCheck.screen"),
        Shot(name: "goalcheck", seed: "eight", tab: 4, extra: ["-LHOpenGoalCheck"], waitFor: "goalCheck.screen"),
        Shot(name: "goalcheck-diff", seed: "eight", tab: 4, extra: ["-LHOpenGoalCheck", "-LHGoalCheckScrollDiff"], waitFor: "goalCheck.diff"),
        Shot(name: "inbox-cleaner", seed: "brian", tab: 5, extra: ["-LHCleanerFact"], waitFor: "cleanerFact.card"),
    ]

    private func captureAll(scheme: String, size: String?) {
        let sizeArgs = size == "ax3" ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"] : []
        for shot in shots {
            app.terminate()
            launch(seed: shot.seed, tab: shot.tab, scheme: scheme, extra: shot.extra + sizeArgs)
            XCTAssertTrue(element(shot.waitFor).waitForExistence(timeout: 15), "\(shot.name)-\(shot.seed): \(shot.waitFor)")
            Thread.sleep(forTimeInterval: 1.5)
            capture("\(shot.name)-\(shot.seed)_\(scheme)_\(size ?? "default")")
        }
    }

    // MARK: Helpers

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func back() {
        let button = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    @discardableResult
    private func scrollTo(_ el: XCUIElement, up: Bool = false) -> Bool {
        for _ in 0..<8 {
            if el.exists && el.isHittable { return true }
            if up { app.swipeDown() } else { app.swipeUp() }
        }
        return el.exists && el.isHittable
    }

    private func launch(seed: String, tab: Int, scheme: String = "light", extra: [String] = []) {
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "occasional",
            "-LHHomeSeed", seed,
            "-LHInitialTab", "\(tab)",
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ] + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        if tab == 1 || tab == 5 { XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 15)) }
        Thread.sleep(forTimeInterval: 3)
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
