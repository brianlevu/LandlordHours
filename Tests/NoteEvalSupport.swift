import Foundation
#if !NOTE_EVAL_HOST
@testable import LandlordHours
#endif

// MARK: - Note reader eval (shared by NoteReaderEvalTests and the host-Mac harness)
//
// Loads Tests/Fixtures/note-eval.json (66 hand-labelled landlord notes), scores a reader per
// field and checks the hard rules. Foundation only, so scripts/note-eval-host can compile it
// with the app's NoteReading sources on the Mac (the host's Apple Intelligence and PCC).

struct NoteEvalFixture: Decodable {
    struct Property: Decodable {
        let ref: String
        let name: String
        let address: String
        let type: String
        let aliases: [String]
    }

    struct Case: Decodable {
        let id: String
        let note: String
        let spouseTracking: Bool
        let property: String?
        let categoryAnyOf: [String]?
        let hours: Double?
        let date: String?
        let participant: String?
        let nonCountable: Bool
    }

    let now: String
    let timeZone: String
    let properties: [Property]
    let cases: [Case]
}

struct NoteEvalSet {
    let fixture: NoteEvalFixture
    let properties: [RentalProperty]
    let refs: [String: UUID]
    let now: Date
    let calendar: Calendar

    init(data: Data) throws {
        fixture = try JSONDecoder().decode(NoteEvalFixture.self, from: data)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: fixture.timeZone) ?? .current
        self.calendar = calendar
        now = ISO8601DateFormatter().date(from: fixture.now) ?? Date()
        var refs: [String: UUID] = [:]
        properties = fixture.properties.enumerated().map { index, p in
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
            refs[p.ref] = id
            return RentalProperty(id: id, name: p.name, address: p.address, propertyType: p.type == "str" ? .str : .ltr, aliases: p.aliases)
        }
        self.refs = refs
    }

    func request(_ c: NoteEvalFixture.Case) -> NoteReadRequest {
        NoteReadRequest(text: c.note, properties: properties, spouseTracking: c.spouseTracking, now: now, calendar: calendar)
    }

    func day(_ iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static let fields = ["property", "category", "hours", "date", "participant"]

    /// field → correct?
    func score(_ c: NoteEvalFixture.Case, _ r: NoteReading) -> [String: Bool] {
        var out: [String: Bool] = [:]
        out["property"] = r.propertyId == c.property.flatMap { refs[$0] }
        if let allowed = c.categoryAnyOf {
            out["category"] = r.category.map { cat in allowed.contains { NoteModelPrompt.category(forKey: $0) == cat } } ?? false
        } else {
            out["category"] = r.category == nil
        }
        switch (c.hours, r.hours) {
        case (nil, nil): out["hours"] = true
        case (let e?, let g?): out["hours"] = abs(e - g) < 0.02
        default: out["hours"] = false
        }
        switch (c.date.flatMap(day), r.date) {
        case (nil, nil): out["date"] = true
        case (let e?, let g?): out["date"] = calendar.isDate(e, inSameDayAs: g)
        default: out["date"] = false
        }
        let expectSpouse = c.participant == "spouse"
        out["participant"] = expectSpouse ? r.participant == .spouse : (r.participant == nil || r.participant == .selfParticipant)
        return out
    }

    /// The hard rules. Empty = clean.
    func violations(_ c: NoteEvalFixture.Case, _ r: NoteReading) -> [String] {
        var out: [String] = []
        if r.hours != nil && (c.hours == nil || !NoteDuration.hasEvidence(c.note)) {
            out.append("\(c.id): invented hours \(r.hours!)")
        }
        if let id = r.propertyId, !properties.contains(where: { $0.id == id }) {
            out.append("\(c.id): property outside the list")
        }
        if c.nonCountable, let cat = r.category, cat.countsForREPS {
            out.append("\(c.id): non-countable note filed as \(cat.rawValue)")
        }
        if let d = r.description {
            let extra = NoteFactGuard.untraceable(d, request: request(c), propertyId: r.propertyId, category: r.category)
            if !extra.isEmpty { out.append("\(c.id): description adds \(extra)") }
        }
        if !c.spouseTracking, r.participant == .spouse {
            out.append("\(c.id): spouse without spouse tracking")
        }
        if let date = r.date, date > now {
            out.append("\(c.id): future date")
        }
        return out
    }

    struct TierReport {
        var name: String
        var correct: [String: Int] = [:]
        var total = 0
        var violations: [String] = []
        var descriptionsOffered = 0
        var descriptionsKept = 0
        var misses: [String] = []
        var samples: [String] = []
        var unavailable: String?

        func percent(_ field: String) -> Double { total == 0 ? 0 : Double(correct[field] ?? 0) / Double(total) * 100 }

        var line: String {
            if let unavailable { return "NOTE-EVAL \(name): unavailable (\(unavailable))" }
            let cells = NoteEvalSet.fields.map { String(format: "%@ %.0f%%", $0, percent($0)) }.joined(separator: " · ")
            return "NOTE-EVAL \(name) n=\(total): \(cells) · descriptions kept \(descriptionsKept)/\(descriptionsOffered) · hard-rule violations \(violations.count)"
        }
    }

    mutating func record(_ report: inout TierReport, _ c: NoteEvalFixture.Case, _ r: NoteReading, offeredDescription: Bool = false) {
        report.total += 1
        for (field, ok) in score(c, r) {
            if ok { report.correct[field, default: 0] += 1 } else { report.misses.append("\(c.id).\(field)") }
        }
        report.violations += violations(c, r)
        if offeredDescription { report.descriptionsOffered += 1 }
        if let d = r.description {
            report.descriptionsKept += 1
            if report.samples.count < 80 { report.samples.append("\(c.id): \(d)") }
        }
    }

    /// The 1.x keyword parser's answer, as the old sheet used it.
    static func legacyReading(_ parsed: ParsedTimeEntry?) -> NoteReading {
        var r = NoteReading()
        guard let parsed else { return r }
        r.propertyId = parsed.property?.id
        r.category = parsed.categoryMatched ? parsed.category : nil
        r.hours = parsed.hoursAreExplicit ? parsed.hours : nil
        r.participant = parsed.participant == .spouse ? .spouse : nil
        return r
    }

    /// A stand-in for PCC: the labelled answer, with an injected error on every third note
    /// (invented hours, a property that isn't the user's, a countable category on a
    /// non-countable note, a description that adds facts, a date phrase not in the note).
    /// What it measures is the pipeline (merge + guards), not a model.
    func pccFakeDraft(_ c: NoteEvalFixture.Case, index: Int, prompt: NoteModelPrompt) -> NoteModelDraft {
        var draft = NoteModelDraft()
        if let ref = c.property, let id = refs[ref], let i = properties.firstIndex(where: { $0.id == id }) {
            draft.propertyOption = prompt.propertyOptions[i]
        }
        draft.category = c.categoryAnyOf?.first.flatMap { NoteModelPrompt.category(forKey: $0) }
        draft.hours = c.hours
        draft.doneBySpouse = c.participant == "spouse"
        draft.description = c.note
        if index % 3 == 0 {
            switch (index / 3) % 5 {
            case 0: draft.hours = 3
            case 1: draft.propertyOption = "Sunset Villa"
            case 2: draft.category = .management
            case 3: draft.description = "Repaired the kitchen leak with the plumber"
            default: draft.datePhrase = "last Monday"; draft.doneBySpouse = true
            }
        }
        return draft
    }
}
