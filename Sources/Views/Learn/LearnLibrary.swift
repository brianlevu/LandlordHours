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
