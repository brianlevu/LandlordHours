import Foundation

// MARK: - Package K: one identity, records that follow you (2.2)
//
// The iCloud account the device is signed in to is the only identity. There is no sign-in and no
// profile. On the device the record set lives under one fixed key prefix (`v2.`) plus the existing
// Application Support folders; in iCloud it is the private zone `LandlordHoursZone`, tagged with
// one unified id. Every 1.x / 2.0.x state is mapped onto that model by `RecordSetMigration`
// (steps S1–S10 of `docs/design/v2-identity-package-K.md` §3.1). Nothing is ever deleted by the
// merge: what it cannot place goes to Earlier records, Recently removed or the backup.

/// The migration steps, in order. Persisted as `v2.migration.state`.
enum MigrationStep: String, Codable, CaseIterable, Comparable {
    case notStarted
    case inventoried
    case backedUp
    case groupsResolved
    case deviceMerged
    case cloudInventoried
    case cloudResolved
    case cloudMerged
    case householdWritten
    case deltaPulled
    case pushed
    case done

    private var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    static func < (lhs: MigrationStep, rhs: MigrationStep) -> Bool { lhs.order < rhs.order }
}

/// Every unscoped key package K writes. All live under `v2.` so Delete all data can find them.
enum IdentityKeys {
    static let prefix = "v2."
    static let state = "v2.migration.state"
    /// The scope id: folder names (`Capture/<id>`, `Sync/<id>`), capture ids, notification ids.
    /// Frozen at `deviceMerged` (the device primary's legacy id, or "household").
    static let storageId = "v2.storageId"
    /// The CloudKit `appUserId` tag of the live set. Provisional until S8 decides it.
    static let unifiedId = "v2.unifiedId"
    static let unifiedIdDecided = "v2.unifiedId.decided"
    /// Capture ids derive from this (R19); frozen with the storage id.
    static let captureProfileId = "v2.captureProfileId"
    /// The iCloud user record name learned at S5 (account guard, §1.4).
    static let icloudUserRecordName = "v2.icloudUserRecordName"
    /// Set while the S2 backup could not be written (§3.4): the app keeps running on `u.<id>.`.
    static let legacyPrefixId = "v2.legacyPrefixId"
    static let backupNeededBytes = "v2.migration.backupNeededBytes"
    /// Settings precedence flags (v4 §3.3), set by user edits only.
    static let goalDirty = "v2.goal.dirty"
    static let goalDirtyWhileEmpty = "v2.goal.dirtyWhileEmpty"
    static let taxDirty = "v2.tax.dirty"
    static let taxDirtyWhileEmpty = "v2.tax.dirtyWhileEmpty"
    /// Names deleted after migration (90 days): blocks resurrection from 1.1 devices (R11).
    static let deletedRecordNames = "v2.deletedRecordNames"
    /// The zone was deleted on another device (P31); sync paused until answered.
    static let zoneGone = "v2.sync.zoneGone"
    /// This device has completed at least one sync with the zone (zone-gone guard).
    static let hasSynced = "v2.sync.hasSynced"
    /// The iCloud account changed (P13); sync paused until answered.
    static let accountChanged = "v2.sync.accountChanged"
    /// Per-launch/once notices (Today cards).
    static let noticeDone = "v2.notice.p12Shown"
    static let noticeSettingsKept = "v2.notice.p29Pending"
    static let noticeICloudOffDismissedAt = "v2.notice.p10DismissedAt"
    static let noticeCloudWaiting = "v2.notice.p11"
    /// The onboarding answers that lost to the household pair (P29 / Advanced).
    static let discardedOnboardingAnswers = "v2.merge.discardedSettings"
    /// Your name (also synced in `TaxProfile.displayName`).
    static let displayName = "v2.profile.name"
    /// Records counted at the last S5 read that could not be parsed (P26).
    static let unparsedCount = "v2.sync.unparsedCount"
    /// The last iCloud problem (status row text), and when the last successful sync ran.
    static let lastSyncProblem = "v2.sync.lastProblem"
    /// Remaining S8b loops after `changeTokenExpired`.
    static let deltaLoops = "v2.migration.deltaLoops"
    /// Zone server change token from S5 (archived `CKServerChangeToken`).
    static let migrationZoneToken = "v2.migration.zoneToken"
}

/// Which key prefix and scope id the app runs on right now.
///
/// `UserScope` (AppViewModel.swift) is a thin wrapper over this: every existing call site keeps
/// calling `UserScope.key(_:)` and lands on `v2.` once the device merge has run.
enum IdentityScope {
    struct Resolved: Equatable {
        /// The scope id (`UserScope.userId`): nil only before the first launch of 2.2 finished S4.
        var scopeId: String?
        /// The key prefix: `v2.`, `u.<id>.` (legacy-prefix mode, DEBUG fixtures) or "" (none yet).
        var prefix: String
    }

    #if DEBUG
    /// Unit tests and DEBUG captures pin an isolated legacy-shaped scope (`u.<id>.`), so a mock
    /// scenario never touches the person's real `v2.` record set.
    static var debugOverride: String?
    static let debugScopeKey = "debug.scopeId"
    #endif

    static func resolve(_ defaults: UserDefaults = .standard) -> Resolved {
        #if DEBUG
        if let id = debugOverride, !id.isEmpty { return Resolved(scopeId: id, prefix: "u.\(id).") }
        if let id = defaults.string(forKey: debugScopeKey), !id.isEmpty { return Resolved(scopeId: id, prefix: "u.\(id).") }
        #endif
        if let legacy = defaults.string(forKey: IdentityKeys.legacyPrefixId), !legacy.isEmpty {
            return Resolved(scopeId: legacy, prefix: "u.\(legacy).")
        }
        if step(defaults) >= .deviceMerged, let storage = defaults.string(forKey: IdentityKeys.storageId), !storage.isEmpty {
            return Resolved(scopeId: storage, prefix: IdentityKeys.prefix)
        }
        return Resolved(scopeId: nil, prefix: "")
    }

    /// A DEBUG mock or fixture scope is active: it must never sync with the person's real zone.
    static func isDebugScope(_ defaults: UserDefaults = .standard) -> Bool {
        #if DEBUG
        return (debugOverride?.isEmpty == false) || (defaults.string(forKey: debugScopeKey)?.isEmpty == false)
        #else
        return false
        #endif
    }

    static func step(_ defaults: UserDefaults = .standard) -> MigrationStep {
        defaults.string(forKey: IdentityKeys.state).flatMap(MigrationStep.init(rawValue:)) ?? .notStarted
    }

    /// The CloudKit tag for the live set (`appUserId`). Falls back to the scope id.
    static func unifiedId(_ defaults: UserDefaults = .standard) -> String? {
        #if DEBUG
        if let id = debugOverride, !id.isEmpty { return id }
        if let id = defaults.string(forKey: debugScopeKey), !id.isEmpty { return id }
        #endif
        if let legacy = defaults.string(forKey: IdentityKeys.legacyPrefixId), !legacy.isEmpty { return legacy }
        return defaults.string(forKey: IdentityKeys.unifiedId) ?? resolve(defaults).scopeId
    }

    /// True for the scope id and for every legacy id merged into the live set (combined, spouse,
    /// or the primary). A notification or queued "Log it" made under one of them lands here.
    static func isLiveProfileId(_ id: String, defaults: UserDefaults = .standard) -> Bool {
        if id == resolve(defaults).scopeId { return true }
        if id == unifiedId(defaults) { return true }
        return MigrationFiles.liveLegacyIds(defaults: defaults).contains(id)
    }
}

/// Where the migration writes its files: `Application Support/migration/` and `archive/`.
enum MigrationFiles {
    nonisolated static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    static func migrationDirectory(root: URL) -> URL { root.appendingPathComponent(IdentityFolder.migration.rawValue, isDirectory: true) }
    static func archiveDirectory(root: URL) -> URL { root.appendingPathComponent(IdentityFolder.archive.rawValue, isDirectory: true) }
    static func groupsURL(root: URL) -> URL { migrationDirectory(root: root).appendingPathComponent("groups.json") }

    /// Ids listed in groups.json as merged into the live set (primary, combine, spouse).
    static func liveLegacyIds(defaults: UserDefaults = .standard, root: URL = defaultRoot) -> Set<String> {
        guard let groups = GroupsFile.load(root: root) else { return [] }
        return Set(groups.groups.filter { $0.status.isLive }.map(\.id))
    }

    /// Writes `data` atomically and flushes it to disk before returning (S2, "fsynced").
    static func writeDurably(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        guard fm.createFile(atPath: temp.path, contents: nil,
                            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: temp)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            try? fm.removeItem(at: temp)
            throw error
        }
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        try fm.moveItem(at: temp, to: url)
    }
}
