import Foundation
import UserNotifications

// MARK: - Notification copy (2.0 surfaces lane)
//
// Every notification LandlordHours sends, as a title and a short body. Source: the surfaces copy
// sheet (2026-10-19). Rules: plain words; "rental work"; no 1.x tab names; never "evidence" or
// "qualify"; nothing implies we log without the user tapping Log it. The event, as the person
// wrote it in their calendar, is the title; the body is one plain question or sentence.
// Scheduling, quiet hours and caps live elsewhere and are unchanged.

struct NotificationText: Equatable {
    var title: String
    var body: String
}

enum NotificationCopy {
    enum Timing: Equatable {
        case justEnded, earlierToday, yesterday

        var words: String {
            switch self {
            case .justEnded: return "just ended"
            case .earlierToday: return "ended earlier today"
            case .yesterday: return "ended yesterday"
            }
        }
    }

    /// The three actions on the end-of-visit prompt, in order.
    enum Action: CaseIterable {
        case logIt, edit, notRentalWork

        var title: String {
            switch self {
            case .logIt: return "Log it"
            case .edit: return "Edit…"
            case .notRentalWork: return "Not rental work"
            }
        }

        var symbol: String {
            switch self {
            case .logIt: return "checkmark.circle"
            case .edit: return "pencil"
            case .notRentalWork: return "xmark.circle"
            }
        }

        var icon: UNNotificationActionIcon { UNNotificationActionIcon(systemImageName: symbol) }
    }

    /// "Plumber visit just ended" / "Log 2h at Pine Cabin?"
    static func endOfVisit(eventTitle: String, timing: Timing, hours: Double?, propertyName: String?) -> NotificationText {
        var ask = "Log it?"
        if let hours, hours > 0 {
            ask = "Log \(hoursText(hours))"
            if let propertyName, !propertyName.isEmpty { ask += " at \(propertyName)" }
            ask += "?"
        }
        return NotificationText(title: "\(shortTitle(eventTitle)) \(timing.words)", body: ask)
    }

    /// One short follow-up after a lock-screen action couldn't finish.
    static func followUp(_ followUp: CaptureFollowUp, eventTitle: String) -> NotificationText {
        let body: String
        switch followUp {
        case .mightAlreadyBeLogged: body = "This might already be in your records. Tap to check before saving."
        case .eventMoved: body = "This moved on your calendar. Tap to check the time before saving."
        case .eventGone: body = "This is gone from your calendar, so nothing was logged."
        case .cannotVerify: body = "We couldn’t check this on your calendar. Tap to log it yourself."
        case .needsInput: body = "This needs a property or hours. Tap to finish it."
        case .offerMute: body = "Got it, that’s not rental work. Stop suggesting events like this one?"
        case .queuedTooLong: body = "Not logged yet, because iCloud didn’t finish syncing. Tap to check it."
        }
        return NotificationText(title: shortTitle(eventTitle), body: body)
    }

    /// Engagement: nothing logged for a while.
    static func inactive(days: Int) -> NotificationText {
        NotificationText(
            title: "Anything for your rentals lately?",
            body: "Nothing logged in \(days) days. Add what you did while you still remember it."
        )
    }

    /// Engagement: November–December, make the PDF. Whole hours.
    static func yearEnd(hours: Double, year: Int) -> NotificationText {
        NotificationText(
            title: "Tax time is coming",
            body: "You have \(Int(max(0, hours).rounded(.down)))h logged for \(String(year)). You can make the PDF for your CPA any time."
        )
    }

    // MARK: Helpers

    static func shortTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "Your event" : trimmed
        guard title.count > 60 else { return title }
        return String(title.prefix(59)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// 2 → "2h", 1.5 → "1.5h", 1.25 → "1.25h", 0.75 → "45 min".
    static func hoursText(_ hours: Double) -> String {
        if hours < 1 {
            return "\(max(1, Int((hours * 60).rounded()))) min"
        }
        let rounded = (hours * 100).rounded() / 100
        if rounded == rounded.rounded() { return "\(Int(rounded))h" }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        return text + "h"
    }
}

// MARK: - Pace and care nudges (2.3 package D)
//
// Settings › Pace reminders. The facts come first, then the number. No streaks, no guilt, no
// "evidence" or "qualify". Pace is about hours; care is about upkeep and never mentions hours.
// All strings live in `Sources/Resources/Strings/Nudges.xcstrings` (table "Nudges").

enum NudgeStrings {
    static let table = "Nudges"

    static func t(_ key: StaticString, _ value: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: value, table: table)
    }

    static func f(_ key: StaticString, _ format: String.LocalizationValue, _ args: CVarArg...) -> String {
        String(format: String(localized: key, defaultValue: format, table: table), arguments: args)
    }
}

enum NudgeCopy {
    /// "Your week" / "420 of 750 this year. About 38h a week gets you to 750 by Dec 31."
    static func weekly(hours: Int, target: Int, perWeek: Int) -> NotificationText {
        let title = NudgeStrings.t("nudge.weekly.title", "Your week")
        if perWeek <= 0 {
            return NotificationText(title: title, body: NudgeStrings.f("nudge.weekly.bodyMet", "%lld of %lld this year. You’re at your goal.", hours, target))
        }
        return NotificationText(title: title, body: NudgeStrings.f(
            "nudge.weekly.body", "%lld of %lld this year. About %lldh a week gets you to %lld by Dec 31.", hours, target, perWeek, target))
    }

    /// The calm line for a goal that is out of reach at this pace. Settings preview only: no
    /// notification is ever sent with it.
    static func outOfReach(target: Int) -> NotificationText {
        NotificationText(
            title: NudgeStrings.t("nudge.weekly.title", "Your week"),
            body: NudgeStrings.f("nudge.outOfReach.body", "%lld by Dec 31 is out of reach at this pace. Keep logging what you do.", target))
    }

    /// "Your pace" / "About 24h behind the pace for 750 by Dec 31."
    static func behind(hoursBehind: Int, target: Int) -> NotificationText {
        NotificationText(
            title: NudgeStrings.t("nudge.behind.title", "Your pace"),
            body: NudgeStrings.f("nudge.behind.body", "About %lldh behind the pace for %lld by Dec 31.", hoursBehind, target))
    }

    /// "Year end" / "Your 2026 total is 612h. Add anything missing before Dec 31."
    static func yearEnd(year: Int, hours: Int) -> NotificationText {
        NotificationText(
            title: NudgeStrings.t("nudge.yearEnd.title", "Year end"),
            body: NudgeStrings.f("nudge.yearEnd.body", "Your %lld total is %lldh. Add anything missing before Dec 31.", year, hours))
    }

    /// The rental is the title; the body names the one care item. No hours.
    static func care(rental: String, item: String) -> NotificationText {
        NotificationText(title: rental, body: NudgeStrings.f("nudge.care.body", "Up next: %@.", item))
    }
}
