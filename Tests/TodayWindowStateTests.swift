import XCTest
@testable import LandlordHours

final class TodayWindowStateTests: XCTestCase {
    private var cal = Calendar(identifier: .gregorian)
    private let rentalA = UUID()
    private let rentalB = UUID()
    private var now: Date!

    override func setUp() {
        super.setUp()
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        now = cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 15))!
    }

    private func entry(_ rental: UUID, hours: Double = 1, at date: Date) -> TimeEntry {
        TimeEntry(propertyId: rental, participant: .selfParticipant, category: .repairs, hours: hours, date: date)
    }

    func testNoEntriesIsDark() {
        XCTAssertFalse(TodayWindowState.loggedToday(entries: [], rentalIDs: [rentalA], now: now, calendar: cal))
        XCTAssertFalse(TodayWindowState.loggedToday(entries: [], rentalIDs: nil, now: now, calendar: cal))
    }

    func testEntryYesterdayIsDark() {
        let lateYesterday = cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 23, minute: 59))!
        XCTAssertFalse(TodayWindowState.loggedToday(entries: [entry(rentalA, at: lateYesterday)], rentalIDs: [rentalA], now: now, calendar: cal))
    }

    func testEntryTodayIsLit() {
        XCTAssertTrue(TodayWindowState.loggedToday(entries: [entry(rentalA, at: now)], rentalIDs: [rentalA], now: now, calendar: cal))
        let midnight = cal.startOfDay(for: now)
        XCTAssertTrue(TodayWindowState.loggedToday(entries: [entry(rentalA, at: midnight)], rentalIDs: [rentalA], now: now, calendar: cal))
    }

    func testDifferentRentalDoesNotLightSelectedRentalButLightsAll() {
        let entries = [entry(rentalB, at: now)]
        XCTAssertFalse(TodayWindowState.loggedToday(entries: entries, rentalIDs: [rentalA], now: now, calendar: cal))
        XCTAssertTrue(TodayWindowState.loggedToday(entries: entries, rentalIDs: nil, now: now, calendar: cal))
        XCTAssertTrue(TodayWindowState.loggedToday(entries: entries, rentalIDs: [rentalA, rentalB], now: now, calendar: cal))
    }

    func testZeroHourEntryDoesNotLight() {
        XCTAssertFalse(TodayWindowState.loggedToday(entries: [entry(rentalA, hours: 0, at: now)], rentalIDs: [rentalA], now: now, calendar: cal))
    }
}
