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
                return remoteResult
            }
        }

        return localResult
    }

    // MARK: - Local Parser (keyword-based, no API needed)

    private func parseLocally(text: String, properties: [RentalProperty]) -> ParsedTimeEntry? {
        let lower = text.lowercased()

        // Extract hours
        let hours = extractHours(from: lower)

        // Match category by keywords
        let category = matchCategory(from: lower)

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

    private func extractHours(from text: String) -> Double {
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

        return 1.0
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
