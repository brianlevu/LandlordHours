import SwiftUI

/// Day-1 backfill reveal (concept §1, "Day-1 backfill"): the blueprint house sketches in, then the
/// hours found in the calendar build it HATCHED, never solid, with "Nothing is saved until you
/// confirm". Done in at most 2.5 s (HouseMotion.backfillTotalDuration), skippable at any time.
/// A light tap per 50 found hours. Reduce Motion: the static hatched end state.
struct BackfillRevealView: View {
    /// Hours found in the backfill (suggestions, not records).
    let foundHours: Double
    let suggestionCount: Int
    /// Confirmed hours already on the house (usually 0 on day 1).
    var confirmedHours: Double = 0
    var artScheme: ColorScheme? = nil
    /// DEBUG/capture: start at the end state.
    var startSettled = false
    var onReview: () -> Void = {}
    var onSkip: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var environmentScheme
    @State private var sketch: CGFloat = 0
    @State private var hatch: CGFloat = 0
    @State private var shownHours: Double = 0
    @State private var hapticTick = 0
    @State private var finished = false

    private var hatchedKeyframe: HouseKeyframe { HouseProgress.keyframe(for: confirmedHours + foundHours) }
    private var confirmedKeyframe: HouseKeyframe { HouseProgress.keyframe(for: confirmedHours) }

    var body: some View {
        ZStack {
            HouseBlueprintPaper().ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { finished ? onSkip() : settle() }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HouseTokens.onHeroPrimary)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("backfill-skip")
                }
                .padding(.horizontal, 20)

                Text("Looking back 90 days")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .textCase(.uppercase)
                    .tracking(1.3)
                    .foregroundStyle(HouseTokens.drafting)
                    .padding(.top, 8)
                Text("\(Int(shownHours.rounded(.down)))h found")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(HouseTokens.onHeroPrimary)
                    .contentTransition(.numericText(value: shownHours))
                    .padding(.top, 6)
                    .accessibilityLabel("\(Int(foundHours.rounded(.down))) hours found from your calendar")
                Text("from your calendar")
                    .font(.title3)
                    .foregroundStyle(HouseTokens.onHeroSecondary)
                    .accessibilityHidden(true)

                house
                    .frame(width: 320, height: 320)
                    .padding(.top, 12)

                Text("Nothing is saved until you confirm.")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HouseTokens.onHeroPrimary)
                    .padding(.top, 4)
                Text("Hatched floors are suggestions. They turn solid only when you say they were work.")
                    .font(.subheadline)
                    .foregroundStyle(HouseTokens.onHeroSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 36)
                    .padding(.top, 4)
                Spacer(minLength: 12)
                Button(action: onReview) {
                    Text(suggestionCount == 1 ? "Review 1 suggestion" : "Review \(suggestionCount) suggestions")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HouseTokens.blueprint)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .accessibilityIdentifier("backfill-review")
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTick)
        .preferredColorScheme(.dark)
        .task { await play() }
    }

    @ViewBuilder
    private var house: some View {
        ZStack {
            // Ground and anything already confirmed stay solid; the linework sketches in over it.
            Image(decorative: confirmedKeyframe.builtImageName)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
            HouseHatchedView(keyframe: hatchedKeyframe, subtracting: confirmedKeyframe)
                .mask(HouseRisingMask(progress: hatch))
            HouseLineworkView(keyframe: confirmedKeyframe)
                .mask(HouseRisingMask(progress: sketch, feather: 0.02))
        }
        .environment(\.colorScheme, artScheme ?? environmentScheme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Blueprint house. \(Int(foundHours.rounded(.down))) found hours drawn as hatched suggestions, not saved.")
        .accessibilityAddTraits(.isImage)
    }

    private func play() async {
        if startSettled || reduceMotion { settle(animated: false); return }
        let ns: (Double) -> UInt64 = { UInt64($0 * 1_000_000_000) }
        try? await Task.sleep(nanoseconds: ns(HouseMotion.backfillLeadIn))
        if finished { return }
        withAnimation(.easeOut(duration: HouseMotion.backfillSketchDuration)) { sketch = 1 }
        try? await Task.sleep(nanoseconds: ns(HouseMotion.backfillHatchDelay))
        if finished { return }
        withAnimation(.easeInOut(duration: HouseMotion.backfillHatchDuration)) { hatch = 1 }
        let steps = 20
        let stepTime = HouseMotion.backfillHatchDuration / Double(steps)
        var lastBucket = 0
        for step in 1...steps {
            if finished { return }
            let value = foundHours * Double(step) / Double(steps)
            withAnimation(.linear(duration: stepTime)) { shownHours = value }
            let bucket = Int(value / HouseMotion.backfillHapticStepHours)
            if bucket > lastBucket { lastBucket = bucket; hapticTick += 1 }
            try? await Task.sleep(nanoseconds: ns(stepTime))
        }
        finished = true
    }

    private func settle(animated: Bool = true) {
        let apply = {
            sketch = 1
            hatch = 1
            shownHours = foundHours
            finished = true
        }
        if animated && !reduceMotion {
            withAnimation(.easeOut(duration: HouseMotion.reducedCrossfade)) { apply() }
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { apply() }
        }
    }
}

#Preview("Backfill 212h") {
    BackfillRevealView(foundHours: 212, suggestionCount: 14)
}
