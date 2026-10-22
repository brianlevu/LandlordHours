import SwiftUI

// MARK: - Learning center (2.0)
//
// Sandbox `S2Learn` (spec §5 Learn, frames learn-* / learn-article-*): a Fraunces title, the
// blueprint hero with the house at its roof stage, "Start here" with mono numerals, "All topics"
// as a plain list. No photos, no badges, no icons beyond chevrons. Words come from the `Learn`
// String Catalog via `LearnLibrary`.

struct LearningCenterView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var openedArticle: LearnArticle? = Self.launchArticle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Learning center")
                        .lhDisplayFont(.largeTitle)
                        .foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    hero
                }

                VStack(alignment: .leading, spacing: 10) {
                    LearnSectionHeader("Start here")
                    VStack(spacing: 0) {
                        let start = LearnLibrary.startHere
                        ForEach(Array(start.enumerated()), id: \.element.id) { index, article in
                            Button { openedArticle = article } label: { StartRow(article: article) }
                                .buttonStyle(.lhPressable)
                                .accessibilityIdentifier("learn.row.\(article.id)")
                            if index < start.count - 1 { PropertyInsetDivider(leading: 54) }
                        }
                    }
                    .propertyCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    LearnSectionHeader("All topics")
                    VStack(spacing: 0) {
                        let all = LearnLibrary.allTopics
                        ForEach(Array(all.enumerated()), id: \.element.id) { index, article in
                            Button { openedArticle = article } label: { TopicRow(article: article) }
                                .buttonStyle(.lhPressable)
                                .accessibilityIdentifier("learn.row.\(article.id)")
                            if index < all.count - 1 { PropertyInsetDivider() }
                        }
                    }
                    .propertyCard()
                }

                Text(LearnLibrary.line("learn.disclaimer"))
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .background(colors.background.ignoresSafeArea())
        // Solid canvas bar: scrolled content (the blueprint hero) never meets the clock.
        .toolbarBackground(colors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .hidesAppTabBar()
        .navigationDestination(item: $openedArticle) { LearnArticleView(article: $0) }
        .accessibilityIdentifier("learn.screen")
    }

    /// Blueprint paper with the house at its roof stage. At accessibility sizes the house drops
    /// out so the words get the whole card.
    private var hero: some View {
        let showsHouse = !dynamicTypeSize.isAccessibilitySize
        return ZStack(alignment: .topLeading) {
            InboxBlueprintPaper(cornerRadius: 24)
            if showsHouse {
                HouseArtView(keyframe: .k12_roof, canvas: .blueprintHero)
                    .frame(width: 150, height: 150)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 2)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(LearnLibrary.line("learn.hero.eyebrow"))
                    .font(AppTypography.drafting)
                    .textCase(.uppercase)
                    .tracking(1.3)
                    .foregroundStyle(HouseTokens.drafting)
                Text(LearnLibrary.line("learn.hero.line"))
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: showsHouse ? 190 : .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(minHeight: 150)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("learn.hero")
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

// MARK: - Rows

private struct StartRow: View {
    let article: LearnArticle
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let numeral = Text(verbatim: String(format: "%02d", article.number))
            .font(.system(.footnote, design: .monospaced, weight: .medium))
            .foregroundStyle(colors.draftingInk)
        let title = Text(article.title)
            .font(.body.weight(.semibold))
            .foregroundStyle(colors.textPrimary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 14) {
            // At accessibility sizes the numeral sits above the title so the title keeps the width.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { numeral; title }
            } else {
                numeral.frame(minWidth: 24, alignment: .leading)
                title
            }
            Spacer(minLength: 8)
            LearnChevron()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct TopicRow: View {
    let article: LearnArticle
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        HStack(spacing: 12) {
            Text(article.title)
                .font(.body)
                .foregroundStyle(colors.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            LearnChevron()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct LearnChevron: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AdaptiveColors(colorScheme: colorScheme).textTertiary)
            .accessibilityHidden(true)
    }
}

/// The one section header style: 13 semibold caps, +0.3 tracking, secondary text.
struct LearnSectionHeader: View {
    let title: LocalizedStringKey
    @Environment(\.colorScheme) private var colorScheme

    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.3)
            .foregroundStyle(AdaptiveColors(colorScheme: colorScheme).textSecondary)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Article

struct LearnArticleView: View {
    let article: LearnArticle
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                eyebrow
                    .font(AppTypography.drafting)
                    .textCase(.uppercase)
                    .tracking(1.3)
                    .foregroundStyle(colors.draftingInk)
                Text(article.title)
                    .lhDisplayFont(.title)
                    .foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("learn.article.title")
                ForEach(Array(article.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.body)
                        .foregroundStyle(colors.textPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Rectangle()
                    .fill(colors.border)
                    .frame(height: 0.5)
                    .padding(.top, 8)
                    .accessibilityHidden(true)
                Text(LearnLibrary.line("learn.disclaimer"))
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(LearnLibrary.line("learn.sources"))
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .background(colors.background.ignoresSafeArea())
        // Solid canvas bar: scrolled content (the blueprint hero) never meets the clock.
        .toolbarBackground(colors.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .hidesAppTabBar()
        .accessibilityIdentifier("learn.article.\(article.id)")
    }

    @ViewBuilder private var eyebrow: some View {
        let numeral = String(format: "%02d", article.number)
        switch article.group {
        case .start: Text("\(numeral) · Start here")
        case .all: Text("All topics")
        }
    }
}
