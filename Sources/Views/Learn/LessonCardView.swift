import SwiftUI

// MARK: - One lesson card (2.3, package C; frames l2–l4, l6–l11)
//
// Fraunces 28 title, a `.body` line in secondary ink, then one body block: a counts list
// (`LHCardLines`), value lines, or numbered questions. An inset note sits under it. The last card of a
// lesson ends on `learn.notAdvice` (standard §C.5).

struct LessonCardView: View {
    let card: LessonCard
    let isLast: Bool
    /// The filled-in note for a personal card (nil = hide the note).
    var personalNote: String? = nil

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var noteText: String? { card.notePersonal ? personalNote : card.note }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(card.title)
                .font(LHFont.screenTitle(size: 28))
                .foregroundStyle(colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("lesson.card.title")
            Text(card.text)
                .font(.body)
                .foregroundStyle(colors.textSecondary)
                .lineSpacing(2)
                .padding(.top, 12)
            bodyContent
                .padding(.top, LHMetrics.sectionGap)
            if let note = noteText {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: card.noteSymbol)
                        .font(.body)
                        .foregroundStyle(colors.action)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(LHMetrics.cardPadding)
                .background(colors.actionSurface, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                .padding(.top, 16)
                .accessibilityIdentifier("lesson.card.note")
            }
            if isLast {
                LHFootnote(LearnLibrary.notAdvice)
                    .padding(.top, LHMetrics.sectionGap)
                    .accessibilityIdentifier("lesson.notAdvice")
            }
        }
        .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lesson.card.\(card.index + 1)")
    }

    @ViewBuilder private var bodyContent: some View {
        switch card.body {
        case .counts(let yes, let no):
            VStack(alignment: .leading, spacing: 16) {
                list(LearnLibrary.line("lesson.usuallyCounts"), items: yes, symbol: "checkmark", tint: .positive)
                list(LearnLibrary.line("lesson.usuallyDoesnt"), items: no, symbol: "xmark", tint: .neutral)
            }
        case .lines(let lines):
            VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
                if card.isExample {
                    Text(LearnLibrary.line("lesson.example"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.textSecondary)
                        .padding(.horizontal, 4)
                        .accessibilityIdentifier("lesson.card.example")
                }
                LHRowGroup {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        if index > 0 { LHDivider(leadingInset: 16) }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                label(line.label)
                                Spacer(minLength: 8)
                                value(line.value).multilineTextAlignment(.trailing)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                label(line.label)
                                value(line.value)
                            }
                        }
                        .padding(LHRow.insets)
                        .frame(minHeight: LHMetrics.rowMinHeight)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        case .questions(let questions):
            LHRowGroup {
                ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                    if index > 0 { LHDivider(leadingInset: LHRow.browseDividerInset) }
                    HStack(spacing: 12) {
                        QuestionNumberTile(number: index + 1)
                        Text(question)
                            .font(.body)
                            .foregroundStyle(colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(LHRow.insets)
                    .frame(minHeight: LHMetrics.rowMinHeight)
                    .accessibilityElement(children: .combine)
                }
            }
        case .none:
            EmptyView()
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.body).foregroundStyle(colors.textSecondary)
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.body.weight(.semibold))
            .fontDesign(.rounded)
            .monospacedDigit()
            .foregroundStyle(colors.textPrimary)
    }

    private func list(_ title: String, items: [String], symbol: String, tint: LHCardLine.Tint) -> some View {
        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            Text(title)
                .font(.headline)
                .foregroundStyle(colors.textPrimary)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            LHCardLines(lines: items.enumerated().map { LHCardLine(id: $0.offset, symbol: symbol, tint: tint, text: $0.element) })
        }
    }
}

/// The number tile of a question: the Learning center's tile, 36pt on the same grid as a glyph tile.
private struct QuestionNumberTile: View {
    let number: Int
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 36

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        Text(String(number))
            .font(.body.weight(.semibold))
            .fontDesign(.rounded)
            .foregroundStyle(colors.action)
            .frame(width: side, height: side)
            .background(colors.actionSurface, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}
