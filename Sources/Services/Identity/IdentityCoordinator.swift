import Foundation
import SwiftUI

// MARK: - What the identity surfaces show
//
// One observable object the views read: the iCloud status row, Earlier records, the two-sets
// question, the bulk / zone-gone / account-changed sheets, the Welcome footer (P1/P3/P2) and the
// one Today notice. It owns the engine and the Earlier records store and wires them to the sync.

enum ICloudRecordsStatus: Equatable {
    case on(lastSync: Date?)
    case syncing
    /// No account, LandlordHours switched off, or this build has no iCloud.
    case off
    /// A managed or child account: can't be used for sync.
    case restricted
    case problem(String, lastSync: Date?)
}

/// The Today card K fills (C owns how it looks; K owns when and what).
enum TodayIdentityNotice: Equatable, Identifiable {
    /// P10: iCloud is off, after the first saved entry.
    case iCloudOff
    /// P11: the cloud step is waiting for iCloud.
    case cloudWaiting
    /// P12: the migration finished (once).
    case unified
    /// P25: the backup couldn't be written.
    case needsSpace(bytes: Int)
    /// P29: the household settings were kept over this phone's setup answers.
    case settingsKept
    /// P28 entry: a bulk hold is waiting.
    case bulkWaiting(hours: Double, total: Double)
    /// P13 decided later.
    case accountChangedLater
    /// Quota (U38).
    case iCloudFull

    var id: String {
        switch self {
        case .iCloudOff: return "p10"
        case .cloudWaiting: return "p11"
        case .unified: return "p12"
        case .needsSpace: return "p25"
        case .settingsKept: return "p29"
        case .bulkWaiting: return "p28"
        case .accountChangedLater: return "p13"
        case .iCloudFull: return "quota"
        }
    }
}

/// Welcome's footer state (§4.3 B hand-off): P1 / P3 (≤ 8 s) / P2.
enum WelcomeRecordsState: Equatable {
    case standard
    case checking
    case found(hours: Double)
}

/// Counts for Settings › iCloud & records and the Welcome / Today copy.
enum IdentityRecordsSummary {
    /// Anything came from an earlier version on this device (an upgrade, not a fresh install).
    static func wasUpgrade(root: URL = MigrationFiles.defaultRoot) -> Bool {
        guard let groups = GroupsFile.load(root: root) else { return false }
        return groups.groups.contains { $0.entryCount > 0 || $0.propertyCount > 0 }
    }
}

@MainActor
final class IdentityCoordinator: ObservableObject {
    let defaults: UserDefaults
    let root: URL
    let earlier: EarlierRecordsStore
    private(set) var engine: RecordSetMigration?
    private(set) var source: IdentityZoneSource?

    @Published private(set) var status: ICloudRecordsStatus = .off
    @Published private(set) var pendingQuestion: ArchivedGroup?
    @Published private(set) var pendingIndex = 1
    @Published private(set) var pendingTotal = 1
    @Published private(set) var bulkHold: BulkHold?
    @Published private(set) var zoneGone = false
    @Published private(set) var accountChanged = false
    @Published private(set) var welcome: WelcomeRecordsState = .standard
    @Published private(set) var todayNotice: TodayIdentityNotice?
    @Published private(set) var groups: GroupsFile?
    /// The person swiped the question away this launch ("Decide later").
    @Published var questionDeferred = false
    @Published var bulkDeferred = false
    @Published var accountChangedDeferred = false
    /// iCloud search failed (diagnosis §7.1): shown, never hidden.
    @Published private(set) var searchFailed = false

    init(defaults: UserDefaults = .standard, root: URL = MigrationFiles.defaultRoot) {
        self.defaults = defaults
        self.root = root
        self.earlier = EarlierRecordsStore(root: root)
    }

    func attach(source: IdentityZoneSource, live: LiveRecordSet, sync: CloudKitSyncService) {
        self.source = source
        let engine = RecordSetMigration(defaults: defaults, root: root, source: source, live: live, earlier: earlier)
        #if DEBUG
        engine.crashAt = IdentityFixtures.crashAt
        #endif
        engine.onChange = { [weak self] in self?.refresh() }
        self.engine = engine
        sync.engine = engine
        if source !== sync { sync.zoneSourceOverride = source }
        sync.onIdentityChange = { [weak self] in self?.refresh() }
        refresh()
    }

    // MARK: Refresh

    func refresh(sync: CloudKitSyncService? = nil) {
        earlier.reload()
        earlier.purgeExpired()
        groups = GroupsFile.load(root: root)
        bulkHold = earlier.bulkHold
        zoneGone = defaults.bool(forKey: IdentityKeys.zoneGone)
        accountChanged = defaults.bool(forKey: IdentityKeys.accountChanged)
        searchFailed = defaults.string(forKey: IdentityKeys.lastSyncProblem) != nil && IdentityScope.step(defaults) < .cloudInventoried
        let pending = earlier.pendingGroups
        pendingTotal = max(pending.count, 1)
        pendingQuestion = pending.first
        pendingIndex = 1
        if let sync { updateStatus(sync) }
        todayNotice = computeNotice()
    }

    func updateStatus(_ sync: CloudKitSyncService) {
        let state = sync.accountState
        if sync.isSyncing || sync.isRunningInitialSync {
            status = .syncing
        } else if state == .restricted {
            status = .restricted
        } else if state == .noAccount || state == .unsupported {
            status = .off
        } else if let problem = defaults.string(forKey: IdentityKeys.lastSyncProblem) ?? sync.syncError {
            status = .problem(problem, lastSync: sync.lastSyncDate)
        } else if sync.accountAvailable {
            status = .on(lastSync: sync.lastSyncDate)
        } else if state == .temporarilyUnavailable || state == .couldNotDetermine {
            // "Can't tell right now" keeps the last state and retries (§1.4).
            if case .syncing = status { status = .on(lastSync: sync.lastSyncDate) }
        } else {
            status = .off
        }
        todayNotice = computeNotice(sync: sync)
    }

    private func computeNotice(sync: CloudKitSyncService? = nil) -> TodayIdentityNotice? {
        if let bytes = defaults.object(forKey: IdentityKeys.backupNeededBytes) as? Int { return .needsSpace(bytes: bytes) }
        if let hold = bulkHold { return .bulkWaiting(hours: hold.heldHours, total: hold.totalHours) }
        if accountChanged { return .accountChangedLater }
        if defaults.bool(forKey: IdentityKeys.noticeSettingsKept) { return .settingsKept }
        if defaults.object(forKey: IdentityKeys.noticeDone) as? Bool == false { return .unified }
        if case .problem(let text, _) = status, text.contains(String(localized: "iCloud is full.", table: "Identity")) { return .iCloudFull }
        if defaults.bool(forKey: IdentityKeys.noticeCloudWaiting), IdentityScope.step(defaults) < .cloudInventoried,
           IdentityRecordsSummary.wasUpgrade(root: root), status != .off { return .cloudWaiting }
        if status == .off || status == .restricted, hasSavedEntry, !iCloudOffSnoozed { return .iCloudOff }
        return nil
    }

    /// Set by the view model when the live set has at least one entry.
    var hasSavedEntry = false

    private var iCloudOffSnoozed: Bool {
        guard let at = defaults.object(forKey: IdentityKeys.noticeICloudOffDismissedAt) as? Date else { return false }
        return Date().timeIntervalSince(at) < 30 * 86_400
    }

    func dismissNotice(_ notice: TodayIdentityNotice) {
        switch notice {
        case .unified: defaults.set(true, forKey: IdentityKeys.noticeDone)
        case .settingsKept: defaults.removeObject(forKey: IdentityKeys.noticeSettingsKept)
        case .iCloudOff: defaults.set(Date(), forKey: IdentityKeys.noticeICloudOffDismissedAt)
        case .cloudWaiting: defaults.removeObject(forKey: IdentityKeys.noticeCloudWaiting)
        case .needsSpace, .bulkWaiting, .accountChangedLater, .iCloudFull: break
        }
        todayNotice = computeNotice()
    }

    // MARK: Welcome (P1 / P3 / P2)

    /// While the device set is empty and iCloud is on, Welcome says it is checking (≤ 8 s), then
    /// what it found. Tapping Get started meanwhile is fine (dirtyWhileEmpty protects the answers).
    func runWelcomeCheck(liveHours: () -> Double, sync: CloudKitSyncService) async {
        let before = liveHours()
        if before > 0 { welcome = .found(hours: before); return }
        guard IdentityScope.step(defaults) < .done else { welcome = .standard; return }
        welcome = .checking
        let task = Task { await sync.start() }
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if liveHours() > 0 || !sync.isRunningInitialSync { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        _ = task
        let after = liveHours()
        welcome = after > 0 ? .found(hours: after) : .standard
    }

    func setWelcome(_ state: WelcomeRecordsState) { welcome = state }

    // MARK: Answers (forwarded to the engine)

    func answer(_ answer: TwoSetsAnswer, group id: String) { engine?.answer(answer, group: id); questionDeferred = false; refresh() }
    func undoSpouse(group id: String) { engine?.undoSpouse(group: id); refresh() }
    func reconsider(group id: String) { engine?.reconsider(group: id); refresh() }
    func deleteGroup(_ id: String) async { await engine?.deleteGroup(id); refresh() }
    func putBack(_ names: Set<String>) { engine?.putBack(names); refresh() }
    func answerBulk(_ answer: BulkAnswer) { engine?.answerBulk(answer); bulkDeferred = false; refresh() }
    func deferAccountChanged() { accountChangedDeferred = true; refresh() }
    func showAccountChangedAgain() { accountChangedDeferred = false; refresh() }

    var archivedGroups: [ArchivedGroup] { earlier.groups.filter { !$0.isEmpty || $0.settingsOnly } }
    var settingsOnlyGroups: [GroupRecord] { groups?.groups.filter { $0.settingsOnly } ?? [] }
    var removed: [RemovedRecord] { earlier.removed }
    var unparsedCount: Int { defaults.integer(forKey: IdentityKeys.unparsedCount) }
    var waitingCount: Int { earlier.pendingGroups.count + (bulkHold == nil ? 0 : 1) }
    var earlierCount: Int { archivedGroups.count + (removed.isEmpty ? 0 : 1) + settingsOnlyGroups.count }
    var discardedSettings: DiscardedSettings? {
        defaults.data(forKey: IdentityKeys.discardedOnboardingAnswers).flatMap { try? JSONDecoder().decode(DiscardedSettings.self, from: $0) }
    }
    var backupURL: URL? { MigrationBackup.latestURL(root: root) }
}
