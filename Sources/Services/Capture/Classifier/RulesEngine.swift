import Foundation

// MARK: - Rules engine (pure)
//
// Scores free text (calendar title + location, or an email's "sender: subject") against
// `ClassifierKeywords` and the user's properties. No I/O, no model, runs on every OS the app
// supports (iOS 17+). The calibration test drives this directly.
//
// Classifier v2 (2026-10-19, from real-owner calibration):
// - property aliases (listing titles, nicknames, vendors) match as full phrases at the name boost;
// - an "I live here" property makes address and street matches weak, and they need a work keyword;
// - a street match needs every street word, never one shared word ("San", "Lake");
// - platform and store names are weak alone and score only next to a host action or purchase;
// - mailing-list tags, marketing and account mail count against.

struct RulesVerdict: Equatable {
    /// Sum of matched signal weights, plus the property-match boost.
    var score: Double
    /// Probability-like 0...1 mapped from `score` (logistic).
    var confidence: Double
    /// Best category from the keyword table, or nil when no signal voted.
    var category: ActivityCategory?
    var propertyId: UUID?
    /// Short human-readable reasons, e.g. "keyword: plumber". Local only.
    var evidence: [String]
    /// True when the item may show as "Not sure": a landlord keyword or a counted property match
    /// that noise doesn't outweigh, and either a score of at least `notSureMinScore` or a
    /// property/alias match.
    var hasLandlordSignal: Bool
}

enum RulesEngine {
    /// Logistic mapping: confidence = 1 / (1 + e^-(slope * score - offset)).
    /// No signals (score 0) → ~0.12; one strong landlord word (2.5) → ~0.82.
    static let slope = 1.4
    static let offset = 2.0

    /// Boosts added to the score for a property match.
    static let propertyNameBoost = 2.5
    static let propertyAddressBoost = 3.0
    static let propertyStreetBoost = 2.0
    /// Address and street boosts are multiplied by this for a property the owner lives in.
    static let ownerOccupiedFactor = 0.4
    /// Added when a platform or store name sits next to a host action or a purchase.
    static let pairingBonus = 1.2
    /// A raw "[list-name]" tag in the text (mailing lists, community groups).
    static let mailingListPenalty = -3.0
    /// Below this rules score, a keyword hit alone doesn't make an item "Not sure".
    static let notSureMinScore = 1.5

    static func confidence(forScore score: Double) -> Double {
        1 / (1 + exp(-(slope * score - offset)))
    }

    static func evaluate(text: String, properties: [RentalProperty]) -> RulesVerdict {
        // A mailing-list tag names the list, never a property ("[maple-neighbors]").
        let listTag = hasMailingListTag(text)
        var normalized = normalize(listTag ? text.replacingOccurrences(of: mailingListTagPattern, with: " ", options: .regularExpression) : text)
        var score = 0.0
        var categoryVotes: [ActivityCategory: Double] = [:]
        var evidence: [String] = []
        var hasPositive = false

        // Property first: a matched name or alias phrase is taken out of the text before the
        // keywords run, so words inside a listing title ("family", "reservation") don't count
        // against it.
        let propertyMatch = matchProperty(normalized: normalized, properties: properties)
        if let match = propertyMatch, let phrase = match.phrase {
            normalized = removing(phrase: phrase, from: normalized)
            // The phrase still votes for a category ("Ridgeline Plumbing" → repairs), never for score.
            let paddedPhrase = " \(phrase) "
            for signal in ClassifierKeywords.signals where signal.landlord > 0 && matches(signal, in: paddedPhrase) {
                if let category = signal.category, signal.categoryWeight > 0 {
                    categoryVotes[category, default: 0] += signal.categoryWeight
                }
            }
        }
        let padded = " \(normalized) "

        var roles = Set<ClassifierSignal.Role>()
        var hasWorkKeyword = false
        for signal in ClassifierKeywords.signals where matches(signal, in: padded) {
            score += signal.landlord
            if signal.landlord > 0 {
                hasPositive = true
                // Platform and store names alone are not work: they need a host action or a
                // purchase. They still count as a weak positive for the "Not sure" band.
                if signal.role != .platform && signal.role != .store { hasWorkKeyword = true }
            }
            roles.insert(signal.role)
            if let category = signal.category, signal.categoryWeight > 0 {
                categoryVotes[category, default: 0] += signal.categoryWeight
            }
            evidence.append(signal.landlord >= 0 ? "keyword: \(signal.phrase)" : "not landlord: \(signal.phrase)")
        }
        if roles.contains(.platform) && roles.contains(.hostAction) {
            score += pairingBonus
            evidence.append("pair: platform + host action")
        }
        if roles.contains(.store) && roles.contains(.purchase) {
            score += pairingBonus
            evidence.append("pair: store + purchase")
        }
        if listTag {
            score += mailingListPenalty
            evidence.append("not landlord: mailing list")
        }
        if hasPercentOff(text) {
            score -= 2.0
            evidence.append("not landlord: % off")
        }

        var countedProperty: PropertyMatch?
        if let match = propertyMatch {
            if match.isWeak && !hasWorkKeyword {
                // An address at a home the owner lives in is not work by itself.
                evidence.append("property (lives here, no work keyword): \(match.reason)")
            } else {
                countedProperty = match
                score += match.boost
                hasPositive = true
                evidence.append("property: \(match.reason)")
            }
        }

        // Highest vote wins; ties go to the category listed first in ActivityCategory.
        let category = ActivityCategory.allCases
            .compactMap { cat in categoryVotes[cat].map { (cat, $0) } }
            .max { lhs, rhs in
                if lhs.1 == rhs.1 {
                    let order = ActivityCategory.allCases
                    return order.firstIndex(of: lhs.0)! > order.firstIndex(of: rhs.0)!
                }
                return lhs.1 < rhs.1
            }?.0

        // Host work on a rental platform with no property named: the user's only short-term
        // rental is the one it is about. No score boost.
        var proposedId = (countedProperty ?? propertyMatch)?.property.id
        if proposedId == nil, roles.contains(.platform), roles.contains(.hostAction) {
            let shortTerm = properties.filter { $0.propertyType == .str }
            if shortTerm.count == 1 {
                proposedId = shortTerm[0].id
                evidence.append("property guess: only short-term rental")
            }
        }

        // "Not sure" needs more than any keyword hit: a score of at least 1.5, or a property or
        // alias match. Noise that outweighs the keyword still drops it ("Rent tux for wedding").
        let signal = hasPositive && score > 0 && (score >= notSureMinScore || countedProperty != nil)
        return RulesVerdict(
            score: score,
            confidence: confidence(forScore: score),
            category: category,
            propertyId: proposedId,
            evidence: evidence,
            hasLandlordSignal: signal
        )
    }

    // MARK: Text

    /// Lowercased, diacritics folded, every non-alphanumeric run collapsed to one space.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        var out = ""
        out.reserveCapacity(folded.count)
        var lastWasSpace = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        if out.hasSuffix(" ") { out.removeLast() }
        return out
    }

    static func words(_ normalized: String) -> [String] {
        normalized.split(separator: " ").map(String.init)
    }

    /// `padded` is " <normalized> ". Word-prefix match by default, whole-word when asked.
    static func matches(_ signal: ClassifierSignal, in padded: String) -> Bool {
        let needle = " " + signal.phrase + (signal.wholeWord ? " " : "")
        return padded.contains(needle)
    }

    static func removing(phrase: String, from normalized: String) -> String {
        let padded = " \(normalized) ".replacingOccurrences(of: " \(phrase) ", with: " ")
        return normalize(padded)
    }

    /// A "[list-name]" tag in the raw text: mailing lists and community groups put one in the
    /// subject ("[neighbors] Plumber recommendation?"). Checked before normalisation.
    static func hasMailingListTag(_ raw: String) -> Bool {
        raw.range(of: mailingListTagPattern, options: .regularExpression) != nil
    }

    static let mailingListTagPattern = #"\[[^\]\s][^\]]{1,40}\]"#

    /// "20% off": retail marketing. Checked before normalisation.
    static func hasPercentOff(_ raw: String) -> Bool {
        raw.range(of: #"\d\s*%\s*off\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: Property matching

    struct PropertyMatch {
        let property: RentalProperty
        let boost: Double
        let reason: String
        /// The normalized name or alias phrase that matched (removed before keyword scoring).
        let phrase: String?
        /// An address/street match on a property the owner lives in: needs a work keyword.
        let isWeak: Bool
    }

    /// Finds the property the text is about. Order of trust:
    /// 0. the full name or an alias as a phrase ("Maple Cottage", a listing title, a vendor);
    /// 1. house number + every street word of the address ("412 Oak", "240 San Marco");
    /// 2. the property's distinctive name words ("Maple Cottage" → "maple");
    /// 3. every street word, or a unit token, alone ("Lakeshore", "4B").
    /// A tie between properties at the same level proposes nothing. For a property the owner
    /// lives in, levels 1 and 3 (and a name that is just the street) are weak.
    static func matchProperty(normalized: String, properties: [RentalProperty]) -> PropertyMatch? {
        guard !properties.isEmpty else { return nil }
        let textWords = Set(words(normalized))
        let padded = " \(normalized) "

        func contains(_ phrase: String) -> Bool { !phrase.isEmpty && padded.contains(" \(phrase) ") }

        // 0. Full name or alias as a phrase. The longest phrase wins a tie between properties.
        var phraseHits: [(RentalProperty, String, String, Bool)] = []   // property, phrase, label, isName
        for p in properties {
            let name = normalize(p.name)
            if contains(name) { phraseHits.append((p, name, p.name, true)) }
            for alias in p.aliases {
                let a = normalize(alias)
                if a.count >= 3, contains(a) { phraseHits.append((p, a, alias, false)) }
            }
        }
        if !phraseHits.isEmpty {
            let longest = phraseHits.map { $0.1.count }.max() ?? 0
            let best = phraseHits.filter { $0.1.count == longest }
            if Set(best.map { $0.0.id }).count == 1, let hit = best.first {
                let p = hit.0
                // A name that is only the street ("Birchwood" at 77 Birchwood Ln) is an
                // address match for a home the owner lives in.
                let weak = p.isOwnerOccupied && hit.3 && nameIsStreet(p)
                let boost = weak ? propertyNameBoost * ownerOccupiedFactor : propertyNameBoost
                return PropertyMatch(property: p, boost: boost, reason: hit.3 ? p.name : "also called \(hit.2)", phrase: hit.1, isWeak: weak)
            }
        }

        // 1. House number + every street word.
        let numbered = properties.filter { p in
            let parts = addressParts(p.address)
            guard let number = parts.number, textWords.contains(number), !parts.streetWords.isEmpty else { return false }
            return parts.streetWords.isSubset(of: textWords)
        }
        if numbered.count == 1, let p = numbered.first {
            return addressMatch(p, boost: propertyAddressBoost)
        }

        // 2. Distinctive name words.
        let scored = properties.compactMap { p -> (RentalProperty, Int)? in
            let nameWords = Set(words(normalize(p.name))).filter { $0.count > 2 && !ClassifierKeywords.propertyStopWords.contains($0) && !ClassifierKeywords.placeWords.contains($0) }
            let hits = nameWords.intersection(textWords).count
            return hits > 0 ? (p, hits) : nil
        }.sorted { $0.1 > $1.1 }
        if let best = scored.first, scored.dropFirst().first?.1 != best.1 {
            let p = best.0
            let weak = p.isOwnerOccupied && nameIsStreet(p)
            return PropertyMatch(property: p, boost: weak ? propertyNameBoost * ownerOccupiedFactor : propertyNameBoost,
                                 reason: p.name, phrase: nil, isWeak: weak)
        }

        // 3. Every street word, or a unit token, alone. A street made only of generic place
        // words ("Lake", "San") never matches alone.
        let streetOnly = properties.filter { p in
            let parts = addressParts(p.address)
            let streetHit = !parts.streetWords.isEmpty
                && !parts.streetWords.isSubset(of: ClassifierKeywords.placeWords)
                && parts.streetWords.isSubset(of: textWords)
            return streetHit || !parts.unitTokens.isDisjoint(with: textWords)
        }
        if streetOnly.count == 1, let p = streetOnly.first {
            return addressMatch(p, boost: propertyStreetBoost)
        }
        return nil
    }

    private static func addressMatch(_ p: RentalProperty, boost: Double) -> PropertyMatch {
        let weak = p.isOwnerOccupied
        return PropertyMatch(property: p, boost: weak ? boost * ownerOccupiedFactor : boost,
                             reason: p.shortAddress, phrase: nil, isWeak: weak)
    }

    /// True when the property's distinctive name words are all street words of its address.
    static func nameIsStreet(_ p: RentalProperty) -> Bool {
        let nameWords = Set(words(normalize(p.name))).filter { !ClassifierKeywords.propertyStopWords.contains($0) }
        guard !nameWords.isEmpty else { return false }
        return nameWords.isSubset(of: addressParts(p.address).streetWords)
    }

    struct AddressParts {
        var number: String?
        var streetWords: Set<String>
        var unitTokens: Set<String>
    }

    /// Only the first address segment ("412 Oak St") is used: city and state would match far
    /// too much ("Flight to Austin"). Generic street words ("St", "Ave") are dropped.
    static func addressParts(_ address: String) -> AddressParts {
        let first = address.components(separatedBy: ",").first ?? address
        let tokens = words(normalize(first))
        var number: String?
        var street = Set<String>()
        var units = Set<String>()
        for (index, token) in tokens.enumerated() {
            let hasDigit = token.contains { $0.isNumber }
            let hasLetter = token.contains { $0.isLetter }
            if index == 0, hasDigit, !hasLetter {
                number = token
            } else if hasDigit && hasLetter {
                if token.range(of: #"^\d+(st|nd|rd|th)$"#, options: .regularExpression) != nil {
                    street.insert(token)     // "4th" in "2777 4th St" is the street, not a unit
                } else {
                    units.insert(token)      // "4b"
                }
            } else if !hasDigit, token.count > 2, !ClassifierKeywords.propertyStopWords.contains(token) {
                street.insert(token)
            }
        }
        return AddressParts(number: number, streetWords: street, unitTokens: units)
    }
}
