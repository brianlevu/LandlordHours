import XCTest

/// Capture helpers for the adaptive mockups (DEBUG screens, -LHAdaptive). Not part of any gate.
final class AdaptiveRotateUITests: XCTestCase {
    func testLandscape() { XCUIDevice.shared.orientation = .landscapeLeft; Thread.sleep(forTimeInterval: 1.5) }
    func testPortrait() { XCUIDevice.shared.orientation = .portrait; Thread.sleep(forTimeInterval: 1.5) }

    /// Drags the iPadOS window's resize grip (bottom-right) through the band edges, holding at each
    /// width, so the recording shows A→B→C and the 8pt hysteresis on a real window.
    func testResizeWindow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-LHAdaptive", "today", "-LHAdaptiveSidebar", "hidden", "-lh.probe.layout", "-LHSkyTime", "day"]
        app.launch()
        Thread.sleep(forTimeInterval: 3)
        let screen = XCUIApplication(bundleIdentifier: "com.apple.springboard").coordinate(withNormalizedOffset: .zero)
        let targets: [CGFloat] = [1000, 896, 884, 900, 916, 700, 596, 584, 604, 616, 1000, 1376]
        for t in targets {
            let f = app.windows.firstMatch.frame
            let from = CGVector(dx: f.maxX - 4, dy: f.maxY - 4)
            let to = CGVector(dx: min(f.minX + t, 1376) - 4, dy: f.maxY - 4)
            screen.withOffset(from).press(forDuration: 0.5, thenDragTo: screen.withOffset(to), withVelocity: 250, thenHoldForDuration: 0.4)
            Thread.sleep(forTimeInterval: 1.8)
            print("ADAPTIVE-RESIZE target \(t) window \(app.windows.firstMatch.frame)")
        }
    }

    /// R12 capture: shrinks the window to a compact width (< 520pt) and attaches a screenshot.
    func testNarrowWindow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-LHAdaptive", "today", "-lh.probe.layout", "-LHSkyTime", "day"]
        app.launch()
        Thread.sleep(forTimeInterval: 3)
        let screen = XCUIApplication(bundleIdentifier: "com.apple.springboard").coordinate(withNormalizedOffset: .zero)
        for _ in 0..<4 {
            let f = app.windows.firstMatch.frame
            if f.width < 520 { break }
            screen.withOffset(CGVector(dx: f.maxX - 4, dy: f.maxY - 4))
                .press(forDuration: 0.5, thenDragTo: screen.withOffset(CGVector(dx: f.minX + 480, dy: f.maxY - 4)), withVelocity: 250, thenHoldForDuration: 0.4)
            Thread.sleep(forTimeInterval: 2)
        }
        Thread.sleep(forTimeInterval: 2)
        print("ADAPTIVE-NARROW window \(app.windows.firstMatch.frame)")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "narrow-window"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Undo testNarrowWindow: the window frame persists per app, even across reinstalls.
    func testFillWindow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-LHAdaptive", "today"]
        app.launch()
        Thread.sleep(forTimeInterval: 3)
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let screen = sb.coordinate(withNormalizedOffset: .zero)
        let f = app.windows.firstMatch.frame
        print("ADAPTIVE-FILL before \(f)")
        screen.withOffset(CGVector(dx: f.minX + 51, dy: f.minY + 43)).tap()
        Thread.sleep(forTimeInterval: 2)
        for label in ["Zoom", "Fill", "Full Screen"] {
            let b = sb.buttons[label]
            if b.exists { b.tap(); print("ADAPTIVE-FILL tapped \(label)"); break }
        }
        Thread.sleep(forTimeInterval: 2)
        print("ADAPTIVE-FILL after \(app.windows.firstMatch.frame)")
        print("ADAPTIVE-FILL sb buttons \(sb.buttons.allElementsBoundByIndex.prefix(30).map { $0.label })")
    }
}
