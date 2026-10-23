import XCTest
@testable import LandlordHours

/// 2.1 Properties rows, the rental page card, Check my goal and the Inbox cleaner card: the
/// rules the views read. Every store here is an isolated defaults suite.
@MainActor
final class RentalPlanSurfacesTests: XCTestCase {
    private let delaney = RentalProperty(name: "Delaney Ct", address: "1", propertyType: .ltr)
    private let santaRay = RentalProperty(name: "Santa Ray Ave", address: "2", propertyType: .str)
    private let yeandle = RentalProperty(name: "Yeandle Ave", address: "3", propertyType: .ltr)
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: RentalPlanStore!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "RentalPlanSurfacesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = RentalPlanStore(defaults: defaults, userId: { "tester" })
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        try await super.tearDown()
    }

    private var props: [RentalProperty] { [delaney, santaRay, yeandle] }
    private func ctx(_ goal: GoalChoice, grouping: Bool = false) -> RentalPlanContext {
        store.context(properties: props, goal: goal, grouping: grouping)
    }

    // MARK: Rows

    func testRowLinesUseTheRentalsOwnTargetNotTheGlobalGoal() {
        XCTAssertEqual(PropertyMeta.rowLine(hours: 12.9, track: .ownTarget(hours: 100), type: .str), "12h of 100h · A few nights")
        // A 500 target under a 100 goal says 500 (the "0h of 500h under a 100 goal" class, fixed).
        XCTAssertEqual(PropertyMeta.rowLine(hours: 230, track: .ownTarget(hours: 500), type: .str), "230h of 500h · A few nights")
        XCTAssertEqual(PropertyMeta.rowLine(hours: 120, track: .ownTarget(hours: 100), type: .str), "120h of 100h · A few nights")
        XCTAssertEqual(PropertyMeta.rowLine(hours: 84, track: .recordOnly(.longStays), type: .ltr), "84h this year · Long stays: hours kept, no target")
        XCTAssertEqual(PropertyMeta.rowLine(hours: 40, track: .recordOnly(.yourChoice), type: .ltr), "40h this year · Long stays: hours kept, no target")
        XCTAssertEqual(PropertyMeta.rowLine(hours: 0, track: .recordOnly(.someoneElse), type: .ltr), "0h this year · Someone else does most: hours kept, no target")
        XCTAssertEqual(PropertyMeta.rowLine(hours: 12, track: .sharedTotal(hours: 750), type: .ltr), "12h this year · Long stays")
        XCTAssertEqual(PropertyMeta.rowLine(hours: 12, track: .recordOnly(.goalIsRecord), type: .str), "12h this year · A few nights")
        XCTAssertEqual(PropertyMeta.hoursLine(-3, track: .ownTarget(hours: 100)), "0h of 100h")
        XCTAssertEqual(PropertyMeta.hoursLine(.nan, track: .sharedTotal(hours: 750)), "0h this year")
    }

    func testBriansRowsFollowThePlanRules() {
        store.setWhoDoesMost(.someoneElse, for: delaney.id)
        store.setWhoDoesMost(.me, for: santaRay.id)
        let plans = RentalPlanning.plans(ctx(.mp100))
        XCTAssertEqual(plans[santaRay.id]?.track, .ownTarget(hours: 100))
        XCTAssertEqual(plans[delaney.id]?.track, .recordOnly(.someoneElse))
        XCTAssertEqual(plans[yeandle.id]?.track, .recordOnly(.longStays))
        // Under mp500 the same rental reads 500, never the 100 of another goal.
        XCTAssertEqual(RentalPlanning.plans(ctx(.mp500))[santaRay.id]?.track, .ownTarget(hours: 500))
    }

    func testHeaderLine() {
        XCTAssertEqual(PropertyMeta.headerLine(count: 3, totalHours: 96.7, mode: .perRental), "3 rentals · 96h this year")
        XCTAssertEqual(PropertyMeta.headerLine(count: 6, totalHours: 212, mode: .shared(hours: 750)), "6 rentals · 212h toward 750")
        XCTAssertEqual(PropertyMeta.headerLine(count: 1, totalHours: 5, mode: .record), "1 rental · 5h this year")
    }

    func testSectionsOnlyWhenBothKindsExist() {
        let mixed = PropertyMeta.sections(props, plans: RentalPlanning.plans(ctx(.mp100)))
        XCTAssertEqual(mixed.map(\.kind), [.tracking, .recordOnly])
        XCTAssertEqual(mixed[0].properties.map(\.name), ["Santa Ray Ave"])
        XCTAssertEqual(mixed[1].properties.map(\.name), ["Delaney Ct", "Yeandle Ave"], "list order inside a group")
        XCTAssertEqual(mixed.map(\.title), ["Tracking a target", "Record only"])
        let shared = PropertyMeta.sections(props, plans: RentalPlanning.plans(ctx(.reps750)))
        XCTAssertEqual(shared.map(\.kind), [.all])
        XCTAssertNil(shared[0].title)
        let allLong = [delaney, yeandle]
        let longCtx = store.context(properties: allLong, goal: .mp500, grouping: false)
        XCTAssertEqual(PropertyMeta.sections(allLong, plans: RentalPlanning.plans(longCtx)).map(\.kind), [.all])
        XCTAssertEqual(PropertyMeta.sections([], plans: [:]), [])
    }

    func testRowStageIsPinnedAt500AndRecordIsAPlainLot() {
        XCTAssertEqual(RentalStage.hours(track: .ownTarget(hours: 100), hours: 640), 500)
        XCTAssertEqual(RentalStage.hours(track: .recordOnly(.longStays), hours: 84), 0)
    }

    // MARK: Rental page card

    func testCardChoiceClearsTheOverrideWhenItMatchesTheDefault() {
        let c = ctx(.mp100)
        RentalPlanCard.choose(track: false, for: santaRay, c, store: store)
        XCTAssertEqual(store.overrides[santaRay.id], .record)
        XCTAssertEqual(RentalPlanning.plan(for: santaRay, ctx(.mp100)).track, .recordOnly(.yourChoice))
        RentalPlanCard.choose(track: true, for: santaRay, ctx(.mp100), store: store)
        XCTAssertNil(store.overrides[santaRay.id], "back to the default: nothing stored, it re-derives")
        RentalPlanCard.choose(track: true, for: yeandle, ctx(.mp100), store: store)
        XCTAssertEqual(store.overrides[yeandle.id], .track)
        XCTAssertEqual(RentalPlanning.plan(for: yeandle, ctx(.mp100)).track, .ownTarget(hours: 100))
    }

    func testCardWordsNameTheTarget() {
        store.setWhoDoesMost(.me, for: santaRay.id)
        XCTAssertEqual(RentalPlanCard.explanation(for: santaRay, ctx(.mp100)),
                       "It has its own 100-hour target. You do most of the work, so 100 hours and more than anyone else still fits.")
        XCTAssertEqual(RentalPlanCard.explanation(for: yeandle, ctx(.mp100)),
                       "Long stays have no target under your goal. Pick Track a goal and it will have its own 100-hour target.")
        XCTAssertFalse(RentalPlanCard.isEditable(ctx(.reps750)))
        XCTAssertFalse(RentalPlanCard.isEditable(ctx(.mp100, grouping: true)))
        XCTAssertFalse(RentalPlanCard.isEditable(ctx(.record)))
        XCTAssertTrue(RentalPlanCard.isEditable(ctx(.mp500)))
        XCTAssertEqual(RentalPlanCard.readOnlyLine(ctx(.reps750)), "Counts toward your 750. Every rental’s hours go into one total.")
    }

    // MARK: Check my goal

    func testKeepPinsTheCurrentTracksForChangedRows() {
        store.setWhoDoesMost(.me, for: santaRay.id)
        let c = ctx(.mp100)
        let draft: [UUID: WhoDoesMost] = [santaRay.id: .someoneElse]
        let rows = GoalCheck.rows(c, draft: draft)
        XCTAssertEqual(rows.first { $0.propertyId == santaRay.id }?.proposed, .ownTarget(hours: 500))
        XCTAssertEqual(rows.filter(\.changes).count, 1)
        XCTAssertEqual(GoalCheckWords.switchTitle(rows), "Switch Santa Ray Ave to 500")
        GoalCheckActions.keep(c, draft: draft, store: store)
        XCTAssertEqual(store.whoDoesMost[santaRay.id], .someoneElse, "the answer is saved")
        XCTAssertEqual(store.overrides[santaRay.id], .trackPinned(hours: 100))
        XCTAssertNil(store.overrides[delaney.id], "unchanged rows are left alone")
        XCTAssertEqual(RentalPlanning.plan(for: santaRay, ctx(.mp100)).track, .ownTarget(hours: 100), "Keep keeps 100")
    }

    func testSwitchSavesTheAnswerAndTheTargetReDerives() {
        store.setWhoDoesMost(.me, for: santaRay.id)
        _ = store.reconcile(ctx(.mp100), announce: false)
        GoalCheckActions.switchToProposed(draft: [santaRay.id: .notSure], store: store)
        XCTAssertNil(store.overrides[santaRay.id])
        XCTAssertEqual(RentalPlanning.plan(for: santaRay, ctx(.mp100)).track, .ownTarget(hours: 500))
        XCTAssertEqual(RentalPlanAnnouncer.announce(ctx(.mp100), store: store, toasts: nil), "Santa Ray Ave now has its own 500-hour target.")
    }

    func testDiffReasonsAndNoChangeRows() {
        let rows = GoalCheck.rows(ctx(.mp100), draft: [santaRay.id: .someoneElse])
        let santa = rows.first { $0.propertyId == santaRay.id }!
        XCTAssertEqual(GoalCheckWords.reason(santa), "Someone else does more hours here, so the app can’t track 100 here. 500 doesn’t compare you with anyone")
        XCTAssertEqual(GoalCheckWords.trackValue(santa.current), "100 hours")
        XCTAssertEqual(GoalCheckWords.trackValue(santa.proposed), "500 hours")
        let yRow = rows.first { $0.propertyId == yeandle.id }!
        XCTAssertFalse(yRow.changes)
        XCTAssertEqual(GoalCheckWords.reason(yRow), "Long stays have no target under your goal")
        XCTAssertFalse(GoalCheck.asksPerRental(ctx(.reps750)))
        XCTAssertTrue(GoalCheck.asksPerRental(ctx(.mp100)))
    }

    // MARK: Toast after a goal change

    func testToastSentenceAfterAGoalChange() {
        _ = store.reconcile(ctx(.mp100), announce: false)
        let center = LHToastCenter(sleep: { _ in try? await Task.sleep(for: .seconds(3600)) }, announce: { _ in })
        let sentence = RentalPlanAnnouncer.announce(ctx(.reps750), store: store, toasts: center)
        XCTAssertEqual(sentence, "Every rental now counts toward one 750-hour total.")
        XCTAssertEqual(center.current?.message, sentence)
        XCTAssertEqual(center.current?.identifier, "plan.toast")
        XCTAssertNil(RentalPlanAnnouncer.announce(ctx(.reps750), store: store, toasts: nil), "nothing moved, no toast")
    }

    func testOverrideIsNamedAsKeptAfterAGoalChange() {
        store.setOverride(.record, for: santaRay.id)
        _ = store.reconcile(ctx(.mp100), announce: false)
        let sentence = RentalPlanAnnouncer.announce(ctx(.mp100, grouping: true), store: store, toasts: nil)
        XCTAssertEqual(sentence, "Every rental now counts toward one 100-hour total.")
    }

    // MARK: Inbox cleaner card

    func testCleanerCardHidesWithTheStubAndShowsWithAFact() {
        XCTAssertTrue(CleanerFactInbox.pending(source: StubCleanerFactSource(), properties: props, answered: []).isEmpty)
        struct OneFact: CleanerFactSource {
            let p: RentalProperty
            func facts(for properties: [RentalProperty]) -> [CleanerFact] {
                [CleanerFact(propertyId: p.id, propertyName: p.name, eventTitle: "Turnover clean")]
            }
        }
        let source = OneFact(p: santaRay)
        let pending = CleanerFactInbox.pending(source: source, properties: props, answered: [])
        XCTAssertEqual(pending.map(\.propertyName), ["Santa Ray Ave"])
        XCTAssertTrue(CleanerFactInbox.pending(source: source, properties: props, answered: [CleanerFactInbox.key(pending[0])]).isEmpty,
                      "an answered card goes")
        XCTAssertTrue(CleanerFactInbox.pending(source: source, properties: [delaney], answered: []).isEmpty, "a deleted rental's fact goes")
        XCTAssertEqual(CleanerFactInbox.who(for: .theyDoMore), .someoneElse)
        XCTAssertEqual(CleanerFactInbox.who(for: .iDoMore), .me)
        XCTAssertEqual(CleanerFactInbox.who(for: .notSure), .notSure)
    }

    func testAnsweringTheCleanerCardMovesTheRentalTo500() {
        store.setWhoDoesMost(.me, for: santaRay.id)
        _ = store.reconcile(ctx(.mp100), announce: false)
        store.setWhoDoesMost(CleanerFactInbox.who(for: .theyDoMore), for: santaRay.id)
        XCTAssertEqual(store.reconcile(ctx(.mp100)), "Santa Ray Ave now has its own 500-hour target.")
    }
}
