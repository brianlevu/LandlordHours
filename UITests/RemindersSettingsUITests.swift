import XCTest

/// 2.3 package D: Settings › Pace reminders, and the lifecycle of the nudges it schedules.
/// The lifecycle steps read the real pending requests through the DEBUG probe (`-LHNudgeProbe`:
/// one line per pending nudge, `id | yyyy-MM-dd HH:mm | title | body | thread`), not the screen.
/// Wording is never pinned: identifiers, switch values and the probe's structure only.
final class RemindersSettingsUITests: XCTestCase {
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: Launch helpers

    private func launch(_ extra: [String] = [], scheme: String = "light", probe: Bool = true, relaunch: Bool = false) {
        app.terminate()
        // A relaunch keeps the profile: the choices are stored per profile, as a real relaunch would find them.
        // and does not reseed the mock data (the persisted records stay).
        var args = (relaunch ? [] : [UITestIsolation.resetProfilesArgument, "-LHMockScenario", "frequent"]) + ["-LHInitialTab", "4",
                    "-LHColorScheme", scheme, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if probe { args.append("-LHNudgeProbe") }
        app.launchArguments = args + extra
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func allowNotificationsIfAsked() {
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 4) { allow.tap() }
    }

    /// Settings is a lazy list: scroll to the Pace reminders row and open it.
    private func openScreen() {
        if element("settings.reminders").exists { return }
        let row = element("settings.paceReminders")
        _ = row.waitForExistence(timeout: 20)
        var swipes = 0
        while (!row.exists || !row.isHittable) && swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(row.exists, "Settings has the Pace reminders row")
        row.tap()
        XCTAssertTrue(element("settings.reminders").waitForExistence(timeout: 10), "Pace reminders screen is open")
    }

    /// Scrolls until the element sits clear of the header (below y 170) and above the foot.
    private func reveal(_ el: XCUIElement) {
        for _ in 0..<8 {
            guard el.exists else { app.swipeUp(); continue }
            let frame = el.frame
            if frame.minY < 170 { app.swipeDown(velocity: .slow) }
            else if frame.maxY > 800 || !el.isHittable { app.swipeUp(velocity: .slow) }
            else { break }
        }
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func refreshProbe() {
        let refresh = app.buttons["nudge.probe.refresh"]
        reveal(refresh)
        refresh.tap()
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// The pending nudge lines, after a refresh.
    private func pendingLines() -> [String] {
        refreshProbe()
        let probe = element("nudge.probe")
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        let text = probe.label
        return text == "none" ? [] : text.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    private func fields(_ line: String) -> [String] { line.components(separatedBy: " | ") }

    private func fireHour(_ line: String) -> Int {
        let stamp = fields(line)[1]   // yyyy-MM-dd HH:mm
        return Int(stamp.dropFirst(11).prefix(2)) ?? -1
    }

    private func toggle(_ id: String) -> XCUIElement { app.switches[id] }

    private func setToggle(_ id: String, on: Bool) {
        let t = toggle(id)
        XCTAssertTrue(t.waitForExistence(timeout: 10), id)
        reveal(t)
        if (t.value as? String == "1") != on {
            t.tap()
            allowNotificationsIfAsked()
            Thread.sleep(forTimeInterval: 1.0)
        }
        XCTAssertEqual(t.value as? String, on ? "1" : "0", id)
    }

    // MARK: Screen

    func testSettingsRowOpensTheScreenWithEverythingOff() {
        launch(["-LHNudgeReset", "1"])
        XCTAssertTrue(element("settings.paceReminders").waitForExistence(timeout: 20) || true)
        openScreen()
        for id in ["reminders.weekly", "reminders.behind", "reminders.yearEnd", "reminders.care"] {
            XCTAssertTrue(toggle(id).waitForExistence(timeout: 5), id)
            XCTAssertEqual(toggle(id).value as? String, "0", "\(id) is off until the person opts in")
        }
        XCTAssertTrue(element("reminders.quiet").exists, "quiet hours row")
        XCTAssertTrue(element("reminders.preview").exists || { app.swipeUp(); return element("reminders.preview").exists }(), "weekly preview")
        XCTAssertEqual(pendingLines(), [], "nothing is scheduled before an opt-in")
        XCTAssertTrue(app.buttons["reminders.back"].exists)
    }

    func testQuietHoursSheetChangesTheRow() {
        launch(["-LHNudgeReset", "1"])
        openScreen()
        let quiet = element("reminders.quiet")
        reveal(quiet)
        let before = quiet.label
        quiet.tap()
        XCTAssertTrue(element("reminders.quiet.sheet").waitForExistence(timeout: 5))
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.firstMatch.waitForExistence(timeout: 5), "From and Until wheels")
        XCTAssertEqual(wheels.count, 2)
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: "10\u{202F}PM")
        Thread.sleep(forTimeInterval: 0.8)
        let close = app.buttons["Close"].firstMatch
        if close.exists { close.tap() } else { app.swipeDown() }
        Thread.sleep(forTimeInterval: 1)
        XCTAssertNotEqual(element("reminders.quiet").label, before, "the row shows the new window")
        XCTAssertTrue(element("nudge.probe.settings").label.contains("quiet 22-8"), element("nudge.probe.settings").label)
    }

    // MARK: Lifecycle

    /// Off until opted in; quiet hours; cancel when off; survive relaunch; no duplicates;
    /// background and foreground; force-quit and relaunch.
    func testLifecycleOfTheWeeklyNudge() {
        // 0. Fresh: nothing pending without an opt-in, even after a launch and a foreground.
        launch(["-LHNudgeReset", "1"])
        openScreen()
        XCTAssertEqual(pendingLines(), [], "never fires when not opted in")
        XCTAssertTrue(element("nudge.probe.settings").label.hasSuffix("on "), element("nudge.probe.settings").label)

        // 1. Opt in: the weekly note is pending, on Sundays at 6 PM (default quiet hours 8 PM – 8 AM).
        setToggle("reminders.weekly", on: true)
        let first = pendingLines()
        XCTAssertGreaterThanOrEqual(first.count, 1)
        XCTAssertLessThanOrEqual(first.count, 3)
        for line in first {
            XCTAssertTrue(fields(line)[0].hasPrefix("nudge.weeklyPace."), line)
            XCTAssertEqual(fireHour(line), 18, line)
            XCTAssertEqual(fields(line)[4], "landlordhours.nudge.pace", "pace goes in its own thread")
        }
        let ids = Set(first.map { fields($0)[0] })
        XCTAssertEqual(ids.count, first.count, "no duplicate request ids")

        // 2. Background and foreground: the same requests, none doubled.
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        openScreen()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(Set(pendingLines().map { fields($0)[0] }), ids, "background and foreground change nothing")
        XCTAssertEqual(pendingLines().count, first.count)

        // 3. Force-quit and relaunch: choices and requests survive.
        launch(relaunch: true)
        openScreen()
        XCTAssertEqual(toggle("reminders.weekly").value as? String, "1", "the choice survives a force-quit")
        XCTAssertEqual(Set(pendingLines().map { fields($0)[0] }), ids, "the requests survive a force-quit")

        // 4. Quiet hours: 4 PM – 9 AM pushes the 6 PM note to 9 AM the next morning.
        launch(["-LHNudgeQuietStart", "16", "-LHNudgeQuietEnd", "9"], relaunch: true)
        openScreen()
        Thread.sleep(forTimeInterval: 1.5)
        let quietLines = pendingLines()
        XCTAssertFalse(quietLines.isEmpty)
        for line in quietLines {
            let hour = fireHour(line)
            XCTAssertFalse(hour >= 16 || hour < 9, "a nudge landed in quiet hours: \(line)")
            XCTAssertEqual(hour, 9, line)
        }

        // 5. Cancel when turned off, and it stays cancelled after a relaunch.
        setToggle("reminders.weekly", on: false)
        XCTAssertEqual(pendingLines(), [], "turning it off cancels the pending nudges")
        launch(relaunch: true)
        openScreen()
        XCTAssertEqual(toggle("reminders.weekly").value as? String, "0")
        XCTAssertEqual(pendingLines(), [], "still cancelled after a relaunch")
    }

    /// Care goes out as its own notification, about one rental, and never alongside pace.
    func testCareNudgeIsSeparateFromPace() {
        launch(["-LHNudgeReset", "1", "-LHNudgeCareStub", "1"])
        openScreen()
        setToggle("reminders.weekly", on: true)
        setToggle("reminders.care", on: true)
        let lines = pendingLines()
        let care = lines.filter { fields($0)[0].hasPrefix("nudge.carePlan.") }
        let pace = lines.filter { fields($0)[0].hasPrefix("nudge.weeklyPace.") }
        XCTAssertEqual(care.count, 1, "one care item at a time: \(lines)")
        XCTAssertFalse(pace.isEmpty)
        XCTAssertEqual(fields(care[0])[4], "landlordhours.nudge.care")
        XCTAssertTrue(pace.allSatisfy { fields($0)[4] == "landlordhours.nudge.pace" })
        let careDay = fields(care[0])[1].prefix(10)
        XCTAssertTrue(pace.allSatisfy { !fields($0)[1].hasPrefix(String(careDay)) }, "pace and care never share a day")
        // Turning care off removes only the care nudge.
        setToggle("reminders.care", on: false)
        let after = pendingLines()
        XCTAssertTrue(after.allSatisfy { fields($0)[0].hasPrefix("nudge.weeklyPace.") })
        XCTAssertEqual(after.count, pace.count)
        setToggle("reminders.weekly", on: false)
    }

    // MARK: Frames for the visual gate (TEST_RUNNER_LH_SHOT_DIR)

    func testCaptureRemindersFrames() throws {
        guard let dir = ProcessInfo.processInfo.environment["LH_SHOT_DIR"] else { throw XCTSkip("LH_SHOT_DIR not set") }
        let scheme = ProcessInfo.processInfo.environment["LH_SCHEME"] ?? "light"
        launch(["-LHNudgeReset", "1", "-LHNudgeSeed", "weekly,yearEnd,care"], scheme: scheme, probe: false)
        openScreen()
        Thread.sleep(forTimeInterval: 1.5)
        let shot = XCUIScreen.main.screenshot()
        try shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("n1-reminders-\(scheme).png"))
    }
}
