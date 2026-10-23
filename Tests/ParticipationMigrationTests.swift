import XCTest
@testable import LandlordHours

// MARK: - 2.1: the "did anyone else do more?" answer, per rental
//
// The 2.0 app kept one answer per tax year. 2.1 keeps one per rental (and one for the grouped
// activity). These tests cover the copy from the old answers, its idempotence, what a rental
// added later gets, the lifecycle hooks (delete, reset, sign-out, profile switch) and the tax
// engine reading each rental's own answer.

@MainActor
final class ParticipationMigrationTests: CaptureTestCase {
    private var tax: TaxProfileManager { TaxProfileManager.shared }
    private var savedGrouping = false

    private var legacyKey: String { UserScope.key("LandlordHours.taxProfile.noOneParticipatedMore") }
    private var answersKey: String { UserScope.key("LandlordHours.taxProfile.noOneParticipatedMore.v2") }
    private var migrationKey: String { UserScope.key("LandlordHours.taxProfile.noOneParticipatedMore.v2.migration") }

    override func setUp() async throws {
        try await super.setUp()
        tax.reload()                     // read the fresh test profile, not the host's
        RentalPlanStore.shared.reload()
        savedGrouping = tax.groupingElection
    }

    override func tearDown() async throws {
        tax.groupingElection = savedGrouping
        try await super.tearDown()
        // super cleared the profile's keys and restored the host's identity: read it again.
        tax.reload()
        RentalPlanStore.shared.reload()
    }

    /// Writes the 2.0 per-year map exactly as 2.0 stored it.
    private func writeLegacy(_ map: [Int: Bool]) {
        let encodable = Dictionary(uniqueKeysWithValues: map.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(try! JSONEncoder().encode(encodable), forKey: legacyKey)
    }

    private func rental(_ name: String, _ type: PropertyType = .str, created: Date = Date()) -> RentalProperty {
        var p = RentalProperty(name: name, address: name, propertyType: type)
        p.createdAt = created
        return p
    }

    /// A 2.0 install upgrading: two rentals and the 2025/2026 answers already on disk, then the
    /// app launches (reload stamps the migration) and the rentals load.
    private func upgradedInstall() -> (RentalProperty, RentalProperty) {
        let a = rental("Santa", created: Date(timeIntervalSinceNow: -86_400 * 300))
        let b = rental("Cabin", created: Date(timeIntervalSinceNow: -86_400 * 100))
        writeLegacy([2025: true, 2026: false])
        tax.reload()
        tax.migrateParticipationAnswers(properties: [a, b])
        return (a, b)
    }

    // MARK: Migration

    func testLegacyAnswersCopyToEachExistingRentalAndTheGroupedActivity() {
        let (a, b) = upgradedInstall()
        for id in [a.id, b.id] {
            XCTAssertEqual(tax.noOneParticipatedMore(forYear: 2025, propertyId: id), true)
            XCTAssertEqual(tax.noOneParticipatedMore(forYear: 2026, propertyId: id), false)
        }
        XCTAssertEqual(tax.noOneParticipatedMore(forYear: 2025, propertyId: nil), true)
        XCTAssertEqual(tax.noOneParticipatedMore(forYear: 2026, propertyId: nil), false)
        XCTAssertEqual(tax.noOneParticipatedMore(forYear: 2025), true, "the year-only accessor is the grouped answer")
        XCTAssertNil(tax.noOneParticipatedMore(forYear: 2024, propertyId: a.id))
    }

    func testLegacyKeyIsByteIdenticalAfterwards() {
        let a = rental("Santa", created: Date(timeIntervalSinceNow: -3_600))
        writeLegacy([2025: true, 2026: false])
        let before = UserDefaults.standard.data(forKey: legacyKey)
        tax.reload()
        tax.migrateParticipationAnswers(properties: [a])
        tax.setNoOneParticipatedMore(true, forYear: 2026, propertyId: a.id)
        tax.setNoOneParticipatedMore(nil, forYear: 2025, propertyId: nil)
        XCTAssertEqual(UserDefaults.standard.data(forKey: legacyKey), before, "the 2.0 map is never rewritten")
        XCTAssertEqual(tax.noOneParticipatedMoreByYear, [2025: true, 2026: false])
    }

    func testMigrationIsIdempotent() {
        let (a, b) = upgradedInstall()
        let answers = UserDefaults.standard.data(forKey: answersKey)
        let state = UserDefaults.standard.data(forKey: migrationKey)
        for _ in 0..<3 { tax.migrateParticipationAnswers(properties: [a, b]) }
        XCTAssertEqual(UserDefaults.standard.data(forKey: answersKey), answers)
        XCTAssertEqual(UserDefaults.standard.data(forKey: migrationKey), state)
        XCTAssertEqual(tax.participationAnswers.count, 6, "2 years x (2 rentals + grouped)")
    }

    func testAMigratedRentalTheOwnerClearedStaysCleared() {
        let (a, b) = upgradedInstall()
        tax.setNoOneParticipatedMore(nil, forYear: 2025, propertyId: a.id)
        tax.setNoOneParticipatedMore(nil, forYear: 2025, propertyId: nil)
        tax.migrateParticipationAnswers(properties: [a, b])
        tax.reload()
        tax.migrateParticipationAnswers(properties: [a, b])
        XCTAssertNil(tax.noOneParticipatedMore(forYear: 2025, propertyId: a.id), "the migration never re-fills a cleared answer")
        XCTAssertNil(tax.noOneParticipatedMore(forYear: 2025, propertyId: nil))
        XCTAssertEqual(tax.noOneParticipatedMore(forYear: 2025, propertyId: b.id), true)
    }

    func testARentalCreatedAfterTheStampDoesNotInherit() {
        let (a, b) = upgradedInstall()
        let later = rental("New", created: Date(timeIntervalSinceNow: 3_600))
        tax.migrateParticipationAnswers(properties: [a, b, later])
        XCTAssertNil(tax.noOneParticipatedMore(forYear: 2025, propertyId: later.id))
        XCTAssertNil(tax.noOneParticipatedMore(forYear: 2026, propertyId: later.id))
    }

    func testARentalArrivingLaterThatPredatesTheStampInherits() {
        let (a, b) = upgradedInstall()
        // Pulled from iCloud after the first launch, but created on another device long ago.
        let fromCloud = rental("Delaney", .ltr, created: Date(timeIntervalSinceNow: -86_400 * 500))
        tax.migrateParticipationAnswers(properties: [a, b, fromCloud])
        XCTAssertEqual(tax.noOneParticipatedMore(forYear: 2025, propertyId: fromCloud.id), true)
        XCTAssertEqual(tax.noOneParticipatedMore(forYear: 2026, propertyId: fromCloud.id), false)
    }

    func testAnsweringOneRentalLeavesTheOtherUnanswered() {
        tax.reload()
        let a = rental("Santa"), b = rental("Cabin")
        tax.migrateParticipationAnswers(properties: [a, b])
        tax.setNoOneParticipatedMore(true, forYear: 2026, propertyId: a.id)
        XCTAssertEqual(tax.noOneParticipatedMore(forYear: 2026, propertyId: a.id), true)
        XCTAssertNil(tax.noOneParticipatedMore(forYear: 2026, propertyId: b.id))
        XCTAssertNil(tax.noOneParticipatedMore(forYear: 2026), "the grouped answer is separate")
    }

    func testClearingOneAnswer() {
        let (a, b) = upgradedInstall()
        tax.setNoOneParticipatedMore(nil, forYear: 2026, propertyId: a.id)
        XCTAssertNil(tax.noOneParticipatedMore(forYear: 2026, propertyId: a.id))
        XCTAssertEqual(tax.noOneParticipatedMore(forYear: 2025, propertyId: a.id), true, "other years stay")
        XCTAssertEqual(tax.noOneParticipatedMore(forYear: 2026, propertyId: b.id), false, "other rentals stay")
        tax.reload()
        XCTAssertNil(tax.noOneParticipatedMore(forYear: 2026, propertyId: a.id), "cleared on disk")
    }

    func testDataResetClearsAnswersAndMigrationState() {
        _ = upgradedInstall()
        XCTAssertNotNil(UserDefaults.standard.object(forKey: answersKey))
        XCTAssertNotNil(UserDefaults.standard.object(forKey: migrationKey))
        tax.resetForDataReset()
        XCTAssertNil(UserDefaults.standard.object(forKey: answersKey))
        XCTAssertNil(UserDefaults.standard.object(forKey: migrationKey))
        XCTAssertNil(UserDefaults.standard.object(forKey: legacyKey))
        XCTAssertTrue(tax.participationAnswers.isEmpty)
    }

    func testSignOutClearsMemoryAndReloadBringsAnswersBack() {
        let (a, _) = upgradedInstall()
        tax.setNoOneParticipatedMore(true, forYear: 2026, propertyId: a.id)
        tax.resetForSignOut()
        XCTAssertTrue(tax.participationAnswers.isEmpty)
        XCTAssertNil(tax.noOneParticipatedMore(forYear: 2026, propertyId: a.id))
        tax.reload()
        XCTAssertEqual(tax.noOneParticipatedMore(forYear: 2026, propertyId: a.id), true, "kept on disk for the profile")
    }

    func testTwoProfilesDoNotMix() {
        let a = rental("Santa")
        tax.setNoOneParticipatedMore(true, forYear: 2026, propertyId: a.id)
        let first = profileId
        let second = "local-capture-other-\(UUID().uuidString.prefix(8))"
        defer { AppViewModel.clearScopedAccountData(for: second) }

        UserDefaults.standard.set(second, forKey: ProfileKeys.localProfileId)
        tax.reload()
        XCTAssertNil(tax.noOneParticipatedMore(forYear: 2026, propertyId: a.id), "the other profile has no answer")
        tax.setNoOneParticipatedMore(false, forYear: 2026, propertyId: a.id)

        UserDefaults.standard.set(first, forKey: ProfileKeys.localProfileId)
        tax.reload()
        XCTAssertEqual(tax.noOneParticipatedMore(forYear: 2026, propertyId: a.id), true)
    }

    // MARK: Lifecycle hooks in the view model

    func testAddingARentalRunsTheMigrationAndANewRentalStartsUnanswered() {
        writeLegacy([2026: true])
        tax.reload()
        let (vm, oak) = makeViewModel()
        XCTAssertNil(tax.noOneParticipatedMore(forYear: 2026, propertyId: oak), "created after the stamp")
        XCTAssertEqual(tax.noOneParticipatedMore(forYear: 2026, propertyId: nil), true)
        let state = UserDefaults.standard.data(forKey: migrationKey).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        XCTAssertEqual((state?["done"] as? [String]) ?? [], [], "a rental made after the stamp is never marked as migrated")
        _ = vm
    }

    func testDeletingARentalForgetsItsAnswersAndPlan() {
        let (vm, oak) = makeViewModel()
        vm.addProperty(name: "Pine", address: "2 Pine", type: .str)
        let pine = vm.properties.first { $0.name == "Pine" }!.id
        tax.setNoOneParticipatedMore(true, forYear: 2026, propertyId: oak)
        tax.setNoOneParticipatedMore(false, forYear: 2025, propertyId: oak)
        tax.setNoOneParticipatedMore(true, forYear: 2026, propertyId: pine)
        RentalPlanStore.shared.setOverride(.record, for: oak)
        RentalPlanStore.shared.setWhoDoesMost(.me, for: oak)
        RentalPlanStore.shared.setFocus(rental: oak)

        vm.deleteProperty(vm.properties.first { $0.id == oak }!)

        XCTAssertNil(tax.noOneParticipatedMore(forYear: 2026, propertyId: oak))
        XCTAssertNil(tax.noOneParticipatedMore(forYear: 2025, propertyId: oak))
        XCTAssertEqual(tax.noOneParticipatedMore(forYear: 2026, propertyId: pine), true)
        XCTAssertNil(RentalPlanStore.shared.overrides[oak])
        XCTAssertNil(RentalPlanStore.shared.whoDoesMost[oak])
        XCTAssertNil(RentalPlanStore.shared.focusToken)
    }

    func testAccountDataClearRemovesTheNewKeys() {
        _ = upgradedInstall()
        RentalPlanStore.shared.setOverride(.record, for: UUID())
        RentalPlanStore.shared.setFocusAll()
        AppViewModel.clearScopedAccountData(for: profileId)
        XCTAssertNil(UserDefaults.standard.object(forKey: answersKey))
        XCTAssertNil(UserDefaults.standard.object(forKey: migrationKey))
        XCTAssertNil(UserDefaults.standard.object(forKey: legacyKey))
        for base in RentalPlanStore.allKeys {
            XCTAssertNil(UserDefaults.standard.object(forKey: UserScope.key(base, userId: profileId)), base)
        }
    }

    func testSignOutAndSignInReloadThePlanStoreForTheProfile() {
        let (vm, oak) = makeViewModel()
        RentalPlanStore.shared.setOverride(.record, for: oak)
        vm.signOut()
        XCTAssertNil(RentalPlanStore.shared.overrides[oak], "signed out: nothing of the profile in memory")
        UserDefaults.standard.set(profileId, forKey: ProfileKeys.localProfileId)
        vm.signIn()
        XCTAssertEqual(RentalPlanStore.shared.overrides[oak], .record, "signed back in: the profile's plan is back")
    }

    // MARK: The engine reads each rental's own answer

    private let year = 2026

    private func entry(_ id: UUID, _ hours: Double) -> TimeEntry {
        TimeEntry(propertyId: id, participant: .selfParticipant, category: .repairs, hours: hours,
                  date: DateComponents(calendar: .current, year: year, month: 4, day: 2, hour: 10).date!)
    }

    func testEachShortStayUsesItsOwnAnswer() {
        let a = rental("Santa"), b = rental("Cabin")
        let answers: [UUID: Bool] = [a.id: true]
        let lookup: (UUID?) -> Bool? = { $0.flatMap { answers[$0] } }
        let entries = [entry(a.id, 140), entry(b.id, 120)]

        func status(_ id: UUID) -> TaxQualificationEngine.MaterialParticipationResult {
            TaxQualificationEngine.materialParticipationStatus(entries: entries, year: year, propertyId: id,
                                                               groupingElection: false, noOneParticipatedMore: lookup(id))
        }
        XCTAssertTrue(status(a.id).meets100HourTest)
        XCTAssertFalse(status(a.id).meets100HourThresholdPendingConfirmation)
        XCTAssertFalse(status(b.id).meets100HourTest)
        XCTAssertTrue(status(b.id).meets100HourThresholdPendingConfirmation)

        let overview = TaxQualificationEngine.materialParticipationOverview(
            entries: entries, properties: [a, b], year: year, groupingElection: false, answers: lookup)
        XCTAssertEqual(overview.propertyId, a.id)
        XCTAssertTrue(overview.meets100HourTest)

        let bLeads = [entry(a.id, 140), entry(b.id, 160)]
        let overviewB = TaxQualificationEngine.materialParticipationOverview(
            entries: bLeads, properties: [a, b], year: year, groupingElection: false, answers: lookup)
        XCTAssertEqual(overviewB.propertyId, b.id)
        XCTAssertFalse(overviewB.meets100HourTest, "B's answer, not A's")
        XCTAssertTrue(overviewB.meets100HourThresholdPendingConfirmation)
    }

    func testGroupedActivityUsesTheGroupedAnswer() {
        let a = rental("Santa"), b = rental("Cabin")
        let lookup: (UUID?) -> Bool? = { $0 == nil ? true : false }
        let overview = TaxQualificationEngine.materialParticipationOverview(
            entries: [entry(a.id, 60), entry(b.id, 60)], properties: [a, b], year: year, groupingElection: true, answers: lookup)
        XCTAssertNil(overview.propertyId)
        XCTAssertTrue(overview.meets100HourTest)
    }

    func testViewModelOverviewReadsThePerRentalStore() {
        tax.groupingElection = false
        let (vm, oak) = makeViewModel()
        vm.addProperty(name: "Pine", address: "2 Pine", type: .ltr)
        let pine = vm.properties.first { $0.name == "Pine" }!.id
        vm.timeEntries = [entry(oak, 140), entry(pine, 120)]
        tax.setNoOneParticipatedMore(true, forYear: year, propertyId: oak)

        XCTAssertTrue(vm.materialParticipationStatus(year: year, propertyId: oak).meets100HourTest)
        XCTAssertTrue(vm.materialParticipationStatus(year: year, propertyId: pine).meets100HourThresholdPendingConfirmation)
        XCTAssertTrue(vm.materialParticipationOverview(year: year).meets100HourTest)

        vm.timeEntries = [entry(oak, 140), entry(pine, 160)]
        let overview = vm.materialParticipationOverview(year: year)
        XCTAssertEqual(overview.propertyId, pine)
        XCTAssertFalse(overview.meets100HourTest)
        XCTAssertTrue(overview.meets100HourThresholdPendingConfirmation)
    }

    func testAuditReportUsesEachRentalsAnswer() {
        let a = rental("Santa"), b = rental("Cabin")
        let input = AuditReportBuilder.inputFromTaxProfile(
            entries: [entry(a.id, 140), entry(b.id, 120)], properties: [a, b], taxYear: year,
            spouseTracking: false, nonREWorkHours: 0, groupingElection: false,
            noOneParticipatedMore: true, propertyAnswers: [a.id: true])
        let report = AuditReportBuilder.build(input)
        let lines = Dictionary(uniqueKeysWithValues: report.materialParticipation.map { ($0.label, $0) })
        XCTAssertEqual(lines["Santa"]?.meets100HourTest, true)
        XCTAssertEqual(lines["Cabin"]?.meets100HourTest, false, "the grouped answer never stands in for a rental's own")
        XCTAssertEqual(lines["Cabin"]?.pendingConfirmation, true)
    }

    func testExportFingerprintChangesWhenAnyAnswerChanges() {
        let (vm, oak) = makeViewModel()
        vm.addProperty(name: "Pine", address: "2 Pine", type: .str)
        let pine = vm.properties.first { $0.name == "Pine" }!.id
        let base = ExportFingerprint.current(app: vm, year: year)
        tax.setNoOneParticipatedMore(true, forYear: year, propertyId: pine)
        let afterPine = ExportFingerprint.current(app: vm, year: year)
        XCTAssertNotEqual(base, afterPine)
        tax.setNoOneParticipatedMore(false, forYear: year, propertyId: oak)
        XCTAssertNotEqual(afterPine, ExportFingerprint.current(app: vm, year: year))
        tax.setNoOneParticipatedMore(true, forYear: year - 1, propertyId: oak)
        let otherYear = ExportFingerprint.current(app: vm, year: year)
        tax.setNoOneParticipatedMore(nil, forYear: year - 1, propertyId: oak)
        XCTAssertEqual(otherYear, ExportFingerprint.current(app: vm, year: year), "another year's answer does not touch this report")
    }
}
