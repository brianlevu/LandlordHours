import XCTest

/// WP-H house renderer through the DEBUG `-LHHousePreview <hours> <goal> <scheme>` hook:
/// the hero's VoiceOver label, the milestone's Continue, and the backfill's Skip.
final class HousePreviewUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    private func launch(_ hours: String, _ goal: String = "reps", scheme: String = "light", extra: [String] = []) {
        app.terminate()
        app.launchArguments = ["-LHHousePreview", hours, goal, scheme, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
    }

    func testHeroIsOneLabelledImageWithHoursGoalAndNextMilestone() {
        launch("212")
        let house = app.descendants(matching: .any)["house-hero"]
        XCTAssertTrue(house.waitForExistence(timeout: 10))
        XCTAssertTrue(house.label.contains("212 of 750 hours"), house.label)
        XCTAssertTrue(house.label.contains("REPS goal"), house.label)
        XCTAssertTrue(house.label.contains("roof at 500 hours"), house.label)
        // Decorative layers stay out of the tree: no image element named after an asset.
        XCTAssertEqual(app.images.matching(NSPredicate(format: "identifier BEGINSWITH 'bp_'")).count, 0)
        XCTAssertEqual(app.images.matching(NSPredicate(format: "label CONTAINS 'bp_'")).count, 0)
    }

    func testMPGoalHeroDark() {
        launch("120", "mp500", scheme: "dark")
        let house = app.descendants(matching: .any)["house-hero"]
        XCTAssertTrue(house.waitForExistence(timeout: 10))
        XCTAssertTrue(house.label.contains("120 of 500 hours"), house.label)
    }

    func testConfirmCrossingFiveHundredOpensTheCelebrationWithContinue() {
        launch("499", extra: ["-LHHouseScene", "confirm", "-LHHouseConfirmHours", "2", "-LHHouseConfirmDelay", "0.5"])
        let cont = app.buttons["milestone-continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 10), "the 500h celebration should open after the confirm")
        XCTAssertTrue(cont.isHittable)
        XCTAssertTrue(app.buttons["milestone-share"].waitForExistence(timeout: 3), "celebrations carry Share")
        cont.tap()
        XCTAssertTrue(app.descendants(matching: .any)["house-hero"].waitForExistence(timeout: 5))
        XCTAssertFalse(cont.exists)
    }

    func testBackfillIsSkippable() {
        launch("212", extra: ["-LHHouseScene", "backfill"])
        let skip = app.buttons["backfill-skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '212 hours found'")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["backfill-review"].isHittable)
    }
}
