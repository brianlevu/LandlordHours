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

    /// The Log button's words (non-breaking spaces read as spaces).
    private var saveLabel: String { app.buttons["log.save"].label }

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
        XCTAssertTrue(shows("Matched from your words"), caption.label)
        // The parser runs after each 600ms pause; wait for the read of the whole note.
        let property = app.buttons["log.property"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Pine Cabin"), evaluatedWith: property)
        waitForExpectations(timeout: 6)
        XCTAssertTrue(app.buttons["log.category"].label.contains("Repairs"), app.buttons["log.category"].label)
        let save = app.buttons["log.save"]
        XCTAssertEqual(save.label, "Log 1h at Pine Cabin")
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
        note.typeText("Fixed the sink at Oak St for 2 hours")
        XCTAssertTrue(element("log.fill.caption").waitForExistence(timeout: 6))
        expectation(for: NSPredicate(format: "label BEGINSWITH %@", "Log 2h at Oak Street Duplex"), evaluatedWith: app.buttons["log.save"])
        waitForExpectations(timeout: 6)
        app.buttons["log.done"].tap()
        app.buttons["log.fill.undo"].tap()
        XCTAssertTrue(app.buttons["log.property"].label.contains("not chosen"), app.buttons["log.property"].label)
        XCTAssertEqual(saveLabel, "Pick a rental", "the button names the gap and is never dead")
        XCTAssertTrue(app.buttons["log.save"].isEnabled)
        // Tapping it opens the rental editor instead of logging.
        app.buttons["log.save"].tap()
        XCTAssertTrue(app.buttons["log.pick.property.0"].waitForExistence(timeout: 4))
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
        XCTAssertTrue(saveLabel.hasPrefix("Log 2h at Oak Street Duplex"), saveLabel)
        XCTAssertTrue(element("log.fill.caption").waitForExistence(timeout: 4))
        XCTAssertTrue(shows("Filled from your note"))
        app.buttons["log.done"].tap()
        app.buttons["log.fill.undo"].tap()
        XCTAssertTrue(description.waitForNonExistence(timeout: 4), "Undo clears the description")
        XCTAssertTrue(app.buttons["log.property"].label.contains("not chosen"), app.buttons["log.property"].label)
        XCTAssertTrue(app.buttons["log.date"].label.contains("Today"), app.buttons["log.date"].label)
        XCTAssertEqual(saveLabel, "Pick a rental")
    }

    func testTwoRentalsLeaveThePropertyForTheUser() {
        launch(seed: "four", extra: ["-LHNoteModel", "fake"])
        app.buttons["tab.logTime"].tap()
        let note = element("log.note")
        XCTAssertTrue(note.waitForExistence(timeout: 8))
        note.tap()
        note.typeText("Fixed the sink at Pine Cabin and mowed at Maple Court, 2 hours")
        XCTAssertTrue(element("log.propertyHint").waitForExistence(timeout: 8))
        XCTAssertTrue(shows("mentions 2 rentals"))
        XCTAssertTrue(app.buttons["log.property"].label.contains("not chosen"), app.buttons["log.property"].label)
        XCTAssertEqual(saveLabel, "Pick a rental")
    }

    func testWithoutAModelTheRulesStillFill() {
        launch(seed: "four", extra: ["-LHNoteModel", "unavailable"])
        app.buttons["tab.logTime"].tap()
        let note = element("log.note")
        XCTAssertTrue(note.waitForExistence(timeout: 8))
        note.tap()
        note.typeText("fixed the sink at Oak St with Mike, about 2 hours yesterday")
        XCTAssertTrue(element("log.fill.caption").waitForExistence(timeout: 6))
        XCTAssertTrue(shows("Matched from your words"), "the rules still read the note, and say so")
        XCTAssertTrue(app.buttons["log.property"].label.contains("Oak Street Duplex"))
        XCTAssertTrue(saveLabel.hasPrefix("Log 2h at Oak Street Duplex"), saveLabel)
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
        XCTAssertTrue(saveLabel.hasPrefix("Log 2h at Oak Street Duplex"), saveLabel)
        XCTAssertTrue(save.isEnabled, "the UI never blocks on the model")
        save.tap()
        XCTAssertTrue(element("shell.toast").waitForExistence(timeout: 5), "Log cancels the read and logs what is on screen")
    }

    /// "Read my notes with Apple's model" off: no model runs, the rules still fill and say so.
    func testWithTheModelSwitchOffTheRulesStillFillAndSayWhere() {
        launch(seed: "four", extra: ["-LHNoteModel", "off"])
        app.buttons["tab.logTime"].tap()
        let note = element("log.note")
        XCTAssertTrue(note.waitForExistence(timeout: 8))
        note.tap()
        note.typeText("fixed the sink at Oak St, 2 hours")
        XCTAssertTrue(element("log.fill.caption").waitForExistence(timeout: 6))
        XCTAssertTrue(shows("Matched from your words"))
        XCTAssertFalse(element("log.reading").exists)
        XCTAssertFalse(element("log.description").exists)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(element("log.description").exists, "no model ever answers")
    }

    /// The manual door: every field, no reading, four taps.
    func testEnterDetailsYourselfNeedsNoNote() {
        launch(seed: "four", extra: [])
        app.buttons["tab.logTime"].tap()
        let enter = app.buttons["log.enterDetails"]
        XCTAssertTrue(enter.waitForExistence(timeout: 8))
        enter.tap()
        XCTAssertTrue(app.buttons["log.property"].waitForExistence(timeout: 4))
        app.buttons["log.property"].tap()
        app.buttons["log.pick.property.1"].tap()
        XCTAssertFalse(saveLabel == "Pick a rental")
        app.buttons["log.hours"].tap()
        app.buttons["log.chip.2h"].tap()
        XCTAssertTrue(saveLabel.hasPrefix("Log 2h at"), saveLabel)
    }

    /// Zero rentals: one field, then Log creates the rental and the entry together.
    func testFirstLogCreatesTheRentalAndTheEntry() {
        launch(seed: "empty", extra: [])
        app.buttons["tab.logTime"].tap()
        let name = element("log.rentalName")
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        XCTAssertEqual(saveLabel, "Name your rental")
        name.tap()
        name.typeText("Pine Cabin")
        let note = element("log.note")
        note.tap()
        note.typeText("fixed the sink, 1 hour")
        XCTAssertTrue(element("log.fill.caption").waitForExistence(timeout: 6))
        XCTAssertTrue(saveLabel.hasPrefix("Add Pine Cabin and log 1h"), saveLabel)
        app.buttons["log.save"].tap()
        XCTAssertTrue(element("shell.toast").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pine Cabin added · Logged 1h"].exists)
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
        app.buttons["sheet.close"].tap()
        let todayStop = app.buttons["today.timer.stop"]
        XCTAssertTrue(todayStop.waitForExistence(timeout: 5), "Today's timer card replaces the floating banner")
        Thread.sleep(forTimeInterval: 61)   // run past the one-minute floor
        todayStop.tap()
        let ran = element("log.timer.ran")
        XCTAssertTrue(ran.waitForExistence(timeout: 6))
        XCTAssertTrue(shows("Timer ran 1m"), ran.label)
        XCTAssertEqual(saveLabel, "Log 5m at Pine Cabin")
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
        XCTAssertTrue(shows("Couldn’t save this"), error.label)
        XCTAssertTrue(save.exists, "the sheet stays open with the note")
        XCTAssertFalse(element("shell.toast").exists)
        save.tap()   // the next try works
        XCTAssertTrue(element("shell.toast").waitForExistence(timeout: 5))
    }

    func testNotCountedWorkSaysSoAndStillLogs() {
        launch(seed: "four", extra: ["-LHOpenLog", "notCounted"])
        let line = element("log.notCounted")
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        XCTAssertTrue(shows("Financing doesn\u{2019}t count toward your hours."), line.label)
        XCTAssertTrue(app.buttons["log.save"].isEnabled)
    }

    func testKindOfWorkEditorGroupsTheWorkThatDoesntCount() {
        launch(seed: "four", extra: ["-LHOpenLog", "nfModel"])
        let row = app.buttons["log.category"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Doesn\u{2019}t count toward your hours")).firstMatch.waitForExistence(timeout: 4))
        for kind in ["investing", "financing", "negotiation"] {
            XCTAssertTrue(app.buttons["log.pick.category.\(kind)"].exists, kind)
        }
        app.buttons["log.pick.category.investing"].tap()
        XCTAssertTrue(element("log.notCounted").waitForExistence(timeout: 4))
    }

    func testAtTheFreeLimitTheRentalEditorShowsTheLock() {
        launch(seed: "limit", extra: ["-LHOpenLog", "nfModel"])
        let row = app.buttons["log.property"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        // Scoped to the editor: Today's "Your record" lock under the sheet has its own Unlock Pro.
        let unlock = element("log.editor.property").buttons["lock.unlock"].firstMatch
        XCTAssertTrue(unlock.waitForExistence(timeout: 6))
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
        XCTAssertTrue(app.buttons["sheet.close"].waitForExistence(timeout: 8), "the old Track tab index opens the sheet")
        app.buttons["sheet.close"].tap()
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
        /// Scrolled fully into view instead of `waitFor` (e.g. the Date row below the description).
        var scrollTo: String? = nil
        /// Taps the Spouse segment of the Who control and asserts it is selected before the capture.
        var selectSpouse = false
    }

    private let shots: [Shot] = [
        Shot(name: "log-empty", seed: "four", extra: ["-LHOpenLog", "empty"], waitFor: "log.note"),
        Shot(name: "log-typed", seed: "four", extra: ["-LHOpenLog", "typed"], waitFor: "log.note"),
        Shot(name: "log-filled", seed: "four", extra: ["-LHOpenLog", "filled"], waitFor: "log.fill.caption"),
        Shot(name: "log-filled-spouse", seed: "four", extra: ["-LHOpenLog", "filled", "-LHLogSpouse"], waitFor: "log.who", scrollTo: "log.who", selectSpouse: true),
        Shot(name: "log-quick", seed: "limit", extra: ["-LHOpenLog", "quick"], waitFor: "log.note"),
        Shot(name: "log-invalid", seed: "four", extra: ["-LHOpenLog", "invalid"], waitFor: "log.save"),
        Shot(name: "log-keyboard", seed: "four", extra: ["-LHOpenLog", "keyboard"], waitFor: "log.done", settle: 2),
        Shot(name: "log-not-counted", seed: "four", extra: ["-LHOpenLog", "notCounted"], waitFor: "log.notCounted"),
        Shot(name: "log-save-failed", seed: "four", extra: ["-LHOpenLog", "saveFailed"], waitFor: "log.saveError"),
        Shot(name: "log-voice-first", seed: "four", extra: ["-LHOpenLog", "voiceFirst", "-LHVoiceFirstUse"], waitFor: "log.voice.intro"),
        Shot(name: "log-voice-listening", seed: "four", extra: ["-LHOpenLog", "listening"], waitFor: "log.listening"),
        Shot(name: "log-voice-filled", seed: "four", extra: ["-LHOpenLog", "voiceFilled"], waitFor: "log.fill.caption"),
        Shot(name: "log-voice-denied", seed: "four", extra: ["-LHOpenLog", "voiceDenied", "-LHVoiceDenied"], waitFor: "log.voice.denied"),
        Shot(name: "timer-idle", seed: "four", extra: ["-LHOpenLog", "timerIdle"], waitFor: "timer.start"),
        Shot(name: "timer-running", seed: "four", extra: ["-LHOpenLog", "timerRunning"], waitFor: "timer.card"),
        Shot(name: "timer-review", seed: "four", extra: ["-LHOpenLog", "timerReview"], waitFor: "log.timer.ran"),
        // Apple's model filling the note (scripted model tier, the real reader and form).
        Shot(name: "ai-thinking", seed: "four", extra: ["-LHOpenLog", "aiNote", "-LHNoteModel", "thinking"], waitFor: "log.reading", settle: 1.5),
        Shot(name: "ai-filled", seed: "four", extra: ["-LHOpenLog", "aiNote", "-LHNoteModel", "fake"], waitFor: "log.description", settle: 1.5,
             scrollTo: "log.date"),
        Shot(name: "ai-undone", seed: "four", extra: ["-LHOpenLog", "aiNote", "-LHNoteModel", "fake"], waitFor: "log.description", settle: 1.0,
             tap: "log.fill.undo", then: "log.property"),
        Shot(name: "ai-partial", seed: "four", extra: ["-LHOpenLog", "aiPartial", "-LHNoteModel", "fake"], waitFor: "log.fill.caption", settle: 1.5),
        Shot(name: "ai-two-rentals", seed: "four", extra: ["-LHOpenLog", "aiTwoRentals", "-LHNoteModel", "fake"], waitFor: "log.propertyHint", settle: 1.5),
        Shot(name: "ai-rules-only", seed: "four", extra: ["-LHOpenLog", "aiNote", "-LHNoteModel", "unavailable"], waitFor: "log.fill.caption", settle: 1.5),
        Shot(name: "picker-category", seed: "four", extra: ["-LHOpenLog", "pickerCategory"], waitFor: "picker.category", settle: 2),
        Shot(name: "picker-property", seed: "four", extra: ["-LHOpenLog", "pickerProperty"], waitFor: "picker.property", settle: 2),
        Shot(name: "pane-probe", seed: "four", extra: ["-LHOpenLog", "nfModel", "-LHLogPlacement", "pane"], waitFor: "log.fill.caption"),
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


    // MARK: Note-first frames (2.1)
    //
    // The 17 states of the approved prototype, as the real sheet: light and dark, default size and AX3.
    // Names follow the prototype's frames: `{scheme}-{def|ax3}-{NN}-{state}`.

    private struct NFShot {
        let name: String
        let state: String
        let waitFor: String
        var seed = "four"
        var extra: [String] = []
        var settle = 1.2
    }

    private let nfShots: [NFShot] = [
        NFShot(name: "01-initial", state: "nfInitial", waitFor: "log.note", settle: 1.8),
        NFShot(name: "02a-typing", state: "nfTyping", waitFor: "log.note", settle: 1.8),
        NFShot(name: "02b-rules-fill", state: "nfRules", waitFor: "log.reading"),
        NFShot(name: "03-model-landed", state: "nfModel", waitFor: "log.fill.caption"),
        NFShot(name: "04a-partial-no-hours", state: "nfPartialHours", waitFor: "log.fill.caption"),
        NFShot(name: "04b-partial-kind-empty", state: "nfPartialKind", waitFor: "log.category"),
        NFShot(name: "05-two-rentals", state: "nfTwoRentals", waitFor: "log.propertyHint"),
        NFShot(name: "06a-zero-property", state: "nfZero", waitFor: "log.rentalName", seed: "empty"),
        NFShot(name: "06b-zero-named", state: "nfZeroNamed", waitFor: "log.rentalName", seed: "empty"),
        NFShot(name: "07a-inline-edit-hours", state: "nfEditHours", waitFor: "log.hours.value"),
        NFShot(name: "07b-undone", state: "nfUndone", waitFor: "log.rows"),
        NFShot(name: "08a-voice-listening", state: "nfListening", waitFor: "log.listening"),
        NFShot(name: "08b-mic-intro", state: "nfMicIntro", waitFor: "log.voice.intro"),
        NFShot(name: "09-model-swap-caution", state: "nfSwap", waitFor: "log.updated.undo"),
        NFShot(name: "10-enter-details-yourself", state: "nfManual", waitFor: "log.autoFill.on"),
        NFShot(name: "11-toast", state: "nfToast", waitFor: "shell.toast", settle: 1.0),
        NFShot(name: "12-timer-review", state: "timerReview", waitFor: "log.timer.ran"),
    ]

    func testCaptureNoteFirstLightDefault() { captureNoteFirst(scheme: "light", size: nil) }
    func testCaptureNoteFirstDarkDefault() { captureNoteFirst(scheme: "dark", size: nil) }
    func testCaptureNoteFirstLightXXL() { captureNoteFirst(scheme: "light", size: "xxl") }
    func testCaptureNoteFirstDarkXXL() { captureNoteFirst(scheme: "dark", size: "xxl") }
    func testCaptureNoteFirstLightAX3() { captureNoteFirst(scheme: "light", size: "ax3") }
    func testCaptureNoteFirstDarkAX3() { captureNoteFirst(scheme: "dark", size: "ax3") }
    func testCaptureNoteFirstLightAX5() { captureNoteFirst(scheme: "light", size: "ax5", only: ["01-initial", "03-model-landed", "05-two-rentals", "07a-inline-edit-hours", "06a-zero-property"]) }
    func testCaptureNoteFirstDarkAX5() { captureNoteFirst(scheme: "dark", size: "ax5", only: ["01-initial", "03-model-landed", "05-two-rentals", "07a-inline-edit-hours", "06a-zero-property"]) }

    private func captureNoteFirst(scheme: String, size: String?, only: Set<String>? = nil) {
        continueAfterFailure = true
        let tag = size ?? "def"
        for shot in nfShots where only?.contains(shot.name) ?? true {
            app.terminate()
            launch(seed: shot.seed, scheme: scheme, extra: ["-LHOpenLog", shot.state] + shot.extra + sizeArgs(size))
            XCTAssertTrue(element(shot.waitFor).waitForExistence(timeout: 15), "\(shot.name): \(shot.waitFor)")
            Thread.sleep(forTimeInterval: shot.settle)
            // The keyboard's one-time "slide to type" card would sit over the sheet.
            let tip = app.buttons["Continue"]
            if tip.exists { tip.tap(); Thread.sleep(forTimeInterval: 0.6) }
            capture("\(scheme)-\(tag)-\(shot.name)")
        }
    }

    /// The post-log handoff, captured as a screen recording by the caller: types a note into the real
    /// sheet, waits for the rules and the scripted model, taps Log. `-LHLogScript` drives it.
    func testScriptedUnfoldAndLog() {
        launch(seed: "four", scheme: "dark", extra: ["-LHNoteModel", "fake", "-LHLogScript", "full"])
        XCTAssertTrue(element("shell.toast").waitForExistence(timeout: 40), "the script logs the entry")
        Thread.sleep(forTimeInterval: 2)
    }

    func testScriptedModelSwapShowsTheRowsOwnUndo() {
        launch(seed: "four", scheme: "light", extra: ["-LHNoteModel", "swap", "-LHLogScript", "swap", "-LHLogNoLog", "1"])
        XCTAssertTrue(element("log.updated.undo").waitForExistence(timeout: 20), "a late model answer says it updated the row")
        element("log.updated.undo").tap()
        XCTAssertTrue(element("log.updated.undo").waitForNonExistence(timeout: 8))
    }

    private func sizeArgs(_ size: String?) -> [String] {
        switch size {
        case "xxl": return ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"]
        case "ax3": return ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        case "ax5": return ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        default: return []
        }
    }

    /// Package E (v2): the states the note-first set does not cover, light and dark, default / XXL / AX3.
    func testCaptureV2Extras() {
        let names: Set<String> = ["log-filled-spouse", "log-not-counted", "log-save-failed", "log-keyboard", "log-voice-denied",
                                  "timer-idle", "timer-running", "picker-category", "picker-property",
                                  "today-timer-running", "today-timer-draft"]
        for scheme in ["light", "dark"] {
            for size in [nil, "xxl", "ax3"] as [String?] { captureAll(scheme: scheme, size: size, names: names) }
        }
    }

    private static let extraNames: Set<String> = ["log-filled-spouse", "log-not-counted", "log-save-failed", "log-keyboard", "log-voice-denied",
                                                  "timer-idle", "timer-running", "picker-category", "picker-property"]
    func testCaptureExtrasLightDefault() { captureAll(scheme: "light", size: nil, names: Self.extraNames) }
    func testCaptureExtrasDarkDefault() { captureAll(scheme: "dark", size: nil, names: Self.extraNames) }
    func testCaptureExtrasLightXXL() { captureAll(scheme: "light", size: "xxl", names: Self.extraNames) }
    func testCaptureExtrasDarkXXL() { captureAll(scheme: "dark", size: "xxl", names: Self.extraNames) }
    func testCaptureExtrasLightAX3() { captureAll(scheme: "light", size: "ax3", names: Self.extraNames) }
    func testCaptureExtrasDarkAX3() { captureAll(scheme: "dark", size: "ax3", names: Self.extraNames) }

    /// The Who control's selected state, scrolled clear of the pinned footer at every size.
    func testCaptureWhoOnly() {
        for scheme in ["light", "dark"] {
            for size in [nil, "xxl", "ax3"] as [String?] { captureAll(scheme: scheme, size: size, names: ["log-filled-spouse"]) }
        }
    }

    /// Final fix round: the disabled mic (log-voice-denied), the empty note's placeholder at every size
    /// (log-empty), and the Who control with Spouse selected, light and dark, default / XXL / AX3.
    func testCaptureEFinal() {
        let names: Set<String> = ["log-empty", "log-voice-denied", "log-filled-spouse"]
        for scheme in ["light", "dark"] {
            for size in [nil, "xxl", "ax3"] as [String?] { captureAll(scheme: scheme, size: size, names: names) }
        }
    }

    func testCapturePaneProbe() {
        for scheme in ["light", "dark"] { captureAll(scheme: scheme, size: nil, names: ["pane-probe"]) }
    }

    /// The states a fix touched, in every scheme and size.
    func testCaptureFixups() {
        let names: Set<String> = ["log-typed", "log-filled-spouse", "log-save-failed", "log-not-counted", "log-invalid"] 
        for scheme in ["light", "dark"] {
            for size in [nil, "xxl", "ax3"] as [String?] { captureAll(scheme: scheme, size: size, names: names) }
        }
    }

    /// Apple's model filling the note: thinking, filled, Undo, partial, no model → rules.
    /// Frames changed by the 44pt Undo target and the Date-row scroll (round 2).
    func testCaptureAIFillFixups() {
        let names: Set<String> = ["ai-filled", "ai-partial", "ai-rules-only", "ai-two-rentals"]
        for scheme in ["light", "dark"] {
            for size in [nil, "xxl", "ax3"] as [String?] { captureAll(scheme: scheme, size: size, prefix: "ai-", names: names) }
        }
    }

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
            var target = element(shot.waitFor)
            XCTAssertTrue(target.waitForExistence(timeout: 15), "\(shot.name): \(shot.waitFor)")
            if let tap = shot.tap {
                // Let the fill settle, then tap (Undo) and wait for the result.
                Thread.sleep(forTimeInterval: 1.2)
                let button = element(tap)
                if button.waitForExistence(timeout: 6) { button.tap() }
                if let then = shot.then { XCTAssertTrue(element(then).waitForExistence(timeout: 6), "\(shot.name): \(then)") }
                XCTAssertFalse(element("log.description").exists, "\(shot.name): Undo cleared the description")
                // The waited-for element may be gone after the tap: scroll to the result instead.
                target = element(shot.then ?? "log.property")
            }
            if let scrollTo = shot.scrollTo {
                // The fill lands after ~1 s; scroll once the row is final.
                Thread.sleep(forTimeInterval: 1.2)
                target = element(scrollTo)
            }
            if shot.waitFor != "shell.toast" && shot.waitFor != "log.done" {
                // Today's card sits under the hero, and at AX sizes a sheet's state (the Who row,
                // the save error) can sit below the fold: scroll it fully into view.
                let today = app.buttons["tab.today"]
                var bottom = shot.name.hasPrefix("today-") ? today.frame.minY : app.windows.firstMatch.frame.maxY - 24
                // A row the pinned Log button would fade over must clear the button.
                let save = app.buttons["log.save"]
                if shot.scrollTo != nil, save.exists { bottom = min(bottom, save.frame.minY - 48) }
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
            if shot.selectSpouse {
                let spouse = element("log.who").buttons["Spouse"]
                XCTAssertTrue(spouse.waitForExistence(timeout: 6), "\(shot.name): Spouse segment")
                spouse.tap()
                Thread.sleep(forTimeInterval: 0.6)
                XCTAssertTrue(spouse.isSelected, "\(shot.name): Spouse is the selected segment")
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
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 15) || app.buttons["sheet.close"].waitForExistence(timeout: 25)
                      || element("shell.toast").exists)   // the toast state logs and dismisses the sheet before the bar is reachable
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
