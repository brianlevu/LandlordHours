import SwiftUI

// MARK: - LHCard.Summary (standard §1.10) and LHTile.Stat (§1.11)
//
// Summary: `backgroundSecondary`, radius 20, padding 16, hairline in dark only. Order: value
// (`.largeTitle.rounded.bold` tabular) → label `.subheadline` `textSecondary` → optional `.footnote`
// → optional one `LHButton.secondary`, or the whole card is one press target. Ceiling 160pt at
// default. v2: no eyebrow, no illustration, no hero card (the house sits on the page, §H.1).
//
// Stat tile: two-up, 12 gutter, radius 16, padding 14. Value `.title2.rounded.bold` tabular; label
// `.caption` `textSecondary` one line; optional trend glyph. 84–96pt. Read-only or whole-tile tap.
// 2-up only in columns ≥ 440, else 1-up (§1.27).

enum LHCard {
    struct Summary: View {
        let value: String
        let label: String
        var footnote: String? = nil
        var actionTitle: String? = nil
        var action: (() -> Void)? = nil
        /// Whole-card tap (used when there is no button).
        var onTap: (() -> Void)? = nil

        @Environment(\.colorScheme) private var colorScheme
        private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

        init(value: String, label: String, footnote: String? = nil, actionTitle: String? = nil,
             action: (() -> Void)? = nil, onTap: (() -> Void)? = nil) {
            self.value = value
            self.label = label
            self.footnote = footnote
            self.actionTitle = actionTitle
            self.action = action
            self.onTap = onTap
        }

        var body: some View {
            if let onTap, action == nil {
                Button(action: onTap) { card }.buttonStyle(LHButton.press)
            } else {
                card
            }
        }

        private var card: some View {
            let shape = RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
            return VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(colors.textPrimary)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                if let footnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                        .padding(.top, 2)
                }
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(LHButton.secondary)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LHMetrics.cardPadding)
            .background(colors.backgroundSecondary, in: shape)
            .overlay { if colorScheme == .dark { shape.strokeBorder(colors.border, lineWidth: LHMetrics.hairline) } }
            .accessibilityElement(children: .combine)
        }
    }
}

enum LHTile {
    struct Stat: View {
        enum Trend: Equatable { case up, down, flat }

        let value: String
        let label: String
        var trend: Trend? = nil
        var onTap: (() -> Void)? = nil

        @Environment(\.colorScheme) private var colorScheme
        private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

        init(value: String, label: String, trend: Trend? = nil, onTap: (() -> Void)? = nil) {
            self.value = value
            self.label = label
            self.trend = trend
            self.onTap = onTap
        }

        var body: some View {
            if let onTap {
                Button(action: onTap) { tile }.buttonStyle(LHButton.press)
            } else {
                tile
            }
        }

        private var trendSymbol: String? {
            switch trend {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .flat: return "arrow.right"
            case nil: return nil
            }
        }

        private var tile: some View {
            let shape = RoundedRectangle(cornerRadius: LHMetrics.tileRadius, style: .continuous)
            return VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(value)
                        .font(.title2.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(colors.textPrimary)
                        .contentTransition(.numericText())
                    if let trendSymbol {
                        Image(systemName: trendSymbol)
                            .font(.subheadline)
                            .foregroundStyle(colors.textSecondary)
                            .accessibilityHidden(true)
                    }
                }
                Text(label)
                    .font(.caption)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(14)
            .background(colors.backgroundSecondary, in: shape)
            .overlay { if colorScheme == .dark { shape.strokeBorder(colors.border, lineWidth: LHMetrics.hairline) } }
            .accessibilityElement(children: .combine)
        }
    }

    /// Two-up when the column is ≥ 440pt wide (and not at accessibility sizes), else one-up; 12 gutter.
    struct StatGrid<Content: View>: View {
        @ViewBuilder var content: Content
        @State private var width: CGFloat = 0
        @Environment(\.dynamicTypeSize) private var typeSize

        init(@ViewBuilder content: () -> Content) { self.content = content() }

        static func columns(width: CGFloat, accessibility: Bool) -> Int { (width >= 440 && !accessibility) ? 2 : 1 }

        var body: some View {
            let n = Self.columns(width: width, accessibility: typeSize.isAccessibilitySize)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: n), spacing: 12) {
                content
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
    }
}
