import Foundation
import os.log

private let logger = Logger(subsystem: "com.openclaw.landlordhours", category: "AI")

// MARK: - AI Time Entry Service
class AITimeEntryService {
    static let shared = AITimeEntryService()

    /// Pre-compiled regex patterns for category matching — built once at init.
    private let categoryPatterns: [(ActivityCategory, NSRegularExpression)]

    private var apiKey: String {
        if let key = Bundle.main.object(forInfoDictionaryKey: "MINIMAX_API_KEY") as? String, !key.isEmpty {
            return key
        }
        return ProcessInfo.processInfo.environment["MINIMAX_API_KEY"] ?? ""
    }
    private let endpoint = "https://api.minimax.chat/v1/text/chatcompletion_pro"

    private init() {
        // Pre-compile category keyword patterns into regexes (ordered by specificity)
        let categoryKeywords: [(ActivityCategory, [String])] = [
            (.repairs, ["repair", "fix", "broke", "broken", "leak", "plumb", "faucet", "hvac",
                        "heater", "furnace", "ac ", "a/c", "air condition", "appliance",
                        "toilet", "sink", "pipe", "drain", "roof", "gutter", "paint",
                        "patch", "drywall", "electrical", "wiring", "outlet", "light fixture"]),
            (.renovations, ["renovate", "renovation", "remodel", "upgrade", "install",
                            "replace", "flooring", "tile", "cabinet", "countertop",
                            "bathroom remodel", "kitchen remodel", "addition", "demolition"]),
            (.leasing, ["lease", "leas", "tenant", "showing", "screen", "application",
                        "move-in", "move in", "move-out", "move out", "evict", "vacancy",
                        "listing", "advertise", "rental agreement", "renew", "rent"]),
            (.management, ["manage", "inspect", "clean", "maintenance", "mow", "landscape",
                           "lawn", "snow", "trash", "pest", "exterminator", "vendor",
                           "coordinate", "supervise", "check on", "visit", "walk-through",
                           "schedule", "organize", "meet with", "property check"]),
            (.bookkeeping, ["bookkeep", "accounting", "tax", "receipt", "invoice", "expense",
                            "budget", "financial", "quickbooks", "spreadsheet", "record keep",
                            "bank", "payment", "billing", "ledger"]),
            (.legal, ["legal", "lawyer", "attorney", "court", "compliance", "permit",
                       "license", "zoning", "code", "regulation", "contract", "lawsuit",
                       "dispute", "filing", "lien"]),
            (.insurance, ["insurance", "claim", "policy", "coverage", "adjuster",
                          "premium", "deductible", "liability"]),
            (.travel, ["travel", "drive", "drove", "commute", "mileage", "trip to",
                       "went to", "visit property", "gas", "fuel"]),
            (.investing, ["invest", "research", "analyze", "market", "deal", "acquisition",
                          "due diligence", "offer", "negotiate price", "property search",
                          "real estate search"]),
            (.financing, ["financ", "mortgage", "loan", "refinanc", "bank meeting",
                          "lender", "interest rate", "appraisal", "closing"]),
            (.contractNegotiation, ["contract", "negotiat", "agreement", "terms", "bid",
                                     "proposal", "scope of work", "contractor"]),
        ]

        categoryPatterns = categoryKeywords.compactMap { category, keywords in
            let escaped = keywords.map { NSRegularExpression.escapedPattern(for: $0) }
            let pattern = escaped.joined(separator: "|")
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return nil
            }
            return (category, regex)
        }
    }

    func parseTimeEntry(from text: String, properties: [RentalProperty]) async -> ParsedTimeEntry? {
        // Always try local parsing first — it's instant and works offline
        let localResult = parseLocally(text: text, properties: properties)

        // If we have an API key, try the remote API for better accuracy
        if !apiKey.isEmpty {
            if let remoteResult = await parseRemotely(text: text, properties: properties) {
                return mergeRemoteResult(remoteResult, with: localResult, sourceText: text)
            }
        }

        return localResult
    }

    private func mergeRemoteResult(_ remote: ParsedTimeEntry, with local: ParsedTimeEntry?, sourceText: String) -> ParsedTimeEntry {
        guard let local else { return remote }
        let hasExplicitHours = extractExplicitHours(from: sourceText.lowercased()) != nil

        return ParsedTimeEntry(
            property: remote.property ?? local.property,
            category: remote.category,
            hours: (!hasExplicitHours && abs(remote.hours - 1.0) < 0.001) ? local.hours : remote.hours,
            participant: remote.participant,
            notes: remote.notes.isEmpty ? local.notes : remote.notes
        )
    }

    // MARK: - Local Parser (keyword-based, no API needed)

    private func parseLocally(text: String, properties: [RentalProperty]) -> ParsedTimeEntry? {
        let lower = text.lowercased()

        // Match category by keywords
        let category = matchCategory(from: lower)

        // Extract or estimate hours after category detection, so short natural notes
        // still produce a useful draft instead of a generic 1.0h default.
        let hours = extractExplicitHours(from: lower) ?? estimateHours(for: category, text: lower)

        // Match property by name
        let property = matchProperty(from: lower, properties: properties)

        // Match participant
        let participant: Participant = lower.contains("spouse") || lower.contains("wife") || lower.contains("husband")
            ? .spouse : .selfParticipant

        return ParsedTimeEntry(
            property: property,
            category: category,
            hours: hours,
            participant: participant,
            notes: text
        )
    }

    private func extractExplicitHours(from text: String) -> Double? {
        // Match dictated mixed-duration phrases before simpler hour-only patterns.
        let mixedDurationPatterns = [
            #"(\d+\.?\d*)\s*(?:hours?|hrs?|h)\s+(?:and\s+)?(\d+)\s*(?:minutes?|mins?|m)\b"#,
            #"(\d+\.?\d*)\s*(?:hours?|hrs?|h)\s+(?:and\s+)?(?:a\s+)?half\b"#
        ]

        for pattern in mixedDurationPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                let hourRange = match.range(at: 1)
                guard let swiftHourRange = Range(hourRange, in: text),
                      let hours = Double(text[swiftHourRange]) else { continue }

                var minutes = 30.0
                if match.numberOfRanges > 2 {
                    let minuteRange = match.range(at: 2)
                    if let swiftMinuteRange = Range(minuteRange, in: text),
                       let parsedMinutes = Double(text[swiftMinuteRange]) {
                        minutes = parsedMinutes
                    }
                }

                return min(max(hours + (minutes / 60), 0.25), 24)
            }
        }

        let naturalLanguageHours: [(String, Double)] = [
            (#"\b(?:one|an|a|1)\s+and\s+(?:a\s+)?half\s+hours?\b"#, 1.5),
            (#"\b(?:an|a|one|1)\s+hour\s+and\s+(?:a\s+)?half\b"#, 1.5),
            (#"\b(?:an|one|1)\s+hour\b"#, 1.0),
            (#"\b(?:a|one|1)\s+half\s+hour\b"#, 0.5),
            (#"\bhalf\s+(?:an\s+)?hour\b"#, 0.5),
            (#"\b(?:quarter|15\s+minutes?)\b"#, 0.25),
            (#"\b(?:thirty|30)\s+minutes?\b"#, 0.5),
            (#"\b(?:forty\s*five|45)\s+minutes?\b"#, 0.75),
            (#"\b(?:two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+hours?\b"#, 0)
        ]

        for (pattern, value) in naturalLanguageHours {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
                continue
            }

            if value > 0 {
                return value
            }

            if let swiftRange = Range(match.range, in: text) {
                return wordHourValue(in: String(text[swiftRange]))
            }
        }

        // Match patterns like "3 hours", "2.5h", "1.5 hrs", "for 3h", "took 2 hours"
        let patterns = [
            #"(\d+\.?\d*)\s*(?:hours?|hrs?|h)\b"#,
            #"(?:for|took|spent|about)\s+(\d+\.?\d*)\s*(?:hours?|hrs?|h)?"#,
            #"(\d+\.?\d*)\s*(?:hours?|hrs?|h)"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                let range = match.range(at: 1)
                if let swiftRange = Range(range, in: text), let value = Double(text[swiftRange]) {
                    return min(max(value, 0.25), 24)
                }
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*(?:minutes?|mins?|m)\b"#, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text),
           let minutes = Double(text[range]) {
            return min(max(minutes / 60, 0.25), 24)
        }

        return nil
    }

    private func wordHourValue(in text: String) -> Double? {
        let hourWords: [String: Double] = [
            "two": 2,
            "three": 3,
            "four": 4,
            "five": 5,
            "six": 6,
            "seven": 7,
            "eight": 8,
            "nine": 9,
            "ten": 10,
            "eleven": 11,
            "twelve": 12
        ]

        for (word, value) in hourWords where text.contains(word) {
            return value
        }
        return nil
    }

    private func estimateHours(for category: ActivityCategory, text: String) -> Double {
        if text.contains("quick") || text.contains("brief") || text.contains("call") || text.contains("texted") {
            return 0.5
        }

        if text.contains("paint") {
            if text.contains("house") || text.contains("exterior") || text.contains("room") {
                return 3.0
            }
            return 2.0
        }

        switch category {
        case .repairs:
            return 1.5
        case .renovations:
            return 3.0
        case .leasing, .legal, .insurance:
            return 1.0
        case .bookkeeping, .management:
            return 0.75
        case .travel:
            return 1.0
        case .investing, .financing, .contractNegotiation:
            return 0.5
        }
    }

    private func matchCategory(from text: String) -> ActivityCategory {
        let range = NSRange(text.startIndex..., in: text)
        for (category, regex) in categoryPatterns {
            if regex.firstMatch(in: text, range: range) != nil {
                return category
            }
        }
        return .management // Default
    }

    private func matchProperty(from text: String, properties: [RentalProperty]) -> RentalProperty? {
        // Try exact name match first, then partial match
        for property in properties {
            let name = property.name.lowercased()
            if text.contains(name) { return property }
        }

        // Match meaningful property-name words. This handles natural phrases like
        // "Oak Street leak" for a saved property named "Oak Street Duplex".
        let textWords = significantWords(in: text)
        let nameMatches = properties.compactMap { property -> (property: RentalProperty, score: Int)? in
            let nameWords = significantWords(in: property.name.lowercased())
            let score = nameWords.intersection(textWords).count
            return score > 0 ? (property, score) : nil
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.property.name.count > rhs.property.name.count
            }
            return lhs.score > rhs.score
        }

        if let best = nameMatches.first {
            let isAmbiguous = nameMatches.dropFirst().first?.score == best.score
            if !isAmbiguous || best.score >= 2 {
                return best.property
            }
        }

        // Try address parts
        for property in properties {
            let addressWords = property.address.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 3 }
            for word in addressWords {
                if text.contains(word) { return property }
            }
        }

        // If only one property, default to it
        if properties.count == 1 { return properties[0] }

        return nil
    }

    private func significantWords(in text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "the", "and", "for", "with", "unit", "house", "home", "property", "rental",
            "duplex", "triplex", "apartment", "condo", "street", "st", "avenue", "ave",
            "road", "rd", "drive", "dr", "lane", "ln", "court", "ct", "place", "pl"
        ]

        return Set(
            text.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count > 2 && !stopWords.contains($0) }
        )
    }

    // MARK: - Remote API Parser (MiniMax — optional enhancement)

    private func parseRemotely(text: String, properties: [RentalProperty]) async -> ParsedTimeEntry? {
        let propertyList = properties.map { "- \($0.name): \($0.address)" }.joined(separator: "\n")

        let prompt = """
        Parse this time entry description and extract the relevant information.

        Available properties:
        \(propertyList)

        Categories (IRS-qualified for REPS):
        - Repairs & Maintenance
        - Property Management
        - Leasing & Tenant Relations
        - Bookkeeping & Financial
        - Legal & Compliance
        - Insurance & Claims
        - Travel to Property
        - Renovations & Improvements

        Participants: Self, Spouse

        User's input: "\(text)"

        Respond with JSON in this exact format:
        {
            "propertyName": "matched property name or empty string",
            "category": "best matching category or empty string",
            "hours": number (e.g., 2.0),
            "participant": "Self" or "Spouse",
            "notes": "any additional context extracted"
        }

        If no clear match, use empty strings. Estimate hours if mentioned (e.g., "4 hours" = 4.0).
        """

        guard let url = URL(string: endpoint) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "MiniMax-M2.5",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that parses time entry descriptions."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return parseJSONResponse(content, properties: properties)
            }
        } catch {
            logger.error("Remote parse error: \(error.localizedDescription)")
        }

        return nil
    }

    private func parseJSONResponse(_ content: String, properties: [RentalProperty]) -> ParsedTimeEntry? {
        guard let jsonStart = content.firstIndex(of: "{"),
              let jsonEnd = content.lastIndex(of: "}") else { return nil }

        let jsonString = String(content[jsonStart...jsonEnd])
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let propertyName = json["propertyName"] as? String ?? ""
        let categoryRaw = json["category"] as? String ?? ""
        // Accept string or number, clamp to valid range
        let rawHours: Double
        if let h = json["hours"] as? Double {
            rawHours = h
        } else if let s = json["hours"] as? String, let h = Double(s) {
            rawHours = h
        } else {
            rawHours = 1.0
        }
        let hours = min(max(rawHours, 0.25), 24)
        let participantRaw = json["participant"] as? String ?? "Self"

        let matchedProperty = properties.first {
            $0.name.lowercased() == propertyName.lowercased() ||
            $0.name.lowercased().contains(propertyName.lowercased())
        }

        let matchedCategory = ActivityCategory.allCases.first {
            $0.rawValue.lowercased().contains(categoryRaw.lowercased()) ||
            categoryRaw.lowercased().contains($0.rawValue.lowercased())
        }

        let participant: Participant = participantRaw == "Spouse" ? .spouse : .selfParticipant

        return ParsedTimeEntry(
            property: matchedProperty,
            category: matchedCategory ?? .repairs,
            hours: hours,
            participant: participant,
            notes: ""
        )
    }
}

struct ParsedTimeEntry {
    var property: RentalProperty?
    var category: ActivityCategory
    var hours: Double
    var participant: Participant
    var notes: String
}
