import XCTest

/// §1.27 must-prove 12 (the mode switch in a resizable window) and 16 (the mode settles the same at
/// 799/800 whichever side it is reached from). Drags the iPadOS window's resize grip, holds at each
/// width, lets it settle (0.3 s + margin), and checks the mode and that the tab survives. Needs a
/// windowed iPadOS (26+) simulator; skips when the window cannot be resized (full screen only).
/// Frames are kept attachments named `window-<width>-<mode>`.
final class AdaptiveWindowUITests: XCTestCase {
    private var app: XCUIApplication!
    private var screen: XCUICoordinate {
        XCUIApplication(bundleIdentifier: "com.apple.springboard").coordinate(withNormalizedOffset: .zero)
    }

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launchArguments = [UITestIsolation.resetProfilesArgument, "-LHMockScenario", "emptyMainTabs",
                               "-LHSeedSuggestions", "inbox", "-LHCraftSeed", "craft", "-LHCraftWindows", "lit",
                               "-LHAdaptiveSelect", "3", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        sleep(3)
    }

    override func tearDown() {
        fill()
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private var isTwoPane: Bool { app.descendants(matching: .any)["pane.house"].waitForExistence(timeout: 3) }

    /// Drags the bottom-trailing grip so the window is `width` wide; returns the width it got.
    @discardableResult
    private func resize(to width: CGFloat) -> CGFloat {
        for _ in 0..<3 {
            let f = app.windows.firstMatch.frame
            if abs(f.width - width) <= 1 { break }
            let from = CGVector(dx: f.maxX - 4, dy: f.maxY - 4)
            let to = CGVector(dx: f.minX + width - 4, dy: f.maxY - 4)
            screen.withOffset(from).press(forDuration: 0.5, thenDragTo: screen.withOffset(to), withVelocity: 250, thenHoldForDuration: 0.4)
            sleep(2)   // past the 0.3 s settle
        }
        return app.windows.firstMatch.frame.width
    }

    /// Back to the full window (the frame persists per app, even across reinstalls).
    private func fill() {
        guard let app else { return }
        let f = app.windows.firstMatch.frame
        let full = XCUIApplication(bundleIdentifier: "com.apple.springboard").windows.firstMatch.frame.width
        if full > 0, f.width < full - 1 { resize(to: full) }
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testModeSwitchSettlesTheSameFromBothSides() throws {
        let start = app.windows.firstMatch.frame.width
        let got = resize(to: start - 200)
        guard got < start - 50 else { throw XCTSkip("this simulator's window does not resize (no windowed iPadOS)") }
        XCTAssertGreaterThanOrEqual(app.windows.firstMatch.frame.height, 645, "the window must be tall enough for the width test")

        // Records selected first: a mode switch must keep the tab.
        let bar = app.tabBars.firstMatch
        if bar.buttons["Records"].waitForExistence(timeout: 5) { bar.buttons["Records"].tap() }

        // 800 from above, 799 from above, 799 from below, 800 from below; then the narrow windows.
        for (target, wantTwoPane) in [(CGFloat(900), true), (800, true), (799, false), (700, false), (799, false),
                                      (800, true), (375, false), (1000, true)] {
            let w = resize(to: target)
            let two = isTwoPane
            let mode = two ? "twopane" : "compact"
            attach("window-\(Int(w))-\(mode)")
            if abs(w - target) <= 1 {
                XCTAssertEqual(two, wantTwoPane, "window \(w) wide settled as \(mode)")
            } else {
                XCTContext.runActivity(named: "asked \(target), got \(w) (\(mode)); not asserted") { _ in }
            }
            if app.tabBars.firstMatch.buttons["Records"].exists {
                XCTAssertTrue(app.tabBars.firstMatch.buttons["Records"].isSelected, "\(w): the tab survives the mode switch")
            }
        }
    }
}
