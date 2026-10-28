import Foundation

// MARK: - Calendar event signals (2.2 Inbox fix)
//
// What a calendar event says besides its title, and how that moves the "is this rental work?"
// score. A match on the event's LOCATION alone is weak evidence (a sync at a rental's street,
// a haircut in the same town), so it is capped at "Not sure" and hidden when anything points
// away from rental work. Weights are from the 2026-10-27 diagnosis.
//
// Pure: no EventKit, no I/O. The detector fills `CalendarContext`; `RulesClassifier` calls this
// for calendar items.

enum CalendarEventSignals {
    /// Score ceiling for an item whose only landlord evidence is its location. Under the
    /// "likely" line (1.5 maps to a confidence of 0.50) and at the "Not sure" minimum.
    static let locationOnlyMaxScore = RulesEngine.notSureMinScore

    // Weights tuned 2026-10-27 on 980 synthetic Jev-labelled events (inbox-tune/weights.json).
    /// 0: tenant and guest calls happen on Zoom; at -3 the link cost about 7 points of recall
    /// for no gain in precision. A zero-weight signal is not a negative signal.
    static let videoLinkPenalty = 0.0
    static let manyAttendeesPenalty = -1.0
    static let recurringWithAttendeesPenalty = -1.5
    static let organizedByOtherOnWorkCalendarPenalty = -2.0
    static let remoteLocationPenalty = -3.0
    static let personalServicePenalty = -3.0

    /// People on the invite, the owner included, at which a meeting is a team's, not a landlord's.
    static let manyAttendees = 3

    struct Penalty: Equatable {
        var reason: String
        var score: Double
    }

    /// Hosts and phrases of video meetings. Matched in the URL, the location and the notes.
    static let videoHosts = [
        "zoom.us", "zoom.com", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com",
    ]
    /// The same services named in words ("Zoom", "Google Meet"), matched on the location.
    static let videoNames = ["zoom", "google meet", "microsoft teams", "ms teams", "teams meeting", "webex", "webex meeting", "zoom meeting"]

    static let remoteWords = ["remote", "virtual", "online", "telehealth", "telemedicine"]

    /// Salons, clinics and other personal appointments. Matched on the title and the location
    /// (not the notes: "hair" in a tenant's note is not a haircut).
    static let personalServiceWords: [(phrase: String, wholeWord: Bool)] = [
        ("salon", false), ("barber", false), ("haircut", false), ("hair", false), ("stylist", false),
        ("nails", true), ("manicure", false), ("pedicure", false), ("spa", true), ("massage", false),
        ("clinic", false), ("medical", false), ("doctor", false), ("dentist", false), ("dental", false),
        ("orthodont", false), ("therapy", false), ("therapist", false), ("checkup", false), ("check up", false),
        ("optometr", false), ("chiropract", false), ("physio", false), ("telehealth", false), ("telemedicine", false),
    ]

    /// Every "not rental work" signal on the event.
    static func penalties(title: String, location: String?, context: CalendarContext) -> [Penalty] {
        var out: [Penalty] = []
        if hasVideoLink(location: location, context: context) {
            out.append(Penalty(reason: "video meeting link", score: videoLinkPenalty))
        }
        if context.attendeeCount >= manyAttendees {
            out.append(Penalty(reason: "\(context.attendeeCount) attendees", score: manyAttendeesPenalty))
        }
        if context.isRecurring && context.attendeeCount >= 2 {
            out.append(Penalty(reason: "repeating event with attendees", score: recurringWithAttendeesPenalty))
        }
        if context.organizedByOther && context.isWorkCalendar {
            out.append(Penalty(reason: "organized by someone else on a work calendar", score: organizedByOtherOnWorkCalendarPenalty))
        }
        if let location, mentions(remoteWords.map { ($0, true) }, in: location) {
            out.append(Penalty(reason: "remote location", score: remoteLocationPenalty))
        }
        let place = [title, location ?? ""].joined(separator: " ")
        if mentions(personalServiceWords.map { ($0.phrase, $0.wholeWord) }, in: place) {
            out.append(Penalty(reason: "personal appointment words", score: personalServicePenalty))
        }
        return out.filter { $0.score != 0 }
    }

    static func hasVideoLink(location: String?, context: CalendarContext) -> Bool {
        let raw = [context.url, location, context.notes].compactMap { $0 }.joined(separator: " ").lowercased()
        if videoHosts.contains(where: { raw.contains($0) }) { return true }
        if let location, mentions(videoNames.map { ($0, true) }, in: location) { return true }
        return false
    }

    /// Word-prefix (or whole-word) match of any phrase in normalized text.
    private static func mentions(_ phrases: [(String, Bool)], in text: String) -> Bool {
        let padded = " \(RulesEngine.normalize(text)) "
        return phrases.contains { phrase, wholeWord in
            padded.contains(" " + phrase + (wholeWord ? " " : ""))
        }
    }
}

extension RulesEngine {
    /// A calendar event: title and location scored apart, plus what the invite says.
    ///
    /// - A property found only in the LOCATION (nothing in the title names the property or a
    ///   landlord word) is capped at "Not sure" (`locationOnlyMaxScore`), and hidden when any
    ///   negative signal sits beside it: a negative keyword or an event signal.
    /// - Event signals (`CalendarEventSignals`) lower the score of every event. If they leave
    ///   nothing, the item is hidden for good (the on-device model cannot bring it back); a
    ///   landlord word in the title still keeps it at "Not sure".
    static func evaluateCalendar(
        title: String,
        location: String?,
        context: CalendarContext,
        properties: [RentalProperty]
    ) -> RulesVerdict {
        let joined = [title, location ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        var verdict = evaluate(text: joined, properties: properties)
        let titleOnly = evaluate(text: title, properties: properties)
        let penalties = CalendarEventSignals.penalties(title: title, location: location, context: context)
        let penalty = penalties.reduce(0.0) { $0 + $1.score }
        let eventEvidence = penalties.map { "not rental: \($0.reason)" }
        let hasNegativeKeyword = verdict.evidence.contains { $0.hasPrefix("not landlord:") }

        let propertyCounted = verdict.evidence.contains { $0.hasPrefix("property:") }
        let titleHasLandlordWord = titleOnly.evidence.contains { $0.hasPrefix("keyword:") }
        let titleNamesProperty = titleOnly.evidence.contains { $0.hasPrefix("property:") }
        let locationOnly = propertyCounted && !titleHasLandlordWord && !titleNamesProperty

        verdict.evidence.append(contentsOf: eventEvidence)
        let hasNegative = hasNegativeKeyword || !penalties.isEmpty

        if locationOnly {
            if hasNegative {
                return hidden(verdict, score: min(verdict.score + penalty, 0), note: "location only, with a not-rental signal")
            }
            let capped = min(verdict.score, CalendarEventSignals.locationOnlyMaxScore)
            verdict.score = capped
            verdict.confidence = confidence(forScore: capped)
            verdict.evidence.append(ClassifierThresholds.locationOnlyEvidence)
            // A counted property match always leaves landlord evidence (never hidden).
            verdict.hasLandlordSignal = capped > 0
            return verdict
        }

        guard penalty < 0 else { return verdict }
        let before = verdict
        verdict.score += penalty
        verdict.confidence = confidence(forScore: verdict.score)
        let stillSignal = before.hasLandlordSignal && verdict.score > 0
            && (verdict.score >= notSureMinScore || propertyCounted)
        // A landlord word in the title ("Tenant call") keeps the item visible as "Not sure" even
        // when the event signals outweigh it: the title is stronger than the invite.
        let titleCarries = titleOnly.hasLandlordSignal && titleOnly.score >= notSureMinScore
        verdict.hasLandlordSignal = stillSignal || titleCarries
        if !verdict.hasLandlordSignal {
            return hidden(verdict, score: verdict.score, note: "event signals outweigh the match")
        }
        return verdict
    }

    private static func hidden(_ verdict: RulesVerdict, score: Double, note: String) -> RulesVerdict {
        var out = verdict
        out.score = score
        out.confidence = confidence(forScore: score)
        out.hasLandlordSignal = false
        out.evidence.append(ClassifierThresholds.notRentalEvidence)
        out.evidence.append("hidden: \(note)")
        return out
    }
}
