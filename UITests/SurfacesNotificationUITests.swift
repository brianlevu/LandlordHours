import XCTest

/// 2.0 surfaces: the real notifications, OS-rendered (not a mock). The app (DEBUG,
/// `-LHDebugPostSampleNotifications`) posts the NotificationCopy samples after a delay; this test
/// allows the permission prompt and goes Home, long-presses the end-of-visit BANNER as it arrives
/// (the expanded platter with Log it / Edit… / Not rental work), then locks the device and captures
/// the stacked group and the expanded list. Run each theme on a FRESH simulator (Springboard keeps a
/// group's expanded state). Frames go to $LH_SHOT_DIR (TEST_RUNNER_LH_SHOT_DIR) as notif-<step>-<scheme>.png.
final class SurfacesNotificationUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func testCaptureNotifications() throws {
        let scheme = ProcessInfo.processInfo.environment["LH_SCHEME"] ?? "light"
        let app = XCUIApplication()
        app.launchArguments = [
            "-LHMockScenario", "occasional",
            "-LHDebugPostSampleNotifications", "-LHDebugNotificationDelay", "14",
            "-LHColorScheme", scheme,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()

        // Allow notifications (asked once per install).
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 8) { allow.tap() }
        XCUIDevice.shared.press(.home)

        // 1. The end-of-visit banner (fires last): long-press it for the three actions.
        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Plumber visit just ended'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 30), "End-of-visit banner delivered")
        banner.press(forDuration: 1.5)
        let notRental = springboard.descendants(matching: .any)["Not rental work"]
        XCTAssertTrue(notRental.waitForExistence(timeout: 6), "Actions: Not rental work")
        XCTAssertTrue(springboard.descendants(matching: .any)["Log it"].exists, "Actions: Log it")
        XCTAssertTrue(springboard.descendants(matching: .any)["Edit…"].exists, "Actions: Edit…")
        Thread.sleep(forTimeInterval: 1)
        shoot("actions", scheme)

        // Close the menu without choosing an action.
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)

        // 2. Lock and wake: the Lock Screen shows the group stacked.
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        Thread.sleep(forTimeInterval: 2)
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        Thread.sleep(forTimeInterval: 3)
        let top = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Plumber visit'")).firstMatch
        if !top.waitForExistence(timeout: 5) {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
            Thread.sleep(forTimeInterval: 1.5)
        }
        XCTAssertTrue(top.waitForExistence(timeout: 5), "Notifications on the Lock Screen")
        shoot("stack", scheme)

        // 3. Tap the stack: every notification with its title.
        top.tap()
        Thread.sleep(forTimeInterval: 2)
        shoot("list", scheme)
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
