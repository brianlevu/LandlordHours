import SwiftUI

// MARK: - Learning center (2.3: lessons with progress, then the short reads)
//
// A plain page with no house. `.lhTabScreen` (collection root, back icon): a progress card
// ("1 of 3", `LHProgressBar`), "Lessons" as 56pt+ `LHRow.Browse` rows in one grouped container (a
// read lesson turns its tile into `LHRow.DoneTile` and says "Read"), "Short reads" for the older
// articles, and `learn.notAdvice` last. Words come from the `Learn` String Catalog via `LearnLibrary`;
// the page title and Back come from `Settings.xcstrings` via `HS`. Frame l5.

struct LearningCenterView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var progress = LessonProgressStore.shared
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var openedArticle: LearnArticle? = Self.launchArticle
    @State private var openLesson: LessonOpen?
    @State private var launched = false

    private var lessons: [Lesson] { LearnLibrary.lessons }
    private var readCount: Int { lessons.filter { progress.isRead($0.id) }.count }
    private var upNextIndex: Int? { lessons.firstIndex { !progress.isRead($0.id) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                progressCard
                lessonsSection
                shortReadsSection
                LHFootnote(LearnLibrary.notAdvice)
                    .accessibilityIdentifier("learn.notAdvice")
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
        .lessonSheet(open: $openLesson)
        .accessibilityIdentifier("learn.screen")
        .onAppear { openLaunchLesson() }
    }

    // MARK: Progress

    private var progressCard: some View {
        let shape = RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 2) {
            Text(LearnLibrary.format("lessons.count", readCount, lessons.count))
                .font(.largeTitle.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(colors.textPrimary)
            Text(LearnLibrary.line("lessons.caption"))
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
            LHProgressBar(value: lessons.isEmpty ? 0 : Double(readCount) / Double(lessons.count))
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LHMetrics.cardPadding)
        .background(colors.backgroundSecondary, in: shape)
        .overlay { if colorScheme == .dark { shape.strokeBorder(colors.border, lineWidth: LHMetrics.hairline) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LearnLibrary.format("lessons.a11y.progress", readCount, lessons.count))
        .accessibilityIdentifier("learn.progress")
    }

    // MARK: Lessons

    private var lessonsSection: some View {
        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            LHSectionHeader(LearnLibrary.line("lessons.section")).padding(.horizontal, 4)
            LHRowGroup {
                ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                    if index > 0 { LHDivider(leadingInset: LHRow.browseDividerInset) }
                    let read = progress.isRead(lesson.id)
                    let upNext = index == upNextIndex
                    LHRow.Browse(title: lesson.title, meta: meta(lesson, read: read, upNext: upNext),
                                 action: { LessonLauncher.open(lesson.id, into: $openLesson) }) {
                        if read {
                            LHRow.DoneTile()
                        } else {
                            LessonNumberTile(number: index + 1, emphasised: upNext)
                        }
                    }
                    .accessibilityIdentifier("lesson.row.\(lesson.id)")
                }
            }
        }
    }

    private func meta(_ lesson: Lesson, read: Bool, upNext: Bool) -> String {
        if read { return LearnLibrary.line("lessons.meta.read") }
        let line = LearnLibrary.format("lessons.meta.cards", lesson.cards.count, lesson.minutes)
        return upNext ? LearnLibrary.format("lessons.meta.upNext", line) : line
    }

    // MARK: Short reads

    private var shortReadsSection: some View {
        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            LHSectionHeader(LearnLibrary.line("lessons.shortReads")).padding(.horizontal, 4)
            LHRowGroup {
                ForEach(Array(LearnLibrary.shared.enumerated()), id: \.element.id) { index, article in
                    if index > 0 { LHDivider(leadingInset: LHRow.browseDividerInset) }
                    LHRow.Browse(title: article.title, systemImage: "book", tint: .neutral, action: { openedArticle = article })
                        .accessibilityIdentifier("learn.row.\(article.id)")
                }
            }
        }
    }

    // MARK: Launch hooks (DEBUG)

    private static var launchArticle: LearnArticle? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-LHOpenLearningArticle"), args.indices.contains(i + 1) {
            return LearnLibrary.article(id: args[i + 1])
        }
        #endif
        return nil
    }

    /// `-LHOpenLesson <lessonID>-<card 1…3>` opens that card from the list (frames, tests).
    private func openLaunchLesson() {
        #if DEBUG
        guard !launched else { return }
        launched = true
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LHOpenLesson"), args.indices.contains(i + 1) else { return }
        let parts = args[i + 1].split(separator: "-").map(String.init)
        guard let id = parts.first, LearnLibrary.lesson(id: id) != nil else { return }
        let card = (parts.dropFirst().first.flatMap(Int.init) ?? 1) - 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { LessonLauncher.open(id, card: card, into: $openLesson) }
        #endif
    }
}

/// The reading-order tile of a lesson: the action wash when it's up next, neutral otherwise. 36pt on
/// the same grid as a glyph tile; rounded semibold, tabular.
private struct LessonNumberTile: View {
    let number: Int
    var emphasised = false
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 36

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        Text(String(number))
            .font(.body.weight(.semibold))
            .fontDesign(.rounded)
            .monospacedDigit()
            .foregroundStyle(emphasised ? colors.action : colors.textSecondary)
            .frame(width: side, height: side)
            .background(emphasised ? colors.actionSurface : colors.backgroundTertiary,
                        in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Article

struct LearnArticleView: View {
    let article: LearnArticle
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(article.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    Text(paragraph)
                        .font(.body)
                        .foregroundStyle(colors.textPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, index == 0 ? -LHLeadInModifier.inset(.body, typeSize) : 0)
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
