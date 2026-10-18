import XCTest
@testable import LandlordHours

// MARK: - Model Codable Tests

final class ModelCodableTests: XCTestCase {

    func testRentalPropertyRoundtrip() throws {
        let property = RentalProperty(name: "Oak House", address: "123 Oak St, Portland, OR", propertyType: .ltr)
        let data = try JSONEncoder().encode(property)
        let decoded = try JSONDecoder().decode(RentalProperty.self, from: data)

        XCTAssertEqual(decoded.id, property.id)
        XCTAssertEqual(decoded.name, "Oak House")
        XCTAssertEqual(decoded.address, "123 Oak St, Portland, OR")
        XCTAssertEqual(decoded.propertyType, .ltr)
    }

    func testRentalPropertyDecodesWithoutModifiedAt() throws {
        // Older records may not have modifiedAt — should fall back to createdAt
        let json = """
        {"id":"550e8400-e29b-41d4-a716-446655440000","name":"Test","address":"Addr","propertyType":"LTR","createdAt":0}
        """
        let decoded = try JSONDecoder().decode(RentalProperty.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.modifiedAt, decoded.createdAt)
    }

    func testTimeEntryRoundtrip() throws {
        let propertyId = UUID()
        let entry = TimeEntry(
            propertyId: propertyId,
            participant: .selfParticipant,
            category: .repairs,
            hours: 2.5,
            date: Date(),
            notes: "Fixed leaking faucet"
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(TimeEntry.self, from: data)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.propertyId, propertyId)
        XCTAssertEqual(decoded.participant, .selfParticipant)
        XCTAssertEqual(decoded.category, .repairs)
        XCTAssertEqual(decoded.hours, 2.5)
        XCTAssertEqual(decoded.notes, "Fixed leaking faucet")
    }

    func testTimeEntryDecodesWithoutAttachments() throws {
        // Entries from CloudKit or older versions may lack attachments
        let propertyId = UUID()
        let json = """
        {"id":"550e8400-e29b-41d4-a716-446655440001","propertyId":"\(propertyId.uuidString)","participant":"Self","category":"Repairs & Maintenance","hours":1.0,"date":0,"notes":"test","createdAt":0}
        """
        let decoded = try JSONDecoder().decode(TimeEntry.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.attachments.isEmpty)
    }

    func testPropertyTypeRawValues() {
        XCTAssertEqual(PropertyType.ltr.rawValue, "LTR")
        XCTAssertEqual(PropertyType.str.rawValue, "STR")
        XCTAssertEqual(PropertyType(rawValue: "LTR"), .ltr)
        XCTAssertEqual(PropertyType(rawValue: "STR"), .str)
        XCTAssertNil(PropertyType(rawValue: "invalid"))
    }

    func testParticipantRawValues() {
        XCTAssertEqual(Participant.selfParticipant.rawValue, "Self")
        XCTAssertEqual(Participant.spouse.rawValue, "Spouse")
    }
}

// MARK: - Category REPS Qualification Tests

final class CategoryREPSTests: XCTestCase {

    func testREPSQualifiedCategories() {
        let qualified: [ActivityCategory] = [
            .repairs, .management, .leasing, .bookkeeping,
            .legal, .insurance, .travel, .renovations
        ]
        for cat in qualified {
            XCTAssertTrue(cat.countsForREPS, "\(cat.rawValue) should count for REPS")
        }
    }

    func testNonREPSCategories() {
        let nonQualified: [ActivityCategory] = [
            .investing, .financing, .contractNegotiation
        ]
        for cat in nonQualified {
            XCTAssertFalse(cat.countsForREPS, "\(cat.rawValue) should NOT count for REPS")
        }
    }

    func testREPSFilteredLists() {
        XCTAssertEqual(ActivityCategory.repsQualified.count, 8)
        XCTAssertEqual(ActivityCategory.nonREPS.count, 3)
        XCTAssertEqual(
            ActivityCategory.repsQualified.count + ActivityCategory.nonREPS.count,
            ActivityCategory.allCases.count
        )
    }

    func testTimeEntryCountsForREPSMatchesCategory() {
        let propertyId = UUID()
        let repsEntry = TimeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs, hours: 1)
        let nonRepsEntry = TimeEntry(propertyId: propertyId, participant: .selfParticipant, category: .investing, hours: 1)

        XCTAssertTrue(repsEntry.countsForREPS)
        XCTAssertFalse(nonRepsEntry.countsForREPS)
    }
}

// MARK: - REPS Requirements Tests

final class REPSRequirementsTests: XCTestCase {

    func testAnnualThreshold() {
        XCTAssertEqual(REPSRequirements.annualHourThreshold, 750.0)
    }

    func testWorkingTimePercentage() {
        XCTAssertEqual(REPSRequirements.workingTimePercentage, 0.50)
    }

    func testWeeklyGoal() {
        let expected = 750.0 / 52.0
        XCTAssertEqual(REPSRequirements.weeklyGoal, expected, accuracy: 0.01)
    }

    func testMonthlyGoal() {
        let expected = 750.0 / 12.0
        XCTAssertEqual(REPSRequirements.monthlyGoal, expected, accuracy: 0.01)
    }
}

// MARK: - Tax Qualification Engine Tests

final class TaxQualificationEngineTests: XCTestCase {

    func testREPSDoesNotCombineSpouseHoursFor750HourTest() {
        let propertyId = UUID()
        let entries = [
            makeEntry(propertyId: propertyId, participant: .selfParticipant, category: .management, hours: 400),
            makeEntry(propertyId: propertyId, participant: .spouse, category: .management, hours: 400)
        ]

        let result = TaxQualificationEngine.repsStatus(
            entries: entries,
            participant: .selfParticipant,
            year: currentYear,
            nonRealEstateHours: 100
        )

        XCTAssertEqual(result.realEstateHours, 400)
        XCTAssertFalse(result.meets750HourTest)
        XCTAssertFalse(result.isQualified)
    }

    func testREPSTestsRequireMoreThan750AndMoreThanHalf() {
        let propertyId = UUID()
        let entries = [
            makeEntry(propertyId: propertyId, participant: .selfParticipant, category: .management, hours: 751)
        ]

        let qualified = TaxQualificationEngine.repsStatus(
            entries: entries,
            participant: .selfParticipant,
            year: currentYear,
            nonRealEstateHours: 700
        )
        XCTAssertTrue(qualified.meets750HourTest)
        XCTAssertTrue(qualified.meetsMoreThanHalfPersonalServicesTest)
        XCTAssertTrue(qualified.isQualified)

        let failsMoreThanHalf = TaxQualificationEngine.repsStatus(
            entries: entries,
            participant: .selfParticipant,
            year: currentYear,
            nonRealEstateHours: 800
        )
        XCTAssertTrue(failsMoreThanHalf.meets750HourTest)
        XCTAssertFalse(failsMoreThanHalf.meetsMoreThanHalfPersonalServicesTest)
        XCTAssertFalse(failsMoreThanHalf.isQualified)
    }

    func testMaterialParticipationCanCombineSpouseHours() {
        let propertyId = UUID()
        let entries = [
            makeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs, hours: 60),
            makeEntry(propertyId: propertyId, participant: .spouse, category: .leasing, hours: 50)
        ]

        // Spouse hours still combine (60 + 50 = 110). The 100-hour test now also
        // requires confirming no one else participated more.
        let result = TaxQualificationEngine.materialParticipationStatus(
            entries: entries,
            year: currentYear,
            propertyId: propertyId,
            groupingElection: false,
            noOneParticipatedMore: true
        )

        XCTAssertEqual(result.ownerAndSpouseHours, 110)
        XCTAssertTrue(result.meets100HourTest)
        XCTAssertTrue(result.isMateriallyParticipating)
    }

    // MARK: - 100-Hour Test Confirmation (IRS Test 3)

    func testHundredHourTestUnconfirmedIsConditionalNotMet() {
        let propertyId = UUID()
        let entries = [
            makeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs, hours: 101)
        ]

        // nil = unanswered: threshold cleared but the test cannot be asserted yet.
        let result = TaxQualificationEngine.materialParticipationStatus(
            entries: entries,
            year: currentYear,
            propertyId: propertyId,
            groupingElection: false,
            noOneParticipatedMore: nil
        )

        XCTAssertEqual(result.ownerAndSpouseHours, 101)
        XCTAssertFalse(result.meets100HourTest)
        XCTAssertFalse(result.isMateriallyParticipating)
        XCTAssertTrue(result.meets100HourThresholdPendingConfirmation)
        XCTAssertNil(result.noOneParticipatedMore)
    }

    func testHundredHourTestConfirmedYesPasses() {
        let propertyId = UUID()
        let entries = [
            makeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs, hours: 101)
        ]

        let result = TaxQualificationEngine.materialParticipationStatus(
            entries: entries,
            year: currentYear,
            propertyId: propertyId,
            groupingElection: false,
            noOneParticipatedMore: true
        )

        XCTAssertTrue(result.meets100HourTest)
        XCTAssertTrue(result.isMateriallyParticipating)
        XCTAssertFalse(result.meets100HourThresholdPendingConfirmation)
    }

    func testHundredHourTestConfirmedSomeoneElseDidMoreFails() {
        let propertyId = UUID()
        let entries = [
            makeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs, hours: 101)
        ]

        // false = someone else participated more: Test 3 fails even though hours > 100.
        let result = TaxQualificationEngine.materialParticipationStatus(
            entries: entries,
            year: currentYear,
            propertyId: propertyId,
            groupingElection: false,
            noOneParticipatedMore: false
        )

        XCTAssertEqual(result.ownerAndSpouseHours, 101)
        XCTAssertFalse(result.meets100HourTest)
        XCTAssertFalse(result.isMateriallyParticipating)
        XCTAssertFalse(result.meets100HourThresholdPendingConfirmation)
    }

    func testHundredHourBoundaryIsNotConditionalAtExactly100EvenIfConfirmed() {
        let propertyId = UUID()
        let entries = [
            makeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs, hours: 100)
        ]

        // Exactly 100 is not "more than 100"; confirmation can't manufacture a pass.
        for answer: Bool? in [nil, true, false] {
            let result = TaxQualificationEngine.materialParticipationStatus(
                entries: entries,
                year: currentYear,
                propertyId: propertyId,
                groupingElection: false,
                noOneParticipatedMore: answer
            )
            XCTAssertEqual(result.ownerAndSpouseHours, 100)
            XCTAssertFalse(result.meets100HourTest, "100h should never pass Test 3 (answer: \(String(describing: answer)))")
            XCTAssertFalse(result.meets100HourThresholdPendingConfirmation)
            XCTAssertFalse(result.isMateriallyParticipating)
        }
    }

    func testFiveHundredHourPathIsUnaffectedByConfirmation() {
        let propertyId = UUID()
        let entries = [
            makeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs, hours: 501)
        ]

        // The 500-hour test stands on its own regardless of the 100-hour confirmation.
        for answer: Bool? in [nil, true, false] {
            let result = TaxQualificationEngine.materialParticipationStatus(
                entries: entries,
                year: currentYear,
                propertyId: propertyId,
                groupingElection: false,
                noOneParticipatedMore: answer
            )
            XCTAssertTrue(result.meets500HourTest, "500h path must hold (answer: \(String(describing: answer)))")
            XCTAssertTrue(result.isMateriallyParticipating)
        }

        // Unanswered at 501h is not a pending 100-hour prompt: participation is already established.
        let unanswered = TaxQualificationEngine.materialParticipationStatus(
            entries: entries,
            year: currentYear,
            propertyId: propertyId,
            groupingElection: false,
            noOneParticipatedMore: nil
        )
        XCTAssertTrue(unanswered.isMateriallyParticipating)
    }

    func testConfirmationDoesNotChangeREPSOutputs() {
        let propertyId = UUID()
        let entries = [
            makeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs, hours: 800)
        ]

        // REPS is measured independently of the 100-hour confirmation.
        let reps = TaxQualificationEngine.repsStatus(
            entries: entries,
            participant: .selfParticipant,
            year: currentYear,
            nonRealEstateHours: 100
        )

        XCTAssertEqual(reps.realEstateHours, 800)
        XCTAssertTrue(reps.meets750HourTest)
        XCTAssertTrue(reps.meetsMoreThanHalfPersonalServicesTest)
        XCTAssertTrue(reps.isQualified)
    }

    func testSpouseCombinationUnchangedWhenSomeoneElseDidMore() {
        let propertyId = UUID()
        let entries = [
            makeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs, hours: 60),
            makeEntry(propertyId: propertyId, participant: .spouse, category: .leasing, hours: 50)
        ]

        // Combination math (110h) is unchanged; only the Test 3 pass is gated.
        let result = TaxQualificationEngine.materialParticipationStatus(
            entries: entries,
            year: currentYear,
            propertyId: propertyId,
            groupingElection: false,
            noOneParticipatedMore: false
        )

        XCTAssertEqual(result.ownerAndSpouseHours, 110)
        XCTAssertFalse(result.meets100HourTest)
        XCTAssertFalse(result.isMateriallyParticipating)
    }

    func testMaterialParticipationGroupingCombinesProperties() {
        let propertyA = UUID()
        let propertyB = UUID()
        let entries = [
            makeEntry(propertyId: propertyA, participant: .selfParticipant, category: .repairs, hours: 300),
            makeEntry(propertyId: propertyB, participant: .spouse, category: .management, hours: 225)
        ]

        let ungrouped = TaxQualificationEngine.materialParticipationStatus(
            entries: entries,
            year: currentYear,
            propertyId: propertyA,
            groupingElection: false
        )
        XCTAssertEqual(ungrouped.ownerAndSpouseHours, 300)
        XCTAssertFalse(ungrouped.meets500HourTest)

        let grouped = TaxQualificationEngine.materialParticipationStatus(
            entries: entries,
            year: currentYear,
            propertyId: propertyA,
            groupingElection: true
        )
        XCTAssertEqual(grouped.ownerAndSpouseHours, 525)
        XCTAssertTrue(grouped.meets500HourTest)
    }

    func testUngroupedMaterialParticipationDoesNotAggregateWithoutProperty() {
        let propertyA = UUID()
        let propertyB = UUID()
        let entries = [
            makeEntry(propertyId: propertyA, participant: .selfParticipant, category: .repairs, hours: 60),
            makeEntry(propertyId: propertyB, participant: .spouse, category: .management, hours: 50)
        ]

        let result = TaxQualificationEngine.materialParticipationStatus(
            entries: entries,
            year: currentYear,
            propertyId: nil,
            groupingElection: false
        )

        XCTAssertEqual(result.ownerAndSpouseHours, 0)
        XCTAssertFalse(result.meets100HourTest)
        XCTAssertFalse(result.isMateriallyParticipating)
    }

    func testMaterialParticipationHundredHourTestIsStrictlyMoreThan100() {
        let propertyId = UUID()
        let entries = [
            makeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs, hours: 100)
        ]

        let result = TaxQualificationEngine.materialParticipationStatus(
            entries: entries,
            year: currentYear,
            propertyId: propertyId,
            groupingElection: false
        )

        XCTAssertEqual(result.ownerAndSpouseHours, 100)
        XCTAssertFalse(result.meets100HourTest)
        XCTAssertFalse(result.isMateriallyParticipating)
    }

    func testInvestorLevelHoursAreExcludedFromQualificationCalculations() {
        let propertyId = UUID()
        let entries = [
            makeEntry(propertyId: propertyId, participant: .selfParticipant, category: .investing, hours: 900)
        ]

        let reps = TaxQualificationEngine.repsStatus(
            entries: entries,
            participant: .selfParticipant,
            year: currentYear,
            nonRealEstateHours: 0
        )
        let material = TaxQualificationEngine.materialParticipationStatus(
            entries: entries,
            year: currentYear,
            propertyId: propertyId,
            groupingElection: false
        )

        XCTAssertEqual(reps.realEstateHours, 0)
        XCTAssertEqual(material.ownerAndSpouseHours, 0)
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private func makeEntry(
        propertyId: UUID,
        participant: Participant,
        category: ActivityCategory,
        hours: Double
    ) -> TimeEntry {
        TimeEntry(
            propertyId: propertyId,
            participant: participant,
            category: category,
            hours: hours,
            date: Date(),
            notes: "Test entry"
        )
    }
}

// MARK: - AI Local Parser Tests

final class AILocalParserTests: XCTestCase {

    private let service = AITimeEntryService.shared

    // We can't test private methods directly, so we test through parseTimeEntry
    // with no API key set (guarantees local parsing path)

    func testParseRepairEntry() async {
        let properties = [RentalProperty(name: "Oak House", address: "123 Oak St", propertyType: .ltr)]
        let result = await service.parseTimeEntry(from: "Fixed the leaking faucet at Oak House for 2 hours", properties: properties)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, .repairs)
        XCTAssertEqual(result?.hours, 2.0)
        XCTAssertEqual(result?.property?.name, "Oak House")
        XCTAssertEqual(result?.participant, .selfParticipant)
    }

    func testParseTravelEntry() async {
        let properties = [RentalProperty(name: "Maple", address: "456 Maple Ave", propertyType: .str)]
        let result = await service.parseTimeEntry(from: "Drove to Maple for 1.5 hours", properties: properties)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, .travel)
        XCTAssertEqual(result?.hours, 1.5)
        XCTAssertEqual(result?.property?.name, "Maple")
    }

    func testParseSpouseParticipant() async {
        let result = await service.parseTimeEntry(from: "My spouse managed the property for 3 hours", properties: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.participant, .spouse)
        XCTAssertEqual(result?.hours, 3.0)
    }

    func testParseDefaultsToManagement() async {
        let result = await service.parseTimeEntry(from: "did some stuff today 1h", properties: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, .management) // Default when no keyword matches
    }

    func testParseEstimatesRepairHoursWhenNoHoursMentioned() async {
        let result = await service.parseTimeEntry(from: "fixed the sink", properties: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.hours, 1.5) // Repairs get a useful estimate when no hours are extracted
    }

    func testParsePaintedHouseAsRepairWithSinglePropertyAndEstimatedHours() async {
        let properties = [RentalProperty(name: "Oak House", address: "123 Oak St", propertyType: .ltr)]
        let result = await service.parseTimeEntry(from: "I painted the house", properties: properties)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, .repairs)
        XCTAssertEqual(result?.hours, 3.0)
        XCTAssertEqual(result?.property?.name, "Oak House")
    }

    func testParseNaturalLanguageHourOverridesPaintEstimate() async {
        let properties = [RentalProperty(name: "Oak Street Duplex", address: "123 Oak St", propertyType: .ltr)]
        let result = await service.parseTimeEntry(from: "Painting the porch for an hour", properties: properties)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, .repairs)
        XCTAssertEqual(result?.hours, 1.0)
        XCTAssertEqual(result?.property?.name, "Oak Street Duplex")
    }

    func testParseWordBasedHours() async {
        let result = await service.parseTimeEntry(from: "painted trim for two hours", properties: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.hours, 2.0)
    }

    func testParseDictatedHalfHourPhrase() async {
        let result = await service.parseTimeEntry(from: "called the tenant for one and a half hours", properties: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.hours, 1.5)
    }

    func testParseDictatedMinutePhrase() async {
        let result = await service.parseTimeEntry(from: "reviewed receipts for thirty minutes", properties: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, .bookkeeping)
        XCTAssertEqual(result?.hours, 0.5)
    }

    func testParseDictatedMixedHoursAndMinutes() async {
        let result = await service.parseTimeEntry(from: "painted the porch for 1 hour and 30 minutes", properties: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, .repairs)
        XCTAssertEqual(result?.hours, 1.5)
    }

    func testParseMatchesPropertyByAddress() async {
        let properties = [RentalProperty(name: "Unit A", address: "1234 Washington Boulevard, Seattle", propertyType: .ltr)]
        let result = await service.parseTimeEntry(from: "Repaired plumbing at Washington 2h", properties: properties)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.property?.name, "Unit A")
    }

    func testParseMatchesPropertyByPartialNamePhrase() async {
        let properties = [
            RentalProperty(name: "Maple Avenue House", address: "555 Maple Avenue", propertyType: .ltr),
            RentalProperty(name: "Oak Street Duplex", address: "214 Oak Street", propertyType: .ltr)
        ]
        let result = await service.parseTimeEntry(from: "Called plumber about the Oak Street leak for 1 hour", properties: properties)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.category, .repairs)
        XCTAssertEqual(result?.hours, 1.0)
        XCTAssertEqual(result?.property?.name, "Oak Street Duplex")
    }

    func testParseHoursCappedAt24() async {
        let result = await service.parseTimeEntry(from: "worked 48 hours on repairs", properties: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.hours, 24.0) // Capped
    }

    func testParseHoursMinimum() async {
        let result = await service.parseTimeEntry(from: "quick repair 0.1h", properties: [])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.hours, 0.25) // Minimum
    }

    func testParseSinglePropertyAutoSelect() async {
        let properties = [RentalProperty(name: "My House", address: "555 Any St", propertyType: .ltr)]
        // Text doesn't mention the property name or address
        let result = await service.parseTimeEntry(from: "bookkeeping work 2h", properties: properties)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.property?.name, "My House") // Auto-selected when only 1 property
    }

    func testParseNoPropertyWhenMultipleAndNoMatch() async {
        let properties = [
            RentalProperty(name: "House A", address: "111 First St", propertyType: .ltr),
            RentalProperty(name: "House B", address: "222 Second St", propertyType: .str)
        ]
        let result = await service.parseTimeEntry(from: "did some legal work 1h", properties: properties)

        XCTAssertNotNil(result)
        XCTAssertNil(result?.property) // Can't determine which property
    }
}

// MARK: - UserScope Tests

final class UserScopeTests: XCTestCase {
    /// Snapshot of every unscoped auth/profile key (incl. 1.1 localProfileId).
    private var authSnapshot: AuthStateSnapshot!

    /// Saved auth state to restore after tests, since this is a hosted test.
    private var savedAppleUserId: String?
    private var savedEmailUserId: String?

    override func setUp() {
        super.setUp()
        authSnapshot = AuthStateSnapshot.capture()
        AuthStateSnapshot.clearAll()
        // Save any existing auth state from the host app
        savedAppleUserId = UserDefaults.standard.string(forKey: "appleUserId")
        savedEmailUserId = UserDefaults.standard.string(forKey: "emailUserId")
        // Clear for test isolation
        UserDefaults.standard.removeObject(forKey: "appleUserId")
        UserDefaults.standard.removeObject(forKey: "emailUserId")
        UserDefaults.standard.synchronize()
    }

    override func tearDown() {
        // Restore original auth state so we don't break the host app
        if let saved = savedAppleUserId {
            UserDefaults.standard.set(saved, forKey: "appleUserId")
        } else {
            UserDefaults.standard.removeObject(forKey: "appleUserId")
        }
        if let saved = savedEmailUserId {
            UserDefaults.standard.set(saved, forKey: "emailUserId")
        } else {
            UserDefaults.standard.removeObject(forKey: "emailUserId")
        }
        UserDefaults.standard.synchronize()
        authSnapshot.restore()
        super.tearDown()
    }

    func testUserIdReflectsCurrentAuthState() {
        // In a hosted test, we can't guarantee nil state (app may restore keys).
        // Instead, verify that setting a key updates userId correctly.
        UserDefaults.standard.set("test-user-abc", forKey: "appleUserId")
        UserDefaults.standard.synchronize()
        XCTAssertEqual(UserScope.userId, "test-user-abc")
    }

    func testUserIdReturnsAppleId() {
        UserDefaults.standard.set("apple-123", forKey: "appleUserId")
        XCTAssertEqual(UserScope.userId, "apple-123")
    }

    func testUserIdReturnsEmailIdWhenNoApple() {
        UserDefaults.standard.set("email-test@example.com", forKey: "emailUserId")
        XCTAssertEqual(UserScope.userId, "email-test@example.com")
    }

    func testAppleIdTakesPrecedenceOverEmail() {
        UserDefaults.standard.set("apple-123", forKey: "appleUserId")
        UserDefaults.standard.set("email-test@example.com", forKey: "emailUserId")
        XCTAssertEqual(UserScope.userId, "apple-123")
    }

    func testKeyScopingWithUser() {
        UserDefaults.standard.set("user-42", forKey: "appleUserId")
        XCTAssertEqual(UserScope.key("someKey"), "u.user-42.someKey")
    }

    func testKeyScopingProducesUserPrefixedKey() {
        // Verify that setting a user produces correctly prefixed keys
        UserDefaults.standard.set("scope-test-user", forKey: "appleUserId")
        UserDefaults.standard.synchronize()
        let key = UserScope.key("someKey")
        XCTAssertTrue(key.hasPrefix("u.scope-test-user."), "Key should have user prefix, got: \(key)")
        XCTAssertTrue(key.hasSuffix(".someKey"), "Key should end with base key, got: \(key)")
    }

    func testDifferentUsersGetDifferentKeys() {
        UserDefaults.standard.set("user-A", forKey: "appleUserId")
        let keyA = UserScope.key("data")

        UserDefaults.standard.set("user-B", forKey: "appleUserId")
        let keyB = UserScope.key("data")

        XCTAssertNotEqual(keyA, keyB)
        XCTAssertEqual(keyA, "u.user-A.data")
        XCTAssertEqual(keyB, "u.user-B.data")
    }
}

// MARK: - Local Data Reset Tests

@MainActor
final class AppViewModelLocalResetTests: XCTestCase {
    /// Snapshot of every unscoped auth/profile key (incl. 1.1 localProfileId).
    private var authSnapshot: AuthStateSnapshot!

    private var savedAppleUserId: String?
    private var savedEmailUserId: String?

    override func setUp() {
        super.setUp()
        authSnapshot = AuthStateSnapshot.capture()
        AuthStateSnapshot.clearAll()
        savedAppleUserId = UserDefaults.standard.string(forKey: "appleUserId")
        savedEmailUserId = UserDefaults.standard.string(forKey: "emailUserId")
        UserDefaults.standard.removeObject(forKey: "appleUserId")
        UserDefaults.standard.set("reset-test-user", forKey: "emailUserId")
        UserDefaults.standard.set("reset@example.com", forKey: "emailUserEmail")
        UserDefaults.standard.synchronize()
    }

    override func tearDown() {
        AppViewModel.clearScopedAccountData(for: "reset-test-user")
        if let savedAppleUserId {
            UserDefaults.standard.set(savedAppleUserId, forKey: "appleUserId")
        } else {
            UserDefaults.standard.removeObject(forKey: "appleUserId")
        }
        if let savedEmailUserId {
            UserDefaults.standard.set(savedEmailUserId, forKey: "emailUserId")
        } else {
            UserDefaults.standard.removeObject(forKey: "emailUserId")
        }
        UserDefaults.standard.synchronize()
        authSnapshot.restore()
        super.tearDown()
    }

    func testResetCurrentUserLocalDataClearsMemoryAndScopedPreferences() {
        let viewModel = AppViewModel()
        viewModel.properties = [RentalProperty(name: "Oak", address: "123 Oak St", propertyType: .ltr)]
        viewModel.timeEntries = [
            TimeEntry(propertyId: viewModel.properties[0].id, participant: .selfParticipant, category: .management, hours: 2, notes: "Test")
        ]
        viewModel.isTimerRunning = true
        viewModel.timerStartTime = Date()
        viewModel.timerPropertyId = viewModel.properties[0].id
        GoalManager.shared.setGlobalGoal(.str)
        CategoryManager.shared.addCategory(
            CustomCategory(name: "Custom", iconName: "house", colorHex: "7B68EE", countsForREPS: true)
        )
        TaxProfileManager.shared.nonREWorkHours = 123
        UserDefaults.standard.set(true, forKey: UserScope.key("hasCompletedOnboarding"))

        viewModel.resetCurrentUserLocalData()

        XCTAssertTrue(viewModel.properties.isEmpty)
        XCTAssertTrue(viewModel.timeEntries.isEmpty)
        XCTAssertFalse(viewModel.isTimerRunning)
        XCTAssertNil(viewModel.timerStartTime)
        XCTAssertNil(viewModel.timerPropertyId)
        XCTAssertEqual(GoalManager.shared.globalGoalType, .reps)
        XCTAssertTrue(CategoryManager.shared.customCategories.isEmpty)
        XCTAssertEqual(TaxProfileManager.shared.nonREWorkHours, 0)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: UserScope.key("hasCompletedOnboarding")))
    }
}

@MainActor
final class AppViewModelFlowTests: XCTestCase {
    /// Snapshot of every unscoped auth/profile key (incl. 1.1 localProfileId).
    private var authSnapshot: AuthStateSnapshot!

    private let testUserId = "flow-test-user"
    private var savedAppleUserId: String?
    private var savedEmailUserId: String?

    override func setUp() {
        super.setUp()
        authSnapshot = AuthStateSnapshot.capture()
        AuthStateSnapshot.clearAll()
        savedAppleUserId = UserDefaults.standard.string(forKey: "appleUserId")
        savedEmailUserId = UserDefaults.standard.string(forKey: "emailUserId")
        UserDefaults.standard.removeObject(forKey: "appleUserId")
        UserDefaults.standard.set(testUserId, forKey: "emailUserId")
        AppViewModel.clearScopedAccountData(for: testUserId)
        UserDefaults.standard.synchronize()
    }

    override func tearDown() {
        AppViewModel.clearScopedAccountData(for: testUserId)
        if let savedAppleUserId {
            UserDefaults.standard.set(savedAppleUserId, forKey: "appleUserId")
        } else {
            UserDefaults.standard.removeObject(forKey: "appleUserId")
        }
        if let savedEmailUserId {
            UserDefaults.standard.set(savedEmailUserId, forKey: "emailUserId")
        } else {
            UserDefaults.standard.removeObject(forKey: "emailUserId")
        }
        UserDefaults.standard.synchronize()
        authSnapshot.restore()
        super.tearDown()
    }

    func testDeletingPropertyRemovesEntriesAndCancelsRunningTimer() {
        let viewModel = AppViewModel()
        viewModel.suppressCelebrations = true
        viewModel.addProperty(name: "Oak", address: "123 Oak St", type: .ltr)
        let property = viewModel.properties[0]
        viewModel.addTimeEntry(
            propertyId: property.id,
            participant: .selfParticipant,
            category: .management,
            hours: 1,
            date: Date(),
            notes: "Test"
        )
        viewModel.startTimer(propertyId: property.id, category: .repairs)

        viewModel.deleteProperty(property)

        XCTAssertTrue(viewModel.properties.isEmpty)
        XCTAssertTrue(viewModel.timeEntries.isEmpty)
        XCTAssertFalse(viewModel.isTimerRunning)
        XCTAssertNil(viewModel.timerPropertyId)
        XCTAssertNil(viewModel.timerStartTime)
    }

    func testCalendarImportSkipsDuplicateExternalIdAndContentDuplicate() {
        let viewModel = AppViewModel()
        viewModel.suppressCelebrations = true
        viewModel.addProperty(name: "Oak", address: "123 Oak St", type: .ltr)
        let propertyId = viewModel.properties[0].id
        let eventDate = Date()

        let first = makeDetectedEntry(propertyId: propertyId, eventDate: eventDate, externalId: "event-1")
        XCTAssertEqual(viewModel.importCalendarEntries([first]), 1)
        XCTAssertEqual(viewModel.timeEntries.count, 1)

        XCTAssertEqual(viewModel.importCalendarEntries([first]), 0)
        XCTAssertEqual(viewModel.timeEntries.count, 1)

        let contentDuplicate = makeDetectedEntry(propertyId: propertyId, eventDate: eventDate, externalId: "event-1-copy")
        XCTAssertEqual(viewModel.importCalendarEntries([contentDuplicate]), 0)
        XCTAssertEqual(viewModel.timeEntries.count, 1)
    }

    func testStopTimerCapsStaleTimerAt24Hours() {
        let viewModel = AppViewModel()
        viewModel.suppressCelebrations = true
        viewModel.addProperty(name: "Oak", address: "123 Oak St", type: .ltr)
        let propertyId = viewModel.properties[0].id
        viewModel.startTimer(propertyId: propertyId, category: .management)
        viewModel.timerStartTime = Calendar.current.date(byAdding: .hour, value: -30, to: Date())

        viewModel.stopTimer(participant: .selfParticipant, notes: "Long timer")

        XCTAssertFalse(viewModel.isTimerRunning)
        XCTAssertTrue(viewModel.timerWasCapped)
        XCTAssertEqual(viewModel.timeEntries.count, 1)
        XCTAssertEqual(viewModel.timeEntries[0].hours, 24, accuracy: 0.01)
    }

    private func makeDetectedEntry(propertyId: UUID, eventDate: Date, externalId: String) -> DetectedCalendarEntry {
        DetectedCalendarEntry(
            sourceExternalId: externalId,
            sourceCalendarId: "calendar-1",
            eventTitle: "Plumbing repair",
            eventDate: eventDate,
            propertyId: propertyId,
            category: .repairs,
            hours: 1.5
        )
    }
}

// MARK: - Engagement Intelligence Tests

final class EngagementIntelligenceServiceTests: XCTestCase {
    private let service = EngagementIntelligenceService()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testNewUserWithoutPropertyGetsSetupNudgeNotPaceReminder() {
        let context = makeContext(
            now: date(year: 2026, month: 3, day: 15),
            properties: [],
            entries: []
        )

        let recommendation = service.recommendation(for: context, calendar: calendar)

        XCTAssertEqual(recommendation.surface, .homeNudge)
        XCTAssertEqual(recommendation.reason, .setupProperty)
        XCTAssertEqual(recommendation.destination, .addProperty)
    }

    func testRecentLogChoosesSilence() {
        let property = makeProperty()
        let context = makeContext(
            now: date(year: 2026, month: 6, day: 15),
            properties: [property],
            entries: [
                makeEntry(propertyId: property.id, date: date(year: 2026, month: 6, day: 14), hours: 350)
            ]
        )

        let recommendation = service.recommendation(for: context, calendar: calendar)

        XCTAssertEqual(recommendation, .doNothing)
    }

    func testInactiveUserGetsQuietLoggingReminder() {
        let property = makeProperty()
        let context = makeContext(
            now: date(year: 2026, month: 6, day: 15),
            properties: [property],
            entries: [
                makeEntry(propertyId: property.id, date: date(year: 2026, month: 6, day: 1), hours: 2)
            ]
        )

        let recommendation = service.recommendation(for: context, calendar: calendar)

        XCTAssertEqual(recommendation.surface, .notification)
        XCTAssertEqual(recommendation.reason, .inactiveLogging)
        XCTAssertEqual(recommendation.destination, .track)
        XCTAssertTrue(recommendation.message.contains("14 days"))
    }

    func testRepeatedDismissalSuppressesSimilarReminder() {
        let property = makeProperty()
        let context = makeContext(
            now: date(year: 2026, month: 6, day: 15),
            properties: [property],
            entries: [
                makeEntry(propertyId: property.id, date: date(year: 2026, month: 6, day: 1), hours: 2)
            ],
            dismissals: [
                EngagementDismissal(reason: .inactiveLogging, dismissedAt: date(year: 2026, month: 6, day: 10)),
                EngagementDismissal(reason: .inactiveLogging, dismissedAt: date(year: 2026, month: 6, day: 12))
            ]
        )

        let recommendation = service.recommendation(for: context, calendar: calendar)

        XCTAssertEqual(recommendation, .doNothing)
    }

    func testCalendarDraftsOutrankGenericInactivity() {
        let property = makeProperty()
        let context = makeContext(
            now: date(year: 2026, month: 6, day: 15),
            properties: [property],
            entries: [
                makeEntry(propertyId: property.id, date: date(year: 2026, month: 6, day: 1), hours: 2)
            ],
            calendarDraftCount: 2
        )

        let recommendation = service.recommendation(for: context, calendar: calendar)

        XCTAssertEqual(recommendation.surface, .notification)
        XCTAssertEqual(recommendation.reason, .calendarDraftsReady)
        XCTAssertEqual(recommendation.destination, .calendarReview)
    }

    func testLongRunningTimerUsesLiveActivityReview() {
        let property = makeProperty()
        let context = makeContext(
            now: date(year: 2026, month: 6, day: 15, hour: 14),
            properties: [property],
            entries: [
                makeEntry(propertyId: property.id, date: date(year: 2026, month: 6, day: 14), hours: 1)
            ],
            isTimerRunning: true,
            timerStartTime: date(year: 2026, month: 6, day: 15, hour: 9)
        )

        let recommendation = service.recommendation(for: context, calendar: calendar)

        XCTAssertEqual(recommendation.surface, .liveActivity)
        XCTAssertEqual(recommendation.reason, .timerSafety)
        XCTAssertEqual(recommendation.destination, .timerReview)
    }

    func testBehindPaceUsesWidgetWhenThereIsNoStrongerPrompt() {
        let property = makeProperty()
        let context = makeContext(
            now: date(year: 2026, month: 10, day: 1),
            properties: [property],
            entries: [
                makeEntry(propertyId: property.id, date: date(year: 2026, month: 9, day: 28), hours: 100)
            ]
        )

        let recommendation = service.recommendation(for: context, calendar: calendar)

        XCTAssertEqual(recommendation.surface, .widget)
        XCTAssertEqual(recommendation.reason, .behindPace)
        XCTAssertEqual(recommendation.destination, .reports)
    }

    func testYearEndExportOutranksInactivityWhenRecordsExist() {
        let property = makeProperty()
        let context = makeContext(
            now: date(year: 2026, month: 12, day: 10),
            properties: [property],
            entries: [
                makeEntry(propertyId: property.id, date: date(year: 2026, month: 11, day: 1), hours: 20)
            ]
        )

        let recommendation = service.recommendation(for: context, calendar: calendar)

        XCTAssertEqual(recommendation.surface, .notification)
        XCTAssertEqual(recommendation.reason, .yearEndExport)
        XCTAssertEqual(recommendation.destination, .export)
    }

    func testNoCalendarCandidatesDoesNotCreateCalendarPrompt() {
        let property = makeProperty()
        let context = makeContext(
            now: date(year: 2026, month: 6, day: 15),
            properties: [property],
            entries: [
                makeEntry(propertyId: property.id, date: date(year: 2026, month: 6, day: 14), hours: 350)
            ],
            calendarDraftCount: 0
        )

        let recommendation = service.recommendation(for: context, calendar: calendar)

        XCTAssertEqual(recommendation, .doNothing)
    }

    func testNotificationPlannerCreatesCalendarReviewPlan() {
        let property = makeProperty()
        let context = makeContext(
            now: date(year: 2026, month: 6, day: 15),
            properties: [property],
            entries: [
                makeEntry(propertyId: property.id, date: date(year: 2026, month: 6, day: 1), hours: 2)
            ],
            calendarDraftCount: 2
        )

        let plan = EngagementNotificationScheduler(service: service).plan(for: context)

        XCTAssertEqual(plan?.identifier, "engagement.calendarDraftsReady")
        XCTAssertEqual(plan?.reason, .calendarDraftsReady)
        XCTAssertEqual(plan?.destination, .calendarReview)
        XCTAssertEqual(plan?.delay, 60)
        XCTAssertEqual(plan?.playsSound, false)
        XCTAssertTrue(plan?.body.contains("2 calendar items may be landlord work") == true)
    }

    func testNotificationPlannerDoesNotScheduleWhenPermissionDenied() {
        let property = makeProperty()
        var context = makeContext(
            now: date(year: 2026, month: 6, day: 15),
            properties: [property],
            entries: [
                makeEntry(propertyId: property.id, date: date(year: 2026, month: 6, day: 1), hours: 2)
            ]
        )
        context.notificationPermission = .denied

        let plan = EngagementNotificationScheduler(service: service).plan(for: context)

        XCTAssertNil(plan)
    }

    func testNotificationPlannerDoesNotScheduleSilentOrWidgetRecommendations() {
        let property = makeProperty()
        let recentContext = makeContext(
            now: date(year: 2026, month: 6, day: 15),
            properties: [property],
            entries: [
                makeEntry(propertyId: property.id, date: date(year: 2026, month: 6, day: 14), hours: 350)
            ]
        )
        let widgetContext = makeContext(
            now: date(year: 2026, month: 10, day: 1),
            properties: [property],
            entries: [
                makeEntry(propertyId: property.id, date: date(year: 2026, month: 9, day: 28), hours: 100)
            ]
        )
        let scheduler = EngagementNotificationScheduler(service: service)

        XCTAssertNil(scheduler.plan(for: recentContext))
        XCTAssertNil(scheduler.plan(for: widgetContext))
    }

    func testNotificationPlannerCreatesYearEndExportPlan() {
        let property = makeProperty()
        let context = makeContext(
            now: date(year: 2026, month: 12, day: 10),
            properties: [property],
            entries: [
                makeEntry(propertyId: property.id, date: date(year: 2026, month: 11, day: 1), hours: 20)
            ]
        )

        let plan = EngagementNotificationScheduler(service: service).plan(for: context)

        XCTAssertEqual(plan?.identifier, "engagement.yearEndExport")
        XCTAssertEqual(plan?.reason, .yearEndExport)
        XCTAssertEqual(plan?.destination, .export)
        XCTAssertEqual(plan?.cooldownDays, 14)
        XCTAssertEqual(plan?.playsSound, false)
    }

    func testNotificationPlannerSuppressesRecentlyScheduledPlanWhenRespectingCooldown() {
        let property = makeProperty()
        let suiteName = "LandlordHoursTests.notificationCooldown.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let context = makeContext(
            now: date(year: 2026, month: 6, day: 15),
            properties: [property],
            entries: [
                makeEntry(propertyId: property.id, date: date(year: 2026, month: 6, day: 1), hours: 2)
            ]
        )
        let scheduler = EngagementNotificationScheduler(service: service, defaults: defaults)
        let firstPlan = scheduler.plan(for: context)

        XCTAssertNotNil(firstPlan)

        scheduler.markScheduled(firstPlan!, at: date(year: 2026, month: 6, day: 14))

        XCTAssertNil(scheduler.plan(for: context, respectingCooldown: true))
        XCTAssertNotNil(scheduler.plan(for: context, respectingCooldown: false))
    }

    func testWidgetSnapshotKeepsSetupStateActionable() {
        let snapshot = EngagementWidgetSnapshot.empty

        XCTAssertEqual(snapshot.headline, "Set up tracking")
        XCTAssertEqual(snapshot.detail, "Add a property before pace checks begin.")
        XCTAssertEqual(snapshot.actionLabel, "Add property")
        XCTAssertEqual(snapshot.recommendationDestination, .addProperty)
        XCTAssertEqual(snapshot.progress, 0)
        XCTAssertEqual(snapshot.targetLabel, "750h REPS")
    }

    func testWidgetSnapshotShowsBehindPaceAsReportAction() {
        // isStale compares against the real clock, so anchor updatedAt to now;
        // a fixed calendar date made this test fail once that date was 36h old.
        let snapshot = EngagementWidgetSnapshot(
            updatedAt: Date(),
            taxYear: 2026,
            propertyCount: 2,
            yearHours: 100,
            targetHours: 750,
            targetLabel: "750h REPS",
            targetShortLabel: "750h",
            requiredHoursToDate: 560,
            daysRemainingInYear: 91,
            lastLogDate: date(year: 2026, month: 9, day: 28),
            isTimerRunning: false,
            timerStartTime: nil,
            recommendationSurface: .widget,
            recommendationReason: .behindPace,
            recommendationDestination: .reports,
            recommendationTitle: "Behind REPS pace",
            recommendationMessage: "Review your pace before the year gets tighter."
        )

        XCTAssertEqual(snapshot.headline, "460h behind")
        XCTAssertEqual(snapshot.actionLabel, "Review pace")
        XCTAssertTrue(snapshot.isBehindPace)
        XCTAssertEqual(snapshot.progress, 100.0 / 750.0, accuracy: 0.001)
    }

    func testWidgetSnapshotUsesConfiguredGoalTarget() {
        let snapshot = EngagementWidgetSnapshot(
            updatedAt: date(year: 2026, month: 6, day: 15),
            taxYear: 2026,
            propertyCount: 1,
            yearHours: 40,
            targetHours: 100,
            targetLabel: "100h STR",
            targetShortLabel: "100h",
            requiredHoursToDate: 45,
            daysRemainingInYear: 199,
            lastLogDate: date(year: 2026, month: 6, day: 14),
            isTimerRunning: false,
            timerStartTime: nil,
            recommendationSurface: .none,
            recommendationReason: .noActionNeeded,
            recommendationDestination: .none,
            recommendationTitle: "",
            recommendationMessage: ""
        )

        XCTAssertEqual(snapshot.progress, 0.4, accuracy: 0.001)
        XCTAssertEqual(snapshot.targetShortLabel, "100h")
    }

    func testWidgetSnapshotPrioritizesRunningTimer() {
        let start = date(year: 2026, month: 6, day: 15, hour: 9)
        let snapshot = EngagementWidgetSnapshot(
            updatedAt: date(year: 2026, month: 6, day: 15, hour: 11),
            taxYear: 2026,
            propertyCount: 1,
            yearHours: 42,
            targetHours: 750,
            targetLabel: "750h REPS",
            targetShortLabel: "750h",
            requiredHoursToDate: 340,
            daysRemainingInYear: 199,
            lastLogDate: nil,
            isTimerRunning: true,
            timerStartTime: start,
            recommendationSurface: .liveActivity,
            recommendationReason: .timerSafety,
            recommendationDestination: .timerReview,
            recommendationTitle: "Timer still running",
            recommendationMessage: "Review the session before saving."
        )

        XCTAssertEqual(snapshot.headline, "Timer active")
        XCTAssertEqual(snapshot.detail, "Review before saving.")
        XCTAssertEqual(snapshot.actionLabel, "Review")
        XCTAssertEqual(snapshot.timerStartTime, start)
    }

    private func makeContext(
        now: Date,
        properties: [RentalProperty],
        entries: [TimeEntry],
        calendarDraftCount: Int = 0,
        isTimerRunning: Bool = false,
        timerStartTime: Date? = nil,
        dismissals: [EngagementDismissal] = [],
        isProUser: Bool = false
    ) -> EngagementContext {
        EngagementContext(
            now: now,
            taxYear: calendar.component(.year, from: now),
            properties: properties,
            timeEntries: entries,
            calendarDraftCount: calendarDraftCount,
            isTimerRunning: isTimerRunning,
            timerStartTime: timerStartTime,
            notificationPermission: .authorized,
            recentDismissals: dismissals,
            isProUser: isProUser
        )
    }

    private func makeProperty() -> RentalProperty {
        RentalProperty(name: "Oak Street Duplex", address: "123 Oak St", propertyType: .ltr)
    }

    private func makeEntry(propertyId: UUID, date: Date, hours: Double) -> TimeEntry {
        TimeEntry(
            propertyId: propertyId,
            participant: .selfParticipant,
            category: .management,
            hours: hours,
            date: date,
            notes: "Test landlord work"
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }
}

// MARK: - Date Extension Tests

final class DateExtensionTests: XCTestCase {

    func testStartOfDay() {
        let now = Date()
        let start = now.startOfDay
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: start)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.second, 0)
    }

    func testIsToday() {
        XCTAssertTrue(Date().isToday)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertFalse(yesterday.isToday)
    }

    func testShortAddress() {
        let property = RentalProperty(name: "Test", address: "123 Main St, Portland, OR 97201", propertyType: .ltr)
        XCTAssertEqual(property.shortAddress, "123 Main St")
    }

    func testShortAddressNoComma() {
        let property = RentalProperty(name: "Test", address: "123 Main St", propertyType: .ltr)
        XCTAssertEqual(property.shortAddress, "123 Main St")
    }
}

// MARK: - TimeEntry Formatting Tests

final class TimeEntryFormattingTests: XCTestCase {

    func testFormattedDuration() {
        let entry = TimeEntry(propertyId: UUID(), participant: .selfParticipant, category: .repairs, hours: 2.5)
        XCTAssertEqual(entry.formattedDuration, "2.5h")
    }

    func testFormattedDurationWholeNumber() {
        let entry = TimeEntry(propertyId: UUID(), participant: .selfParticipant, category: .repairs, hours: 3.0)
        XCTAssertEqual(entry.formattedDuration, "3.0h")
    }

    func testGetPropertyName() {
        let propertyId = UUID()
        let properties = [
            RentalProperty(id: propertyId, name: "Oak House", address: "123 Oak St", propertyType: .ltr)
        ]
        let entry = TimeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs, hours: 1)
        XCTAssertEqual(entry.getPropertyName(from: properties), "Oak House")
    }

    func testGetPropertyNameUnknownWhenMissing() {
        let entry = TimeEntry(propertyId: UUID(), participant: .selfParticipant, category: .repairs, hours: 1)
        XCTAssertEqual(entry.getPropertyName(from: []), "Unknown")
    }
}

// MARK: - TimeEntry importSource Backward Compatibility Tests

final class TimeEntryImportSourceTests: XCTestCase {

    func testTimeEntryDecodesWithoutImportSource() throws {
        // Old entries that lack importSource should decode with nil
        let propertyId = UUID()
        let json = """
        {"id":"550e8400-e29b-41d4-a716-446655440002","propertyId":"\(propertyId.uuidString)","participant":"Self","category":"Repairs & Maintenance","hours":1.0,"date":0,"notes":"test","createdAt":0}
        """
        let decoded = try JSONDecoder().decode(TimeEntry.self, from: Data(json.utf8))
        XCTAssertNil(decoded.importSource)
    }

    func testTimeEntryRoundtripWithImportSource() throws {
        let entry = TimeEntry(
            propertyId: UUID(),
            participant: .selfParticipant,
            category: .management,
            hours: 2.0,
            importSource: "calendar",
            importExternalId: "event-123",
            importCalendarId: "calendar-abc"
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(TimeEntry.self, from: data)
        XCTAssertEqual(decoded.importSource, "calendar")
        XCTAssertEqual(decoded.importExternalId, "event-123")
        XCTAssertEqual(decoded.importCalendarId, "calendar-abc")
    }

    func testTimeEntryRoundtripWithNilImportSource() throws {
        let entry = TimeEntry(
            propertyId: UUID(),
            participant: .selfParticipant,
            category: .repairs,
            hours: 1.0
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(TimeEntry.self, from: data)
        XCTAssertNil(decoded.importSource)
    }

    func testExistingInitDefaultsToNilImportSource() {
        let entry = TimeEntry(
            propertyId: UUID(),
            participant: .selfParticipant,
            category: .repairs,
            hours: 1.0
        )
        XCTAssertNil(entry.importSource)
    }
}

// MARK: - CalendarImportService Categorization Tests

final class CalendarImportServiceTests: XCTestCase {

    func testCategorizeRepairEvent() {
        let service = CalendarImportService.shared
        XCTAssertEqual(service.categorizeEvent(title: "Plumber at Oak House"), .repairs)
        XCTAssertEqual(service.categorizeEvent(title: "HVAC maintenance"), .repairs)
        XCTAssertEqual(service.categorizeEvent(title: "Fix leaking pipe"), .repairs)
    }

    func testCategorizeLeasingEvent() {
        let service = CalendarImportService.shared
        XCTAssertEqual(service.categorizeEvent(title: "Tenant screening call"), .leasing)
        XCTAssertEqual(service.categorizeEvent(title: "Lease signing meeting"), .leasing)
        XCTAssertEqual(service.categorizeEvent(title: "Property showing"), .leasing)
    }

    func testCategorizeTravelEvent() {
        let service = CalendarImportService.shared
        XCTAssertEqual(service.categorizeEvent(title: "Inspection walkthrough"), .travel)
    }

    func testCategorizeRenovationEvent() {
        let service = CalendarImportService.shared
        XCTAssertEqual(service.categorizeEvent(title: "Contractor meeting"), .renovations)
        XCTAssertEqual(service.categorizeEvent(title: "Closing on property"), .renovations)
    }

    func testCategorizeInsuranceEvent() {
        let service = CalendarImportService.shared
        XCTAssertEqual(service.categorizeEvent(title: "Insurance claim follow-up"), .insurance)
    }

    func testCategorizeLegalEvent() {
        let service = CalendarImportService.shared
        XCTAssertEqual(service.categorizeEvent(title: "Legal consultation"), .legal)
        XCTAssertEqual(service.categorizeEvent(title: "Eviction hearing"), .legal)
    }

    func testCategorizeDefaultsToManagement() {
        let service = CalendarImportService.shared
        XCTAssertEqual(service.categorizeEvent(title: "Property check"), .management)
        XCTAssertEqual(service.categorizeEvent(title: "Random meeting"), .management)
    }
}

// MARK: - TimeAttachment File Storage Tests

final class TimeAttachmentStorageTests: XCTestCase {

    func testEncodeOmitsInlineData() throws {
        let attachment = TimeAttachment(filename: "receipt.jpg", data: Data([1, 2, 3]), mimeType: "image/jpeg")
        let encoded = try JSONEncoder().encode(attachment)
        let json = String(decoding: encoded, as: UTF8.self)
        // Bytes must never ride along in the persisted blob — that is the whole point.
        XCTAssertFalse(json.contains("\"data\""))
        XCTAssertTrue(attachment.hasPendingData)
    }

    func testDecodeLegacyInlineDataBecomesPending() throws {
        let bytes = Data([9, 8, 7, 6, 5])
        let base64 = bytes.base64EncodedString()
        let id = UUID()
        let json = "{\"id\":\"\(id.uuidString)\",\"filename\":\"receipt.jpg\",\"data\":\"\(base64)\",\"mimeType\":\"image/jpeg\",\"createdAt\":0,\"modifiedAt\":0}"
        let decoded = try JSONDecoder().decode(TimeAttachment.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.id, id)
        XCTAssertTrue(decoded.hasPendingData)
        XCTAssertEqual(decoded.pendingBytes, bytes)
    }

    func testFileExtensionDerivation() {
        XCTAssertEqual(TimeAttachment(filename: "receipt.PNG", data: Data(), mimeType: "image/png").fileExtension, "png")
        XCTAssertEqual(TimeAttachment(filename: "noextension", data: Data(), mimeType: "image/jpeg").fileExtension, "jpeg")
    }

    func testAttachmentStoreWriteReadDeleteRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AttachmentStore(directory: dir)
        let attachment = TimeAttachment(filename: "receipt.jpg", data: Data([1, 2, 3]), mimeType: "image/jpeg")
        let bytes = Data([4, 5, 6, 7, 8])

        try store.write(bytes, for: attachment)
        XCTAssertTrue(store.fileExists(for: attachment))
        XCTAssertEqual(store.read(attachment), bytes)

        store.delete(attachment)
        XCTAssertFalse(store.fileExists(for: attachment))
        XCTAssertNil(store.read(attachment))
    }

    func testAttachmentStoreWriteThrowsWhenDirectoryUnwritable() throws {
        // Point the store at a path nested under a regular file so directory creation fails.
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("x".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = AttachmentStore(directory: fileURL.appendingPathComponent("nested", isDirectory: true))
        let attachment = TimeAttachment(filename: "receipt.jpg", data: Data(), mimeType: "image/jpeg")

        XCTAssertThrowsError(try store.write(Data([1, 2, 3]), for: attachment))
    }
}

// MARK: - Persistence Hardening Tests

@MainActor
final class PersistenceHardeningTests: XCTestCase {
    /// Snapshot of every unscoped auth/profile key (incl. 1.1 localProfileId).
    private var authSnapshot: AuthStateSnapshot!

    private let testUserId = "persistence-test-user"
    private var savedAppleUserId: String?
    private var savedEmailUserId: String?
    private var savedAttachmentStore: AttachmentStore!
    private var attachmentDir: URL!

    override func setUp() {
        super.setUp()
        authSnapshot = AuthStateSnapshot.capture()
        AuthStateSnapshot.clearAll()
        savedAppleUserId = UserDefaults.standard.string(forKey: "appleUserId")
        savedEmailUserId = UserDefaults.standard.string(forKey: "emailUserId")
        UserDefaults.standard.removeObject(forKey: "appleUserId")
        UserDefaults.standard.set(testUserId, forKey: "emailUserId")
        AppViewModel.clearScopedAccountData(for: testUserId)
        UserDefaults.standard.synchronize()

        // Isolate attachment storage to a fresh temp directory for each test.
        savedAttachmentStore = AttachmentStore.shared
        attachmentDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("attachments-test-\(UUID().uuidString)", isDirectory: true)
        AttachmentStore.shared = AttachmentStore(directory: attachmentDir)
    }

    override func tearDown() {
        AttachmentStore.shared = savedAttachmentStore
        if let attachmentDir { try? FileManager.default.removeItem(at: attachmentDir) }
        AppViewModel.clearScopedAccountData(for: testUserId)
        if let savedAppleUserId {
            UserDefaults.standard.set(savedAppleUserId, forKey: "appleUserId")
        } else {
            UserDefaults.standard.removeObject(forKey: "appleUserId")
        }
        if let savedEmailUserId {
            UserDefaults.standard.set(savedEmailUserId, forKey: "emailUserId")
        } else {
            UserDefaults.standard.removeObject(forKey: "emailUserId")
        }
        UserDefaults.standard.synchronize()
        authSnapshot.restore()
        super.tearDown()
    }

    private func makeLocalDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    func testSaveLoadRoundTripWithAttachments() {
        let viewModel = AppViewModel()
        viewModel.suppressCelebrations = true
        viewModel.addProperty(name: "Oak", address: "123 Oak St", type: .ltr)
        let propertyId = viewModel.properties[0].id

        let bytes = Data([10, 20, 30, 40, 50])
        viewModel.addTimeEntry(
            propertyId: propertyId,
            participant: .selfParticipant,
            category: .repairs,
            hours: 2.0,
            date: Date(),
            notes: "Fixed sink",
            attachments: [TimeAttachment(filename: "receipt.jpg", data: bytes, mimeType: "image/jpeg")]
        )

        XCTAssertNil(viewModel.persistenceError)
        let attachment = viewModel.timeEntries[0].attachments[0]
        XCTAssertTrue(AttachmentStore.shared.fileExists(for: attachment))
        XCTAssertFalse(attachment.hasPendingData, "Bytes should be flushed to disk after save")

        // Fresh view model reloads from the persisted store.
        let reloaded = AppViewModel()
        XCTAssertEqual(reloaded.properties.count, 1)
        XCTAssertEqual(reloaded.timeEntries.count, 1)
        let reloadedAttachment = reloaded.timeEntries[0].attachments[0]
        XCTAssertFalse(reloadedAttachment.hasPendingData)
        XCTAssertEqual(reloadedAttachment.data, bytes, "Attachment bytes must survive a reload from disk")
        XCTAssertNil(reloaded.persistenceError)
    }

    func testLegacyInlineAttachmentMigratesToFileAndIsIdempotent() {
        let bytes = Data([1, 2, 3, 4, 5, 6])
        let base64 = bytes.base64EncodedString()
        let propertyId = UUID()
        let entryId = UUID()
        let attachmentId = UUID()

        // Hand-crafted legacy blob with inline base64 `data`, as older builds wrote it.
        let legacyJSON = "[{\"id\":\"\(entryId.uuidString)\",\"propertyId\":\"\(propertyId.uuidString)\",\"participant\":\"Self\",\"category\":\"Repairs & Maintenance\",\"hours\":2.0,\"date\":0,\"notes\":\"legacy\",\"attachments\":[{\"id\":\"\(attachmentId.uuidString)\",\"filename\":\"receipt.jpg\",\"data\":\"\(base64)\",\"mimeType\":\"image/jpeg\",\"createdAt\":0,\"modifiedAt\":0}],\"createdAt\":0,\"modifiedAt\":0}]"
        UserDefaults.standard.set(Data(legacyJSON.utf8), forKey: UserScope.key("LandlordHours.entries"))

        // First launch: decode + migrate.
        let viewModel = AppViewModel()
        XCTAssertEqual(viewModel.timeEntries.count, 1)
        let attachment = viewModel.timeEntries[0].attachments[0]
        XCTAssertTrue(AttachmentStore.shared.fileExists(for: attachment), "Legacy bytes must be written to a file")
        XCTAssertEqual(attachment.data, bytes)
        XCTAssertFalse(attachment.hasPendingData, "Migration should clear the in-memory inline copy")

        // The re-saved blob must no longer carry the inline bytes.
        let savedData = UserDefaults.standard.data(forKey: UserScope.key("LandlordHours.entries"))!
        let savedString = String(decoding: savedData, as: UTF8.self)
        XCTAssertFalse(savedString.contains(base64), "Migration must drop inline bytes from the persisted blob")

        // Second launch on the migrated blob: idempotent no-op, bytes still load from disk.
        let reloaded = AppViewModel()
        XCTAssertEqual(reloaded.timeEntries.count, 1)
        let reloadedAttachment = reloaded.timeEntries[0].attachments[0]
        XCTAssertFalse(reloadedAttachment.hasPendingData)
        XCTAssertEqual(reloadedAttachment.data, bytes, "Re-running migration must be safe and preserve bytes")
    }

    func testCorruptBlobSurfacesErrorWithoutCrashOrSilentEmptyState() {
        // A present-but-undecodable entries blob is corruption, not an empty dataset.
        UserDefaults.standard.set(Data("this is not valid json".utf8), forKey: UserScope.key("LandlordHours.entries"))

        let viewModel = AppViewModel()

        XCTAssertNotNil(viewModel.persistenceError, "Corrupt store must surface an error")
        XCTAssertTrue(viewModel.timeEntries.isEmpty)
    }

    func testFreshInstallDoesNotSurfaceErrorForEmptyStore() {
        // No saved blob at all is a legitimate empty dataset — no error banner.
        let viewModel = AppViewModel()
        XCTAssertNil(viewModel.persistenceError)
        XCTAssertTrue(viewModel.timeEntries.isEmpty)
        XCTAssertTrue(viewModel.properties.isEmpty)
    }

    func testSaveFailureSetsPublishedError() throws {
        // Redirect attachment storage to a path that cannot be written.
        let unwritableFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("x".utf8).write(to: unwritableFile)
        defer { try? FileManager.default.removeItem(at: unwritableFile) }
        AttachmentStore.shared = AttachmentStore(directory: unwritableFile.appendingPathComponent("nested", isDirectory: true))

        let viewModel = AppViewModel()
        viewModel.suppressCelebrations = true
        // A save without attachments succeeds.
        viewModel.addProperty(name: "Oak", address: "123 Oak St", type: .ltr)
        XCTAssertNil(viewModel.persistenceError)

        // A save that must flush an attachment file fails and surfaces the error.
        viewModel.addTimeEntry(
            propertyId: viewModel.properties[0].id,
            participant: .selfParticipant,
            category: .repairs,
            hours: 1.0,
            date: Date(),
            notes: "receipt",
            attachments: [TimeAttachment(filename: "receipt.jpg", data: Data([1, 2, 3]), mimeType: "image/jpeg")]
        )

        XCTAssertNotNil(viewModel.persistenceError, "A failed save must set the published error")
    }

    func testEntriesForYearTaxBoundaries() {
        let viewModel = AppViewModel()
        viewModel.suppressCelebrations = true
        let propertyId = UUID()
        func entry(on date: Date) -> TimeEntry {
            TimeEntry(propertyId: propertyId, participant: .selfParticipant, category: .repairs, hours: 1.0, date: date)
        }

        let dec31_2025_2300 = makeLocalDate(2025, 12, 31, 23, 0)
        let jan1_2026_0000 = makeLocalDate(2026, 1, 1, 0, 0)
        let mid2024 = makeLocalDate(2024, 6, 15, 12, 0)

        viewModel.timeEntries = [entry(on: dec31_2025_2300), entry(on: jan1_2026_0000), entry(on: mid2024)]

        // Dec 31 23:00 local belongs to 2025, not 2026.
        let year2025 = viewModel.entriesForYear(2025)
        XCTAssertEqual(year2025.count, 1)
        XCTAssertEqual(year2025.first?.date, dec31_2025_2300)

        // Jan 1 00:00 local belongs to 2026.
        let year2026 = viewModel.entriesForYear(2026)
        XCTAssertEqual(year2026.count, 1)
        XCTAssertEqual(year2026.first?.date, jan1_2026_0000)

        // Prior-year entry is excluded from both boundary years.
        XCTAssertFalse(year2025.contains { $0.date == mid2024 })
        XCTAssertFalse(year2026.contains { $0.date == mid2024 })
        XCTAssertEqual(viewModel.entriesForYear(2024).count, 1)
    }
}

// MARK: - Analytics Opt-Out Tests

/// Covers the Settings "Share Anonymous Usage Data" toggle's persistence mechanics.
/// `Analytics.setOptOut` never runs configured in XCTest (see `Analytics.shouldConfigure`,
/// which explicitly gates off whenever `XCTestConfigurationFilePath` is present), so these
/// tests exercise the two things that ARE testable without a live PostHog SDK instance:
/// the UserDefaults-backed persistence the Settings toggle relies on (`Analytics.isOptedOut`,
/// the same key `@AppStorage(Analytics.optOutKey)` binds to in `SettingsView`), and the pure
/// gating functions (`shouldSend`) that decide whether an opted-out user's events go out.
final class AnalyticsOptOutTests: XCTestCase {

    private var savedOptOutValue: Bool?

    override func setUp() {
        super.setUp()
        savedOptOutValue = UserDefaults.standard.object(forKey: Analytics.optOutKey) as? Bool
        UserDefaults.standard.removeObject(forKey: Analytics.optOutKey)
    }

    override func tearDown() {
        if let savedOptOutValue {
            UserDefaults.standard.set(savedOptOutValue, forKey: Analytics.optOutKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Analytics.optOutKey)
        }
        super.tearDown()
    }

    /// A fresh install (no key written yet) must read as shared/opted-in — the toggle defaults
    /// to ON, matching `@AppStorage(Analytics.optOutKey) private var analyticsOptedOut = false`
    /// in `SettingsView`.
    func testDefaultsToSharedWhenKeyNeverWritten() {
        XCTAssertFalse(Analytics.isOptedOut, "No stored preference must read as shared (opted in) by default")
    }

    /// Mirrors exactly what flipping the Settings toggle does: `SettingsView`'s
    /// `shareAnalyticsBinding` writes straight to `UserDefaults` under `Analytics.optOutKey`
    /// (via `@AppStorage`), and `Analytics.isOptedOut` is the read side of that same key.
    func testTogglingWritesUserDefaultsKey() {
        UserDefaults.standard.set(true, forKey: Analytics.optOutKey)
        XCTAssertTrue(Analytics.isOptedOut, "Turning the toggle off (opting out) must persist true under the opt-out key")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: Analytics.optOutKey))

        UserDefaults.standard.set(false, forKey: Analytics.optOutKey)
        XCTAssertFalse(Analytics.isOptedOut, "Turning the toggle back on (sharing) must persist false under the opt-out key")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: Analytics.optOutKey))
    }

    /// `setOptOut` is safe to call in either order without crashing or leaving the SDK in a bad
    /// state, whether or not analytics ever configured (it never does under XCTest — see the
    /// class doc comment). This is the "round trip" the toggle performs every time the user
    /// flips it back and forth.
    func testSetOptOutRoundTripsWithoutCrashing() {
        XCTAssertFalse(Analytics.isConfigured, "Analytics must never configure under XCTest (XCTestConfigurationFilePath gate)")

        Analytics.setOptOut(true)
        XCTAssertFalse(Analytics.isConfigured, "setOptOut must not itself configure analytics")

        Analytics.setOptOut(false)
        XCTAssertFalse(Analytics.isConfigured, "setOptOut must remain a no-op guard when analytics was never configured")
    }

    /// The gating check `capture()` runs on every call: an opted-out user's events must never
    /// send, and flipping back to opted-in must be honored on the very next call — no caching,
    /// no delayed effect.
    func testShouldSendHonorsOptOutImmediately() {
        XCTAssertTrue(Analytics.shouldSend(configured: true, optedOut: false), "Configured + opted in must send")
        XCTAssertFalse(Analytics.shouldSend(configured: true, optedOut: true), "Configured + opted out must never send")
        XCTAssertFalse(Analytics.shouldSend(configured: false, optedOut: false), "Never-configured must never send, opt-out state aside")
    }
}

// MARK: - Privacy: no network in the time entry parser

final class AITimeEntryServiceNetworkTests: XCTestCase {

    /// Counts any request that goes through URLSession's protocol machinery.
    final class RecordingURLProtocol: URLProtocol {
        static var requestCount = 0
        override class func canInit(with request: URLRequest) -> Bool {
            requestCount += 1
            return false
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {}
        override func stopLoading() {}
    }

    func testParsingMakesNoNetworkRequests() async {
        RecordingURLProtocol.requestCount = 0
        URLProtocol.registerClass(RecordingURLProtocol.self)
        defer { URLProtocol.unregisterClass(RecordingURLProtocol.self) }

        let properties = [RentalProperty(name: "Oak House", address: "123 Oak St", propertyType: .ltr)]
        let result = await AITimeEntryService.shared.parseTimeEntry(
            from: "Fixed the leaking faucet at Oak House for 2 hours", properties: properties)

        XCTAssertNotNil(result)
        XCTAssertEqual(RecordingURLProtocol.requestCount, 0)
    }

    func testServiceSourceHasNoNetworkCode() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/Services/AITimeEntryService.swift")
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("Source not readable from this test host")
        }
        for banned in ["URLSession", "URLRequest", "minimax", "MINIMAX", "http://", "https://"] {
            XCTAssertFalse(source.contains(banned), "AITimeEntryService must stay on-device: found \(banned)")
        }
    }
}
