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

    /// The crafted house is one labelled image: the stage and the lights. The hours, the goal and
    /// the pace are Today's number block, not the house (package C; covered in TodayHouseUITests).
    private var house: XCUIElement { app.descendants(matching: .any)["craft.house"] }

    func testHeroIsOneLabelledImageWithTheStageAndTheLights() {
        launch("212")
        XCTAssertTrue(house.waitForExistence(timeout: 10))
        XCTAssertEqual(house.label, "House, Frame going up, lights on")
        // Decorative layers stay out of the tree: no image element named after an asset.
        XCTAssertEqual(app.images.matching(NSPredicate(format: "identifier BEGINSWITH 'bp_'")).count, 0)
        XCTAssertEqual(app.images.matching(NSPredicate(format: "label CONTAINS 'bp_'")).count, 0)
    }

    /// BUG (found repairing these tests): the crafted house's stills are `Image(name)`, not
    /// `Image(decorative:)`, so the asset names ("craft_frame70", "craft_frame70-unlit") sit in the
    /// accessibility tree under the house. The old house hid its art; this check passed then.
    /// Strict: when the stills are made decorative this starts passing, and the expectation must go.
    func testArtLayersAreHiddenFromVoiceOver() {
        launch("212")
        XCTAssertTrue(house.waitForExistence(timeout: 10))
        XCTAssertEqual(app.images.matching(NSPredicate(format: "label BEGINSWITH 'craft_'")).count, 0,
                       "The art layers are hidden from VoiceOver: only the house is read")
    }

    func testMPGoalHeroDark() {
        launch("120", "mp500", scheme: "dark")
        XCTAssertTrue(house.waitForExistence(timeout: 10))
        XCTAssertEqual(house.label, "House, Frame going up, lights on")
    }

    /// The confirm scene adds hours to an unlit house: the stage advances and the lights come on.
    func testConfirmCrossingToTheRoofChangesTheStageAndLightsTheWindows() {
        launch("440", extra: ["-LHHouseScene", "confirm", "-LHHouseConfirmHours", "20", "-LHHouseConfirmDelay", "6", "-LHHouseUnlit"])
        XCTAssertTrue(house.waitForExistence(timeout: 10))
        XCTAssertEqual(house.label, "House, Frame finished, lights off")
        let after = NSPredicate(format: "label == %@", "House, Roof on, siding going up, lights on")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "craft.house").matching(after).firstMatch
            .waitForExistence(timeout: 10), "after the confirm: \(house.label)")
    }

    /// The celebration itself (Continue and Share) is shown by the milestone scene; Today presents it on real data.
    func testMilestoneSceneCarriesContinueAndShare() {
        launch("501", extra: ["-LHHouseScene", "milestone", "-LHHouseMilestone", "500", "-LHHouseSettled"])
        let cont = app.buttons["milestone-continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 10), "the 500h celebration shows Continue")
        XCTAssertTrue(cont.isHittable)
        XCTAssertTrue(app.buttons["milestone-share"].waitForExistence(timeout: 3), "celebrations carry Share")
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
