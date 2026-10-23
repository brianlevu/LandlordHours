import XCTest
@testable import LandlordHours

// MARK: - 2.1 rental plans: defaults, overrides across goal changes, the stage, the focus,
// the toast sentence, the per-profile store and "Check my goal". Pure rules on stored answers.

final class RentalPlanTests: XCTestCase {
    // Brian's order: Delaney (long stays) added first, then Santa (short stays), then Yeandle (long).
    private let delaney = RentalProperty(name: "Delaney", address: "1", propertyType: .ltr)
    private let santa = RentalProperty(name: "Santa", address: "2", propertyType: .str)
    private let yeandle = RentalProperty(name: "Yeandle", address: "3", propertyType: .ltr)
    private let cabin = RentalProperty(name: "Cabin", address: "4", propertyType: .str)

    private var brians: [RentalProperty] { [delaney, santa, yeandle] }

    private func ctx(_ goal: GoalChoice, _ props: [RentalProperty], grouping: Bool = false,
                     overrides: [UUID: RentalOverride] = [:], who: [UUID: WhoDoesMost] = [:]) -> RentalPlanContext {
        RentalPlanContext(goal: goal, grouping: grouping, properties: props, overrides: overrides, whoDoesMost: who)
    }

    private func track(_ p: RentalProperty, _ c: RentalPlanContext) -> RentalTrack {
        RentalPlanning.plan(for: p, c).track
    }

    // MARK: Defaults: goal x kind of rental

    func testReps750PutsEveryRentalOnTheSharedTotal() {
        let c = ctx(.reps750, brians)
        XCTAssertEqual(RentalPlanning.mode(c), .shared(hours: 750))
        for p in brians { XCTAssertEqual(track(p, c), .sharedTotal(hours: 750), p.name) }
    }

    func testRecordGoalMakesEveryRentalRecordOnly() {
        let c = ctx(.record, brians)
        XCTAssertEqual(RentalPlanning.mode(c), .record)
        for p in brians {
            XCTAssertEqual(track(p, c), .recordOnly(.goalIsRecord), p.name)
            XCTAssertFalse(RentalPlanning.plan(for: p, c).isOverride)
        }
    }

    func testMp100MixedKindsGivesTheShortStayItsOwn100AndLongStaysRecordOnly() {
        let c = ctx(.mp100, brians)
        XCTAssertEqual(RentalPlanning.mode(c), .perRental)
        XCTAssertEqual(track(santa, c), .ownTarget(hours: 100))
        XCTAssertEqual(track(delaney, c), .recordOnly(.longStays))
        XCTAssertEqual(track(yeandle, c), .recordOnly(.longStays))
    }

    func testMp500AllLongStaysGivesEachRentalItsOwn500() {
        let c = ctx(.mp500, [delaney, yeandle])
        for p in [delaney, yeandle] { XCTAssertEqual(track(p, c), .ownTarget(hours: 500), p.name) }
    }

    func testGroupingSharesTheGoalsHours() {
        let c100 = ctx(.mp100, brians, grouping: true)
        let c500 = ctx(.mp500, brians, grouping: true)
        XCTAssertEqual(RentalPlanning.mode(c100), .shared(hours: 100))
        XCTAssertEqual(RentalPlanning.mode(c500), .shared(hours: 500))
        for p in brians {
            XCTAssertEqual(track(p, c100), .sharedTotal(hours: 100))
            XCTAssertEqual(track(p, c500), .sharedTotal(hours: 500))
        }
    }

    func testRecordOnlyLongStayWhereSomeoneElseDoesMostSaysSo() {
        let c = ctx(.mp100, brians, who: [delaney.id: .someoneElse])
        XCTAssertEqual(track(delaney, c), .recordOnly(.someoneElse))
    }

    // MARK: Who does most

    func testSomeoneElseOrNotSureUnderMp100Gives500() {
        XCTAssertEqual(track(santa, ctx(.mp100, brians, who: [santa.id: .someoneElse])), .ownTarget(hours: 500))
        XCTAssertEqual(track(santa, ctx(.mp100, brians, who: [santa.id: .notSure])), .ownTarget(hours: 500))
        XCTAssertEqual(RentalPlanning.ownTargetHours(goal: .mp100, whoDoesMost: .someoneElse), 500)
        XCTAssertEqual(RentalPlanning.ownTargetHours(goal: .mp100, whoDoesMost: .notSure), 500)
    }

    func testMeOrMeAndSpouseKeeps100() {
        XCTAssertEqual(track(santa, ctx(.mp100, brians, who: [santa.id: .me])), .ownTarget(hours: 100))
        XCTAssertEqual(track(santa, ctx(.mp100, brians, who: [santa.id: .meAndSpouse])), .ownTarget(hours: 100))
        XCTAssertEqual(RentalPlanning.ownTargetHours(goal: .mp100, whoDoesMost: nil), 100)
    }

    func testMp500NeverChangesWithWhoDoesMost() {
        for who in WhoDoesMost.allCases {
            XCTAssertEqual(RentalPlanning.ownTargetHours(goal: .mp500, whoDoesMost: who), 500, who.rawValue)
            XCTAssertEqual(track(delaney, ctx(.mp500, [delaney, yeandle], who: [delaney.id: who])), .ownTarget(hours: 500), who.rawValue)
        }
    }

    // MARK: Overrides survive goal changes

    func testAnOverrideIsKeptAcrossGoalChangesAndUntouchedRentalsReDerive() {
        let props = [delaney, santa, cabin]   // two short stays, one long
        let overrides: [UUID: RentalOverride] = [santa.id: .record]

        let mp100 = ctx(.mp100, props, overrides: overrides)
        XCTAssertEqual(track(santa, mp100), .recordOnly(.yourChoice))
        XCTAssertTrue(RentalPlanning.plan(for: santa, mp100).isOverride)
        XCTAssertEqual(track(cabin, mp100), .ownTarget(hours: 100))
        XCTAssertEqual(track(delaney, mp100), .recordOnly(.longStays))

        let mp500 = ctx(.mp500, props, overrides: overrides)
        XCTAssertEqual(track(santa, mp500), .recordOnly(.yourChoice), "the owner's choice is kept")
        XCTAssertEqual(track(cabin, mp500), .ownTarget(hours: 500), "untouched rentals follow the new goal")
        XCTAssertEqual(track(delaney, mp500), .recordOnly(.longStays))

        let reps = ctx(.reps750, props, overrides: overrides)
        for p in props { XCTAssertEqual(track(p, reps), .sharedTotal(hours: 750), "750 ignores overrides: \(p.name)") }
        XCTAssertFalse(RentalPlanning.plan(for: santa, reps).isOverride)

        let back = ctx(.mp100, props, overrides: overrides)
        XCTAssertEqual(track(santa, back), .recordOnly(.yourChoice), "the override was never deleted")
        XCTAssertEqual(track(cabin, back), .ownTarget(hours: 100))
    }

    @MainActor
    func testStoreKeepsTheOverrideThroughGoalChanges() {
        let (store, suite) = makeStore()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let props = [delaney, santa, cabin]
        store.setOverride(.record, for: santa.id)
        for goal in [GoalChoice.mp100, .mp500, .reps750, .mp100] {
            _ = RentalPlanning.plans(store.context(properties: props, goal: goal, grouping: false))
            XCTAssertEqual(store.overrides[santa.id], .record, "after \(goal.rawValue)")
        }
        XCTAssertEqual(track(santa, store.context(properties: props, goal: .mp100, grouping: false)), .recordOnly(.yourChoice))
    }

    func testTrackOverrideUsesTheWorkedOutTargetAndPinnedKeepsItsHours() {
        let c = ctx(.mp100, brians, overrides: [delaney.id: .track, yeandle.id: .trackPinned(hours: 100)],
                    who: [delaney.id: .someoneElse, yeandle.id: .someoneElse])
        XCTAssertEqual(track(delaney, c), .ownTarget(hours: 500))
        XCTAssertEqual(track(yeandle, c), .ownTarget(hours: 100))
    }

    // MARK: Stage

    func testOwnTargetStagePinsAt500() {
        XCTAssertEqual(RentalStage.hours(track: .ownTarget(hours: 100), hours: 620), 500)
        XCTAssertEqual(RentalStage.hours(track: .ownTarget(hours: 500), hours: 120), 120)
        XCTAssertEqual(RentalStage.keyframe(track: .ownTarget(hours: 100), hours: 900), HouseProgress.keyframe(for: 500))
    }

    func testSharedStageIsUnpinned() {
        XCTAssertEqual(RentalStage.hours(track: .sharedTotal(hours: 750), hours: 620), 620)
        XCTAssertEqual(RentalStage.hours(track: .sharedTotal(hours: 750), hours: 800), 800)
        XCTAssertEqual(RentalStage.keyframe(track: .sharedTotal(hours: 750), hours: 800), HouseProgress.keyframe(for: 800))
    }

    func testRecordOnlyStageIsAPlainLot() {
        let record = RentalTrack.recordOnly(.longStays)
        XCTAssertEqual(RentalStage.hours(track: record, hours: 300), 0)
        XCTAssertEqual(RentalStage.keyframe(track: record, hours: 300), HouseProgress.keyframe(for: 0))
        XCTAssertTrue(RentalStage.isPlainLot(record))
        XCTAssertFalse(RentalStage.isPlainLot(.ownTarget(hours: 100)))
        XCTAssertFalse(RentalStage.isPlainLot(.sharedTotal(hours: 750)))
    }

    func testStageIgnoresBadHours() {
        XCTAssertEqual(RentalStage.hours(track: .sharedTotal(hours: 750), hours: -5), 0)
        XCTAssertEqual(RentalStage.hours(track: .ownTarget(hours: 100), hours: .nan), 0)
    }

    // MARK: Default focus

    func testDefaultFocusIsTheOwnTargetRentalNotTheFirstAdded() {
        let c = ctx(.mp100, brians)
        let hours: [UUID: Double] = [delaney.id: 300, santa.id: 4, yeandle.id: 120]
        XCTAssertEqual(RentalPlanning.defaultFocus(c) { hours[$0] ?? 0 }, santa.id, "Delaney has more hours but no target")
    }

    func testDefaultFocusPicksTheOwnTargetRentalWithMostHours() {
        let allLong = ctx(.mp500, [delaney, yeandle])
        let hours: [UUID: Double] = [delaney.id: 10, santa.id: 30, yeandle.id: 40, cabin.id: 50]
        XCTAssertEqual(RentalPlanning.defaultFocus(allLong) { hours[$0] ?? 0 }, yeandle.id)
        let mixed = ctx(.mp100, [delaney, santa, cabin])
        XCTAssertEqual(RentalPlanning.defaultFocus(mixed) { $0 == delaney.id ? 400 : hours[$0] ?? 0 }, cabin.id,
                       "the long stay has the most hours but no target")
    }

    func testDefaultFocusTieKeepsListOrder() {
        let c = ctx(.mp500, [delaney, yeandle])
        XCTAssertEqual(RentalPlanning.defaultFocus(c) { _ in 12 }, delaney.id)
    }

    func testNoDefaultFocusWhenShared() {
        XCTAssertNil(RentalPlanning.defaultFocus(ctx(.reps750, brians)) { _ in 1 })
        XCTAssertNil(RentalPlanning.defaultFocus(ctx(.mp100, brians, grouping: true)) { _ in 1 })
        XCTAssertNil(RentalPlanning.defaultFocus(ctx(.record, brians)) { _ in 1 })
    }

    // MARK: Toast sentence

    func testSummarySharedTotal() {
        let before = RentalPlanning.plans(ctx(.mp100, brians))
        let after = RentalPlanning.plans(ctx(.reps750, brians))
        XCTAssertEqual(RentalPlanChange.summary(before: before, after: after, properties: brians),
                       "Every rental now counts toward one 750-hour total.")
    }

    func testSummarySingleRental() {
        let before = RentalPlanning.plans(ctx(.mp100, brians))
        let after = RentalPlanning.plans(ctx(.mp100, brians, who: [santa.id: .someoneElse]))
        XCTAssertEqual(RentalPlanChange.summary(before: before, after: after, properties: brians),
                       "Santa now has its own 500-hour target.")
    }

    func testSummaryNamesKeptRentals() {
        let props = [delaney, santa, cabin]
        let overrides: [UUID: RentalOverride] = [santa.id: .record]
        let before = RentalPlanning.plans(ctx(.mp100, props, overrides: overrides))
        let after = RentalPlanning.plans(ctx(.mp500, props, overrides: overrides))
        let sentence = RentalPlanChange.summary(before: before, after: after, properties: props)
        XCTAssertEqual(sentence, "Cabin now has its own 500-hour target. Rentals you set yourself stayed as they were.")
    }

    func testSummaryNilWhenNothingChanged() {
        let plans = RentalPlanning.plans(ctx(.mp100, brians))
        XCTAssertNil(RentalPlanChange.summary(before: plans, after: plans, properties: brians))
    }

    func testSummaryRecordGoal() {
        let before = RentalPlanning.plans(ctx(.mp500, [delaney, yeandle]))
        let after = RentalPlanning.plans(ctx(.record, [delaney, yeandle]))
        XCTAssertEqual(RentalPlanChange.summary(before: before, after: after, properties: [delaney, yeandle]),
                       "Your rentals now keep hours with no target.")
    }

    // MARK: Store

    @MainActor
    private func makeStore(userId: String? = "rental-plan-test") -> (RentalPlanStore, String) {
        let suite = "RentalPlanTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (RentalPlanStore(defaults: defaults, userId: { userId }), suite)
    }

    @MainActor
    func testStorePersistenceRoundTrip() {
        let suite = "RentalPlanTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RentalPlanStore(defaults: defaults, userId: { "p1" })
        store.setOverride(.trackPinned(hours: 100), for: santa.id)
        store.setOverride(.record, for: delaney.id)
        store.setWhoDoesMost(.someoneElse, for: yeandle.id)
        store.setFocus(rental: santa.id)

        let reloaded = RentalPlanStore(defaults: defaults, userId: { "p1" })
        XCTAssertEqual(reloaded.overrides, [santa.id: .trackPinned(hours: 100), delaney.id: .record])
        XCTAssertEqual(reloaded.whoDoesMost, [yeandle.id: .someoneElse])
        XCTAssertEqual(reloaded.chosenFocus(in: brians), .rental(santa.id))
        XCTAssertNotNil(defaults.data(forKey: UserScope.key(RentalPlanStore.overridesBaseKey, userId: "p1")), "scoped to the profile")

        let other = RentalPlanStore(defaults: defaults, userId: { "p2" })
        XCTAssertTrue(other.overrides.isEmpty, "another profile sees nothing")
        XCTAssertNil(other.focusToken)

        reloaded.setFocusAll()
        XCTAssertEqual(RentalPlanStore(defaults: defaults, userId: { "p1" }).chosenFocus(in: brians), .all)
    }

    @MainActor
    func testStoreForgetLeavesNothingBehind() {
        let (store, suite) = makeStore()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        store.setOverride(.record, for: santa.id)
        store.setWhoDoesMost(.me, for: santa.id)
        store.setFocus(rental: santa.id)
        store.setOverride(.track, for: delaney.id)
        store.forget(santa.id)
        XCTAssertNil(store.overrides[santa.id])
        XCTAssertNil(store.whoDoesMost[santa.id])
        XCTAssertNil(store.focusToken)
        XCTAssertEqual(store.overrides[delaney.id], .track, "other rentals are untouched")
        store.reload()
        XCTAssertNil(store.overrides[santa.id], "forgotten on disk too")
    }

    @MainActor
    func testChosenFocusFallsBackWhenTheRentalIsGone() {
        let (store, suite) = makeStore()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        store.setFocus(rental: cabin.id)
        XCTAssertNil(store.chosenFocus(in: brians))
        store.setFocus(rental: nil)
        XCTAssertNil(store.chosenFocus(in: brians))
    }

    @MainActor
    func testStoreResetAll() {
        let suite = "RentalPlanTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RentalPlanStore(defaults: defaults, userId: { "p1" })
        store.setOverride(.record, for: santa.id)
        store.setWhoDoesMost(.notSure, for: santa.id)
        store.setFocusAll()
        store.reconcile(ctx(.mp100, brians))
        store.resetAll()
        XCTAssertTrue(store.overrides.isEmpty)
        XCTAssertTrue(store.whoDoesMost.isEmpty)
        XCTAssertNil(store.focusToken)
        for base in RentalPlanStore.allKeys {
            XCTAssertNil(defaults.object(forKey: UserScope.key(base, userId: "p1")), base)
        }
        XCTAssertNil(store.reconcile(ctx(.reps750, brians)), "the snapshot went too: the next look is a first look")
    }

    @MainActor
    func testReconcileFirstLookIsSilentThenAGoalChangeAnnounces() {
        let (store, suite) = makeStore()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        XCTAssertNil(store.reconcile(ctx(.mp100, brians)), "first look announces nothing")
        XCTAssertNil(store.reconcile(ctx(.mp100, brians)), "nothing changed")
        XCTAssertEqual(store.reconcile(ctx(.reps750, brians)), "Every rental now counts toward one 750-hour total.")
        XCTAssertNil(store.reconcile(ctx(.reps750, brians)))
    }

    @MainActor
    func testReconcileSnapshotSurvivesARelaunch() {
        let suite = "RentalPlanTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        RentalPlanStore(defaults: defaults, userId: { "p1" }).reconcile(ctx(.mp100, brians))
        let relaunched = RentalPlanStore(defaults: defaults, userId: { "p1" })
        XCTAssertEqual(relaunched.reconcile(ctx(.mp100, brians, who: [santa.id: .someoneElse])),
                       "Santa now has its own 500-hour target.")
    }

    @MainActor
    func testTrackDescribeParseRoundTrip() {
        let tracks: [RentalTrack] = [.ownTarget(hours: 100), .ownTarget(hours: 500), .sharedTotal(hours: 750),
                                     .recordOnly(.longStays), .recordOnly(.someoneElse), .recordOnly(.yourChoice), .recordOnly(.goalIsRecord)]
        for t in tracks { XCTAssertEqual(RentalPlanStore.parse(RentalPlanStore.describe(t)), t) }
        XCTAssertNil(RentalPlanStore.parse("garbage"))
    }

    func testOverrideCodableRoundTrip() throws {
        for o in [RentalOverride.track, .record, .trackPinned(hours: 100)] {
            let data = try JSONEncoder().encode(o)
            XCTAssertEqual(try JSONDecoder().decode(RentalOverride.self, from: data), o)
        }
    }

    // MARK: Check my goal

    func testDraftSomeoneElseMovesA100To500() {
        let c = ctx(.mp100, brians)
        let rows = GoalCheck.rows(c, draft: [santa.id: .someoneElse])
        let row = rows.first { $0.propertyId == santa.id }!
        XCTAssertEqual(row.current, .ownTarget(hours: 100))
        XCTAssertEqual(row.proposed, .ownTarget(hours: 500))
        XCTAssertTrue(row.changes)
        XCTAssertEqual(row.whoDoesMost, .someoneElse)
    }

    func testPinnedOverrideDoesNotMove() {
        let c = ctx(.mp100, brians, overrides: [santa.id: .trackPinned(hours: 100)])
        let row = GoalCheck.rows(c, draft: [santa.id: .someoneElse]).first { $0.propertyId == santa.id }!
        XCTAssertEqual(row.current, .ownTarget(hours: 100))
        XCTAssertEqual(row.proposed, .ownTarget(hours: 100))
        XCTAssertFalse(row.changes)
    }

    func testUnchangedRowsDoNotChange() {
        let c = ctx(.mp100, brians, who: [delaney.id: .me])
        let rows = GoalCheck.rows(c, draft: [santa.id: .me])
        XCTAssertEqual(rows.map(\.propertyId), brians.map(\.id), "rows keep list order")
        XCTAssertTrue(rows.allSatisfy { !$0.changes })
        XCTAssertEqual(rows.first { $0.propertyId == delaney.id }?.whoDoesMost, .me, "an earlier answer shows when not in the draft")
    }

    func testCheckMyGoalAvailability() {
        XCTAssertTrue(GoalCheck.asksPerRental(ctx(.mp100, brians)))
        XCTAssertFalse(GoalCheck.asksPerRental(ctx(.reps750, brians)))
        XCTAssertFalse(GoalCheck.asksPerRental(ctx(.mp500, brians, grouping: true)))
        XCTAssertTrue(GoalCheck.isAvailable(ctx(.reps750, brians)))
        XCTAssertFalse(GoalCheck.isAvailable(ctx(.mp100, [])))
    }
}
