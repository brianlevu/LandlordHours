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

        let result = TaxQualificationEngine.materialParticipationStatus(
            entries: entries,
            year: currentYear,
            propertyId: propertyId,
            groupingElection: false
        )

        XCTAssertEqual(result.ownerAndSpouseHours, 110)
        XCTAssertTrue(result.meets100HourTest)
        XCTAssertTrue(result.isMateriallyParticipating)
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

    /// Saved auth state to restore after tests, since this is a hosted test.
    private var savedAppleUserId: String?
    private var savedEmailUserId: String?

    override func setUp() {
        super.setUp()
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

    private var savedAppleUserId: String?
    private var savedEmailUserId: String?

    override func setUp() {
        super.setUp()
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

    private let testUserId = "flow-test-user"
    private var savedAppleUserId: String?
    private var savedEmailUserId: String?

    override func setUp() {
        super.setUp()
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
