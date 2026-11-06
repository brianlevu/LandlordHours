import Foundation
import CloudKit
import CryptoKit
import os.log

private let trackerLogger = Logger(subsystem: "com.openclaw.landlordhours", category: "SyncChangeTracker")

// MARK: - Push changed records only
//
// Before 2.0 every push sent EVERY local record (last writer wins on the server). An old copy
// on one device could then overwrite a newer edit made on another. Now a push sends only
// records whose content differs from what this device last knew the server holds:
// - after a successful push, the pushed content becomes the baseline;
// - after a pull, the server's content becomes the baseline (so pulled data is never echoed
//   back, and a local copy that is still newer after the merge is still pushed);
// - a record with no baseline (new, or first run after the upgrade) is pushed, exactly as 1.x
//   would have.
// The record format is unchanged, so 1.1 devices read 2.0 records as before.
//
// Baselines are content fingerprints (SHA-256 of the record's fields), stored per profile in
// Application Support/Sync/<profile>/pushed-fingerprints.json.
@MainActor
final class SyncChangeTracker {
    struct Contents: Codable, Equatable {
        var version = 1
        /// recordName → fingerprint of the content the server is known to hold.
        var fingerprints: [String: String] = [:]
        /// Records deleted locally whose iCloud delete hasn't been confirmed (tombstones).
        /// Optional so files written before tombstones existed still decode.
        var pendingDeletes: [String]?
    }

    /// Fields rewritten on every build of the record (1.x/2.0 settings stamped
    /// `modifiedAt = Date()`), so they can't tell a change apart. 2.2 settings records carry no
    /// `modifiedAt`; the exclusion stays so 2.0.x records compare equal.
    nonisolated static let volatileKeysByType: [String: Set<String>] = [
        "GoalSettings": ["modifiedAt"],
        "TaxProfile": ["modifiedAt"]
    ]

    let userId: String
    let fileURL: URL
    /// Read from disk before every use: the engine, the sync service and the answers each make
    /// their own instance for the same file, and a stale in-memory copy written back would erase
    /// another instance's tombstones or baselines.
    private var stored: Contents
    var contents: Contents { reload(); return stored }

    nonisolated static var defaultBaseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("Sync", isDirectory: true)
    }

    /// Profile delete: removes the profile's baselines and tombstones.
    nonisolated static func removeAll(forUserId userId: String, baseDirectory: URL = defaultBaseDirectory) {
        try? FileManager.default.removeItem(at: SuggestionStore.directory(forUserId: userId, baseDirectory: baseDirectory))
    }

    init(userId: String, baseDirectory: URL = SyncChangeTracker.defaultBaseDirectory) {
        self.userId = userId
        self.fileURL = SuggestionStore.directory(forUserId: userId, baseDirectory: baseDirectory)
            .appendingPathComponent("pushed-fingerprints.json")
        stored = Contents()
        reload()
    }

    private func reload() {
        if let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode(Contents.self, from: data) {
            stored = decoded
        } else {
            stored = Contents()
        }
    }

    // MARK: Fingerprints

    /// Stable fingerprint of a record's fields (record type and every non-volatile key).
    nonisolated static func fingerprint(_ record: CKRecord, excluding extra: Set<String> = []) -> String {
        let volatile = (volatileKeysByType[record.recordType] ?? []).union(extra)
        var parts = ["type=\(record.recordType)"]
        for key in record.allKeys().sorted() where !volatile.contains(key) {
            parts.append("\(key)=\(encode(record[key]))")
        }
        let digest = SHA256.hash(data: Data(parts.joined(separator: "\u{1F}").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func encode(_ value: CKRecordValue?) -> String {
        switch value {
        case nil: return "nil"
        case let date as Date: return "d:\(Int64((date.timeIntervalSince1970 * 1000).rounded()))"  // CloudKit keeps milliseconds
        case let string as String: return "s:\(string)"
        case let number as NSNumber: return "n:\(number.stringValue)"
        case let array as [Any]: return "a:[" + array.map { "\($0)" }.joined(separator: ",") + "]"
        case let reference as CKRecord.Reference: return "r:\(reference.recordID.recordName)"
        case let asset as CKAsset: return "f:\(asset.fileURL?.lastPathComponent ?? "")"
        case let other?: return "o:\(other)"
        }
    }

    // MARK: Queries

    /// Records whose content differs from the known server baseline (or have none).
    func changedRecords(_ records: [CKRecord]) -> [CKRecord] {
        let fingerprints = contents.fingerprints
        return records.filter { fingerprints[$0.recordID.recordName] != Self.fingerprint($0) }
    }

    func hasBaseline(for recordName: String) -> Bool { contents.fingerprints[recordName] != nil }

    // MARK: Updates

    /// The server now holds exactly these records (after a successful push, or as pulled).
    func recordServerState(_ records: [CKRecord]) {
        guard !records.isEmpty else { return }
        reload()
        // A record deleted locally meanwhile keeps no baseline; its tombstone is pushed next.
        let tombstoned = Set(stored.pendingDeletes ?? [])
        for record in records where !tombstoned.contains(record.recordID.recordName) {
            stored.fingerprints[record.recordID.recordName] = Self.fingerprint(record)
        }
        save()
    }

    /// Records deleted locally or on the server: no baseline any more.
    func forget(recordNames: [String]) {
        guard !recordNames.isEmpty else { return }
        reload()
        for name in recordNames { stored.fingerprints[name] = nil }
        save()
    }

    /// Account change or zone deleted: every local record is re-uploaded on the next push.
    /// Tombstones stay (a local delete must still reach iCloud).
    func resetBaselines() {
        reload()
        stored.fingerprints = [:]
        save()
    }

    // MARK: Tombstones

    var pendingDeletes: [String] { contents.pendingDeletes ?? [] }

    func addTombstones(_ recordNames: [String]) {
        reload()
        let before = stored.pendingDeletes ?? []
        var set = before
        for name in recordNames where !set.contains(name) { set.append(name) }
        guard set != before else { return }
        stored.pendingDeletes = set
        save()
    }

    /// iCloud confirmed these deletes.
    func clearTombstones(_ recordNames: [String]) {
        reload()
        let remove = Set(recordNames)
        let before = stored.pendingDeletes ?? []
        let remaining = before.filter { !remove.contains($0) }
        guard remaining.count != before.count else { return }
        stored.pendingDeletes = remaining.isEmpty ? nil : remaining
        // The server no longer holds them: a record re-created with the same id is new.
        for name in remove { stored.fingerprints[name] = nil }
        save()
    }

    /// Records that exist locally again are not deletes any more.
    func cancelTombstones(for localRecordNames: Set<String>) {
        clearTombstones(pendingDeletes.filter { localRecordNames.contains($0) })
    }

    /// Profile data deleted from iCloud: the next push starts from scratch.
    func reset() {
        stored = Contents()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(stored)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            trackerLogger.error("Could not save sync baselines: \(error.localizedDescription, privacy: .public)")
        }
    }
}
