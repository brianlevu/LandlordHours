import SwiftUI

// MARK: - LHCardLines (standard §1.1a, 2.3 amendment 3)
//
// Read-only lines inside one card: an inline glyph and a sentence per line, no dividers, nothing
// to tap (the lesson's "Usually counts / Usually doesn't" lists; Monzo and Lloyds lesson cards).
// They are lines, not rows: D1 (56–88pt) and D3 do not apply, and the gate does not measure them
// as rows. The card is the `LHRowGroup` container; lines are 14 from the card edge at the ends and
// 12 apart. A line with an action is a row (`LHRow.Browse`), never a card line.

struct LHCardLine: Identifiable, Equatable {
    enum Tint: Equatable { case positive, neutral, action }
    let id: Int
    let symbol: String
    var tint: Tint = .neutral
    let text: String
}

struct LHCardLines: View {
    let lines: [LHCardLine]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        LHRowGroup {
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: line.symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ink(line.tint, colors))
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text(line.text)
                        .font(.body)
                        .foregroundStyle(colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.top, index == 0 ? 14 : 6)
                .padding(.bottom, index == lines.count - 1 ? 14 : 6)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func ink(_ tint: LHCardLine.Tint, _ colors: AdaptiveColors) -> Color {
        switch tint {
        case .positive: return colors.positive
        case .neutral: return colors.textSecondary
        case .action: return colors.action
        }
    }
}
