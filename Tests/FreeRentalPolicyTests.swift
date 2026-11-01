import XCTest
@testable import LandlordHours

/// The free rental: everyone keeps one rental free forever, picks which one, and can switch it
/// once a month. Other rentals are view-only on the free plan; their hours stay counted.
final class FreeRentalPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)
    private let day: TimeInterval = 86_400
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    private let pine = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let oak = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    private let lake = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!

    private var rentals: [RentalUsage] {
        [RentalUsage(id: pine, hours: 120, createdAt: now.addingTimeInterval(-300 * day)),
         RentalUsage(id: oak, hours: 46, createdAt: now.addingTimeInterval(-200 * day)),
         RentalUsage(id: lake, hours: 12, createdAt: now.addingTimeInterval(-100 * day))]
    }

    private var trialPlan: Plan {
        .trial(.init(startedAt: now, expiresAt: now.addingTimeInterval(14 * day), willAutoRenew: true,
                     inGracePeriod: false, originalTransactionID: 1))
    }

    private func picked(_ id: UUID, at date: Date) -> FreeRentalSelection {
        FreeRentalSelection(rentalID: id, chosenAt: date, source: .picked)
    }

    // MARK: Which rental is free

    func testNoRentalsHasNoFreeRental() {
        XCTAssertNil(FreeRentalPolicy.freeRentalID(selection: nil, rentals: []))
    }

    func testOneRentalIsFreeWithoutAPick() {
        let one = [rentals[1]]
        XCTAssertEqual(FreeRentalPolicy.freeRentalID(selection: nil, rentals: one), oak)
        XCTAssertFalse(FreeRentalPolicy.needsPick(plan: .free, selection: nil, rentals: one))
    }

    func testDefaultIsTheMostUsedRental() {
        XCTAssertEqual(FreeRentalPolicy.freeRentalID(selection: nil, rentals: rentals), pine)
    }

    func testDefaultTieBreaksOnTheOldestThenTheID() {
        let a = RentalUsage(id: oak, hours: 10, createdAt: now.addingTimeInterval(-10 * day))
        let b = RentalUsage(id: lake, hours: 10, createdAt: now.addingTimeInterval(-20 * day))
        XCTAssertEqual(FreeRentalPolicy.freeRentalID(selection: nil, rentals: [a, b]), lake)
        let c = RentalUsage(id: pine, hours: 10, createdAt: a.createdAt)
        XCTAssertEqual(FreeRentalPolicy.freeRentalID(selection: nil, rentals: [a, c]), pine) // same day: lower id
    }

    func testNonFiniteHoursDoNotWinTheDefault() {
        let bad = RentalUsage(id: lake, hours: .nan, createdAt: now)
        let ok = RentalUsage(id: oak, hours: 1, createdAt: now)
        XCTAssertEqual(FreeRentalPolicy.freeRentalID(selection: nil, rentals: [bad, ok]), oak)
    }

    func testAPickWins() {
        XCTAssertEqual(FreeRentalPolicy.freeRentalID(selection: picked(lake, at: now), rentals: rentals), lake)
    }

    func testADeletedPickFallsBackToTheDefault() {
        let gone = UUID()
        XCTAssertEqual(FreeRentalPolicy.freeRentalID(selection: picked(gone, at: now), rentals: rentals), pine)
    }

    // MARK: Access

    func testProSeesEveryRentalInFull() {
        for r in rentals {
            XCTAssertEqual(FreeRentalPolicy.access(for: r.id, plan: trialPlan, selection: nil, rentals: rentals), .full)
            XCTAssertEqual(FreeRentalPolicy.access(for: r.id, plan: .founding(alsoSubscribed: false), selection: nil, rentals: rentals), .full)
        }
    }

    func testFreeKeepsOneInFullAndTheRestViewOnly() {
        let sel = picked(oak, at: now)
        XCTAssertEqual(FreeRentalPolicy.access(for: oak, plan: .free, selection: sel, rentals: rentals), .full)
        XCTAssertEqual(FreeRentalPolicy.access(for: pine, plan: .free, selection: sel, rentals: rentals), .viewOnly)
        XCTAssertEqual(FreeRentalPolicy.access(for: lake, plan: .free, selection: sel, rentals: rentals), .viewOnly)
        XCTAssertTrue(FreeRentalPolicy.canLog(at: oak, plan: .free, selection: sel, rentals: rentals))
        XCTAssertFalse(FreeRentalPolicy.canLog(at: pine, plan: .free, selection: sel, rentals: rentals))
    }

    func testViewOnlyHoursStayCounted() {
        // The plan never removes hours from a total: every rental counts, whatever its access.
        let sel = picked(oak, at: now)
        XCTAssertEqual(Set(FreeRentalPolicy.countedRentalIDs(plan: .free, selection: sel, rentals: rentals)),
                       Set(rentals.map(\.id)))
    }

    func testUnknownRentalIsViewOnlyOnFree() {
        XCTAssertEqual(FreeRentalPolicy.access(for: UUID(), plan: .free, selection: nil, rentals: rentals), .viewOnly)
    }

    func testAddingRentals() {
        XCTAssertTrue(FreeRentalPolicy.canAddRental(plan: .free, rentalCount: 0), "the first rental is free")
        XCTAssertFalse(FreeRentalPolicy.canAddRental(plan: .free, rentalCount: 1))
        XCTAssertFalse(FreeRentalPolicy.canAddRental(plan: .free, rentalCount: 3))
        XCTAssertTrue(FreeRentalPolicy.canAddRental(plan: trialPlan, rentalCount: 3))
        XCTAssertTrue(FreeRentalPolicy.canAddRental(plan: .free, rentalCount: -1), "a bad count never blocks the first rental")
    }

    // MARK: The pick sheet

    func testLapsedTrialWithSeveralRentalsNeedsAPick() {
        XCTAssertTrue(FreeRentalPolicy.needsPick(plan: .free, selection: nil, rentals: rentals))
        XCTAssertFalse(FreeRentalPolicy.needsPick(plan: trialPlan, selection: nil, rentals: rentals))
        XCTAssertFalse(FreeRentalPolicy.needsPick(plan: .free, selection: picked(oak, at: now), rentals: rentals))
    }

    func testSwipeDownKeepsTheMostUsedAndStopsAsking() {
        let kept = FreeRentalPolicy.keepDefault(rentals: rentals, now: now)
        XCTAssertEqual(kept?.rentalID, pine)
        XCTAssertEqual(kept?.source, .defaulted)
        XCTAssertFalse(FreeRentalPolicy.needsPick(plan: .free, selection: kept, rentals: rentals))
        XCTAssertNil(FreeRentalPolicy.keepDefault(rentals: [], now: now))
    }

    func testADeletedPickAsksAgain() {
        XCTAssertTrue(FreeRentalPolicy.needsPick(plan: .free, selection: picked(UUID(), at: now), rentals: rentals))
    }

    // MARK: Switching once a month

    func testFirstPickIsAlwaysAllowed() {
        XCTAssertEqual(FreeRentalPolicy.canSwitch(selection: nil, to: lake, rentals: rentals, now: now, calendar: calendar), .allowed)
        let kept = FreeRentalSelection(rentalID: pine, chosenAt: now, source: .defaulted)
        XCTAssertEqual(FreeRentalPolicy.canSwitch(selection: kept, to: lake, rentals: rentals, now: now, calendar: calendar), .allowed,
                       "a swipe-down default isn't the user's pick, so it doesn't start the month")
    }

    func testSwitchInsideTheMonthIsTooSoon() {
        let chosen = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 9))!
        let sel = picked(oak, at: chosen)
        let at = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))!
        let next = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9))!
        XCTAssertEqual(FreeRentalPolicy.canSwitch(selection: sel, to: lake, rentals: rentals, now: at, calendar: calendar), .tooSoon(next: next))
        XCTAssertEqual(FreeRentalPolicy.nextSwitchDate(selection: sel, calendar: calendar), next)
    }

    func testSwitchAtTheMonthBoundaryIsAllowed() {
        let chosen = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 9))!
        let sel = picked(oak, at: chosen)
        let boundary = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9))!
        XCTAssertEqual(FreeRentalPolicy.canSwitch(selection: sel, to: lake, rentals: rentals, now: boundary, calendar: calendar), .allowed)
        XCTAssertEqual(FreeRentalPolicy.canSwitch(selection: sel, to: lake, rentals: rentals, now: boundary.addingTimeInterval(-1), calendar: calendar),
                       .tooSoon(next: boundary))
    }

    func testMonthEndClampsToTheShortMonth() {
        let jan31 = calendar.date(from: DateComponents(year: 2027, month: 1, day: 31, hour: 12))!
        let feb28 = calendar.date(from: DateComponents(year: 2027, month: 2, day: 28, hour: 12))!
        XCTAssertEqual(FreeRentalPolicy.nextSwitchDate(selection: picked(oak, at: jan31), calendar: calendar), feb28)
    }

    func testSwitchToTheSameRentalIsANoOp() {
        XCTAssertEqual(FreeRentalPolicy.canSwitch(selection: picked(oak, at: now), to: oak, rentals: rentals, now: now, calendar: calendar), .sameRental)
    }

    func testSwitchToAnUnknownRentalIsRefused() {
        XCTAssertEqual(FreeRentalPolicy.canSwitch(selection: nil, to: UUID(), rentals: rentals, now: now, calendar: calendar), .unknownRental)
    }

    func testDeletedFreeRentalDoesNotLockTheUserOut() {
        let sel = picked(UUID(), at: now.addingTimeInterval(-day))
        XCTAssertEqual(FreeRentalPolicy.canSwitch(selection: sel, to: lake, rentals: rentals, now: now, calendar: calendar), .allowed)
    }

    func testAPickDatedInTheFutureIsTreatedAsClockSkew() {
        // A clock set a year ahead when picking must not lock the switch for a year.
        let sel = picked(oak, at: now.addingTimeInterval(365 * day))
        XCTAssertEqual(FreeRentalPolicy.canSwitch(selection: sel, to: lake, rentals: rentals, now: now, calendar: calendar), .allowed)
    }

    func testAPickWithinADayAheadStillCounts() {
        let sel = picked(oak, at: now.addingTimeInterval(3600))
        guard case .tooSoon = FreeRentalPolicy.canSwitch(selection: sel, to: lake, rentals: rentals, now: now, calendar: calendar) else {
            return XCTFail("a small clock difference is not skew")
        }
    }

    func testSwitchRecordsANewPick() {
        let new = FreeRentalPolicy.switched(to: lake, now: now)
        XCTAssertEqual(new, FreeRentalSelection(rentalID: lake, chosenAt: now, source: .picked))
    }
}

/// The 14-day trial's dates, the day-12 reminder and the paywall's offer.
final class TrialScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)
    private let day: TimeInterval = 86_400
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    private func trial(start: Date, renew: Bool = true, original: UInt64 = 7) -> Plan {
        .trial(.init(startedAt: start, expiresAt: start.addingTimeInterval(14 * day), willAutoRenew: renew,
                     inGracePeriod: false, originalTransactionID: original))
    }

    func testPreviewTimelineIsTodayDay12Day14() {
        let s = TrialSchedule.preview(from: now, calendar: calendar)
        XCTAssertEqual(s.start, now)
        XCTAssertEqual(s.reminder, calendar.date(byAdding: .day, value: 12, to: now))
        XCTAssertEqual(s.renewal, calendar.date(byAdding: .day, value: 14, to: now))
    }

    func testPreviewFollowsTheProductsTrialLength() {
        let s = TrialSchedule.preview(from: now, trialDays: 7, calendar: calendar)
        XCTAssertEqual(s.renewal, calendar.date(byAdding: .day, value: 7, to: now))
        XCTAssertEqual(s.reminder, calendar.date(byAdding: .day, value: 5, to: now))
    }

    func testCurrentScheduleComesFromTheTrial() {
        let start = now.addingTimeInterval(-day)
        let s = TrialSchedule.current(trial(start: start), calendar: calendar)
        XCTAssertEqual(s?.renewal, start.addingTimeInterval(14 * day))
        XCTAssertEqual(s?.reminder, calendar.date(byAdding: .day, value: -2, to: start.addingTimeInterval(14 * day)))
        XCTAssertNil(TrialSchedule.current(.free, calendar: calendar))
        XCTAssertNil(TrialSchedule.current(.founding(alsoSubscribed: false), calendar: calendar))
    }

    func testDay12ReminderShowsOnDay12Once() {
        let start = now.addingTimeInterval(-12 * day)
        XCTAssertTrue(TrialSchedule.shouldShowDay12Reminder(plan: trial(start: start), now: now, shown: [], calendar: calendar))
        XCTAssertFalse(TrialSchedule.shouldShowDay12Reminder(plan: trial(start: start), now: now, shown: [7], calendar: calendar))
    }

    func testDay12ReminderNotBeforeDay12() {
        let start = now.addingTimeInterval(-11 * day)
        XCTAssertFalse(TrialSchedule.shouldShowDay12Reminder(plan: trial(start: start), now: now, shown: [], calendar: calendar))
    }

    func testNoReminderOnceTheTrialEnded() {
        let start = now.addingTimeInterval(-14 * day)
        XCTAssertFalse(TrialSchedule.shouldShowDay12Reminder(plan: trial(start: start), now: now, shown: [], calendar: calendar))
    }

    func testNoKeepProReminderAfterTheUserCancelled() {
        let start = now.addingTimeInterval(-12 * day)
        XCTAssertFalse(TrialSchedule.shouldShowDay12Reminder(plan: trial(start: start, renew: false), now: now, shown: [], calendar: calendar))
    }

    func testNoReminderForPaidFreeOrFounding() {
        let sub = Plan.Subscription(startedAt: now.addingTimeInterval(-12 * day), expiresAt: now.addingTimeInterval(2 * day),
                                    willAutoRenew: true, inGracePeriod: false, originalTransactionID: 1)
        XCTAssertFalse(TrialSchedule.shouldShowDay12Reminder(plan: .pro(sub), now: now, shown: [], calendar: calendar))
        XCTAssertFalse(TrialSchedule.shouldShowDay12Reminder(plan: .free, now: now, shown: [], calendar: calendar))
        XCTAssertFalse(TrialSchedule.shouldShowDay12Reminder(plan: .founding(alsoSubscribed: false), now: now, shown: [], calendar: calendar))
    }

    func testPaywallOffer() {
        XCTAssertEqual(PaywallOffer.resolve(plan: .free, eligibleForIntroOffer: true, introTrialDays: 14), .freeTrial(days: 14))
        XCTAssertEqual(PaywallOffer.resolve(plan: .free, eligibleForIntroOffer: false, introTrialDays: 14), .subscribe,
                       "a lapsed trial can't start a second one")
        XCTAssertEqual(PaywallOffer.resolve(plan: .free, eligibleForIntroOffer: true, introTrialDays: nil), .subscribe)
        XCTAssertEqual(PaywallOffer.resolve(plan: trial(start: now), eligibleForIntroOffer: false, introTrialDays: 14), .owned)
        XCTAssertEqual(PaywallOffer.resolve(plan: .founding(alsoSubscribed: false), eligibleForIntroOffer: true, introTrialDays: 14), .owned)
    }
}
