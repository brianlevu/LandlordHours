import XCTest
@testable import LandlordHours

/// Package J (§1.27): the one mode function, the pane sizes, the shelf's honest "All rentals", and
/// the work pane's filter.
final class AdaptiveLayoutTests: XCTestCase {
    private func mode(_ w: CGFloat, _ h: CGFloat, previous: LayoutMode? = nil, live: Bool = false,
                      division: PaneDivision? = nil) -> LayoutMode {
        LayoutMode.resolve(previous: previous, size: CGSize(width: w, height: h), division: division, live: live).mode
    }

    func testThresholdsSettledHaveNoHistory() {
        XCTAssertEqual(mode(799, 1000), .compact)
        XCTAssertEqual(mode(800, 1000), .twoPane)
        XCTAssertEqual(mode(1000, 644), .compact)
        XCTAssertEqual(mode(1000, 645), .twoPane)
        // A settled window gets the same mode whatever came before.
        XCTAssertEqual(mode(804, 1000, previous: .compact), .twoPane)
        XCTAssertEqual(mode(804, 1000, previous: .twoPane), .twoPane)
    }

    func testSizeTable() {
        XCTAssertEqual(mode(402, 874), .compact)            // iPhone 17 portrait
        XCTAssertEqual(mode(956, 440), .compact)            // Pro Max landscape (H < 645)
        XCTAssertEqual(mode(382, 644), .compact)            // Duo closed
        XCTAssertEqual(mode(744, 1133), .compact)           // iPad mini portrait
        XCTAssertEqual(mode(1133, 744), .twoPane)           // iPad mini landscape
        XCTAssertEqual(mode(820, 1180), .twoPane)           // iPad 10th gen portrait
        XCTAssertEqual(mode(1180, 820), .twoPane)
        XCTAssertEqual(mode(790, 820), .compact)            // 11" 2/3 tile
        XCTAssertEqual(mode(1376, 1032), .twoPane)
    }

    func testHysteresisOnlyWhileLive() {
        // From compact, a live resize turns two-pane on only at 808 / 653.
        XCTAssertEqual(mode(804, 1000, previous: .compact, live: true), .compact)
        XCTAssertEqual(mode(808, 1000, previous: .compact, live: true), .twoPane)
        XCTAssertEqual(mode(1000, 650, previous: .compact, live: true), .compact)
        XCTAssertEqual(mode(1000, 653, previous: .compact, live: true), .twoPane)
        // From two-pane, it stays on down to 800 / 645.
        XCTAssertEqual(mode(800, 1000, previous: .twoPane, live: true), .twoPane)
        XCTAssertEqual(mode(799, 1000, previous: .twoPane, live: true), .compact)
    }

    func testDivisionSplitsAtTheFold() {
        let fold = PaneDivision(rect: CGRect(x: 463.5, y: 0, width: 24, height: 669))
        let open = LayoutMode.resolve(previous: nil, size: CGSize(width: 951, height: 669), division: fold, live: false)
        XCTAssertEqual(open.mode, .twoPane)
        XCTAssertTrue(open.isDivision)
        XCTAssertEqual(open.first.width, 463.5, accuracy: 0.01)
        XCTAssertEqual(open.second.width, 463.5, accuracy: 0.01)
        let propped = PaneDivision(rect: CGRect(x: 0, y: 463.5, width: 669, height: 24))
        XCTAssertEqual(mode(669, 951, division: propped), .stacked)
        // Panes under 380 stay compact.
        XCTAssertEqual(mode(700, 669, division: PaneDivision(rect: CGRect(x: 338, y: 0, width: 24, height: 669))), .compact)
    }

    func testPaneGapAndWidths() {
        let s = LayoutMode.resolve(previous: nil, size: CGSize(width: 820, height: 1180), division: nil, live: false)
        XCTAssertEqual(s.gap.width, LayoutMode.paneGap)
        XCTAssertEqual(s.first.width, 398, accuracy: 0.01)
        XCTAssertEqual(s.second.minX, 422, accuracy: 0.01)
    }

    func testHeroSides() {
        XCTAssertEqual(PaneMetrics.heroSide(paneWidth: 463.5, paneHeight: 669, accessibility: false), 290)   // Duo
        XCTAssertEqual(PaneMetrics.heroSide(paneWidth: 578, paneHeight: 820, accessibility: false), 362)     // 10th gen landscape
        // 13" landscape: the pane is over 900 tall, so the iPad sizing note grows the house past the
        // table's 390 toward the content width (600 - 2 x 24 gutter, cap 0.45 H = 464).
        XCTAssertEqual(PaneMetrics.heroSide(paneWidth: 676, paneHeight: 1032, accessibility: false), 464)
        XCTAssertEqual(PaneMetrics.heroSide(paneWidth: 676, paneHeight: 820, accessibility: false), 369)   // capped at 0.45 H
        XCTAssertEqual(PaneMetrics.heroSide(paneWidth: 398, paneHeight: 1180, accessibility: false), 366)    // tall pane fills
        XCTAssertGreaterThanOrEqual(PaneMetrics.heroSide(paneWidth: 463.5, paneHeight: 669, accessibility: true), 220)
        XCTAssertEqual(PaneMetrics.gutter(paneWidth: 463.5, onDuo: true), 16)
        XCTAssertEqual(PaneMetrics.gutter(paneWidth: 398), 16)
        XCTAssertEqual(PaneMetrics.gutter(paneWidth: 578), 24)
    }

    private func item(_ name: String, hours: Double, behind: Bool) -> HouseShelfItem {
        HouseShelfItem(id: name, rentalID: UUID(), name: name, hours: hours, goal: 100,
                       stage: CraftStage.stage(hours: hours, goal: 100), lit: false,
                       pace: TodayPaceSentence(lead: behind ? "Behind by 9h." : "On pace.", rest: "", tone: behind ? .behind : .positive),
                       behindBy: behind ? 9 : 0)
    }

    func testAllRentalsHasNoGoalAndLeadsTheShelf() {
        let shelf = HouseShelf(rentals: [item("A", hours: 46, behind: true), item("B", hours: 4, behind: true), item("C", hours: 262, behind: false)])
        let all = shelf.items[0]
        XCTAssertTrue(all.isAll)
        XCTAssertNil(all.goal)
        XCTAssertNil(all.stage)
        XCTAssertEqual(shelf.summary.wholeHours, 312)
        XCTAssertEqual(shelf.summary.behindCount, 2)
        XCTAssertEqual(shelf.skyline.count, 3)
        XCTAssertEqual(shelf.step(from: HouseShelf.allID, by: -1), "C")
        // One rental: no "All rentals".
        XCTAssertEqual(HouseShelf(rentals: [item("A", hours: 1, behind: false)]).items.count, 1)
    }

    func testFilterKeepsUnassignedItems() {
        let pine = UUID(), oak = UUID()
        let items = [
            Suggestion.makeForTest(key: "a", property: pine),
            Suggestion.makeForTest(key: "b", property: oak),
            Suggestion.makeForTest(key: "c", property: nil),
        ]
        XCTAssertEqual(Set(PaneConfirmFilter.items(items, rentalID: pine).map(\.sourceKey)), ["a", "c"])
        XCTAssertEqual(PaneConfirmFilter.hiddenCount(items, rentalID: pine), 1)
        XCTAssertEqual(PaneConfirmFilter.items(items, rentalID: nil).count, 3)
    }

    func testEarlierMeasureIgnoresStaleAndNeverEmptiesAfterTheFact() {
        let a = UUID(), b = UUID()
        let old = EarlierMeasure.key([a], typeSize: .large)
        let new = EarlierMeasure.key([a, b], typeSize: .large)
        XCTAssertNotEqual(old, new)
        XCTAssertNotEqual(new, EarlierMeasure.key([a, b], typeSize: .xxLarge))
        var m = EarlierMeasure()
        m.record(key: old, index: 0, end: 30)
        m.record(key: new, index: 0, end: 32)
        m.record(key: new, index: 1, end: 90)
        m.record(key: new, index: 2, end: 150)
        XCTAssertEqual(m.key, new)
        XCTAssertEqual(m.ends, [0: 32, 1: 90, 2: 150])
        // The fresh measure fits rows: the section shows them.
        XCTAssertEqual(OnTheRecordCard.fitCount(ends: m.ends, candidates: 2, top: 100, room: 220), 1)
        XCTAssertEqual(OnTheRecordCard.fitCount(ends: m.ends, candidates: 2, top: 100, room: 400), 2)
        XCTAssertEqual(OnTheRecordCard.fitCount(ends: [:], candidates: 2, top: 100, room: 400), 0)
    }

    // MARK: Whole cards above the bar at rest (gate J r2)

    /// Header 60, then rows of 63 (ends 123, 186, ...); feet 44; record 100.
    private func plan(_ n: Int, hidden: Int = 0, filtered: Bool, room: CGFloat) -> PaneConfirmFit.Plan {
        var ends: [Int: CGFloat] = [0: 60]
        for i in stride(from: 1, through: max(n, 1), by: 1) { ends[i] = 60 + CGFloat(i) * 63 }
        return PaneConfirmFit.plan(ends: ends, count: n, hidden: hidden, seeAll: 44, moreElsewhere: 44,
                                   record: 100, filtered: filtered, room: room)
    }

    func testConfirmFitShowsEverythingWhenItFits() {
        // 8 + 60 + 5 x 63 + 44 (more elsewhere) + 10 + 100 = 537
        XCTAssertEqual(plan(5, hidden: 3, filtered: true, room: 537), .init(rows: 5, showsRecord: true))
        XCTAssertEqual(plan(5, hidden: 0, filtered: false, room: 600), .init(rows: 5, showsRecord: true))
    }

    func testConfirmFitAllRentalsRunsRowsToTheBar() {
        // 8 rows on "All rentals" in a short pane: whole rows and "See all", never a row under the bar.
        // 8 + 60 + k x 63 + 44 <= 420 -> k = 4; the record no longer fits under them.
        XCTAssertEqual(plan(8, filtered: false, room: 420), .init(rows: 4, showsRecord: false))
        // More room goes to more rows first (DU4: rows run to the bar).
        XCTAssertEqual(plan(8, filtered: false, room: 8 + 60 + 4 * 63 + 44 + 10 + 100), .init(rows: 5, showsRecord: false))
        // A short list: every row, then the record.
        XCTAssertEqual(plan(3, filtered: false, room: 600), .init(rows: 3, showsRecord: true))
    }

    func testConfirmFitFilteredKeepsThreeRowsAndTheRecord() {
        // 5 rows of Pine Cabin, room for 3 rows + "See all" + the record: DU4 filtered.
        let room: CGFloat = 8 + 60 + 3 * 63 + 44 + 10 + 100
        XCTAssertEqual(plan(5, hidden: 3, filtered: true, room: room), .init(rows: 3, showsRecord: true))
        // Below that, rows win and the record waits.
        XCTAssertEqual(plan(5, hidden: 3, filtered: true, room: room - 20), .init(rows: 4, showsRecord: false))
    }

    func testConfirmFitStackedKeepsOneRowOrGivesWayAtAX() {
        // Propped (DU13): one row, "See all", the record.
        let room: CGFloat = 8 + 60 + 63 + 44 + 10 + 100
        XCTAssertEqual(PaneConfirmFit.plan(ends: [0: 60, 1: 123, 2: 186, 3: 249], count: 3, hidden: 0, seeAll: 44, moreElsewhere: 44,
                                           record: 100, filtered: true, room: room, maxRows: 1), .init(rows: 1, showsRecord: true))
        // AX: the row is taller than the half; the header and "See all" stay, nothing under the bar.
        XCTAssertEqual(PaneConfirmFit.plan(ends: [0: 120, 1: 420, 2: 720], count: 2, hidden: 0, seeAll: 70, moreElsewhere: 90,
                                           record: 160, filtered: true, room: 300, maxRows: 1), .init(rows: 0, showsRecord: false))
        // Unmeasured: one row, as before.
        XCTAssertEqual(PaneConfirmFit.plan(ends: [:], count: 3, hidden: 0, seeAll: nil, moreElsewhere: nil, record: nil,
                                           filtered: false, room: 300, maxRows: 1), .init(rows: 1, showsRecord: true))
    }

    func testConfirmFitAXOneRowAtLeastAndUnmeasuredShowsAll() {
        // One AX row taller than the pane: one row, it scrolls.
        var ends: [Int: CGFloat] = [0: 120]
        for i in 1...3 { ends[i] = 120 + CGFloat(i) * 400 }
        XCTAssertEqual(PaneConfirmFit.plan(ends: ends, count: 3, hidden: 0, seeAll: 60, moreElsewhere: 90, record: 200,
                                           filtered: false, room: 380), .init(rows: 1, showsRecord: false))
        // Before the off-screen measure lands: the old behaviour, every row.
        XCTAssertEqual(PaneConfirmFit.plan(ends: [:], count: 6, hidden: 0, seeAll: nil, moreElsewhere: nil, record: nil,
                                           filtered: false, room: 400), .init(rows: 6, showsRecord: true))
    }

    func testEarlierElsewhereOnlyForOneRentalAndBeforeToday() {
        let pine = UUID(), oak = UUID()
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 15))!
        func entry(_ rental: UUID, daysBack: Int) -> TimeEntry {
            TimeEntry(propertyId: rental, participant: .selfParticipant, category: .repairs, hours: 1,
                      date: cal.date(byAdding: .day, value: -daysBack, to: now)!, notes: "")
        }
        let all = [entry(pine, daysBack: 1), entry(oak, daysBack: 0), entry(oak, daysBack: 2), entry(oak, daysBack: 1)]
        let own = OnTheRecordCard.earlier(all, rentalID: pine, now: now, calendar: cal)
        XCTAssertEqual(own.count, 1)
        let elsewhere = OnTheRecordCard.earlierElsewhere(all, rentalID: pine, now: now, calendar: cal)
        XCTAssertEqual(elsewhere.count, 2, "today's entry is on the record, not earlier")
        XCTAssertTrue(elsewhere.allSatisfy { $0.propertyId == oak })
        XCTAssertGreaterThan(elsewhere[0].date, elsewhere[1].date, "newest first")
        XCTAssertTrue(OnTheRecordCard.earlierElsewhere(all, rentalID: nil, now: now, calendar: cal).isEmpty, "All rentals has no elsewhere")
    }
}

private extension Suggestion {
    static func makeForTest(key: String, property: UUID?) -> Suggestion {
        Suggestion(sourceKey: key, kind: .calendar, detectedAt: Date(), start: Date(), end: Date().addingTimeInterval(3600),
                   title: key, proposedPropertyId: property)
    }
}
