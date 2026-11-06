import XCTest
@testable import LandlordHours

/// fix/2.0.1-signin home screen: Today names one rental everywhere, and a Properties row
/// promises a target only when the hero counts that rental.
final class TodayFocusTests: XCTestCase {
    private let year = 2026
    private let delaney = RentalProperty(name: "Delaney Ct", address: "1", propertyType: .ltr)
    private let santaRay = RentalProperty(name: "Santa Ray Ave", address: "2", propertyType: .str)
    private let yeandle = RentalProperty(name: "Yeandle Ave", address: "3", propertyType: .ltr)
    private let cabin = RentalProperty(name: "Cabin", address: "4", propertyType: .str)

    private func entry(_ property: RentalProperty, hours: Double) -> TimeEntry {
        TimeEntry(propertyId: property.id, participant: .selfParticipant, category: .repairs, hours: hours,
                  date: DateComponents(calendar: .current, year: year, month: 3, day: 5).date!)
    }

    private func focus(_ props: [RentalProperty], _ entries: [TimeEntry] = [], grouping: Bool = false, perRental: Bool = true) -> String? {
        TaxQualificationEngine.todayFocusProperty(entries: entries, properties: props, year: year,
                                                  groupingElection: grouping, countsPerRental: perRental)?.name
    }

    func testBriansSetupNamesSantaRayEvenWithNoHoursAndDelaneyAddedFirst() {
        XCTAssertEqual(focus([delaney, santaRay, yeandle]), "Santa Ray Ave", "the only short stay, not properties.first")
    }

    func testLongStaysNeverStandInForAShortStay() {
        let entries = [entry(delaney, hours: 300), entry(santaRay, hours: 5)]
        XCTAssertEqual(focus([delaney, santaRay, yeandle], entries), "Santa Ray Ave")
    }

    func testAllSameKindPicksTheRentalWithTheMostHours() {
        let entries = [entry(delaney, hours: 10), entry(yeandle, hours: 40)]
        XCTAssertEqual(focus([delaney, yeandle], entries), "Yeandle Ave")
        XCTAssertEqual(focus([santaRay, cabin], [entry(cabin, hours: 3)]), "Cabin")
    }

    func testNoFocusWhenTheCountCoversEveryRental() {
        XCTAssertNil(focus([delaney, santaRay], grouping: true))
        XCTAssertNil(focus([delaney, santaRay], perRental: false), "750 goal or record")
        XCTAssertNil(focus([]))
    }

    func testCountedRentalsFollowTheHeroRule() {
        XCTAssertEqual(TaxQualificationEngine.countedProperties([delaney, santaRay, yeandle]).map(\.name), ["Santa Ray Ave"])
        XCTAssertEqual(TaxQualificationEngine.countedProperties([delaney, yeandle]).count, 2)
        XCTAssertEqual(TaxQualificationEngine.countedProperties([santaRay, cabin]).count, 2)
    }

    func testRowTextPerGoalAndKind() {
        // (goal, grouping, counted, hours) -> text
        let cases: [(HouseGoal, Bool, Bool, Double, String)] = [
            (.mp100, false, true, 0, "0h of 100h"),
            (.mp100, false, true, 99.9, "99h of 100h"),
            (.mp100, false, true, 100, "100h this year"),
            (.mp100, false, true, 140, "140h this year"),
            (.mp500, false, true, 12, "12h of 500h"),
            (.mp500, false, true, 500, "500h this year"),
            (.mp100, false, false, 12, "12h this year"),
            (.mp500, false, false, 12, "12h this year"),
            (.mp100, true, true, 12, "12h this year"),
            (.reps750, false, true, 12, "12h this year"),
            (.reps750, false, false, 12, "12h this year"),
            (.reps750, true, true, 800, "800h this year"),
        ]
        for (goal, grouping, counted, hours, expected) in cases {
            XCTAssertEqual(PropertyMeta.hoursLine(hours, goal: goal, groupingElection: grouping, counted: counted), expected,
                           "\(goal) grouping=\(grouping) counted=\(counted) \(hours)h")
        }
    }

    func testBriansSetupRowsUnderGoal100() {
        let props = [delaney, santaRay, yeandle]
        let counted = Set(TaxQualificationEngine.countedProperties(props).map(\.id))
        let lines = props.map { PropertyMeta.hoursLine(0, goal: .mp100, groupingElection: false, counted: counted.contains($0.id)) }
        XCTAssertEqual(lines, ["0h this year", "0h of 100h", "0h this year"])
    }
}
