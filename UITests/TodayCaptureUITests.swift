import XCTest

/// Frames for the visual gate: every Today state below the house, light and dark, at the default
/// size, XXL and AX3. Runs only when `LH_CAPTURE_DIR` is set
/// (`TEST_RUNNER_LH_CAPTURE_DIR=<dir> xcodebuild test -only-testing:LandlordHoursUITests/TodayCaptureUITests`).
/// Pin the simulator's status bar first (`xcrun simctl status_bar <udid> override --time 9:41 …`).
final class TodayCaptureUITests: XCTestCase {
    private var app: XCUIApplication!
    private var dir: String { ProcessInfo.processInfo.environment["LH_CAPTURE_DIR"] ?? "" }

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(dir.isEmpty, "Captures only (set LH_CAPTURE_DIR)")
        UITestIsolation.resetStoreKit()
        continueAfterFailure = true
        app = XCUIApplication()
    }

    private enum Size: String, CaseIterable {
        case standard = "", xxl = "-xxl", ax3 = "-ax3"
        var category: String? {
            switch self {
            case .standard: return nil
            case .xxl: return "UICTContentSizeCategoryXXL"
            case .ax3: return "UICTContentSizeCategoryAccessibilityXL"
            }
        }
    }

    private static let hours = ["-LHMockScenario", "emptyMainTabs", "-LHTodayHours", "212"]
    private static let tuesday = ["-LHFixedNow", "2026-10-20T15:00"]

    /// name → (launch arguments, element that must exist before the frame is taken)
    private static let states: [(String, [String], String)] = [
        ("confirm", hours + tuesday + ["-LHSeedSuggestions", "inbox", "-LHTodayConfirmLimit", "3",
                                       "-LHTodayWeekSample", "1.5,0", "-LHTodayScrollTo", "confirm"], "today.confirm.card"),
        ("confirm-more", hours + tuesday + ["-LHSeedSuggestions", "inbox", "-LHTodayWeekSample", "1.5,0",
                                            "-LHTodayScrollTo", "confirm"], "today.confirm.reviewAll"),
        ("swipe", hours + tuesday + ["-LHSeedSuggestions", "inbox", "-LHTodayConfirmLimit", "3",
                                     "-LHTodaySwipePreview", "112", "-LHTodayScrollTo", "confirm"], "today.confirm.card"),
        ("caughtup", hours + tuesday + ["-LHSeedSuggestions", "empty", "-LHTodayWeekSample", "1.5,0",
                                        "-LHTodayScrollTo", "confirm"], "today.caughtUp"),
        ("caughtup-off", hours + tuesday + ["-LHTodayWeekSample", "1.5,0", "-LHTodayScrollTo", "confirm"], "today.caughtUp.off"),
        ("loading", hours + tuesday + ["-LHSeedSuggestions", "empty", "-LHTodayScanning", "-LHTodayWeekSample", "1.5,0",
                                       "-LHTodayScrollTo", "confirm"], "today.lookingBack"),
        ("week", hours + ["-LHFixedNow", "2026-10-25T15:00", "-LHSeedSuggestions", "empty",
                          "-LHTodayWeekSample", "1.5,0,3,2,0,3,0", "-LHTodayScrollTo", "week"], "today.week"),
        ("week-midweek", hours + ["-LHFixedNow", "2026-10-22T15:00", "-LHSeedSuggestions", "empty",
                                  "-LHTodayWeekSample", "1.5,0,3,2", "-LHTodayScrollTo", "week"], "today.week"),
        ("record", hours + tuesday + ["-LHSeedSuggestions", "empty", "-LHTodayWeekSample", "1.5,0",
                                      "-LHTodayScrollTo", "record"], "today.yourRecord"),
        ("draft", tuesday + ["-LHSeedTimerDraft", "twoPending", "-LHTodayWeekSample", "2,1",
                             "-LHTodayScrollTo", "draft"], "draft.card"),
        ("noproperty", ["-LHMockScenario", "emptyMainTabs"], "today.hero"),
        // Goal-first hero (2.0 messaging): target in the eyebrow, whose count, and where you stand.
        ("hero-500-pace", base + tuesday + ["-LHGoalChoice", "mp500", "-LHTodayHours", "420"], "today.hero"),
        ("hero-500-behind", base + tuesday + ["-LHGoalChoice", "mp500", "-LHTodayHours", "212"], "today.hero"),
        ("hero-750-own", base + tuesday + ["-LHGoalChoice", "reps750", "-LHGoalPro", "me", "-LHTodayHours", "212"], "today.hero"),
        ("hero-750-spouse", base + tuesday + ["-LHGoalChoice", "reps750", "-LHGoalPro", "spouse", "-LHTodayHours", "212",
                                              "-LHTodaySpouseHours", "300"], "today.hero"),
        ("hero-750-reached", base + tuesday + ["-LHGoalChoice", "reps750", "-LHGoalPro", "me", "-LHTodayHours", "760"], "today.hero"),
        ("hero-100-confirm", base + tuesday + ["-LHGoalChoice", "mp100", "-LHTodayHours", "104", "-LHTodayNoOneMore", "unanswered"], "today.hero"),
        ("hero-100-str", base + tuesday + ["-LHGoalChoice", "mp100", "-LHTodayHours", "212", "-LHTodayStrHours", "86"], "today.hero"),
        ("hero-day1", base + tuesday + ["-LHGoalChoice", "reps750", "-LHTodayHours", "1"], "today.hero"),
        ("hero-day1-pending", ["-LHMockScenario", "emptyMainTabs", "-LHSeedSuggestions", "inbox"] + tuesday
            + ["-LHGoalChoice", "reps750", "-LHTodayHours", "1"], "today.hero"),
        ("hero-100-str-long", base + tuesday + ["-LHGoalChoice", "mp100", "-LHTodayHours", "212", "-LHTodayStrHours", "86",
                                                "-LHTodayStrName", "Lakefront Tahoe Cabin and Guest House"], "today.hero"),
        ("hero-record", base + tuesday + ["-LHGoalChoice", "record", "-LHTodayHours", "212"], "today.hero"),
    ]
    private static let base = ["-LHMockScenario", "emptyMainTabs", "-LHSeedSuggestions", "empty"]

    private func capture(_ state: String, then action: ((XCUIApplication) -> String?)? = nil, as name: String? = nil) {
        guard let (_, stateArgs, anchor) = Self.states.first(where: { $0.0 == state }) else { return XCTFail("No state \(state)") }
        let env = ProcessInfo.processInfo.environment
        // `LH_CAPTURE_REST=1`: the screen at rest (scroll top: header, hero and subtitle), named "-rest".
        let rest = env["LH_CAPTURE_REST"] == "1"
        var args = stateArgs
        if rest, let i = args.firstIndex(of: "-LHTodayScrollTo") { args.removeSubrange(i...(i + 1)) }
        let suffix = rest ? "-rest" : ""
        // `LH_CAPTURE_SIZES=ax3` (comma list of standard,xxl,ax3) limits the sizes.
        let sizes = env["LH_CAPTURE_SIZES"].map { list in Size.allCases.filter { list.split(separator: ",").contains(Substring($0 == .standard ? "standard" : String($0.rawValue.dropFirst()))) } } ?? Size.allCases
        // `LH_CAPTURE_SCHEMES=light` re-shoots one theme only (a fix round that changed one).
        let schemes = (ProcessInfo.processInfo.environment["LH_CAPTURE_SCHEMES"] ?? "light,dark")
            .split(separator: ",").map(String.init)
        for scheme in schemes {
            for size in sizes {
                app.terminate()
                var arguments = [UITestIsolation.resetProfilesArgument, "-LHNoSwipePeek", "-LHInitialTab", "0",
                                 "-LHColorScheme", scheme, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + args
                if let category = size.category { arguments += ["-UIPreferredContentSizeCategoryName", category] }
                app.launchArguments = arguments
                app.launch()
                let element = app.descendants(matching: .any)[rest ? "today.hero" : anchor]
                XCTAssertTrue(element.waitForExistence(timeout: 25), "\(state) \(scheme)\(size.rawValue): \(anchor)")
                Thread.sleep(forTimeInterval: 2.2)   // scroll hook (0.7s) + entrance motion settle
                if let action {
                    guard let waitFor = action(app) else { continue }
                    XCTAssertTrue(app.descendants(matching: .any)[waitFor].waitForExistence(timeout: 5), "\(name ?? state): \(waitFor)")
                    Thread.sleep(forTimeInterval: 0.6)
                }
                write("today-\(name ?? state)\(suffix)-\(scheme)\(size.rawValue)")
            }
        }
    }

    private func write(_ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testCaptureConfirm() { capture("confirm") }
    func testCaptureConfirmMore() { capture("confirm-more") }
    func testCaptureSwipe() { capture("swipe") }
    func testCaptureCaughtUp() { capture("caughtup") }
    func testCaptureCaughtUpOff() { capture("caughtup-off") }
    func testCaptureLoading() { capture("loading") }
    func testCaptureWeek() { capture("week") }
    func testCaptureWeekMidweek() { capture("week-midweek") }
    func testCaptureRecord() { capture("record") }
    func testCaptureDraft() { capture("draft") }
    func testCaptureNoProperty() { capture("noproperty") }
    /// The Inbox banner ("…count toward your hours") and the Properties rows ("520h this year · Long stays",
    /// "212h of 500h · A few nights"), light and dark, default and AX3.
    func testCaptureInboxAndProperties() {
        let args = ["-LHMockScenario", "emptyMainTabs", "-LHSeedSuggestions", "inbox"] + Self.tuesday
            + ["-LHGoalChoice", "mp500", "-LHTodayHours", "520", "-LHTodayStrHours", "212"]
        for scheme in ["light", "dark"] {
            for size in [Size.standard, Size.ax3] {
                app.terminate()
                var arguments = [UITestIsolation.resetProfilesArgument, "-LHNoSwipePeek", "-LHInitialTab", "0",
                                 "-LHColorScheme", scheme, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + args
                if let category = size.category { arguments += ["-UIPreferredContentSizeCategoryName", category] }
                app.launchArguments = arguments
                app.launch()
                XCTAssertTrue(app.buttons["tab.inbox"].waitForExistence(timeout: 25))
                app.buttons["tab.inbox"].tap()
                Thread.sleep(forTimeInterval: 2.0)
                write("inbox-banner-\(scheme)\(size.rawValue)")
                app.buttons["tab.properties"].tap()
                Thread.sleep(forTimeInterval: 2.0)
                write("properties-rows-\(scheme)\(size.rawValue)")
                if size == .ax3 {
                    app.swipeUp(velocity: .slow)
                    Thread.sleep(forTimeInterval: 1.0)
                    write("properties-rows-scrolled-\(scheme)\(size.rawValue)")
                }
            }
        }
    }

    /// 2.0.1: Brian's setup (goal 100; Delaney Ct and Yeandle Ave long stays, Santa Ray Ave short
    /// stays, no hours). Today names Santa Ray Ave in the eyebrow, flag and subtitle; the rows
    /// read "0h of 100h" only for Santa Ray Ave.
    func testCaptureBriansSetup() {
        let args = ["-LHMockScenario", "emptyMainTabs", "-LHSeedSuggestions", "empty", "-LHPropertiesSeed", "brian",
                    "-LHPropertiesGoal", "mp100", "-LHGoalChoice", "mp100"] + Self.tuesday
        for scheme in ["light", "dark"] {
            for size in [Size.standard, Size.ax3] {
                app.terminate()
                var arguments = [UITestIsolation.resetProfilesArgument, "-LHNoSwipePeek", "-LHInitialTab", "0",
                                 "-LHColorScheme", scheme, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + args
                if let category = size.category { arguments += ["-UIPreferredContentSizeCategoryName", category] }
                app.launchArguments = arguments
                app.launch()
                XCTAssertTrue(app.descendants(matching: .any)["today.hero"].waitForExistence(timeout: 25))
                Thread.sleep(forTimeInterval: 2.2)
                write("today-brian-\(scheme)\(size.rawValue)")
                app.buttons["tab.properties"].tap()
                Thread.sleep(forTimeInterval: 2.0)
                write("properties-brian-\(scheme)\(size.rawValue)")
            }
        }
    }

    func testCaptureHero100() {
        for state in ["hero-100-confirm", "hero-100-str", "hero-100-str-long"] { capture(state) }
    }

    func testCaptureHeroGoalFirst() {
        for state in ["hero-500-pace", "hero-500-behind", "hero-750-own", "hero-750-spouse", "hero-750-reached",
                      "hero-100-confirm", "hero-100-str", "hero-100-str-long", "hero-day1", "hero-day1-pending",
                      "hero-record", "noproperty"] { capture(state) }
    }

    /// The shared full-width Inbox toast after a confirm from Today (Undo showing).
    func testCaptureToast() {
        capture("confirm", then: { app in
            let confirm = app.buttons["inbox.confirm.cal:debug-plumber"]
            guard confirm.waitForExistence(timeout: 5), confirm.isHittable else { return nil }
            confirm.tap()
            return "inbox.toast"
        }, as: "toast")
    }
}
