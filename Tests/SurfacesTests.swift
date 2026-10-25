import XCTest
import UIKit
import UserNotifications
@testable import LandlordHours

// MARK: - 2.0 surfaces: widget entries, notification copy, the one toast queue
//
// Copy source: ~/AgentScratch/landlordhours/2026-10-19/surfaces/copy-sheet.md.

// MARK: Widget display (pure)

final class WidgetSurfaceDisplayTests: XCTestCase {
    private func snapshot(
        properties: Int = 1,
        hours: Double = 212,
        goal: WidgetSurfaceSnapshot.Goal = .reps750,
        goalHours: Double = 750,
        required: Double = 600,
        pending: Int = 3,
        timer: Date? = nil,
        timerName: String? = nil,
        paceReady: Bool = true,
        record: Bool = false,
        rentals: [WidgetRentalFigure] = [],
        rows: [WidgetConfirmRow] = []
    ) -> WidgetSurfaceSnapshot {
        WidgetSurfaceSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100), taxYear: 2026, propertyCount: properties,
            hours: hours, goal: goal, goalHours: goalHours, requiredHoursToDate: required,
            pendingCount: pending, timerStart: timer, timerPropertyName: timerName,
            houseKeyframe: "", stageTitle: "Frame going up", nextStepLabel: "",
            houseStage: "craft_frame70", loggedToday: true, paceReady: paceReady, isRecord: record,
            rentals: rentals, confirmRows: rows
        )
    }

    private func rentals(_ behind: [Double]) -> [WidgetRentalFigure] {
        behind.enumerated().map { WidgetRentalFigure(id: "r\($0.offset)", name: "Rental \($0.offset)", hours: 100, stage: "craft_started", lit: $0.offset == 0, behindBy: $0.element) }
    }

    func testBehindWithThreeToConfirm() {
        let d = WidgetSurfaceDisplay(snapshot: snapshot())
        XCTAssertEqual(d.state, .behind(gap: 388))
        XCTAssertEqual(d.number, "212")
        XCTAssertEqual(d.caption, "of 750 hours")
        XCTAssertEqual(d.hoursLine, "212 of 750 hours")
        XCTAssertEqual(d.status?.text, "Behind by 388 hours")
        XCTAssertEqual(d.status?.tone, .behind)
        XCTAssertEqual(d.pill?.text, "3 to confirm")
        XCTAssertEqual(d.pill?.url, WidgetLinks.inbox)
        XCTAssertEqual(d.inlineText(elapsed: ""), "212 hours · 3 to confirm")
        XCTAssertEqual(d.rectangularHeadline(elapsed: ""), "212 of 750 hours")
        XCTAssertEqual(d.rectangularLine, "3 to confirm")
        XCTAssertEqual(d.pendingFace.text, "3")
        XCTAssertTrue(d.hasRing)
        XCTAssertEqual(d.progress, 212.0 / 750.0, accuracy: 0.0001)
        XCTAssertEqual(d.url, WidgetLinks.inbox)
    }

    func testOneHourGapReadsOneHourNotHours() {
        let d = WidgetSurfaceDisplay(snapshot: snapshot(hours: 599, required: 600, pending: 0))
        XCTAssertEqual(d.status?.text, "Behind by 1 hour")
    }

    func testOnPaceAndCaughtUpShowsTheStage() {
        let d = WidgetSurfaceDisplay(snapshot: snapshot(hours: 640, required: 600, pending: 0))
        XCTAssertEqual(d.state, .onPace)
        XCTAssertEqual(d.status?.text, "On pace")
        XCTAssertEqual(d.status?.tone, .positive)
        XCTAssertNil(d.pill, "Nothing waits: the stage line, not a pill")
        XCTAssertEqual(d.stageLine, "Frame going up")
        XCTAssertEqual(d.rectangularLine, "On pace")
        XCTAssertEqual(d.pendingFace.text, "Done")
        XCTAssertEqual(d.inlineText(elapsed: ""), "640 of 750 hours")
        XCTAssertEqual(d.url, WidgetLinks.today)
    }

    func testPaceIsTodaysRuleNotASlackBand() {
        // Behind once the rounded gap is an hour or more, exactly like TodayPaceSentence.
        XCTAssertEqual(WidgetSurfaceDisplay(snapshot: snapshot(hours: 599.6, required: 600, pending: 0)).state, .onPace)
        XCTAssertEqual(WidgetSurfaceDisplay(snapshot: snapshot(hours: 599.4, required: 600, pending: 0)).state, .behind(gap: 1))
        XCTAssertEqual(WidgetSurfaceDisplay(snapshot: snapshot(hours: 594.5, required: 600, pending: 0)).state, .behind(gap: 6))
    }

    func testPaceWaitsForTwoWeeksOrTenHours() {
        let d = WidgetSurfaceDisplay(snapshot: snapshot(hours: 6, required: 40, pending: 0, paceReady: false))
        XCTAssertEqual(d.state, .paceNotReady)
        XCTAssertEqual(d.status?.text, "Log a few weeks to see your pace")
        XCTAssertEqual(d.status?.tone, .neutral)
        let withPending = WidgetSurfaceDisplay(snapshot: snapshot(hours: 6, required: 40, pending: 2, paceReady: false))
        XCTAssertEqual(withPending.status?.text, "Confirm your found hours to see your pace")
    }

    func testEmptyIsNeutralNeverDone() {
        let d = WidgetSurfaceDisplay(snapshot: snapshot(hours: 0, required: 300, pending: 0))
        XCTAssertEqual(d.state, .empty)
        XCTAssertEqual(d.status?.text, "No hours yet")
        XCTAssertEqual(d.inlineText(elapsed: ""), "0 of 750 hours")
        XCTAssertEqual(d.pendingFace.text, "–", "A new user never sees Done")
    }

    func testNoProperty() {
        let d = WidgetSurfaceDisplay(snapshot: snapshot(properties: 0, hours: 0, pending: 0))
        XCTAssertEqual(d.state, .noProperty)
        XCTAssertNil(d.status)
        XCTAssertEqual(d.pill?.text, "Add a rental")
        XCTAssertEqual(d.caption, "Add a rental to start counting.")
        XCTAssertEqual(d.inlineText(elapsed: ""), "Add a rental")
        XCTAssertEqual(d.rectangularLine, "to start counting")
        XCTAssertEqual(d.pendingFace.text, "Add")
        XCTAssertEqual(d.hoursFace.symbol, "plus")
        XCTAssertFalse(d.hasRing)
        XCTAssertEqual(d.url, WidgetLinks.addProperty)
    }

    func testGoalMetNeedsMoreThanTheGoal() {
        XCTAssertEqual(WidgetSurfaceDisplay(snapshot: snapshot(hours: 750, required: 700, pending: 0)).state, .onPace,
                       "The law says MORE than 750")
        let d = WidgetSurfaceDisplay(snapshot: snapshot(hours: 768, required: 700, pending: 1))
        XCTAssertEqual(d.state, .met)
        XCTAssertEqual(d.status?.text, "Done for 2026")
        XCTAssertEqual(d.inlineText(elapsed: ""), "750 hours reached")
        XCTAssertEqual(d.hoursFace.symbol, "checkmark")
        XCTAssertEqual(d.rectangularLine, "1 to confirm")
    }

    func testMaterialParticipationGoalWords() {
        let d = WidgetSurfaceDisplay(snapshot: snapshot(hours: 520, goal: .mp500, goalHours: 500, required: 400, pending: 0))
        XCTAssertEqual(d.state, .met)
        XCTAssertEqual(d.status?.text, "500 hours reached", "The MP-500 house is not finished at 520h")
        XCTAssertEqual(d.caption, "of 500 hours")
    }

    func testRecordHasNoGoalAndNoPace() {
        let d = WidgetSurfaceDisplay(snapshot: snapshot(hours: 300, required: 600, pending: 0, record: true))
        XCTAssertEqual(d.caption, "hours logged in 2026")
        XCTAssertEqual(d.state, .onPace, "A record is never behind")
        XCTAssertEqual(d.status?.text, "On your 2026 record")
        XCTAssertFalse(d.hasRing)
        XCTAssertEqual(d.inlineText(elapsed: ""), "300 hours in 2026")
    }

    func testTimerWins() {
        let start = Date(timeIntervalSince1970: 1_000)
        let d = WidgetSurfaceDisplay(snapshot: snapshot(timer: start, timerName: "Pine Cabin"))
        XCTAssertEqual(d.state, .timer)
        XCTAssertEqual(d.pill?.text, "Stop and review")
        XCTAssertEqual(d.status?.text, "Pine Cabin")
        XCTAssertEqual(d.inlineText(elapsed: "0:42"), "Timer 0:42 · Pine Cabin")
        XCTAssertEqual(d.rectangularLine, "Stop it to review")
        XCTAssertEqual(d.url, WidgetLinks.logTime)
        XCTAssertEqual(WidgetSurfaceDisplay.elapsedText(from: start, to: start.addingTimeInterval(42 * 60 + 59)), "0:42")
        XCTAssertEqual(WidgetSurfaceDisplay.elapsedText(from: start, to: start.addingTimeInterval(4 * 3600 + 12 * 60)), "4:12")
    }

    func testNumberNeverRunsAheadOfTheRecords() {
        XCTAssertEqual(WidgetSurfaceDisplay(snapshot: snapshot(hours: 212.9)).number, "212")
    }

    // MARK: All rentals (H10): hours across them, how many are behind, never a goal or a stage

    func testAllRentalsNeverShowsASummedGoal() {
        let d = WidgetSurfaceDisplay(snapshot: snapshot(properties: 3, hours: 312, pending: 0, rentals: rentals([388, 526, 0])))
        XCTAssertEqual(d.state, .allRentals(behind: 2))
        XCTAssertTrue(d.isAllRentals)
        XCTAssertEqual(d.caption, "hours across 3 rentals")
        XCTAssertNil(d.stageLine, "No stage for all rentals")
        XCTAssertEqual(d.hoursLine, "312 hours across 3 rentals")
        XCTAssertEqual(d.status?.text, "2 of 3 behind")
        XCTAssertEqual(d.status?.tone, .behind)
        XCTAssertFalse(d.hasRing, "No ring: there is no goal for all rentals")
        XCTAssertEqual(d.progress, 0)
        XCTAssertEqual(d.inlineText(elapsed: ""), "312 hours · 3 rentals")
        for text in [d.caption, d.hoursLine, d.status?.text ?? "", d.rectangularLine, d.inlineText(elapsed: ""), d.accessibilityLabel] {
            XCTAssertFalse(text.contains("750"), "A summed goal in: \(text)")
        }
    }

    func testAllRentalsOnPace() {
        let d = WidgetSurfaceDisplay(snapshot: snapshot(properties: 2, hours: 1250, pending: 0, rentals: rentals([0, 0])))
        XCTAssertEqual(d.state, .allRentals(behind: 0))
        XCTAssertEqual(d.status?.text, "All on pace")
        XCTAssertEqual(d.status?.tone, .positive)
    }

    func testSkylineIsTodaysRule() {
        // 4 houses under 290, 5 at 290 or more, never under 44, never more than fit at 44.
        XCTAssertEqual(WidgetSkyline.cap(frame: 400), 5)
        XCTAssertEqual(WidgetSkyline.cap(frame: 220), 4)
        XCTAssertEqual(WidgetSkyline.cap(frame: 150), 3, "Four 44pt houses do not fit in 150")
        XCTAssertEqual(WidgetSkyline.houseSide(frame: 150, count: 3), 44, accuracy: 0.01, "Never under 44")
        XCTAssertGreaterThanOrEqual(WidgetSkyline.houseSide(frame: 100, count: 5), 44)
        XCTAssertEqual(WidgetSkyline.houseSide(frame: 400, count: 1), 168, accuracy: 0.01)
        // Over the cap: the most-behind rentals show first, in the shelf's order.
        let eight = (0..<8).map { WidgetRentalFigure(id: "r\($0)", name: "R\($0)", hours: 0, stage: "craft_started", lit: false, behindBy: Double($0 == 6 ? 900 : ($0 == 2 ? 700 : $0))) }
        let shown = WidgetSkyline.visible(eight, frame: 150).map(\.id)
        XCTAssertEqual(shown, ["r2", "r6", "r7"])
    }

    func testHouseArtNamesFollowTheStageAndTheLitState() {
        XCTAssertEqual(WidgetHouseArt.assetName(stage: "craft_half", lit: true), "wg_thumb_half")
        XCTAssertEqual(WidgetHouseArt.assetName(stage: "craft_complete", lit: false), "wg_thumb_complete-unlit")
        XCTAssertEqual(WidgetHouseArt.assetName(stage: "k07_frame060", lit: true), "wg_thumb_started", "An unknown stage draws the first one")
        for stage in ["started", "frame70", "framing", "half", "complete"] {
            for lit in [true, false] {
                XCTAssertNotNil(UIImage(named: WidgetHouseArt.assetName(stage: "craft_" + stage, lit: lit)), "\(stage) lit=\(lit)")
            }
        }
    }

    func testMidnightPutsTheLightsOut() {
        let lit = snapshot(properties: 2, hours: 100, rentals: rentals([0, 0]))
        XCTAssertTrue(lit.loggedToday)
        XCTAssertTrue(lit.rentals[0].lit)
        let next = lit.nextDay()
        XCTAssertFalse(next.loggedToday)
        XCTAssertTrue(next.rentals.allSatisfy { !$0.lit })
        XCTAssertEqual(next.hours, lit.hours)
    }

    // MARK: To confirm rows (large)

    func testConfirmRowDetailLines() {
        let d = WidgetSurfaceDisplay(snapshot: snapshot())
        XCTAssertEqual(d.detail(for: WidgetConfirmRow(key: "a", title: "x", rentalName: "Pine Cabin", hours: 1.5)), "Pine Cabin · 1.5h")
        XCTAssertEqual(d.detail(for: WidgetConfirmRow(key: "a", title: "x", rentalName: "Pine Cabin", hours: 2)), "Pine Cabin · 2h")
        XCTAssertEqual(d.detail(for: WidgetConfirmRow(key: "a", title: "x", rentalName: nil, hours: nil, canConfirm: false)), "Not sure yet")
    }

    // MARK: Storage

    func testStoreRoundTripsAndFallsBackToEmpty() {
        let suite = "WidgetSurfaceStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(WidgetSurfaceStore.load(from: defaults), .empty)
        let s = snapshot(timer: Date(timeIntervalSince1970: 5), timerName: "Oak", rentals: rentals([3]),
                         rows: [WidgetConfirmRow(key: "k", title: "Plumber", rentalName: "Oak", hours: 2)])
        WidgetSurfaceStore.save(s, to: defaults)
        XCTAssertEqual(WidgetSurfaceStore.load(from: defaults), s)
    }

    func testASnapshotAnOlderBuildStoredStillLoads() throws {
        // What 2.0.x wrote: no stage, lit, pace, record, rentals or rows.
        let old = """
        {"updatedAt": 100, "taxYear": 2026, "propertyCount": 2, "hours": 212, "goal": "reps", "goalHours": 750,
         "requiredHoursToDate": 600, "pendingCount": 3, "houseKeyframe": "k05_frame040",
         "stageTitle": "Frame going up", "nextStepLabel": "Roof at 500h"}
        """
        let s = try JSONDecoder().decode(WidgetSurfaceSnapshot.self, from: Data(old.utf8))
        XCTAssertEqual(s.hours, 212)
        XCTAssertEqual(s.houseStage, "craft_started")
        XCTAssertFalse(s.loggedToday)
        XCTAssertTrue(s.paceReady)
        XCTAssertTrue(s.rentals.isEmpty)
        XCTAssertTrue(s.confirmRows.isEmpty)
        XCTAssertEqual(WidgetSurfaceDisplay(snapshot: s).houses.count, 1, "Two rentals recorded, none listed: one house, not a crash")
    }

    func testNoBannedWordsInAnyWidgetString() {
        let cases = [
            snapshot(), snapshot(hours: 640, pending: 0), snapshot(hours: 0, pending: 0), snapshot(properties: 0, hours: 0, pending: 0),
            snapshot(hours: 800), snapshot(timer: Date(), timerName: "Pine"), snapshot(hours: 6, pending: 0, paceReady: false),
            snapshot(properties: 3, hours: 312, rentals: rentals([4, 0, 9])), snapshot(hours: 300, record: true),
        ]
        for s in cases {
            let d = WidgetSurfaceDisplay(snapshot: s)
            let strings = [d.caption, d.hoursLine, d.status?.text ?? "", d.pill?.text ?? "", d.inlineText(elapsed: "0:01"), d.stageLine ?? "",
                           d.rectangularTitle, d.rectangularHeadline(elapsed: "0:01"), d.rectangularLine, d.accessibilityLabel,
                           d.pendingFace.accessibilityLabel, d.hoursFace.accessibilityLabel, d.toConfirmText]
            for text in strings {
                for banned in ["evidence", "qualif", "audit", "tax-ready", "Track", "Home", "property", "REPS", "Behind by 1 hours"] {
                    XCTAssertFalse(text.localizedCaseInsensitiveContains(banned), "\(banned) in \(text)")
                }
                XCTAssertFalse(text.contains("'"), "Curly apostrophes only: \(text)")
            }
        }
    }
}

// MARK: Widget entries from real data (spouse rules, counts, goal met)

@MainActor
final class WidgetSurfaceBuilderTests: CaptureTestCase {
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

    private func seeded(selfHours: Double = 70, spouseHours: Double = 40) -> (AppViewModel, UUID) {
        let (vm, property) = makeViewModel()
        vm.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs, hours: selfHours, date: Date(), notes: "")
        vm.addTimeEntry(propertyId: property, participant: .spouse, category: .leasing, hours: spouseHours, date: Date(), notes: "")
        return (vm, property)
    }

    func testRepsCountsOnlyYourOwnHoursEvenWhenTrackedJointly() {
        GoalManager.shared.globalGoalType = .reps
        TaxProfileManager.shared.spouseTracking = true
        let (vm, _) = seeded()
        let s = vm.widgetSurfaceSnapshot(suggestions: [])
        XCTAssertEqual(s.goal, .reps750)
        XCTAssertEqual(s.hours, 70, accuracy: 0.001, "IRC 469(c)(7)(B): one spouse alone")
        XCTAssertEqual(s.hours, vm.houseCountableHours(), accuracy: 0.001, "Same number as Today's house")
    }

    func testMaterialParticipationCombinesOnlyWhenTrackedJointly() {
        GoalManager.shared.globalGoalType = .str
        TaxProfileManager.shared.spouseTracking = true
        let (vm, _) = seeded()
        XCTAssertEqual(vm.widgetSurfaceSnapshot(suggestions: []).hours, 110, accuracy: 0.001)
        TaxProfileManager.shared.spouseTracking = false
        XCTAssertEqual(vm.widgetSurfaceSnapshot(suggestions: []).hours, 70, accuracy: 0.001)
    }

    func testPendingCountIsTheInboxBadgeCount() {
        let (vm, property) = seeded()
        let now = Date()
        let pending = [
            calendarSuggestion(externalId: "A", start: now.addingTimeInterval(-7200), propertyId: property),
            calendarSuggestion(externalId: "B", start: now.addingTimeInterval(-10800), propertyId: property),
        ]
        var future = calendarSuggestion(externalId: "C", start: now.addingTimeInterval(3600), propertyId: property)
        future.detectedAt = now.addingTimeInterval(7200)
        var done = calendarSuggestion(externalId: "D", start: now.addingTimeInterval(-3600), propertyId: property)
        done.state = .dismissed(reason: .notLandlordWork)
        let all = pending + [future, done]
        let s = vm.widgetSurfaceSnapshot(now: now, suggestions: all)
        XCTAssertEqual(s.pendingCount, InboxLogic.visible(all, now: now).count)
        XCTAssertEqual(s.pendingCount, 2)
    }

    func testGoalMetAndTheHouseStage() {
        GoalManager.shared.globalGoalType = .reps
        let (vm, _) = seeded(selfHours: 760, spouseHours: 0)
        let s = vm.widgetSurfaceSnapshot(suggestions: [])
        XCTAssertEqual(s.houseStage, CraftStage.complete.rawValue)
        XCTAssertEqual(WidgetSurfaceDisplay(snapshot: s).state, .met)
        XCTAssertEqual(s.stageTitle, CraftStage.complete.spokenName)
        XCTAssertTrue(s.loggedToday, "Hours were logged today, so the windows are lit")
        XCTAssertEqual(s.rentals.map(\.stage), [CraftStage.complete.rawValue])
    }

    func testWindowsAreLitOnlyWhenHoursWereLoggedToday() {
        GoalManager.shared.globalGoalType = .reps
        let (vm, property) = makeViewModel()
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        vm.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs, hours: 3, date: yesterday, notes: "")
        XCTAssertFalse(vm.widgetSurfaceSnapshot(now: now, suggestions: []).loggedToday)
        XCTAssertFalse(vm.widgetSurfaceSnapshot(now: now, suggestions: []).rentals[0].lit)
        vm.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs, hours: 1, date: now, notes: "")
        let s = vm.widgetSurfaceSnapshot(now: now, suggestions: [])
        XCTAssertTrue(s.loggedToday)
        XCTAssertTrue(s.rentals[0].lit)
    }

    func testTwoRentalsAreSummedWithEachOwnHouse() {
        GoalManager.shared.globalGoalType = .reps
        let (vm, first) = makeViewModel()
        vm.addProperty(name: "Maple", address: "2 Maple St", type: .ltr)
        let second = vm.properties[1].id
        let now = Date()
        vm.addTimeEntry(propertyId: first, participant: .selfParticipant, category: .repairs, hours: 200, date: now, notes: "")
        vm.addTimeEntry(propertyId: second, participant: .selfParticipant, category: .repairs, hours: 40, date: Calendar.current.date(byAdding: .day, value: -3, to: now)!, notes: "")
        let s = vm.widgetSurfaceSnapshot(now: now, suggestions: [])
        XCTAssertEqual(s.rentals.count, 2)
        XCTAssertEqual(s.hours, s.rentals.reduce(0) { $0 + $1.hours }, accuracy: 0.001, "Today's All rentals number")
        XCTAssertEqual(s.rentals.map(\.lit), [true, false], "Each rental has its own lit state")
        XCTAssertEqual(s.rentals[0].stage, CraftStage.stage(hours: s.rentals[0].hours, goal: 750).rawValue)
        XCTAssertTrue(WidgetSurfaceDisplay(snapshot: s).isAllRentals)
    }

    func testToConfirmRowsAreNewestFirstAndSayWhetherOneTapCanLogThem() {
        let (vm, property) = seeded()
        let now = Date()
        let rows = [
            calendarSuggestion(externalId: "old", start: now.addingTimeInterval(-86_400), title: "Older", propertyId: property),
            calendarSuggestion(externalId: "new", start: now.addingTimeInterval(-7200), title: "Newer", propertyId: property, hours: 2),
            calendarSuggestion(externalId: "vague", start: now.addingTimeInterval(-10_800), title: "Vague", propertyId: nil, hours: nil, category: nil),
        ]
        let s = vm.widgetSurfaceSnapshot(now: now, suggestions: rows)
        XCTAssertEqual(s.confirmRows.map(\.title), ["Newer", "Vague", "Older"])
        XCTAssertEqual(s.confirmRows.map(\.canConfirm), [true, false, true])
        XCTAssertEqual(s.confirmRows[0].rentalName, "Oak")
        XCTAssertEqual(s.confirmRows[0].hours, 2)
        XCTAssertEqual(s.confirmRows.count, s.pendingCount)
    }

    func testPaceWaitsUntilTenHoursOrTwoWeeksOfData() {
        GoalManager.shared.globalGoalType = .reps
        let (vm, property) = makeViewModel()
        let now = Date()
        vm.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs, hours: 4, date: now, notes: "")
        XCTAssertFalse(vm.widgetSurfaceSnapshot(now: now, suggestions: []).paceReady)
        vm.addTimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs, hours: 7, date: now, notes: "")
        XCTAssertTrue(vm.widgetSurfaceSnapshot(now: now, suggestions: []).paceReady)
    }

    func testTimerCarriesThePropertyName() {
        let (vm, property) = seeded()
        vm.startTimer(propertyId: property, category: .repairs)
        defer { vm.cancelTimer() }
        let s = vm.widgetSurfaceSnapshot(suggestions: [])
        XCTAssertNotNil(s.timerStart)
        XCTAssertEqual(s.timerPropertyName, "Oak")
        XCTAssertEqual(WidgetSurfaceDisplay(snapshot: s).state, .timer)
    }

    func testSavesWriteTheSnapshotToTheAppGroup() {
        GoalManager.shared.globalGoalType = .reps
        let (vm, _) = seeded(selfHours: 12, spouseHours: 0)
        XCTAssertEqual(WidgetSurfaceStore.load().hours, vm.houseCountableHours(), accuracy: 0.001)
        XCTAssertEqual(WidgetSurfaceStore.load().propertyCount, 1)
    }
}

// MARK: Notification content

final class NotificationCopyTests: XCTestCase {
    func testEndOfVisitHasATitleAndAShortBody() {
        let c = NotificationCopy.endOfVisit(eventTitle: "Plumber visit", timing: .justEnded, hours: 2, propertyName: "Pine Cabin")
        XCTAssertEqual(c.title, "Plumber visit just ended")
        XCTAssertEqual(c.body, "Log 2h at Pine Cabin?")
        XCTAssertEqual(NotificationCopy.endOfVisit(eventTitle: "Plumber visit", timing: .earlierToday, hours: 2, propertyName: nil).title,
                       "Plumber visit ended earlier today")
        XCTAssertEqual(NotificationCopy.endOfVisit(eventTitle: "Plumber visit", timing: .yesterday, hours: 2, propertyName: nil).body, "Log 2h?")
        XCTAssertEqual(NotificationCopy.endOfVisit(eventTitle: "Plumber visit", timing: .justEnded, hours: nil, propertyName: "Pine").body, "Log it?")
        XCTAssertEqual(NotificationCopy.endOfVisit(eventTitle: "  ", timing: .justEnded, hours: 0.75, propertyName: nil).title, "Your event just ended")
        XCTAssertEqual(NotificationCopy.endOfVisit(eventTitle: "Plumber", timing: .justEnded, hours: 0.75, propertyName: nil).body, "Log 45 min?")
    }

    func testFollowUpsUseTheEventAsTitle() {
        let expected: [(CaptureFollowUp, String)] = [
            (.mightAlreadyBeLogged, "This might already be in your records. Tap to check before saving."),
            (.eventMoved, "This moved on your calendar. Tap to check the time before saving."),
            (.eventGone, "This is gone from your calendar, so nothing was logged."),
            (.cannotVerify, "We couldn’t check this on your calendar. Tap to log it yourself."),
            (.needsInput, "This needs a property or hours. Tap to finish it."),
            (.offerMute, "Got it, that’s not rental work. Stop suggesting events like this one?"),
            (.queuedTooLong, "Not logged yet, because iCloud didn’t finish syncing. Tap to check it."),
        ]
        for (followUp, body) in expected {
            let c = NotificationCopy.followUp(followUp, eventTitle: "Dentist")
            XCTAssertEqual(c.title, "Dentist")
            XCTAssertEqual(c.body, body)
        }
    }

    func testEngagementNudges() {
        let quiet = NotificationCopy.inactive(days: 9)
        XCTAssertEqual(quiet.title, "Anything for your rentals lately?")
        XCTAssertEqual(quiet.body, "Nothing logged in 9 days. Add what you did while you still remember it.")
        let yearEnd = NotificationCopy.yearEnd(hours: 212.5, year: 2026)
        XCTAssertEqual(yearEnd.title, "Tax time is coming")
        XCTAssertEqual(yearEnd.body, "You have 212h logged for 2026. You can make the PDF for your CPA any time.", "Whole hours")
    }

    func testActionsTitlesAndIcons() {
        let category = CaptureNotificationCategories.suggestion
        XCTAssertEqual(category.actions.map(\.title), ["Log it", "Edit…", "Not rental work"])
        XCTAssertEqual(NotificationCopy.Action.allCases.map(\.symbol), ["checkmark.circle", "pencil", "xmark.circle"])
        XCTAssertTrue(category.actions[0].options.contains(.authenticationRequired))
        XCTAssertTrue(category.actions[1].options.contains(.foreground))
        XCTAssertFalse(category.actions[2].options.contains(.foreground))
    }

    func testEveryStringIsPlainAndCurly() {
        var all: [NotificationText] = [
            NotificationCopy.endOfVisit(eventTitle: "Plumber visit", timing: .justEnded, hours: 2, propertyName: "Pine"),
            NotificationCopy.inactive(days: 7), NotificationCopy.yearEnd(hours: 10, year: 2026),
        ]
        all += [CaptureFollowUp.mightAlreadyBeLogged, .eventMoved, .eventGone, .cannotVerify, .needsInput, .offerMute, .queuedTooLong]
            .map { NotificationCopy.followUp($0, eventTitle: "Visit") }
        for text in all.flatMap({ [$0.title, $0.body] }) {
            for banned in ["evidence", "qualif", "audit", "tax-ready", "landlord work", "Track", "Home", "IRS", "deduct"] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(banned), "\(banned) in \(text)")
            }
            XCTAssertFalse(text.contains("'"), "Curly apostrophes only: \(text)")
        }
    }

    func testEngagementWordsShownInTheAppAndBySiri() {
        let service = EngagementIntelligenceService()
        let property = RentalProperty(name: "Oak", address: "1 Oak", propertyType: .ltr)
        var context = EngagementContext(
            now: Date(), taxYear: 2026, properties: [], timeEntries: [], calendarDraftCount: 0,
            isTimerRunning: false, timerStartTime: nil, notificationPermission: .authorized,
            recentDismissals: [], isProUser: false
        )
        let setup = service.recommendation(for: context)
        XCTAssertEqual(setup.title, "Add your first property")
        XCTAssertEqual(setup.message, "Then we can start finding your rental work.")
        context.properties = [property]
        context.calendarDraftCount = 3
        let drafts = service.recommendation(for: context)
        XCTAssertEqual(drafts.title, "3 to confirm")
        XCTAssertEqual(drafts.message, "3 calendar events look like rental work.")
    }
}

// MARK: The one toast queue

@MainActor
final class ToastQueueTests: XCTestCase {
    private var announced: [String] = []

    private func makeCenter() -> LHToastCenter {
        // Time never passes on its own: the tests dismiss explicitly.
        LHToastCenter(sleep: { _ in try? await Task.sleep(for: .seconds(3600)) }, announce: { [unowned self] in self.announced.append($0) })
    }

    func testShowsOneAtATimeInOrder() {
        let center = makeCenter()
        center.show(.success, "Added Oak Street Duplex")
        center.show(.neutral, "Timer discarded", actionTitle: "Undo") {}
        center.show(.problem, "Couldn’t save your last change. Your iPhone may be out of space.", actionTitle: "Retry") {}
        XCTAssertEqual(center.current?.message, "Added Oak Street Duplex")
        XCTAssertEqual(center.queue.map(\.message).count, 2)
        center.dismissCurrent()
        XCTAssertEqual(center.current?.message, "Timer discarded")
        XCTAssertEqual(center.current?.actionTitle, "Undo")
        center.dismissCurrent()
        XCTAssertEqual(center.current?.kind, .problem)
        center.dismissCurrent()
        XCTAssertNil(center.current)
        XCTAssertEqual(announced.first, "Added Oak Street Duplex")
        XCTAssertEqual(announced[1], "Timer discarded. Undo is available.")
    }

    func testActionRunsOnceAndAdvances() {
        let center = makeCenter()
        var retried = 0
        center.show(.problem, "Couldn’t save", actionTitle: "Retry") { retried += 1 }
        center.show(.success, "Added Oak")
        center.performAction()
        XCTAssertEqual(retried, 1)
        XCTAssertEqual(center.current?.message, "Added Oak")
        center.performAction()
        XCTAssertEqual(retried, 1, "A toast without an action does nothing")
        XCTAssertNil(center.current)
    }

    func testDuplicatesAreDropped() {
        let center = makeCenter()
        center.show(.problem, "Couldn’t save")
        center.show(.problem, "Couldn’t save")
        center.show(.success, "Added Oak")
        center.show(.success, "Added Oak")
        XCTAssertEqual(center.queue.count, 1)
    }

    func testFullQueueDropsSuccessBeforeProblems() {
        let center = makeCenter()
        center.maxQueued = 2
        center.show(.success, "first")
        center.show(.problem, "p1")
        center.show(.success, "s1")
        center.show(.problem, "p2")
        XCTAssertEqual(center.queue.map(\.message), ["p1", "p2"])
    }

    func testActionTitleNeedsAnAction() {
        let center = makeCenter()
        center.show(.success, "Logged 2h", actionTitle: "Undo")
        XCTAssertNil(center.current?.actionTitle, "No button that does nothing")
    }

    func testTimesOutAndShowsTheNext() async {
        let center = LHToastCenter(sleep: { _ in await Task.yield() }, announce: { _ in })
        center.show(.success, "a")
        center.show(.success, "b")
        for _ in 0..<50 where center.current?.message == "a" { await Task.yield() }
        XCTAssertEqual(center.current?.message, "b")
    }

    func testDurations() {
        XCTAssertEqual(LHToastSpec(kind: .success, message: "x").duration, 4)
        XCTAssertEqual(LHToastSpec(kind: .neutral, message: "x", actionTitle: "Undo").duration, 8, "§1.19: 8 s with an action")
        XCTAssertEqual(LHToastSpec(kind: .problem, message: "x").duration, 8)
    }

    func testInboxToastMapsOntoTheOneToast() {
        let inbox = InboxToast(message: "Marked not rental work", kind: .neutral, undo: nil)
        XCTAssertEqual(inbox.spec.id, inbox.id)
        XCTAssertEqual(inbox.spec.kind, .neutral)
        XCTAssertNil(inbox.spec.actionTitle)
    }

    func testPersistenceCopy() {
        XCTAssertEqual(AppViewModel.saveFailureMessage, "Couldn’t save your last change. Your iPhone may be out of space.")
        XCTAssertEqual(AppViewModel.loadFailureMessage, "Couldn’t open your records. They’re still safe on this iPhone.")
    }
}

// MARK: Siri copy

final class SiriCopyTests: XCTestCase {
    private func context(properties: Int, target: Double = 750) -> EngagementContext {
        let list = (0..<properties).map { RentalProperty(name: "P\($0)", address: "", propertyType: .ltr) }
        var c = EngagementContext(
            now: Date(), taxYear: 2026, properties: list, timeEntries: [], calendarDraftCount: 0,
            isTimerRunning: false, timerStartTime: nil, notificationPermission: .authorized,
            recentDismissals: [], isProUser: false
        )
        c.targetHours = target
        return c
    }

    private func snapshot(hours: Double, required: Double) -> EngagementSnapshot {
        EngagementSnapshot(
            yearHours: hours, lastLogDate: nil, daysSinceLastLog: nil,
            daysRemainingInYear: 73, requiredHoursToDate: required, isBehindPace: hours + 5 < required, timerAgeHours: nil
        )
    }

    func testSummaryInPlainWords() {
        let text = LandlordHoursIntentCopy.summaryDialog(
            year: 2026, context: context(properties: 2), snapshot: snapshot(hours: 212, required: 600),
            recommendation: .doNothing, pendingCount: 3
        )
        XCTAssertEqual(text, "You have 212 of your 750 hours for 2026. You’re 388 hours behind pace, and 3 visits are waiting for you to confirm.")
        XCTAssertEqual(
            LandlordHoursIntentCopy.summaryDialog(year: 2026, context: context(properties: 1), snapshot: snapshot(hours: 640, required: 600), recommendation: .doNothing),
            "You have 640 of your 750 hours for 2026. You’re on pace."
        )
        XCTAssertEqual(
            LandlordHoursIntentCopy.summaryDialog(year: 2026, context: context(properties: 0), snapshot: snapshot(hours: 0, required: 0), recommendation: .doNothing),
            "You haven’t added a property yet. Add one in LandlordHours and we’ll start finding your rental work."
        )
    }

    func testNextActionStartsWithWhatToConfirm() {
        let (line, dest) = LandlordHoursIntentCopy.nextAction(recommendation: .doNothing, pendingCount: 3, hasProperty: true)
        XCTAssertEqual(line, "3 visits are waiting for you to confirm.")
        XCTAssertEqual(dest, .inbox)
        let (caught, home) = LandlordHoursIntentCopy.nextAction(recommendation: .doNothing, pendingCount: 0, hasProperty: true)
        XCTAssertEqual(caught, "You’re all caught up. Nothing is waiting for you.")
        XCTAssertEqual(home, .home)
    }

    func testDestinationsUse2Point0Names() {
        XCTAssertEqual(LandlordHoursIntentDestination.home.confirmation, "Opening Today.")
        XCTAssertEqual(LandlordHoursIntentDestination.inbox.tabIndex, ShellTab.inboxIndex)
        XCTAssertEqual(LandlordHoursIntentDestination.records.tabIndex, ShellTab.recordsIndex)
        XCTAssertEqual(LandlordHoursIntentDestination.track.confirmation, "Opening Log time.")
        XCTAssertEqual(LandlordHoursShortcuts.shortcutTileColor, .navy)
    }
}

// MARK: Launch hand-off: see ConversionPathTests (package B, v2 launch on pageTop).
