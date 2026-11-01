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

    /// Unambiguous personal appointments, matched as whole words or whole phrases on the title and
    /// the location (never the notes). Words that also turn up in property work (hair, spa,
    /// medical, therapy, dental, clinic, nails) are NOT here: "Hot tub spa drain", "Paint the
    /// therapy room" and "Repair hairline crack" are rental work.
    static let personalServicePhrases = [
        "haircut", "hair cut", "barber", "barbershop", "salon", "hair salon", "hair stylist", "stylist",
        "dentist", "dental appointment", "dental cleaning", "orthodontist", "doctor", "doctor s appointment",
        "medical appointment", "urgent care", "telehealth", "telemedicine", "therapy session", "physical therapy",
        "physio", "physiotherapy", "massage", "manicure", "pedicure", "chiropractor", "optometrist",
        "checkup", "check up",
    ]

    /// Words of a work meeting. With attendees or a repeat they say "someone's team meeting".
    static let meetingWords = ["meeting", "weekly", "planning", "huddle", "kickoff", "agenda", "briefing"]

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
        if mentions(personalServicePhrases.map { ($0, true) }, in: place) {
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

    static func titleHasMeetingWord(_ title: String) -> Bool {
        mentions(meetingWords.map { ($0, true) }, in: title)
    }

    /// Reasons that count even without a landlord word to weigh them against: a personal
    /// appointment, a remote place or a work calendar's organizer. Attendees and repeats alone
    /// do not (a showing has attendees too).
    static func isStrong(_ penalty: Penalty) -> Bool {
        !(penalty.reason.hasSuffix("attendees") || penalty.reason.hasPrefix("repeating"))
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
    /// The landlord words in a title and whether anything in it argues against them.
    struct TitleKeywords: Equatable {
        /// Strongest table weight among the words that are not the bare verb "rent"/"rents".
        var strong = 0.0
        /// Strongest weight among all of them, the bare verb included.
        var any = 0.0
        /// The title also carries a `not landlord:` table hit (wedding, car, tux, ...).
        var hasNotLandlord = false

        /// The title vouches for rental work. A word other than the bare verb always does ("rental",
        /// "rent collection", "hoa", "paint"). The bare verb does only with nothing against it:
        /// "Rent review" yes, "Rent a car" and "Rent tuxedo for wedding" no.
        var vouches: Bool { strong > 0 || (any > 0 && !hasNotLandlord) }
        /// The title carries the event on its own (2.3 F, D2): the same as `vouches`, at a word of
        /// weight 1.0 or more. "Deck", "check in", "window", "install" (0.4–0.6) vouch but never carry:
        /// they lost to the invite in 21 of the 42 office look-alikes (inbox-noise report §1).
        var carries: Bool { strong >= RulesEngine.carryingTitleKeyword || (any >= RulesEngine.carryingTitleKeyword && !hasNotLandlord) }
        /// Strong enough to outweigh the table's noise words ("Lease signing - Dr Patel dental practice").
        var isStrong: Bool { strong >= RulesEngine.strongTitleKeyword }
    }

    static let bareRentVerb: Set<String> = ["rent", "rents"]

    static func titleKeywords(_ title: String) -> TitleKeywords {
        keywords(in: evaluate(text: title, properties: []).evidence)
    }

    private static func keywords(in evidence: [String]) -> TitleKeywords {
        let notLandlord = evidence.filter { $0.hasPrefix("not landlord:") }.map { String($0.dropFirst("not landlord: ".count)) }
        // "Rental car", "car rental": the rental word names a vehicle, not a property.
        let vehicle = notLandlord.contains("rental car") || notLandlord.contains("car rental")
        var out = TitleKeywords(hasNotLandlord: !notLandlord.isEmpty)
        for line in evidence where line.hasPrefix("keyword: ") {
            let phrase = String(line.dropFirst("keyword: ".count))
            if vehicle && phrase.hasPrefix("rent") { continue }
            guard let weight = ClassifierKeywords.signals.first(where: { $0.phrase == phrase })?.landlord else { continue }
            out.any = max(out.any, weight)
            if !bareRentVerb.contains(phrase) { out.strong = max(out.strong, weight) }
        }
        return out
    }

    /// True when a landlord word of weight 1.0 or more in the title carries the event (2.3 F, D2).
    /// One answer for the live scan, the backfill and both cleanups.
    static func titleHasLandlordKeyword(_ title: String) -> Bool { titleKeywords(title).carries }

    /// A title word at least this heavy keeps an event visible against the invite, and brings a
    /// skipped event back as "Not sure" (`CalendarVisibility`). Was any word (> 0) in 2.2.
    static let carryingTitleKeyword = 1.0

    /// A strong landlord word: the table weight is at least this.
    static let strongTitleKeyword = 2.0

    /// A calendar event: title and location scored apart, plus what the invite says.
    ///
    /// - Evidence found only in the LOCATION (a property or a landlord word, with nothing in the
    ///   title) is capped at "Not sure" (`locationOnlyMaxScore`). It is hidden only beside a
    ///   strong "not rental" reason: a negative keyword, a personal appointment, a remote place, a
    ///   work calendar's organizer, or attendees/repeat on a meeting-worded title. Attendees or a
    ///   repeat alone never hide it (a showing has attendees).
    /// - A landlord word in the TITLE is never pushed to hidden by the event signals: at worst
    ///   "Not sure". A strong one (weight 2.0+, "lease", "tenant", "showing") also outweighs the
    ///   keyword table's noise words ("Lease signing - Dr Patel dental practice").
    /// - Hidden items carry `notRentalEvidence`, so the on-device model cannot bring them back.
    static func evaluateCalendar(
        title: String,
        location: String?,
        context: CalendarContext,
        properties: [RentalProperty]
    ) -> RulesVerdict {
        let joined = [title, location ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        let penalties = CalendarEventSignals.penalties(title: title, location: location, context: context)
        // Name-word collision guard (2.3 F): one word of a rental's name or a one-word alias next to
        // invite signals is a coincidence ("[PLAT] Atlas check-in" beside "Atlas Lofts"), not a match.
        var scored = properties
        var collision: String?
        if !penalties.isEmpty, let match = matchProperty(normalized: normalize(joined), properties: properties), match.isSingleWord {
            scored = []
            collision = "property (one name word beside invite signals): \(match.reason)"
        }
        var verdict = evaluate(text: joined, properties: scored)
        if let collision { verdict.evidence.append(collision) }
        let titleOnly = evaluate(text: title, properties: scored)
        let base = legacyCalendarVerdict(verdict, title: title, titleOnly: titleOnly, penalties: penalties)
        return gated(base, penalties: penalties)
    }

    /// The 2.2 rules (title against invite, location-only cap), before the 2.3 gate.
    private static func legacyCalendarVerdict(_ joinedVerdict: RulesVerdict, title: String, titleOnly: RulesVerdict, penalties: [CalendarEventSignals.Penalty]) -> RulesVerdict {
        var verdict = joinedVerdict
        let penalty = penalties.reduce(0.0) { $0 + $1.score }
        let hasNegativeKeyword = verdict.evidence.contains { $0.hasPrefix("not landlord:") }
        let meetingish = CalendarEventSignals.titleHasMeetingWord(title)
            && penalties.contains { !CalendarEventSignals.isStrong($0) }
        let hasStrongNegative = hasNegativeKeyword || penalties.contains(where: CalendarEventSignals.isStrong) || meetingish

        let propertyCounted = verdict.evidence.contains { $0.hasPrefix("property:") }
        let joinedHasKeyword = verdict.evidence.contains { $0.hasPrefix("keyword:") }
        let keywords = keywords(in: titleOnly.evidence)
        let titleNamesProperty = titleOnly.evidence.contains { $0.hasPrefix("property:") }
        let locationOnly = (propertyCounted || joinedHasKeyword) && !keywords.vouches && !titleNamesProperty

        verdict.evidence.append(contentsOf: penalties.map { "not rental: \($0.reason)" })

        if locationOnly {
            if hasStrongNegative {
                return hidden(verdict, score: min(verdict.score + penalty, 0), note: "location only, with a not-rental signal")
            }
            let capped = min(verdict.score, CalendarEventSignals.locationOnlyMaxScore)
            verdict.score = capped
            verdict.confidence = confidence(forScore: capped)
            verdict.evidence.append(ClassifierThresholds.locationOnlyEvidence)
            verdict.hasLandlordSignal = capped > 0
            return verdict
        }

        let before = verdict
        verdict.score += penalty
        verdict.confidence = confidence(forScore: verdict.score)
        let stillSignal = before.hasLandlordSignal && verdict.score > 0
            && (verdict.score >= notSureMinScore || propertyCounted)
        // The title's landlord word is stronger than the invite. A strong one (lease, tenant,
        // showing) keeps the item visible against everything, the table's noise words and a
        // personal appointment included. Any other vouching word keeps it visible against the
        // invite (attendees, repeat, meeting word, work organizer), but not against a personal
        // appointment or a remote place, and not against noise words.
        let hardPenalty = penalties.contains { $0.reason == "personal appointment words" || $0.reason == "remote location" }
        let titleCarries = keywords.isStrong || (keywords.carries && penalty < 0 && !hardPenalty)
        verdict.hasLandlordSignal = stillSignal || titleCarries
        if !verdict.hasLandlordSignal, penalty < 0 {
            return hidden(verdict, score: verdict.score, note: "event signals outweigh the match")
        }
        return verdict
    }

    // MARK: The positive-signal gate (2.3 F, "G2" + "D2" in the inbox-noise report)

    /// Words that never count alone: they need another positive word beside them. "Check in" is a
    /// team meeting as often as a guest arrival, "deck" a slide deck as often as a porch.
    static let pairingOnlyWords: Set<String> = ["check in", "deck", "window", "tour", "potential", "keys", "replacement", "inquir"]
    /// Hardware stores pass the gate on their own (a trip to buy parts).
    static let storeNames: Set<String> = ["home depot", "lowes", "lowe s", "hardware store"]
    /// One positive word at least this heavy (and not pairing-only) passes the gate.
    static let gateSingleWord = 0.6
    /// Positive words that together reach this pass the gate ("Guest check in").
    static let gateWordSum = 1.2

    /// The table weight of every landlord keyword in `evidence` ("keyword: plumb").
    static func keywordHits(_ evidence: [String]) -> [(phrase: String, weight: Double)] {
        evidence.compactMap { line in
            guard line.hasPrefix("keyword: ") else { return nil }
            let phrase = String(line.dropFirst("keyword: ".count))
            guard let weight = ClassifierKeywords.signals.last(where: { $0.phrase == phrase })?.landlord else { return nil }
            return (phrase, weight)
        }
    }

    /// G2: the event names something only rental work would. A property name, alias or address;
    /// a keyword of 0.6 or more that is not pairing-only; a hardware store; or positive keywords
    /// summing to 1.2 or more. Without one, nothing (the model included) can put it in the Inbox.
    static func hasRentalCue(_ evidence: [String]) -> Bool {
        if evidence.contains(where: { $0.hasPrefix("property:") }) { return true }
        let hits = keywordHits(evidence)
        if hits.contains(where: { $0.weight >= gateSingleWord && !pairingOnlyWords.contains($0.phrase) }) { return true }
        if hits.contains(where: { storeNames.contains($0.phrase) }) { return true }
        return hits.map(\.weight).filter { $0 > 0 }.reduce(0, +) >= gateWordSum
    }

    /// Applies G2 and D2 to a calendar verdict. Hidden items carry `notRentalEvidence` (so the model
    /// is not asked and its "yes" can't bring them back); items that pass carry `rentalCueEvidence`.
    private static func gated(_ verdict: RulesVerdict, penalties: [CalendarEventSignals.Penalty]) -> RulesVerdict {
        if verdict.evidence.contains(ClassifierThresholds.notRentalEvidence) { return verdict }
        guard hasRentalCue(verdict.evidence) else {
            return hidden(verdict, score: verdict.score, note: "no rental cue")
        }
        // D2: invite signals (attendees, a repeat, a work organizer, a remote place) beat every
        // title word under 1.0 when no property matched. Under 2.0 ("D") cost 4 points of recall.
        let property = verdict.evidence.contains { $0.hasPrefix("property:") }
        let heaviest = keywordHits(verdict.evidence).map(\.weight).max() ?? 0
        if !penalties.isEmpty, !property, heaviest < carryingTitleKeyword {
            return hidden(verdict, score: verdict.score, note: "invite signals outweigh weak words")
        }
        var out = verdict
        out.evidence.append(ClassifierThresholds.rentalCueEvidence)
        return out
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

/// Whether a classifier outcome is shown in the Inbox. One answer for the live scan, the backfill
/// and the one-time cleanup, so they can never disagree about the same event.
enum CalendarVisibility {
    /// The classification to show, or nil to hide. A hidden item with a landlord word of 1.0 or
    /// more in its title is kept as "Not sure" (confidence at least 0.30), unless the rules marked
    /// it as not rental work (no rental cue, invite signals, a personal appointment, a remote
    /// place). Muted items are nil: a mute is the user's rule, handled by the caller. Pure (moved
    /// here from the coordinator in 2.3 so the synthetic-set harness runs the real code).
    ///
    /// `keepKeywordTitles`: the cleanup of items already in the Inbox. It never deletes one with a
    /// landlord word in its title, even when the rules marked it not rental; it drops to "Not sure".
    static func shown(_ outcome: ClassifierOutcome, title: String, keepKeywordTitles: Bool = false) -> CaptureClassification? {
        switch outcome {
        case .suggest(let classification):
            return classification
        case .skip(var classification):
            guard keepKeywordTitles || !classification.evidence.contains(ClassifierThresholds.notRentalEvidence),
                  RulesEngine.titleHasLandlordKeyword(title) else { return nil }
            classification.confidence = max(classification.confidence, ClassifierThresholds.notSure)
            classification.evidence.append(ClassifierThresholds.landlordSignalEvidence)
            return classification
        case .muted:
            return nil
        }
    }
}
