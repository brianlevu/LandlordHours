import SwiftUI

/// The Blueprint house at hero size. Shows the keyframe for the current countable hours, built
/// pass under tinted linework, and crossfades between keyframes when hours change. A confirm that
/// adds hours plays the board sequence (when the house has a course for it to land on), fires a
/// light haptic at settle, then updates the keyframe. Reduce Motion: no board, instant swap.
///
/// One accessibility element: hours, goal and next milestone in words. The layers are hidden.
struct HouseHeroView: View {
    let progress: HouseProgress
    var canvas: HouseCanvas = .blueprintHero
    /// Off for static uses (thumbnails, share images): changes swap or crossfade, no board.
    var animatesConfirms = true
    /// Called after a confirm settles, once per milestone crossed (lowest first).
    var onMilestone: (HouseMilestone) -> Void = { _ in }
    /// DEBUG/capture: show this board frame statically over the house.
    var debugConfirmStill: Int? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownKeyframe: HouseKeyframe?
    @State private var boardRun: UUID?
    @State private var boardOpacity = 1.0
    @State private var settleTick = 0
    @State private var pending: Pending?

    private struct Pending {
        let target: HouseKeyframe
        let transition: HouseKeyframeTransition
        let milestones: [HouseMilestone]
    }

    private var current: HouseKeyframe { shownKeyframe ?? progress.keyframe }

    var body: some View {
        ZStack {
            HouseArtView(keyframe: current, canvas: canvas)
                .id(current)
                .transition(.opacity)
            if boardRun != nil || debugConfirmStill != nil {
                ConfirmBuildAnimation(runID: boardRun, stillFrame: debugConfirmStill, onSettle: settle)
                    .opacity(boardOpacity)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { if shownKeyframe == nil { shownKeyframe = progress.keyframe } }
        .onChange(of: progress.hours) { old, new in handleChange(from: old, to: new) }
        .sensoryFeedback(.impact(weight: .light), trigger: settleTick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.accessibilityLabel)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("house-hero")
    }

    private func handleChange(from old: Double, to new: Double) {
        let target = HouseProgress.keyframe(for: new)
        let crossed = HouseProgress.milestonesCrossed(from: old, to: new)
        guard animatesConfirms else {
            apply(HouseMotion.keyframeTransition(from: current, to: target, reduceMotion: reduceMotion), target)
            return
        }
        switch HouseMotion.confirmPlan(oldHours: old, newHours: new, reduceMotion: reduceMotion) {
        case .none:
            apply(.instant, target)
        case .instantSwap:
            apply(.instant, target)
            settleTick += 1
            crossed.forEach(onMilestone)
        case .crossfadeOnly(let transition):
            apply(transition, target)
            settleTick += 1
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(HouseMotion.keyframeCrossfade * 1_000_000_000))
                crossed.forEach(onMilestone)
            }
        case .boardSequence(_, _, let transition):
            pending = Pending(target: target, transition: transition, milestones: crossed)
            boardOpacity = 1
            boardRun = UUID()
        }
    }

    private func settle() {
        settleTick += 1
        guard let pending else { return }
        self.pending = nil
        apply(pending.transition, pending.target)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(HouseMotion.keyframeCrossfade * 1_000_000_000))
            withAnimation(.easeIn(duration: HouseMotion.boardFadeOut)) { boardOpacity = 0 }
            try? await Task.sleep(nanoseconds: UInt64(HouseMotion.boardFadeOut * 1_000_000_000))
            boardRun = nil
            pending.milestones.forEach(onMilestone)
        }
    }

    private func apply(_ transition: HouseKeyframeTransition, _ target: HouseKeyframe) {
        switch transition {
        case .instant:
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { shownKeyframe = target }
        case .crossfade(let duration):
            withAnimation(.easeInOut(duration: duration)) { shownKeyframe = target }
        }
    }
}

/// The Today hero card on blueprint paper, ported from the approved sandbox layout
/// (DesignSandbox/BlueprintScreens.swift `BlueprintHero`): the number column on the left, the
/// house on the right two-thirds. Integration into DashboardView happens after WP-D merges.
struct HouseHeroCard: View {
    let progress: HouseProgress
    var year: Int = Calendar.current.component(.year, from: Date())
    /// Pace words from the caller ("On pace, 18h ahead"); nil hides the line.
    var status: String? = nil
    var onMilestone: (HouseMilestone) -> Void = { _ in }
    var debugConfirmStill: Int? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            HouseBlueprintPaper()
            GeometryReader { g in
                let houseSize = min(g.size.height * 0.96, g.size.width * 0.6)
                let columnWidth = max(0, g.size.width - houseSize - 16)
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(String(year)) · \(progress.goal.eyebrow)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .textCase(.uppercase)
                            .tracking(1.3)
                            .foregroundStyle(HouseTokens.drafting)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text("\(progress.wholeHours)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(HouseTokens.onHeroPrimary)
                            .contentTransition(.identity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.top, 2)
                        Text("of \(Int(progress.goal.targetHours))h")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(HouseTokens.onHeroSecondary)
                        Spacer(minLength: 8)
                        if let status {
                            Text(status)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(HouseTokens.positiveOnHero)
                                .lineLimit(2)
                        }
                        Text(progress.stage.spokenName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HouseTokens.onHeroPrimary)
                            .lineLimit(2)
                        Text(progress.nextMilestoneLabel)
                            .font(.footnote)
                            .foregroundStyle(HouseTokens.onHeroSecondary)
                            .lineLimit(2)
                    }
                    .frame(width: columnWidth, alignment: .leading)
                    .padding(.leading, 20)
                    .padding(.vertical, 20)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityElement(children: .combine)

                    HouseHeroView(progress: progress, canvas: .blueprintHero, onMilestone: onMilestone, debugConfirmStill: debugConfirmStill)
                        .frame(width: houseSize, height: houseSize)
                        .position(x: g.size.width - houseSize / 2, y: g.size.height - houseSize / 2 + 2)
                }
            }
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: HouseTokens.blueprint.opacity(0.25), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("house-hero-card")
    }
}

#Preview("Hero · 212h REPS") {
    HouseHeroCard(progress: HouseProgress(hours: 212, goal: .reps750), status: "On pace, 18h ahead")
        .padding(20)
        .background(HouseTokens.canvas(.light))
}

#Preview("Hero · 680h dark") {
    HouseHeroCard(progress: HouseProgress(hours: 680, goal: .reps750))
        .padding(20)
        .background(HouseTokens.canvas(.dark))
        .preferredColorScheme(.dark)
}

#Preview("House on a card") {
    HouseHeroView(progress: HouseProgress(hours: 120, goal: .mp500), canvas: .card)
        .frame(width: 240, height: 240)
        .padding()
        .background(HouseTokens.card(.light))
}
