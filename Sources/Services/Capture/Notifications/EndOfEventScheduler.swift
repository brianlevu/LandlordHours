import Foundation
import UIKit
import UserNotifications
import os.log

private let schedulerLogger = Logger(subsystem: "com.openclaw.landlordhours", category: "EndOfEventScheduler")

// MARK: - End-of-event scheduler
//
// One local notification per likely calendar suggestion, 5 minutes after the event ends
// (an absolute-time trigger, rebuilt when the time zone changes):
// "Plumber visit just ended. Log 2h at Pine Cabin?"
//
// Rules:
// - iPhone only. An iPad never schedules (and removes any it has), so one event never pings
//   twice across a user's devices.
// - Budget: at most 20 pending, at most 2 per calendar day (delivered ones count for their day).
// - Quiet hours 21:00–08:00: a fire time inside them moves to the next 08:00.
// - Only pending, calendar, not-backfill items at or above the "likely" confidence that are not
//   flagged "might already be logged" and whose fire time is still ahead.
// - Rebuilt from the full pending list on every launch, foreground and background refresh:
//   anything no longer wanted (confirmed, dismissed, moved, profile switched) is cancelled.
//   A notification that was already delivered is never scheduled again.
@MainActor
final class EndOfEventScheduler: CaptureNotifier {
    struct Policy: Equatable {
        var maxPending = 20
        var maxPerDay = 2
        var quietStartHour = 21
        var quietEndHour = 8
        var delayAfterEnd: TimeInterval = 5 * 60
        /// Same value as WP2's `ClassifierThresholds.likely`; switch to that constant once the
        /// classifier is merged into release/2.0.
        var likelyThreshold = 0.60
    }

    nonisolated static let identifierPrefix = "capture.end."
    nonisolated static let threadIdentifier = "landlordhours.capture"
    nonisolated static let fireAtKey = "fireAt"
    nonisolated static let timeZoneKey = "timeZone"
    nonisolated static let logKey = "LandlordHours.capture.notificationLog"

    nonisolated static func identifier(forSourceKey key: String) -> String { identifierPrefix + key }

    let policy: Policy
    private let center: CaptureNotificationCenter
    private let isPhone: () -> Bool
    private let clock: () -> Date
    /// Read on every use, so a time-zone change (travel, DST) is picked up by the next rebuild.
    private let calendarProvider: () -> Calendar
    private var calendar: Calendar { calendarProvider() }
    private let defaults: UserDefaults
    private let propertyNames: () -> [UUID: String]

    init(
        center: CaptureNotificationCenter = SystemCaptureNotificationCenter(),
        policy: Policy = Policy(),
        isPhone: @escaping () -> Bool = { UIDevice.current.userInterfaceIdiom == .phone },
        clock: @escaping () -> Date = Date.init,
        calendar: @escaping () -> Calendar = { Calendar.autoupdatingCurrent },
        defaults: UserDefaults = .standard,
        propertyNames: @escaping () -> [UUID: String] = { [:] }
    ) {
        self.center = center
        self.policy = policy
        self.isPhone = isPhone
        self.clock = clock
        self.calendarProvider = calendar
        self.defaults = defaults
        self.propertyNames = propertyNames
    }

    // MARK: CaptureNotifier

    /// Rebuilds the schedule. `suggestions` is the profile's FULL pending list: anything not in
    /// it is cancelled.
    func schedule(_ suggestions: [Suggestion], profileId: String) async {
        await rebuild(pending: suggestions, profileId: profileId)
    }

    func cancel(sourceKeys: [String]) async {
        let ids = sourceKeys.map(Self.identifier(forSourceKey:))
        center.removePending(identifiers: ids)
        center.removeDelivered(identifiers: ids)
        var log = loadLog()
        let now = clock()
        for id in ids where (log[id] ?? .distantPast) > now { log[id] = nil }
        saveLog(log)
    }

    /// Removes every pending end-of-event notification (iPad, kill switch, signed out).
    func removeAllPending() async {
        let ours = await center.pendingRequests().map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePending(identifiers: ours)
        var log = loadLog()
        let now = clock()
        log = log.filter { $0.value <= now }
        saveLog(log)
    }

    // MARK: Rebuild

    struct Planned: Equatable {
        var suggestion: Suggestion
        var fireDate: Date
        var deferred: Bool
    }

    func rebuild(pending suggestions: [Suggestion], profileId: String) async {
        guard isPhone() else {
            await removeAllPending()
            return
        }
        guard await center.canDeliver() else {
            await removeAllPending()
            return
        }

        let now = clock()
        var log = loadLog()
        // Delivered (fire time passed): keep two days for the per-day budget and to avoid
        // announcing the same event twice; drop the rest.
        let horizon = now.addingTimeInterval(-3 * 86_400)
        log = log.filter { $0.value > horizon }
        let delivered = log.filter { $0.value <= now }

        let chosen = plan(suggestions, delivered: delivered, now: now)
        let existing = await center.pendingRequests().filter { $0.identifier.hasPrefix(Self.identifierPrefix) }
        let existingById = Dictionary(existing.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })

        var toAdd: [UNNotificationRequest] = []
        var keep = Set<String>()
        for item in chosen {
            let request = makeRequest(item, profileId: profileId, now: now)
            if let current = existingById[request.identifier], Self.isSame(current, request) {
                keep.insert(request.identifier)
            } else {
                toAdd.append(request)
            }
        }
        let stale = existing.map(\.identifier).filter { !keep.contains($0) }
        center.removePending(identifiers: stale)

        var scheduled = delivered
        for item in chosen where keep.contains(Self.identifier(forSourceKey: item.suggestion.sourceKey)) {
            scheduled[Self.identifier(forSourceKey: item.suggestion.sourceKey)] = item.fireDate
        }
        for request in toAdd {
            do {
                try await center.add(request)
                if let fire = request.content.userInfo[Self.fireAtKey] as? TimeInterval {
                    scheduled[request.identifier] = Date(timeIntervalSince1970: fire)
                }
            } catch {
                schedulerLogger.error("Could not schedule capture notification: \(error.localizedDescription, privacy: .public)")
            }
        }
        saveLog(scheduled)
    }

    /// Which suggestions get a notification, and when. Pure apart from the calendar.
    func plan(_ suggestions: [Suggestion], delivered: [String: Date], now: Date) -> [Planned] {
        let candidates: [Planned] = suggestions.compactMap { suggestion in
            guard suggestion.kind == .calendar,
                  suggestion.isPending,
                  !suggestion.isBackfill,
                  !suggestion.mightAlreadyBeLogged,
                  suggestion.confidence >= policy.likelyThreshold,
                  let end = suggestion.end,
                  delivered[Self.identifier(forSourceKey: suggestion.sourceKey)] == nil else { return nil }
            let (fire, deferred) = fireDate(afterEventEnd: end)
            guard fire > now else { return nil }
            return Planned(suggestion: suggestion, fireDate: fire, deferred: deferred)
        }
        .sorted {
            $0.fireDate != $1.fireDate ? $0.fireDate < $1.fireDate : $0.suggestion.confidence > $1.suggestion.confidence
        }

        var perDay: [Date: Int] = [:]
        for fire in delivered.values {
            perDay[calendar.startOfDay(for: fire), default: 0] += 1
        }
        var chosen: [Planned] = []
        for item in candidates {
            guard chosen.count < policy.maxPending else { break }
            let day = calendar.startOfDay(for: item.fireDate)
            guard perDay[day, default: 0] < policy.maxPerDay else { continue }
            perDay[day, default: 0] += 1
            chosen.append(item)
        }
        return chosen
    }

    /// Event end + 5 min, moved out of quiet hours to the next 08:00.
    func fireDate(afterEventEnd end: Date) -> (Date, Bool) {
        let fire = end.addingTimeInterval(policy.delayAfterEnd)
        let hour = calendar.component(.hour, from: fire)
        let morning: (Date) -> Date = { day in
            self.calendar.date(bySettingHour: self.policy.quietEndHour, minute: 0, second: 0, of: day) ?? day
        }
        if hour >= policy.quietStartHour {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: fire)) ?? fire
            return (morning(nextDay), true)
        }
        if hour < policy.quietEndHour {
            return (morning(calendar.startOfDay(for: fire)), true)
        }
        return (fire, false)
    }

    // MARK: Content

    func makeRequest(_ item: Planned, profileId: String, now: Date) -> UNNotificationRequest {
        let suggestion = item.suggestion
        let content = UNMutableNotificationContent()
        let text = self.content(for: suggestion, fireDate: item.fireDate, deferred: item.deferred)
        content.title = text.title
        content.body = text.body
        content.categoryIdentifier = CaptureNotificationAction.categoryIdentifier
        content.threadIdentifier = Self.threadIdentifier
        var info = CaptureNotificationAction.userInfo(profileId: profileId, sourceKey: suggestion.sourceKey)
        info[Self.fireAtKey] = item.fireDate.timeIntervalSince1970
        // The zone the quiet hours and copy were computed in; a change forces a rebuild.
        info[Self.timeZoneKey] = calendar.timeZone.identifier
        content.userInfo = info
        content.interruptionLevel = .active

        // Absolute time, never wall-clock components: after a time-zone or DST change a
        // calendar trigger would fire at the same local time, possibly before the event ends.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, item.fireDate.timeIntervalSince(now)), repeats: false)
        return UNNotificationRequest(identifier: Self.identifier(forSourceKey: suggestion.sourceKey), content: content, trigger: trigger)
    }

    /// Title "Plumber visit just ended", body "Log 2h at Pine Cabin?" (NotificationCopy).
    func content(for suggestion: Suggestion, fireDate: Date, deferred: Bool) -> NotificationText {
        let timing: NotificationCopy.Timing
        if !deferred {
            timing = .justEnded
        } else if let end = suggestion.end, calendar.isDate(end, inSameDayAs: fireDate) {
            timing = .earlierToday
        } else {
            timing = .yesterday
        }
        let name = suggestion.proposedPropertyId.flatMap { propertyNames()[$0] }
        return NotificationCopy.endOfVisit(eventTitle: suggestion.title, timing: timing, hours: suggestion.proposedHours, propertyName: name)
    }

    nonisolated static func shortTitle(_ raw: String) -> String { NotificationCopy.shortTitle(raw) }

    /// 2 → "2h", 1.5 → "1.5h", 1.25 → "1.25h", 0.75 → "45 min".
    nonisolated static func hoursText(_ hours: Double) -> String { NotificationCopy.hoursText(hours) }

    private static func isSame(_ a: UNNotificationRequest, _ b: UNNotificationRequest) -> Bool {
        a.content.title == b.content.title
            && a.content.body == b.content.body
            && (a.content.userInfo[fireAtKey] as? TimeInterval) == (b.content.userInfo[fireAtKey] as? TimeInterval)
            && (a.content.userInfo[timeZoneKey] as? String) == (b.content.userInfo[timeZoneKey] as? String)
            && (a.content.userInfo[NotificationPayload.profileIdKey] as? String) == (b.content.userInfo[NotificationPayload.profileIdKey] as? String)
    }

    // MARK: Log (identifier → fire date)

    private func loadLog() -> [String: Date] {
        guard let raw = defaults.dictionary(forKey: Self.logKey) as? [String: Double] else { return [:] }
        return raw.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private func saveLog(_ log: [String: Date]) {
        defaults.set(log.mapValues(\.timeIntervalSince1970), forKey: Self.logKey)
    }
}
