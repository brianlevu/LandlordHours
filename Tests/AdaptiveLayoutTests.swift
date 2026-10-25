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
}

private extension Suggestion {
    static func makeForTest(key: String, property: UUID?) -> Suggestion {
        Suggestion(sourceKey: key, kind: .calendar, detectedAt: Date(), start: Date(), end: Date().addingTimeInterval(3600),
                   title: key, proposedPropertyId: property)
    }
}
