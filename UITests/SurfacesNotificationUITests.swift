import XCTest

/// 2.0 surfaces: the real notifications on the simulator's Notification Center (OS-rendered, not a
/// mock). The app (DEBUG, `-LHDebugPostSampleNotifications`) posts the NotificationCopy samples; this
/// test allows the permission prompt, goes Home, opens Notification Center and long-presses the
/// end-of-visit prompt to show its three actions. Frames go to $LH_SHOT_DIR when set
/// (TEST_RUNNER_LH_SHOT_DIR), named notif-<step>-<scheme>.png.
final class SurfacesNotificationUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func testCaptureNotifications() throws {
        let scheme = ProcessInfo.processInfo.environment["LH_SCHEME"] ?? "light"
        let app = XCUIApplication()
        app.launchArguments = [
            "-LHMockScenario", "occasional",
            "-LHDebugPostSampleNotifications",
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()

        // Allow notifications (only asked once per install).
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 8) { allow.tap() }

        XCUIDevice.shared.press(.home)
        // Samples fire 3–6 s after permission; wait for the last (end of visit) as a banner.
        let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Plumber visit just ended'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "End-of-visit notification delivered")
        Thread.sleep(forTimeInterval: 6)

        // Notification Center: swipe down from the top-left.
        let start = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.005))
        let end = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: end)
        Thread.sleep(forTimeInterval: 2)
        shoot("list", scheme)

        // Long-press the end-of-visit prompt: the platter grows and the three actions appear.
        let prompt = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Plumber visit just ended'")).firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.press(forDuration: 1.2)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(springboard.buttons["Not rental work"].waitForExistence(timeout: 5), "Third action label")
        XCTAssertTrue(springboard.buttons["Log it"].exists)
        shoot("expanded", scheme)
    }

    private func shoot(_ step: String, _ scheme: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "notif-\(step)-\(scheme)"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["LH_SHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("notif-\(step)-\(scheme).png"))
        }
    }
}
