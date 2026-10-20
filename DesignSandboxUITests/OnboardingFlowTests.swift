import XCTest

/// Real taps through the 2.0 onboarding for the recordings. Prints "DEMO_START <epoch>" once
/// Welcome is on screen so the host script can trim the video to start there.
final class OnboardingFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ step: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let appearance = ProcessInfo.processInfo.environment["SANDBOX_APPEARANCE"] ?? "light"
        app.launchArguments = ["-LHOnboardingStep", step, "-appearance", appearance, "-recording", "YES"] + extra
        app.launch()
        return app
    }

    private func mark() { print("DEMO_START \(Date().timeIntervalSince1970)") }

    private func tap(_ e: XCUIElement, wait: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(e.waitForExistence(timeout: wait), "missing \(e)", file: file, line: line)
        e.tap()
    }

    func testHappyPath() {
        let app = launch("flow")
        let start = app.buttons["onb-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        sleep(10)                                              // pre-roll: let the screen recorder settle
        mark()
        sleep(3)
        start.tap()                                            // Welcome → Goal
        sleep(1)
        tap(app.buttons["goal-750"])
        usleep(900_000)
        tap(app.buttons["onb-primary"])                        // Build toward 750h
        sleep(2)                                               // rows + hatched storeys
        tap(app.buttons["onb-primary"])                        // Look at my calendar → prompt (mock)
        sleep(2)
        tap(app.buttons["prompt-allow"])                       // Allow Full Access
        usleep(1_200_000)
        tap(app.buttons["who-both"])
        sleep(2)
        tap(app.buttons["onb-primary"])                        // Continue
        usleep(1_200_000)
        let field = app.textFields["property-name"]
        tap(field)
        usleep(700_000)
        field.typeText("Oak Street duplex")
        usleep(600_000)
        tap(app.buttons["onb-primary"])                        // Save it (one tap; moves on by itself)
        sleep(3)
        tap(app.buttons["onb-primary"])                        // Yes, after visits → prompt (mock)
        sleep(2)
        tap(app.buttons["prompt-allow"])
        // Staked: wait for the scan to finish so the headline is the found hours.
        let today = app.buttons["onb-today"]
        XCTAssertTrue(today.waitForExistence(timeout: 8))
        sleep(4)
        today.tap()                                            // Review 14 suggestions → Inbox
        sleep(2)
        tap(app.buttons["confirm-0"])                          // Confirm the plumber visit
        sleep(3)
    }

    func testSkipPath() {
        let app = launch("flow")
        let start = app.buttons["onb-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        sleep(10)                                              // pre-roll: let the screen recorder settle
        mark()
        sleep(2)
        start.tap()
        sleep(1)
        tap(app.buttons["goal-750"])
        usleep(800_000)
        tap(app.buttons["onb-primary"])
        sleep(2)
        tap(app.buttons["onb-link"])                           // Not now (calendar)
        usleep(1_200_000)
        tap(app.buttons["onb-primary"])                        // Continue (just me)
        usleep(1_200_000)
        tap(app.buttons["onb-link"])                           // I'll add it later → Today, empty lot
        sleep(4)
    }

    /// Step 4 stake moment, for the Reduce Motion clip.
    func testStakeMoment() {
        let app = launch("4", ["-LHOnbName", "Oak Street duplex"])
        let stake = app.buttons["onb-primary"]
        XCTAssertTrue(stake.waitForExistence(timeout: 15))
        mark()
        sleep(2)
        stake.tap()
        sleep(4)
    }
}
