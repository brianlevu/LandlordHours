import XCTest
@testable import LandlordHours

// MARK: - WP-R follow-up (a): spouse hours off → engagement, Siri and the widget count like the house

final class EngagementSpouseSettingTests: XCTestCase {
    private let service = EngagementIntelligenceService()
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    /// Self 300h + spouse 600h on one property, the same shape as the int1 finding.
    private func context(goal: HourGoalType, includeSpouse: Bool) -> EngagementContext {
        let property = RentalProperty(name: "Oak", address: "1 Oak", propertyType: .str)
        let day = date(2026, 9, 28)
        let entries = [
            TimeEntry(propertyId: property.id, participant: .selfParticipant, category: .management, hours: 300, date: day, notes: "self"),
            TimeEntry(propertyId: property.id, participant: .spouse, category: .management, hours: 600, date: day, notes: "spouse")
        ]
        var context = EngagementContext(
            now: date(2026, 10, 1),
            taxYear: 2026,
            properties: [property],
            timeEntries: entries,
            calendarDraftCount: 0,
            isTimerRunning: false,
            timerStartTime: nil,
            notificationPermission: .authorized,
            recentDismissals: [],
            isProUser: true
        )
        context.goalType = goal
        context.targetHours = goal.hoursRequired
        context.includeSpouse = includeSpouse
        return context
    }

    func testMaterialParticipationExcludesSpouseWhenSpouseHoursAreOff() {
        XCTAssertEqual(service.snapshot(for: context(goal: .str, includeSpouse: false), calendar: calendar).yearHours, 300, accuracy: 0.001)
        XCTAssertEqual(service.snapshot(for: context(goal: .str, includeSpouse: true), calendar: calendar).yearHours, 900, accuracy: 0.001)
    }

    func testRepsNeverCombinesWhicheverWayTheSettingIs() {
        XCTAssertEqual(service.snapshot(for: context(goal: .reps, includeSpouse: true), calendar: calendar).yearHours, 300, accuracy: 0.001)
        XCTAssertEqual(service.snapshot(for: context(goal: .reps, includeSpouse: false), calendar: calendar).yearHours, 300, accuracy: 0.001)
    }

    func testSiriSummaryExcludesSpouseWhenSpouseHoursAreOff() {
        let ctx = context(goal: .str, includeSpouse: false)
        let text = LandlordHoursIntentCopy.summaryDialog(
            year: 2026,
            context: ctx,
            snapshot: service.snapshot(for: ctx, calendar: calendar),
            recommendation: service.recommendation(for: ctx, calendar: calendar)
        )
        XCTAssertTrue(text.contains("You have 300.0 hours toward 100 this year"), text)
    }

    func testDefaultContextKeepsTheJointTotal() {
        // Callers that predate the setting (the Engagement Lab) keep the 1.x behaviour.
        var ctx = context(goal: .str, includeSpouse: true)
        ctx = EngagementContext(
            now: ctx.now, taxYear: ctx.taxYear, properties: ctx.properties, timeEntries: ctx.timeEntries,
            calendarDraftCount: 0, isTimerRunning: false, timerStartTime: nil,
            notificationPermission: .authorized, recentDismissals: [], isProUser: true,
            targetHours: 100, goalType: .str
        )
        XCTAssertTrue(ctx.includeSpouse)
    }
}

/// The model's own builder (widget + Siri) agrees with Today's house in both spouse settings.
@MainActor
final class EngagementMatchesHouseTests: CaptureTestCase {
    private var savedSpouseTracking = true
    private var savedGoal: HourGoalType = .reps

    override func setUp() async throws {
        try await super.setUp()
        savedSpouseTracking = TaxProfileManager.shared.spouseTracking
        savedGoal = GoalManager.shared.globalGoalType
    }

    override func tearDown() async throws {
        TaxProfileManager.shared.spouseTracking = savedSpouseTracking
        GoalManager.shared.globalGoalType = savedGoal
        TodayHouseEvents.shared.takeConfirm()
        try await super.tearDown()
    }

    private func seed() -> AppViewModel {
        let (vm, property) = makeViewModel()
        vm.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs, hours: 70, date: Date(), notes: "")
        vm.addTimeEntry(propertyId: property, participant: .spouse, category: .leasing, hours: 40, date: Date(), notes: "")
        return vm
    }

    func testWidgetAndSiriContextMatchTheHouseWithSpouseHoursOff() {
        GoalManager.shared.globalGoalType = .str
        let vm = seed()
        TaxProfileManager.shared.spouseTracking = false

        let context = vm.engagementContext()
        XCTAssertFalse(context.includeSpouse)
        let engagementHours = EngagementIntelligenceService.shared.snapshot(for: context).yearHours
        XCTAssertEqual(engagementHours, 70, accuracy: 0.001)
        XCTAssertEqual(engagementHours, vm.houseCountableHours(goal: .mp100), accuracy: 0.001)

        // The widget snapshot is rewritten when the setting changes, with the same number.
        XCTAssertEqual(EngagementWidgetSnapshotStore.load().yearHours, 70, accuracy: 0.001)
    }

    func testWidgetAndSiriContextMatchTheHouseWithSpouseHoursOn() {
        GoalManager.shared.globalGoalType = .str
        let vm = seed()
        TaxProfileManager.shared.spouseTracking = true

        let engagementHours = EngagementIntelligenceService.shared.snapshot(for: vm.engagementContext()).yearHours
        XCTAssertEqual(engagementHours, 110, accuracy: 0.001)
        XCTAssertEqual(engagementHours, vm.houseCountableHours(goal: .mp100), accuracy: 0.001)
        XCTAssertEqual(EngagementWidgetSnapshotStore.load().yearHours, 110, accuracy: 0.001)
    }

    func testReportsLeadWithTodaysNumbers() {
        GoalManager.shared.globalGoalType = .reps
        TaxProfileManager.shared.spouseTracking = true
        let vm = seed()
        let year = Calendar.current.component(.year, from: Date())

        let reps = vm.reportStandings(goal: .reps750, year: year)
        XCTAssertEqual(reps.map(\.person), [.you, .spouse])
        XCTAssertEqual(reps[0].hours, vm.houseCountableHours(goal: .reps750, year: year), accuracy: 0.001)
        XCTAssertEqual(reps[1].hours, 40, accuracy: 0.001, "The spouse's own REPS hours, never added to yours")

        TaxProfileManager.shared.spouseTracking = false
        let mp = vm.reportStandings(goal: .mp100, year: year)
        XCTAssertEqual(mp.count, 1)
        XCTAssertEqual(mp[0].hours, vm.houseCountableHours(goal: .mp100, year: year), accuracy: 0.001)
        XCTAssertEqual(mp[0].hours, 70, accuracy: 0.001)
    }
}

// MARK: - Records logic

final class RecordsLogicTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private let property = UUID()

    private func entry(_ hours: Double, _ day: Date, source: String? = nil, confirmed: Bool = false, who: Participant = .selfParticipant, notes: String = "", category: ActivityCategory = .repairs) -> TimeEntry {
        TimeEntry(
            propertyId: property, participant: who, category: category, hours: hours, date: day, notes: notes,
            importSource: source, confirmedAt: confirmed ? day : nil
        )
    }

    func testTotalLabelSaysTheREPSTestCountsYourHoursOnly() {
        XCTAssertEqual(
            RecordsLogic.totalLabel(goal: .reps750, tracksSpouseJointly: true),
            "All logged hours. The 750h test counts your hours only."
        )
        XCTAssertEqual(
            RecordsLogic.totalLabel(goal: .reps750, tracksSpouseJointly: false),
            "All logged hours. The 750h test counts your hours only."
        )
        XCTAssertEqual(
            RecordsLogic.totalLabel(goal: .mp100, tracksSpouseJointly: true),
            "All logged hours. The 100h test counts you and your spouse."
        )
        XCTAssertEqual(
            RecordsLogic.totalLabel(goal: .mp500, tracksSpouseJointly: false),
            "All logged hours. The 500h test counts your hours only."
        )
    }

    func testSourceBadges() {
        let day = date(2026, 10, 1)
        XCTAssertEqual(RecordSourceBadge(entry: entry(1, day)), .manual)
        XCTAssertEqual(RecordSourceBadge(entry: entry(1, day, source: "timer")), .timer)
        XCTAssertEqual(RecordSourceBadge(entry: entry(1, day, source: "voice")), .voice)
        XCTAssertEqual(RecordSourceBadge(entry: entry(1, day, source: "calendar")), .calendarImport)
        XCTAssertEqual(RecordSourceBadge(entry: entry(1, day, source: "calendar", confirmed: true)), .suggested)
        XCTAssertEqual(RecordSourceBadge(entry: entry(1, day, source: "future-thing")), .other)
        XCTAssertEqual(RecordSourceBadge.calendarImport.title, "Calendar import")
        XCTAssertEqual(RecordSourceBadge.suggested.title, "Suggested")
    }

    func testMonthSectionsNewestFirstWithTotals() {
        let entries = [
            entry(2, date(2026, 10, 14)),
            entry(1.5, date(2026, 10, 16)),
            entry(3, date(2026, 9, 2)),
            entry(0.75, date(2026, 9, 20))
        ]
        let sections = RecordsLogic.monthSections(entries, calendar: calendar)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(calendar.component(.month, from: sections[0].month), 10)
        XCTAssertEqual(sections[0].totalHours, 3.5, accuracy: 0.001)
        XCTAssertEqual(sections[0].entries.first?.hours, 1.5, "Newest first inside a month")
        XCTAssertEqual(sections[1].totalHours, 3.75, accuracy: 0.001)
    }

    func testFiltersBySourceWhoYearAndSearch() {
        let entries = [
            entry(2, date(2026, 10, 14), source: "calendar", confirmed: true, notes: "Plumber visit"),
            entry(1, date(2026, 10, 15), source: "timer", who: .spouse, notes: "Turnover clean"),
            entry(4, date(2025, 3, 1), notes: "Old year")
        ]
        var filter = RecordsFilter(year: 2026)
        XCTAssertEqual(RecordsLogic.filtered(entries, filter: filter, propertyName: { _ in "Pine Cabin" }, calendar: calendar).count, 2)
        filter.source = .suggested
        XCTAssertEqual(RecordsLogic.filtered(entries, filter: filter, propertyName: { _ in nil }, calendar: calendar).map(\.hours), [2])
        filter.source = nil
        filter.participant = .spouse
        XCTAssertEqual(RecordsLogic.filtered(entries, filter: filter, propertyName: { _ in nil }, calendar: calendar).map(\.hours), [1])
        filter.participant = nil
        filter.searchText = "pine"
        XCTAssertEqual(RecordsLogic.filtered(entries, filter: filter, propertyName: { _ in "Pine Cabin" }, calendar: calendar).count, 2, "Search matches the property name")
        filter.searchText = "plumber"
        XCTAssertEqual(RecordsLogic.filtered(entries, filter: filter, propertyName: { _ in nil }, calendar: calendar).map(\.hours), [2])
    }

    func testTitleUsesTheNoteOrTheCategory() {
        let day = date(2026, 10, 1)
        XCTAssertEqual(RecordsLogic.title(for: entry(1, day, notes: "Fixed faucet\nand the drain")), "Fixed faucet")
        XCTAssertEqual(RecordsLogic.title(for: entry(1, day, notes: "  ", category: .leasing)), "Leasing")
        XCTAssertEqual(
            RecordsLogic.title(for: entry(1, day, notes: "Oak Street Duplex: tenant messages"), propertyName: "Oak Street Duplex"),
            "Tenant messages",
            "The property has its own line, so a leading property name is dropped"
        )
    }

    func testHoursFormatting() {
        XCTAssertEqual(BPHours.short(2), "2h")
        XCTAssertEqual(BPHours.short(1.5), "1h 30m")
        XCTAssertEqual(BPHours.short(0.75), "45m")
        XCTAssertEqual(BPHours.short(0), "0h")
        XCTAssertEqual(BPHours.spoken(2.25), "2 hours 15 minutes")
    }
}

// MARK: - Reports logic

final class ReportsLogicTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private func rep(hours: Double, other: Double) -> TaxQualificationEngine.REPSResult {
        TaxQualificationEngine.REPSResult(
            participant: .selfParticipant,
            realEstateHours: hours,
            nonRealEstateHours: other,
            meets750HourTest: hours > 750,
            meetsMoreThanHalfPersonalServicesTest: other > 0 && hours > other
        )
    }

    private var midOctober: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12))! }

    func testREPSUsesTodaysPaceLineAndNamesTheFiftyPercentRule() {
        let standing = ReportsLogic.repsStanding(person: .you, rep: rep(hours: 212, other: 0), year: 2026, now: midOctober, calendar: calendar)
        let today = TodayPace.resolve(hours: 212, goal: .reps750, date: midOctober, calendar: calendar)
        XCTAssertEqual(standing.status, today.text)
        XCTAssertEqual(standing.tone, .caution)
        XCTAssertEqual(standing.detail, "50% rule: add your other work hours to check this.")
    }

    func testBothTestsMetIsPositive() {
        let standing = ReportsLogic.repsStanding(person: .you, rep: rep(hours: 800, other: 400), year: 2026, now: midOctober, calendar: calendar)
        XCTAssertEqual(standing.status, "Both tests met")
        XCTAssertEqual(standing.tone, .positive)
    }

    func testHoursMetButRuleOpenIsCaution() {
        let standing = ReportsLogic.repsStanding(person: .you, rep: rep(hours: 800, other: 0), year: 2026, now: midOctober, calendar: calendar)
        XCTAssertEqual(standing.status, "Hours target met")
        XCTAssertEqual(standing.tone, .caution)
    }

    func testClosedYearSaysHowShortItEnded() {
        let pace = ReportsLogic.paceStatus(hours: 700, goal: .reps750, year: 2025, now: midOctober, calendar: calendar)
        XCTAssertEqual(pace.text, "Year ended 50h short")
        XCTAssertEqual(pace.tone, .caution)
    }

    func testMP100WaitsForTheParticipationAnswer() {
        let result = TaxQualificationEngine.MaterialParticipationResult(
            propertyId: nil, ownerAndSpouseHours: 120, meets500HourTest: false, meets100HourTest: false, noOneParticipatedMore: nil
        )
        let standing = ReportsLogic.mpStanding(goal: .mp100, hours: 120, result: result, includesSpouse: true, year: 2026, now: midOctober, calendar: calendar)
        XCTAssertEqual(standing.status, "100 hours reached")
        XCTAssertEqual(standing.person, .household)
    }

    func testRankedFoldsTheTailIntoOther() {
        let bars = ReportsLogic.ranked([("a", 10), ("b", 9), ("c", 8), ("d", 1), ("e", 1), ("f", 1), ("g", 1), ("z", 0)], limit: 4)
        XCTAssertEqual(bars.map(\.label), ["a", "b", "c", "Other"])
        XCTAssertEqual(bars.last?.hours ?? 0, 4, accuracy: 0.001)
    }
}
