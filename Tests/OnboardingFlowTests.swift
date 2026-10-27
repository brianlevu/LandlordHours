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
        var property: (String, String, PropertyType)?
        var goalAnswers: (RentalMix, RealEstatePro)?
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
        s.saveGoalAnswers = { r.goalAnswers = ($0, $1) }
        s.addProperty = { r.property = ($0, $1, $2) }
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

    // MARK: Skip path: seven taps to Today

    func testSkipPathIsSevenTapsAndLandsOnTodayWithNothingAsked() async {
        let r = Recorder()
        let flow = makeFlow(recorder: r)
        var taps = 0
        flow.start(); taps += 1                       // Get started
        XCTAssertEqual(flow.step, .goal)
        flow.answerRental(.shortStays); taps += 1     // What do you rent out?
        flow.answerPro(.me); taps += 1                // Real estate as a main job? (750 is suggested and selected)
        XCTAssertEqual(flow.goal, .reps750)
        flow.confirmGoal(); taps += 1                 // Aim for 750 hours
        XCTAssertEqual(flow.step, .calendar)
        flow.calendarNotNow(); taps += 1              // Not now
        XCTAssertEqual(flow.step, .who)
        flow.confirmWho(); taps += 1                  // Continue (just me)
        XCTAssertEqual(flow.step, .property)
        flow.skipProperty(); taps += 1                // I’ll add it later
        XCTAssertEqual(taps, 7)
        XCTAssertEqual(r.completion, OnbCompletion(cohort: .new, openInbox: false, foundShown: false,
                                                   skippedProperty: true, calendar: .notNow))
        XCTAssertEqual(r.calendarPrompts, 0, "Not now never spends the system prompt")
        XCTAssertEqual(r.notifyPrompts, 0)
        XCTAssertEqual(r.backfillStarts, 0)
        XCTAssertEqual(r.calendarSuggestions, false)
        XCTAssertNil(r.property)
        XCTAssertEqual(r.who, .me)
        XCTAssertEqual(r.goal, .reps750)
        XCTAssertEqual(r.goalAnswers?.0, .shortStays)
        XCTAssertEqual(r.goalAnswers?.1, .me)
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
        XCTAssertEqual(BackfillJob.countableHours(items), 3, "Today's reveal counts the same hours")
    }

    func testHoursTextNeverRoundsUp() {
        XCTAssertEqual(OnbFormat.hours(23), "23h")
        XCTAssertEqual(OnbFormat.hours(22.99), "22.9h")
        XCTAssertEqual(OnbFormat.hours(0.25), "15m")
        XCTAssertEqual(OnbFormat.hours(1), "1h")
        XCTAssertEqual(OnbFormat.suggestions(1), "1 suggestion")
        XCTAssertEqual(OnbFormat.suggestions(14), "14 suggestions")
    }

    /// Probe: one 5-minute countable event must never render "0h found".
    func testFiveMinuteEventNeverRendersZeroHoursFound() {
        let now = Date(timeIntervalSince1970: 10_000)
        let found = OnbFound.from([suggestion("call", hours: 5.0 / 60)], now: now)
        XCTAssertEqual(found.hoursText, "5m")
        let headline = OnbStakedHeadline.make(calendar: .allowed, scan: .finished, found: found)
        XCTAssertEqual(headline, .found(found))
        if case .found(let f) = headline {
            XCTAssertEqual("\(f.hoursText) found", "5m found")
            XCTAssertNotEqual("\(f.hoursText) found", "0h found")
        }
        // Under a minute shows nothing countable rather than "0m found" / "0h found".
        let tiny = OnbFound(count: 1, hours: 0.5 / 60)
        XCTAssertFalse(tiny.hasDisplayableHours)
        XCTAssertEqual(OnbStakedHeadline.make(calendar: .allowed, scan: .finished, found: tiny), .nothingCountable(count: 1))
        // Every value from 0 to 2h in 30-second steps: "found" never reads zero.
        for halfMinutes in 0...240 {
            let f = OnbFound(count: 1, hours: Double(halfMinutes) / 120)
            if case .found(let shown) = OnbStakedHeadline.make(calendar: .allowed, scan: .finished, found: f) {
                XCTAssertFalse(["0h", "0m", "0.0h"].contains(shown.hoursText), "\(f.hours)h rendered \(shown.hoursText)")
            }
        }
    }

    func testStakedHeadlineStates() {
        let some = OnbFound(count: 14, hours: 23)
        XCTAssertEqual(OnbStakedHeadline.make(calendar: .allowed, scan: .finished, found: some), .found(some))
        XCTAssertEqual(OnbStakedHeadline.make(calendar: .allowed, scan: .finished, found: some).reviewCount, 14)
        XCTAssertEqual(OnbStakedHeadline.make(calendar: .allowed, scan: .finished, found: .none), .nothingFound)
        XCTAssertNil(OnbStakedHeadline.nothingFound.reviewCount, "0 found goes to Today, not an empty Inbox")
        // Found only non-countable work: never "0h found".
        let uncounted = OnbFound(count: 3, hours: 0)
        let headline = OnbStakedHeadline.make(calendar: .allowed, scan: .finished, found: uncounted)
        XCTAssertEqual(headline, .nothingCountable(count: 3))
        XCTAssertNotEqual(headline, .found(uncounted))
        XCTAssertEqual(OnbStakedHeadline.nothingCountableLine(3), "We found 3 things, but none count toward your hours yet.")
        XCTAssertEqual(OnbStakedHeadline.nothingCountableLine(1), "We found 1 thing, but none count toward your hours yet.")
        XCTAssertEqual(headline.reviewCount, 3, "They still wait in the Inbox to be answered")
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
        XCTAssertEqual(OnbGoal.mp100.callToAction, "Aim for 100 hours")
        XCTAssertEqual(OnbGoal.mp500.callToAction, "Aim for 500 hours")
        XCTAssertEqual(OnbGoal.reps750.callToAction, "Aim for 750 hours")
        XCTAssertEqual(OnbCopy.countLine(goal: .mp500), "0 of 500 hours")
        XCTAssertEqual(OnbCopy.countLine(goal: .record), "0 hours in the book")
    }

    func testSpouseNoteFollowsTheGoal() {
        XCTAssertTrue(OnbGoal.spouseNote(for: .reps750).contains("one of you has to get there alone"))
        XCTAssertTrue(OnbGoal.spouseNote(for: .mp100).contains("count together"))
        XCTAssertTrue(OnbGoal.spouseNote(for: .mp500).contains("count together for this target"))
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

// MARK: - Goal-first messaging (2.0): the goal step, the hero's words, per-rental counts

@MainActor
final class GoalFirstMessagingTests: XCTestCase {

    // MARK: The goal mapping, every branch

    func testSuggestionMappingEveryBranch() {
        let cases: [(RentalMix, RealEstatePro, OnbGoal, [OnbGoal])] = [
            (.shortStays, .nobody, .mp100, [.mp500, .reps750]),
            (.both,       .nobody, .mp100, [.mp500, .reps750]),
            (.longTerm,   .nobody, .mp500, [.mp100, .reps750]),
            (.shortStays, .me,     .reps750, [.mp500, .mp100]),
            (.longTerm,   .me,     .reps750, [.mp500, .mp100]),
            (.both,       .me,     .reps750, [.mp500, .mp100]),
            (.shortStays, .spouse, .reps750, [.mp500, .mp100]),
            (.longTerm,   .spouse, .reps750, [.mp500, .mp100]),
            (.both,       .spouse, .reps750, [.mp500, .mp100]),
        ]
        for (rental, pro, suggested, others) in cases {
            let s = OnbGoalSuggestion.make(rental: rental, pro: pro)
            XCTAssertEqual(s.suggested, suggested, "\(rental) / \(pro)")
            XCTAssertEqual(s.alternatives, others, "\(rental) / \(pro)")
            XCTAssertEqual(s.ordered.last, .record, "Just keep a record is always last")
            XCTAssertEqual(s.ordered.first, suggested, "The suggestion is first")
            XCTAssertEqual(Set(s.ordered), Set(OnbGoal.allCases), "Every target is offered once")
            XCTAssertEqual(s.ordered.count, 4)
        }
    }

    func testAnswersSuggestAndPreselectTheTarget() {
        var s = OnbServices()
        var saved: (RentalMix, RealEstatePro)?
        s.saveGoalAnswers = { saved = ($0, $1) }
        let flow = OnbFlow(cohort: .new, services: s, startAt: .goal)
        XCTAssertEqual(flow.goalPhase, .rental)
        XCTAssertNil(flow.suggestion)
        flow.answerRental(.both)
        XCTAssertEqual(flow.goalPhase, .pro)
        XCTAssertNil(flow.goal, "Nothing is selected until both questions are answered")
        flow.answerPro(.nobody)
        XCTAssertEqual(flow.goalPhase, .target)
        XCTAssertEqual(flow.goal, .mp100, "Short stays or both, and no real estate pro: 100 hours")
        flow.confirmGoal()
        XCTAssertEqual(saved?.0, .both)
        XCTAssertEqual(saved?.1, .nobody)
        XCTAssertEqual(flow.step, .calendar)
    }

    func testBackStepsThroughTheQuestionsBeforeLeavingTheGoalStep() {
        let flow = OnbFlow(cohort: .new, services: OnbServices(), startAt: .goal)
        flow.answerRental(.longTerm)
        flow.answerPro(.nobody)
        XCTAssertEqual(flow.goal, .mp500, "Long-term and no pro: 500 hours")
        flow.back()
        XCTAssertEqual(flow.goalPhase, .pro)
        XCTAssertEqual(flow.step, .goal)
        flow.back()
        XCTAssertEqual(flow.goalPhase, .rental)
        XCTAssertEqual(flow.step, .goal)
        flow.back()
        XCTAssertEqual(flow.step, .welcome)
    }

    func testSpousePathStartsWhoPutsInTheHoursOnBoth() {
        let flow = OnbFlow(cohort: .new, services: OnbServices(), startAt: .goal)
        flow.answerRental(.shortStays)
        flow.answerPro(.spouse)
        XCTAssertEqual(flow.who, .both)
        flow.answerPro(.me)
        XCTAssertEqual(flow.who, .me)
    }

    func testFirstPropertyKindFollowsWhatTheOwnerRents() {
        let flow = OnbFlow(cohort: .new, services: OnbServices(), startAt: .property)
        flow.rental = .shortStays
        XCTAssertEqual(flow.firstPropertyType, .str)
        flow.rental = .longTerm
        XCTAssertEqual(flow.firstPropertyType, .ltr)
        flow.rental = .both
        XCTAssertEqual(flow.firstPropertyType, .str, "Both: short stay unless they say otherwise")
        flow.firstPropertyIsShortStay = false
        XCTAssertEqual(flow.firstPropertyType, .ltr)
        var saved: PropertyType?
        var s = OnbServices()
        s.addProperty = { _, _, type in saved = type }
        let again = OnbFlow(cohort: .new, services: s, startAt: .property)
        again.rental = .shortStays
        again.name = "Tahoe cabin"
        XCTAssertTrue(again.saveProperty())
        XCTAssertEqual(saved, .str)
    }

    func testCardWordsSayWhatThe750CountsAndNeverClaimFrequency() {
        for pro in [RealEstatePro.me, .spouse, .nobody] {
            XCTAssertTrue(OnbGoalCopy.detail(.reps750, pro: pro, isSuggested: false, rental: .both)
                .contains("Counts the rental hours you log here. Other real-estate work isn’t tracked yet"), "\(pro)")
        }
        XCTAssertEqual(OnbGoalCopy.title(.reps750, pro: .spouse), "750 hours, your spouse’s own count")
        XCTAssertEqual(OnbGoalCopy.title(.mp100, pro: .nobody), "100 hours, and more than anyone else")
        let banned = ["most common", "usually", "most owners", "qualify", "household"]
        for goal in OnbGoal.allCases {
            for pro in [RealEstatePro.me, .spouse, .nobody] {
                for suggested in [true, false] {
                    let text = (OnbGoalCopy.title(goal, pro: pro) + OnbGoalCopy.detail(goal, pro: pro, isSuggested: suggested, rental: .both)).lowercased()
                    for word in banned { XCTAssertFalse(text.contains(word), "\(goal) \(word)") }
                }
            }
        }
    }

    // MARK: Onboarding lines with real numbers

    func testFoundAndSetUpHeadlines() {
        XCTAssertEqual(OnbCopy.foundHeadline(OnbFound(count: 14, hours: 23)), "23 hours found. 0 counted.")
        XCTAssertEqual(OnbCopy.foundHeadline(OnbFound(count: 2, hours: 23.57)), "23.5 hours found. 0 counted.", "Never rounds up")
        XCTAssertEqual(OnbCopy.foundHeadline(OnbFound(count: 1, hours: 1)), "1 hour found. 0 counted.")
        XCTAssertEqual(OnbCopy.foundHeadline(OnbFound(count: 1, hours: 0.75)), "45 minutes found. 0 counted.")
        XCTAssertEqual(OnbCopy.foundBody(count: 14, goal: .mp100),
                       "From 14 calendar events in the last 90 days. Confirm the rental ones and they count toward your 100 hours.")
        XCTAssertTrue(OnbCopy.foundBody(count: 1, goal: .mp500).hasPrefix("From 1 calendar event "))
        XCTAssertTrue(OnbCopy.foundBody(count: 3, goal: .record).hasSuffix("go in your record."))
        XCTAssertEqual(OnbCopy.setUpHeadline(goal: .mp100), "You’re set up for 100 hours.")
        XCTAssertEqual(OnbCopy.setUpHeadline(goal: .reps750), "You’re set up for 750 hours.")
        XCTAssertEqual(OnbCopy.setUpHeadline(goal: .record), "You’re set up to keep a record.")
    }

    func testUpgraderHeadlineUsesTheirRealHoursAndTarget() {
        XCTAssertEqual(OnbCopy.upgradeHeadline(hours: 312.9, goal: .reps750, isRecord: false), "Your 312 hours, on the way to 750.")
        XCTAssertEqual(OnbCopy.upgradeHeadline(hours: 87, goal: .mp100, isRecord: false), "Your 87 hours, on the way to 100.")
        XCTAssertEqual(OnbCopy.upgradeHeadline(hours: 0, goal: .mp500, isRecord: false), "Your hours, on the way to 500.")
        XCTAssertEqual(OnbCopy.upgradeHeadline(hours: 312, goal: .reps750, isRecord: true), "Your 312 hours, safe in your record.")
    }

    func testWelcomeAndGoalCopyAreFreeOfClaims() {
        let lines = [OnbCopy.upgradeBody(isRecord: false), OnbCopy.upgradeBody(isRecord: true), OnbCopy.upgradeRepsNote,
                     OnbCopy.setUpBody(goal: .mp100), OnbCopy.setUpBody(goal: .record)]
        for line in lines {
            let l = line.lowercased()
            for word in ["qualif", "save on tax", "audit-proof", "write off", "deduct", "loophole"] { XCTAssertFalse(l.contains(word), line) }
        }
        XCTAssertTrue(OnbCopy.upgradeRepsNote.contains("rental hours you log here"))
    }

    // MARK: The answers are stored next to the goal

    func testGoalSetupAnswersRoundTripAndTheSpouseProFollowsTheSpousesCount() {
        let manager = GoalManager.shared
        let (rental, pro) = (manager.rentalMix, manager.realEstatePro)
        defer { manager.setGoalSetup(rental: rental, pro: pro) }
        manager.setGoalSetup(rental: .both, pro: .spouse)
        XCTAssertEqual(manager.rentalMix, .both)
        XCTAssertEqual(manager.realEstatePro, .spouse)
        XCTAssertEqual(manager.repsParticipant, .spouse)
        manager.setGoalSetup(rental: .longTerm, pro: .me)
        XCTAssertEqual(manager.repsParticipant, .selfParticipant)
        manager.setGoalSetup(rental: nil, pro: nil)
        XCTAssertNil(manager.rentalMix)
        XCTAssertEqual(manager.repsParticipant, .selfParticipant, "1.x and upgraders count their own hours")
    }

    // MARK: Today hero words

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private var oct21: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))! }

    private func copy(_ goal: HouseGoal, hours: Double, record: Bool = false, participant: Participant = .selfParticipant,
                      half: TaxQualificationEngine.MoreThanHalfStatus = .notEntered, noOneMore: Bool? = nil,
                      property: String? = nil, days: Int = 60, pending: Bool = false) -> TodayHeroCopy {
        TodayHeroCopy.make(.init(goal: goal, isRecord: record, hours: hours, year: 2026, now: oct21, calendar: cal,
                                 repsParticipant: participant, halfTest: half, noOneParticipatedMore: noOneMore,
                                 propertyName: property, daysOfData: days, hasPendingToConfirm: pending))
    }

    func testHeroOnPace() {
        let c = copy(.mp500, hours: 420)
        XCTAssertEqual(c.eyebrow, "2026 · 500-hour target")
        XCTAssertNil(c.qualifier)
        XCTAssertEqual(c.caption, "of 500 hours")
        XCTAssertEqual(c.spoken, "of 500 hours · on pace for Dec 31")
        XCTAssertEqual(c.status, "On pace for Dec 31")
        XCTAssertEqual(c.tone, .positive)
    }

    func testHeroBehindSaysTheHoursAWeekHonestly() {
        // 71 days left = 10.14 weeks. 288h to go is 28.4 a week: rounds up, never down.
        let c = copy(.mp500, hours: 212)
        XCTAssertEqual(c.spoken, "of 500 hours · 29h a week to finish by Dec 31")
        XCTAssertEqual(c.tone, .caution)
        XCTAssertEqual(copy(.mp100, hours: 20).spoken, "of 100 hours · 8h a week to finish by Dec 31")
        // 60 days in with no hours: behind, and honest about it.
        XCTAssertEqual(copy(.mp100, hours: 0).phrase, "10h a week to finish by Dec 31")
    }

    func testHeroMetStates() {
        XCTAssertEqual(copy(.mp500, hours: 501).spoken, "of 500 hours · reached, based on your records")
        XCTAssertEqual(copy(.mp500, hours: 501).tone, .positive)
    }

    func testHeroNeverCallsExactlyTheTargetReached() {
        // The tests are "more than": exactly 500 is not met.
        let c = copy(.mp500, hours: 500)
        XCTAssertFalse(c.phrase?.contains("reached") ?? false)
        XCTAssertEqual(c.phrase, "on pace for Dec 31")
    }

    func testHero100HourTestIsNeverReachedUntilNoOneDidMoreIsConfirmed() {
        let unconfirmed = copy(.mp100, hours: 104, noOneMore: nil)
        XCTAssertEqual(unconfirmed.eyebrow, "2026 · 100-hour target")
        XCTAssertEqual(unconfirmed.qualifier, "more than anyone else")
        XCTAssertEqual(unconfirmed.spoken, "of 100 hours · confirm no one did more")
        XCTAssertTrue(unconfirmed.needsConfirmation, "The hero opens the existing question")
        XCTAssertEqual(unconfirmed.tone, .caution)
        XCTAssertFalse(unconfirmed.phrase?.contains("reached") ?? true)
        XCTAssertFalse(unconfirmed.claimsReached)
        let progress = HouseProgress(hours: 104, goal: .mp100)
        XCTAssertFalse(progress.accessibilityLabel(claimsGoalReached: unconfirmed.claimsReached).contains("Goal hours reached"),
                       "VoiceOver never says reached before the question is answered")
        XCTAssertTrue(progress.accessibilityLabel.contains("Goal hours reached"))

        let confirmed = copy(.mp100, hours: 104, noOneMore: true)
        XCTAssertFalse(confirmed.needsConfirmation)
        XCTAssertTrue(confirmed.claimsReached)
        XCTAssertEqual(confirmed.tone, .positive)
        XCTAssertTrue(confirmed.phrase?.contains("no one did more") ?? false)

        let someone = copy(.mp100, hours: 104, noOneMore: false)
        XCTAssertEqual(someone.tone, .caution)
        XCTAssertFalse(someone.needsConfirmation)
        XCTAssertTrue(someone.phrase?.contains("someone else did more") ?? false)

        XCTAssertFalse(copy(.mp100, hours: 60, noOneMore: nil).needsConfirmation, "Under 100 hours there is nothing to confirm yet")
    }

    func testHeroREPSSaysWhoseCountAndKeepsTheHalfTestVisible() {
        let mine = copy(.reps750, hours: 300)
        XCTAssertEqual(mine.eyebrow, "2026 · 750-hour target")
        XCTAssertEqual(mine.qualifier, "your own count")
        XCTAssertEqual(copy(.reps750, hours: 300, participant: .spouse).qualifier, "spouse’s own count")
        let open = copy(.reps750, hours: 760, half: .notEntered)
        XCTAssertEqual(open.tone, .caution)
        XCTAssertFalse(open.claimsReached, "750 hours alone is not the whole test")
        XCTAssertEqual(open.phrase, "750 reached. Add your other work hours to check the half rule.")
        XCTAssertEqual(copy(.reps750, hours: 760, half: .notMet).phrase, "750 reached. The half rule isn’t met yet.")
        let met = copy(.reps750, hours: 760, half: .met)
        XCTAssertEqual(met.tone, .positive)
        XCTAssertTrue(met.claimsReached)
        XCTAssertEqual(met.phrase, "reached, based on your records")
    }

    func testHeroRecordOnlyShowsHoursLoggedAndNoPace() {
        let c = copy(.reps750, hours: 212, record: true)
        XCTAssertEqual(c.eyebrow, "2026 · Your record")
        XCTAssertEqual(c.caption, "hours logged in 2026")
        XCTAssertNil(c.phrase)
        XCTAssertNil(c.qualifier)
    }

    // MARK: Day one: no pace until there is something to pace

    func testPaceWaitsForTwoWeeksOrTenHours() {
        // One hour on day one: never "74h a week".
        let dayOne = copy(.reps750, hours: 1, days: 0, pending: true)
        XCTAssertEqual(dayOne.phrase, "Confirm your found hours to see your pace.")
        XCTAssertEqual(dayOne.tone, .neutral)
        XCTAssertFalse(dayOne.spoken.contains("a week"))
        XCTAssertEqual(copy(.reps750, hours: 1, days: 0, pending: false).phrase, "Log a few weeks to see your pace.")
        XCTAssertEqual(copy(.reps750, hours: 0, days: 0, pending: false).phrase, "Log a few weeks to see your pace.")
        // Ten confirmed hours is enough, even on day one; so is a 14th day with fewer hours.
        XCTAssertTrue(copy(.reps750, hours: 10, days: 0).phrase?.contains("a week to finish by Dec 31") ?? false)
        XCTAssertTrue(copy(.reps750, hours: 3, days: 14).phrase?.contains("a week to finish by Dec 31") ?? false)
        XCTAssertEqual(copy(.reps750, hours: 9.9, days: 13).phrase, "Log a few weeks to see your pace.")
        XCTAssertTrue(TodayHeroCopy.paceIsReady(hours: 0, daysOfData: 14))
        XCTAssertFalse(TodayHeroCopy.paceIsReady(hours: 9.99, daysOfData: 13))
        // A reached target never waits on the pace.
        XCTAssertEqual(copy(.mp500, hours: 501, days: 0).phrase, "reached, based on your records")
        // The finish card waits too.
        let card = TodayPaceCards.finish(hours: 1, goal: .reps750, pace: TodayPace(text: "x", tone: .neutral), now: oct21, calendar: cal, paceReady: false)
        XCTAssertEqual(card.value, "Not yet")
        XCTAssertEqual(TodayPaceCards.finish(hours: 100, goal: .reps750, pace: TodayPace(text: "x", tone: .neutral), now: oct21, calendar: cal).value, "65h a week")
    }

    func testHeaderLineDropsTheDotZeroAndHasNoTargetForARecord() {
        XCTAssertEqual(TodayHeroCopy.headerLine(hours: 212, target: 750, isRecord: false, year: 2026), "212h toward 750 this year.")
        XCTAssertEqual(TodayHeroCopy.headerLine(hours: 212.5, target: 100, isRecord: false, year: 2026), "212.5h toward 100 this year.")
        XCTAssertEqual(TodayHeroCopy.headerLine(hours: 212, target: 750, isRecord: true, year: 2026), "212 hours logged in 2026.")
        XCTAssertFalse(TodayHeroCopy.headerLine(hours: 212, target: 750, isRecord: true, year: 2026).contains("750"), "A record has no target")
    }

    func testEyebrowNamesTheRentalWhenTheCountIsOneRentals() {
        let c = copy(.mp100, hours: 86, property: "Tahoe cabin")
        XCTAssertEqual(c.eyebrow, "2026 · Tahoe cabin · 100-hour target")
        XCTAssertEqual(c.propertyName, "Tahoe cabin")
        XCTAssertEqual(c.eyebrowTarget, "100-hour target")
        XCTAssertEqual(copy(.mp500, hours: 86).eyebrow, "2026 · 500-hour target")
        XCTAssertNil(copy(.mp500, hours: 86, property: "   ").propertyName, "A blank name is no name")
    }

    func testEmptyLotLineUsesThePersonsOwnTarget() {
        XCTAssertEqual(TodayHeroCopy.emptyLotLine(target: 750), "Add a rental. Hours you confirm count toward your 750.")
        XCTAssertEqual(TodayHeroCopy.emptyLotLine(target: 100), "Add a rental. Hours you confirm count toward your 100.")
        XCTAssertEqual(TodayHeroCopy.emptyLotLine(target: nil), "Add a rental. Hours you confirm count toward your goal.")
        XCTAssertEqual(copy(.mp500, hours: 0, days: 0).targetHours, 500)
        XCTAssertNil(copy(.reps750, hours: 0, record: true).targetHours)
    }

    func testHeroYearIsNeverGrouped() {
        XCTAssertFalse(copy(.mp500, hours: 10).eyebrow.contains("2,026"))
    }

    // MARK: Per-rental counts (the 100 and 500 hour tests are per rental)

    private func entry(_ property: RentalProperty, hours: Double, participant: Participant = .selfParticipant) -> TimeEntry {
        TimeEntry(propertyId: property.id, participant: participant, category: .repairs, hours: hours,
                  date: cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 12))!)
    }

    func testBothKindsOfRentalShowTheShortStaysOwnCount() {
        let cabin = RentalProperty(name: "Tahoe cabin", address: "", propertyType: .str)
        let duplex = RentalProperty(name: "Oak Street duplex", address: "", propertyType: .ltr)
        let entries = [entry(cabin, hours: 40), entry(duplex, hours: 300)]
        let overview = TaxQualificationEngine.materialParticipationOverview(
            entries: entries, properties: [duplex, cabin], year: 2026, groupingElection: false)
        XCTAssertEqual(overview.ownerAndSpouseHours, 40, "The long-term rental's 300 hours never stand in for the cabin")
        XCTAssertEqual(overview.propertyId, cabin.id)
    }

    func testOnlyOneKindKeepsTheBestPropertyAndGroupingKeepsTheTotal() {
        let a = RentalProperty(name: "A", address: "", propertyType: .ltr)
        let b = RentalProperty(name: "B", address: "", propertyType: .ltr)
        let entries = [entry(a, hours: 40), entry(b, hours: 90)]
        XCTAssertEqual(TaxQualificationEngine.materialParticipationOverview(
            entries: entries, properties: [a, b], year: 2026, groupingElection: false).ownerAndSpouseHours, 90)
        let cabin = RentalProperty(name: "Cabin", address: "", propertyType: .str)
        let mixed = entries + [entry(cabin, hours: 10)]
        XCTAssertEqual(TaxQualificationEngine.materialParticipationOverview(
            entries: mixed, properties: [a, b, cabin], year: 2026, groupingElection: true).ownerAndSpouseHours, 140,
                       "A grouping election counts all rentals as one activity")
    }

    func testTwoShortStaysUseTheBestOne() {
        let a = RentalProperty(name: "A", address: "", propertyType: .str)
        let b = RentalProperty(name: "B", address: "", propertyType: .str)
        let duplex = RentalProperty(name: "D", address: "", propertyType: .ltr)
        let o = TaxQualificationEngine.materialParticipationOverview(
            entries: [entry(a, hours: 30), entry(b, hours: 55), entry(duplex, hours: 400)],
            properties: [a, b, duplex], year: 2026, groupingElection: false)
        XCTAssertEqual(o.ownerAndSpouseHours, 55)
    }

    // MARK: The 750 follows the real estate professional's own hours

    func testWeekStripFollowsTheSpouseWhenTheSpouseIsThePro() {
        let p = RentalProperty(name: "A", address: "", propertyType: .ltr)
        let mine = entry(p, hours: 3), hers = entry(p, hours: 5, participant: .spouse)
        XCTAssertTrue(TodayWeek.counts(mine, goal: .reps750, includeSpouse: true))
        XCTAssertFalse(TodayWeek.counts(hers, goal: .reps750, includeSpouse: true), "Spouse hours never join your 750")
        XCTAssertTrue(TodayWeek.counts(hers, goal: .reps750, includeSpouse: true, repsParticipant: .spouse))
        XCTAssertFalse(TodayWeek.counts(mine, goal: .reps750, includeSpouse: true, repsParticipant: .spouse))
        XCTAssertTrue(TodayWeek.counts(hers, goal: .mp500, includeSpouse: true), "Material participation combines spouses")
        XCTAssertFalse(TodayWeek.counts(hers, goal: .mp500, includeSpouse: false))
    }
}
