import XCTest
@testable import LandlordHours

/// 2.0 onboarding rules: step routing, the skip path, permission-denied paths, 0 found, and the
/// one source of "N found" (the profile's inbox).
@MainActor
final class OnboardingFlowTests: XCTestCase {

    // MARK: Fakes

    private final class Recorder {
        var events: [OnbEvent] = []
        var goal: OnbGoal?
        var who: OnbWho?
        var property: (String, String)?
        var calendarSuggestions: Bool?
        var eventPrompts: Bool?
        var completion: OnbCompletion?
        var profileEnsured = 0
        var calendarPrompts = 0
        var notifyPrompts = 0
        var backfillStarts = 0
        var backfillUpdate: (@MainActor (OnbScanUpdate) -> Void)?
    }

    private func makeFlow(
        cohort: OnbCohort = .new,
        calendar: CalendarAccess = .fullAccess,
        notifications: Bool = true,
        startAt: OnbStep? = nil,
        recorder r: Recorder
    ) -> OnbFlow {
        var s = OnbServices()
        s.ensureProfile = { r.profileEnsured += 1 }
        s.saveGoal = { r.goal = $0 }
        s.saveWho = { r.who = $0 }
        s.addProperty = { r.property = ($0, $1) }
        s.requestCalendar = { r.calendarPrompts += 1; return calendar }
        s.setCalendarSuggestions = { r.calendarSuggestions = $0 }
        s.startBackfill = { update in r.backfillStarts += 1; r.backfillUpdate = update }
        s.requestNotifications = { r.notifyPrompts += 1; return notifications }
        s.setEventPrompts = { r.eventPrompts = $0 }
        s.complete = { r.completion = $0 }
        s.track = { r.events.append($0) }
        return OnbFlow(cohort: cohort, services: s, startAt: startAt)
    }

    private func suggestion(_ key: String, hours: Double?, backfill: Bool = true, pending: Bool = true,
                            category: ActivityCategory? = .repairs,
                            detectedAt: Date = Date(timeIntervalSince1970: 1_000)) -> Suggestion {
        var s = Suggestion(sourceKey: "cal:\(key)", kind: .calendar, detectedAt: detectedAt, start: detectedAt,
                           title: key, proposedCategory: category, proposedHours: hours, hoursBasis: .scheduled,
                           confidence: 0.9, isBackfill: backfill)
        if !pending { s.state = .dismissed(reason: .notLandlordWork) }
        return s
    }

    // MARK: Routing (pure)

    func testNewUserSequenceAndProgress() {
        XCTAssertEqual(OnbRouting.newUserSequence, [.welcome, .goal, .calendar, .who, .property, .notify, .staked])
        let flow = makeFlow(recorder: Recorder())
        XCTAssertEqual(flow.progressTotal, 6)
        XCTAssertEqual(flow.progressValue, 0)
    }

    func testNotifyIsAskedOnlyAfterACalendarGrant() {
        let seq = OnbRouting.newUserSequence
        let property = seq.firstIndex(of: .property)!
        XCTAssertEqual(OnbRouting.next(from: property, in: seq, calendar: .allowed, skippedProperty: false), .step(property + 1))
        for answer in [OnbCalendar.denied, .notNow, .notAsked] {
            XCTAssertEqual(OnbRouting.next(from: property, in: seq, calendar: answer, skippedProperty: false),
                           .step(seq.firstIndex(of: .staked)!), "\(answer) skips the visit-end note")
        }
    }

    func testBackSkipsTheUnaskedNoteAndStopsAtWelcome() {
        let seq = OnbRouting.newUserSequence
        let staked = seq.firstIndex(of: .staked)!
        XCTAssertEqual(OnbRouting.back(from: staked, in: seq, calendar: .notNow), seq.firstIndex(of: .property))
        XCTAssertEqual(OnbRouting.back(from: staked, in: seq, calendar: .allowed), seq.firstIndex(of: .notify))
        XCTAssertNil(OnbRouting.back(from: 0, in: seq, calendar: .allowed))
    }

    func testSkippedPropertyNeverReachesStaked() {
        let seq = OnbRouting.newUserSequence
        let property = seq.firstIndex(of: .property)!
        XCTAssertEqual(OnbRouting.next(from: property, in: seq, calendar: .notNow, skippedProperty: true), .finish)
        // Even with the note pending, a skip goes to Today once the note is answered.
        XCTAssertEqual(OnbRouting.next(from: property, in: seq, calendar: .allowed, skippedProperty: true), .step(property + 1))
        XCTAssertEqual(OnbRouting.next(from: property + 1, in: seq, calendar: .allowed, skippedProperty: true), .finish)
    }

    func testUpgraderSequence() {
        let seq = OnbRouting.upgradeSequence
        XCTAssertEqual(seq, [.wnHouse, .calendar, .notify])
        XCTAssertEqual(OnbRouting.next(from: 1, in: seq, calendar: .notNow, skippedProperty: false), .finish)
        XCTAssertEqual(OnbRouting.next(from: 1, in: seq, calendar: .allowed, skippedProperty: false), .step(2))
        XCTAssertEqual(OnbRouting.next(from: 2, in: seq, calendar: .allowed, skippedProperty: false), .finish)
        let flow = makeFlow(cohort: .upgrade, recorder: Recorder())
        XCTAssertEqual(flow.progressTotal, 3)
        XCTAssertEqual(flow.progressValue, 1)
    }

    // MARK: Skip path: six taps to Today

    func testSkipPathIsSixTapsAndLandsOnTodayWithNothingAsked() async {
        let r = Recorder()
        let flow = makeFlow(recorder: r)
        var taps = 0
        flow.start(); taps += 1                       // Start building
        XCTAssertEqual(flow.step, .goal)
        flow.goal = .reps750; taps += 1               // the 750 card
        flow.confirmGoal(); taps += 1                 // Build toward 750h
        XCTAssertEqual(flow.step, .calendar)
        flow.calendarNotNow(); taps += 1              // Not now
        XCTAssertEqual(flow.step, .who)
        flow.confirmWho(); taps += 1                  // Continue (just me)
        XCTAssertEqual(flow.step, .property)
        flow.skipProperty(); taps += 1                // I'll add it later
        XCTAssertEqual(taps, 6)
        XCTAssertEqual(r.completion, OnbCompletion(cohort: .new, openInbox: false, foundShown: false,
                                                   skippedProperty: true, calendar: .notNow))
        XCTAssertEqual(r.calendarPrompts, 0, "Not now never spends the system prompt")
        XCTAssertEqual(r.notifyPrompts, 0)
        XCTAssertEqual(r.backfillStarts, 0)
        XCTAssertEqual(r.calendarSuggestions, false)
        XCTAssertNil(r.property)
        XCTAssertEqual(r.who, .me)
        XCTAssertEqual(r.goal, .reps750)
        XCTAssertEqual(r.profileEnsured, 1)
        XCTAssertTrue(r.events.contains(.propertyAdded(hasAddress: false, skipped: true)))
        XCTAssertTrue(r.events.contains(.calendarResult(.notNow)))
    }

    func testGoalButtonDoesNothingUntilACardIsChosen() {
        let r = Recorder()
        let flow = makeFlow(startAt: .goal, recorder: r)
        flow.confirmGoal()
        XCTAssertEqual(flow.step, .goal)
        XCTAssertNil(r.goal)
    }

    // MARK: Happy path

    func testHappyPathStartsTheBackfillAndAsksTheNoteOnce() async {
        let r = Recorder()
        let flow = makeFlow(startAt: .calendar, recorder: r)
        flow.goal = .mp500
        await flow.askCalendar()
        XCTAssertEqual(flow.calendar, .allowed)
        XCTAssertEqual(r.calendarSuggestions, true)
        XCTAssertEqual(r.backfillStarts, 1)
        XCTAssertEqual(flow.scan, .running)
        XCTAssertEqual(flow.step, .who)
        flow.who = .both
        flow.confirmWho()
        XCTAssertEqual(r.who, .both)
        flow.name = "  Oak Street duplex "
        XCTAssertTrue(flow.saveProperty())
        XCTAssertEqual(r.property?.0, "Oak Street duplex")
        XCTAssertEqual(r.property?.1, "", "The folded address is not saved")
        flow.stakeDropped = true
        XCTAssertFalse(flow.saveProperty(), "One tap: a second save does nothing")
        flow.next()
        XCTAssertEqual(flow.step, .notify)
        await flow.askNotify()
        XCTAssertEqual(r.notifyPrompts, 1)
        XCTAssertEqual(r.eventPrompts, true)
        XCTAssertEqual(flow.step, .staked)
    }

    func testPropertyAddressIsSavedOnlyWhenOpened() {
        let r = Recorder()
        let flow = makeFlow(startAt: .property, recorder: r)
        flow.name = "Pine"
        flow.address = "14 Pine Ridge Rd"
        flow.addressOpen = true
        flow.saveProperty()
        XCTAssertEqual(r.property?.1, "14 Pine Ridge Rd")
        XCTAssertTrue(r.events.contains(.propertyAdded(hasAddress: true, skipped: false)))
    }

    func testEmptyNameCannotBeSaved() {
        let r = Recorder()
        let flow = makeFlow(startAt: .property, recorder: r)
        flow.name = "   "
        XCTAssertFalse(flow.saveProperty())
        XCTAssertNil(r.property)
    }

    // MARK: Permission denied

    func testCalendarDeniedContinuesWithoutTheNoteOrABackfill() async {
        let r = Recorder()
        let flow = makeFlow(calendar: .denied, startAt: .calendar, recorder: r)
        await flow.askCalendar()
        XCTAssertEqual(flow.calendar, .denied)
        XCTAssertEqual(r.calendarSuggestions, false)
        XCTAssertEqual(r.backfillStarts, 0)
        XCTAssertEqual(flow.step, .who)
        flow.confirmWho()
        flow.name = "Oak"
        flow.saveProperty()
        flow.next()
        XCTAssertEqual(flow.step, .staked, "No visit-end note without the calendar")
        XCTAssertEqual(flow.stakedHeadline, .plain)
        XCTAssertTrue(r.events.contains(.calendarResult(.denied)))
    }

    func testWriteOnlyCalendarCountsAsDenied() async {
        let r = Recorder()
        let flow = makeFlow(calendar: .limited, startAt: .calendar, recorder: r)
        await flow.askCalendar()
        XCTAssertEqual(flow.calendar, .denied)
        XCTAssertEqual(r.backfillStarts, 0)
    }

    func testNotificationsDeniedStaysOff() async {
        let r = Recorder()
        let flow = makeFlow(notifications: false, startAt: .notify, recorder: r)
        flow.calendar = .allowed
        await flow.askNotify()
        XCTAssertEqual(r.eventPrompts, false)
        XCTAssertEqual(flow.notify, false)
        XCTAssertTrue(r.events.contains(.notifyResult("denied")))
    }

    func testNotifyNotNowNeverPrompts() {
        let r = Recorder()
        let flow = makeFlow(startAt: .notify, recorder: r)
        flow.calendar = .allowed
        flow.notifyNotNow()
        XCTAssertEqual(r.notifyPrompts, 0)
        XCTAssertEqual(r.eventPrompts, false)
        XCTAssertEqual(flow.step, .staked)
    }

    // MARK: Found count: source, 0 found, still running

    func testFoundCountsOnlyPendingBackfillItemsTheInboxShows() {
        let now = Date(timeIntervalSince1970: 10_000)
        let items = [
            suggestion("a", hours: 2),
            suggestion("b", hours: 1.5),
            suggestion("c", hours: nil),                                     // counted, no hours
            suggestion("live", hours: 3, backfill: false),                    // not the look-back
            suggestion("gone", hours: 4, pending: false),                     // already answered
            suggestion("future", hours: 5, detectedAt: Date(timeIntervalSince1970: 20_000)), // not visible yet
        ]
        let found = OnbFound.from(items, now: now)
        XCTAssertEqual(found, OnbFound(count: 3, hours: 3.5))
        XCTAssertEqual(found.count, InboxLogic.visible(items, now: now).filter(\.isBackfill).count,
                       "The same items the Inbox lists")
        XCTAssertEqual(found.hoursText, "3.5h")
    }

    func testNonCountableCategoriesNeverFeedFoundHours() {
        let now = Date(timeIntervalSince1970: 10_000)
        let items = [
            suggestion("plumber", hours: 2, category: .repairs),
            suggestion("refi", hours: 3, category: .financing),
            suggestion("offer", hours: 1, category: .contractNegotiation),
            suggestion("deal", hours: 4, category: .investing),
            suggestion("unsure", hours: 1, category: nil),
        ]
        let found = OnbFound.from(items, now: now)
        XCTAssertEqual(found.hours, 3, "Only countable work (and not-yet-categorised items) adds hours")
        XCTAssertEqual(found.count, 5, "Every item still waits in the Inbox")
    }

    func testHoursTextNeverRoundsUp() {
        XCTAssertEqual(OnbFormat.hours(23), "23h")
        XCTAssertEqual(OnbFormat.hours(22.99), "22.9h")
        XCTAssertEqual(OnbFormat.hours(0.25), "0.2h")
        XCTAssertEqual(OnbFormat.suggestions(1), "1 suggestion")
        XCTAssertEqual(OnbFormat.suggestions(14), "14 suggestions")
    }

    func testStakedHeadlineStates() {
        let some = OnbFound(count: 14, hours: 23)
        XCTAssertEqual(OnbStakedHeadline.make(calendar: .allowed, scan: .finished, found: some), .found(some))
        XCTAssertEqual(OnbStakedHeadline.make(calendar: .allowed, scan: .finished, found: some).reviewCount, 14)
        XCTAssertEqual(OnbStakedHeadline.make(calendar: .allowed, scan: .finished, found: .none), .nothingFound)
        XCTAssertNil(OnbStakedHeadline.nothingFound.reviewCount, "0 found goes to Today, not an empty Inbox")
        XCTAssertEqual(OnbStakedHeadline.make(calendar: .allowed, scan: .running, found: some), .lookingBack(some))
        XCTAssertNil(OnbStakedHeadline.lookingBack(some).reviewCount, "Still running: no number to review yet")
        XCTAssertEqual(OnbStakedHeadline.make(calendar: .allowed, scan: .blocked, found: some), .plain)
        XCTAssertEqual(OnbStakedHeadline.make(calendar: .denied, scan: .finished, found: some), .plain)
        XCTAssertEqual(OnbStakedHeadline.make(calendar: .notNow, scan: .idle, found: .none), .plain)
    }

    func testPropertyHint() {
        let nine = OnbFound(count: 9, hours: 12)
        XCTAssertEqual(OnbCopy.propertyHint(calendar: .allowed, scan: .running, found: nine), "9 suggestions so far · still looking")
        XCTAssertEqual(OnbCopy.propertyHint(calendar: .allowed, scan: .finished, found: nine), "9 suggestions waiting")
        XCTAssertNil(OnbCopy.propertyHint(calendar: .allowed, scan: .finished, found: .none))
        XCTAssertNil(OnbCopy.propertyHint(calendar: .notNow, scan: .idle, found: nine))
    }

    func testBackfillUpdatesFeedStakedAndReviewOpensInbox() async {
        let r = Recorder()
        let flow = makeFlow(startAt: .calendar, recorder: r)
        await flow.askCalendar()
        r.backfillUpdate?(OnbScanUpdate(state: .running, found: OnbFound(count: 5, hours: 7)))
        XCTAssertEqual(flow.propertyHint, "5 suggestions so far · still looking")
        r.backfillUpdate?(OnbScanUpdate(state: .finished, found: OnbFound(count: 14, hours: 23)))
        XCTAssertEqual(flow.stakedHeadline.reviewCount, 14)
        flow.foundShown = true
        flow.leaveStaked()
        XCTAssertEqual(r.completion?.openInbox, true)
        XCTAssertEqual(r.completion?.foundShown, true)
    }

    func testZeroFoundLeavesStakedForToday() async {
        let r = Recorder()
        let flow = makeFlow(startAt: .calendar, recorder: r)
        await flow.askCalendar()
        r.backfillUpdate?(OnbScanUpdate(state: .finished, found: .none))
        XCTAssertEqual(flow.stakedHeadline, .nothingFound)
        flow.leaveStaked()
        XCTAssertEqual(r.completion?.openInbox, false)
    }

    func testBackfillStartsOnce() async {
        let r = Recorder()
        let flow = makeFlow(startAt: .calendar, recorder: r)
        await flow.askCalendar()
        flow.startBackfill()
        XCTAssertEqual(r.backfillStarts, 1)
    }

    func testFinishFiresOnce() {
        let r = Recorder()
        let flow = makeFlow(startAt: .staked, recorder: r)
        flow.leaveStaked()
        r.completion = nil
        flow.leaveStaked()
        XCTAssertNil(r.completion)
    }

    // MARK: Goals, notes, analytics

    func testGoalMapping() {
        XCTAssertEqual(OnbGoal.reps750.houseGoal, .reps750)
        XCTAssertEqual(OnbGoal.mp500.houseGoal, .mp500)
        XCTAssertEqual(OnbGoal.mp100.houseGoal, .mp100)
        XCTAssertEqual(OnbGoal.record.houseGoal, .reps750)
        XCTAssertEqual(OnbGoal.record.callToAction, "Keep a record")
        XCTAssertEqual(OnbCopy.countLine(goal: .mp500), "0 of 500h")
        XCTAssertEqual(OnbCopy.countLine(goal: .record), "0h in the book")
    }

    func testSpouseNoteFollowsTheGoal() {
        XCTAssertTrue(OnbGoal.spouseNote(for: .reps750).contains("one of you has to get there alone"))
        XCTAssertTrue(OnbGoal.spouseNote(for: .mp100).contains("count together"))
        XCTAssertFalse(OnbGoal.spouseNote(for: .record).contains("750"))
    }

    func testEveryStepFiresAViewEvent() {
        let r = Recorder()
        let flow = makeFlow(recorder: r)
        flow.appeared()
        flow.start()
        XCTAssertEqual(r.events.prefix(2), [.stepViewed(.welcome, .new), .stepViewed(.goal, .new)])
    }

    func testLaunchValues() {
        XCTAssertEqual(OnbStep(launchValue: "0"), .welcome)
        XCTAssertEqual(OnbStep(launchValue: "6"), .staked)
        XCTAssertEqual(OnbStep(launchValue: "property"), .property)
        XCTAssertNil(OnbStep(launchValue: "9"))
    }

    // MARK: Goal choice: material participation at 500 hours, beside 1.x's goals

    func testExistingStoredGoalsReadBackUnchanged() {
        XCTAssertEqual(GoalChoice(hourGoalType: .reps, materialParticipationTarget: 0), .reps750)
        XCTAssertEqual(GoalChoice(hourGoalType: .str, materialParticipationTarget: 0), .mp100, "1.x STR stays the 100-hour test")
        XCTAssertEqual(GoalChoice(hourGoalType: .both, materialParticipationTarget: 0), .record)
        XCTAssertEqual(GoalChoice(hourGoalType: .reps, materialParticipationTarget: 500), .reps750, "A stray target never changes REPS")
        XCTAssertEqual(GoalChoice(hourGoalType: .str, materialParticipationTarget: 500), .mp500)
    }

    func testGoalChoiceTargetsAndHouseGoals() {
        XCTAssertEqual(GoalChoice.allCases.map(\.targetHours), [750, 500, 100, 750])
        XCTAssertEqual(GoalChoice.mp500.houseGoal, .mp500, "500 is never mapped to 100")
        XCTAssertEqual(GoalChoice.mp500.hourGoalType, .str, "1.x devices keep reading a valid goal type")
        XCTAssertEqual(GoalChoice.record.hourGoalType, .both)
        XCTAssertEqual(GoalChoice.mp500.widgetLabels.0, "500h MP")
        XCTAssertEqual(GoalChoice.mp100.widgetLabels.0, "100h STR")
        XCTAssertEqual(OnbGoal.allCases.map(\.goalChoice), [.reps750, .mp500, .mp100, .record], "Onboarding and Settings offer the same goals")
    }

    func testGoalChoiceStorageRoundTripsAndSettingsChangesClearTheTarget() {
        let manager = GoalManager.shared
        let saved = manager.goalChoice
        defer { manager.setGoalChoice(saved) }
        for choice in GoalChoice.allCases {
            manager.setGoalChoice(choice)
            XCTAssertEqual(manager.goalChoice, choice)
        }
        manager.setGoalChoice(.mp500)
        XCTAssertEqual(manager.houseGoal, .mp500)
        manager.setGlobalGoal(.str)
        XCTAssertEqual(manager.goalChoice, .mp100, "A plain 1.x goal change drops the 500 target")
    }

    func testSyncedTargetAppliesAndOlderRecordsKeepIt() {
        let manager = GoalManager.shared
        let saved = manager.goalChoice
        defer { manager.setGoalChoice(saved) }
        let app = AppModelHost.shared.viewModel
        manager.setGoalChoice(.mp100)
        app.syncDidReceiveGoalSettings(globalGoalType: .str, propertyGoals: [], materialParticipationTarget: 500)
        XCTAssertEqual(manager.goalChoice, .mp500)
        app.syncDidReceiveGoalSettings(globalGoalType: .str, propertyGoals: [], materialParticipationTarget: nil)
        XCTAssertEqual(manager.goalChoice, .mp500, "A record without the field (pre-2.0 device) keeps the target")
        app.syncDidReceiveGoalSettings(globalGoalType: .str, propertyGoals: [], materialParticipationTarget: 0)
        XCTAssertEqual(manager.goalChoice, .mp100)
    }

    func testWidgetAndEngagementMeasureAgainstFiveHundred() {
        let manager = GoalManager.shared
        let saved = manager.goalChoice
        defer { manager.setGoalChoice(saved) }
        manager.setGoalChoice(.mp500)
        let context = AppModelHost.shared.viewModel.engagementContext()
        XCTAssertEqual(context.targetHours, 500)
        manager.setGoalChoice(.mp100)
        XCTAssertEqual(AppModelHost.shared.viewModel.engagementContext().targetHours, 100)
    }

    // MARK: House goal storage (500 vs 100 hours)

    func testHouseGoalStoresTheFiveHundredHourTarget() {
        let manager = GoalManager.shared
        let saved = manager.globalGoalType
        defer { manager.setGlobalGoal(saved) }
        manager.setHouseGoal(.mp500)
        XCTAssertEqual(manager.globalGoalType, .str, "1.x devices keep a valid goal")
        XCTAssertEqual(manager.houseGoal, .mp500)
        manager.setHouseGoal(.mp100)
        XCTAssertEqual(manager.houseGoal, .mp100)
        manager.setHouseGoal(.mp500)
        manager.setGlobalGoal(.str)
        XCTAssertEqual(manager.houseGoal, .mp100, "A plain goal change drops the 500 target")
        manager.setHouseGoal(.reps750)
        XCTAssertEqual(manager.houseGoal, .reps750)
    }
}

// MARK: - Placing what the look-back found before the first property existed

@MainActor
final class OnboardingPlacementTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("onb-place-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func item(_ key: String, property: UUID? = nil, pending: Bool = true) -> Suggestion {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var s = Suggestion(sourceKey: "cal:\(key)", kind: .calendar, detectedAt: start, start: start,
                           end: start.addingTimeInterval(3600), title: key, proposedPropertyId: property,
                           proposedCategory: .repairs, proposedHours: 1, hoursBasis: .scheduled, confidence: 0.9,
                           isBackfill: true)
        if !pending { s.state = .dismissed(reason: .notLandlordWork) }
        return s
    }

    func testOnlyASolePropertyIsUsed() {
        let one = RentalProperty(name: "Oak", address: "", propertyType: .ltr)
        let two = RentalProperty(name: "Pine", address: "", propertyType: .str)
        XCTAssertEqual(OnbPlacement.soleProperty([one]), one.id)
        XCTAssertNil(OnbPlacement.soleProperty([one, two]), "Several properties: nothing is guessed")
        XCTAssertNil(OnbPlacement.soleProperty([]))
    }

    func testOnePropertyAttachesToEveryPendingUnplacedSuggestion() {
        let store = SuggestionStore(userId: "onb", baseDirectory: dir)
        let oak = UUID(), elsewhere = UUID()
        store.ingest([item("a"), item("b"), item("placed", property: elsewhere)], existingEntries: [])
        XCTAssertEqual(store.attachPropertyToUnplaced(oak), 2)
        XCTAssertEqual(store.pending.filter { $0.proposedPropertyId == oak }.count, 2)
        XCTAssertEqual(store.suggestion(forKey: "cal:placed")?.proposedPropertyId, elsewhere, "A matched property is kept")
        // Saved: a fresh store reads the same.
        let reread = SuggestionStore(userId: "onb", baseDirectory: dir)
        XCTAssertTrue(reread.pending.allSatisfy { $0.proposedPropertyId != nil })
        // Every row is now one-tap confirmable.
        XCTAssertTrue(reread.pending.filter { $0.proposedPropertyId == oak }
            .allSatisfy { InboxLogic.canQuickLog($0, propertyIds: [oak, elsewhere]) })
    }

    func testARescanKeepsTheAttachedProperty() {
        let store = SuggestionStore(userId: "onb", baseDirectory: dir)
        let oak = UUID()
        store.ingest([item("a")], existingEntries: [])
        store.attachPropertyToUnplaced(oak)
        store.ingest([item("a")], existingEntries: [])            // the look-back runs again
        XCTAssertEqual(store.suggestion(forKey: "cal:a")?.proposedPropertyId, oak)
    }

    func testNothingToAttachChangesNothing() {
        let store = SuggestionStore(userId: "onb", baseDirectory: dir)
        store.ingest([item("placed", property: UUID())], existingEntries: [])
        XCTAssertEqual(store.attachPropertyToUnplaced(UUID()), 0)
    }
}
