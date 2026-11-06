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
