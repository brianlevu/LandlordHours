import XCTest
@testable import LandlordHours

// MARK: - Log time v2 (package E): what the host (the compact shell, package J's right pane) can rely on

private let pine = RentalProperty(name: "Pine Cabin", address: "88 Ridge Rd", propertyType: .str)
private let oak = RentalProperty(name: "Oak Street Duplex", address: "214 Oak St", propertyType: .ltr)
private let maple = RentalProperty(name: "Maple Court", address: "12 Maple Ct", propertyType: .ltr)

final class LogTimeHostingTests: XCTestCase {
    /// Package J passes the rental the shelf shows; Log time starts on it, as a default.
    func testTheRentalShownIsTheStartingRental() {
        let form = LogForm.starting(properties: [pine, oak, maple], entries: [], rentalShown: oak.id)
        XCTAssertEqual(form.propertyId, oak.id)
        XCTAssertFalse(form.isUserSet(.property), "a note can still name another rental")
        XCTAssertEqual(form.provenance(.property), .defaultValue)
    }

    func testAllRentalsStartsWithoutARental() {
        let form = LogForm.starting(properties: [pine, oak, maple], entries: [], rentalShown: nil)
        XCTAssertNil(form.propertyId, "on All rentals the sheet asks which one")
    }

    func testAnUnknownRentalShownIsIgnored() {
        let form = LogForm.starting(properties: [pine, oak], entries: [], rentalShown: UUID())
        XCTAssertNil(form.propertyId)
    }

    func testTheOnlyRentalWinsOverTheShownOne() {
        let form = LogForm.starting(properties: [pine], entries: [], rentalShown: UUID())
        XCTAssertEqual(form.propertyId, pine.id)
    }

    func testANoteStillOverridesTheRentalShown() {
        var form = LogForm.starting(properties: [pine, oak, maple], entries: [], rentalShown: pine.id)
        let reading = NoteRules.read(NoteReadRequest(text: "fixed the sink at Oak St, 2 hours",
                                                     properties: [pine, oak, maple], spouseTracking: false))
        form.apply(reading, source: .note, spouseTracking: false)
        XCTAssertEqual(form.propertyId, oak.id)
        form.undoFill()
        XCTAssertEqual(form.propertyId, pine.id, "Undo goes back to the rental shown")
    }

    /// The Log button names the rental shown (`Log %@ at %@`), so the pane never names a different one.
    func testTheLogButtonNamesTheRentalShown() {
        let form = LogForm.starting(properties: [pine, oak], entries: [], rentalShown: oak.id)
        var withKind = form
        withKind.setCategory(.repairs)
        let title = LogTimeFormat.buttonTitle(form: withKind, properties: [pine, oak])
        XCTAssertTrue(title.hasPrefix("Log\u{00A0}1h"), title)
        XCTAssertTrue(title.contains("Oak\u{00A0}Street\u{00A0}Duplex"), title)
        XCTAssertFalse(title.contains("Pine"), title)
    }
}

final class LogTimeFormatV2Tests: XCTestCase {
    func testClockTimeAndLongDayDoNotNeedTheInbox() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 9, minute: 41))!
        XCTAssertEqual(LogTimeFormat.clockTime(date, calendar: calendar), "9:41")
        XCTAssertEqual(LogTimeFormat.longDay(date, calendar: calendar), "Wed, Oct 14")
    }

    func testStringsComeFromTheLogTimeTable() {
        // The English text is the key: with or without the catalog, the words are the same.
        XCTAssertEqual(lt("Log time"), "Log time")
        XCTAssertEqual(lt("Logged \("1h") at \("Pine Cabin")"), "Logged 1h at Pine Cabin")
    }
}
