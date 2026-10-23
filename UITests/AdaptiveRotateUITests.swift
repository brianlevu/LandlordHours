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
}
