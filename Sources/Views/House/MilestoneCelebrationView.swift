import SwiftUI

/// The milestone (100 / 500 / 750 / the goal), standard §H.5 and §B.3 `houseStageAdvance`.
///
/// The crafted house at hero size on the dusk/night page. The house's own moves come first: the
/// stage change from where it stood just under the threshold (`timberDrop` when it ends at
/// framing, else `stageFade`, chosen by `CraftHouseView`), and `windowsOn` if the windows were
/// dark. Then one milestone beat: a single confetti burst in the house palette (`HouseConfettiBeat`,
/// ≤ 24 pieces, ≤ 0.60 s, behind the chip's band, never over the number) with the Fraunces line
/// ("500 hours."), and one `.success`. No sign, no words in the scene, no linework (§H.2).
/// Tap the house to skip to the settled state. Reduce Motion: no clip, no confetti; the still
/// crossfades and the line fades in.
struct MilestoneCelebrationView: View {
    let celebration: HouseCelebration
    /// The countable hours after the save (the copy only claims a line when hours pass it).
    let hours: Double
    /// Hours were logged today (the windows end lit).
    var windowsLit = true
    /// The goal the house measures against (the stage function's denominator).
    var goalHours: Double = GoalManager.shared.houseGoal.targetHours
    var date: Date = Date()
    /// DEBUG/capture: start already settled.
    var startSettled = false
    /// DEBUG/capture: wait this long before the motion starts (so a recording has no cold launch).
    var startDelay: Double = 0
    var onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutBand) private var band

    @State private var advanced = false
    @State private var lineShown = false
    @State private var beatTick = 0
    @State private var successTick = 0
    @State private var window: CGSize = .zero
    @State private var heroSide: CraftHeroSide?
    @State private var shareImage: UIImage?

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var year: Int { Calendar.current.component(.year, from: date) }
    private var ax: Bool { dynamicTypeSize.isAccessibilitySize }

    /// Where the house stood just under the threshold, and where it stands now.
    private var beforeStage: CraftStage {
        CraftStage.stage(hours: max(0, celebration.thresholdHours - 0.5), goal: goalHours)
    }
    private var afterStage: CraftStage { CraftStage.stage(hours: max(hours, celebration.thresholdHours), goal: goalHours) }

    private var side: CGFloat {
        heroSide?.side ?? CraftHeroSize.hero(windowWidth: 402, windowHeight: 874, accessibility: ax)
    }

    var body: some View {
        // The actions end the content, never a pinned inset over it: at AX3 a pinned Continue
        // covered the detail line (gate C-1.2). The column is at least the viewport tall, so at
        // default the buttons still sit at the bottom.
        GeometryReader { viewport in
            ScrollView {
                VStack(spacing: 0) {
                    LHToastChipSlot {
                        Color.clear.frame(height: 36)
                    }
                    .padding(.top, 4)
                    ZStack(alignment: .top) {
                        CraftHouseView(stage: advanced ? afterStage : beforeStage, windowsLit: advanced ? windowsLit : false,
                                       side: side, fillsStage: !ax, dropAllowed: true,
                                       onStageSettled: { _ in scheduleBeat(after: windowsLit ? CraftMotion.windowsFade : 0) })
                        HouseConfettiBeat(trigger: beatTick, width: side, fall: side * 0.62)
                    }
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { finish(animated: true) }
                    .accessibilityIdentifier("milestone.house")

                    VStack(spacing: 6) {
                        Text(Self.title(for: celebration))
                            .font(LHFont.screenTitle(size: 34))
                            .foregroundStyle(colors.textPrimary)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                            .opacity(lineShown ? 1 : 0)
                        Text(Self.hoursLine(for: celebration, hours: hours, year: year))
                            .font(.body)
                            .foregroundStyle(colors.textSecondary)
                        Text(Self.detail(for: celebration, hours: hours))
                            .font(.subheadline)
                            .foregroundStyle(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LHMetrics.gutter + 4)
                    .padding(.top, ax ? 8 : -28)
                    .accessibilityElement(children: .combine)

                    Spacer(minLength: LHMetrics.sectionGap)
                    actions
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
                    window = size
                    heroSide = CraftHeroSide.resolve(previous: heroSide, kind: .hero, window: size, band: band, accessibility: ax)
                }
        }
        .sensoryFeedback(.success, trigger: successTick)
        .onAppear { play() }
        .task { renderShareImage() }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 4) {
            Button(String(localized: "milestone.continue", defaultValue: "Continue", table: "Today"), action: onContinue)
                .buttonStyle(LHButton.primary)
                .accessibilityIdentifier("milestone-continue")
            if let shareImage {
                let image = Image(uiImage: shareImage)
                ShareLink(item: image, preview: SharePreview(Self.hoursLine(for: celebration, hours: hours, year: year), image: image)) {
                    Label(String(localized: "milestone.share", defaultValue: "Share", table: "Today"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(LHButton.tertiary)
                .accessibilityIdentifier("milestone-share")
            }
        }
        .padding(.horizontal, LHMetrics.gutter)
        .padding(.bottom, 8)
        .frame(maxWidth: band == .a ? .infinity : LHMetrics.readingColumn)
    }

    @MainActor
    private func renderShareImage() {
        let card = HouseShareCard(celebration: celebration, hours: hours, year: year, stage: afterStage, lit: windowsLit)
            .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        shareImage = renderer.uiImage
    }

    // MARK: Motion (`houseStageAdvance`)

    /// The milestone's own `.onAppear` motion (one of the two places §B.1 allows it).
    private func play() {
        if startSettled { finish(animated: false); return }
        let lead = startDelay + HouseMotion.milestoneLeadIn
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(lead))
            guard !advanced else { return }
            advanced = true   // CraftHouseView plays the stage change and the windows
            if beforeStage == afterStage {
                scheduleBeat(after: windowsLit ? CraftMotion.windowsAfterSettle + CraftMotion.windowsFade : 0)
            }
        }
    }

    private func scheduleBeat(after delay: Double) {
        guard !lineShown else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            beat()
        }
    }

    private func beat() {
        guard !lineShown else { return }
        successTick += 1
        beatTick += 1
        withAnimation(AppAnimation.reveal) { lineShown = true }
    }

    private func finish(animated: Bool) {
        guard !(lineShown && advanced) else { return }
        var t = Transaction()
        t.disablesAnimations = !animated
        withTransaction(t) {
            advanced = true
            lineShown = true
        }
    }

    // MARK: Copy (§C: one beat, then quiet; never "qualify")

    /// The Fraunces line: "500 hours."
    static func title(for celebration: HouseCelebration) -> String {
        let n = Int(celebration.thresholdHours)
        return String(localized: "milestone.title", defaultValue: "\(n) hours.", table: "Today")
    }

    /// "502 confirmed hours in 2026": the actual whole hours, never below the threshold shown.
    static func hoursLine(for celebration: HouseCelebration, hours: Double, year: Int) -> String {
        let n = max(Int(celebration.thresholdHours), Int(hours.rounded(.down)))
        return String(localized: "milestone.hoursLine", defaultValue: "\(n) confirmed hours in \(String(year))", table: "Today")
    }

    /// Claims a line only when the hours pass it.
    static func detail(for celebration: HouseCelebration, hours: Double) -> String {
        switch celebration {
        case .stage(.foundation100):
            return hours > 100
                ? String(localized: "milestone.detail.100past", defaultValue: "Past 100 hours. That’s the line for the 100\u{2011}hour test.", table: "Today")
                : String(localized: "milestone.detail.100at", defaultValue: "The 100\u{2011}hour test needs more than 100. You’re at the line.", table: "Today")
        case .stage(.roof500):
            return hours > 500
                ? String(localized: "milestone.detail.500past", defaultValue: "Past 500 hours. That’s the line for the 500\u{2011}hour test.", table: "Today")
                : String(localized: "milestone.detail.500at", defaultValue: "The 500\u{2011}hour test needs more than 500. You’re at the line.", table: "Today")
        case .stage(.keys750):
            return String(localized: "milestone.detail.750", defaultValue: "More than 750 hours on your record.", table: "Today")
        case .goalMet(.reps750):
            return String(localized: "milestone.detail.goal750", defaultValue: "Your 750 hours are on your record.", table: "Today")
        case .goalMet(.mp500):
            return String(localized: "milestone.detail.mp500", defaultValue: "Past 500 hours. That’s the line for the 500\u{2011}hour test.", table: "Today")
        case .goalMet(.mp100):
            return String(localized: "milestone.detail.mp100", defaultValue: "Past 100 hours. The 100\u{2011}hour test also asks that no one else did more.", table: "Today")
        }
    }
}

/// The share image: the house, the number and the words on the page, no app chrome. 360pt square.
struct HouseShareCard: View {
    let celebration: HouseCelebration
    let hours: Double
    let year: Int
    var stage: CraftStage = .complete
    var lit = true

    var body: some View {
        let colors = AdaptiveColors(colorScheme: .light)
        ZStack(alignment: .topLeading) {
            LHPage()
            Image(stage.assetName(lit: lit || !CraftHouseView.hasUnlitTwin(stage)))
                .resizable()
                .scaledToFit()
                .frame(width: 300, height: 300)
                .position(x: 200, y: 200)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(max(Int(celebration.thresholdHours), Int(hours.rounded(.down))))")
                    .font(LHFont.heroNumeral(size: 56))
                    .foregroundStyle(colors.textPrimary)
                Text(String(localized: "milestone.share.caption", defaultValue: "confirmed hours in \(String(year))", table: "Today"))
                    .font(.headline)
                    .foregroundStyle(colors.textSecondary)
                Spacer()
                Text(verbatim: "Dormer")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.textSecondary)
            }
            .padding(22)
        }
        .frame(width: 360, height: 360)
        .environment(\.colorScheme, .light)
    }
}

#Preview("500h milestone") {
    MilestoneCelebrationView(celebration: .stage(.roof500), hours: 502, onContinue: {})
}
