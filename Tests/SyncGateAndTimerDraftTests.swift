import XCTest
@testable import LandlordHours

// MARK: - Push gate, end to end through start()

@MainActor
final class InitialSyncGateTests: XCTestCase {
    private var authSnapshot: AuthStateSnapshot!
    private var profileId = ""

    override func setUp() {
        super.setUp()
        authSnapshot = AuthStateSnapshot.capture()
        AuthStateSnapshot.clearAll()
        profileId = "local-gate-\(UUID().uuidString.prefix(8))"
        UserDefaults.standard.set(profileId, forKey: ProfileKeys.localProfileId)
    }

    override func tearDown() {
        AppViewModel.clearScopedAccountData(for: profileId)
        authSnapshot.restore()
        super.tearDown()
    }

    private final class Recorder {
        var calls: [String] = []
    }

    private func ops(_ recorder: Recorder, account: Bool, pullOK: Bool) -> CloudKitSyncService.InitialSyncOperations {
        CloudKitSyncService.InitialSyncOperations(
            accountAvailable: { recorder.calls.append("account"); return account },
            prepare: { recorder.calls.append("prepare") },
            push: { recorder.calls.append("push") },
            pull: { recorder.calls.append("pull"); return pullOK }
        )
    }

    func testStartFlushesHeldPushAfterSuccessfulPull() async {
        let service = CloudKitSyncService()
        service.schedulePush()                       // edit made before the first pull
        XCTAssertTrue(service.hasHeldPush)

        let recorder = Recorder()
        service.operationsOverride = ops(recorder, account: true, pullOK: true)
        await service.start()

        XCTAssertEqual(recorder.calls, ["account", "prepare", "pull", "push"],
                       "No push before the pull; the held edit is flushed right after it")
        XCTAssertEqual(service.initialSyncCompletedFor, profileId)
        XCTAssertFalse(service.hasHeldPush)
        XCTAssertEqual(service.flushedHeldPushCount, 1)
    }

    func testFailedPullKeepsGateClosedSaysSoAndRetryFlushes() async {
        let service = CloudKitSyncService()
        service.schedulePush()
        let recorder = Recorder()
        service.operationsOverride = ops(recorder, account: true, pullOK: false)
        await service.start()

        XCTAssertEqual(recorder.calls, ["account", "prepare", "pull"], "Nothing pushed after a failed pull")
        XCTAssertNil(service.initialSyncCompletedFor)
        XCTAssertTrue(service.hasHeldPush)
        XCTAssertEqual(service.syncError, CloudKitSyncService.heldChangesMessage, "Held changes are not silent")

        // Sync Now retries the initial sync; once the pull succeeds the edit is flushed.
        let retry = Recorder()
        service.operationsOverride = ops(retry, account: true, pullOK: true)
        await service.syncNow()
        XCTAssertEqual(Array(retry.calls.prefix(4)), ["account", "prepare", "pull", "push"])
        XCTAssertEqual(service.initialSyncCompletedFor, profileId)
        XCTAssertFalse(service.hasHeldPush)
    }

    func testICloudOffAtLaunchThenAvailableOpensGate() async {
        let service = CloudKitSyncService()
        let off = Recorder()
        service.operationsOverride = ops(off, account: false, pullOK: true)
        await service.start()
        XCTAssertEqual(off.calls, ["account"])
        XCTAssertNil(service.initialSyncCompletedFor)

        service.schedulePush()
        await service.syncNow()                      // still off: says so, doesn't hold silently
        XCTAssertNotNil(service.syncError)
        XCTAssertTrue(service.hasHeldPush)

        let on = Recorder()
        service.operationsOverride = ops(on, account: true, pullOK: true)
        await service.start()                         // what checkAccountStatus triggers on change
        XCTAssertEqual(on.calls, ["account", "prepare", "pull", "push"])
        XCTAssertEqual(service.initialSyncCompletedFor, profileId)
        XCTAssertFalse(service.hasHeldPush)
    }
}

// MARK: - Timer drafts

final class TimerDraftTests: XCTestCase {
    func testSuggestedHoursIsExactNotRoundedUp() {
        let twoMinutes = StaleTimerRecovery(startTime: Date(), propertyId: UUID(), category: .repairs,
                                            elapsedHours: 2.0 / 60.0, reason: .pausedAtSwitch)
        XCTAssertEqual(twoMinutes.suggestedHours, 2.0 / 60.0, accuracy: 0.0001)
        let forgotten = StaleTimerRecovery(startTime: Date(), propertyId: UUID(), category: .repairs, elapsedHours: 30)
        XCTAssertEqual(forgotten.suggestedHours, 24)
        XCTAssertTrue(forgotten.wasCapped)
        XCTAssertFalse(twoMinutes.wasCapped)
    }

    func testLegacyDraftWithoutReasonDecodesAsForgotten() throws {
        let recovery = StaleTimerRecovery(startTime: Date(timeIntervalSince1970: 0), propertyId: UUID(),
                                          category: .repairs, elapsedHours: 25)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(recovery)) as? [String: Any])
        object.removeValue(forKey: "reason")
        object.removeValue(forKey: "pausedAt")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(StaleTimerRecovery.self, from: legacy)
        XCTAssertEqual(decoded.reason, .forgotten)
        XCTAssertEqual(decoded.elapsedHours, 25)
    }
}

@MainActor
final class TimerDraftFlowTests: XCTestCase {
    private var authSnapshot: AuthStateSnapshot!
    private var id = ""

    override func setUp() {
        super.setUp()
        authSnapshot = AuthStateSnapshot.capture()
        AuthStateSnapshot.clearAll()
        id = "local-drafts-\(UUID().uuidString.prefix(8))"
    }

    override func tearDown() {
        AppViewModel.clearScopedAccountData(for: id)
        UserDefaults.standard.removeObject(forKey: "u.\(id).LandlordHours.properties")
        UserDefaults.standard.removeObject(forKey: "u.\(id).LandlordHours.entries")
        authSnapshot.restore()
        super.tearDown()
    }

    func testSecondSwitchKeepsEarlierDraftAndSaveUsesExactTime() throws {
        UserDefaults.standard.set(id, forKey: ProfileKeys.localProfileId)
        let viewModel = AppViewModel()
        viewModel.suppressCelebrations = true
        viewModel.addProperty(name: "Oak", address: "1 Oak", type: .ltr)
        let propertyId = viewModel.properties[0].id

        // First switch with a running timer → draft 1.
        viewModel.startTimer(propertyId: propertyId, category: .repairs)
        viewModel.signOut()
        UserDefaults.standard.set(id, forKey: ProfileKeys.localProfileId)
        viewModel.signIn()
        XCTAssertEqual(viewModel.staleTimerRecoveries.count, 1)

        // Second switch before reviewing draft 1 → draft 2 is added, draft 1 kept.
        viewModel.startTimer(propertyId: propertyId, category: .management)
        viewModel.signOut()
        UserDefaults.standard.set(id, forKey: ProfileKeys.localProfileId)
        viewModel.signIn()
        XCTAssertEqual(viewModel.staleTimerRecoveries.count, 2, "Earlier draft must not be overwritten")
        XCTAssertEqual(viewModel.staleTimerRecoveries.map(\.category), [.repairs, .management])
        XCTAssertTrue(viewModel.staleTimerRecoveries.allSatisfy { $0.reason == .pausedAtSwitch })

        // Saving uses the exact (tiny) elapsed time, never rounded up to 15 minutes.
        let entriesBefore = viewModel.timeEntries.count
        viewModel.saveRecoveredStaleTimer()
        XCTAssertEqual(viewModel.timeEntries.count, entriesBefore + 1)
        let saved = try XCTUnwrap(viewModel.timeEntries.first { $0.category == .repairs })
        XCTAssertLessThan(saved.hours, 0.25)
        XCTAssertEqual(viewModel.staleTimerRecoveries.count, 1, "The next draft is still waiting")

        viewModel.discardRecoveredStaleTimer()
        XCTAssertTrue(viewModel.staleTimerRecoveries.isEmpty)
        XCTAssertNil(UserDefaults.standard.data(forKey: "u.\(id).LandlordHours.staleTimerRecoveries"))
    }
}
