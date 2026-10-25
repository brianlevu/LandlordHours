import XCTest
@testable import LandlordHours

/// Package A2: the shared "All rentals" views (standard §H.1 H10, §1.27 shared keys).
final class SharedHouseViewsTests: XCTestCase {
    private func item(_ id: String, behind: Double = 0) -> RentalSkylineItem {
        RentalSkylineItem(id: id, name: id, stage: .framing, lit: false, behindBy: behind)
    }

    func testHouseSideFormulaAndFloor() {
        // 220 stacked frame, 4 houses -> 44.0 each (the standard's arithmetic).
        XCTAssertEqual(RentalSkylineLayout.houseSide(frame: 220, count: 4), 44.0, accuracy: 0.05)
        // 290 frame, 5 houses -> 44.1.
        XCTAssertEqual(RentalSkylineLayout.houseSide(frame: 290, count: 5), 44.08, accuracy: 0.1)
        // A single house is capped at 0.42 S.
        XCTAssertEqual(RentalSkylineLayout.houseSide(frame: 390, count: 1), 0.42 * 390, accuracy: 0.01)
        // Never under 44.
        XCTAssertGreaterThanOrEqual(RentalSkylineLayout.houseSide(frame: 100, count: 5), 44)
    }

    func testCap() {
        XCTAssertEqual(RentalSkylineLayout.cap(frame: 290), 5)
        XCTAssertEqual(RentalSkylineLayout.cap(frame: 287), 4)
        XCTAssertEqual(RentalSkylineLayout.cap(frame: 220), 4)
    }

    func testOverCapShowsMostBehindFirstInShelfOrder() {
        let items = [item("a", behind: 1), item("b", behind: 9), item("c"), item("d", behind: 5), item("e", behind: 9), item("f", behind: 2)]
        let shown = RentalSkylineLayout.visible(items, frame: 390).map(\.id)
        // Cap 5 drops the least behind ("c"); the rest stay in shelf order.
        XCTAssertEqual(shown, ["a", "b", "d", "e", "f"])
        // Cap 4 at a small frame drops "a" too (1 < 2).
        XCTAssertEqual(RentalSkylineLayout.visible(items, frame: 220).map(\.id), ["b", "d", "e", "f"])
        // Ties break by shelf order.
        let tied = [item("x", behind: 3), item("y", behind: 3), item("z", behind: 3), item("w", behind: 3), item("v", behind: 3)]
        XCTAssertEqual(RentalSkylineLayout.visible(tied, frame: 220).map(\.id), ["x", "y", "z", "w"])
        // Under the cap nothing is dropped.
        XCTAssertEqual(RentalSkylineLayout.visible(Array(items.prefix(3)), frame: 220).count, 3)
    }

    func testAllRentalsLines() {
        let behind = AllRentalsSummary(hours: 312.7, rentalCount: 3, behindCount: 3)
        XCTAssertEqual(behind.numberLine, "312 hours across 3 rentals · 3 of 3 behind")
        XCTAssertEqual(behind.paceLine, "Tap a house to see its pace.")
        let onPace = AllRentalsSummary(hours: 80, rentalCount: 2, behindCount: 0)
        XCTAssertEqual(onPace.numberLine, "80 hours across 2 rentals · All on pace")
        XCTAssertEqual(onPace.paceLine, "Every rental is on pace.")
        // Behind count is clamped to the rental count; bad hours read as zero.
        XCTAssertEqual(AllRentalsSummary(hours: .nan, rentalCount: 2, behindCount: 9).behindCount, 2)
        XCTAssertEqual(AllRentalsSummary(hours: .nan, rentalCount: 2, behindCount: 0).wholeHours, 0)
    }
}
