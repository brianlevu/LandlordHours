import SwiftUI

/// Day-1 backfill reveal (v2): the hours the 90-day look-back found, on the dusk/night page with
/// the crafted house as it stands on CONFIRMED hours only. Found hours are suggestions, so the
/// house does not grow and nothing moves on appear (§H.6); the number counts up once (`countChange`).
/// One primary "Review N suggestions", one tertiary "Skip".
struct BackfillRevealView: View {
    /// Hours found in the backfill (suggestions, not records).
    let foundHours: Double
    let suggestionCount: Int
    /// Confirmed hours already on the house (usually 0 on day 1).
    var confirmedHours: Double = 0
    /// Kept for callers that pass their scheme; the page follows the environment's appearance.
    var artScheme: ColorScheme? = nil
    /// DEBUG/capture: start at the end state.
    var startSettled = false
    /// DEBUG/capture: wait this long before the count (so a recording has no cold launch).
    var startDelay: Double = 0
    var onReview: () -> Void = {}
    var onSkip: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutBand) private var band
    @State private var shownHours: Double = 0
    @State private var heroSide: CraftHeroSide?

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var ax: Bool { dynamicTypeSize.isAccessibilitySize }
    private var stage: CraftStage { CraftStage.stage(hours: confirmedHours, goal: GoalManager.shared.houseGoal.targetHours) }
    private var side: CGFloat {
        heroSide?.side ?? CraftHeroSize.hero(windowWidth: 402, windowHeight: 874, accessibility: ax)
    }

    var body: some View {
        // The primary ends the content, never a pinned inset over it (the milestone's AX3 defect).
        GeometryReader { viewport in
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button(String(localized: "backfill.skip", defaultValue: "Skip", table: "Today"), action: onSkip)
                            .buttonStyle(LHButton.tertiary)
                            .accessibilityIdentifier("backfill-skip")
                    }
                    .padding(.horizontal, LHMetrics.gutter)
                    CraftHouseView(stage: stage, windowsLit: false, side: side, fillsStage: !ax)
                        .frame(maxWidth: .infinity)
                    VStack(spacing: 2) {
                        Text(verbatim: "\(Int(shownHours.rounded(.down)))")
                            .font(LHFont.heroNumeral(size: ax ? 54 : 84))
                            .tracking(-2)
                            .foregroundStyle(colors.textPrimary)
                            .contentTransition(.numericText(value: shownHours))
                            .accessibilityLabel(String(localized: "backfill.foundLabel",
                                                       defaultValue: "\(Int(foundHours.rounded(.down))) hours found in your calendar", table: "Today"))
                        Text(String(localized: "backfill.found", defaultValue: "hours found in your calendar", table: "Today"))
                            .font(.body)
                            .foregroundStyle(colors.textSecondary)
                            .accessibilityHidden(true)
                        Text(String(localized: "backfill.note", defaultValue: "Nothing counts until you confirm it.", table: "Today"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(colors.textPrimary)
                            .padding(.top, 8)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LHMetrics.gutter + 4)
                    .padding(.top, ax ? 0 : -44)

                    Spacer(minLength: LHMetrics.sectionGap)
                    Button(suggestionCount == 1
                           ? String(localized: "backfill.reviewOne", defaultValue: "Review 1 suggestion", table: "Today")
                           : String(localized: "backfill.review", defaultValue: "Review \(suggestionCount) suggestions", table: "Today"),
                           action: onReview)
                        .buttonStyle(LHButton.primary)
                        .padding(.horizontal, LHMetrics.gutter)
                        .padding(.bottom, 8)
                        .accessibilityIdentifier("backfill-review")
                }
                .frame(maxWidth: band == .a ? .infinity : LHMetrics.readingColumn)
                .frame(maxWidth: .infinity)
                .frame(minHeight: viewport.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { LHPage() }
        .background {
            Color.clear
                .onGeometryChange(for: CGSize.self) { proxy in
                    CGSize(width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                           height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
                } action: { size in
                    heroSide = CraftHeroSide.resolve(previous: heroSide, kind: .hero, window: size, band: band, accessibility: ax)
                }
        }
        .task { await count() }
    }

    private func count() async {
        if startSettled || reduceMotion { shownHours = foundHours; return }
        try? await Task.sleep(for: .seconds(startDelay + HouseMotion.backfillLeadIn))
        withAnimation(AppAnimation.count) { shownHours = foundHours }
    }
}

#Preview("Backfill 212h") {
    BackfillRevealView(foundHours: 212, suggestionCount: 14)
}
