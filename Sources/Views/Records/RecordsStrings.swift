import Foundation

// MARK: - Package G strings
//
// Every user-facing string in Records, the record page and Reports goes through the package
// catalog `Sources/Resources/Strings/RecordsReports.xcstrings` (table "RecordsReports"). Keys are
// `records.*`, `record.*` and `reports.*`. Format strings take arguments; nothing is concatenated.

enum RR {
    static let table = "RecordsReports"

    /// One string from the package catalog, with its English default.
    static func t(_ key: StaticString, _ value: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: value, table: table)
    }
}
