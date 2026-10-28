import SwiftUI

// MARK: - Learning center (v2)
//
// Standard v2 (package H): a plain page with no house. `.lhTabScreen` (collection root, back icon),
// one `LHCard.Summary` header with no eyebrow, "Start here" and "All topics" as 56pt `LHRow.Browse`
// rows in one grouped container, the disclaimer last. Words come from the `Learn` String Catalog
// via `LearnLibrary`; the chrome strings come from `Settings.xcstrings` via `HS`.

struct LearningCenterView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var openedArticle: LearnArticle? = Self.launchArticle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                LHCard.Summary(
                    value: HS.f("learnList.count", "%lld short reads", LearnLibrary.shared.count),
                    label: LearnLibrary.line("learn.hero.line")
                )
                .accessibilityIdentifier("learn.hero")

                section(HS.t("learnList.start", "Start here"), articles: LearnLibrary.startHere, numbered: true)
                section(HS.t("learnList.all", "All topics"), articles: LearnLibrary.allTopics, numbered: false)

                LHFootnote(LearnLibrary.line("learn.disclaimer"))
            }
            .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .background { LHCanvas() }
        .lhTabScreen(HS.t("learnList.title", "Learning center"), back: LHBackAction(label: HS.t("common.back", "Back"), identifier: "learn.back") { dismiss() })
        .hidesAppTabBar()
        .navigationDestination(item: $openedArticle) { LearnArticleView(article: $0) }
        .accessibilityIdentifier("learn.screen")
    }

    private func section(_ title: String, articles: [LearnArticle], numbered: Bool) -> some View {
        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            LHSectionHeader(title)
            LHRowGroup {
                ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                    LHRow.Browse(title: article.title, action: { openedArticle = article }) {
                        if numbered {
                            LearnNumberTile(number: article.number)
                        } else {
                            LHRowGlyph(systemImage: "book", tint: .neutral)
                        }
                    }
                    .accessibilityIdentifier("learn.row.\(article.id)")
                    if index < articles.count - 1 { LHDivider(leadingInset: LHRow.browseDividerInset) }
                }
            }
        }
    }

    private static var launchArticle: LearnArticle? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-LHOpenLearningArticle"), args.indices.contains(i + 1) {
            return LearnLibrary.article(id: args[i + 1])
        }
        #endif
        return nil
    }
}

// MARK: - Number tile

/// The reading order of "Start here": a 36pt wash tile holding the number, the same grid as a glyph
/// tile. Rounded semibold, tabular.
private struct LearnNumberTile: View {
    let number: Int
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 36

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        Text(String(number))
            .font(.body.weight(.semibold))
            .fontDesign(.rounded)
            .monospacedDigit()
            .foregroundStyle(colors.action)
            .frame(width: side, height: side)
            .background(colors.actionSurface, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Article

struct LearnArticleView: View {
    let article: LearnArticle
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(article.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.body)
                        .foregroundStyle(colors.textPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LHDivider()
                    .padding(.top, 8)
                Text(LearnLibrary.line("learn.disclaimer"))
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(LearnLibrary.line("learn.sources"))
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .background { LHCanvas() }
        .lhDetailScreen(article.title, back: LHBackAction(label: HS.t("common.back", "Back"), identifier: "learn.article.back") { dismiss() })
        .hidesAppTabBar()
        .accessibilityIdentifier("learn.article.\(article.id)")
    }
}
