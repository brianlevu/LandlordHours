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
        // Without a grouping election the best property is Today's number.
        TaxProfileManager.shared.groupingElection = false
        XCTAssertEqual(vm.propertyCountableHours(oak, goal: .mp500), vm.houseCountableHours(goal: .mp500), accuracy: 0.001)

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
        XCTAssertEqual(PropertyHouseStage.keyframe(for: hours), .k00_lot, "the 3 investor hours never pour the slab")
        let kinds = vm.propertyFigures(for: vm.properties.first { $0.id == oak }!, goal: .reps750).kinds
        XCTAssertEqual(kinds.map(\.category), [.repairs])
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

// MARK: - The mini-house stage (same mapping as Today)

final class PropertyHouseStageTests: XCTestCase {
    func testBoundariesOnThe500hLadder() {
        XCTAssertEqual(PropertyHouseStage.keyframe(for: 0), .k00_lot)
        XCTAssertEqual(PropertyHouseStage.keyframe(for: 99), .k00_lot)
        XCTAssertEqual(PropertyHouseStage.keyframe(for: 100), .k01_slab, "slab at 100")
        XCTAssertEqual(PropertyHouseStage.keyframe(for: 499), .k10_frame090)
        XCTAssertEqual(PropertyHouseStage.keyframe(for: 500), .k12_roof, "complete with the roof on at 500")
        XCTAssertEqual(PropertyHouseStage.keyframe(for: 501), .k12_roof, "never past the roof")
        XCTAssertEqual(PropertyHouseStage.keyframe(for: 900), .k12_roof)

        XCTAssertEqual(PropertyHouseStage.stage(for: 0), .emptyLot)
        XCTAssertEqual(PropertyHouseStage.stage(for: 99), .groundwork)
        XCTAssertEqual(PropertyHouseStage.stage(for: 100), .slab)
        XCTAssertEqual(PropertyHouseStage.stage(for: 499), .framing)
        XCTAssertEqual(PropertyHouseStage.stage(for: 500), .roofed)
        XCTAssertEqual(PropertyHouseStage.stage(for: 501), .roofed)
    }

    func testBelow500ItMatchesTodaysKeyframes() {
        for h in stride(from: 0.0, through: 500, by: 0.5) {
            XCTAssertEqual(PropertyHouseStage.keyframe(for: h), HouseProgress.keyframe(for: h), "\(h)h")
        }
        XCTAssertEqual(PropertyHouseStage.keyframe(for: -5), .k00_lot)
        XCTAssertEqual(PropertyHouseStage.keyframe(for: .nan), .k00_lot)
    }

    func testWordingPerGoalAndGrouping() {
        // Material participation, no grouping election: the 500h test runs per rental.
        for goal in [HouseGoal.mp500, .mp100] {
            XCTAssertEqual(PropertyMeta.hoursLine(212, goal: goal, groupingElection: false), "212h of 500h")
            XCTAssertEqual(PropertyMeta.hoursLine(499.9, goal: goal, groupingElection: false), "499h of 500h")
            XCTAssertEqual(PropertyMeta.hoursLine(520, goal: goal, groupingElection: false), "520h · roof’s on")
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
        let d41 = PropertyDeletion(property: p, entryCount: 41)
        XCTAssertEqual(d41.title, "Delete Pine Cabin and its 41 entries?")
        XCTAssertEqual(d41.message, "Its 41 entries and their photos are deleted too, on this iPhone and in iCloud. This can’t be undone.")
        let d1 = PropertyDeletion(property: p, entryCount: 1)
        XCTAssertEqual(d1.title, "Delete Pine Cabin and its 1 entry?")
        let d0 = PropertyDeletion(property: p, entryCount: 0)
        XCTAssertEqual(d0.title, "Delete Pine Cabin?")
        XCTAssertEqual(d0.message, "It’s removed from this iPhone and iCloud. This can’t be undone.")
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
