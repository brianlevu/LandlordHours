import XCTest

/// §1.27 hand-off frames: every top-level screen (Today, Inbox, Records, Rentals, Settings, Reports,
/// Log time) in light and dark, at the default size (L) and XXL, in the orientation the run asks for
/// (`TEST_RUNNER_LH_ORIENT` = `portrait` | `landscape`, default portrait). Each frame is a kept
/// attachment named `screen-<mode>-<orientation>-<screen>-<theme>-<size>`, where mode is `twopane`
/// or `compact` as the app laid it out. Run with -only-testing; a capture helper, not a check.
final class AdaptiveScreensCaptureUITests: XCTestCase {
    private var app: XCUIApplication!

    private static let screens: [(String, Int)] = [("today", 0), ("inbox", 5), ("records", 6), ("rentals", 1),
                                                   ("settings", 4), ("reports", 3), ("logtime", 2)]
    private static let sizes: [(String, String)] = [("L", "UICTContentSizeCategoryL"), ("XXL", "UICTContentSizeCategoryXXL")]

    override func setUp() {
        continueAfterFailure = true
    }

    private var orientation: (UIDeviceOrientation, String) {
        ProcessInfo.processInfo.environment["LH_ORIENT"] == "landscape" ? (.landscapeLeft, "landscape") : (.portrait, "portrait")
    }

    func testCaptureTopLevelScreens() {
        let (device, tag) = orientation
        XCUIDevice.shared.orientation = device
        for theme in ["light", "dark"] {
            for (size, category) in Self.sizes {
                for (screen, tab) in Self.screens {
                    app = XCUIApplication()
                    app.launchArguments = [UITestIsolation.resetProfilesArgument, "-LHMockScenario", "emptyMainTabs",
                                           "-LHSeedSuggestions", "inbox", "-LHCraftSeed", "craft", "-LHCraftWindows", "lit",
                                           "-LHAdaptiveSelect", "3", "-LHInitialTab", "\(tab)",
                                           "-LHColorScheme", theme, "-UIPreferredContentSizeCategoryName", category,
                                           "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
                    app.launch()
                    XCUIDevice.shared.orientation = device
                    let twoPane = app.descendants(matching: .any)["pane.house"].waitForExistence(timeout: 8)
                    sleep(3)
                    let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    shot.name = "screen-\(twoPane ? "twopane" : "compact")-\(tag)-\(screen)-\(theme)-\(size)"
                    shot.lifetime = .keepAlways
                    add(shot)
                    app.terminate()
                }
            }
        }
    }
}
