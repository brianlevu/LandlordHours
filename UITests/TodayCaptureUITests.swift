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
    ]

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
