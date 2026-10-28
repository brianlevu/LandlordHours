import XCTest
import UIKit
@testable import LandlordHours

// MARK: - Properties (2.0 redesign): per-property hours, the mini-house stage, the free limit,
// and delete. Written before the view; the view reads only these.

@MainActor
final class PropertyCountableHoursTests: CaptureTestCase {
    private var savedSpouseTracking = true
    private var savedGrouping = false
    private var savedGoal: HourGoalType = .reps

    override func setUp() async throws {
        try await super.setUp()
        savedSpouseTracking = TaxProfileManager.shared.spouseTracking
        savedGrouping = TaxProfileManager.shared.groupingElection
        savedGoal = GoalManager.shared.globalGoalType
    }

    override func tearDown() async throws {
        TaxProfileManager.shared.spouseTracking = savedSpouseTracking
        TaxProfileManager.shared.groupingElection = savedGrouping
        GoalManager.shared.globalGoalType = savedGoal
        TodayHouseEvents.shared.takeConfirm()
        try await super.tearDown()
    }

    private var year: Int { Calendar.current.component(.year, from: Date()) }

    private func add(_ vm: AppViewModel, _ property: UUID, _ hours: Double, _ category: ActivityCategory,
                     _ who: Participant = .selfParticipant, date: Date = Date(), notes: String = "") {
        vm.addTimeEntry(propertyId: property, participant: who, category: category, hours: hours, date: date, notes: notes)
    }

    /// Two properties: Oak (from makeViewModel) and Pine.
    private func twoProperties() -> (AppViewModel, UUID, UUID) {
        let (vm, oak) = makeViewModel()
        vm.addProperty(name: "Pine Cabin", address: "88 Ridge Rd", type: .str)
        let pine = vm.properties.first { $0.name == "Pine Cabin" }!.id
        return (vm, oak, pine)
    }

    func testREPSCountsOwnHoursPerPropertyNeverSpouseNeverInvestorTasks() {
        let (vm, oak, pine) = twoProperties()
        TaxProfileManager.shared.spouseTracking = true          // even when tracked jointly
        add(vm, oak, 120, .repairs)
        add(vm, oak, 60, .investing)                            // not countable
        add(vm, oak, 40, .management, .spouse)                  // spouse never fills YOUR 750
        add(vm, pine, 30, .leasing)
        add(vm, pine, 15, .contractNegotiation)                 // not countable

        XCTAssertEqual(vm.propertyCountableHours(oak, goal: .reps750), 120, accuracy: 0.001)
        XCTAssertEqual(vm.propertyCountableHours(pine, goal: .reps750), 30, accuracy: 0.001)
        // Per-property REPS hours add up to exactly what Today's house counts.
        let sum = vm.properties.reduce(0) { $0 + vm.propertyCountableHours($1.id, goal: .reps750) }
        XCTAssertEqual(sum, vm.houseCountableHours(goal: .reps750), accuracy: 0.001)
    }

    func testMaterialParticipationCountsSpouseOnlyWhenTrackedJointly() {
        let (vm, oak, pine) = twoProperties()
        add(vm, oak, 70, .repairs)
        add(vm, oak, 40, .leasing, .spouse)
        add(vm, oak, 25, .financing)                            // not countable
        add(vm, pine, 10, .bookkeeping, .spouse)

        TaxProfileManager.shared.spouseTracking = true
        XCTAssertEqual(vm.propertyCountableHours(oak, goal: .mp500), 110, accuracy: 0.001)
        XCTAssertEqual(vm.propertyCountableHours(pine, goal: .mp100), 10, accuracy: 0.001)
        // Without a grouping election Today shows one rental's own count: with both kinds of
        // rental (Oak is long-term, Pine Cabin is short-term) that is the short-term rental's.
        TaxProfileManager.shared.groupingElection = false
        XCTAssertEqual(vm.propertyCountableHours(pine, goal: .mp500), vm.houseCountableHours(goal: .mp500), accuracy: 0.001)

        TaxProfileManager.shared.spouseTracking = false
        XCTAssertEqual(vm.propertyCountableHours(oak, goal: .mp500), 70, accuracy: 0.001)
        XCTAssertEqual(vm.propertyCountableHours(pine, goal: .mp100), 0, accuracy: 0.001)
    }

    func testGroupingElectionStillShowsEachPropertysOwnHours() {
        let (vm, oak, pine) = twoProperties()
        TaxProfileManager.shared.groupingElection = true
        TaxProfileManager.shared.spouseTracking = true
        add(vm, oak, 50, .repairs)
        add(vm, pine, 20, .repairs)
        XCTAssertEqual(vm.propertyCountableHours(oak, goal: .mp500), 50, accuracy: 0.001)
        XCTAssertEqual(vm.propertyCountableHours(pine, goal: .mp500), 20, accuracy: 0.001)
    }

    func testDefaultGoalFollowsTheSettingLikeToday() {
        let (vm, oak, _) = twoProperties()
        TaxProfileManager.shared.spouseTracking = true
        add(vm, oak, 10, .repairs)
        add(vm, oak, 5, .repairs, .spouse)
        GoalManager.shared.globalGoalType = .reps
        XCTAssertEqual(vm.propertyCountableHours(oak), 10, accuracy: 0.001)
        GoalManager.shared.globalGoalType = .str
        XCTAssertEqual(vm.propertyCountableHours(oak), 15, accuracy: 0.001)
    }

    func testPerRentalWordingFollowsTheGoalAndTheGroupingElection() {
        let (vm, _, _) = twoProperties()
        GoalManager.shared.globalGoalType = .str
        TaxProfileManager.shared.groupingElection = false
        XCTAssertTrue(vm.propertyGoalIsPerProperty)
        TaxProfileManager.shared.groupingElection = true
        XCTAssertFalse(vm.propertyGoalIsPerProperty)
        GoalManager.shared.globalGoalType = .reps
        TaxProfileManager.shared.groupingElection = false
        XCTAssertFalse(vm.propertyGoalIsPerProperty)
    }

    func testOtherYearsNeverCount() {
        let (vm, oak, _) = twoProperties()
        let lastYear = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        add(vm, oak, 300, .repairs, date: lastYear)
        XCTAssertEqual(vm.propertyCountableHours(oak, goal: .reps750), 0, accuracy: 0.001)
    }

    func testNonCountableCategoriesNeverReachTheHouseOrTheKinds() {
        let (vm, oak, _) = twoProperties()
        add(vm, oak, 99, .repairs)
        add(vm, oak, 1, .investing)
        add(vm, oak, 1, .financing)
        add(vm, oak, 1, .contractNegotiation)
        let hours = vm.propertyCountableHours(oak, goal: .reps750)
        XCTAssertEqual(hours, 99, accuracy: 0.001, "102h logged, 99h count")
        XCTAssertEqual(CraftStage.stage(hours: hours, goal: 750), .started, "the 3 investor hours never move the house")
        let kinds = vm.propertyFigures(for: vm.properties.first { $0.id == oak }!, goal: .reps750).kinds
        XCTAssertEqual(kinds.map(\.category), [.repairs])
    }

    func testRentalRowsLightOnlyTheRentalLoggedTodayAndMatchItsHours() {
        let (vm, oak, pine) = twoProperties()
        GoalManager.shared.globalGoalType = .reps
        let cal = Calendar.current
        add(vm, oak, 3, .repairs, date: Date())
        add(vm, pine, 5, .repairs, date: cal.date(byAdding: .day, value: -2, to: Date())!)
        let rows = vm.rentalRows(now: Date())
        let oakRow = rows.first { $0.id == oak }!, pineRow = rows.first { $0.id == pine }!
        XCTAssertTrue(oakRow.lit, "hours logged at Oak today")
        XCTAssertFalse(pineRow.lit, "Pine's hours were two days ago")
        XCTAssertEqual(oakRow.hours, vm.propertyCountableHours(oak), accuracy: 0.001)
        XCTAssertEqual(pineRow.stage, CraftStage.stage(hours: vm.propertyCountableHours(pine), goal: 750))
        XCTAssertEqual(rows.map(\.id), vm.properties.map(\.id), "the list keeps the rentals' order")
    }

    func testFiguresKindsTopFourRecentAndCounts() {
        let (vm, oak, pine) = twoProperties()
        let cal = Calendar.current
        func daysAgo(_ d: Int) -> Date { cal.date(byAdding: .day, value: -d, to: Date())! }
        add(vm, oak, 9, .repairs, date: daysAgo(9), notes: "Gutters")
        add(vm, oak, 5, .management, date: daysAgo(8))
        add(vm, oak, 4, .leasing, date: daysAgo(3), notes: "Showing")
        add(vm, oak, 3, .bookkeeping, date: daysAgo(2))
        add(vm, oak, 1, .legal, date: daysAgo(1), notes: "Permit")
        add(vm, oak, 2, .investing, date: daysAgo(0))
        add(vm, pine, 7, .repairs, date: daysAgo(0))

        let f = vm.propertyFigures(for: vm.properties.first { $0.id == oak }!, goal: .reps750)
        XCTAssertEqual(f.hours, 22, accuracy: 0.001)
        XCTAssertEqual(f.kinds.map(\.category), [.repairs, .management, .leasing, .bookkeeping], "top four, largest first")
        XCTAssertEqual(f.entryCount, 6, "every entry for this rental this year")
        XCTAssertEqual(f.recent.count, 3)
        XCTAssertEqual(f.recent.first?.category, .investing, "newest first, from Records")
        XCTAssertTrue(f.recent.allSatisfy { $0.propertyId == oak })
        XCTAssertEqual(cal.startOfDay(for: f.lastDate!), cal.startOfDay(for: daysAgo(0)))
    }
}

// MARK: - The rental's house: the one stage function, the same goal as its Today page (v2)

final class RentalStageTests: XCTestCase {
    func testRowStageIsTheOneStageFunctionAgainstTheRentalsGoal() {
        let id = UUID()
        for goal in [100.0, 500, 750] {
            for h in stride(from: 0.0, through: goal * 1.3, by: goal / 40) {
                let row = RentalRowModel(id: id, name: "Pine Cabin", hours: h, goal: goal, lit: false, kind: .str)
                XCTAssertEqual(row.stage, CraftStage.stage(hours: h, goal: goal), "\(h)h of \(goal)")
                // The same rental's Today page: TodayFocus for one rental measures against the same goal.
                let today = TodayFocus(rentalID: id, name: "Pine Cabin", hours: h, goal: goal)
                XCTAssertEqual(row.stage, today.stage, "the thumbnail and Today agree at \(h)h of \(goal)")
            }
        }
        // No 500h cap any more: a rental reaches the finished house at its goal.
        XCTAssertEqual(RentalRowModel(id: id, name: "A", hours: 750, goal: 750, lit: true, kind: .ltr).stage, .complete)
        XCTAssertEqual(RentalRowModel(id: id, name: "A", hours: 500, goal: 750, lit: true, kind: .ltr).stage, .half)
    }

    func testRowWordsAndHours() {
        let row = RentalRowModel(id: UUID(), name: "Pine Cabin", hours: 212.9, goal: 750, lit: true, kind: .str)
        XCTAssertEqual(row.value, "212h", "whole hours, never rounded up")
        XCTAssertEqual(RentalRowModel(id: UUID(), name: "M", hours: 0, goal: 750, lit: false, kind: .ltr).value, "0h", "never 0m")
        XCTAssertEqual(row.meta, "Frame going up", "the stage in words")
        XCTAssertEqual(RentalRowModel(id: UUID(), name: "Oak", hours: 0, goal: 750, lit: false, kind: .ltr).meta, "Framing started")
        XCTAssertTrue(row.spoken.hasSuffix("A few nights"), "VoiceOver still hears the kind of stay")
        XCTAssertTrue(row.spoken.hasPrefix("Pine Cabin, 212 hours"))
        // Bad input never reaches the house.
        let bad = RentalRowModel(id: UUID(), name: "X", hours: .nan, goal: 750, lit: false, kind: .ltr)
        XCTAssertEqual(bad.hours, 0)
        XCTAssertEqual(bad.stage, .started)
    }

    func testListSubtitleIsHoursOnlyNeverAGoal() {
        let line = RentalsText.subtitle(count: 3, wholeHours: 312)
        XCTAssertEqual(line, "3 rentals · 312h this year")
        XCTAssertFalse(line.contains("of"), "All rentals never shows a goal, summed or otherwise (H10)")
    }

    func testHouseLookIsReservedNotBuilt() {
        XCTAssertFalse(RentalHouseLook.isBuilt, "§F.1 is designed for, not built: the House row renders nothing")
        XCTAssertEqual(RentalHouseLook.slots, ["roof", "siding", "trim", "door"], "four slots, no more (§F.1)")
        for stage in ["half", "complete"] {
            XCTAssertNil(UIImage(named: "craft_slots_craft_\(stage)"), "no mask pack in the bundle before §F.1")
            XCTAssertNil(UIImage(named: "craft_slots_\(stage)"))
        }
    }
}

// MARK: - The rental page's figures

final class RentalPageFiguresTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        c.firstWeekday = 2
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

    private func input(hours: Double, goal: Double = 100, isRecord: Bool = false, days: Int = 60,
                       thisWeek: Double = 0, lastWeek: Double = 0, now: Date? = nil) -> RentalPageFigures.Input {
        RentalPageFigures.Input(hours: hours, goal: goal, isRecord: isRecord, thisWeek: thisWeek, lastWeek: lastWeek,
                                year: 2026, now: now ?? date(2026, 10, 22), calendar: cal, daysOfData: days)
    }

    func testStageAndPaceAreTodaysForOneRental() {
        let f = RentalPageFigures.make(input(hours: 46, goal: 100))
        XCTAssertEqual(f.stage, .frame70)
        let today = TodayPaceSentence.make(.init(hours: 46, goal: 100, year: 2026, now: date(2026, 10, 22), calendar: cal,
                                                 paceReady: true))
        XCTAssertEqual(f.pace, today, "the rental page says what its Today page says")
        XCTAssertEqual(f.pace.tone, .behind)
    }

    func testFinishTile() {
        XCTAssertEqual(RentalPageFigures.make(input(hours: 120, goal: 100)).finishTile, .init(value: "Reached", label: "100 hours"))
        XCTAssertEqual(RentalPageFigures.make(input(hours: 0)).finishTile.value, "Not yet", "no hours, no weekly number")
        XCTAssertEqual(RentalPageFigures.make(input(hours: 2, days: 3)).finishTile.value, "Not yet", "pace waits for data")
        let weekly = RentalPageFigures.make(input(hours: 46, goal: 100)).finishTile
        XCTAssertEqual(weekly.label, "To finish by Dec 31")
        let weeks = TodayPaceCards.weeksLeft(now: date(2026, 10, 22), calendar: cal)
        XCTAssertEqual(weekly.value, "\(Int((54 / weeks).rounded(.up)))h a week")
        let record = RentalPageFigures.make(input(hours: 46, isRecord: true)).finishTile
        XCTAssertEqual(record, .init(value: "70", label: "Days left in 2026"))
    }

    func testWeekTileTrend() {
        XCTAssertEqual(RentalPageFigures.weekTile(thisWeek: 0, lastWeek: 0), .init(value: "0h", label: "This week", trend: nil))
        XCTAssertEqual(RentalPageFigures.weekTile(thisWeek: 6, lastWeek: 2).trend, .up)
        XCTAssertEqual(RentalPageFigures.weekTile(thisWeek: 1.5, lastWeek: 4).trend, .down)
        XCTAssertEqual(RentalPageFigures.weekTile(thisWeek: 3, lastWeek: 3.1).trend, .flat)
        XCTAssertEqual(RentalPageFigures.weekTile(thisWeek: 1.5, lastWeek: 0).value, "1h 30m")
    }

    func testWeekHoursSplitAtTheCalendarWeek() {
        let now = date(2026, 10, 22) // Thursday; the week starts Monday the 19th.
        func entry(_ d: Date, _ h: Double) -> TimeEntry {
            TimeEntry(propertyId: UUID(), participant: .selfParticipant, category: .repairs, hours: h, date: d)
        }
        let entries = [entry(date(2026, 10, 19), 2), entry(date(2026, 10, 22), 1.5),
                       entry(date(2026, 10, 18), 4), entry(date(2026, 10, 12), 1),
                       entry(date(2026, 10, 11), 9), entry(date(2026, 10, 20), .nan)]
        let w = RentalWeek.hours(entries: entries, now: now, calendar: cal)
        XCTAssertEqual(w.thisWeek, 3.5, accuracy: 0.001)
        XCTAssertEqual(w.lastWeek, 5, accuracy: 0.001)
        XCTAssertEqual(RentalWeek.daysOfData(entries: entries, year: 2026, now: now, calendar: cal), 11)
        XCTAssertEqual(RentalWeek.daysOfData(entries: [], year: 2026, now: now, calendar: cal), 0)
    }
}

final class PropertyMetaTests: XCTestCase {
    func testWordingPerGoalAndGrouping() {
        // Material participation, no grouping election: the 500h test runs per rental.
        // The target is the goal's own number (100 or 500).
        for goal in [HouseGoal.mp500, .mp100] {
            let target = Int(goal.targetHours)
            XCTAssertEqual(PropertyMeta.hoursLine(Double(target) - 0.1, goal: goal, groupingElection: false), "\(target - 1)h of \(target)h")
            XCTAssertEqual(PropertyMeta.hoursLine(Double(target) + 20, goal: goal, groupingElection: false), "\(target + 20)h this year")
            // With a grouping election there is no per-rental test.
            XCTAssertEqual(PropertyMeta.hoursLine(212, goal: goal, groupingElection: true), "212h this year")
        }
        // REPS never claims a per-property 500h test.
        XCTAssertEqual(PropertyMeta.hoursLine(212.9, goal: .reps750, groupingElection: false), "212h this year", "never rounds up")
        XCTAssertEqual(PropertyMeta.hoursLine(520, goal: .reps750, groupingElection: true), "520h this year")
        XCTAssertTrue(PropertyMeta.isPerPropertyTest(goal: .mp500, groupingElection: false))
        XCTAssertFalse(PropertyMeta.isPerPropertyTest(goal: .mp500, groupingElection: true))
        XCTAssertFalse(PropertyMeta.isPerPropertyTest(goal: .reps750, groupingElection: false))
    }
}

// MARK: - Free limit

@MainActor
final class PropertyLimitTests: CaptureTestCase {
    private var savedPro = false

    override func setUp() async throws {
        try await super.setUp()
        savedPro = SubscriptionManager.shared.isPro
    }

    override func tearDown() async throws {
        SubscriptionManager.shared.isPro = savedPro
        try await super.tearDown()
    }

    func testFreeCoversOneRental() {
        XCTAssertFalse(PropertyLimit.isAtLimit(isPro: false, propertyCount: 0))
        XCTAssertTrue(PropertyLimit.isAtLimit(isPro: false, propertyCount: 1))
        XCTAssertTrue(PropertyLimit.isAtLimit(isPro: false, propertyCount: 3), "a downgraded owner keeps their rentals and stays previewing")
        XCTAssertFalse(PropertyLimit.isAtLimit(isPro: true, propertyCount: 1))
        XCTAssertFalse(PropertyLimit.isAtLimit(isPro: true, propertyCount: 40))
    }

    func testViewModelGatesAddingThroughSubscriptionManager() {
        let (vm, _) = makeViewModel()
        SubscriptionManager.shared.isPro = false
        XCTAssertTrue(vm.propertiesAtFreeLimit)
        XCTAssertFalse(vm.canAddProperty())
        SubscriptionManager.shared.isPro = true
        XCTAssertFalse(vm.propertiesAtFreeLimit)
        XCTAssertTrue(vm.canAddProperty())
    }

    func testLockedPreviewCopySaysWhatStaysActive() {
        XCTAssertEqual(PropertyLimit.lockLine, "Free covers one rental.")
        XCTAssertEqual(PropertyLimit.keepsLine(firstPropertyName: "Pine Cabin"), "Pine Cabin keeps tracking. Nothing is lost.")
        XCTAssertEqual(PropertyLimit.keepsLine(firstPropertyName: nil), "Your rental keeps tracking. Nothing is lost.")
        XCTAssertEqual(PropertyLimit.paywallContext, .secondProperty)
    }
}

// MARK: - Seal

final class PropertySealTests: XCTestCase {
    func testMonogram() {
        XCTAssertEqual(PropertySealStyle.monogram("Pine Cabin"), "PC")
        XCTAssertEqual(PropertySealStyle.monogram("The Arroyo Seco Schoolhouse Lofts, Unit 4B"), "AS")
        XCTAssertEqual(PropertySealStyle.monogram("Maple"), "MA")
        XCTAssertEqual(PropertySealStyle.monogram("12 Oak St"), "OS", "skips leading numbers")
    }

    func testPaletteCyclesByCreationOrderSoNeighboursDiffer() {
        let names = ["A", "B", "C", "D", "E", "F"]
        var props: [RentalProperty] = []
        for (i, n) in names.enumerated() {
            var p = RentalProperty(name: n, address: "", propertyType: .ltr)
            p.createdAt = Date(timeIntervalSince1970: TimeInterval(1000 + i))
            props.append(p)
        }
        let palettes = props.map { PropertySealStyle.palette(for: $0, in: props.shuffled()) }
        XCTAssertEqual(palettes, [.blueprint, .timber, .terracotta, .brass, .slate, .blueprint])
    }
}

// MARK: - Delete

@MainActor
final class PropertyDeletionTests: CaptureTestCase {
    func testAlertCopyMatchesWhatDeleteDoes() {
        let p = RentalProperty(name: "Pine Cabin", address: "", propertyType: .str)
        // §1.21: a title of at most six words, at most two sentences, whatever the rental's name.
        let long = RentalProperty(name: "The Arroyo Seco Schoolhouse Lofts, Unit 4B", address: "", propertyType: .ltr)
        for property in [p, long] {
            let d = PropertyDeletion(property: property, entryCount: 41, loggedHours: 34.5)
            XCTAssertEqual(d.title, "Delete this rental?")
            XCTAssertLessThanOrEqual(d.title.split(separator: " ").count, 6)
            XCTAssertEqual(d.message, "\(property.name), its 34h 30m of logged time and any photos go from this device and iCloud. This can’t be undone.")
        }
        let d0 = PropertyDeletion(property: p, entryCount: 0)
        XCTAssertEqual(d0.title, "Delete this rental?")
        XCTAssertEqual(d0.message, "Pine Cabin goes from this device and iCloud. This can’t be undone.")
    }

    func testDeleteGoesThroughTheViewModelAndTombstonesPropertyAndEntries() {
        let (vm, oak) = makeViewModel()
        let trackerDir = FileManager.default.temporaryDirectory.appendingPathComponent("props-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: trackerDir) }
        vm.syncService.changeTrackerBaseDirectory = trackerDir
        vm.addTimeEntry(propertyId: oak, participant: .selfParticipant, category: .repairs, hours: 2, date: Date(), notes: "Sink")
        vm.addTimeEntry(propertyId: oak, participant: .spouse, category: .leasing, hours: 1, date: Date(), notes: "Showing")
        let entryIds = vm.timeEntries.filter { $0.propertyId == oak }.map(\.id.uuidString)
        let property = vm.properties.first { $0.id == oak }!

        let deletion = PropertyDeletion.make(for: property, in: vm)
        XCTAssertEqual(deletion.entryCount, 2)
        XCTAssertEqual(deletion.loggedHours, 3, accuracy: 0.001)
        deletion.perform(in: vm)

        XCTAssertFalse(vm.properties.contains { $0.id == oak })
        XCTAssertFalse(vm.timeEntries.contains { $0.propertyId == oak })
        XCTAssertEqual(Set(vm.syncService.changeTracker!.pendingDeletes), Set([oak.uuidString] + entryIds),
                       "property and its entries are tombstoned for iCloud")
    }
}

// MARK: - Category colour map (one map, app-wide)

final class CategoryInkTests: XCTestCase {
    private func luminance(_ hex: String) -> Double {
        let v = UInt64(hex, radix: 16) ?? 0
        func ch(_ x: UInt64) -> Double {
            let c = Double(x) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * ch((v >> 16) & 0xFF) + 0.7152 * ch((v >> 8) & 0xFF) + 0.0722 * ch(v & 0xFF)
    }

    private func contrast(_ a: String, _ b: String) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func testLeasingIsHarbourBlueEverywhere() {
        XCTAssertEqual(AppColors.categoryInkHex(.leasing).light, "1B6C8C")
        XCTAssertEqual(AppColors.categoryInkHex(.leasing).dark, "7CC6E4")
        XCTAssertNotEqual(AppColors.categoryInkHex(.leasing).light, AppColors.Hex.rose, "rose means spouse")
    }

    func testEveryInkIsReadableOnCards() {
        for category in ActivityCategory.allCases {
            let hex = AppColors.categoryInkHex(category)
            XCTAssertGreaterThanOrEqual(contrast(hex.light, AppColors.Hex.card), 4.5, "\(category) light")
            XCTAssertGreaterThanOrEqual(contrast(hex.dark, AppColors.Hex.darkCard), 4.5, "\(category) dark")
        }
    }

    func testEveryCategoryHasItsOwnTool() {
        let tools = ActivityCategory.allCases.map(\.blueprintToolName)
        XCTAssertEqual(Set(tools).count, ActivityCategory.allCases.count, "no shared stand-in tools")
        for category in ActivityCategory.allCases {
            for size in [36, 56] {
                XCTAssertNotNil(UIImage(named: "bp_tool_\(category.blueprintToolName)_\(size)",
                                        in: Bundle(for: AppViewModel.self), compatibleWith: nil),
                                "bp_tool_\(category.blueprintToolName)_\(size)")
            }
        }
    }
}

// MARK: - Rentals gallery: the pace line under each tile (Brian, 2026-10-26)

final class RentalTilePaceTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func date(_ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: 12))! }
    private func pace(_ hours: Double, goal: Double = 100, record: Bool = false, now: Date? = nil, days: Int = 120) -> RentalTilePace {
        RentalTilePace.make(hours: hours, goal: goal, isRecord: record, year: 2026, now: now ?? date(10, 26), calendar: cal, daysOfData: days)
    }

    func testDoneForTheYearOnceTheGoalIsMet() {
        XCTAssertEqual(pace(100), RentalTilePace(text: "Done for the year", tone: .positive))
        XCTAssertEqual(pace(112).text, "Done for the year")
    }

    func testBehindSaysByHowMuchInTheBehindTone() {
        // 100h × 299/365 expected by Oct 26 (day 299) = 82h; 46h logged is 36h behind.
        let p = pace(46)
        XCTAssertEqual(p.text, "Behind by 36h")
        XCTAssertEqual(p.tone, .behind)
    }

    func testOnPaceWhenAtOrAheadOfTheYearsPace() {
        let p = pace(88)
        XCTAssertEqual(p.text, "On pace")
        XCTAssertEqual(p.tone, .positive)
    }

    func testNoPaceYetSaysWhatAWeekGetsThere() {
        // 8h over 5 days of data: under 10h and under two weeks, so no pace; 92h over ~9.4 weeks left.
        let p = pace(8, days: 5)
        XCTAssertEqual(p.tone, .neutral)
        XCTAssertTrue(p.text.hasSuffix("h a week to go"), p.text)
        XCTAssertEqual(p.text, "10h a week to go")
    }

    func testNoHoursAndRecordAreNeutralPlainWords() {
        XCTAssertEqual(pace(0), RentalTilePace(text: "No hours yet", tone: .neutral))
        XCTAssertEqual(pace(30, goal: 0, record: true), RentalTilePace(text: "Keeping a record", tone: .neutral))
        XCTAssertEqual(pace(30, record: true).text, "Keeping a record")
    }

    func testBadHoursNeverCrash() {
        XCTAssertEqual(pace(.nan).text, "No hours yet")
        XCTAssertEqual(pace(-5).text, "No hours yet")
    }

    func testNoTrailingFullStopsAndNoConfirmCount() {
        for h in [0.0, 8, 46, 88, 100] { XCTAssertFalse(pace(h, days: 120).text.hasSuffix("."), "\(h)") }
    }

    func testTileHoursLineSaysTheGoalOrJustTheHours() {
        let row = RentalRowModel(id: UUID(), name: "Santa Ray Ave", hours: 88.9, goal: 100, lit: false, kind: .str)
        let withGoal = RentalTileModel(row: row, goal: 100, pace: pace(88))
        XCTAssertEqual(withGoal.hoursLine, "88 of 100h")
        XCTAssertEqual(withGoal.spoken, "Santa Ray Ave, 88 of 100h, On pace")
        XCTAssertEqual(RentalTileModel(row: row, goal: 0, pace: pace(88, goal: 0, record: true)).hoursLine, "88h")
    }
}

// MARK: - A rental with no hours draws the first stage the house system defines (shot-bug 6, 2026-10-27)

final class RentalTileZeroHourStageTests: XCTestCase {
    /// §H.3: five stages, `started` is the first and the only one below 20% of the goal. There is no
    /// separate empty-lot render, so 0h (and any bad input) must draw `started`, never a later stage.
    func testZeroHoursDrawsTheFirstStageForEveryGoal() {
        for goal in [100.0, 500, 750] {
            let row = RentalRowModel(id: UUID(), name: "Lakeside A-Frame", hours: 0, goal: goal, lit: false, kind: .ltr)
            XCTAssertEqual(row.stage, CraftStage.allCases.first)
            XCTAssertEqual(row.stage, .started, "goal \(Int(goal))")
            XCTAssertEqual(row.value, "0h")
        }
        for bad in [-5.0, .nan, .infinity] {
            XCTAssertEqual(RentalRowModel(id: UUID(), name: "x", hours: bad, goal: 100, lit: false, kind: .ltr).stage, .started)
        }
    }

    /// The first stage's art exists for light and dark, lit and unlit, and is the lowest stage: the
    /// tile can never show anything earlier than this, so "0h looks half-built" is a missing-art
    /// question (no empty-lot render), not a mapping one.
    func testEveryStageThatAZeroHourTileCouldDrawHasItsArt() {
        let bundle = Bundle(for: AppViewModel.self)
        for lit in [true, false] {
            XCTAssertNotNil(UIImage(named: CraftStage.started.assetName(lit: lit), in: bundle, compatibleWith: nil))
        }
        XCTAssertEqual(CraftStage.stage(hours: 19.9, goal: 100), .started)
        XCTAssertEqual(CraftStage.stage(hours: 20, goal: 100), .frame70)
    }
}

// MARK: - The rental's headline and its breakdown follow the same person (REPS)

@MainActor
final class PropertyRepsParticipantTests: CaptureTestCase {
    private let goals = GoalManager.shared
    private var savedPro: RealEstatePro?

    override func setUp() async throws {
        try await super.setUp()
        savedPro = goals.realEstatePro
    }

    override func tearDown() async throws {
        goals.setGoalSetup(rental: goals.rentalMix, pro: savedPro)
        try await super.tearDown()
    }

    private var year: Int { Calendar.current.component(.year, from: Date()) }

    func testHeadlineAndBreakdownBothUseTheRealEstateProfessional() {
        let (vm, oak) = makeViewModel()
        vm.addTimeEntry(propertyId: oak, participant: .selfParticipant, category: .repairs, hours: 80, date: Date(), notes: "")
        vm.addTimeEntry(propertyId: oak, participant: .spouse, category: .leasing, hours: 30, date: Date(), notes: "")
        vm.addTimeEntry(propertyId: oak, participant: .spouse, category: .investing, hours: 9, date: Date(), notes: "")
        for (pro, who, hours, kinds) in [(RealEstatePro.me, Participant.selfParticipant, 80.0, [ActivityCategory.repairs]),
                                         (.spouse, .spouse, 30.0, [.leasing])] {
            goals.setGoalSetup(rental: goals.rentalMix, pro: pro)
            XCTAssertEqual(goals.repsParticipant, who)
            XCTAssertEqual(vm.propertyCountableHours(oak, goal: .reps750, year: year), hours, accuracy: 0.001, "headline, \(pro)")
            let entries = vm.propertyCountableEntries(oak, goal: .reps750, year: year)
            XCTAssertTrue(entries.allSatisfy { $0.participant == who }, "breakdown entries are \(who)'s only, \(pro)")
            XCTAssertEqual(entries.reduce(0) { $0 + $1.hours }, hours, accuracy: 0.001, "entries sum to the headline, \(pro)")
            let figures = vm.propertyFigures(for: vm.properties[0], goal: .reps750, year: year)
            XCTAssertEqual(figures.kinds.map(\.category), kinds, "kinds, \(pro)")
        }
    }
}
