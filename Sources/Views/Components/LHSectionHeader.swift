import SwiftUI

// MARK: - LHSectionHeader (standard §1.15, §1.15a) and LHFootnote (§1.22)
//
// `.headline` `textPrimary`, sentence case, the count after a middle dot ("To confirm · 7"); no
// count capsule and no drafting mono (v2). A header that names a state uses `behind` /
// `positiveOnPage` on the hero page and `caution` / `positive` on the plain canvas or in a card.
// Trailing slot: one `.tertiary`. Spacing: 24 above, 8 below (the caller's stack applies
// `LHMetrics.sectionGap` / `headerToContent`; inside a `List` section the system places it).
//
// Day headers (§1.15a): `.day` style, `.subheadline.semibold` `textSecondary`, height 28. The
// text comes from the Inbox's one day formatter (`InboxFormat.dayHeader(_:now:)`).

struct LHSectionHeader: View {
    enum Style: Equatable {
        case section
        case day
    }

    enum Tone: Equatable {
        case normal
        /// A state that needs attention ("Needs attention", "Behind").
        case attention
        /// A good state ("On pace").
        case positive
    }

    let title: String
    var count: Int? = nil
    var style: Style = .section
    var tone: Tone = .normal
    /// True on the dusk/night page (hero screens): state inks switch to the page-safe ones.
    var onPage = false
    var trailingTitle: String? = nil
    var trailingAction: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    init(_ title: String, count: Int? = nil, style: Style = .section, tone: Tone = .normal, onPage: Bool = false,
         trailingTitle: String? = nil, trailingAction: (() -> Void)? = nil) {
        self.title = title
        self.count = count
        self.style = style
        self.tone = tone
        self.onPage = onPage
        self.trailingTitle = trailingTitle
        self.trailingAction = trailingAction
    }

    /// "To confirm · 7".
    static func text(_ title: String, count: Int?) -> String {
        guard let count else { return title }
        return String(localized: "section.titleCount", defaultValue: "\(title) · \(count)", table: "Foundations",
                      comment: "Section header with a count after a middle dot, e.g. To confirm · 7")
    }

    private var ink: Color {
        if style == .day { return colors.textSecondary }
        switch tone {
        case .normal: return colors.textPrimary
        case .attention: return onPage ? colors.behind : colors.caution
        case .positive: return onPage ? colors.positiveOnPage : colors.positive
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.text(title, count: count))
                .font(style == .day ? .subheadline.weight(.semibold) : .headline)
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let trailingTitle, let trailingAction {
                Button(trailingTitle, action: trailingAction)
                    .buttonStyle(LHButton.tertiary)
            }
        }
        .frame(minHeight: style == .day ? 28 : 24)
    }
}

// MARK: - LHFootnote

/// The CPA footnote and other one-line notes: `.footnote` `textSecondary` (tertiary fails AA at 12pt
/// on the canvas), the last element of the content, at most one per screen.
struct LHFootnote: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    init(_ text: String) { self.text = text }

    /// `common.cpaFootnote`: "Your CPA decides what the numbers mean."
    static var cpa: LHFootnote {
        LHFootnote(String(localized: "common.cpaFootnote", defaultValue: "Your CPA decides what the numbers mean."))
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(AdaptiveColors(colorScheme: colorScheme).textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
