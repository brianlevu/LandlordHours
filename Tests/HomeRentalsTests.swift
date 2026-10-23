import XCTest
@testable import LandlordHours

// MARK: - Today with several rentals (2.1): the row, the hero per focus, Add up, the stage, layout

final class HomeRentalsTests: XCTestCase {
    private let year = 2026
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 12))!
    // Brian's device, in the order he added them: the default focus is NOT the first rental.
    private let delaney = RentalProperty(name: "Delaney Ct", address: "1", propertyType: .ltr)
    private let santa = RentalProperty(name: "Santa Ray Ave", address: "2", propertyType: .str)
    private let yeandle = RentalProperty(name: "Yeandle Ave", address: "3", propertyType: .ltr)

    private var brianHours: [UUID: Double] { [delaney.id: 84, santa.id: 12, yeandle.id: 0] }

    private func rentals(_ props: [RentalProperty], goal: GoalChoice, grouping: Bool = false,
                         overrides: [UUID: RentalOverride] = [:], who: [UUID: WhoDoesMost] = [:],
                         hours: [UUID: Double], total: Double = 0) -> HomeRentals {
        let ctx = RentalPlanContext(goal: goal, grouping: grouping, properties: props, overrides: overrides, whoDoesMost: who)
        return HomeRentals.make(properties: props, mode: RentalPlanning.mode(ctx), plans: RentalPlanning.plans(ctx),
                                hours: { hours[$0.id] ?? 0 }, totalHours: total)
    }

    private func input(total: Double = 0, goal: HouseGoal = .mp100, answer: @escaping (UUID?) -> Bool? = { _ in nil }) -> HomeHero.Input {
        let copy = TodayHeroCopy.make(.init(goal: goal, hours: total, year: year, now: now, daysOfData: 200))
        return HomeHero.Input(year: year, now: now, daysOfData: 200, answer: answer,
                              totalCopy: copy, totalHours: total, totalGoal: goal, totalFlag: HomeRentals.allRentalsName)
    }

    // MARK: The row

    func testBriansRowListsEveryRentalInListOrderWithNoAllTile() {
        let r = rentals([delaney, santa, yeandle], goal: .mp100, hours: brianHours)
        XCTAssertEqual(r.tiles.map(\.name), ["Delaney Ct", "Santa Ray Ave", "Yeandle Ave"])
        XCTAssertFalse(r.tiles.contains { $0.isAll }, "each rental counts on its own: no shared total")
        XCTAssertTrue(r.showsRow)
        XCTAssertFalse(r.showsSeeAll)
        XCTAssertEqual(r.loggedHours, 96, accuracy: 0.001)
        XCTAssertEqual(r.tile(.rental(santa.id))?.hoursLine, "12 of 100")
        XCTAssertEqual(r.tile(.rental(santa.id))?.tileLine, "100-hour target")
        XCTAssertEqual(r.tile(.rental(delaney.id))?.hoursLine, "84h")
        XCTAssertEqual(r.tile(.rental(delaney.id))?.tileLine, "Record only")
        XCTAssertNil(r.tile(.rental(delaney.id))?.fraction, "no target, no bar")
        XCTAssertEqual(r.tile(.rental(santa.id))?.fraction ?? 0, 0.12, accuracy: 0.0001)
    }

    func testOneRentalShowsNoRow() {
        XCTAssertFalse(rentals([santa], goal: .mp100, hours: brianHours).showsRow)
        XCTAssertFalse(rentals([santa], goal: .reps750, hours: brianHours).showsRow, "the All tile is not a second rental")
    }

    func testSharedTotalPutsAllRentalsFirst() {
        let r = rentals([delaney, santa, yeandle], goal: .reps750, hours: brianHours, total: 212)
        XCTAssertEqual(r.order.first, .all)
        XCTAssertEqual(r.tiles.first?.name, "All rentals")
        XCTAssertEqual(r.tiles.first?.hoursLine, "212 of 750")
        XCTAssertEqual(r.tiles.first?.tileLine, "One shared total")
        XCTAssertEqual(r.tile(.rental(delaney.id))?.tileLine, "Counts toward 750")
        XCTAssertEqual(r.rentalCount, 3)
        let record = rentals([delaney, santa], goal: .record, hours: brianHours, total: 96)
        XCTAssertEqual(record.order.first, .all, "a record also starts on All rentals")
        XCTAssertEqual(record.tiles.first?.tileLine, "Hours kept, no target")
    }

    func testSeeAllFromSixRentals() {
        let five = (0..<5).map { RentalProperty(name: "R\($0)", address: "", propertyType: .ltr) }
        XCTAssertFalse(rentals(five, goal: .mp500, hours: [:]).showsSeeAll)
        let six = five + [RentalProperty(name: "R5", address: "", propertyType: .ltr)]
        XCTAssertTrue(rentals(six, goal: .mp500, hours: [:]).showsSeeAll)
    }

    func testSwipeStepsThroughTheRowAndStopsAtTheEnds() {
        let r = rentals([delaney, santa, yeandle], goal: .reps750, hours: brianHours, total: 96)
        XCTAssertEqual(r.step(from: .all, by: 1), .rental(delaney.id))
        XCTAssertEqual(r.step(from: .rental(yeandle.id), by: -1), .rental(santa.id))
        XCTAssertNil(r.step(from: .all, by: -1))
        XCTAssertNil(r.step(from: .rental(yeandle.id), by: 1))
        XCTAssertEqual(r.focus(at: 0), .all)
        XCTAssertEqual(r.focus(at: 99), .rental(yeandle.id), "clamped")
    }

    func testSpokenLabelsUsePlainWords() {
        let r = rentals([delaney, santa, yeandle], goal: .mp100, who: [delaney.id: .someoneElse], hours: brianHours)
        XCTAssertEqual(r.tile(.rental(santa.id))?.spoken(selected: true),
                       "Santa Ray Ave, 12 of 100 hours, has its own target, selected")
        let delaneyLine = r.tile(.rental(delaney.id))?.spoken ?? ""
        XCTAssertTrue(delaneyLine.hasPrefix("Delaney Ct, 84 hours, record only."), delaneyLine)
        for tile in r.tiles {
            for banned in ["role", "grouping", "election", "qualified"] {
                XCTAssertFalse(tile.spoken.lowercased().contains(banned), "\(banned) in \(tile.spoken)")
                XCTAssertFalse(tile.tileLine.lowercased().contains(banned))
            }
        }
    }

    // MARK: The hero per mode

    func testOwnTargetHeroIsThatRentalsCount() {
        let r = rentals([delaney, santa, yeandle], goal: .mp100, hours: brianHours)
        let hero = HomeHero.make(r, focus: .rental(santa.id), input(total: 12))
        XCTAssertEqual(hero.kind, .ownTarget(santa.id))
        XCTAssertEqual(hero.hours, 12)
        XCTAssertEqual(hero.goal, .mp100)
        XCTAssertEqual(hero.copy.propertyName, "Santa Ray Ave")
        XCTAssertEqual(hero.copy.targetHours, 100)
        XCTAssertEqual(hero.copy.eyebrow, "2026 · Santa Ray Ave · 100-hour target")
        XCTAssertEqual(hero.copy.qualifier, "more than anyone else")
        XCTAssertEqual(hero.flag, "Santa Ray Ave", "the flag and the eyebrow name the same rental")
        XCTAssertEqual(hero.participationPropertyId, santa.id)
        XCTAssertNil(hero.stageTitle)
        XCTAssertTrue(hero.hasTarget)
        XCTAssertEqual(HomeHero.headerLine(hero), "12h toward 100 at Santa Ray Ave.")
    }

    func testAFiveHundredRentalUnderAHundredGoal() {
        // Someone else does most at the cabin: it gets 500, which compares nobody.
        let r = rentals([delaney, santa], goal: .mp100, who: [santa.id: .someoneElse], hours: [santa.id: 230])
        let hero = HomeHero.make(r, focus: .rental(santa.id), input())
        XCTAssertEqual(hero.goal, .mp500)
        XCTAssertEqual(hero.copy.targetHours, 500)
        XCTAssertNil(hero.copy.qualifier)
    }

    func testOwnHundredTargetAsksTheQuestionForThatRentalOnly() {
        let r = rentals([santa, RentalProperty(name: "Cabin", address: "", propertyType: .str)], goal: .mp100,
                        hours: [santa.id: 104])
        let unanswered = HomeHero.make(r, focus: .rental(santa.id), input { _ in nil })
        XCTAssertTrue(unanswered.copy.needsConfirmation)
        let answered = HomeHero.make(r, focus: .rental(santa.id), input { id in id == self.santa.id ? true : nil })
        XCTAssertFalse(answered.copy.needsConfirmation)
        XCTAssertTrue(answered.copy.claimsReached)
    }

    func testRecordOnlyHeroIsAPlainLotWithNoPace() {
        let r = rentals([delaney, santa, yeandle], goal: .mp100, who: [delaney.id: .someoneElse], hours: brianHours)
        let hero = HomeHero.make(r, focus: .rental(delaney.id), input())
        XCTAssertEqual(hero.kind, .recordOnly(delaney.id))
        XCTAssertEqual(hero.hours, 84)
        XCTAssertEqual(hero.stageHours, 0, "a plain lot")
        XCTAssertEqual(hero.stageTitle, "Hours kept, no target")
        XCTAssertEqual(hero.copy.qualifier, RentalPlanWords.reason(.someoneElse))
        XCTAssertNil(hero.copy.targetHours)
        XCTAssertNil(hero.copy.phrase, "no pace")
        XCTAssertFalse(hero.hasTarget)
        XCTAssertEqual(hero.flag, "Delaney Ct")
        XCTAssertNil(HomeHero.headerLine(hero))
    }

    func testSharedModeRentalShowsItsPartOfTheTotal() {
        let r = rentals([delaney, santa, yeandle], goal: .reps750, hours: brianHours, total: 212)
        let all = HomeHero.make(r, focus: .all, input(total: 212, goal: .reps750))
        XCTAssertEqual(all.kind, .total)
        XCTAssertEqual(all.hours, 212)
        XCTAssertEqual(all.flag, "All rentals")
        let part = HomeHero.make(r, focus: .rental(delaney.id), input(total: 212, goal: .reps750))
        XCTAssertEqual(part.kind, .sharedPart(delaney.id))
        XCTAssertEqual(part.hours, 84)
        XCTAssertEqual(part.copy.phrase, "212 of 750 in all")
        XCTAssertEqual(part.stageTitle, "Counts toward the shared total")
        XCTAssertEqual(part.stageHours, 0)
        XCTAssertNil(part.participationPropertyId)
    }

    func testAddingUpSumsTheNamesWithNoTarget() {
        let r = rentals([delaney, santa, yeandle], goal: .mp100, hours: brianHours)
        let one = HomeHero.make(r, focus: .rental(santa.id), summed: [delaney.id], input())
        XCTAssertEqual(one.kind, .ownTarget(santa.id), "one pick is not a sum yet")
        let two = HomeHero.make(r, focus: .rental(santa.id), summed: [delaney.id, santa.id], input())
        XCTAssertEqual(two.kind, .sum([delaney.id, santa.id]))
        XCTAssertEqual(two.hours, 96)
        XCTAssertEqual(two.copy.phrase, "Delaney Ct + Santa Ray Ave")
        XCTAssertEqual(two.copy.caption, "hours combined")
        XCTAssertNil(two.copy.targetHours)
        XCTAssertEqual(two.stageHours, 0)
        XCTAssertEqual(two.flag, "2 rentals")
        let three = HomeHero.make(r, focus: .all, summed: [delaney.id, santa.id, yeandle.id], input())
        XCTAssertEqual(three.copy.phrase, "Delaney Ct + Santa Ray Ave + 1 more")
    }

    // MARK: Add up

    func testSelectionTapsFocusOrPick() {
        var s = HomeSelection()
        XCTAssertEqual(s.tap(.rental(santa.id)), .focus(.rental(santa.id)))
        s.toggleSum(focus: .rental(santa.id))
        XCTAssertTrue(s.summing)
        XCTAssertEqual(s.summed, [santa.id], "starts with the focused rental")
        XCTAssertEqual(s.sumIds, [], "one pick: no sum yet")
        XCTAssertEqual(s.tap(.rental(delaney.id)), .picked)
        XCTAssertEqual(s.sumIds, [santa.id, delaney.id])
        XCTAssertTrue(s.isSelected(.rental(delaney.id), focus: .rental(santa.id)))
        XCTAssertFalse(s.showsFullHouse(.rental(santa.id), focus: .rental(santa.id)), "no full house while adding up")
        XCTAssertEqual(s.tap(.rental(delaney.id)), .picked)
        XCTAssertEqual(s.summed, [santa.id])
        XCTAssertEqual(s.tap(.all), .focus(.all))
        XCTAssertFalse(s.summing, "All rentals leaves adding up")
        s.toggleSum(focus: .all)
        XCTAssertEqual(s.summed, [])
        s.toggleSum(focus: .all)
        XCTAssertFalse(s.summing, "Done")
    }

    // MARK: One stage function

    func testHeroAndTileShowTheSameHouse() {
        // Two long-stay rentals under 500: each has its own target.
        let r = rentals([delaney, yeandle], goal: .mp500, hours: [delaney.id: 640, yeandle.id: 120])
        for tile in r.tiles {
            let hero = HomeHero.make(r, focus: tile.focus, input(goal: .mp500))
            XCTAssertEqual(hero.stageHours, tile.stageHours, tile.name)
        }
        XCTAssertEqual(r.tile(.rental(delaney.id))?.stageHours, 500, "own target pins at the 500 line")
        XCTAssertEqual(HomeStage.hours(track: .sharedTotal(hours: 750), hours: 640, isAll: true), 640, "All rentals is unpinned")
        XCTAssertEqual(HomeStage.hours(track: .sharedTotal(hours: 750), hours: 640, isAll: false), 0, "a rental's part is a plain lot")
        XCTAssertEqual(HomeStage.hours(track: .recordOnly(.longStays), hours: 80, isAll: false), 0)
    }

    // MARK: Layout

    func testRowAlwaysLeavesTheLastTilePeeking() {
        for width in [320.0, 354.0, 392.0, 420.0, 700.0] {
            let w = HomeLayout.tileWidth(rowWidth: width)
            XCTAssertGreaterThanOrEqual(w, 96)
            XCTAssertLessThanOrEqual(w, 132)
        }
        let phone = HomeLayout.tileWidth(rowWidth: 392)
        let used = 3 * phone + 3 * 10
        XCTAssertLessThan(used, 392, "three tiles visible")
        XCTAssertGreaterThan(used + 64, 392, "the next tile is cut by the edge")
    }

    func testAccessibilitySizesUseTheList() {
        XCTAssertTrue(HomeLayout.usesList(isAccessibilitySize: true))
        XCTAssertFalse(HomeLayout.usesList(isAccessibilitySize: false))
        XCTAssertEqual(HomeLayout.listLimit, 3)
    }

    // MARK: Widget words

    func testWidgetNamesTheFocusedRental() {
        var snap = WidgetSurfaceSnapshot.empty
        snap.propertyCount = 3; snap.hours = 12; snap.goal = .mp100; snap.goalHours = 100; snap.requiredHoursToDate = 81
        snap.focusName = "Santa Ray Ave"
        let d = WidgetSurfaceDisplay(snapshot: snap)
        XCTAssertEqual(d.smallLabel, "Santa Ray Ave")
        XCTAssertEqual(d.mediumLabel, "Santa Ray Ave · \(snap.taxYear)")
        XCTAssertTrue(d.accessibilityLabel.hasPrefix("Santa Ray Ave, 12 of 100 hours."), d.accessibilityLabel)
        snap.focusName = nil
        XCTAssertEqual(WidgetSurfaceDisplay(snapshot: snap).smallLabel, "Your hours")
    }

    func testWidgetSnapshotWithoutFocusStillDecodes() throws {
        var old = WidgetSurfaceSnapshot.empty
        old.focusName = "Gone"
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "focusName")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(WidgetSurfaceSnapshot.self, from: data)
        XCTAssertNil(decoded.focusName, "a 2.0.x snapshot decodes")
        XCTAssertEqual(decoded.stageTitle, old.stageTitle)
    }
}

// MARK: - On the real view model: the default focus, a deleted rental, the widget

@MainActor
final class HomeFocusIntegrationTests: CaptureTestCase {
    private var savedChoice: GoalChoice = .reps750
    private var savedSpouse = false
    private var savedGrouping = false
    private var year: Int { Calendar.current.component(.year, from: Date()) }

    override func setUp() async throws {
        try await super.setUp()
        savedChoice = GoalManager.shared.goalChoice
        savedSpouse = TaxProfileManager.shared.spouseTracking
        savedGrouping = TaxProfileManager.shared.groupingElection
        RentalPlanStore.shared.reload()
        RentalPlanStore.shared.resetAll()
        TaxProfileManager.shared.spouseTracking = false
        TaxProfileManager.shared.groupingElection = false
        GoalManager.shared.setGoalChoice(.mp100)
    }

    override func tearDown() async throws {
        RentalPlanStore.shared.resetAll()
        GoalManager.shared.setGoalChoice(savedChoice)
        TaxProfileManager.shared.spouseTracking = savedSpouse
        TaxProfileManager.shared.groupingElection = savedGrouping
        try await super.tearDown()
    }

    /// Brian's device: Delaney Ct (long stays, 84h), Santa Ray Ave (a few nights, 12h), Yeandle Ave.
    private func briansDevice() -> (AppViewModel, RentalProperty, RentalProperty, RentalProperty) {
        let vm = AppViewModel()
        vm.suppressCelebrations = true
        vm.addProperty(name: "Delaney Ct", address: "1", type: .ltr)
        vm.addProperty(name: "Santa Ray Ave", address: "2", type: .str)
        vm.addProperty(name: "Yeandle Ave", address: "3", type: .ltr)
        let d = vm.properties.first { $0.name == "Delaney Ct" }!
        let s = vm.properties.first { $0.name == "Santa Ray Ave" }!
        let y = vm.properties.first { $0.name == "Yeandle Ave" }!
        vm.addTimeEntry(propertyId: d.id, participant: .selfParticipant, category: .repairs, hours: 84, date: Date(), notes: "")
        vm.addTimeEntry(propertyId: s.id, participant: .selfParticipant, category: .repairs, hours: 12, date: Date(), notes: "")
        return (vm, d, s, y)
    }

    func testDefaultFocusIsNotTheFirstAddedRental() {
        let (vm, d, s, _) = briansDevice()
        XCTAssertEqual(vm.properties.first?.id, d.id)
        XCTAssertEqual(vm.resolvedTodayFocus(year: year), .rental(s.id))
        XCTAssertEqual(vm.todayFocusProperty(year: year)?.name, "Santa Ray Ave")
    }

    func testChosenFocusSticksAndFallsBackWhenTheRentalIsDeleted() {
        let (vm, d, s, _) = briansDevice()
        RentalPlanStore.shared.setFocus(rental: d.id)
        XCTAssertEqual(vm.resolvedTodayFocus(year: year), .rental(d.id))
        RentalPlanStore.shared.reload()
        XCTAssertEqual(vm.resolvedTodayFocus(year: year), .rental(d.id), "survives a relaunch")
        vm.deleteProperty(d)
        XCTAssertEqual(vm.resolvedTodayFocus(year: year), .rental(s.id), "a deleted rental falls back to the default")
    }

    func testWidgetFollowsTheFocus() {
        let (vm, d, s, _) = briansDevice()
        let snap = vm.widgetSurfaceSnapshot(now: Date(), suggestions: [])
        XCTAssertEqual(snap.focusName, "Santa Ray Ave")
        XCTAssertEqual(snap.hours, 12, accuracy: 0.001)
        XCTAssertEqual(snap.goalHours, 100)
        RentalPlanStore.shared.setFocus(rental: d.id)
        let record = vm.widgetSurfaceSnapshot(now: Date(), suggestions: [])
        XCTAssertNil(record.focusName, "a record-only rental has no target: the widget keeps the total")
        RentalPlanStore.shared.setOverride(.record, for: s.id)
        RentalPlanStore.shared.setOverride(.track, for: d.id)
        let delaney = vm.widgetSurfaceSnapshot(now: Date(), suggestions: [])
        XCTAssertEqual(delaney.focusName, "Delaney Ct")
        XCTAssertEqual(delaney.hours, 84, accuracy: 0.001)
    }

    func testOneRentalWidgetKeepsItsTwoOhWords() {
        let vm = AppViewModel()
        vm.suppressCelebrations = true
        vm.addProperty(name: "Cabin", address: "1", type: .str)
        vm.addTimeEntry(propertyId: vm.properties[0].id, participant: .selfParticipant, category: .repairs, hours: 5, date: Date(), notes: "")
        let snap = vm.widgetSurfaceSnapshot(now: Date(), suggestions: [])
        XCTAssertNil(snap.focusName, "one rental: no name on the widget, as in 2.0")
        XCTAssertEqual(snap.hours, 5, accuracy: 0.001)
    }
}
