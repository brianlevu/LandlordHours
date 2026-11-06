import XCTest
@testable import LandlordHours

// MARK: - Countable hours drive the stage

@MainActor
final class TodayHouseCountableHoursTests: CaptureTestCase {
    private var savedSpouseTracking = true
    private var savedGoal: HourGoalType = .reps

    override func setUp() async throws {
        try await super.setUp()
        savedSpouseTracking = TaxProfileManager.shared.spouseTracking
        savedGoal = GoalManager.shared.globalGoalType
        TodayHouseEvents.shared.takeConfirm()
    }

    override func tearDown() async throws {
        TaxProfileManager.shared.spouseTracking = savedSpouseTracking
        GoalManager.shared.globalGoalType = savedGoal
        TodayHouseEvents.shared.takeConfirm()
        try await super.tearDown()
    }

    private func add(_ vm: AppViewModel, _ property: UUID, _ hours: Double, _ category: ActivityCategory, _ who: Participant = .selfParticipant) {
        vm.addTimeEntry(propertyId: property, participant: who, category: category, hours: hours, date: Date(), notes: "")
    }

    func testREPSCountsOwnHoursOnlyInvestorTasksAndSpouseExcluded() {
        let (vm, property) = makeViewModel()
        TaxProfileManager.shared.spouseTracking = true          // even when tracked jointly
        add(vm, property, 120, .repairs)
        add(vm, property, 60, .investing)                       // investor-only
        add(vm, property, 30, .financing)                       // investor-only
        add(vm, property, 400, .management, .spouse)            // spouse never fills YOUR 750

        let hours = vm.houseCountableHours(goal: .reps750)
        XCTAssertEqual(hours, 120, accuracy: 0.001)
        XCTAssertEqual(hours, vm.repsStatus(participant: .selfParticipant, year: Calendar.current.component(.year, from: Date())).realEstateHours,
                       accuracy: 0.001, "The house reuses the tax engine's REPS hours")
        // 120h of 750 = just started, not the framing the 610h total would draw.
        XCTAssertEqual(HouseProgress(hours: hours, goal: .reps750).stage, .started)
        XCTAssertEqual(HouseProgress(hours: 610, goal: .reps750).stage, .half)
    }

    func testMaterialParticipationCountsSpouseOnlyWhenTrackedJointly() {
        let (vm, property) = makeViewModel()
        add(vm, property, 70, .repairs)
        add(vm, property, 40, .leasing, .spouse)
        add(vm, property, 25, .contractNegotiation)             // investor-only

        TaxProfileManager.shared.spouseTracking = true
        let joint = vm.houseCountableHours(goal: .mp100)
        XCTAssertEqual(joint, 110, accuracy: 0.001)
        XCTAssertEqual(HouseProgress(hours: joint, goal: .mp100).stage, .complete)
        XCTAssertTrue(HouseProgress(hours: joint, goal: .mp100).isGoalMet)

        TaxProfileManager.shared.spouseTracking = false
        let solo = vm.houseCountableHours(goal: .mp100)
        XCTAssertEqual(solo, 70, accuracy: 0.001)
        XCTAssertEqual(HouseProgress(hours: solo, goal: .mp100).stage, .half)
        XCTAssertFalse(HouseProgress(hours: solo, goal: .mp100).isGoalMet)
    }

    func testGoalSettingPicksTheHouseGoal() {
        let (vm, _) = makeViewModel()
        GoalManager.shared.globalGoalType = .str
        XCTAssertEqual(vm.houseGoal, .mp100)
        GoalManager.shared.globalGoalType = .both
        XCTAssertEqual(vm.houseGoal, .reps750)
    }

    func testOtherYearsNeverCount() {
        let (vm, property) = makeViewModel()
        let lastYear = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        vm.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs, hours: 300, date: lastYear, notes: "")
        XCTAssertEqual(vm.houseCountableHours(goal: .reps750), 0, accuracy: 0.001)
    }
}

// MARK: - Confirm hooks

@MainActor
final class TodayHouseConfirmHookTests: CaptureTestCase {
    private var events: TodayHouseEvents { TodayHouseEvents.shared }
    private var savedGoal: HourGoalType = .reps

    override func setUp() async throws {
        try await super.setUp()
        savedGoal = GoalManager.shared.globalGoalType
        GoalManager.shared.globalGoalType = .reps
        events.takeConfirm()
    }

    override func tearDown() async throws {
        events.takeConfirm()
        GoalManager.shared.globalGoalType = savedGoal
        try await super.tearDown()
    }

    private func liveViewModel() -> (AppViewModel, UUID) {
        let (vm, property) = makeViewModel()
        vm.suppressCelebrations = false
        vm.activeCelebration = nil
        return (vm, property)
    }

    func testManualLogFiresConfirmWithBeforeAndAfterHours() {
        let (vm, property) = liveViewModel()
        vm.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs, hours: 10, date: Date(), notes: "")
        events.takeConfirm()
        vm.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs, hours: 2, date: Date(), notes: "")
        let confirm = events.takeConfirm()
        XCTAssertEqual(confirm?.oldHours ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(confirm?.newHours ?? -1, 12, accuracy: 0.001)
        XCTAssertNil(events.pendingConfirm, "Taking the confirm consumes it")
    }

    func testSavesWhileAwayMergeIntoOneBuild() {
        let (vm, property) = liveViewModel()
        vm.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs, hours: 3, date: Date(), notes: "")
        vm.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .leasing, hours: 2, date: Date(), notes: "")
        let confirm = events.takeConfirm()
        XCTAssertEqual(confirm?.oldHours ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(confirm?.newHours ?? -1, 5, accuracy: 0.001)
    }

    func testSavesNeverShowTheOldConfettiOverlay() {
        let (vm, property) = liveViewModel()
        for hours in [12.0, 45, 200, 300] {   // crosses the old 10 / 50 / 250 overlay counts
            vm.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs, hours: hours, date: Date(), notes: "")
            XCTAssertNil(vm.activeCelebration)
        }
        XCTAssertTrue(PendingCelebrationQueue.pending().isEmpty)
        if let next = events.nextCelebration { events.markPresented(next.celebration, year: next.year) }
    }

    func testInvestorOnlyEntryDoesNotBuild() {
        let (vm, property) = liveViewModel()
        vm.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .investing, hours: 5, date: Date(), notes: "")
        XCTAssertNil(events.pendingConfirm, "Hours that do not count never move the house")
    }

    func testTimerStopFiresConfirm() {
        let (vm, property) = liveViewModel()
        vm.startTimer(propertyId: property, category: .repairs)
        vm.timerStartTime = Date().addingTimeInterval(-2 * 3600)
        vm.stopTimer(participant: .selfParticipant)
        let confirm = events.takeConfirm()
        XCTAssertNotNil(confirm)
        XCTAssertEqual(confirm?.newHours ?? 0, 2, accuracy: 0.05)
    }

    func testInboxConfirmFiresConfirm() {
        let (vm, property) = liveViewModel()
        let store = makeStore()
        let s = calendarSuggestion(start: Date().addingTimeInterval(-7200), propertyId: property, hours: 2, category: .repairs)
        store.ingest([s], existingEntries: [], calendar: calendar)
        let result = vm.confirm(s, store: store, profileId: profileId)
        XCTAssertNotNil(result.entryId)
        let confirm = events.takeConfirm()
        XCTAssertEqual(confirm?.newHours ?? 0, 2, accuracy: 0.001)

        // Confirming again is idempotent: no second build.
        _ = vm.confirm(s, store: store, profileId: profileId)
        XCTAssertNil(events.pendingConfirm)
    }

    func testCrossingAHouseMilestoneQueuesItAndSkipsTheOldOverlay() {
        let (vm, property) = liveViewModel()
        vm.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs, hours: 98, date: Date(), notes: "")
        vm.activeCelebration = nil
        vm.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs, hours: 4, date: Date(), notes: "")
        XCTAssertEqual(events.nextCelebration?.celebration, .stage(.foundation100))
        XCTAssertNil(vm.activeCelebration, "No 1.x confetti on a save; the house is the only reward")
        if let next = events.nextCelebration { events.markPresented(next.celebration, year: next.year) }
    }

    func testSuppressedSavesNeverBuild() {
        let (vm, property) = makeViewModel()   // suppressCelebrations = true (mock seeding)
        vm.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs, hours: 5, date: Date(), notes: "")
        XCTAssertNil(events.pendingConfirm)
    }
}

// MARK: - Celebrate once

@MainActor
final class TodayHouseCelebrationLedgerTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "today-house-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func events(profile: String = "p1") -> TodayHouseEvents {
        let defaults = self.defaults!
        return TodayHouseEvents(ledger: { HouseCelebrationLedger(defaults: defaults, userId: profile) })
    }

    func testCrossingQueuesOnceAndNeverRepeats() {
        let hub = events()
        hub.entrySaved(from: 95, to: 105, goal: .reps750, year: 2026)
        XCTAssertEqual(hub.nextCelebration?.celebration, .stage(.foundation100))
        hub.markPresented(.stage(.foundation100), year: 2026)
        XCTAssertNil(hub.nextCelebration)

        // Delete back under 100 and cross it again: never celebrated twice.
        hub.entrySaved(from: 99, to: 101, goal: .reps750, year: 2026)
        XCTAssertNil(hub.nextCelebration)

        // A relaunch (new hub, same profile) remembers it.
        let relaunched = events()
        relaunched.entrySaved(from: 90, to: 110, goal: .reps750, year: 2026)
        XCTAssertNil(relaunched.nextCelebration)
    }

    func testPerYearAndPerProfile() {
        let hub = events()
        hub.entrySaved(from: 95, to: 105, goal: .reps750, year: 2026)
        hub.markPresented(.stage(.foundation100), year: 2026)

        hub.entrySaved(from: 95, to: 105, goal: .reps750, year: 2027)
        XCTAssertEqual(hub.nextCelebration?.year, 2027, "A new tax year earns the slab again")

        let spouseProfile = events(profile: "p2")
        spouseProfile.entrySaved(from: 95, to: 105, goal: .reps750, year: 2026)
        XCTAssertEqual(spouseProfile.nextCelebration?.celebration, .stage(.foundation100), "Another profile has its own ledger")
    }

    func testBigJumpShowsTheHighestAndRetiresTheLower() {
        let hub = events()
        hub.entrySaved(from: 0, to: 520, goal: .reps750, year: 2026)
        XCTAssertEqual(hub.nextCelebration?.celebration, .stage(.roof500))
        hub.markPresented(.stage(.roof500), year: 2026)
        XCTAssertNil(hub.nextCelebration, "The slab is not shown after the roof")
        hub.entrySaved(from: 90, to: 120, goal: .reps750, year: 2026)
        XCTAssertNil(hub.nextCelebration)
    }

    func testGoalKeysReplaceTheStageAtTheSameThreshold() {
        let hub = events()
        hub.entrySaved(from: 740, to: 751, goal: .reps750, year: 2026)
        XCTAssertEqual(hub.nextCelebration?.celebration, .goalMet(.reps750))

        let mp = events(profile: "mp")
        mp.entrySaved(from: 98, to: 101, goal: .mp100, year: 2026)
        XCTAssertEqual(mp.nextCelebration?.celebration, .goalMet(.mp100))
    }

    func testExactly750IsNotTheKeys() {
        let hub = events()
        hub.entrySaved(from: 740, to: 750, goal: .reps750, year: 2026)
        XCTAssertNil(hub.nextCelebration, "REPS is MORE than 750 hours")
    }

    func testPendingSurvivesRelaunchUntilPresented() {
        events().entrySaved(from: 480, to: 502, goal: .reps750, year: 2026)
        let relaunched = events()
        XCTAssertEqual(relaunched.nextCelebration?.celebration, .stage(.roof500))
    }

    func testQueueProtocolFeedsTodayAndIgnoresCelebrated() {
        let hub = events()
        let queue: HouseMilestoneQueue = hub
        queue.enqueue(.stage(.roof500), year: 2026)
        XCTAssertEqual(hub.nextCelebration?.celebration, .stage(.roof500))
        hub.markPresented(.stage(.roof500), year: 2026)
        queue.enqueue(.stage(.roof500), year: 2026)
        XCTAssertNil(hub.nextCelebration)
    }

    func testTokensRoundTrip() {
        for c in [HouseCelebration.stage(.foundation100), .stage(.roof500), .stage(.keys750), .goalMet(.reps750), .goalMet(.mp500), .goalMet(.mp100)] {
            let parsed = HouseCelebrationLedger.parse(token: HouseCelebrationLedger.token(c, year: 2026))
            XCTAssertEqual(parsed?.celebration, c)
            XCTAssertEqual(parsed?.year, 2026)
        }
    }

    func testBackfillRevealShowsOnce() {
        let hub = events()
        hub.backfillFinished(foundHours: 0, suggestionCount: 0)
        XCTAssertNil(hub.pendingBackfill, "Nothing found, nothing to reveal")
        hub.backfillFinished(foundHours: 212, suggestionCount: 14)
        XCTAssertEqual(hub.pendingBackfill?.foundHours, 212)
        hub.markBackfillShown()
        hub.backfillFinished(foundHours: 212, suggestionCount: 14)
        XCTAssertNil(hub.pendingBackfill)
        XCTAssertNil(events().pendingBackfill)
    }
}

// MARK: - Pace line

final class TodayPaceTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: 12))!
    }

    func testBehindIsHonestAndRoundsAgainstTheUser() {
        // Jul 2 2026 = day 183 of 365; 750 × 183/365 = 376.03 expected.
        let pace = TodayPace.resolve(hours: 364, goal: .reps750, date: day(7, 2), calendar: calendar)
        XCTAssertEqual(pace, TodayPace(text: "Behind by 13h", tone: .caution))
    }

    func testOnPaceAndAhead() {
        XCTAssertEqual(TodayPace.resolve(hours: 394.5, goal: .reps750, date: day(7, 2), calendar: calendar),
                       TodayPace(text: "On pace, 18h ahead", tone: .positive))
        XCTAssertEqual(TodayPace.resolve(hours: 376.5, goal: .reps750, date: day(7, 2), calendar: calendar),
                       TodayPace(text: "On pace", tone: .positive))
    }

    func testZeroAndMet() {
        XCTAssertEqual(TodayPace.resolve(hours: 0, goal: .reps750, date: day(7, 2), calendar: calendar).tone, .neutral)
        XCTAssertEqual(TodayPace.resolve(hours: 751, goal: .reps750, date: day(7, 2), calendar: calendar),
                       TodayPace(text: "Goal hours met", tone: .positive))
        XCTAssertNotEqual(TodayPace.resolve(hours: 750, goal: .reps750, date: day(12, 31), calendar: calendar).text,
                          "Goal hours met", "Exactly 750 is not more than 750")
    }
}
