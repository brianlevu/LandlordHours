import Foundation

// MARK: - Rules engine (pure)
//
// Scores free text (calendar title + location) against `ClassifierKeywords` and the user's
// properties. No I/O, no model, runs on every OS the app supports (iOS 17+). The calibration
// test drives this directly.

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
    /// True when at least one positive (landlord) signal or a property matched.
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

    static func confidence(forScore score: Double) -> Double {
        1 / (1 + exp(-(slope * score - offset)))
    }

    static func evaluate(text: String, properties: [RentalProperty]) -> RulesVerdict {
        let normalized = normalize(text)
        let padded = " \(normalized) "
        var score = 0.0
        var categoryVotes: [ActivityCategory: Double] = [:]
        var evidence: [String] = []
        var hasPositive = false

        for signal in ClassifierKeywords.signals where matches(signal, in: padded) {
            score += signal.landlord
            if signal.landlord > 0 { hasPositive = true }
            if let category = signal.category, signal.categoryWeight > 0 {
                categoryVotes[category, default: 0] += signal.categoryWeight
            }
            evidence.append(signal.landlord >= 0 ? "keyword: \(signal.phrase)" : "not landlord: \(signal.phrase)")
        }

        let propertyMatch = matchProperty(normalized: normalized, properties: properties)
        if let match = propertyMatch {
            score += match.boost
            hasPositive = true
            evidence.append("property: \(match.reason)")
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

        return RulesVerdict(
            score: score,
            confidence: confidence(forScore: score),
            category: category,
            propertyId: propertyMatch?.property.id,
            evidence: evidence,
            hasLandlordSignal: hasPositive
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

    // MARK: Property matching

    struct PropertyMatch {
        let property: RentalProperty
        let boost: Double
        let reason: String
    }

    /// Finds the property the text is about. Order of trust:
    /// 1. house number + street word of the address ("412 Oak");
    /// 2. the property's distinctive name words ("Maple Cottage" → "maple");
    /// 3. a street word or unit token alone ("Lakeshore", "4B").
    /// A tie between properties at the same level proposes nothing.
    static func matchProperty(normalized: String, properties: [RentalProperty]) -> PropertyMatch? {
        guard !properties.isEmpty else { return nil }
        let textWords = Set(words(normalized))
        let padded = " \(normalized) "

        // 0. Full name as a phrase.
        let fullName = properties.filter { p in
            let name = normalize(p.name)
            return !name.isEmpty && padded.contains(" \(name) ")
        }
        if fullName.count == 1, let p = fullName.first {
            return PropertyMatch(property: p, boost: propertyNameBoost, reason: p.name)
        }

        // 1. House number + street word.
        let numbered = properties.filter { p in
            let parts = addressParts(p.address)
            guard let number = parts.number, textWords.contains(number) else { return false }
            return !parts.streetWords.isDisjoint(with: textWords)
        }
        if numbered.count == 1, let p = numbered.first {
            return PropertyMatch(property: p, boost: propertyAddressBoost, reason: p.shortAddress)
        }

        // 2. Distinctive name words.
        let scored = properties.compactMap { p -> (RentalProperty, Int)? in
            let nameWords = Set(words(normalize(p.name))).filter { $0.count > 2 && !ClassifierKeywords.propertyStopWords.contains($0) }
            let hits = nameWords.intersection(textWords).count
            return hits > 0 ? (p, hits) : nil
        }.sorted { $0.1 > $1.1 }
        if let best = scored.first, scored.dropFirst().first?.1 != best.1 {
            return PropertyMatch(property: best.0, boost: propertyNameBoost, reason: best.0.name)
        }

        // 3. Street word or unit token alone.
        let streetOnly = properties.filter { p in
            let parts = addressParts(p.address)
            return !parts.streetWords.isDisjoint(with: textWords) || !parts.unitTokens.isDisjoint(with: textWords)
        }
        if streetOnly.count == 1, let p = streetOnly.first {
            return PropertyMatch(property: p, boost: propertyStreetBoost, reason: p.shortAddress)
        }
        return nil
    }

    struct AddressParts {
        var number: String?
        var streetWords: Set<String>
        var unitTokens: Set<String>
    }

    /// Only the first address segment ("412 Oak St") is used: city and state would match far
    /// too much ("Flight to Austin").
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
                units.insert(token)          // "4b"
            } else if !hasDigit, token.count > 2, !ClassifierKeywords.propertyStopWords.contains(token) {
                street.insert(token)
            }
        }
        return AddressParts(number: number, streetWords: street, unitTokens: units)
    }
}
