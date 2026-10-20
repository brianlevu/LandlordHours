import XCTest

/// 2.0 Log time and the timer: journeys (type → auto-fill → save, Undo, voice denied, the timer,
/// a failed save, the keyboard) and capture frames for every state, light and dark, at the
/// default size, XXL and AX3. Frames go to `LH_CAPTURE_DIR` (`TEST_RUNNER_LH_CAPTURE_DIR=<dir>`).
final class LogTimeUITests: XCTestCase {
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

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    /// Any element whose label contains `text`.
    private func shows(_ text: String) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.waitForExistence(timeout: 3)
    }

    private func waitEnabled(_ element: XCUIElement, timeout: TimeInterval = 6) {
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }

    // MARK: Journeys

    /// "+", the note, type, Log: three taps (the brief allows four).
    func testTypeAutoFillSaveInUnderFourTaps() {
        launch(seed: "four", extra: [])
        var taps = 0
        app.buttons["tab.logTime"].tap(); taps += 1
        let note = element("log.note")
        XCTAssertTrue(note.waitForExistence(timeout: 8))
        note.tap(); taps += 1
        note.typeText("Fixed the sink at Pine Cabin, 1 hour")
        let caption = element("log.fill.caption")
        XCTAssertTrue(caption.waitForExistence(timeout: 6), "the note fills the fields")
        XCTAssertTrue(shows("Filled from your note"), caption.label)
        // The parser runs after each 600ms pause; wait for the read of the whole note.
        let property = app.buttons["log.property"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Pine Cabin"), evaluatedWith: property)
        waitForExpectations(timeout: 6)
        XCTAssertTrue(app.buttons["log.category"].label.contains("Repairs"), app.buttons["log.category"].label)
        let save = app.buttons["log.save"]
        XCTAssertEqual(save.label, "Log 1h")
        XCTAssertTrue(save.isHittable, "the Log button rides above the keyboard")
        save.tap(); taps += 1
        let toast = element("shell.toast")
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Logged 1h at Pine Cabin"].exists)
        XCTAssertLessThanOrEqual(taps, 4)
        // Undo deletes the entry again.
        app.buttons["inbox.undo"].tap()
        XCTAssertTrue(toast.waitForNonExistence(timeout: 3))
    }

    func testUndoFillPutsTheFieldsBack() {
        launch(seed: "four", extra: [])
        app.buttons["tab.logTime"].tap()
        let note = element("log.note")
        XCTAssertTrue(note.waitForExistence(timeout: 8))
        note.tap()
        note.typeText("Showing at Oak Street Duplex for 2 hours")
        XCTAssertTrue(element("log.fill.caption").waitForExistence(timeout: 6))
        XCTAssertEqual(app.buttons["log.save"].label, "Log 2h")
        app.buttons["log.done"].tap()
        app.buttons["log.fill.undo"].tap()
        XCTAssertTrue(app.buttons["log.property"].label.contains("Choose"), app.buttons["log.property"].label)
        XCTAssertEqual(app.buttons["log.save"].label, "Log 1h")
        XCTAssertFalse(app.buttons["log.save"].isEnabled, "no property again")
        XCTAssertTrue(element("log.missing").exists)
    }

    // MARK: Apple's model fills the note (NoteReaderChain; -LHNoteModel scripts the model tier)

    func testModelFillsEveryFieldAndUndoPutsThemBack() {
        launch(seed: "four", extra: ["-LHNoteModel", "fake"])
        app.buttons["tab.logTime"].tap()
        let note = element("log.note")
        XCTAssertTrue(note.waitForExistence(timeout: 8))
        note.tap()
        note.typeText("fixed the sink at Oak St with Mike, about 2 hours yesterday")
        let description = element("log.description")
        XCTAssertTrue(description.waitForExistence(timeout: 8), "the model's description for the record")
        XCTAssertTrue(app.buttons["log.property"].label.contains("Oak Street Duplex"), app.buttons["log.property"].label)
        XCTAssertTrue(app.buttons["log.category"].label.contains("Repairs"), app.buttons["log.category"].label)
        XCTAssertTrue(app.buttons["log.date"].label.contains("Yesterday"), app.buttons["log.date"].label)
        XCTAssertEqual(app.buttons["log.save"].label, "Log 2h")
        XCTAssertTrue(element("log.fill.caption").waitForExistence(timeout: 4))
        app.buttons["log.done"].tap()
        app.buttons["log.fill.undo"].tap()
        XCTAssertTrue(description.waitForNonExistence(timeout: 4), "Undo clears the description")
        XCTAssertTrue(app.buttons["log.property"].label.contains("Choose"), app.buttons["log.property"].label)
        XCTAssertTrue(app.buttons["log.date"].label.contains("Today"), app.buttons["log.date"].label)
        XCTAssertEqual(app.buttons["log.save"].label, "Log 1h")
    }

    func testWithoutAModelTheRulesStillFill() {
        launch(seed: "four", extra: ["-LHNoteModel", "unavailable"])
        app.buttons["tab.logTime"].tap()
        let note = element("log.note")
        XCTAssertTrue(note.waitForExistence(timeout: 8))
        note.tap()
        note.typeText("fixed the sink at Oak St with Mike, about 2 hours yesterday")
        XCTAssertTrue(element("log.fill.caption").waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["log.property"].label.contains("Oak Street Duplex"))
        XCTAssertEqual(app.buttons["log.save"].label, "Log 2h")
        XCTAssertFalse(element("log.reading").exists, "no drafting line without a model")
        XCTAssertFalse(element("log.description").exists, "rules never write a description")
    }

    func testWhileTheModelThinksTheRulesHaveFilledAndLogStillWorks() {
        launch(seed: "four", extra: ["-LHNoteModel", "thinking"])
        app.buttons["tab.logTime"].tap()
        let note = element("log.note")
        XCTAssertTrue(note.waitForExistence(timeout: 8))
        note.tap()
        note.typeText("fixed the sink at Oak St, 2 hours")
        XCTAssertTrue(element("log.reading").waitForExistence(timeout: 6), "the drafting line while Apple's model reads")
        XCTAssertTrue(app.buttons["log.property"].label.contains("Oak Street Duplex"), "the rules filled first")
        let save = app.buttons["log.save"]
        XCTAssertEqual(save.label, "Log 2h")
        XCTAssertTrue(save.isEnabled, "the UI never blocks on the model")
        save.tap()
        XCTAssertTrue(element("shell.toast").waitForExistence(timeout: 5))
    }

    func testVoiceDeniedOffersSettingsAndDimsTheMic() {
        launch(seed: "four", extra: ["-LHVoiceDenied"])
        app.buttons["tab.logTime"].tap()
        let mic = app.buttons["log.mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 8))
        mic.tap()
        XCTAssertTrue(element("log.voice.denied").waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Turn on the microphone in Settings to talk instead of type."].exists)
        XCTAssertTrue(app.buttons["log.voice.openSettings"].isHittable)
        XCTAssertFalse(element("log.listening").exists, "nothing records")
        // Typing still works.
        element("log.note").tap()
        element("log.note").typeText("Fixed the sink at Pine Cabin, 1 hour")
        XCTAssertTrue(element("log.fill.caption").waitForExistence(timeout: 6))
    }

    func testVoiceFirstUseExplainsBeforeTheSystemAsks() {
        launch(seed: "four", extra: ["-LHVoiceFirstUse"])
        app.buttons["tab.logTime"].tap()
        let mic = app.buttons["log.mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 8))
        mic.tap()
        XCTAssertTrue(element("log.voice.intro").waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["log.voice.start"].isHittable)
    }

    func testTimerStartStopReviewAndLog() {
        launch(seed: "limit", extra: [])
        app.buttons["tab.logTime"].tap()
        let toTimer = app.buttons["log.startTimer"]
        XCTAssertTrue(toTimer.waitForExistence(timeout: 8))
        toTimer.tap()
        let start = app.buttons["timer.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 4))
        XCTAssertTrue(start.isEnabled, "the only rental is preselected")
        start.tap()
        XCTAssertTrue(element("timer.card").waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Keeps running if you close this. You\u{2019}ll see it on your Lock Screen."].exists)
        // Close: it keeps running, and Today shows it.
        app.buttons["log.close"].tap()
        let todayStop = app.buttons["today.timer.stop"]
        XCTAssertTrue(todayStop.waitForExistence(timeout: 5), "Today's timer card replaces the floating banner")
        Thread.sleep(forTimeInterval: 61)   // run past the one-minute floor
        todayStop.tap()
        let ran = element("log.timer.ran")
        XCTAssertTrue(ran.waitForExistence(timeout: 6))
        XCTAssertTrue(shows("Timer ran 1m"), ran.label)
        XCTAssertEqual(app.buttons["log.save"].label, "Log 5m")
        app.buttons["log.save"].tap()
        XCTAssertTrue(element("shell.toast").waitForExistence(timeout: 5))
        XCTAssertFalse(todayStop.exists)
        XCTAssertFalse(element("today.timerDraft").exists, "logged, so no draft waits")
    }

    func testDiscardingARunningTimerCanBeUndone() {
        launch(seed: "limit", extra: ["-LHOpenLog", "timerRunning"])
        let discard = app.buttons["timer.discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 10))
        discard.tap()
        XCTAssertTrue(app.staticTexts["Timer discarded"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["today.timer.stop"].exists)
        app.buttons["inbox.undo"].tap()
        XCTAssertTrue(app.buttons["today.timer.stop"].waitForExistence(timeout: 4), "the same timer is back")
    }

    func testStoppedTimerWaitsOnTodayAndLogsInOneTap() {
        launch(seed: "limit", extra: ["-LHTodayTimer", "draft"])
        let primary = app.buttons["draft.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        XCTAssertEqual(primary.label, "Log 1h 10m")
        XCTAssertTrue(shows("Timer ran 1h 12m at Pine Cabin"), element("draft.summary").label)
        primary.tap()
        XCTAssertTrue(app.staticTexts["Logged 1h 10m at Pine Cabin"].waitForExistence(timeout: 4))
        XCTAssertTrue(primary.waitForNonExistence(timeout: 3))
    }

    func testAFailedSaveIsSurfacedAndTheSheetStays() {
        launch(seed: "four", extra: ["-LHOpenLog", "filled", "-LHFailNextSave"])
        let save = app.buttons["log.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        let error = element("log.saveError")
        XCTAssertTrue(error.waitForExistence(timeout: 4))
        XCTAssertTrue(shows("Couldn't save this"), error.label)
        XCTAssertTrue(save.exists, "the sheet stays open with the note")
        XCTAssertFalse(element("shell.toast").exists)
        save.tap()   // the next try works
        XCTAssertTrue(element("shell.toast").waitForExistence(timeout: 5))
    }

    func testNotCountedWorkSaysSoAndStillLogs() {
        launch(seed: "four", extra: ["-LHOpenLog", "notCounted"])
        let line = element("log.notCounted")
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        XCTAssertTrue(shows("Financing doesn\u{2019}t count toward your hours or the house."), line.label)
        XCTAssertTrue(app.buttons["log.save"].isEnabled)
    }

    func testCategoryPickerGroupsTheWorkThatDoesntCount() {
        launch(seed: "four", extra: ["-LHOpenLog", "pickerCategory"])
        XCTAssertTrue(element("picker.category").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Doesn\u{2019}t count toward hours"].exists)
        for kind in ["investing", "financing", "negotiation"] {
            XCTAssertTrue(app.buttons["picker.category.\(kind)"].exists, kind)
        }
        app.buttons["picker.category.investing"].tap()
        XCTAssertTrue(element("log.notCounted").waitForExistence(timeout: 4))
    }

    func testAtTheFreeLimitThePropertyPickerShowsTheLock() {
        launch(seed: "limit", extra: ["-LHOpenLog", "pickerPropertyLimit"])
        let unlock = app.buttons["lock.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Pine Cabin keeps tracking. Nothing is lost."].exists)
        unlock.tap()
        XCTAssertTrue(element("paywall.secondProperty").waitForExistence(timeout: 8))
    }

    func testTheKeyboardNeverCoversTheFocusedField() {
        for size in [nil, "ax3"] as [String?] {
            app.terminate()
            launch(seed: "four", extra: sizeArgs(size))
            app.buttons["tab.logTime"].tap()
            let note = element("log.note")
            XCTAssertTrue(note.waitForExistence(timeout: 8))
            note.tap()
            note.typeText("Met the HVAC tech at Oak Street, walked through the duplex and then")
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.waitForExistence(timeout: 4))
            Thread.sleep(forTimeInterval: 1)
            XCTAssertLessThanOrEqual(note.frame.maxY, keyboard.frame.minY, "note clears the keyboard (\(size ?? "default"))")
            let save = app.buttons["log.save"]
            XCTAssertLessThanOrEqual(save.frame.maxY, keyboard.frame.minY, "Log rides on the keyboard (\(size ?? "default"))")
            XCTAssertFalse(app.buttons["tab.today"].isHittable, "the sheet covers the tab bar")
        }
    }

    func testPlusRouteFromOtherSurfacesOpensTheSheet() {
        launch(seed: "four", extra: [], tab: "2")
        XCTAssertTrue(app.buttons["log.close"].waitForExistence(timeout: 8), "the old Track tab index opens the sheet")
        app.buttons["log.close"].tap()
        XCTAssertTrue(app.buttons["tab.today"].isHittable)
    }

    // MARK: Frames

    private struct Shot {
        let name: String
        let seed: String
        var extra: [String] = []
        let waitFor: String
        var settle: Double = 1.2
        /// Tapped after `waitFor` appears (e.g. Undo), then `then` is awaited.
        var tap: String? = nil
        var then: String? = nil
    }

    private let shots: [Shot] = [
        Shot(name: "log-empty", seed: "four", extra: ["-LHOpenLog", "empty"], waitFor: "log.note"),
        Shot(name: "log-typed", seed: "four", extra: ["-LHOpenLog", "typed"], waitFor: "log.note"),
        Shot(name: "log-filled", seed: "four", extra: ["-LHOpenLog", "filled"], waitFor: "log.fill.caption"),
        Shot(name: "log-filled-spouse", seed: "four", extra: ["-LHOpenLog", "filled", "-LHLogSpouse"], waitFor: "log.who.spouse"),
        Shot(name: "log-quick", seed: "limit", extra: ["-LHOpenLog", "quick"], waitFor: "log.note"),
        Shot(name: "log-invalid", seed: "four", extra: ["-LHOpenLog", "invalid"], waitFor: "log.missing"),
        Shot(name: "log-keyboard", seed: "four", extra: ["-LHOpenLog", "keyboard"], waitFor: "log.done", settle: 2),
        Shot(name: "log-not-counted", seed: "four", extra: ["-LHOpenLog", "notCounted"], waitFor: "log.notCounted"),
        Shot(name: "log-save-failed", seed: "four", extra: ["-LHOpenLog", "saveFailed"], waitFor: "log.saveError"),
        Shot(name: "log-voice-first", seed: "four", extra: ["-LHOpenLog", "voiceFirst", "-LHVoiceFirstUse"], waitFor: "log.voice.intro"),
        Shot(name: "log-voice-listening", seed: "four", extra: ["-LHOpenLog", "listening"], waitFor: "log.listening"),
        Shot(name: "log-voice-filled", seed: "four", extra: ["-LHOpenLog", "voiceFilled"], waitFor: "log.fill.caption"),
        Shot(name: "log-voice-denied", seed: "four", extra: ["-LHOpenLog", "voiceDenied", "-LHVoiceDenied"], waitFor: "log.voice.denied"),
        Shot(name: "log-picker-category", seed: "four", extra: ["-LHOpenLog", "pickerCategory"], waitFor: "picker.category", settle: 1.6),
        Shot(name: "log-picker-property", seed: "four", extra: ["-LHOpenLog", "pickerProperty"], waitFor: "picker.property", settle: 1.6),
        Shot(name: "log-picker-property-limit", seed: "limit", extra: ["-LHOpenLog", "pickerPropertyLimit"], waitFor: "lock.unlock", settle: 1.6),
        Shot(name: "timer-idle", seed: "four", extra: ["-LHOpenLog", "timerIdle"], waitFor: "timer.start"),
        Shot(name: "timer-running", seed: "four", extra: ["-LHOpenLog", "timerRunning"], waitFor: "timer.card"),
        Shot(name: "timer-review", seed: "four", extra: ["-LHOpenLog", "timerReview"], waitFor: "log.timer.ran"),
        // Apple's model filling the note (scripted model tier, the real reader and form).
        Shot(name: "ai-thinking", seed: "four", extra: ["-LHOpenLog", "aiNote", "-LHNoteModel", "thinking"], waitFor: "log.reading", settle: 1.5),
        Shot(name: "ai-filled", seed: "four", extra: ["-LHOpenLog", "aiNote", "-LHNoteModel", "fake"], waitFor: "log.description", settle: 1.5),
        Shot(name: "ai-undone", seed: "four", extra: ["-LHOpenLog", "aiNote", "-LHNoteModel", "fake"], waitFor: "log.description", settle: 1.0,
             tap: "log.fill.undo", then: "log.property"),
        Shot(name: "ai-partial", seed: "four", extra: ["-LHOpenLog", "aiPartial", "-LHNoteModel", "fake"], waitFor: "log.fill.caption", settle: 1.5),
        Shot(name: "ai-rules-only", seed: "four", extra: ["-LHOpenLog", "aiNote", "-LHNoteModel", "unavailable"], waitFor: "log.fill.caption", settle: 1.5),
        Shot(name: "today-timer-running", seed: "four", extra: ["-LHTodayTimer", "running"], waitFor: "today.timer.stop", settle: 2),
        Shot(name: "today-timer-draft", seed: "four", extra: ["-LHTodayTimer", "draft"], waitFor: "today.timerDraft", settle: 2),
        Shot(name: "today-timer-discarded", seed: "four", extra: ["-LHTodayTimer", "discarded"], waitFor: "shell.toast", settle: 1),
    ]

    func testCaptureLightDefault() { captureAll(scheme: "light", size: nil) }
    func testCaptureDarkDefault() { captureAll(scheme: "dark", size: nil) }
    func testCaptureLightXXL() { captureAll(scheme: "light", size: "xxl") }
    func testCaptureDarkXXL() { captureAll(scheme: "dark", size: "xxl") }
    func testCaptureLightAX3() { captureAll(scheme: "light", size: "ax3") }
    func testCaptureDarkAX3() { captureAll(scheme: "dark", size: "ax3") }

    private func sizeArgs(_ size: String?) -> [String] {
        switch size {
        case "xxl": return ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"]
        case "ax3": return ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        default: return []
        }
    }

    /// The states a fix touched, in every scheme and size.
    func testCaptureFixups() {
        let names: Set<String> = ["log-typed", "log-filled-spouse", "log-save-failed", "log-not-counted", "log-invalid", "log-picker-property-limit"]
        for scheme in ["light", "dark"] {
            for size in [nil, "xxl", "ax3"] as [String?] { captureAll(scheme: scheme, size: size, names: names) }
        }
    }

    /// Apple's model filling the note: thinking, filled, Undo, partial, no model → rules.
    func testCaptureAIFillStates() {
        for scheme in ["light", "dark"] {
            for size in [nil, "xxl", "ax3"] as [String?] { captureAll(scheme: scheme, size: size, prefix: "ai-") }
        }
    }

    /// Today's timer card in every scheme and size (re-run after a Today-only fix).
    func testCaptureTodayTimerCards() {
        for scheme in ["light", "dark"] {
            for size in [nil, "xxl", "ax3"] as [String?] { captureAll(scheme: scheme, size: size, prefix: "today-") }
        }
    }

    private func captureAll(scheme: String, size: String?, prefix: String = "", names: Set<String>? = nil) {
        // One missing state must not cost the rest of the board.
        continueAfterFailure = true
        for shot in shots where shot.name.hasPrefix(prefix) && (names?.contains(shot.name) ?? true) {
            app.terminate()
            launch(seed: shot.seed, scheme: scheme, extra: shot.extra + sizeArgs(size))
            let target = element(shot.waitFor)
            XCTAssertTrue(target.waitForExistence(timeout: 15), "\(shot.name): \(shot.waitFor)")
            if let tap = shot.tap {
                // Let the fill settle, then tap (Undo) and wait for the result.
                Thread.sleep(forTimeInterval: 1.2)
                let button = element(tap)
                if button.waitForExistence(timeout: 6) { button.tap() }
                if let then = shot.then { XCTAssertTrue(element(then).waitForExistence(timeout: 6), "\(shot.name): \(then)") }
                XCTAssertFalse(element("log.description").exists, "\(shot.name): Undo cleared the description")
            }
            if shot.waitFor != "shell.toast" && shot.waitFor != "log.done" {
                // Today's card sits under the hero, and at AX sizes a sheet's state (the Who row,
                // the save error) can sit below the fold: scroll it fully into view.
                let today = app.buttons["tab.today"]
                let bottom = shot.name.hasPrefix("today-") ? today.frame.minY : app.windows.firstMatch.frame.maxY - 24
                let bar = (bottom: bottom, minY: bottom)
                // Short drags from mid-screen (never from an edge, which would leave the app)
                // until the card sits fully above the tab bar.
                var tries = 0
                while target.frame.maxY > bar.minY - 12 && target.frame.minY > 140 && tries < 8 {
                    let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
                    let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
                    from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
                    Thread.sleep(forTimeInterval: 0.5)
                    tries += 1
                }
            }
            Thread.sleep(forTimeInterval: shot.settle)
            capture("\(shot.name)-\(scheme)\(size.map { "-\($0)" } ?? "")")
        }
    }

    // MARK: Helpers

    private func launch(seed: String, scheme: String = "light", extra: [String], tab: String = "0") {
        app.launchArguments = [
            UITestIsolation.resetProfilesArgument,
            "-LHMockScenario", "occasional",
            "-LHPropertiesSeed", seed,
            "-LHInitialTab", tab,
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ] + extra
        app.launch()
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 15) || app.buttons["log.close"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2.5)
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
