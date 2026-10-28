import XCTest
@testable import LandlordHours

// MARK: - Today, below the house (redesign-specs §2): rules

@MainActor
final class TodayConfirmLogicTests: CaptureTestCase {
    private func s(_ key: String, confidence: Double = 0.9, flagged: Bool = false, start: Date? = nil,
                   detectedAt: Date? = nil) -> Suggestion {
        let start = start ?? date(2026, 10, 14, 9)
        return Suggestion(sourceKey: "cal:\(key)", kind: .calendar, detectedAt: detectedAt ?? start, start: start,
                          end: start.addingTimeInterval(3600), title: key, containerId: "CAL",
                          proposedPropertyId: UUID(), proposedCategory: .repairs, proposedHours: 1,
                          hoursBasis: .scheduled, confidence: confidence, mightAlreadyBeLogged: flagged)
    }

    func testStateHiddenWithoutAProperty() {
        XCTAssertEqual(TodayConfirm.state(hasProperties: false, pendingCount: 4, backfillScanning: true, captureOn: true), .hidden)
    }

    func testRowsWheneverAnythingIsPendingEvenWhileScanning() {
        XCTAssertEqual(TodayConfirm.state(hasProperties: true, pendingCount: 1, backfillScanning: false, captureOn: true), .rows)
        XCTAssertEqual(TodayConfirm.state(hasProperties: true, pendingCount: 3, backfillScanning: true, captureOn: true), .rows)
    }

    func testLoadingOnlyWhileScanningWithNothingFoundYet() {
        XCTAssertEqual(TodayConfirm.state(hasProperties: true, pendingCount: 0, backfillScanning: true, captureOn: true), .loading)
    }

    func testCaughtUpSaysWhetherSuggestionsAreOn() {
        XCTAssertEqual(TodayConfirm.state(hasProperties: true, pendingCount: 0, backfillScanning: false, captureOn: true),
                       .caughtUp(captureOn: true))
        XCTAssertEqual(TodayConfirm.state(hasProperties: true, pendingCount: 0, backfillScanning: false, captureOn: false),
                       .caughtUp(captureOn: false))
    }

    func testCountIsEveryVisibleItemAndRowsAreTheTopTwoMostLikely() {
        let items = [s("low", confidence: 0.4), s("top", confidence: 0.97), s("flag", confidence: 0.9, flagged: true),
                     s("mid", confidence: 0.9), s("ok", confidence: 0.8)]
        XCTAssertEqual(TodayConfirm.count(visible: items), 5)
        XCTAssertEqual(TodayConfirm.rows(visible: items).map(\.title), ["top", "mid"])
        XCTAssertEqual(TodayConfirm.rows(visible: items, limit: 1).map(\.title), ["top"])
        XCTAssertTrue(TodayConfirm.showsReviewAll(count: 5))
        XCTAssertTrue(TodayConfirm.showsReviewAll(count: 3))
        XCTAssertFalse(TodayConfirm.showsReviewAll(count: 2))
        XCTAssertTrue(TodayConfirm.showsReviewAll(count: 2, limit: 1))
        XCTAssertEqual(TodayConfirm.rows(visible: []).count, 0)
    }
}

// MARK: - To confirm follows the rental chip (shot-bug 5, 2026-10-27)

@MainActor
final class TodayConfirmScopeTests: CaptureTestCase {
    private let pine = UUID(), oak = UUID()
    private func s(_ key: String, property: UUID?, confidence: Double = 0.9) -> Suggestion {
        let start = date(2026, 10, 14, 9)
        return Suggestion(sourceKey: "cal:\(key)", kind: .calendar, detectedAt: start, start: start,
                          end: start.addingTimeInterval(3600), title: key, containerId: "CAL",
                          proposedPropertyId: property, proposedCategory: .repairs, proposedHours: 1,
                          hoursBasis: .scheduled, confidence: confidence)
    }

    func testASingleRentalCountsOnlyItsOwnItems() {
        let items = [s("a", property: pine), s("b", property: pine), s("c", property: oak), s("d", property: nil)]
        XCTAssertEqual(TodayConfirm.count(visible: items, rentalID: pine), 2)
        XCTAssertEqual(TodayConfirm.count(visible: items, rentalID: oak), 1)
        XCTAssertEqual(Set(TodayConfirm.rows(visible: items, rentalID: pine).map(\.title)), ["a", "b"])
        XCTAssertFalse(TodayConfirm.showsReviewAll(count: TodayConfirm.count(visible: items, rentalID: oak)))
    }

    func testAllRentalsCountsEverything() {
        let items = [s("a", property: pine), s("b", property: oak), s("c", property: nil)]
        XCTAssertEqual(TodayConfirm.count(visible: items, rentalID: nil), 3)
        XCTAssertEqual(TodayConfirm.count(visible: items), 3)
    }

    func testARentalWithNothingPendingCountsZero() {
        XCTAssertEqual(TodayConfirm.count(visible: [s("a", property: pine)], rentalID: oak), 0)
    }

    func testHeaderCountAndRowsAgreeForTheSamePage() {
        let items = (0..<5).map { s("p\($0)", property: pine) } + (0..<3).map { s("o\($0)", property: oak) }
        for page in [pine, oak, nil] as [UUID?] {
            let count = TodayConfirm.count(visible: items, rentalID: page)
            let rows = TodayConfirm.rows(visible: items, rentalID: page, limit: 99)
            XCTAssertEqual(rows.count, count, "header N must equal the rows it can open")
        }
    }
}

// MARK: - Today ⇄ Inbox: one list, one count, one write path

@MainActor
final class TodayInboxConsistencyTests: CaptureTestCase {
    private var app: AppViewModel!
    private var propertyId: UUID!
    private var store: SuggestionStore!
    private var now: Date!
    private var year: Int!

    override func setUp() async throws {
        try await super.setUp()
        (app, propertyId) = makeViewModel()
        store = makeStore()
        now = Date()
        year = Calendar.current.component(.year, from: now)
    }

    private func model() -> InboxViewModel {
        let store = self.store
        let model = InboxViewModel(app: app, storeProvider: { store }, now: { [now] in now! },
                                   calendar: calendar, spouseTracking: { false }, undoWindow: .infinity)
        model.reload()
        return model
    }

    private func seed(_ count: Int) -> [Suggestion] {
        // Same day as `now` (minus a few hours) keeps every item in this tax year.
        let items = (0..<count).map { i in
            calendarSuggestion(externalId: "T\(i)", start: now.addingTimeInterval(-Double(i + 2) * 3600 - 7200),
                               title: "Plumber \(i)", propertyId: propertyId, hours: 2, category: .repairs)
        }
        store.ingest(items, existingEntries: app.timeEntries, calendar: calendar)
        return items
    }

    /// What Today shows and what the Inbox badge shows, read from the shared model.
    private func assertOneCount(_ today: InboxViewModel, inboxTab: InboxViewModel, file: StaticString = #filePath, line: UInt = #line) {
        inboxTab.reload()
        XCTAssertEqual(TodayConfirm.count(visible: today.visible), today.badgeCount, "Today's capsule is the badge", file: file, line: line)
        XCTAssertEqual(today.badgeCount, inboxTab.badgeCount, "The Inbox sees the same list", file: file, line: line)
        XCTAssertEqual(Set(TodayConfirm.rows(visible: today.visible).map(\.sourceKey))
                        .isSubset(of: Set(inboxTab.visible.map(\.sourceKey))), true, file: file, line: line)
    }

    func testConfirmFromTodayUpdatesTheHouseTheInboxAndTheBadgeTogether() {
        let items = seed(5)
        let today = model()
        let inboxTab = model()
        assertOneCount(today, inboxTab: inboxTab)
        XCTAssertEqual(today.badgeCount, 5)
        let houseBefore = app.houseCountableHours(goal: .reps750, year: year)

        let first = TodayConfirm.rows(visible: today.visible)[0]
        XCTAssertEqual(today.swipeLog(first), .logged)

        XCTAssertEqual(app.houseCountableHours(goal: .reps750, year: year), houseBefore + 2, accuracy: 0.0001,
                       "The house counts the confirmed hours at once")
        XCTAssertEqual(today.badgeCount, 4)
        XCTAssertFalse(today.visible.contains { $0.sourceKey == first.sourceKey })
        assertOneCount(today, inboxTab: inboxTab)
        XCTAssertTrue(items.contains { $0.sourceKey == first.sourceKey })
        XCTAssertEqual(store.suggestion(forKey: first.sourceKey)?.state,
                       .confirmed(entryId: first.entryId(profileId: profileId)))
    }

    func testNotRentalWorkFromTodayLeavesTheHouseAndDropsTheBadge() {
        _ = seed(2)
        let today = model()
        let inboxTab = model()
        let houseBefore = app.houseCountableHours(goal: .reps750, year: year)
        let row = TodayConfirm.rows(visible: today.visible)[0]

        today.dismiss(row)

        XCTAssertEqual(app.houseCountableHours(goal: .reps750, year: year), houseBefore, "Not rental work never counts")
        XCTAssertTrue(store.isDismissed(row.sourceKey))
        XCTAssertEqual(today.toast?.message, "Marked not rental work")
        XCTAssertEqual(today.badgeCount, 1)
        assertOneCount(today, inboxTab: inboxTab)

        today.undo()
        XCTAssertEqual(today.badgeCount, 2, "Undo puts it back on Today and in the Inbox")
        assertOneCount(today, inboxTab: inboxTab)
    }

    func testConfirmFromTheInboxShowsOnTodayToo() {
        _ = seed(3)
        let today = model()
        let inboxTab = model()
        XCTAssertTrue(TodayConfirm.showsReviewAll(count: today.badgeCount))
        let any = inboxTab.visible[0]
        XCTAssertEqual(inboxTab.swipeLog(any), .logged)
        today.reload()
        XCTAssertEqual(today.badgeCount, 2)
        XCTAssertFalse(TodayConfirm.showsReviewAll(count: today.badgeCount), "Two fit on Today: no See all")
        assertOneCount(today, inboxTab: inboxTab)
    }

    func testCaughtUpOnceTheLastItemIsConfirmed() {
        _ = seed(1)
        let today = model()
        XCTAssertEqual(TodayConfirm.state(hasProperties: true, pendingCount: today.badgeCount, backfillScanning: false, captureOn: true), .rows)
        today.swipeLog(today.visible[0])
        XCTAssertEqual(TodayConfirm.state(hasProperties: true, pendingCount: today.badgeCount, backfillScanning: false, captureOn: true),
                       .caughtUp(captureOn: true))
    }
}

// MARK: - This week

final class TodayWeekTests: XCTestCase {
    private func calendar(_ zone: String, firstWeekday: Int = 1) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func at(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func entry(_ date: Date, _ hours: Double, _ who: Participant = .selfParticipant,
                       _ category: ActivityCategory = .repairs) -> TimeEntry {
        TimeEntry(propertyId: UUID(), participant: who, category: category, hours: hours, date: date, notes: "")
    }

    func testWeekStartsMondayEvenWhenTheLocaleStartsSunday() {
        let la = calendar("America/Los_Angeles", firstWeekday: 1)
        let now = at(la, 2026, 10, 21, 10)   // Wednesday
        let days = TodayWeek.days(entries: [], goal: .reps750, includeSpouse: false, now: now, calendar: la)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.map(\.letter), ["M", "T", "W", "T", "F", "S", "S"])
        XCTAssertEqual(days[0].date, at(la, 2026, 10, 19, 0))
        XCTAssertEqual(days.firstIndex(where: \.isToday), 2)
        XCTAssertEqual(days.map(\.isFuture), [false, false, false, true, true, true, true])
        XCTAssertEqual(days[0].hours, 0, "A past day with nothing is 0 (a dot), not 'not yet'")
    }

    func testSundayIsTheLastDayOfItsOwnWeek() {
        let la = calendar("America/Los_Angeles")
        let sunday = at(la, 2026, 10, 25, 20)
        let days = TodayWeek.days(entries: [], goal: .reps750, includeSpouse: false, now: sunday, calendar: la)
        XCTAssertEqual(days[0].date, at(la, 2026, 10, 19, 0), "Sunday belongs to the week that started Monday the 19th")
        XCTAssertTrue(days[6].isToday)
        XCTAssertFalse(days.contains(where: \.isFuture))
    }

    func testEntriesLandOnTheirLocalDayAndOutsideTheWeekAreIgnored() {
        let la = calendar("America/Los_Angeles")
        let now = at(la, 2026, 10, 21, 18)
        let entries = [
            entry(at(la, 2026, 10, 18, 23, 30), 5),   // Sunday before: last week (Monday in UTC)
            entry(at(la, 2026, 10, 19, 0, 10), 1.5),  // Monday just after midnight
            entry(at(la, 2026, 10, 19, 23, 50), 1),   // Monday late (Tuesday in UTC)
            entry(at(la, 2026, 10, 21, 9), 3),        // today
            entry(at(la, 2026, 10, 23, 9), 4),        // Friday: future, never shown
        ]
        let days = TodayWeek.days(entries: entries, goal: .reps750, includeSpouse: false, now: now, calendar: la)
        XCTAssertEqual(days.map(\.hours), [2.5, 0, 3, nil, nil, nil, nil])
        XCTAssertEqual(TodayWeek.total(days), 5.5)

        // The same instants seen from Tokyo split into different days.
        let tokyo = calendar("Asia/Tokyo")
        let tokyoDays = TodayWeek.days(entries: entries, goal: .reps750, includeSpouse: false, now: now, calendar: tokyo)
        XCTAssertNotEqual(tokyoDays.map(\.hours), days.map(\.hours))
    }

    func testDaylightSavingWeekKeepsSevenWholeDays() {
        let la = calendar("America/Los_Angeles")
        // US DST ends Sunday Nov 1, 2026 (25-hour day).
        let now = at(la, 2026, 11, 1, 22)
        let entries = [entry(at(la, 2026, 11, 1, 0, 30), 1), entry(at(la, 2026, 11, 1, 23, 30), 2),
                       entry(at(la, 2026, 10, 26, 0, 30), 1)]
        let days = TodayWeek.days(entries: entries, goal: .reps750, includeSpouse: false, now: now, calendar: la)
        XCTAssertEqual(days.first?.date, at(la, 2026, 10, 26, 0))
        XCTAssertEqual(days.last?.date, at(la, 2026, 11, 1, 0))
        XCTAssertEqual(days[6].hours, 3)
        XCTAssertEqual(days[0].hours, 1)
        XCTAssertTrue(days[6].isToday)

        // Spring forward: Sunday Mar 8, 2026 (23-hour day).
        let spring = at(la, 2026, 3, 9, 12)
        let springDays = TodayWeek.days(entries: [entry(at(la, 2026, 3, 9, 0, 15), 2)], goal: .reps750,
                                        includeSpouse: false, now: spring, calendar: la)
        XCTAssertEqual(springDays[0].date, at(la, 2026, 3, 9, 0))
        XCTAssertEqual(springDays[0].hours, 2)
    }

    // MARK: Spouse rule (the house's rule, applied per day)

    func testREPSCountsYourOwnHoursOnlyEvenWhenSpouseIsTrackedJointly() {
        let la = calendar("America/Los_Angeles")
        let now = at(la, 2026, 10, 21, 18)
        let entries = [entry(at(la, 2026, 10, 20, 9), 2), entry(at(la, 2026, 10, 20, 11), 3, .spouse)]
        let days = TodayWeek.days(entries: entries, goal: .reps750, includeSpouse: true, now: now, calendar: la)
        XCTAssertEqual(days[1].hours, 2, "Spouse hours never count toward your 750 (IRC 469(c)(7)(B))")
    }

    func testMaterialParticipationAddsSpouseHoursOnlyWhenTrackedJointly() {
        let la = calendar("America/Los_Angeles")
        let now = at(la, 2026, 10, 21, 18)
        let entries = [entry(at(la, 2026, 10, 20, 9), 2), entry(at(la, 2026, 10, 20, 11), 3, .spouse)]
        XCTAssertEqual(TodayWeek.days(entries: entries, goal: .mp500, includeSpouse: true, now: now, calendar: la)[1].hours, 5)
        XCTAssertEqual(TodayWeek.days(entries: entries, goal: .mp500, includeSpouse: false, now: now, calendar: la)[1].hours, 2)
        XCTAssertEqual(TodayWeek.days(entries: entries, goal: .mp100, includeSpouse: true, now: now, calendar: la)[1].hours, 5)
    }

    func testInvestorOnlyWorkNeverCounts() {
        let la = calendar("America/Los_Angeles")
        let now = at(la, 2026, 10, 21, 18)
        let entries = [entry(at(la, 2026, 10, 20, 9), 2, .selfParticipant, .investing),
                       entry(at(la, 2026, 10, 20, 10), 1, .selfParticipant, .financing),
                       entry(at(la, 2026, 10, 20, 11), 1, .selfParticipant, .contractNegotiation),
                       entry(at(la, 2026, 10, 20, 12), 1.5, .selfParticipant, .leasing)]
        let days = TodayWeek.days(entries: entries, goal: .reps750, includeSpouse: false, now: now, calendar: la)
        XCTAssertEqual(days[1].hours, 1.5)
    }

    func testWeekDayTotalsMatchTheHouseRuleForTheSameEntries() {
        // Every entry this week, summed per day, equals the REPS engine over the same entries.
        let la = calendar("America/Los_Angeles")
        let now = at(la, 2026, 10, 21, 18)
        let entries = [entry(at(la, 2026, 10, 19, 9), 2), entry(at(la, 2026, 10, 20, 9), 3, .spouse),
                       entry(at(la, 2026, 10, 21, 9), 1, .selfParticipant, .investing),
                       entry(at(la, 2026, 10, 21, 10), 4)]
        let days = TodayWeek.days(entries: entries, goal: .reps750, includeSpouse: true, now: now, calendar: la)
        let engine = entries.filter { $0.participant == .selfParticipant && $0.countsForREPS }.reduce(0) { $0 + $1.hours }
        XCTAssertEqual(TodayWeek.total(days), engine)
    }

    // MARK: Bars

    func testOnlyTheTallestBarIsLabelledAndBarsScaleToIt() {
        let la = calendar("America/Los_Angeles")
        let now = at(la, 2026, 10, 25, 20)
        let entries = [entry(at(la, 2026, 10, 19, 9), 1), entry(at(la, 2026, 10, 21, 9), 3), entry(at(la, 2026, 10, 24, 9), 3)]
        let days = TodayWeek.days(entries: entries, goal: .reps750, includeSpouse: false, now: now, calendar: la)
        XCTAssertEqual(TodayWeek.labelledIndex(days), 2, "Earliest of the tied tallest")
        XCTAssertEqual(TodayWeek.barHeight(hours: 3, peak: 3), 56)
        XCTAssertEqual(TodayWeek.barHeight(hours: 1, peak: 3), 56.0 / 3, accuracy: 0.001)
        XCTAssertEqual(TodayWeek.barHeight(hours: 0.1, peak: 3), 10, "Floor keeps a short day a capsule")
        XCTAssertEqual(TodayWeek.barHeight(hours: 0, peak: 3), 0)
        XCTAssertNil(TodayWeek.labelledIndex(TodayWeek.days(entries: [], goal: .reps750, includeSpouse: false, now: now, calendar: la)))
    }

    func testVoiceOverWords() {
        let la = calendar("America/Los_Angeles")
        let now = at(la, 2026, 10, 21, 18)
        let days = TodayWeek.days(entries: [entry(at(la, 2026, 10, 21, 9), 1.5)], goal: .reps750, includeSpouse: false, now: now, calendar: la)
        XCTAssertEqual(TodayWeek.spoken(days[0]), "Monday, no hours")
        XCTAssertEqual(TodayWeek.spoken(days[2]), "Wednesday, today, 1 hour 30 minutes")
        XCTAssertEqual(TodayWeek.spoken(days[6]), "Sunday, not yet")
    }
}

// MARK: - Pace cards and the record slot

final class TodayPaceAndRecordTests: XCTestCase {
    func testFinishCardIsCautionOnlyWhenBehind() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12))!
        let behind = TodayPaceCards.finish(hours: 212, goal: .reps750, pace: TodayPace(text: "Behind by 388h", tone: .caution), now: now, calendar: calendar)
        XCTAssertEqual(behind.label, "To finish by Dec 31")
        XCTAssertEqual(behind.tone, .caution)
        XCTAssertEqual(behind.status, "Behind pace")
        // 538h left over 73 days (10.43 weeks) → 52h a week, rounded up.
        XCTAssertEqual(behind.value, "52h a week")

        let ahead = TodayPaceCards.finish(hours: 700, goal: .reps750, pace: TodayPace(text: "On pace", tone: .positive), now: now, calendar: calendar)
        XCTAssertEqual(ahead.tone, .neutral)
        XCTAssertEqual(ahead.status, "On pace")

        let met = TodayPaceCards.finish(hours: 751, goal: .reps750, pace: TodayPace(text: "Goal hours met", tone: .positive), now: now, calendar: calendar)
        XCTAssertEqual(met.value, "Reached")
        XCTAssertEqual(met.tone, .positive)
    }

    func testRecordSlotOnlyForFreeUsersFromTenHours() {
        XCTAssertFalse(TodayRecordSlot.isShown(isPro: false, confirmedHours: 9.9))
        XCTAssertTrue(TodayRecordSlot.isShown(isPro: false, confirmedHours: 10))
        XCTAssertFalse(TodayRecordSlot.isShown(isPro: true, confirmedHours: 500))
        XCTAssertFalse(TodayRecordSlot.isShown(isPro: false, confirmedHours: .nan))
    }
}

// MARK: - v2: the crafted hero's pages and pace sentence (§H.1 H10, §H.8)

final class TodayCraftHeroTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testOneRentalHasNoAllRentalsPage() {
        let id = UUID()
        let pages = TodayFocusList.make(rentals: [.init(id: id, name: "Pine Cabin", hours: 46)], goal: 100, allRentalsName: "All rentals")
        XCTAssertEqual(pages.map(\.name), ["Pine Cabin"])
        XCTAssertEqual(pages[0].stage, .frame70)
        XCTAssertEqual(pages[0].id, id.uuidString)
    }

    func testAllRentalsLeadsAndSumsAgainstTheGoal() {
        let pages = TodayFocusList.make(rentals: [.init(id: UUID(), name: "Santa Ray Ave", hours: 46),
                                                  .init(id: UUID(), name: "Delaney Ct", hours: 4),
                                                  .init(id: UUID(), name: "Pine Cabin", hours: 62)],
                                        goal: 100, allRentalsName: "All rentals")
        XCTAssertEqual(pages.map(\.name), ["All rentals", "Santa Ray Ave", "Delaney Ct", "Pine Cabin"])
        XCTAssertTrue(pages[0].isAllRentals)
        XCTAssertEqual(pages[0].hours, 112)
        XCTAssertEqual(pages[0].stage, .complete)
        XCTAssertNil(pages[0].rentalIDs)
        XCTAssertEqual(pages.map(\.stage), [.complete, .frame70, .started, .half])
    }

    func testNoRentalsNoPages() {
        XCTAssertTrue(TodayFocusList.make(rentals: [], goal: 100, allRentalsName: "All rentals").isEmpty)
    }

    func testInitialFocusPrefersTheRememberedPageThenTheCountedRental() {
        let a = UUID(), b = UUID()
        let pages = TodayFocusList.make(rentals: [.init(id: a, name: "A", hours: 1), .init(id: b, name: "B", hours: 2)],
                                        goal: 100, allRentalsName: "All")
        XCTAssertEqual(TodayFocusList.initialFocusID(pages, remembered: b.uuidString, countedRental: a), b.uuidString)
        XCTAssertEqual(TodayFocusList.initialFocusID(pages, remembered: "gone", countedRental: a), a.uuidString)
        XCTAssertEqual(TodayFocusList.initialFocusID(pages, remembered: nil, countedRental: nil), "all")
    }

    func testStepWraps() {
        let pages = TodayFocusList.make(rentals: [.init(id: UUID(), name: "A", hours: 1), .init(id: UUID(), name: "B", hours: 2)],
                                        goal: 100, allRentalsName: "All")
        XCTAssertEqual(TodayFocusList.step(pages, from: pages[2].id, by: 1), pages[0].id)
        XCTAssertEqual(TodayFocusList.step(pages, from: pages[0].id, by: -1), pages[2].id)
        XCTAssertNil(TodayFocusList.step([], from: nil, by: 1))
    }

    func testPaceBehindMatchesTheLockedFrame() {
        // Oct 23 2026 (day 296): 46 of 100 expected 81 → behind by 35; 54 left over 10 weeks → 6h a week.
        let pace = TodayPaceSentence.make(.init(hours: 46, goal: 100, year: 2026, now: day(2026, 10, 23), calendar: calendar))
        XCTAssertEqual(pace.lead, "Behind by 35h.")
        XCTAssertEqual(pace.rest, "6h a week gets you to 100.")
        XCTAssertEqual(pace.tone, .behind)
    }

    func testPaceOnPaceDoneAndCaveat() {
        let onPace = TodayPaceSentence.make(.init(hours: 90, goal: 100, year: 2026, now: day(2026, 10, 23), calendar: calendar))
        XCTAssertEqual(onPace.lead, "On pace.")
        XCTAssertEqual(onPace.tone, .positive)
        let done = TodayPaceSentence.make(.init(hours: 750, goal: 750, year: 2026, now: day(2026, 10, 23), calendar: calendar))
        XCTAssertEqual(done.lead, "Done for 2026.")
        XCTAssertEqual(done.rest, "750 hours on the record.")
        let caveat = TodayPaceSentence.make(.init(hours: 751, goal: 750, year: 2026, now: day(2026, 10, 23), calendar: calendar,
                                                  reachedCaveat: "750 reached. The half rule isn’t met yet."))
        XCTAssertEqual(caveat.tone, .positive, "the hours are reached: the lead is positiveOnPage (§H.4)")
        XCTAssertEqual(caveat.lead, "750 reached.")
        let open = TodayPaceSentence.make(.init(hours: 101, goal: 100, year: 2026, now: day(2026, 10, 23), calendar: calendar,
                                                reachedCaveat: "Confirm no one did more"))
        XCTAssertEqual(open.rest, "Confirm no one did more.", "every pace line ends with a full stop")
    }

    func testReachedCaveatInTodaysWords() {
        func copy(hours: Double, goal: HouseGoal, half: TaxQualificationEngine.MoreThanHalfStatus = .notEntered, noOneMore: Bool? = nil) -> TodayHeroCopy {
            TodayHeroCopy.make(.init(goal: goal, hours: hours, year: 2026, now: day(2026, 10, 23), calendar: calendar,
                                     halfTest: half, noOneParticipatedMore: noOneMore))
        }
        let ask = DashboardView.reachedCaveat(copy(hours: 120, goal: .mp100), hours: 120, goal: 100)
        XCTAssertEqual(ask, "Did anyone do more? Tap to answer.")
        let atLine = DashboardView.reachedCaveat(copy(hours: 750, goal: .reps750), hours: 750, goal: 750)
        XCTAssertEqual(atLine, "The test needs more than 750 hours.")
        let half = DashboardView.reachedCaveat(copy(hours: 760, goal: .reps750), hours: 760, goal: 750)
        XCTAssertEqual(half, "Add your other work hours to check the half rule.", "the lead says \"750 reached.\" once")
    }

    func testRowTimeRangeNeverBreaks() {
        XCTAssertEqual(TodayConfirmBlock.unbreakable("9–10:30"), "9\u{2060}–\u{2060}10:30")
        XCTAssertFalse(TodayConfirmBlock.unbreakable("12–2").contains(" "))
    }

    func testChipNameDropsWholeWords() {
        XCTAssertEqual(TodayChipName.candidates("Pine Cabin"), ["Pine Cabin", "Pine…"])
        XCTAssertEqual(TodayChipName.candidates("Maple"), ["Maple"])
        let long = TodayChipName.candidates("The Arroyo Seco Schoolhouse Lofts")
        XCTAssertEqual(long.first, "The Arroyo Seco Schoolhouse Lofts")
        XCTAssertEqual(long[1], "The Arroyo Seco Schoolhouse…")
        XCTAssertTrue(long.dropFirst().allSatisfy { $0.hasSuffix("…") })
        XCTAssertEqual(TodayChipName.candidates("Oak St, Unit 2"), ["Oak St, Unit 2", "Oak St, Unit…", "Oak St…", "Oak…"])
    }

    func testPaceWaitsAndNeverQualifies() {
        let none = TodayPaceSentence.make(.init(hours: 0, goal: 100, year: 2026, now: day(2026, 3, 1), calendar: calendar))
        XCTAssertNil(none.lead)
        let early = TodayPaceSentence.make(.init(hours: 3, goal: 100, year: 2026, now: day(2026, 3, 1), calendar: calendar, paceReady: false))
        XCTAssertEqual(early.rest, "Log a few weeks to see your pace.")
        let record = TodayPaceSentence.make(.init(hours: 30, goal: 100, year: 2026, now: day(2026, 3, 1), calendar: calendar, isRecord: true))
        XCTAssertNil(record.lead)
        for p in [none, early, record] { XCTAssertFalse(p.spoken.lowercased().contains("qualif")) }
    }

    func testRowLimitFollowsHeightAndTextSize() {
        XCTAssertEqual(TodayConfirm.rowLimit(windowHeight: 874, typeSize: .large), 2)
        XCTAssertEqual(TodayConfirm.rowLimit(windowHeight: 667, typeSize: .large), 1)
        XCTAssertEqual(TodayConfirm.rowLimit(windowHeight: 874, typeSize: .xxLarge), 1)
        XCTAssertEqual(TodayConfirm.rowLimit(windowHeight: 874, typeSize: .accessibility3), 2)
    }
}
