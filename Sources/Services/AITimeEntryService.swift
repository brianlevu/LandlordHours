import Foundation

// MARK: - AI Time Entry Service
class AITimeEntryService {
    static let shared = AITimeEntryService()
    
    private let apiKey = "sk-cp-fIL6McDkFi8WjWDWI1bYkdNXRMP44hOYaMHjlc40PUJD0sUAD0d43mgAeEL2hpsGxoRFf8JJJT4Gf4ZpM8ZX707fJ6sA3u9P2rV1PuwV7RYqgx1pGoiYM_0"
    private let endpoint = "https://api.minimax.chat/v1/text/chatcompletion_pro"
    
    private init() {}
    
    func parseTimeEntry(from text: String, properties: [RentalProperty]) async -> ParsedTimeEntry? {
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

        var request = URLRequest(url: url)
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
            print("AI parse error: \(error)")
        }
        
        return nil
    }
    
    private func parseJSONResponse(_ content: String, properties: [RentalProperty]) -> ParsedTimeEntry? {
        // Extract JSON from response
        guard let jsonStart = content.firstIndex(of: "{"),
              let jsonEnd = content.lastIndex(of: "}") else { return nil }
        
        let jsonString = String(content[jsonStart...jsonEnd])
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        
        let propertyName = json["propertyName"] as? String ?? ""
        let categoryRaw = json["category"] as? String ?? ""
        let hours = json["hours"] as? Double ?? 1.0
        let participantRaw = json["participant"] as? String ?? "Self"
        let notes = json["notes"] as? String ?? ""
        
        // Match property
        let matchedProperty = properties.first { 
            $0.name.lowercased() == propertyName.lowercased() ||
            $0.name.lowercased().contains(propertyName.lowercased())
        }
        
        // Match category
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
            notes: notes
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
