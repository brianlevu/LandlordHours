import XCTest
@testable import LandlordHours

/// Reveal on return (standard §B.3 `houseReveal`, Brian 2026-10-26): Today remembers the last
/// state the user SAW per profile, year and page, and plays one transition from it to the live
/// state when Today becomes visible.
final class HouseRevealTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var coordinator: HouseRevealCoordinator!
    private let year = 2026
    private let goal = 100.0

    override func setUp() {
        super.setUp()
        suite = "HouseRevealTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        coordinator = HouseRevealCoordinator(ledger: HouseSeenLedger(defaults: defaults, userId: "reveal-test"))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        coordinator = nil
        super.tearDown()
    }

    private func state(_ hours: Double, lit: Bool = false) -> HouseSeenState {
        HouseSeenState(stage: CraftStage.stage(hours: hours, goal: goal), lit: lit, hours: hours)
    }

    @discardableResult
    private func visit(_ current: HouseSeenState, year: Int? = nil,
                       dropAllowed: Bool = true, reduceMotion: Bool = false) -> HouseRevealPlan? {
        visit("rental-a", current, year: year, dropAllowed: dropAllowed, reduceMotion: reduceMotion)
    }

    @discardableResult
    private func visit(_ focus: String, _ current: HouseSeenState, year: Int? = nil,
                       dropAllowed: Bool = true, reduceMotion: Bool = false) -> HouseRevealPlan? {
        coordinator.reveal(focus: focus, current: current, year: year ?? self.year,
                           dropAllowed: dropAllowed, reduceMotion: reduceMotion)
    }

    // MARK: First sight

    func testFirstSightShowsThePageAsItIsAndRemembersIt() {
        XCTAssertNil(visit(state(45)), "Never seen: nothing to play")
        XCTAssertEqual(coordinator.ledger.seen(focus: "rental-a", year: year), state(45))
        XCTAssertNil(visit(state(45)), "Seen and unchanged: nothing replays")
    }

    // MARK: Up across framing

    func testUpIntoFramingPlaysTheDropThenTheWindowsAndHoldsTheNumber() throws {
        visit(state(45))                                   // frame70, seen
        let plan = try XCTUnwrap(visit(state(48, lit: true)))
        XCTAssertEqual(plan.from.stage, .frame70)
        XCTAssertEqual(plan.to.stage, .framing)
        XCTAssertEqual(plan.direction, .up)
        XCTAssertEqual(plan.stageMotion, .timberDrop)
        XCTAssertTrue(plan.windowsChange, "First log of the day: windows on after the drop")
        XCTAssertTrue(plan.rollsNumber)
        XCTAssertTrue(plan.holdsNumberUntilSettled, "The number rolls as the last timber lands")
        XCTAssertFalse(plan.isQuiet)
        XCTAssertEqual(plan.duration, CraftMotion.dropFadeIn + CraftMotion.dropClip + CraftMotion.dropCrossfade + CraftMotion.windowsFade,
                       accuracy: 0.001)
    }

    func testUpIntoFramingFadesWhenTheDropAlreadyPlayedForThisStage() throws {
        visit(state(45))
        let plan = try XCTUnwrap(visit(state(48), dropAllowed: false))
        XCTAssertEqual(plan.stageMotion, .stageFade, "The drop plays at most once per stage per rental")
    }

    func testUpAcrossOtherStagesIsOneStageFade() throws {
        visit(state(10))                                   // started
        let plan = try XCTUnwrap(visit(state(70)))         // half: skips framing
        XCTAssertEqual(plan.stageMotion, .stageFade, "Never plays the stages in between")
        XCTAssertEqual(plan.direction, .up)
    }

    // MARK: Up within a stage

    func testUpWithinAStageRollsTheNumberOnly() throws {
        visit(state(20))
        let plan = try XCTUnwrap(visit(state(22)))
        XCTAssertEqual(plan.stageMotion, .none)
        XCTAssertFalse(plan.windowsChange)
        XCTAssertTrue(plan.rollsNumber)
        XCTAssertFalse(plan.holdsNumberUntilSettled)
        XCTAssertEqual(plan.from.hours, 20)
        XCTAssertEqual(plan.to.hours, 22)
    }

    func testWindowsOnlyChangeFadesTheWindows() throws {
        visit(state(20))
        let plan = try XCTUnwrap(visit(state(20, lit: true)))
        XCTAssertEqual(plan.stageMotion, .none)
        XCTAssertTrue(plan.windowsChange)
        XCTAssertFalse(plan.rollsNumber)
    }

    // MARK: Several changes collapse

    func testSeveralChangesWhileAwayCollapseIntoOneTransition() throws {
        visit(state(40))
        // Three saves while Today is hidden: nothing is asked of the coordinator until Today shows.
        let live = [state(42), state(44), state(48, lit: true)]
        let plan = try XCTUnwrap(visit(live.last!))
        XCTAssertEqual(plan.from, state(40), "One transition from the last-seen state")
        XCTAssertEqual(plan.to, state(48, lit: true))
        XCTAssertEqual(plan.stageMotion, .timberDrop)
        XCTAssertNil(visit(live.last!), "Shown once: going back to Today replays nothing")
    }

    // MARK: Down

    func testDownIsAQuietFadeAndTheNumberRollsDown() throws {
        visit(state(12))                                   // started
        visit(state(48, lit: true))                         // framing (seen)
        let plan = try XCTUnwrap(visit(state(1)))          // an edit 48h → 1h
        XCTAssertEqual(plan.direction, .down)
        XCTAssertEqual(plan.stageMotion, .stageFade, "A fade to the lower stage")
        XCTAssertNotEqual(plan.stageMotion, .timberDrop, "No reverse build, no timber removal")
        XCTAssertTrue(plan.isQuiet)
        XCTAssertTrue(plan.rollsNumber, "The number rolls down")
        XCTAssertTrue(plan.windowsChange)
        XCTAssertFalse(plan.holdsNumberUntilSettled)
    }

    func testDownIntoFramingNeverPlaysTheDrop() throws {
        visit(state(70))                                   // half
        let plan = try XCTUnwrap(visit(state(50)))         // framing, from above
        XCTAssertEqual(plan.direction, .down)
        XCTAssertEqual(plan.stageMotion, .stageFade)
    }

    // MARK: Rental switch

    func testRentalSwitchShowsTheSeenStateWithNoReplay() {
        visit("rental-a", state(45))
        visit("rental-b", state(70))
        XCTAssertNil(visit("rental-b", state(70)), "Switching to B with nothing new: no build replay")
        XCTAssertNil(visit("rental-a", state(45)), "And back to A: no replay")
        XCTAssertEqual(coordinator.startState(focus: "rental-b", current: state(70), year: year), state(70))
    }

    func testRentalSwitchPlaysTheCatchUpOnceWhenThatRentalChanged() throws {
        visit("rental-a", state(45))
        visit("rental-b", state(45))
        // B changed while the user looked at A.
        XCTAssertEqual(coordinator.startState(focus: "rental-b", current: state(48), year: year), state(45),
                       "B slides in as it was last seen")
        let plan = try XCTUnwrap(visit("rental-b", state(48)))
        XCTAssertEqual(plan.stageMotion, .timberDrop)
        XCTAssertNil(visit("rental-b", state(48)), "Its catch-up plays once")
        XCTAssertNil(visit("rental-a", state(45)), "A is untouched")
    }

    func testAllRentalsIsItsOwnPage() throws {
        let all = CraftDropLedger.allRentalsKey
        visit(all, state(40))
        visit("rental-a", state(20))
        let plan = try XCTUnwrap(visit(all, state(44)))
        XCTAssertEqual(plan.from.hours, 40)
    }

    // MARK: Reduce Motion

    func testReduceMotionIsAPlainCrossfadeWithNoRoll() throws {
        visit(state(45))
        let plan = try XCTUnwrap(visit(state(48, lit: true), reduceMotion: true))
        XCTAssertEqual(plan.stageMotion, .stageFade, "No clip under Reduce Motion: the still crossfades")
        XCTAssertFalse(plan.rollsNumber, "The digits jump")
        XCTAssertFalse(plan.holdsNumberUntilSettled)
    }

    // MARK: New year

    func testANewYearResetsWhatWasSeen() throws {
        visit(state(48), year: 2026)
        XCTAssertNil(visit(state(2), year: 2027), "January: the first look shows the new year as it is")
        XCTAssertNil(coordinator.ledger.seen(focus: "rental-a", year: 2026), "Last year's pages are dropped")
        let plan = try XCTUnwrap(visit(state(5), year: 2027))
        XCTAssertEqual(plan.from.hours, 2)
    }

    // MARK: Ledger

    func testLedgerIsPerProfile() {
        let other = HouseSeenLedger(defaults: defaults, userId: "someone-else")
        visit(state(45))
        XCTAssertNil(other.seen(focus: "rental-a", year: year))
        XCTAssertNotNil(coordinator.ledger.seen(focus: "rental-a", year: year))
        coordinator.ledger.reset()
        XCTAssertNil(coordinator.ledger.seen(focus: "rental-a", year: year))
    }
}
