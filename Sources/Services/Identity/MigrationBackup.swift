import Foundation

// MARK: - S2 · the backup (mandatory: no backup, no migration)
//
// `migration/v2-backup-<ISO>.json` holds every `u.*` key, every auth key and every unscoped 1.x
// key exactly as stored (each value property-list encoded, base64), plus the per-profile files
// (`Sync/<id>/pushed-fingerprints.json`, `Capture/<id>/suggestions.json`). Written to a temp
// name, flushed, renamed; `backedUp` is recorded only after that. If it can't be written (disk
// full), nothing else happens and the app keeps running on the legacy keys (§3.4, card P25).

struct MigrationBackup: Codable, Equatable {
    var version = 1
    var createdAt: Date
    /// key → base64 of a one-entry property list `{ "v": value }` (exact types survive).
    var keys: [String: String]
    /// Path relative to Application Support → base64 file contents.
    var files: [String: String]

    static let filePrefix = "v2-backup-"

    /// The keys a backup must hold: `u.*`, auth/profile pointers, unscoped 1.x keys, the capture
    /// queue (it carries profile ids), and nothing of the system's.
    static func backedUpKeys(in all: [String: Any]) -> [String] {
        let auth = Set(ProfileKeys.signOutKeys + [ProfileKeys.previousProfileId, CaptureActionQueue.key])
        let unscoped = Set(LegacyInventory.unscopedBaseKeys)
        return all.keys.filter { $0.hasPrefix("u.") || auth.contains($0) || unscoped.contains($0) }.sorted()
    }

    static func make(defaults: UserDefaults, root: URL, now: Date = Date()) -> MigrationBackup {
        let all = defaults.dictionaryRepresentation()
        var keys: [String: String] = [:]
        for key in backedUpKeys(in: all) {
            guard let value = all[key],
                  let data = try? PropertyListSerialization.data(fromPropertyList: ["v": value], format: .binary, options: 0)
            else { continue }
            keys[key] = data.base64EncodedString()
        }
        var files: [String: String] = [:]
        for sub in ["Sync", "Capture"] {
            let dir = root.appendingPathComponent(sub, isDirectory: true)
            guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "json" {
                guard let data = try? Data(contentsOf: url) else { continue }
                let relative = sub + "/" + url.path.replacingOccurrences(of: dir.path + "/", with: "")
                files[relative] = data.base64EncodedString()
            }
        }
        return MigrationBackup(createdAt: now, keys: keys, files: files)
    }

    /// The stored value for `key`, decoded back to its property-list type.
    func value(forKey key: String) -> Any? {
        guard let encoded = keys[key], let data = Data(base64Encoded: encoded),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["v"]
    }

    /// Writes the backup. `write` is the test seam (disk full).
    @discardableResult
    func write(root: URL, now: Date = Date(),
               write: (Data, URL) throws -> Void = { try MigrationFiles.writeDurably($0, to: $1) }) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let url = MigrationFiles.migrationDirectory(root: root).appendingPathComponent("\(Self.filePrefix)\(stamp).json")
        let data = try JSONEncoder.identity.encode(self)
        try write(data, url)
        // Size check: the file on disk is what we meant to write.
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
        if let size, size != data.count { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    /// The newest backup on disk (Advanced › Export the migration backup).
    static func latestURL(root: URL) -> URL? {
        let dir = MigrationFiles.migrationDirectory(root: root)
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.lastPathComponent.hasPrefix(filePrefix) }.sorted { $0.lastPathComponent > $1.lastPathComponent }.first
    }

    static func load(_ url: URL) -> MigrationBackup? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder.identity.decode(MigrationBackup.self, from: $0) }
    }
}
