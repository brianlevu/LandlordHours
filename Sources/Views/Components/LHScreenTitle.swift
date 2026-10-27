import SwiftUI

// MARK: - LHScreenTitle (standard §1.14)
//
// Two cases a screen chooses from, plus the sheet title:
//   .collection  tab roots and "See all" collection roots: Fraunces 34/500 (relative to
//                .largeTitle), optional one-line `.subheadline` `textSecondary` subtitle. A pushed
//                collection root shows a back `.icon` in the leading slot.
//   .detail      a pushed screen about one item (a rental, a record): SF `.title1.semibold`.
//   .sheet       sheet headers: SF `.title2.semibold`, a date or context as the `.subheadline`
//                subtitle ("Today, Thu Oct 22"). No eyebrow anywhere (v2).
// Gutter 20, 8 below, one trailing `.icon` at most, never a "+" (the create action is the fifth tab).

struct LHScreenTitle: View {
    enum Style: Equatable {
        case collection
        case detail
        case sheet
    }

    let title: String
    var subtitle: String? = nil
    var style: Style = .collection
    var back: (() -> Void)? = nil
    var trailingSymbol: String? = nil
    var trailingLabel: String? = nil
    var trailingAction: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    init(_ title: String, subtitle: String? = nil, style: Style = .collection, back: (() -> Void)? = nil,
         trailingSymbol: String? = nil, trailingLabel: String? = nil, trailingAction: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.back = back
        self.trailingSymbol = trailingSymbol
        self.trailingLabel = trailingLabel
        self.trailingAction = trailingAction
    }

    private var ax: Bool { typeSize.isAccessibilitySize }

    @ViewBuilder private var trailing: some View {
        if let trailingSymbol, let trailingAction {
            Button(action: trailingAction) { Image(systemName: trailingSymbol) }
                .buttonStyle(LHButton.icon)
                .accessibilityLabel(trailingLabel ?? "")
        }
    }

    private var titleFont: Font {
        switch style {
        case .collection: return LHFont.screenTitle()
        case .detail: return .title.weight(.semibold)
        case .sheet: return .title2.weight(.semibold)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if back != nil || (ax && trailingSymbol != nil) {
                HStack {
                    if let back {
                        Button(action: back) { Image(systemName: "chevron.backward") }
                            .buttonStyle(LHButton.icon)
                            .accessibilityLabel(String(localized: "title.back", defaultValue: "Back", table: "Foundations"))
                    }
                    Spacer(minLength: 0)
                    // At AX sizes the trailing icon moves up here so the title keeps the full width.
                    if ax { trailing }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(titleFont)
                        .foregroundStyle(colors.textPrimary)
                        // A collection title is one or two words; at AX it shrinks before it would
                        // break a word (Fraunces 34 at AX3 is wider than the screen for "Components").
                        .lineLimit(style == .collection ? 1 : nil)
                        .minimumScaleFactor(style == .collection ? 0.6 : 1)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(colors.textSecondary)
                            .lineLimit(typeSize >= .xxLarge ? nil : 1) // two or more lines from XXL: never a mid-word cut
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !ax { trailing }
            }
        }
        .padding(.bottom, LHMetrics.headerToContent)
    }
}
