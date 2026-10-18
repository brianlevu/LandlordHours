import XCTest
import CloudKit
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

    func testForgottenTimerNoteAndCapCopy() {
        let forgotten = StaleTimerRecovery(startTime: Date(), propertyId: UUID(), category: .repairs, elapsedHours: 30)
        XCTAssertEqual(forgotten.entryNote, "Recovered from a timer that was left running.")
        XCTAssertEqual(forgotten.accessibilityTitle, "Timer left running.")
        let message = forgotten.cardMessage(propertyName: "Oak", hasAnyProperty: true)
        XCTAssertTrue(message.contains("We stopped it at 24 hours. Check it before you save."), message)

        let short = StaleTimerRecovery(startTime: Date(), propertyId: UUID(), category: .repairs, elapsedHours: 3)
        XCTAssertFalse(short.cardMessage(propertyName: "Oak", hasAnyProperty: true)
            .contains("24 hours"))
    }

    func testPausedOver24hShowsCapNoteAndPausedUnderDoesNot() {
        let over = StaleTimerRecovery(startTime: Date(), propertyId: UUID(), category: .repairs,
                                      elapsedHours: 26, reason: .pausedAtSwitch)
        let overMessage = over.cardMessage(propertyName: "Oak", hasAnyProperty: true)
        XCTAssertTrue(overMessage.contains("We stopped it at 24 hours. Check it before you save."), overMessage)
        XCTAssertEqual(over.suggestedHours, 24)

        let under = StaleTimerRecovery(startTime: Date(), propertyId: UUID(), category: .repairs,
                                       elapsedHours: 0.5, reason: .pausedAtSwitch)
        let underMessage = under.cardMessage(propertyName: "Oak", hasAnyProperty: true)
        XCTAssertFalse(underMessage.contains("24 hours"))
        XCTAssertTrue(underMessage.contains("switched profiles"))

        let deleted = under.cardMessage(propertyName: nil, hasAnyProperty: false)
        XCTAssertTrue(deleted.contains("Add a property to save it"))
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

    private func makeTwoDrafts(_ viewModel: AppViewModel) -> UUID {
        viewModel.suppressCelebrations = true
        viewModel.addProperty(name: "Oak", address: "1 Oak", type: .ltr)
        let propertyId = viewModel.properties[0].id
        for category in [ActivityCategory.repairs, .management] {
            viewModel.startTimer(propertyId: propertyId, category: category)
            viewModel.signOut()
            UserDefaults.standard.set(id, forKey: ProfileKeys.localProfileId)
            viewModel.signIn()
        }
        return propertyId
    }

    func testPausedDraftSavesWithTruthfulNote() throws {
        UserDefaults.standard.set(id, forKey: ProfileKeys.localProfileId)
        let viewModel = AppViewModel()
        _ = makeTwoDrafts(viewModel)
        let first = try XCTUnwrap(viewModel.staleTimerRecovery)
        XCTAssertTrue(viewModel.saveRecoveredStaleTimer(id: first.id))
        let saved = try XCTUnwrap(viewModel.timeEntries.first)
        XCTAssertEqual(saved.notes, "Timer paused when switching profiles.")
        XCTAssertNotEqual(saved.notes, "Recovered from a timer that was left running.")
        XCTAssertEqual(first.accessibilityTitle, "Timer paused when you switched profiles.")
    }

    func testDoubleTapSaveSavesOnlyTheDisplayedDraft() throws {
        UserDefaults.standard.set(id, forKey: ProfileKeys.localProfileId)
        let viewModel = AppViewModel()
        _ = makeTwoDrafts(viewModel)
        let shown = try XCTUnwrap(viewModel.staleTimerRecovery)
        let before = viewModel.timeEntries.count

        XCTAssertTrue(viewModel.saveRecoveredStaleTimer(id: shown.id))
        XCTAssertFalse(viewModel.saveRecoveredStaleTimer(id: shown.id), "Second tap is a no-op")

        XCTAssertEqual(viewModel.timeEntries.count, before + 1)
        XCTAssertEqual(viewModel.staleTimerRecoveries.count, 1, "The unseen draft is still pending")
        XCTAssertEqual(viewModel.staleTimerRecoveries.first?.category, .management)
    }

    func testDraftForDeletedPropertyIsKeptAndCanBeSavedElsewhere() throws {
        UserDefaults.standard.set(id, forKey: ProfileKeys.localProfileId)
        let viewModel = AppViewModel()
        viewModel.suppressCelebrations = true
        viewModel.addProperty(name: "Oak", address: "1 Oak", type: .ltr)
        viewModel.addProperty(name: "Pine", address: "2 Pine", type: .ltr)
        let oak = viewModel.properties[0], pine = viewModel.properties[1]
        viewModel.startTimer(propertyId: oak.id, category: .repairs)
        viewModel.signOut()
        UserDefaults.standard.set(id, forKey: ProfileKeys.localProfileId)
        viewModel.signIn()
        viewModel.deleteProperty(viewModel.properties.first { $0.id == oak.id }!)

        // Reload: the draft is kept, not dropped.
        viewModel.signOut()
        UserDefaults.standard.set(id, forKey: ProfileKeys.localProfileId)
        viewModel.signIn()
        let draft = try XCTUnwrap(viewModel.staleTimerRecovery)
        XCTAssertTrue(viewModel.staleTimerRecoveryNeedsProperty(draft))
        XCTAssertFalse(viewModel.saveRecoveredStaleTimer(id: draft.id), "Can't save to a deleted property")
        XCTAssertTrue(viewModel.saveRecoveredStaleTimer(id: draft.id, propertyId: pine.id))
        XCTAssertEqual(viewModel.timeEntries.filter { $0.propertyId == pine.id }.count, 1)
        XCTAssertTrue(viewModel.staleTimerRecoveries.isEmpty)
    }

    func testCappedDraftCannotBeSavedWithOneTap() throws {
        TimerDraftFixture.seed("forgotten24h")
        let viewModel = AppViewModel()
        let draft = try XCTUnwrap(viewModel.staleTimerRecovery)
        defer {
            AppViewModel.clearScopedAccountData(for: TimerDraftFixture.profileId)
            UserDefaults.standard.removeObject(forKey: "u.\(TimerDraftFixture.profileId).LandlordHours.staleTimerRecoveries")
        }
        XCTAssertTrue(draft.requiresReview)
        let before = viewModel.timeEntries.count

        XCTAssertFalse(viewModel.saveRecoveredStaleTimer(id: draft.id), "One-tap save of a capped draft is refused")
        XCTAssertEqual(viewModel.timeEntries.count, before)
        XCTAssertEqual(viewModel.staleTimerRecoveries.count, 1)

        // Saving with reviewed hours works.
        XCTAssertTrue(viewModel.saveRecoveredStaleTimer(id: draft.id, hours: 6))
        XCTAssertEqual(viewModel.timeEntries.last?.hours, 6)
    }

    func testRanLabelAlwaysShowsRealElapsedTime() {
        func ran(_ h: Double) -> String {
            StaleTimerRecovery(startTime: Date(), propertyId: UUID(), category: .repairs, elapsedHours: h).ranLabel
        }
        XCTAssertEqual(ran(0.75), "Ran 45 min")
        XCTAssertEqual(ran(30), "Ran 30.0h")
        XCTAssertEqual(ran(0.001), "Ran under 1 min")
    }

    func testDurationLabelShowsMinutesUnderAnHour() {
        func label(_ hours: Double) -> String {
            StaleTimerRecovery(startTime: Date(), propertyId: UUID(), category: .repairs,
                               elapsedHours: hours, reason: .pausedAtSwitch).durationLabel
        }
        XCTAssertEqual(label(2.0 / 60.0), "2 min")
        XCTAssertEqual(label(0.2 / 60.0), "under 1 min")
        XCTAssertEqual(label(1.5), "1.5h")
    }
}

@MainActor
final class SyncStatusTests: XCTestCase {
    private var authSnapshot: AuthStateSnapshot!
    private var profileId = ""

    override func setUp() {
        super.setUp()
        authSnapshot = AuthStateSnapshot.capture()
        AuthStateSnapshot.clearAll()
        profileId = "local-status-\(UUID().uuidString.prefix(8))"
        UserDefaults.standard.set(profileId, forKey: ProfileKeys.localProfileId)
    }

    override func tearDown() {
        AppViewModel.clearScopedAccountData(for: profileId)
        authSnapshot.restore()
        super.tearDown()
    }

    func testSyncNowDuringInitialSyncDoesNotReportFailure() async {
        let service = CloudKitSyncService()
        service.schedulePush()
        var errorSeenDuringSync: String? = "unset"
        var runningSeen = false
        service.operationsOverride = CloudKitSyncService.InitialSyncOperations(
            accountAvailable: { true },
            prepare: {},
            push: {},
            pull: {
                runningSeen = service.isRunningInitialSync
                await service.syncNow()           // user taps Sync Now mid-sync
                errorSeenDuringSync = service.syncError
                return true
            }
        )
        await service.start()
        XCTAssertTrue(runningSeen)
        XCTAssertNil(errorSeenDuringSync, "No false 'Couldn't reach iCloud' while syncing")
        XCTAssertEqual(service.initialSyncCompletedFor, profileId)
    }

    func testAccountChangedNotificationRechecksAccount() async {
        let service = CloudKitSyncService()
        let before = service.accountStatusCheckCount
        NotificationCenter.default.post(name: .CKAccountChanged, object: nil)
        for _ in 0..<50 where service.accountStatusCheckCount == before {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertGreaterThan(service.accountStatusCheckCount, before)
    }
}
