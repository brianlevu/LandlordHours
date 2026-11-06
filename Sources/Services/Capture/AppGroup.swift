import Foundation

// MARK: - App Group
//
// Extensions (widget, share sheet, Control) run in their own process and cannot read the app's
// UserDefaults.standard, where all records live. They hand work to the app through a drop box
// in the shared App Group container: ONE FILE PER ITEM, written atomically by the extension,
// consumed (then deleted) by the app. Nothing is ever written to one shared file by both
// processes, so neither can lose the other's writes.
enum AppGroup {
    static let identifier = "group.com.openclaw.landlordhours"

    /// The shared container, or nil when the entitlement is missing (e.g. some test hosts).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var dropBox: AppGroupDropBox? {
        containerURL.map { AppGroupDropBox(directory: $0.appendingPathComponent("DropBox", isDirectory: true)) }
    }
}

/// One-file-per-item hand-off between processes.
struct AppGroupDropBox {
    struct Item<Payload: Codable>: Codable {
        var id: UUID
        var createdAt: Date
        /// The profile the item was made for; the app rejects items for an inactive profile.
        var profileId: String?
        var payload: Payload
    }

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// Writes one item as its own file (`<createdAt>-<id>.json`). Atomic: a reader never sees a
    /// half-written file.
    @discardableResult
    func drop<Payload: Codable>(_ payload: Payload, profileId: String?, id: UUID = UUID(), now: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let item = Item(id: id, createdAt: now, profileId: profileId, payload: payload)
        let data = try JSONEncoder.captureEncoder.encode(item)
        let millis = Int64(now.timeIntervalSince1970 * 1000)
        let url = directory.appendingPathComponent("\(millis)-\(id.uuidString).json")
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }

    /// File URLs of waiting items, oldest first.
    func pendingFiles() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Hands each waiting item to `handler` (oldest first). An item is deleted only when the
    /// handler returns true, so a failed or interrupted consume retries next time. Unreadable
    /// files are deleted. Returns the number of items consumed.
    @discardableResult
    func consume<Payload: Codable>(_ type: Payload.Type, handler: (Item<Payload>) throws -> Bool) -> Int {
        var consumed = 0
        for url in pendingFiles() {
            guard let data = try? Data(contentsOf: url),
                  let item = try? JSONDecoder.captureDecoder.decode(Item<Payload>.self, from: data) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            if (try? handler(item)) == true {
                try? FileManager.default.removeItem(at: url)
                consumed += 1
            }
        }
        return consumed
    }
}

// MARK: - Background task identifiers
//
// Declared in Info.plist (`BGTaskSchedulerPermittedIdentifiers`). Registration and scheduling
// belong to the notifications work package; a test keeps this list and Info.plist in step.
enum BackgroundTaskIdentifiers {
    /// BGAppRefreshTask: re-scan the calendar and rebuild end-of-event notifications.
    static let captureRefresh = "com.openclaw.landlordhours.capture.refresh"
    /// BGProcessingTask: day-1 90-day backfill and classification when the device is idle.
    static let captureBackfill = "com.openclaw.landlordhours.capture.backfill"

    static let all = [captureRefresh, captureBackfill]
}
