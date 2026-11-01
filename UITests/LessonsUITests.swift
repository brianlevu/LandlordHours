import XCTest

/// 2.3 package C: the Today milestone card, the 3-card lesson sheet and the lesson list. Behaviour
/// checks by identifier (no wording pinned), plus frame capture for the visual gate
/// (`TEST_RUNNER_LH_CAPTURE_DIR=<dir>`): every state, light and dark, at default, XXL and AX3.
/// Frame ids follow the approved set: l1 (Today card), l2-l4 (lesson 1), l6-l8 (lesson 2),
/// l9-l11 (lesson 3), l5 (the list), t1 (Today with the card).
final class LessonsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        UITestIsolation.resetStoreKit()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: Behaviour

    func testMilestoneCardOpensThreeCardLessonThatEndsOnTheCPALineAndClearsTheCard() {
        launchToday(scenario: "frequent")
        let card = element("today.learn")
        XCTAssertTrue(scrollTo(card), "The Learn card shows at a milestone")
        XCTAssertTrue(element("today.learn.seeAll").exists)
        element("today.learn.read").tap()

        XCTAssertTrue(element("lesson.sheet").waitForExistence(timeout: 10))
        XCTAssertTrue(element("lesson.card.1").waitForExistence(timeout: 5))
        XCTAssertFalse(element("lesson.notAdvice").isHittable, "The not-advice line belongs to the last card")
        element("lesson.next").tap()
        XCTAssertTrue(element("lesson.card.2").waitForExistence(timeout: 5))
        element("lesson.next").tap()
        XCTAssertTrue(element("lesson.card.3").waitForExistence(timeout: 5))
        XCTAssertTrue(element("lesson.notAdvice").waitForExistence(timeout: 5), "Every lesson ends on General learning, not tax advice")
        element("lesson.next").tap()   // Done
        XCTAssertTrue(element("lesson.sheet").waitForNonExistence(timeout: 5))
        XCTAssertTrue(element("today.learn").waitForNonExistence(timeout: 5), "Reading clears the milestone card")
    }

    func testTheCardCanBeDismissedAndStaysGone() {
        launchToday(scenario: "frequent")
        XCTAssertTrue(scrollTo(element("today.learn")))
        element("today.learn.dismiss").tap()
        XCTAssertTrue(element("today.learn").waitForNonExistence(timeout: 5), "Not now clears the card")
        // Away and back: a dismissed milestone doesn't come back (the store's per-profile state is in LessonsTests).
        app.tabBars.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.tabBars.buttons.element(boundBy: 0).waitForExistence(timeout: 5))
        app.tabBars.buttons.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(element("today.learn").exists, "A dismissed milestone doesn't come back")
    }

    func testNoCardBelowTheFirstMilestone() {
        launchToday(scenario: "frequent", hours: "40")
        XCTAssertTrue(app.buttons["tab.today"].exists || app.tabBars.firstMatch.exists || app.staticTexts.firstMatch.waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(element("today.learn").exists, "Only at milestones")
    }

    func testSeeAllOpensTheListAndALessonOpensFromIt() {
        launchToday(scenario: "frequent")
        XCTAssertTrue(scrollTo(element("today.learn")))
        element("today.learn.seeAll").tap()
        XCTAssertTrue(element("learn.screen").waitForExistence(timeout: 10))
        XCTAssertTrue(element("learn.progress").exists)
        XCTAssertTrue(element("learn.notAdvice").exists || scrollTo(element("learn.notAdvice")))
        let row = element("lesson.row.spouse")
        XCTAssertTrue(scrollTo(row, maxSwipes: 2) || row.exists)
        row.tap()
        XCTAssertTrue(element("lesson.sheet").waitForExistence(timeout: 10))
        XCTAssertTrue(element("lesson.card.1").exists)
        element("lesson.close").tap()
        XCTAssertTrue(element("lesson.sheet").waitForNonExistence(timeout: 5))
    }

    func testReadLessonShowsInTheListProgress() {
        launch(["-LHMockScenario", "frequent", "-LHInitialTab", "4", "-LHOpenLearningCenterFromSettings", "-LHLearnReset",
                "-LHOpenLesson", "counts-3"])
        XCTAssertTrue(element("lesson.sheet").waitForExistence(timeout: 20))
        XCTAssertTrue(element("lesson.card.3").waitForExistence(timeout: 5), "Opens on the card asked for")
        element("lesson.close").tap()
        XCTAssertTrue(element("lesson.sheet").waitForNonExistence(timeout: 5))
        XCTAssertTrue(element("learn.progress").label.hasPrefix("1 of 3"), "Reaching the last card counts as read: \(element("learn.progress").label)")
    }

    func testFreeUserGetsCardOneThenThePaywall() {
        launchToday(scenario: "frequent", extra: ["-LHLearnFree"])
        XCTAssertTrue(scrollTo(element("today.learn")), "The card shows on the free plan too")
        element("today.learn.read").tap()
        XCTAssertTrue(element("lesson.sheet").waitForExistence(timeout: 10))
        XCTAssertTrue(element("lesson.card.1").exists)
        XCTAssertFalse(element("lesson.card.2").isHittable, "A free person sees card 1 only")
        element("lesson.next").tap()
        XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 10), "Next opens the paywall")
        XCTAssertFalse(element("lesson.sheet").exists)
    }

    // MARK: Capture

    func testCaptureLightDefault() { captureAll(scheme: "light", size: nil) }
    func testCaptureDarkDefault() { captureAll(scheme: "dark", size: nil) }
    func testCaptureLightXXL() { captureAll(scheme: "light", size: "xxl") }
    func testCaptureDarkXXL() { captureAll(scheme: "dark", size: "xxl") }
    func testCaptureLightAX3() { captureAll(scheme: "light", size: "ax3") }
    func testCaptureDarkAX3() { captureAll(scheme: "dark", size: "ax3") }

    private func wants(_ group: String) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment["LH_CAPTURE_GROUPS"], !raw.isEmpty else { return true }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(group)
    }

    private func captureAll(scheme: String, size: String?) {
        let suffix = scheme + (size.map { "-\($0)" } ?? "")

        if wants("today") {
            launchToday(scenario: "frequent", scheme: scheme, size: size)
            XCTAssertTrue(scrollTo(element("today.learn")))
            settleAndCapture("l1-today-learn-\(suffix)")
        }

        if wants("lessons") {
            let frames: [(String, String, Int)] = [
                ("l2-lesson-1-1", "counts", 1), ("l3-lesson-1-2", "counts", 2), ("l4-lesson-1-3", "counts", 3),
                ("l6-lesson-2-1", "spouse", 1), ("l7-lesson-2-2", "spouse", 2), ("l8-lesson-2-3", "spouse", 3),
                ("l9-lesson-3-1", "log", 1), ("l10-lesson-3-2", "log", 2), ("l11-lesson-3-3", "log", 3),
            ]
            for (name, lesson, card) in frames {
                launch(["-LHMockScenario", "frequent", "-LHInitialTab", "4", "-LHOpenLearningCenterFromSettings", "-LHLearnReset",
                        "-LHOpenLesson", "\(lesson)-\(card)"], scheme: scheme, size: size)
                XCTAssertTrue(element("lesson.card.\(card)").waitForExistence(timeout: 20), name)
                settleAndCapture("\(name)-\(suffix)", wait: 1.6)
            }
        }

        if wants("list") {
            // One lesson read, so the list shows the done tile, "Up next" and a partly filled bar.
            launch(["-LHMockScenario", "frequent", "-LHInitialTab", "4", "-LHOpenLearningCenterFromSettings", "-LHLearnReset",
                    "-LHOpenLesson", "counts-3"], scheme: scheme, size: size)
            XCTAssertTrue(element("lesson.card.3").waitForExistence(timeout: 20))
            element("lesson.close").tap()
            XCTAssertTrue(element("lesson.sheet").waitForNonExistence(timeout: 5))
            settleAndCapture("l5-lesson-list-\(suffix)")
            app.swipeUp()
            app.swipeUp()
            settleAndCapture("l5-lesson-list-end-\(suffix)")
        }
    }

    // MARK: Helpers

    private func launchToday(scenario: String, hours: String = "420", scheme: String = "light", size: String? = nil, extra: [String] = []) {
        launch(["-LHMockScenario", scenario, "-LHInitialTab", "0", "-LHLearnHours", hours, "-LHLearnReset"] + extra, scheme: scheme, size: size)
    }

    private func launch(_ extra: [String], scheme: String = "light", size: String? = nil) {
        app.terminate()
        var args = [UITestIsolation.resetProfilesArgument, "-LHColorScheme", scheme,
                    "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        switch size {
        case "xxl": args += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"]
        case "ax3": args += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        default: break
        }
        app.launchArguments = args + extra
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @discardableResult
    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) -> Bool {
        var swipes = 0
        while (!element.exists || !element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.exists && element.isHittable
    }

    private func settleAndCapture(_ name: String, wait: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: wait)
        let screenshot = XCUIScreen.main.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        if let dir = ProcessInfo.processInfo.environment["LH_CAPTURE_DIR"], !dir.isEmpty {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
