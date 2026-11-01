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

    /// 2.3: a pace note and a care note arrive as two separate notifications, never one (frame n2).
    /// The samples are posted by the DEBUG hook `-LHNudgeFireSamples`. Matching is on the person's
    /// data (the hours, the rental), not on wording.
    func testNudgesArriveAsTwoSeparateNotifications() throws {
        let scheme = ProcessInfo.processInfo.environment["LH_SCHEME"] ?? "light"
        let app = XCUIApplication()
        app.launchArguments = [
            "-LHMockScenario", "occasional", "-LHNudgeFireSamples", "1", "-LHDebugNotificationDelay", "16",
            "-LHColorScheme", scheme, "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 8) { allow.tap() }
        XCUIDevice.shared.press(.home)

        let pace = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '420 of 750'")).firstMatch
        let care = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Pine Cabin'")).firstMatch
        // Banners come and go: read each label the moment it shows.
        if !pace.waitForExistence(timeout: 45) { shoot("nudges-missing", scheme) }
        XCTAssertTrue(pace.exists, "The pace note arrives")
        let paceLabel = pace.label
        XCTAssertFalse(paceLabel.contains("Pine Cabin"), "Pace never carries a rental's care item")
        XCTAssertTrue(care.waitForExistence(timeout: 30), "The care note arrives")
        let careLabel = care.label
        XCTAssertFalse(careLabel.contains("750"), "Care never carries hours")
        XCTAssertNotEqual(paceLabel, careLabel)
        shoot("nudges", scheme)

        // Locked: both sit on the Lock Screen as their own notifications.
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        Thread.sleep(forTimeInterval: 2)
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        Thread.sleep(forTimeInterval: 3)
        if !pace.waitForExistence(timeout: 5) {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
            Thread.sleep(forTimeInterval: 1.5)
        }
        shoot("nudges-lock", scheme)
        XCTAssertTrue(pace.waitForExistence(timeout: 6) && care.waitForExistence(timeout: 6), "Both on the Lock Screen")
        XCTAssertNotEqual(pace.frame, care.frame, "Two notifications, not one")
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
