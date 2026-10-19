import Foundation

// MARK: - Capture opt-in (per profile)
//
// 2.0 must not start sending end-of-event notifications to people who simply updated the app.
// Everything here defaults to OFF and only an explicit choice on the "What's new" intro
// (upgraders) or the onboarding capture step (new users) turns it on.
//
// WP4 integration point: `EndOfEventScheduler` / `CaptureNotificationRefresher` schedule
// nothing unless `CaptureOptIn.eventPromptsEnabled()` (or `AppViewModel.eventPromptsEnabled`)
// is true for the active profile; when it is false they remove all pending capture requests.
enum CaptureOptIn {
    /// "Ask me when a visit ends" — end-of-event local notifications.
    static let eventPromptsBaseKey = "LandlordHours.capture.eventPromptsEnabled"
    /// "Find rental work in my calendar" — calendar suggestions in the inbox.
    static let calendarSuggestionsBaseKey = "LandlordHours.capture.calendarSuggestionsEnabled"
    /// The one-time 2.0 "What's new" intro was answered or dismissed.
    static let whatsNewSeenBaseKey = "LandlordHours.capture.whatsNew20Seen"
    /// The day-1 90-day backfill ran for this profile.
    static let backfillCompletedBaseKey = "LandlordHours.capture.backfillCompleted"

    /// Every per-profile key, for profile reset / delete.
    static let allBaseKeys = [eventPromptsBaseKey, calendarSuggestionsBaseKey, whatsNewSeenBaseKey, backfillCompletedBaseKey]

    private static func key(_ base: String, userId: String?) -> String? {
        guard let userId else { return nil }
        return UserScope.key(base, userId: userId)
    }

    private static func bool(_ base: String, userId: String?, defaults: UserDefaults) -> Bool {
        guard let key = key(base, userId: userId) else { return false }
        return defaults.bool(forKey: key)
    }

    private static func set(_ value: Bool, _ base: String, userId: String?, defaults: UserDefaults) {
        guard let key = key(base, userId: userId) else { return }
        defaults.set(value, forKey: key)
    }

    // MARK: Event prompts (the WP4 gate)

    /// True only after the user explicitly turned on "Ask me when a visit ends" for this profile.
    /// No profile → false.
    static func eventPromptsEnabled(userId: String? = UserScope.userId, defaults: UserDefaults = .standard) -> Bool {
        bool(eventPromptsBaseKey, userId: userId, defaults: defaults)
    }

    static func setEventPromptsEnabled(_ enabled: Bool, userId: String? = UserScope.userId, defaults: UserDefaults = .standard) {
        set(enabled, eventPromptsBaseKey, userId: userId, defaults: defaults)
    }

    // MARK: Calendar suggestions

    static func calendarSuggestionsEnabled(userId: String? = UserScope.userId, defaults: UserDefaults = .standard) -> Bool {
        bool(calendarSuggestionsBaseKey, userId: userId, defaults: defaults)
    }

    static func setCalendarSuggestionsEnabled(_ enabled: Bool, userId: String? = UserScope.userId, defaults: UserDefaults = .standard) {
        set(enabled, calendarSuggestionsBaseKey, userId: userId, defaults: defaults)
    }

    // MARK: Backfill

    static func backfillCompleted(userId: String? = UserScope.userId, defaults: UserDefaults = .standard) -> Bool {
        bool(backfillCompletedBaseKey, userId: userId, defaults: defaults)
    }

    static func markBackfillCompleted(userId: String? = UserScope.userId, defaults: UserDefaults = .standard) {
        set(true, backfillCompletedBaseKey, userId: userId, defaults: defaults)
    }

    // MARK: What's new (upgraders)

    static func whatsNewSeen(userId: String? = UserScope.userId, defaults: UserDefaults = .standard) -> Bool {
        bool(whatsNewSeenBaseKey, userId: userId, defaults: defaults)
    }

    static func markWhatsNewSeen(userId: String? = UserScope.userId, defaults: UserDefaults = .standard) {
        set(true, whatsNewSeenBaseKey, userId: userId, defaults: defaults)
    }

    /// The upgrader intro shows once to a profile that finished 1.x onboarding and has not
    /// answered it. New users answer the same question in onboarding, which marks it seen.
    static func shouldShowWhatsNew(
        userId: String? = UserScope.userId,
        hasCompletedOnboarding: Bool,
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        guard userId != nil, hasCompletedOnboarding else { return false }
        guard !whatsNewSeen(userId: userId, defaults: defaults) else { return false }
        // Debug / UI-test launches (any -LH… argument) stay quiet unless a test asks for it, so
        // existing journeys are not interrupted by a sheet.
        if arguments.contains(showWhatsNewArgument) { return true }
        return !arguments.contains { $0.hasPrefix("-LH") }
    }

    /// DEBUG / UI tests: force the upgrader intro on a seeded launch.
    static let showWhatsNewArgument = "-LHShowWhatsNew"

    /// Records an explicit answer from the intro or onboarding step.
    static func recordChoice(
        calendar: Bool,
        eventPrompts: Bool,
        userId: String? = UserScope.userId,
        defaults: UserDefaults = .standard
    ) {
        setCalendarSuggestionsEnabled(calendar, userId: userId, defaults: defaults)
        // End-of-event prompts need calendar events to talk about.
        setEventPromptsEnabled(calendar && eventPrompts, userId: userId, defaults: defaults)
        markWhatsNewSeen(userId: userId, defaults: defaults)
    }
}

extension AppViewModel {
    /// Whether end-of-event notifications may be scheduled for the active profile. WP4's
    /// scheduler checks this before scheduling anything.
    var eventPromptsEnabled: Bool {
        get { CaptureOptIn.eventPromptsEnabled() }
        set {
            objectWillChange.send()
            CaptureOptIn.setEventPromptsEnabled(newValue)
        }
    }

    /// Whether calendar suggestions are on for the active profile.
    var calendarSuggestionsEnabled: Bool {
        CaptureOptIn.calendarSuggestionsEnabled()
    }
}
