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
        // The samples fire 3–6 s after launch (in the foreground they go straight to the list).
        Thread.sleep(forTimeInterval: 12)

        // Lock the device: the Lock Screen shows the delivered notifications.
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        Thread.sleep(forTimeInterval: 2)
        // Wake the screen without unlocking (the side button again, then a short wait).
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        Thread.sleep(forTimeInterval: 3)
        let anyPrompt = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Plumber visit'")).firstMatch
        if !anyPrompt.waitForExistence(timeout: 5) {
            // Older stacks collapse: swipe up on the list to expand it.
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
            Thread.sleep(forTimeInterval: 1.5)
        }
        XCTAssertTrue(anyPrompt.waitForExistence(timeout: 5), "End-of-visit notification on the Lock Screen")
        shoot("stack", scheme)

        // Tap the stack: iOS expands the group, so every notification shows with its title.
        anyPrompt.tap()
        Thread.sleep(forTimeInterval: 2)
        shoot("list", scheme)

        // Long-press the end-of-visit prompt: the platter grows and the three actions appear.
        let prompt = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Plumber visit just ended'")).firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.press(forDuration: 1.5)
        Thread.sleep(forTimeInterval: 1.5)
        let notRental = springboard.descendants(matching: .any)["Not rental work"]
        // The simulator's Lock Screen doesn't always open the long-press menu; the action titles
        // and icons are covered by NotificationCopyTests. Capture the menu when it shows.
        if notRental.waitForExistence(timeout: 5) {
            XCTAssertTrue(springboard.descendants(matching: .any)["Log it"].exists)
            XCTAssertTrue(springboard.descendants(matching: .any)["Edit…"].exists)
            shoot("actions", scheme)
        }
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
