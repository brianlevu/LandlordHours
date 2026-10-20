import SwiftUI

/// The Blueprint house at hero size. Shows the keyframe for the current countable hours, built
/// pass under tinted linework, and crossfades between keyframes when hours change.
///
/// A confirm that adds hours: a timber beam flies into the house (~180 ms), lands on the newest
/// course with a warm glow pulse and a light haptic; if the hours cross a keyframe the house
/// crossfades to it (through the board sequence when the new keyframe is a siding course). The
/// house only ever grows. Reduce Motion: no beam, board or pulse; the keyframe swaps in place.
///
/// One accessibility element: hours, goal and next step in words. The layers are hidden.
struct HouseHeroView: View {
    let progress: HouseProgress
    var canvas: HouseCanvas = .blueprintHero
    /// Off for static uses (thumbnails, share images): changes swap in place, no beam.
    var animatesConfirms = true
    /// Where the beam starts, in this view's coordinates (e.g. the hero number). nil = above-left.
    var beamOrigin: CGPoint? = nil
    /// Called when the beam lands (or at once without motion), so the caller can count up.
    var onLand: (HouseConfirmPlan) -> Void = { _ in }
    /// Called after a confirm settles with the celebration it earned (the highest one), if any.
    var onCelebration: (HouseCelebration) -> Void = { _ in }
    /// DEBUG/capture: show this board frame statically over the house (registered position).
    var debugConfirmStill: Int? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownKeyframe: HouseKeyframe?
    @State private var boardRun: UUID?
    @State private var boardOffset: CGFloat = 0
    @State private var boardOpacity = 1.0
    @State private var settleTick = 0
    @State private var glow = 0.0
    @State private var glowAnchor = CGPoint(x: 0.5, y: 0.6)
    @State private var beam: Beam?
    @State private var pendingBoard: (target: HouseKeyframe, transition: HouseKeyframeTransition)?

    private struct Beam: Equatable {
        var position: CGPoint
        var scale: CGFloat = 1
        var opacity: Double = 1
        var label: String
    }

    private var current: HouseKeyframe { shownKeyframe ?? progress.keyframe }

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack(alignment: .topLeading) {
                HouseArtView(keyframe: current, canvas: canvas)
                    .frame(width: s, height: s)
                    .id(current)
                    .transition(.opacity)
                if boardRun != nil || debugConfirmStill != nil {
                    ConfirmBuildAnimation(runID: boardRun, stillFrame: debugConfirmStill, onSettle: boardSettled)
                        .frame(width: s, height: s)
                        .offset(y: boardOffset * s)
                        .opacity(boardOpacity)
                }
                Capsule()
                    .fill(RadialGradient(colors: [HouseTokens.window, HouseTokens.window.opacity(0)], center: .center, startRadius: 0, endRadius: s * 0.26))
                    .frame(width: s * 0.56, height: s * 0.13)
                    .blur(radius: 5)
                    .blendMode(.plusLighter)
                    .position(x: glowAnchor.x * s, y: glowAnchor.y * s)
                    .opacity(glow)
                    .allowsHitTesting(false)
                if let beam {
                    HouseBeam(label: beam.label)
                        .scaleEffect(beam.scale)
                        .rotationEffect(.degrees(-6))
                        .position(beam.position)
                        .opacity(beam.opacity)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: s, height: s)
            .onChange(of: progress.hours) { old, new in handleChange(from: old, to: new, size: s) }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { if shownKeyframe == nil { shownKeyframe = progress.keyframe } }
        .sensoryFeedback(.impact(weight: .light), trigger: settleTick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.accessibilityLabel)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("house-hero")
    }

    // MARK: Confirm choreography

    private func handleChange(from old: Double, to new: Double, size s: CGFloat) {
        let plan = HouseMotion.confirmPlan(oldHours: old, newHours: new, reduceMotion: reduceMotion || !animatesConfirms)
        let celebration = HouseProgress.celebrations(from: old, to: new, goal: progress.goal).last
        guard plan.beam else {
            apply(plan.keyframe, plan.target)
            onLand(plan)
            if new > old { settleTick += 1 }
            if let celebration { onCelebration(celebration) }
            return
        }
        let ns: (Double) -> UInt64 = { UInt64($0 * 1_000_000_000) }
        Task { @MainActor in
            // 1. The beam flies from the number into the house.
            let origin = beamOrigin ?? CGPoint(x: -s * 0.1, y: s * 0.1)
            let target = CGPoint(x: plan.anchor.x * s, y: plan.anchor.y * s)
            beam = Beam(position: origin, label: Self.deltaLabel(new - old))
            withAnimation(.spring(response: HouseMotion.beamSpringResponse, dampingFraction: HouseMotion.beamSpringDamping)) {
                beam?.position = target
            }
            try? await Task.sleep(nanoseconds: ns(HouseMotion.beamFlight + 0.04))

            // 2. Landing: the number counts up, the course glows, the beam is absorbed.
            onLand(plan)
            glowAnchor = plan.anchor
            withAnimation(.easeOut(duration: HouseMotion.glowIn)) { glow = 1 }
            withAnimation(.easeIn(duration: 0.18)) {
                beam?.scale = 0.3
                beam?.opacity = 0
            }
            if let offset = plan.boardOffset {
                // 3a. The board slides onto the new course, then becomes the new keyframe.
                pendingBoard = (plan.target, plan.keyframe)
                boardOffset = offset
                boardOpacity = 1
                boardRun = UUID()
            } else {
                // 3b. The house grows (crossfade) if a keyframe was crossed; haptic now.
                apply(plan.keyframe, plan.target)
                settleTick += 1
            }
            try? await Task.sleep(nanoseconds: ns(HouseMotion.glowIn))
            withAnimation(.easeOut(duration: HouseMotion.glowOut)) { glow = 0 }
            try? await Task.sleep(nanoseconds: ns(0.1))
            beam = nil
            let rest = plan.boardOffset != nil ? HouseMotion.confirmSequenceDuration + HouseMotion.keyframeCrossfade : HouseMotion.keyframeCrossfade
            try? await Task.sleep(nanoseconds: ns(rest))
            if let celebration { onCelebration(celebration) }
        }
    }

    private func boardSettled() {
        settleTick += 1
        guard let pending = pendingBoard else { return }
        pendingBoard = nil
        apply(pending.transition, pending.target)
        withAnimation(.easeIn(duration: HouseMotion.keyframeCrossfade)) { boardOpacity = 0 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(HouseMotion.keyframeCrossfade * 1_000_000_000))
            boardRun = nil
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

    /// "+2h", "+1.5h", "+15m".
    static func deltaLabel(_ hours: Double) -> String {
        if hours < 1 { return "+\(max(1, Int((hours * 60).rounded())))m" }
        let rounded = (hours * 10).rounded() / 10
        return rounded == rounded.rounded() ? "+\(Int(rounded))h" : "+\(String(format: "%.1f", rounded))h"
    }
}

/// The confirm beam: a timber clapboard with grain and nail heads, and the hours tag above it.
struct HouseBeam: View {
    let label: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(LinearGradient(colors: [HouseTokens.timberLight, HouseTokens.timber, HouseTokens.timberDark], startPoint: .top, endPoint: .bottom))
            HStack {
                Circle().fill(HouseTokens.nail).frame(width: 3, height: 3)
                Spacer()
                Circle().fill(HouseTokens.nail).frame(width: 3, height: 3)
            }
            .padding(.horizontal, 6)
        }
        .frame(width: 72, height: 12)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
        .overlay(alignment: .top) {
            Text(label)
                .font(.caption.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(HouseTokens.blueprint)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Color.white, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                .fixedSize()
                .offset(y: -26)
        }
        .accessibilityHidden(true)
    }
}

/// How the hero's status line reads: met/on pace, behind, or nothing to judge yet. Colour is
/// never the only signal; positive and caution also carry a glyph.
enum HouseStatusTone: Equatable, Sendable {
    case positive, caution, neutral
}

/// The Today hero card on blueprint paper, ported from the approved sandbox/concept layout: the
/// number top-left, the house filling the right two-thirds and bottom. DashboardView (Today)
/// feeds it the goal's countable hours and the pace line.
/// What the hero's bottom lines say when Today is new: the empty lot (with its one action), or
/// hours found in the calendar that don't count until confirmed. nil: the pace and stage lines.
enum HouseHeroFooter {
    case emptyLot(onAddProperty: () -> Void)
    case found(hoursText: String)
}

struct HouseHeroCard: View {
    let progress: HouseProgress
    var year: Int = Calendar.current.component(.year, from: Date())
    /// Pace words from the caller ("On pace, 18h ahead"); nil hides the line.
    var status: String? = nil
    var statusTone: HouseStatusTone = .positive
    var onCelebration: (HouseCelebration) -> Void = { _ in }
    var debugConfirmStill: Int? = nil
    /// New-owner states (onboarding landing); nil keeps the pace and stage lines.
    var footer: HouseHeroFooter? = nil
    /// The first property's name on a stake in the lot, until the first hour is logged.
    var stakeName: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownHours: Double?
    @State private var pop = false
    // Dynamic Type: the number, eyebrow and card grow with the text size (the house art keeps
    // its share of the card; the card is capped so the art never dominates the screen).
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 56
    @ScaledMetric(relativeTo: .caption2) private var eyebrowSize: CGFloat = 11
    @ScaledMetric(relativeTo: .body) private var scaledCardHeight: CGFloat = 320
    private var cardHeight: CGFloat { min(max(scaledCardHeight, 320), 460) }

    private var statusColor: Color {
        switch statusTone {
        case .positive: return HouseTokens.positiveOnHero
        case .caution: return HouseTokens.cautionOnHero
        case .neutral: return HouseTokens.onHeroSecondary
        }
    }

    private var statusSymbol: String? {
        switch statusTone {
        case .positive: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.circle.fill"
        case .neutral: return nil
        }
    }

    private var displayHours: Int { Int((shownHours ?? progress.hours).rounded(.down)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HouseBlueprintPaper()
            GeometryReader { g in
                // The art has ~6% side and ~8% bottom margins inside its 320 pt camera; size it so
                // the house fills the right half or so (the approved r6 concept proportion) and
                // the words keep a ~130 pt column for real pace copy ("Behind by 388h").
                // A staked lot leaves room on the right for the name flag (approved onboarding landing).
                // The empty lot is smaller too, so its words and button keep a clear column.
                let staked = stakeName != nil
                let shrink: CGFloat = staked ? 0.86 : (footerIsWide ? 0.8 : 1)
                let houseSize = min(g.size.height * 0.84, g.size.width * 0.62) * shrink
                let houseCenter = CGPoint(x: g.size.width - 4 - houseSize * 0.44 - (staked ? 40 : 0), y: g.size.height - 6 - houseSize * 0.417)
                let houseOrigin = CGPoint(x: houseCenter.x - houseSize / 2, y: houseCenter.y - houseSize / 2)
                // Bottom lines stay clear of the lot's left tip (~6% into the camera at ~74% height).
                let columnWidth = max(96, houseOrigin.x + houseSize * 0.04 - 24)
                ZStack(alignment: .topLeading) {
                    HouseHeroView(
                        progress: progress,
                        canvas: .blueprintHero,
                        beamOrigin: CGPoint(x: 72 - houseOrigin.x, y: 92 - houseOrigin.y),
                        onLand: { _ in countUp() },
                        onCelebration: onCelebration,
                        debugConfirmStill: debugConfirmStill
                    )
                    .frame(width: houseSize, height: houseSize)
                    .overlay {
                        if let stakeName {
                            // Room on the right for the flag, which hangs to the right of the post.
                            OnbMiniStake(name: stakeName, maxFlagWidth: g.size.width - (houseOrigin.x + houseSize * OnbScene.stakeBase.x) - 12)
                        }
                    }
                    .position(houseCenter)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(String(year)) · \(progress.goal.eyebrow)")
                            .font(.system(size: eyebrowSize, weight: .medium, design: .monospaced))
                            .textCase(.uppercase)
                            .tracking(1.3)
                            .foregroundStyle(HouseTokens.drafting)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: true, vertical: false)
                        Text("\(displayHours)")
                            .font(.system(size: numberSize, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(HouseTokens.onHeroPrimary)
                            .contentTransition(.identity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .scaleEffect(pop ? HouseMotion.countPopScale : 1, anchor: .leading)
                            .padding(.top, 2)
                            .accessibilityLabel("\(progress.wholeHours) hours")
                        Text("of \(Int(progress.goal.targetHours))h")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(HouseTokens.onHeroSecondary)
                        Spacer(minLength: 8)
                        if let footer {
                            footerView(footer)
                                // The lot's words share the card with the art: capped so they never
                                // truncate or run into the house (VoiceOver reads the full words).
                                .dynamicTypeSize(...DynamicTypeSize.large)
                                .frame(width: columnWidth, alignment: .leading)
                        } else {
                        Group {
                            if let status {
                                // Glyph inline with the words so the line wraps as one sentence;
                                // one line at subheadline, else one line at footnote, else wrapped.
                                let line = statusSymbol.map { Text(Image(systemName: $0)) + Text(" ") + Text(status) } ?? Text(status)
                                ViewThatFits(in: .horizontal) {
                                    line.font(.subheadline.weight(.semibold)).lineLimit(1)
                                    line.font(.footnote.weight(.semibold)).lineLimit(1)
                                    line.font(.subheadline.weight(.semibold)).lineLimit(3)
                                }
                                .foregroundStyle(statusColor)
                                .accessibilityIdentifier("today.hero.status")
                            }
                            Text(progress.stage.spokenName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(HouseTokens.onHeroPrimary)
                                .lineLimit(2)
                            if progress.nextStep != nil {
                                Text(progress.nextMilestoneLabel)
                                    .font(.footnote)
                                    .foregroundStyle(HouseTokens.onHeroSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .frame(width: columnWidth, alignment: .leading)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityElement(children: footerIsWide ? .contain : .combine)  // the empty lot keeps its button tappable
                }
            }
        }
        .frame(height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: HouseTokens.blueprint.opacity(0.25), radius: 16, y: 8)
        .onAppear { if shownHours == nil { shownHours = progress.hours } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("house-hero-card")
    }

    private var footerIsWide: Bool {
        if case .emptyLot = footer { return true }
        return false
    }

    @ViewBuilder private func footerView(_ footer: HouseHeroFooter) -> some View {
        switch footer {
        case .emptyLot(let onAdd):
            VStack(alignment: .leading, spacing: 2) {
                Text("An empty lot.")
                    .font(.headline)
                    .foregroundStyle(HouseTokens.onHeroPrimary)
                Text("Add a property. Every hour you confirm builds on it.")
                    .font(.footnote)
                    .foregroundStyle(HouseTokens.onHeroSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onAdd) {
                    Label("Add property", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(HouseTokens.blueprint)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(HouseTokens.onHeroPrimary, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.lhPressable)
                .padding(.top, 10)
                .accessibilityIdentifier("today.hero.addProperty")
            }
        case .found(let hoursText):
            VStack(alignment: .leading, spacing: 2) {
                Text("\(hoursText) found")
                    .font(.headline)
                    .foregroundStyle(HouseTokens.onHeroPrimary)
                    .accessibilityIdentifier("today.hero.found")
                Text("Not counted until you confirm")
                    .font(.footnote)
                    .foregroundStyle(HouseTokens.onHeroSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Whole-hour steps from the shown number to the new hours with a small spring pop.
    private func countUp() {
        let from = shownHours ?? progress.hours
        let to = progress.hours
        guard to > from, !reduceMotion else { shownHours = to; return }
        let steps = max(1, min(30, Int(to.rounded(.down)) - Int(from.rounded(.down))))
        let stepTime = HouseMotion.countUpMax / Double(steps)
        Task { @MainActor in
            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { pop = true }
            for i in 1...steps {
                shownHours = from + (to - from) * Double(i) / Double(steps)
                try? await Task.sleep(nanoseconds: UInt64(stepTime * 1_000_000_000))
            }
            shownHours = to
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pop = false }
        }
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
