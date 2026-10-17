import XCTest
@testable import LandlordHours

// MARK: - Shared helper

/// Captures and restores every unscoped auth/profile key so hosted tests never leak
/// identity state into the host app or into each other.
struct AuthStateSnapshot {
    static let keys = ProfileKeys.signOutKeys + [ProfileKeys.previousProfileId]
    private var values: [String: Any] = [:]

    static func capture(_ defaults: UserDefaults = .standard) -> AuthStateSnapshot {
        var snapshot = AuthStateSnapshot()
        for key in keys {
            if let value = defaults.object(forKey: key) { snapshot.values[key] = value }
        }
        return snapshot
    }

    static func clearAll(_ defaults: UserDefaults = .standard) {
        for key in keys { defaults.removeObject(forKey: key) }
    }

    func restore(_ defaults: UserDefaults = .standard) {
        for key in Self.keys {
            if let value = values[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

private func makeSuite(_ name: String = #function) -> (UserDefaults, String) {
    let suiteName = "LocalProfileTests.\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return (defaults, suiteName)
}

private func scopedSnapshot(_ defaults: UserDefaults, id: String) -> [String: String] {
    var result: [String: String] = [:]
    for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix("u.\(id).") {
        result[key] = String(describing: value)
    }
    return result
}

private func seedProfileData(
    _ defaults: UserDefaults,
    id: String,
    entries: Int,
    properties: Int,
    lastDate: Date = Date(timeIntervalSince1970: 1_790_000_000)
) {
    let props = (0..<properties).map { RentalProperty(name: "P\($0)", address: "\($0) Main", propertyType: .ltr) }
    let propertyId = props.first?.id ?? UUID()
    let items = (0..<entries).map { index in
        TimeEntry(
            propertyId: propertyId,
            participant: .selfParticipant,
            category: .repairs,
            hours: 1,
            date: lastDate.addingTimeInterval(TimeInterval(-86_400 * index)),
            notes: "e\(index)"
        )
    }
    defaults.set(try! JSONEncoder().encode(props), forKey: "u.\(id).LandlordHours.properties")
    defaults.set(try! JSONEncoder().encode(items), forKey: "u.\(id).LandlordHours.entries")
    defaults.set(true, forKey: "u.\(id).hasCompletedOnboarding")
}

@MainActor
private final class FakeCloudSource: CloudProfileRecordSource {
    var records: [CloudRecordSummary]
    var error: Error?
    init(records: [CloudRecordSummary], error: Error? = nil) {
        self.records = records
        self.error = error
    }
    func fetchProfileRecordSummaries() async throws -> [CloudRecordSummary] {
        if let error { throw error }
        return records
    }
}

// MARK: - Migration (spec test plan 1–4, multiple + signed-out devices)

final class EmailProfileMigrationTests: XCTestCase {

    func testSingleEmailProfileMigratesToLocalProfileWithSameId() {
        let (defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = "email-pat@example.com"
        defaults.set(id, forKey: ProfileKeys.emailUserId)
        defaults.set("Pat", forKey: ProfileKeys.emailUserName)
        defaults.set("pat@example.com", forKey: ProfileKeys.emailUserEmail)
        defaults.set(LoginType.email.rawValue, forKey: ProfileKeys.loginType)
        seedProfileData(defaults, id: id, entries: 5, properties: 2)
        defaults.set(true, forKey: "u.\(id).isProUser")
        let before = scopedSnapshot(defaults, id: id)

        let outcome = ProfileMigration.migrateEmailProfile(defaults: defaults)

        XCTAssertEqual(outcome, .migrated(profileId: id))
        XCTAssertEqual(defaults.string(forKey: ProfileKeys.localProfileId), id)
        XCTAssertEqual(defaults.string(forKey: ProfileKeys.localProfileName), "Pat")
        XCTAssertEqual(defaults.string(forKey: ProfileKeys.localProfileEmail), "pat@example.com")
        XCTAssertEqual(defaults.string(forKey: ProfileKeys.loginType), LoginType.local.rawValue)
        XCTAssertNil(defaults.string(forKey: ProfileKeys.emailUserId))
        XCTAssertNil(defaults.string(forKey: ProfileKeys.emailUserName))
        XCTAssertNil(defaults.string(forKey: ProfileKeys.emailUserEmail))
        XCTAssertEqual(scopedSnapshot(defaults, id: id), before, "No u.X.* key may change")
        XCTAssertEqual(ProfileKeys.resolveUserId(defaults), id)
    }

    func testLegacyLoginTypeEmailStillDecodes() {
        XCTAssertEqual(LoginType(rawValue: "email"), .email)
        XCTAssertEqual(LoginType(rawValue: "local"), .local)
    }

    func testAppleProfileWithoutEmailIsUntouched() {
        let (defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("apple-001", forKey: ProfileKeys.appleUserId)
        defaults.set(LoginType.apple.rawValue, forKey: ProfileKeys.loginType)
        let before = defaults.dictionaryRepresentation().keys.sorted()

        XCTAssertEqual(ProfileMigration.migrateEmailProfile(defaults: defaults), .skippedAppleUser)
        XCTAssertEqual(defaults.dictionaryRepresentation().keys.sorted(), before)
        XCTAssertEqual(ProfileKeys.resolveUserId(defaults), "apple-001")
    }

    func testAppleProfileWithLeftoverEmailProfileIsUntouchedAndEmailDataDiscoverable() {
        let (defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("apple-001", forKey: ProfileKeys.appleUserId)
        defaults.set("email-old@example.com", forKey: ProfileKeys.emailUserId)
        seedProfileData(defaults, id: "email-old@example.com", entries: 3, properties: 1)
        let before = defaults.dictionaryRepresentation().keys.sorted()

        XCTAssertEqual(ProfileMigration.migrateEmailProfile(defaults: defaults), .skippedAppleUser)
        XCTAssertEqual(defaults.dictionaryRepresentation().keys.sorted(), before)
        XCTAssertNil(defaults.string(forKey: ProfileKeys.localProfileId))
        XCTAssertEqual(ProfileKeys.resolveUserId(defaults), "apple-001")

        // The old email profile is offered by "Restore other data" (no launch prompt).
        let found = ProfileDiscovery.deviceProfiles(defaults: defaults, excluding: "apple-001")
        XCTAssertEqual(found.map(\.id), ["email-old@example.com"])
        XCTAssertEqual(found.first?.entryCount, 3)
    }

    func testCrashMidwayWithBothKeysSetFinishesAndKeepsId() {
        let (defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = "email-pat@example.com"
        // State after step 1 wrote local keys but before email keys were deleted.
        defaults.set(id, forKey: ProfileKeys.emailUserId)
        defaults.set("Pat", forKey: ProfileKeys.emailUserName)
        defaults.set(id, forKey: ProfileKeys.localProfileId)
        XCTAssertEqual(ProfileKeys.resolveUserId(defaults), id, "Intermediate state must resolve to X")

        XCTAssertEqual(ProfileMigration.migrateEmailProfile(defaults: defaults), .migrated(profileId: id))
        XCTAssertEqual(defaults.string(forKey: ProfileKeys.localProfileId), id)
        XCTAssertEqual(defaults.string(forKey: ProfileKeys.localProfileName), "Pat")
        XCTAssertNil(defaults.string(forKey: ProfileKeys.emailUserId))
        XCTAssertEqual(ProfileKeys.resolveUserId(defaults), id)
    }

    func testCrashAfterLabelsRemovedButBeforeIdRemovedFinishes() {
        let (defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = "email-pat@example.com"
        defaults.set(id, forKey: ProfileKeys.emailUserId)
        defaults.set(id, forKey: ProfileKeys.localProfileId)
        defaults.set("Pat", forKey: ProfileKeys.localProfileName)

        ProfileMigration.migrateEmailProfile(defaults: defaults)
        XCTAssertNil(defaults.string(forKey: ProfileKeys.emailUserId))
        XCTAssertEqual(defaults.string(forKey: ProfileKeys.localProfileName), "Pat")
        XCTAssertEqual(ProfileKeys.resolveUserId(defaults), id)
    }

    func testMigrationRunTwiceIsANoOp() {
        let (defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = "email-pat@example.com"
        defaults.set(id, forKey: ProfileKeys.emailUserId)
        seedProfileData(defaults, id: id, entries: 2, properties: 1)
        ProfileMigration.migrateEmailProfile(defaults: defaults)
        let afterFirst = defaults.dictionaryRepresentation().mapValues { String(describing: $0) }

        XCTAssertEqual(ProfileMigration.migrateEmailProfile(defaults: defaults), .nothingToMigrate)
        XCTAssertEqual(defaults.dictionaryRepresentation().mapValues { String(describing: $0) }, afterFirst)
    }

    func testMultipleEmailProfilesOnlyActiveMigratesOthersStayRestorable() {
        let (defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("email-b@example.com", forKey: ProfileKeys.emailUserId)
        seedProfileData(defaults, id: "email-a@example.com", entries: 5, properties: 2)
        seedProfileData(defaults, id: "email-b@example.com", entries: 1, properties: 1)
        let beforeA = scopedSnapshot(defaults, id: "email-a@example.com")

        ProfileMigration.migrateEmailProfile(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: ProfileKeys.localProfileId), "email-b@example.com")
        XCTAssertEqual(scopedSnapshot(defaults, id: "email-a@example.com"), beforeA)
        let found = ProfileDiscovery.deviceProfiles(defaults: defaults, excluding: ProfileKeys.resolveUserId(defaults))
        XCTAssertEqual(found.map(\.id), ["email-a@example.com"])
        XCTAssertEqual(found.first?.entryCount, 5)
        XCTAssertEqual(found.first?.propertyCount, 2)
    }

    func testSignedOutDeviceIsUntouchedAndProfileIsDiscoverable() {
        let (defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        seedProfileData(defaults, id: "email-a@example.com", entries: 2, properties: 1)
        let before = defaults.dictionaryRepresentation().keys.sorted()

        XCTAssertEqual(ProfileMigration.migrateEmailProfile(defaults: defaults), .nothingToMigrate)
        XCTAssertEqual(defaults.dictionaryRepresentation().keys.sorted(), before)
        XCTAssertNil(ProfileKeys.resolveUserId(defaults))
        XCTAssertEqual(ProfileDiscovery.deviceProfiles(defaults: defaults, excluding: nil).map(\.id), ["email-a@example.com"])
    }

    func testDifferentLocalProfileActiveLeavesEmailKeysAlone() {
        let (defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("local-123", forKey: ProfileKeys.localProfileId)
        defaults.set("email-a@example.com", forKey: ProfileKeys.emailUserId)

        XCTAssertEqual(
            ProfileMigration.migrateEmailProfile(defaults: defaults),
            .conflictLeftAlone(localId: "local-123", emailId: "email-a@example.com")
        )
        XCTAssertEqual(defaults.string(forKey: ProfileKeys.emailUserId), "email-a@example.com")
        XCTAssertEqual(ProfileKeys.resolveUserId(defaults), "local-123")
    }
}

// MARK: - Discovery (spec 5–6) and restore guard (spec 7)

@MainActor
final class ProfileDiscoveryTests: XCTestCase {

    func testDeviceDiscoveryReturnsInactiveEmailProfilesWithCounts() {
        let (defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        seedProfileData(defaults, id: "email-a@example.com", entries: 5, properties: 2,
                        lastDate: Date(timeIntervalSince1970: 1_790_000_000))
        seedProfileData(defaults, id: "email-a@example.com.au", entries: 1, properties: 1,
                        lastDate: Date(timeIntervalSince1970: 1_700_000_000))
        seedProfileData(defaults, id: "apple-001", entries: 4, properties: 1)
        seedProfileData(defaults, id: "debug-frequent", entries: 4, properties: 1)
        seedProfileData(defaults, id: "email-empty@example.com", entries: 0, properties: 0)
        seedProfileData(defaults, id: "email-active@example.com", entries: 3, properties: 1)

        let found = ProfileDiscovery.deviceProfiles(defaults: defaults, excluding: "email-active@example.com")

        XCTAssertEqual(found.map(\.id), ["email-a@example.com", "email-a@example.com.au"])
        XCTAssertEqual(found[0].entryCount, 5)
        XCTAssertEqual(found[0].propertyCount, 2)
        XCTAssertEqual(found[0].lastEntryDate, Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(found[0].sources, [.device])
        XCTAssertEqual(found[0].displayLabel, "a•••@example.com")
    }

    func testDeviceDiscoveryOffersCorruptProfileRatherThanHidingIt() {
        let (defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: "u.email-x@example.com.LandlordHours.entries")
        XCTAssertEqual(ProfileDiscovery.deviceProfiles(defaults: defaults, excluding: nil).map(\.id), ["email-x@example.com"])
    }

    func testDeviceDiscoveryIncludesSwitchedAwayLocalProfiles() {
        let (defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        seedProfileData(defaults, id: "local-ABC", entries: 2, properties: 1)
        defaults.set("Pat", forKey: "u.local-ABC.\(ProfileRestore.profileNameKey)")
        let found = ProfileDiscovery.deviceProfiles(defaults: defaults, excluding: nil)
        XCTAssertEqual(found.map(\.id), ["local-ABC"])
        XCTAssertEqual(found.first?.displayLabel, "Pat")
    }

    func testCloudDiscoveryGroupsInactiveProfilesAndMergeDeduplicates() async throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let source = FakeCloudSource(records: [
            CloudRecordSummary(appUserId: "email-a@example.com", recordType: "TimeEntry", date: date),
            CloudRecordSummary(appUserId: "email-a@example.com", recordType: "TimeEntry", date: date.addingTimeInterval(-100)),
            CloudRecordSummary(appUserId: "email-a@example.com", recordType: "Property", date: nil),
            CloudRecordSummary(appUserId: "email-a@example.com", recordType: "GoalSettings", date: nil),
            CloudRecordSummary(appUserId: "email-b@example.com", recordType: "TimeEntry", date: date),
            CloudRecordSummary(appUserId: "local-active", recordType: "TimeEntry", date: date),
            CloudRecordSummary(appUserId: "apple-001", recordType: "TimeEntry", date: date),
            CloudRecordSummary(appUserId: nil, recordType: "TimeEntry", date: date),
            CloudRecordSummary(appUserId: "email-onlysettings@example.com", recordType: "TaxProfile", date: nil)
        ])

        let cloud = ProfileDiscovery.cloudProfiles(
            from: try await source.fetchProfileRecordSummaries(),
            excluding: "local-active"
        )
        XCTAssertEqual(Set(cloud.map(\.id)), ["email-a@example.com", "email-b@example.com"])
        let a = try XCTUnwrap(cloud.first { $0.id == "email-a@example.com" })
        XCTAssertEqual(a.entryCount, 2)
        XCTAssertEqual(a.propertyCount, 1)
        XCTAssertEqual(a.lastEntryDate, date)
        XCTAssertEqual(a.sources, [.iCloud])

        let device = [DiscoveredProfile(id: "email-a@example.com", entryCount: 3, propertyCount: 1,
                                        lastEntryDate: date, sources: [.device], name: nil)]
        let merged = ProfileDiscovery.merge(device: device, cloud: cloud)
        XCTAssertEqual(merged.count, 2, "Same profile on device and in iCloud appears once")
        let mergedA = try XCTUnwrap(merged.first { $0.id == "email-a@example.com" })
        XCTAssertEqual(mergedA.sources, [.device, .iCloud])
        XCTAssertEqual(mergedA.entryCount, 3, "Device counts win")
        XCTAssertTrue(mergedA.isOnDevice)
        XCTAssertTrue(try XCTUnwrap(merged.first { $0.id == "email-b@example.com" }).isICloudOnly)
    }

    func testViewModelDiscoveryFallsBackToDeviceWhenCloudFails() async {
        let snapshot = AuthStateSnapshot.capture()
        AuthStateSnapshot.clearAll()
        let id = "email-discovery-\(UUID().uuidString.prefix(6))@example.com"
        seedProfileData(.standard, id: id, entries: 1, properties: 1)
        defer {
            AppViewModel.clearScopedAccountData(for: id)
            UserDefaults.standard.removeObject(forKey: "u.\(id).LandlordHours.properties")
            UserDefaults.standard.removeObject(forKey: "u.\(id).LandlordHours.entries")
            snapshot.restore()
        }
        let viewModel = AppViewModel()
        struct Offline: Error {}
        let found = await viewModel.discoverRestorableProfiles(cloudSource: FakeCloudSource(records: [], error: Offline()))
        XCTAssertTrue(found.contains { $0.id == id && $0.isOnDevice })
    }

    func testMaskedEmail() {
        XCTAssertEqual(ProfileDiscovery.maskedEmail("brian@gmail.com"), "b•••@gmail.com")
        XCTAssertEqual(ProfileDiscovery.maskedEmail("nope"), "•••")
    }

    func testICloudOnlyRestoreSetsMigrationDoneBeforeActivationAndPullsFirst() async {
        let (defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = "email-a@example.com"
        let profile = DiscoveredProfile(id: id, entryCount: 5, propertyCount: 2, lastEntryDate: nil,
                                        sources: [.iCloud], name: nil)

        ProfileRestore.activate(profile, defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: "u.\(id).cloudkit.migrationDone"))
        XCTAssertEqual(defaults.string(forKey: ProfileKeys.localProfileId), id)
        XCTAssertEqual(defaults.string(forKey: ProfileKeys.localProfileEmail), "a@example.com")
        XCTAssertEqual(ProfileKeys.resolveUserId(defaults), id)

        // Fake sync: even if local state looked non-empty, nothing is pushed before the first pull.
        var calls: [String] = []
        await CloudKitSyncService.runInitialSync(
            defaults: defaults,
            migrationDoneKey: "u.\(id).cloudkit.migrationDone",
            hasLocalData: true,
            push: { calls.append("push") },
            pull: { calls.append("pull") }
        )
        XCTAssertEqual(calls, ["pull"], "Zero pushes before the first pull")
    }

    func testDeviceRestoreDoesNotTouchSyncState() {
        let (defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = "email-a@example.com"
        seedProfileData(defaults, id: id, entries: 1, properties: 1)
        let before = scopedSnapshot(defaults, id: id)
        ProfileRestore.activate(DiscoveredProfile(id: id, entryCount: 1, propertyCount: 1, lastEntryDate: nil,
                                                  sources: [.device, .iCloud], name: nil), defaults: defaults)
        XCTAssertEqual(scopedSnapshot(defaults, id: id), before)
        XCTAssertEqual(ProfileKeys.resolveUserId(defaults), id)
    }

    func testEmptyStatePushGuard() async {
        let (defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        var calls: [String] = []

        // Fresh install / reinstall: nothing local → never push defaults over iCloud.
        await CloudKitSyncService.runInitialSync(defaults: defaults, migrationDoneKey: "k", hasLocalData: false,
                                                 push: { calls.append("push") }, pull: { calls.append("pull") })
        XCTAssertEqual(calls, ["pull"])
        XCTAssertTrue(defaults.bool(forKey: "k"))

        // Existing local data, first sync → push then pull (pre-1.1 behaviour preserved).
        calls = []
        await CloudKitSyncService.runInitialSync(defaults: defaults, migrationDoneKey: "k2", hasLocalData: true,
                                                 push: { calls.append("push") }, pull: { calls.append("pull") })
        XCTAssertEqual(calls, ["push", "pull"])

        // Already migrated → pull only.
        calls = []
        await CloudKitSyncService.runInitialSync(defaults: defaults, migrationDoneKey: "k2", hasLocalData: true,
                                                 push: { calls.append("push") }, pull: { calls.append("pull") })
        XCTAssertEqual(calls, ["pull"])
    }
}

// MARK: - Pro carry-over

final class ProCarryOverTests: XCTestCase {

    func testCarryCopiesProToNewProfileAndNeverRemoves() {
        let (defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "u.local-A.isProUser")
        defaults.set(true, forKey: "u.local-A.hasPurchasedPro")

        XCTAssertTrue(ProEntitlementCarryOver.carry(from: "local-A", to: "apple-B", defaults: defaults))
        XCTAssertTrue(defaults.bool(forKey: "u.apple-B.isProUser"))
        XCTAssertTrue(defaults.bool(forKey: "u.apple-B.hasPurchasedPro"))

        // Non-Pro source never downgrades a Pro target.
        XCTAssertFalse(ProEntitlementCarryOver.carry(from: "local-C", to: "apple-B", defaults: defaults))
        XCTAssertTrue(defaults.bool(forKey: "u.apple-B.isProUser"))
    }

    func testMigrationKeepsProBecauseIdIsUnchanged() {
        let (defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = "email-pro@example.com"
        defaults.set(id, forKey: ProfileKeys.emailUserId)
        defaults.set(true, forKey: "u.\(id).isProUser")
        defaults.set(true, forKey: "u.\(id).hasPurchasedPro")
        ProfileMigration.migrateEmailProfile(defaults: defaults)
        let resolved = ProfileKeys.resolveUserId(defaults)
        XCTAssertTrue(defaults.bool(forKey: UserScope.key("isProUser", userId: resolved)))
        XCTAssertTrue(defaults.bool(forKey: UserScope.key("hasPurchasedPro", userId: resolved)))
    }

    func testCarryFromPreviousProfileUsesPointerThenClearsIt() {
        let (defaults, suite) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "u.local-A.isProUser")
        defaults.set("local-A", forKey: ProfileKeys.previousProfileId)
        defaults.set("apple-B", forKey: ProfileKeys.appleUserId)

        XCTAssertTrue(ProEntitlementCarryOver.carryFromPreviousProfile(defaults: defaults))
        XCTAssertTrue(defaults.bool(forKey: "u.apple-B.isProUser"))
        XCTAssertNil(defaults.string(forKey: ProfileKeys.previousProfileId))
    }
}

// MARK: - AppViewModel flows (spec 8–12, sign-out, delete, Pro on profile change)

@MainActor
final class LocalProfileFlowTests: XCTestCase {
    private var authSnapshot: AuthStateSnapshot!
    private var savedAttachmentStore: AttachmentStore!
    private var attachmentDir: URL!
    private var createdIds: [String] = []

    override func setUp() {
        super.setUp()
        authSnapshot = AuthStateSnapshot.capture()
        AuthStateSnapshot.clearAll()
        savedAttachmentStore = AttachmentStore.shared
        attachmentDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lp-attachments-\(UUID().uuidString)", isDirectory: true)
        AttachmentStore.shared = AttachmentStore(directory: attachmentDir)
        createdIds = []
    }

    override func tearDown() {
        for id in createdIds {
            AppViewModel.clearScopedAccountData(for: id)
            UserDefaults.standard.removeObject(forKey: "u.\(id).LandlordHours.properties")
            UserDefaults.standard.removeObject(forKey: "u.\(id).LandlordHours.entries")
        }
        if let id = UserScope.userId {
            AppViewModel.clearScopedAccountData(for: id)
            UserDefaults.standard.removeObject(forKey: "u.\(id).LandlordHours.properties")
            UserDefaults.standard.removeObject(forKey: "u.\(id).LandlordHours.entries")
        }
        AttachmentStore.shared = savedAttachmentStore
        try? FileManager.default.removeItem(at: attachmentDir)
        authSnapshot.restore()
        super.tearDown()
    }

    private func uniqueId(_ prefix: String) -> String {
        let id = "\(prefix)\(UUID().uuidString.prefix(8))"
        createdIds.append(id)
        return id
    }

    func testLaunchMigratesEmailProfileAndShowsDataWithoutSignInWall() {
        let id = uniqueId("email-launch-") + "@example.com"
        createdIds.append(id)
        UserDefaults.standard.set(id, forKey: ProfileKeys.emailUserId)
        UserDefaults.standard.set("Pat", forKey: ProfileKeys.emailUserName)
        seedProfileData(.standard, id: id, entries: 5, properties: 2)

        let viewModel = AppViewModel()

        XCTAssertTrue(viewModel.isSignedIn, "No sign-in wall for a migrated email user")
        XCTAssertEqual(viewModel.userName, "Pat")
        XCTAssertEqual(viewModel.timeEntries.count, 5)
        XCTAssertEqual(viewModel.properties.count, 2)
        XCTAssertEqual(UserDefaults.standard.string(forKey: ProfileKeys.localProfileId), id)
        XCTAssertNil(UserDefaults.standard.string(forKey: ProfileKeys.emailUserId))
    }

    func testContinueWithoutAccountCreatesLocalProfileAndMigratesUnscopedLegacyData() throws {
        let legacyProps = try JSONEncoder().encode([RentalProperty(name: "Legacy", address: "1 Old Rd", propertyType: .ltr)])
        UserDefaults.standard.set(legacyProps, forKey: "LandlordHours.properties")
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

        let viewModel = AppViewModel()
        XCTAssertFalse(viewModel.isSignedIn)
        viewModel.continueWithoutAccount()

        let id = try XCTUnwrap(UserDefaults.standard.string(forKey: ProfileKeys.localProfileId))
        createdIds.append(id)
        XCTAssertTrue(id.hasPrefix("local-"))
        XCTAssertNotNil(UUID(uuidString: String(id.dropFirst("local-".count))))
        XCTAssertEqual(UserScope.userId, id)
        XCTAssertTrue(viewModel.isSignedIn)
        XCTAssertEqual(viewModel.properties.map(\.name), ["Legacy"], "Unscoped legacy data migrated, not wiped")
        XCTAssertNil(UserDefaults.standard.object(forKey: "LandlordHours.properties"))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "u.\(id).hasCompletedOnboarding"), "Onboarding flag scoped and cleared")
        XCTAssertNil(UserDefaults.standard.object(forKey: "hasCompletedOnboarding"))
        XCTAssertEqual(AppleSignInManager.shared.loginType, .local)
    }

    func testSignOutSavesTimerToProfileScopeAndWritesNoUnscopedTimerKeys() {
        let id = uniqueId("local-timer-")
        UserDefaults.standard.set(id, forKey: ProfileKeys.localProfileId)
        let viewModel = AppViewModel()
        viewModel.suppressCelebrations = true
        viewModel.addProperty(name: "Oak", address: "1 Oak", type: .ltr)
        viewModel.startTimer(propertyId: viewModel.properties[0].id, category: .repairs)
        for key in ["LandlordHours.timer", "timerStartTime", "timerPropertyId", "timerCategory"] {
            UserDefaults.standard.removeObject(forKey: key)
        }

        viewModel.signOut()

        for key in ["LandlordHours.timer", "timerStartTime", "timerPropertyId", "timerCategory"] {
            XCTAssertNil(UserDefaults.standard.object(forKey: key), "Unscoped \(key) must not be written")
        }
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "u.\(id).LandlordHours.timer"), "Running timer kept for this profile")
        XCTAssertNotNil(UserDefaults.standard.object(forKey: "u.\(id).timerStartTime"))
        XCTAssertFalse(viewModel.isTimerRunning)
        XCTAssertNil(UserDefaults.standard.string(forKey: ProfileKeys.localProfileId))
        XCTAssertEqual(UserDefaults.standard.string(forKey: ProfileKeys.previousProfileId), id)
    }

    func testDeleteWithICloudUnavailableRaisesErrorAndDeletesNothing() async throws {
        let id = uniqueId("local-del-guard-")
        UserDefaults.standard.set(id, forKey: ProfileKeys.localProfileId)
        let viewModel = AppViewModel()
        viewModel.addProperty(name: "Oak", address: "1 Oak", type: .ltr)
        await viewModel.syncService.checkAccountStatus()
        try XCTSkipIf(viewModel.syncService.accountAvailable, "Needs an environment without iCloud (simulator)")

        do {
            try await viewModel.deleteAccountAndData()
            XCTFail("Expected iCloudUnavailable")
        } catch let error as AppViewModel.ProfileDeletionError {
            XCTAssertEqual(error, .iCloudUnavailable)
        }
        XCTAssertEqual(UserDefaults.standard.string(forKey: ProfileKeys.localProfileId), id)
        XCTAssertNotNil(UserDefaults.standard.data(forKey: "u.\(id).LandlordHours.properties"))
    }

    func testLocalDeleteRemovesKeysFilesNotificationKeysAndProfileIdButNotOtherProfiles() async throws {
        let other = uniqueId("email-other-") + "@example.com"
        createdIds.append(other)
        seedProfileData(.standard, id: other, entries: 2, properties: 1)
        let otherBefore = scopedSnapshot(.standard, id: other)

        let id = uniqueId("local-del-")
        UserDefaults.standard.set(id, forKey: ProfileKeys.localProfileId)
        let viewModel = AppViewModel()
        viewModel.suppressCelebrations = true
        viewModel.addProperty(name: "Oak", address: "1 Oak", type: .ltr)
        viewModel.addTimeEntry(
            propertyId: viewModel.properties[0].id,
            participant: .selfParticipant,
            category: .repairs,
            hours: 1,
            date: Date(),
            notes: "photo",
            attachments: [TimeAttachment(filename: "r.jpg", data: Data([1, 2, 3]), mimeType: "image/jpeg")]
        )
        let attachment = viewModel.timeEntries[0].attachments[0]
        XCTAssertTrue(AttachmentStore.shared.fileExists(for: attachment))
        UserDefaults.standard.set(Date(), forKey: "u.\(id).LandlordHours.notification.lastScheduled.behindPace")
        UserDefaults.standard.set(true, forKey: "u.\(id).isProUser")

        try await viewModel.deleteAccountAndData(allowLocalOnly: true)

        XCTAssertFalse(AttachmentStore.shared.fileExists(for: attachment), "Photo files must be deleted")
        let leftovers = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("u.\(id).") }
        XCTAssertEqual(leftovers.sorted(), [], "All of this profile's keys must be gone")
        XCTAssertNil(UserDefaults.standard.string(forKey: ProfileKeys.localProfileId))
        XCTAssertNil(UserDefaults.standard.string(forKey: ProfileKeys.previousProfileId))
        XCTAssertFalse(viewModel.isSignedIn)
        XCTAssertEqual(scopedSnapshot(.standard, id: other), otherBefore, "Other profiles intact")
    }

    func testLocalProfileNameAndEmailResolveEverywhere() {
        let id = uniqueId("local-names-")
        UserDefaults.standard.set(id, forKey: ProfileKeys.localProfileId)
        UserDefaults.standard.set("Dana", forKey: ProfileKeys.localProfileName)
        UserDefaults.standard.set("dana@example.com", forKey: ProfileKeys.localProfileEmail)
        UserDefaults.standard.set(LoginType.local.rawValue, forKey: ProfileKeys.loginType)

        let viewModel = AppViewModel()
        XCTAssertTrue(viewModel.isSignedIn)                       // checkSignInState
        XCTAssertEqual(viewModel.userName, "Dana")
        viewModel.signIn()                                        // signIn name lookup
        XCTAssertEqual(viewModel.userName, "Dana")

        let manager = AppleSignInManager.shared                   // checkExistingSignIn
        manager.checkExistingSignIn()
        XCTAssertEqual(manager.userId, id)
        XCTAssertEqual(manager.loginType, .local)
        XCTAssertEqual(manager.fullName, "Dana")
        XCTAssertEqual(manager.email, "dana@example.com")
        XCTAssertEqual(AdminAccess.currentEmail, "dana@example.com")

        manager.updateProfile(name: "Dana R", email: "dana.r@example.com", imageData: nil)   // updateProfile
        XCTAssertEqual(UserDefaults.standard.string(forKey: ProfileKeys.localProfileName), "Dana R")
        XCTAssertEqual(UserDefaults.standard.string(forKey: ProfileKeys.localProfileEmail), "dana.r@example.com")
        XCTAssertNil(UserDefaults.standard.string(forKey: ProfileKeys.emailUserName))

        viewModel.signOut()                                       // signOut clears local keys
        XCTAssertNil(UserDefaults.standard.string(forKey: ProfileKeys.localProfileId))
        XCTAssertNil(UserDefaults.standard.string(forKey: ProfileKeys.localProfileName))
        XCTAssertNil(UserDefaults.standard.string(forKey: ProfileKeys.localProfileEmail))
        XCTAssertFalse(manager.isSignedIn)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "u.\(id).\(ProfileRestore.profileNameKey)"), "Dana R",
                       "Name kept with the profile so Restore can show it")
    }

    func testGuestWithProSigningInWithAppleKeepsPro() {
        let guest = uniqueId("local-pro-")
        UserDefaults.standard.set(guest, forKey: ProfileKeys.localProfileId)
        UserDefaults.standard.set(true, forKey: "u.\(guest).isProUser")
        UserDefaults.standard.set(true, forKey: "u.\(guest).hasPurchasedPro")
        let viewModel = AppViewModel()
        viewModel.signOut()   // "Switch profile"

        let apple = uniqueId("apple-pro-")
        UserDefaults.standard.set(apple, forKey: ProfileKeys.appleUserId)
        viewModel.signIn()

        XCTAssertTrue(UserDefaults.standard.bool(forKey: "u.\(apple).isProUser"))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "u.\(apple).hasPurchasedPro"))
        XCTAssertTrue(SubscriptionManager.shared.isPro)
    }

    func testAppleUserRestoringEmailProfileSwitchesAndCarriesPro() {
        let email = uniqueId("email-restore-") + "@example.com"
        createdIds.append(email)
        seedProfileData(.standard, id: email, entries: 4, properties: 1)
        let apple = uniqueId("apple-r-")
        UserDefaults.standard.set(apple, forKey: ProfileKeys.appleUserId)
        UserDefaults.standard.set(true, forKey: "u.\(apple).isProUser")
        let viewModel = AppViewModel()
        XCTAssertTrue(viewModel.isSignedIn)

        let profile = ProfileDiscovery.deviceProfiles(defaults: .standard, excluding: apple).first { $0.id == email }
        XCTAssertNotNil(profile)
        viewModel.switchToProfile(profile!)

        XCTAssertNil(UserDefaults.standard.string(forKey: ProfileKeys.appleUserId))
        XCTAssertEqual(UserScope.userId, email)
        XCTAssertEqual(viewModel.timeEntries.count, 4)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "u.\(email).isProUser"), "Pro carried to the restored profile")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "u.\(apple).isProUser"), "Apple profile keeps Pro")
    }
}
