import SwiftUI

// MARK: - Package H strings
//
// Every user-facing string in Settings, the filing page, Learn's list, Export, Contact support and
// Delete all data goes through the package catalog `Sources/Resources/Strings/Settings.xcstrings`
// (table "Settings"). Keys are `settings.*`, `filing.*`, `learnList.*`, `export.*`, `support.*`,
// `delete.*`, `pdf.*`. Format strings take arguments through `HS.f`; nothing is concatenated.
// The canonical lines (`common.cpaFootnote`, `pdf.title`) live in `Localizable.xcstrings` (package A).

enum HS {
    static let table = "Settings"

    /// One string from the package catalog, with its English default.
    static func t(_ key: StaticString, _ value: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: value, table: table)
    }

    /// A format string from the package catalog (`%lld`, `%@`) filled with `args`.
    static func f(_ key: StaticString, _ format: String.LocalizationValue, _ args: CVarArg...) -> String {
        String(format: String(localized: key, defaultValue: format, table: table), arguments: args)
    }

    /// The canonical CPA footnote, `common.cpaFootnote` (standard §1.22, §C.5).
    static var cpaFootnote: String {
        String(localized: "common.cpaFootnote", defaultValue: "Your CPA decides what the numbers mean.")
    }

    /// `common.nothingCountsUntilConfirm`: "Nothing counts until you confirm it."
    static var nothingCounts: String {
        String(localized: "common.nothingCountsUntilConfirm", defaultValue: "Nothing counts until you confirm it.")
    }

    /// The canonical record title, `pdf.title` ("Rental hours record 2026"): the PDF, the CSV file
    /// name and the paywall preview share it.
    static func recordTitle(year: Int) -> String {
        String(format: String(localized: "pdf.title", defaultValue: "Rental hours record %lld"), year)
    }
}

// MARK: - Header for the long-tail screens (standard §1.14)

/// `LHScreenTitle` with the back control the tests and VoiceOver find by name. Settings goes back
/// to Today; the pushed pages (filing, Learn, Contact support, Delete all data) go back one level.
struct LongTailHeader: View {
    let title: String
    var subtitle: String? = nil
    var style: LHScreenTitle.Style = .collection
    var back: (label: String, identifier: String, action: () -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let back {
                HStack {
                    Button(action: back.action) { Image(systemName: "chevron.backward") }
                        .buttonStyle(LHButton.icon)
                        .accessibilityLabel(back.label)
                        .accessibilityIdentifier(back.identifier)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 8)
            }
            LHScreenTitle(title, subtitle: subtitle, style: style)
        }
    }
}

// MARK: - Value row for grouped lists

/// A label and its value on one row inside a grouped list (the group is the container, so no inner
/// surface): `.body` label left, `.body` `textSecondary` value right with a disclosure or menu
/// chevron. 56pt floor; at accessibility sizes the value drops under the label.
struct LongTailValueRow: View {
    enum Accessory { case disclosure, menu, none }

    let label: String
    let value: String
    var accessory: Accessory = .disclosure

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                  : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Text(label)
                .font(.body)
                .foregroundStyle(colors.textPrimary)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
                .lhWrapsText()
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            HStack(spacing: 6) {
                Text(value)
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.trailing)
                if accessory != .none {
                    Image(systemName: accessory == .menu ? "chevron.up.chevron.down" : "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(colors.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, LHRow.insets.leading)
        .padding(.vertical, LHRow.insets.top)
        .frame(maxWidth: .infinity, minHeight: LHMetrics.rowMinHeight, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
