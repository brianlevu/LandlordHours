import Foundation

// MARK: - Learning center content
//
// The article list lives in `Resources/Learn/LearnArticles.json` (ids, group, paragraph count);
// every word lives in the `Learn` String Catalog (`Resources/Learn/Learn.xcstrings`) under
// `learn.<id>.title` and `learn.<id>.p<n>`. Nothing user-facing is hardcoded here.

struct LearnArticle: Identifiable, Equatable, Hashable {
    enum Group: String, Decodable { case start, all }

    let id: String
    let group: Group
    /// 1-based position inside its group ("01", "02", "03" for Start here).
    let number: Int
    let title: String
    let paragraphs: [String]
}

enum LearnLibrary {
    static let table = "Learn"
    static let manifestName = "LearnArticles"

    private struct Manifest: Decodable {
        struct Entry: Decodable {
            let id: String
            let group: LearnArticle.Group
            let paragraphs: Int
        }
        let version: Int
        let articles: [Entry]
    }

    enum LoadError: Error, Equatable {
        case missingManifest
        case unreadableManifest
        case missingString(String)
    }

    /// Loaded once from the app bundle. Empty if the resource is missing (tests catch that).
    static let shared: [LearnArticle] = (try? load()) ?? []

    static var startHere: [LearnArticle] { shared.filter { $0.group == .start } }
    static var allTopics: [LearnArticle] { shared.filter { $0.group == .all } }

    static func article(id: String) -> LearnArticle? { shared.first { $0.id == id } }

    /// Reads the manifest and resolves every string. Throws if any key has no value, so a
    /// missing translation can never show a raw key to someone.
    static func load(bundle: Bundle = .main) throws -> [LearnArticle] {
        guard let url = bundle.url(forResource: manifestName, withExtension: "json") else {
            throw LoadError.missingManifest
        }
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        } catch {
            throw LoadError.unreadableManifest
        }
        var counters: [LearnArticle.Group: Int] = [:]
        return try manifest.articles.map { entry in
            counters[entry.group, default: 0] += 1
            let title = try text("learn.\(entry.id).title", bundle: bundle)
            let paragraphs = try (1...max(1, entry.paragraphs)).map { try text("learn.\(entry.id).p\($0)", bundle: bundle) }
            return LearnArticle(id: entry.id, group: entry.group, number: counters[entry.group] ?? 1, title: title, paragraphs: paragraphs)
        }
    }

    /// One string from the Learn table. A missing key comes back as the key itself from
    /// Foundation; that is treated as an error.
    static func text(_ key: String, bundle: Bundle = .main) throws -> String {
        let value = String(localized: String.LocalizationValue(key), table: table, bundle: bundle)
        guard value != key, !value.isEmpty else { throw LoadError.missingString(key) }
        return value
    }

    /// Fixed lines on the Learning center (hero, footer). Falls back to empty, never the key.
    static func line(_ key: String) -> String { (try? text(key)) ?? "" }
}

// MARK: - Lessons (2.3)
//
// The 3-card lessons live in `Resources/Learn/Lessons.json` (ids, card kinds, how many lines each
// card has) and the `Learn` String Catalog (`lesson.<id>.title`, `lesson.<id>.c<n>.title|text|note`,
// `….yes<k>`, `….no<k>`, `….line<k>.label|value`, `….q<k>`). The words are the critic-checked text
// from the 2.3 hi-fi sandbox. Every lesson's last card is "Talk to your CPA" and ends on
// `learn.notAdvice`. Nothing user-facing is hardcoded here.

struct LessonCard: Identifiable, Equatable {
    enum Body: Equatable {
        case counts(yes: [String], no: [String])
        case lines([Line])
        case questions([String])
        case none
    }
    struct Line: Equatable { let label: String; let value: String }

    let index: Int
    let title: String
    let text: String
    let body: Body
    /// The inset note under the body. Nil when the card has none.
    let note: String?
    let noteSymbol: String
    /// The note is a template filled from the person's own log (`%1$lld` hours, `%2$@` work).
    let notePersonal: Bool

    var id: Int { index }
}

struct Lesson: Identifiable, Equatable {
    let id: String
    let title: String
    let minutes: Int
    let cards: [LessonCard]
}

extension LearnLibrary {
    static let lessonManifestName = "Lessons"

    private struct LessonManifest: Decodable {
        struct Card: Decodable {
            let body: String
            let noteSymbol: String?
            let yes: Int?
            let no: Int?
            let lines: Int?
            let questions: Int?
            let personalNote: Bool?
        }
        struct Entry: Decodable {
            let id: String
            let minutes: Int
            let cards: [Card]
        }
        let version: Int
        let lessons: [Entry]
    }

    /// Loaded once from the app bundle. Empty if the resource is missing (tests catch that).
    static let lessons: [Lesson] = (try? loadLessons()) ?? []

    static func lesson(id: String) -> Lesson? { lessons.first { $0.id == id } }

    /// Reads the lesson manifest and resolves every string. Throws on any missing key.
    static func loadLessons(bundle: Bundle = .main) throws -> [Lesson] {
        guard let url = bundle.url(forResource: lessonManifestName, withExtension: "json") else {
            throw LoadError.missingManifest
        }
        let manifest: LessonManifest
        do {
            manifest = try JSONDecoder().decode(LessonManifest.self, from: Data(contentsOf: url))
        } catch {
            throw LoadError.unreadableManifest
        }
        return try manifest.lessons.map { entry in
            let cards = try entry.cards.enumerated().map { offset, card -> LessonCard in
                let key = "lesson.\(entry.id).c\(offset + 1)"
                func all(_ stem: String, _ count: Int?) throws -> [String] {
                    try (0..<max(0, count ?? 0)).map { try text("\(key).\(stem)\($0 + 1)", bundle: bundle) }
                }
                let body: LessonCard.Body
                switch card.body {
                case "counts": body = .counts(yes: try all("yes", card.yes), no: try all("no", card.no))
                case "lines":
                    body = .lines(try (0..<max(0, card.lines ?? 0)).map {
                        LessonCard.Line(label: try text("\(key).line\($0 + 1).label", bundle: bundle),
                                        value: try text("\(key).line\($0 + 1).value", bundle: bundle))
                    })
                case "questions": body = .questions(try all("q", card.questions))
                default: body = .none
                }
                let note = card.noteSymbol == nil ? nil : try text("\(key).note", bundle: bundle)
                return LessonCard(index: offset, title: try text("\(key).title", bundle: bundle),
                                  text: try text("\(key).text", bundle: bundle), body: body, note: note,
                                  noteSymbol: card.noteSymbol ?? "chart.bar", notePersonal: card.personalNote ?? false)
            }
            return Lesson(id: entry.id, title: try text("lesson.\(entry.id).title", bundle: bundle),
                          minutes: entry.minutes, cards: cards)
        }
    }

    /// A format string from the Learn table (`%lld`, `%@`, positional `%1$lld`) filled with `args`.
    static func format(_ key: String, _ args: CVarArg..., bundle: Bundle = .main) -> String {
        guard let template = try? text(key, bundle: bundle) else { return "" }
        return String(format: template, arguments: args)
    }

    /// The canonical "General learning, not tax advice." (`learn.notAdvice`, standard §C.5). It lives
    /// in `Localizable.xcstrings`; the key is the only way to reach it.
    static var notAdvice: String {
        String(localized: "learn.notAdvice", defaultValue: "General learning, not tax advice.")
    }
}

// MARK: - The note under "Work you do yourself usually counts"

/// "Most of your 420 hours are repairs and showings." built from the person's own log: the two
/// biggest kinds of countable work, and only when together they are more than half the total.
/// Nothing is shown when the log can't say it.
enum LessonInsights {
    struct Share: Equatable { let hours: Int; let phrase: String }

    static func phrase(for category: ActivityCategory) -> String? {
        switch category {
        case .repairs: return String(localized: "lesson.work.repairs", defaultValue: "repairs", table: LearnLibrary.table)
        case .leasing: return String(localized: "lesson.work.showings", defaultValue: "showings", table: LearnLibrary.table)
        case .management: return String(localized: "lesson.work.management", defaultValue: "management", table: LearnLibrary.table)
        case .bookkeeping: return String(localized: "lesson.work.bookkeeping", defaultValue: "bookkeeping", table: LearnLibrary.table)
        case .renovations: return String(localized: "lesson.work.renovations", defaultValue: "renovations", table: LearnLibrary.table)
        case .travel: return String(localized: "lesson.work.driving", defaultValue: "driving to the rental", table: LearnLibrary.table)
        case .legal: return String(localized: "lesson.work.legal", defaultValue: "legal work", table: LearnLibrary.table)
        case .insurance: return String(localized: "lesson.work.insurance", defaultValue: "insurance claims", table: LearnLibrary.table)
        case .investing, .financing, .contractNegotiation: return nil
        }
    }

    static func share(entries: [(category: ActivityCategory, hours: Double)]) -> Share? {
        var byCategory: [ActivityCategory: Double] = [:]
        for entry in entries where entry.category.countsForREPS && entry.hours.isFinite && entry.hours > 0 {
            byCategory[entry.category, default: 0] += entry.hours
        }
        let total = byCategory.values.reduce(0, +)
        guard total >= 1 else { return nil }
        let top = byCategory.sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
        let named = top.compactMap { item in phrase(for: item.key).map { (item.key, item.value, $0) } }.prefix(2)
        guard let first = named.first else { return nil }
        let covered = named.reduce(0) { $0 + $1.1 }
        guard covered * 2 > total else { return nil }
        let words = named.count == 2 ? "\(first.2) \(and) \(named[named.startIndex + 1].2)" : first.2
        return Share(hours: Int(total.rounded(.down)), phrase: words)
    }

    private static var and: String { String(localized: "lesson.work.and", defaultValue: "and", table: LearnLibrary.table) }
}
