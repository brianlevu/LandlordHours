import Foundation
import UserNotifications

struct EngagementNotificationPlan: Equatable {
    let identifier: String
    let title: String
    let body: String
    let reason: EngagementReason
    let destination: EngagementDestination
    let cooldownDays: Int
    let delay: TimeInterval
    let playsSound: Bool
}

final class EngagementNotificationScheduler {
    static let shared = EngagementNotificationScheduler()
    /// Reasons that never become a notification any more.
    static let retiredReasons: Set<EngagementReason> = [.calendarDraftsReady]

    private let center: UNUserNotificationCenter
    private let service: EngagementIntelligenceService
    private let defaults: UserDefaults

    init(
        center: UNUserNotificationCenter = .current(),
        service: EngagementIntelligenceService = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.center = center
        self.service = service
        self.defaults = defaults
    }

    func plan(for context: EngagementContext, respectingCooldown: Bool = false) -> EngagementNotificationPlan? {
        guard context.notificationPermission != .denied else { return nil }

        let recommendation = service.recommendation(for: context)
        guard recommendation.surface == .notification else { return nil }
        // Retired in 2.0: calendar items are announced one by one at event end
        // (EndOfEventScheduler); a "N calendar items" digest on top would double-notify.
        guard !Self.retiredReasons.contains(recommendation.reason) else { return nil }
        guard recommendation.destination != .none else { return nil }

        let plan = EngagementNotificationPlan(
            identifier: "engagement.\(recommendation.reason.rawValue)",
            title: recommendation.title,
            body: recommendation.message,
            reason: recommendation.reason,
            destination: recommendation.destination,
            cooldownDays: recommendation.cooldownDays,
            delay: delay(for: recommendation.reason),
            playsSound: playsSound(for: recommendation.reason)
        )

        if respectingCooldown && isWithinCooldown(plan, now: context.now) {
            return nil
        }

        return plan
    }

    func scheduleIfUseful(for context: EngagementContext) async {
        guard let plan = plan(for: context, respectingCooldown: true) else { return }

        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = plan.playsSound ? .default : nil
        content.threadIdentifier = "landlordhours.engagement"
        content.categoryIdentifier = categoryIdentifier(for: plan.destination)
        var userInfo: [String: Any] = [
            "reason": plan.reason.rawValue,
            NotificationPayload.destinationKey: plan.destination.rawValue
        ]
        // Every notification carries the profile it was made for (see NotificationPayload).
        if let profileId = UserScope.userId {
            userInfo[NotificationPayload.profileIdKey] = profileId
        }
        content.userInfo = userInfo

        if #available(iOS 15.0, *) {
            content.interruptionLevel = interruptionLevel(for: plan.reason)
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: plan.delay, repeats: false)
        let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)

        center.removePendingNotificationRequests(withIdentifiers: [plan.identifier])
        do {
            try await center.add(request)
            markScheduled(plan, at: context.now)
        } catch {
            return
        }
    }

    func markScheduled(_ plan: EngagementNotificationPlan, at date: Date) {
        defaults.set(date, forKey: lastScheduledKey(for: plan))
    }

    private func isWithinCooldown(_ plan: EngagementNotificationPlan, now: Date) -> Bool {
        guard plan.cooldownDays > 0,
              let lastScheduledAt = defaults.object(forKey: lastScheduledKey(for: plan)) as? Date else {
            return false
        }
        let cooldown = TimeInterval(plan.cooldownDays * 24 * 60 * 60)
        return now.timeIntervalSince(lastScheduledAt) < cooldown
    }

    private func lastScheduledKey(for plan: EngagementNotificationPlan) -> String {
        UserScope.key("LandlordHours.notification.lastScheduled.\(plan.reason.rawValue)")
    }

    private func delay(for reason: EngagementReason) -> TimeInterval {
        switch reason {
        case .calendarDraftsReady, .yearEndExport:
            return 60
        case .inactiveLogging:
            return 60 * 60
        default:
            return 60 * 30
        }
    }

    private func playsSound(for reason: EngagementReason) -> Bool {
        reason == .timerSafety
    }

    private func categoryIdentifier(for destination: EngagementDestination) -> String {
        switch destination {
        case .track: return "LANDLORDHOURS_TRACK"
        case .calendarReview: return "LANDLORDHOURS_REVIEW_CALENDAR"
        case .export: return "LANDLORDHOURS_EXPORT"
        case .reports: return "LANDLORDHOURS_REPORTS"
        case .addProperty: return "LANDLORDHOURS_ADD_PROPERTY"
        case .timerReview: return "LANDLORDHOURS_TIMER"
        case .none: return "LANDLORDHOURS_OPEN"
        }
    }

    @available(iOS 15.0, *)
    private func interruptionLevel(for reason: EngagementReason) -> UNNotificationInterruptionLevel {
        switch reason {
        case .timerSafety:
            return .timeSensitive
        default:
            return .active
        }
    }
}

// MARK: - Pace and care nudges (2.3 package D)
//
// The opt-in notifications from Settings › Pace reminders. The rules are `NudgePolicy` (pure); this
// part hands the result to the system. Every request id starts with `nudge.`, so a rebuild can
// find and replace exactly its own requests and never touches the end-of-visit capture
// notifications or the day-12 billing reminder (which are not nudges and ignore these switches).

enum NudgeNotification {
    static let category = "LANDLORDHOURS_NUDGE"
    static let kindKey = "nudgeKind"
    static let rentalIDKey = "nudgeRentalID"
    static let paceThread = "landlordhours.nudge.pace"
    static let careThread = "landlordhours.nudge.care"
    /// Today reads this once on opening: the rental a care nudge was about. Package E's focus
    /// route consumes it; until then the tap opens Today.
    static let pendingRentalKey = "LandlordHours.nudge.pendingRentalID"
}

@MainActor
final class NudgeScheduler {
    static let shared = NudgeScheduler()

    typealias FactsProvider = @MainActor (_ now: Date, _ calendar: Calendar) -> NudgeFacts?

    private let center: CaptureNotificationCenter
    private let store: NudgeSettingsStore
    private let now: () -> Date
    private let calendar: () -> Calendar
    private let facts: FactsProvider
    private let profileID: () -> String?
    private var tail: Task<Void, Never>?

    init(
        center: CaptureNotificationCenter = SystemCaptureNotificationCenter(),
        store: NudgeSettingsStore = NudgeSettingsStore(),
        now: @escaping () -> Date = { Date() },
        calendar: @escaping () -> Calendar = { Calendar.current },
        facts: @escaping FactsProvider = NudgeScheduler.liveFacts,
        profileID: @escaping () -> String? = { UserScope.userId }
    ) {
        self.center = center
        self.store = store
        self.now = now
        self.calendar = calendar
        self.facts = facts
        self.profileID = profileID
    }

    /// Remakes every pending nudge from the current settings and data. Safe to call from several
    /// places at once: runs are queued, and request ids are stable, so a nudge is never doubled.
    func rebuild(reason: String) async {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await self.performRebuild(reason: reason)
        }
        tail = task
        await task.value
    }

    private func performRebuild(reason: String) async {
        let settings = store.load()
        let pending = await center.pendingRequests().filter { $0.identifier.hasPrefix(NudgePolicy.idPrefix) }
        let pendingIDs = Set(pending.map(\.identifier))
        let moment = now()
        let cal = calendar()

        func clearAll() {
            center.removePending(identifiers: Array(pendingIDs))
            // Plans that never went out must not count as sent later.
            store.saveLedger(store.loadLedger().filter { $0.fireDate <= moment })
        }

        // Off until opted in, and off again the moment the last switch goes off.
        guard settings.anyKindOn else { clearAll(); return }
        // No permission, no profile or no data: nothing is scheduled.
        guard await center.canDeliver(), let facts = facts(moment, cal), let profile = profileID() else { clearAll(); return }

        let output = NudgePolicy.plan(settings: settings, facts: facts, ledger: store.loadLedger())
        center.removePending(identifiers: Array(pendingIDs))
        var added: [NudgePlan] = []
        for plan in output.plans {
            do {
                try await center.add(Self.request(for: plan, profileID: profile, calendar: cal))
                added.append(plan)
            } catch {
                continue
            }
        }
        // Only what the system accepted counts toward the daily and monthly caps.
        let addedKeys = Set(added.map { "\($0.kind.rawValue)|\($0.itemID)|\($0.fireDate.timeIntervalSince1970)" })
        let kept = output.ledger.filter { entry in
            entry.fireDate <= moment || addedKeys.contains("\(entry.kind.rawValue)|\(entry.itemID)|\(entry.fireDate.timeIntervalSince1970)")
        }
        store.saveLedger(kept)
        for plan in added where !pendingIDs.contains(plan.id) {
            Analytics.capture("nudge_scheduled", properties: ["kind": plan.kind.rawValue])
        }
    }

    static func request(for plan: NudgePlan, profileID: String?, calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = nil
        content.threadIdentifier = plan.kind.isCare ? NudgeNotification.careThread : NudgeNotification.paceThread
        content.categoryIdentifier = NudgeNotification.category
        var info: [String: Any] = [
            NudgeNotification.kindKey: plan.kind.rawValue,
            NotificationPayload.destinationKey: LandlordHoursIntentDestination.home.rawValue
        ]
        if let profileID { info[NotificationPayload.profileIdKey] = profileID }
        if let rental = plan.rentalID { info[NudgeNotification.rentalIDKey] = rental.uuidString }
        content.userInfo = info
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger)
    }

    /// The facts about the current profile's data, read from the single model.
    static func liveFacts(now: Date, calendar: Calendar) -> NudgeFacts? {
        guard UserScope.userId != nil else { return nil }
        let viewModel = AppModelHost.shared.viewModel
        let context = viewModel.engagementContext(now: now)
        let snapshot = EngagementIntelligenceService.shared.snapshot(for: context, calendar: calendar)
        let rentals = viewModel.properties.map { NudgeRental(id: $0.id, name: $0.name) }
        let care = viewModel.properties.flatMap { CareDue.source.dueItems(for: $0.id, on: now) }
        var yearHours = snapshot.yearHours
        #if DEBUG
        // QA: pin the year's hours so a lifecycle test can put the pace within reach (or not).
        if UserDefaults.standard.object(forKey: "LHNudgeYearHours") != nil {
            yearHours = UserDefaults.standard.double(forKey: "LHNudgeYearHours")
        }
        #endif
        return NudgeFacts(
            now: now, calendar: calendar, rentals: rentals,
            yearHours: yearHours, targetHours: context.targetHours,
            careItems: care,
            carePlanUnlocked: EntitlementStore.shared.plan.allows(.carePlan)
        )
    }

    /// A switch went off: say which kind (never what the person logged).
    static func recordDisabled(_ kind: NudgeKind) {
        Analytics.capture("nudge_disabled", properties: ["kind": kind.rawValue])
    }

    /// A nudge was tapped.
    static func recordOpened(_ kind: NudgeKind) {
        Analytics.capture("nudge_opened", properties: ["kind": kind.rawValue])
    }

    /// Settings can be read without a scheduler (the row summary).
    static func currentSettings() -> NudgeSettings { NudgeSettingsStore().load() }
}

#if DEBUG
// MARK: Lifecycle probes (DEBUG only)
//
// Release QA asserts the real pending requests, not screenshots. `-LHNudgeProbe` makes the
// Pace reminders screen print them (id, fire time, title, body, thread), and the seeds below let a
// test set quiet hours or a care item without tapping.
//   -LHNudgeQuietStart 16 -LHNudgeQuietEnd 9   quiet hours, applied once at launch
//   -LHNudgeCareStub 1                         one care item due for every rental
//   -LHNudgeSeed weekly,behind,yearEnd,care    turn those kinds on at launch
//   -LHNudgeReset 1                            clear the choices and the send history first
//   -LHNudgeYearHours 600                     pin the year's hours the nudges and the preview read
//   -LHNudgeFireSamples 1                      post the two example notifications (frame n2) a few seconds apart
enum NudgeDebug {
    static var probeOn: Bool { ProcessInfo.processInfo.arguments.contains("-LHNudgeProbe") }

    static func applyLaunchSeeds(store: NudgeSettingsStore = NudgeSettingsStore()) {
        let defaults = UserDefaults.standard
        var settings = store.load()
        var changed = false
        if defaults.bool(forKey: "LHNudgeReset") {
            settings = .default
            store.saveLedger([])
            changed = true
        }
        if defaults.object(forKey: "LHNudgeQuietStart") != nil, defaults.object(forKey: "LHNudgeQuietEnd") != nil {
            settings.quietStartHour = defaults.integer(forKey: "LHNudgeQuietStart")
            settings.quietEndHour = defaults.integer(forKey: "LHNudgeQuietEnd")
            changed = true
        }
        if let seed = defaults.string(forKey: "LHNudgeSeed") {
            for part in seed.split(separator: ",") {
                switch part {
                case "weekly": settings.weeklyPace = true
                case "behind": settings.behindPace = true
                case "yearEnd": settings.yearEnd = true
                case "care": settings.carePlan = true
                default: break
                }
            }
            changed = true
        }
        if changed { store.save(settings) }
        if defaults.bool(forKey: "LHNudgeCareStub") { CareDue.source = StubCareDueSource() }
    }

    /// The two example notifications of frame n2, posted as two separate requests: a weekly pace
    /// note, then a care note. For Release QA and the lock-screen capture only.
    static func postSamples(center: UNUserNotificationCenter = .current()) async {
        let delay = max(3, UserDefaults.standard.double(forKey: "LHDebugNotificationDelay"))
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let notes: [(NotificationText, String, TimeInterval)] = [
            (NudgeCopy.weekly(hours: 420, target: 750, perWeek: 38), NudgeNotification.paceThread, delay),
            (NudgeCopy.care(rental: "Pine Cabin", item: "Clear the gutters"), NudgeNotification.careThread, delay + 3)
        ]
        // Start clean: earlier runs must not stack behind the two samples.
        center.removeDeliveredNotifications(withIdentifiers: ["debug.nudge.sample.weeklyPace", "debug.nudge.sample.carePlan"])
        // Built by the real request builder, so the sample is what the scheduler would send.
        for (index, note) in notes.enumerated() {
            let kind: NudgeKind = index == 0 ? .weeklyPace : .carePlan
            let plan = NudgePlan(id: "debug.nudge.sample.\(kind.rawValue)", kind: kind,
                                 fireDate: Date().addingTimeInterval(note.2), title: note.0.title, body: note.0.body,
                                 rentalID: nil, itemID: "debug")
            try? await center.add(NudgeScheduler.request(for: plan, profileID: UserScope.userId, calendar: .current))
        }
    }

    /// Every pending nudge as one line: `id | 2026-11-08 18:00 | title | body | thread`.
    static func pendingLines(center: UNUserNotificationCenter = .current()) async -> [String] {
        let requests = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(NudgePolicy.idPrefix) }
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd HH:mm"
        return requests.compactMap { request -> (Date, String)? in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger, let fire = trigger.nextTriggerDate() else { return nil }
            let line = [request.identifier, format.string(from: fire), request.content.title, request.content.body, request.content.threadIdentifier]
                .joined(separator: " | ")
            return (fire, line)
        }
        .sorted { $0.0 < $1.0 }
        .map(\.1)
    }

    struct StubCareDueSource: CareDueSource {
        func dueItems(for rentalID: UUID, on date: Date) -> [CareDueItem] {
            [CareDueItem(id: "gutters", rentalID: rentalID, title: "Clear the gutters", due: date.addingTimeInterval(-86_400))]
        }
    }
}
#endif
