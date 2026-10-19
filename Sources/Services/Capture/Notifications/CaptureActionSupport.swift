import Foundation
import UIKit
import UserNotifications

// MARK: - Tap-time checks for "Log it"
//
// A notification can be hours old when it is tapped. Before "Log it" writes a tax record the
// router re-checks, in this order:
//   1. protected data is readable (else the store would look empty) → queue for later;
//   2. the profile's initial iCloud pull has finished (legacy imports may not be on device yet)
//      → queue, confirm after the pull;
//   3. the calendar event still exists at the same time → else no write;
//   4. the item doesn't now look already logged → else route to Edit.
// The seams below let tests drive each branch.

/// What the calendar says about a suggestion's event now.
enum CaptureEventCheck: Equatable {
    case unchanged
    /// Same event, different start or end.
    case moved
    /// Not on the calendar any more (deleted, canceled, or declined).
    case gone
    /// Can't tell (no calendar access). Treated as "don't write blind".
    case unverifiable
}

protocol CaptureEventChecking {
    @MainActor func check(_ suggestion: Suggestion) async -> CaptureEventCheck
}

/// Re-runs the detector over the event's day and looks for the same key.
struct CalendarCaptureEventChecker: CaptureEventChecking {
    var makeDetector: () -> CalendarDetector = { CalendarDetector(source: EventKitCalendarSource()) }
    /// Starts and ends within this of the stored values count as unchanged.
    static let tolerance: TimeInterval = 60

    @MainActor func check(_ suggestion: Suggestion) async -> CaptureEventCheck {
        guard suggestion.kind == .calendar else { return .unchanged }
        let detector = makeDetector()
        // The detector keys occurrences on their ORIGINAL start, so a moved occurrence keeps its
        // key; look a day either side so a small move is still found.
        let interval = DateInterval(
            start: suggestion.start.addingTimeInterval(-86_400),
            end: suggestion.start.addingTimeInterval(2 * 86_400)
        )
        let candidates: [CaptureCandidate]
        do {
            candidates = try await detector.detect(in: interval)
        } catch {
            return .unverifiable
        }
        return Self.compare(suggestion, with: candidates)
    }

    static func compare(_ suggestion: Suggestion, with candidates: [CaptureCandidate]) -> CaptureEventCheck {
        guard let match = candidates.first(where: { $0.sourceKey == suggestion.sourceKey }) else { return .gone }
        let startSame = abs(match.start.timeIntervalSince(suggestion.start)) <= tolerance
        let endSame: Bool
        switch (match.end, suggestion.end) {
        case let (a?, b?): endSame = abs(a.timeIntervalSince(b)) <= tolerance
        case (nil, nil): endSame = true
        default: endSame = false
        }
        return startSame && endSame ? .unchanged : .moved
    }
}

/// Whether the profile's first iCloud pull (this launch) has finished.
enum InitialPullState: Equatable {
    case completed
    /// Expected to finish soon (iCloud on, not done yet). Confirms wait for it.
    case pending
    /// No iCloud for this build or account: nothing to wait for.
    case notApplicable
}

protocol InitialPullGating {
    @MainActor func state(for profileId: String) -> InitialPullState
    /// Starts the initial sync if needed and waits up to `timeout`. True when it completed.
    @MainActor func waitForInitialPull(profileId: String, timeout: TimeInterval) async -> Bool
}

extension CloudKitSyncService: InitialPullGating {
    func state(for profileId: String) -> InitialPullState {
        if initialSyncCompletedFor == profileId { return .completed }
        if !isCloudKitAvailable { return .notApplicable }
        // Checked and iCloud is off: nothing will arrive until the user turns it on.
        if accountStatusCheckCount > 0, !accountAvailable, !isRunningInitialSync { return .notApplicable }
        return .pending
    }

    func waitForInitialPull(profileId: String, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        if !isRunningInitialSync, state(for: profileId) == .pending {
            Task { await self.start() }
        }
        while Date() < deadline {
            switch state(for: profileId) {
            case .completed: return true
            case .notApplicable: return false
            case .pending: try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        return state(for: profileId) == .completed
    }
}

// MARK: - Follow-ups
//
// A background action can't open the app. When "Log it" can't save safely, or after
// "Not landlord work", the user gets one short follow-up instead of silence.

enum CaptureFollowUp: Equatable {
    /// Might already be logged: tap to check.
    case mightAlreadyBeLogged
    /// The event moved on the calendar: tap to check the time.
    case eventMoved
    /// The event is gone from the calendar: nothing was logged.
    case eventGone
    /// Calendar can't be read now: tap to log it by hand.
    case cannotVerify
    /// Property, category or hours missing: tap to finish.
    case needsInput
    /// After "Not landlord work": offer to stop suggesting events like it.
    case offerMute

    func body(title: String) -> String {
        let name = EndOfEventScheduler.shortTitle(title)
        switch self {
        case .mightAlreadyBeLogged: return "You may have logged \(name) already. Tap to check before saving."
        case .eventMoved: return "\(name) moved on your calendar. Tap to check the time before saving."
        case .eventGone: return "\(name) is no longer on your calendar, so nothing was logged."
        case .cannotVerify: return "Couldn't check \(name) on your calendar. Tap to log it yourself."
        case .needsInput: return "\(name) needs a property or hours. Tap to finish logging it."
        case .offerMute: return "Got it. Stop suggesting events like \(name)?"
        }
    }

    var categoryIdentifier: String {
        self == .offerMute ? CaptureNotificationAction.muteOfferCategoryIdentifier : CaptureNotificationAction.reviewCategoryIdentifier
    }
}

protocol CaptureFollowUpPosting {
    @MainActor func post(_ followUp: CaptureFollowUp, for suggestion: Suggestion, profileId: String) async
}

struct SystemCaptureFollowUpPoster: CaptureFollowUpPosting {
    var center: CaptureNotificationCenter = SystemCaptureNotificationCenter()

    @MainActor func post(_ followUp: CaptureFollowUp, for suggestion: Suggestion, profileId: String) async {
        let content = UNMutableNotificationContent()
        content.body = followUp.body(title: suggestion.title)
        content.categoryIdentifier = followUp.categoryIdentifier
        content.threadIdentifier = EndOfEventScheduler.threadIdentifier
        content.userInfo = CaptureNotificationAction.userInfo(profileId: profileId, sourceKey: suggestion.sourceKey)
        content.interruptionLevel = .passive
        let request = UNNotificationRequest(
            identifier: "capture.followup.\(suggestion.sourceKey)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}

// MARK: - Deferred actions queue
//
// "Log it" taps that couldn't run yet (protected data locked, initial iCloud pull pending)
// are kept here and replayed when the pull completes or the app comes to the foreground.
// UserDefaults, small, one item per key.

struct QueuedCaptureAction: Codable, Equatable {
    enum Kind: String, Codable {
        case confirm
        case dismiss
    }

    var profileId: String
    var sourceKey: String
    var kind: Kind
    var queuedAt: Date
}

enum CaptureActionQueue {
    static let key = "LandlordHours.capture.queuedActions"
    /// Items older than this are dropped (the inbox still has the suggestion).
    static let maxAge: TimeInterval = 7 * 86_400

    static func all(defaults: UserDefaults = .standard) -> [QueuedCaptureAction] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder.captureDecoder.decode([QueuedCaptureAction].self, from: data)) ?? []
    }

    static func enqueue(_ action: QueuedCaptureAction, defaults: UserDefaults = .standard) {
        var items = all(defaults: defaults).filter { !($0.profileId == action.profileId && $0.sourceKey == action.sourceKey) }
        items.append(action)
        save(items, defaults: defaults)
    }

    static func remove(profileId: String, sourceKey: String, defaults: UserDefaults = .standard) {
        save(all(defaults: defaults).filter { !($0.profileId == profileId && $0.sourceKey == sourceKey) }, defaults: defaults)
    }

    static func prune(now: Date = Date(), defaults: UserDefaults = .standard) {
        save(all(defaults: defaults).filter { now.timeIntervalSince($0.queuedAt) < maxAge }, defaults: defaults)
    }

    static func save(_ items: [QueuedCaptureAction], defaults: UserDefaults = .standard) {
        if items.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder.captureEncoder.encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}

// MARK: - Environment

/// Everything the router's capture path depends on besides the model host.
struct CaptureActionEnvironment {
    var isProtectedDataAvailable: @MainActor () -> Bool
    var eventChecker: CaptureEventChecking
    var pullGate: (@MainActor (AppModelHost) -> InitialPullGating)
    var followUps: CaptureFollowUpPosting
    /// Cancels pending notifications for keys resolved elsewhere (nil: nothing to cancel).
    var notifier: CaptureNotifier?
    /// How long a "Log it" waits for the initial pull before queueing.
    var pullWaitTimeout: TimeInterval = 20
    var defaults: UserDefaults = .standard

    @MainActor static var live: CaptureActionEnvironment {
        CaptureActionEnvironment(
            isProtectedDataAvailable: { UIApplication.shared.isProtectedDataAvailable },
            eventChecker: CalendarCaptureEventChecker(),
            pullGate: { host in host.viewModel.syncService },
            followUps: SystemCaptureFollowUpPoster(),
            notifier: CaptureNotificationRefresher.shared.scheduler
        )
    }
}
