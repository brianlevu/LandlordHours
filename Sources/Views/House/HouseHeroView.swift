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
            if new > old && animatesConfirms { settleTick += 1 }
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
    /// The target-first words (eyebrow, whose count, caption). nil keeps the plain "of 750h" caption.
    var heroCopy: TodayHeroCopy? = nil
    var onCelebration: (HouseCelebration) -> Void = { _ in }
    var debugConfirmStill: Int? = nil
    /// New-owner states (onboarding landing); nil keeps the pace and stage lines.
    var footer: HouseHeroFooter? = nil
    /// The first property's name on a stake in the lot, until the first hour is logged.
    var stakeName: String? = nil
    /// WP-L: the hours aren't final yet (the first iCloud pull is still running). The number is a
    /// soft placeholder bar and the house slot shows the drafting line sketching the house; when
    /// it turns false the real house crossfades in and the number counts up.
    var isLoading = false
    /// False for changes the user didn't make (an iCloud merge, even after the loading cap): the
    /// house and number update in place, with no beam, count-up or haptic.
    var animatesChanges = true
    /// WP-L: a 90-day look-back is running. The words say so instead of the stage and next
    /// milestone ("An empty lot / Foundation at 100h" reads as final while hours are coming).
    var isLookingBack = false
    /// 2.1: the house shows these hours instead of the number's (a rental's house is pinned at its
    /// 500 line; a record-only rental or a rental's part of a shared total is a plain lot).
    /// nil: the number's hours. Comes from `HomeStage`, the function the tiles use too.
    var stageHours: Double? = nil
    /// 2.1: the words under the number when nothing is being built ("Hours kept, no target");
    /// replaces the stage name and hides the next milestone. nil: the stage name.
    var stageTitle: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var shownHours: Double?
    @State private var cardWidth: CGFloat = 0
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

    /// One piece of the eyebrow: mono capitals, drafting colour.
    private func eyebrowText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: heroCopy == nil ? eyebrowSize : min(eyebrowSize, 14), weight: .medium, design: .monospaced))
            .textCase(.uppercase)
            .tracking(1.3)
            .foregroundStyle(HouseTokens.drafting)
    }

    /// The line under the stage name. A record has no target, so none. A 100-hour target shows only
    /// "Foundation at 100h" until it is reached (never "Roof at 500h" for someone aiming at 100).
    private var showsNextMilestone: Bool {
        guard stageTitle == nil, artProgress.nextStep != nil else { return false }
        guard let copy = heroCopy else { return true }
        guard let target = copy.targetHours else { return false }
        return target > 100 || artProgress.hours < 100
    }

    private var footerIsNil: Bool { if case .none = footer { return true }; return false }

    /// What the house draws: the number's hours, or the caller's stage hours.
    private var artProgress: HouseProgress {
        stageHours.map { HouseProgress(hours: $0, goal: progress.goal) } ?? progress
    }

    /// The number and the art's hours together, so one change handler sees both: when the number
    /// moves and the house does not (a plain lot, a house pinned at its roof), nothing lands a beam,
    /// so the number counts up on its own.
    private struct HeroHours: Equatable { let number: Double; let art: Double }
    private var heroHours: HeroHours { HeroHours(number: progress.hours, art: artProgress.hours) }

    /// Past the default text size the words grow with Dynamic Type and the card grows with them
    /// (the fixed-height card is kept, pixel for pixel, at the default size and below).
    private var usesFlowLayout: Bool { typeSize > .large }

    /// The caption and the pace are two lines: "of 500 hours", then "On pace for Dec 31" across the card's width.
    /// (The house sits lower to make room.) VoiceOver reads them as one: "of 500 hours · on pace for Dec 31".
    private var usesCombinedCaption: Bool {
        heroCopy?.phrase != nil && footerIsNil && !isLookingBack && !isLoading
    }

    private func captionLine(_ copy: TodayHeroCopy) -> some View {
        let glyph = statusSymbol.map { Text(Image(systemName: $0)) + Text(" ") } ?? Text("")
        return VStack(alignment: .leading, spacing: 2) {
            Text(copy.caption)
                .font(.title3.weight(.medium))
                .foregroundStyle(HouseTokens.onHeroSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            (glyph + Text(copy.status ?? ""))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(statusColor)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("today.hero.status")
        }
        // Past Large the words stop growing (as the empty-lot words do) and wrap; VoiceOver reads them in full.
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    private var displayHours: Int { Int((shownHours ?? progress.hours).rounded(.down)) }

    var body: some View {
        Group {
            if usesFlowLayout { flowCard } else { fixedCard }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: HouseTokens.blueprint.opacity(0.25), radius: 16, y: 8)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: HouseMotion.loadCrossfade), value: isLoading)
        .onAppear { if shownHours == nil { shownHours = isLoading ? 0 : progress.hours } }
        .onChange(of: isLoading) { _, loading in
            if loading {
                shownHours = 0
            } else {
                // The data landed: the house has crossfaded in; the number counts up to it.
                shownHours = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : HouseMotion.loadCrossfade * 0.5)) {
                    countUp(over: HouseMotion.loadCountUp)
                }
            }
        }
        .onChange(of: heroHours) { old, new in
            // The house didn't move, so no beam lands: the number follows on its own.
            if new.number != old.number && new.art == old.art && !isLoading { countUp() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("house-hero-card")
    }

    /// 2.0.1's card, unchanged: a fixed-height sheet, words top-left, the house bottom-right.
    private var fixedCard: some View {
        ZStack(alignment: .topLeading) {
            HouseBlueprintPaper()
            GeometryReader { g in
                // The art has ~6% side and ~8% bottom margins inside its 320 pt camera; size it so
                // the house fills the right half or so (the approved r6 concept proportion) and
                // the words keep a ~130 pt column for real pace copy ("Behind by 388h").
                // A staked lot leaves room on the right for the name flag (approved onboarding landing).
                // The empty lot is smaller too, so its words and button keep a clear column.
                let staked = stakeName != nil
                // A staked lot under a two-line caption (a rental's pace) sits smaller still, so the roof
                // never reaches the pace line.
                let shrink: CGFloat = staked ? (usesCombinedCaption ? 0.76 : 0.86) : ((footerIsWide || usesCombinedCaption) ? 0.8 : 1)
                let houseSize = min(g.size.height * 0.84, g.size.width * 0.62) * shrink
                let houseCenter = CGPoint(x: g.size.width - 4 - houseSize * 0.44 - (staked ? 40 : 0), y: g.size.height - 6 - houseSize * 0.417)
                let houseOrigin = CGPoint(x: houseCenter.x - houseSize / 2, y: houseCenter.y - houseSize / 2)
                // Bottom lines stay clear of the lot's left tip (~6% into the camera at ~74% height).
                let columnWidth = max(96, houseOrigin.x + houseSize * 0.04 - 24)
                ZStack(alignment: .topLeading) {
                    Group {
                        if isLoading {
                            DraftingLoader(sketch: .house, surface: .blueprint, subject: "your hours")
                                .accessibilityHidden(true)
                                .transition(.opacity)
                        } else {
                            HouseHeroView(
                                progress: artProgress,
                                canvas: .blueprintHero,
                                animatesConfirms: animatesChanges,
                                beamOrigin: CGPoint(x: 72 - houseOrigin.x, y: 92 - houseOrigin.y),
                                onLand: { _ in countUp() },
                                onCelebration: onCelebration,
                                debugConfirmStill: debugConfirmStill
                            )
                            .transition(.opacity)
                        }
                    }
                    .frame(width: houseSize, height: houseSize)
                    .overlay {
                        if let stakeName {
                            // Room on the right for the flag, which hangs to the right of the post.
                            OnbMiniStake(name: stakeName, maxFlagWidth: g.size.width - (houseOrigin.x + houseSize * OnbScene.stakeBase.x) - 12)
                        }
                    }
                    .position(houseCenter)

                    VStack(alignment: .leading, spacing: 2) {
                        VStack(alignment: .leading, spacing: 1) {
                            if let copy = heroCopy, let name = copy.propertyName {
                                // One rental's count: its name sits in the eyebrow and shortens with an
                                // ellipsis (never wraps mid-word); the year and the target stay whole.
                                Group {
                                    if typeSize.isAccessibilitySize {
                                        // AX sizes: the name never shortens. It gets its own line(s),
                                        // wrapped at word breaks; the year and target share the line above.
                                        VStack(alignment: .leading, spacing: 1) {
                                            eyebrowText("\(copy.eyebrowYear) · \(copy.eyebrowTarget)")
                                                .fixedSize(horizontal: false, vertical: true)
                                            eyebrowText(name)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    } else {
                                        HStack(spacing: 0) {
                                            eyebrowText("\(copy.eyebrowYear) · ").fixedSize()
                                            eyebrowText(name).lineLimit(1).truncationMode(.tail).layoutPriority(-1)
                                            eyebrowText(" · \(copy.eyebrowTarget)").fixedSize()
                                        }
                                    }
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(copy.eyebrow)
                                .accessibilityIdentifier("today.hero.eyebrow")
                            } else {
                                eyebrowText(heroCopy?.eyebrow ?? "\(String(year)) · \(progress.goal.eyebrow)")
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("today.hero.eyebrow")
                            }
                            if let qualifier = heroCopy?.qualifier {
                                Text(qualifier)
                                    .font(.system(size: heroCopy == nil ? eyebrowSize : min(eyebrowSize, 14), weight: .medium, design: .monospaced))
                                    .textCase(.uppercase)
                                    .tracking(1.3)
                                    .foregroundStyle(HouseTokens.onHeroSecondary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("today.hero.qualifier")
                            }
                        }
                        ZStack(alignment: .leading) {
                            // Keeps the number's line height so nothing moves when it lands.
                            Text("\(displayHours)")
                                .font(.system(size: numberSize, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(HouseTokens.onHeroPrimary)
                                .contentTransition(.identity)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .scaleEffect(pop ? HouseMotion.countPopScale : 1, anchor: .leading)
                                .opacity(isLoading ? 0 : 1)
                            if isLoading {
                                PlaceholderBar(width: numberSize * 1.7, height: numberSize * 0.62, surface: .blueprint)
                                    .transition(.opacity)
                            }
                        }
                        .padding(.top, 2)
                        .accessibilityLabel(isLoading ? "Loading your hours" : "\(progress.wholeHours) hours")
                        if usesCombinedCaption, let copy = heroCopy {
                            captionLine(copy)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("today.hero.caption")
                        } else {
                            Text(heroCopy?.caption ?? "of \(Int(progress.goal.targetHours))h")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(HouseTokens.onHeroSecondary)
                                .accessibilityIdentifier("today.hero.caption")
                        }
                        if heroCopy != nil && typeSize.isAccessibilitySize {
                            // Large text: the words follow the number at once, so the status never ends under the tab bar.
                            Color.clear.frame(height: 10)
                        } else {
                            Spacer(minLength: 8)
                        }
                        if isLoading {
                            VStack(alignment: .leading, spacing: 8) {
                                PlaceholderBar(width: min(columnWidth, 120), height: 12, surface: .blueprint)
                                PlaceholderBar(width: min(columnWidth, 88), height: 12, surface: .blueprint)
                            }
                            .frame(width: columnWidth, alignment: .leading)
                            .transition(.opacity)
                        } else if let footer {
                            footerView(footer)
                                // The lot's words share the card with the art: capped so they never
                                // truncate or run into the house (VoiceOver reads the full words).
                                .dynamicTypeSize(...DynamicTypeSize.large)
                                .frame(width: columnWidth, alignment: .leading)
                                .transition(.opacity)
                        } else {
                        Group {
                            if let status, !usesCombinedCaption {
                                // Glyph inline with the words so the line wraps as one sentence;
                                // one line at subheadline, else one line at footnote, else wrapped.
                                let line = statusSymbol.map { Text(Image(systemName: $0)) + Text(" ") + Text(status) } ?? Text(status)
                                ViewThatFits(in: .horizontal) {
                                    line.font(.subheadline.weight(.semibold)).lineLimit(1)
                                    line.font(.footnote.weight(.semibold)).lineLimit(1)
                                    line.font(.subheadline.weight(.semibold)).lineLimit(5)
                                }
                                .foregroundStyle(statusColor)
                                .accessibilityIdentifier("today.hero.status")
                            }
                            if isLookingBack {
                                // Wraps to three lines at large sizes instead of truncating.
                                Text("Looking through your calendar")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(HouseTokens.onHeroPrimary)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("today.hero.lookingBack")
                                Text("Rental work we find waits in your Inbox")
                                    .font(.footnote)
                                    .foregroundStyle(HouseTokens.onHeroSecondary)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if !(heroCopy != nil && typeSize.isAccessibilitySize) {
                                // At accessibility sizes the target words take the room; the stage is in the VoiceOver label.
                                Text(stageTitle ?? artProgress.stage.spokenName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(HouseTokens.onHeroPrimary)
                                    .lineLimit(2)
                                // A record has no target, so no "Roof at 500h" line: the stage name alone.
                                if showsNextMilestone {
                                    Text(artProgress.nextMilestoneLabel)
                                        .font(.footnote)
                                        .foregroundStyle(HouseTokens.onHeroSecondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        // The words share a fixed-height card with the art: past XXL they would be cut
                        // ("Behind…"), so they stop growing there and wrap (VoiceOver reads them in full).
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: columnWidth, alignment: .leading)
                        .transition(.opacity)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityElement(children: footerIsWide ? .contain : .combine)  // the empty lot keeps its button tappable
                }
            }
        }
        .frame(height: cardHeight)
    }

    // MARK: Flowing layout (past the default text size)

    /// The words lead and scale with Dynamic Type at every size (the eyebrow, the number, the
    /// caption and the pace line); the card grows with them. Up to XXXL the house sits in a band
    /// under the words with the stage words beside it; at accessibility sizes the stage words take
    /// the full width and the house sits under them, so nothing collides.
    private var flowCard: some View {
        let inner = max(cardWidth - 40, 200)
        let staked = stakeName != nil
        return VStack(alignment: .leading, spacing: 2) {
            flowEyebrow
            numberView.padding(.top, 2)
                .accessibilityLabel(isLoading ? "Loading your hours" : "\(progress.wholeHours) hours")
            if usesCombinedCaption, let copy = heroCopy {
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.caption)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(HouseTokens.onHeroSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    flowStatus(copy.status ?? "")
                }
                .accessibilityIdentifier("today.hero.caption")
            } else {
                Text(heroCopy?.caption ?? "of \(Int(progress.goal.targetHours))h")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(HouseTokens.onHeroSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.hero.caption")
                if let status, !isLoading, !isLookingBack, footer == nil {
                    flowStatus(status)
                }
            }
            if typeSize.isAccessibilitySize {
                flowLowerWords(width: inner)
                    .padding(.top, 10)
                let s = inner * 0.62 * 0.86
                flowHouse(size: s, flagWidth: 32 + 0.32 * s + (staked ? 28 : 0))
                    .padding(.trailing, staked ? 28 : 0)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                let s = inner * 0.62 * (staked ? 0.86 : 0.8)
                let trailing: CGFloat = staked ? 36 : 0
                let column = max(96, inner - s * 0.96 - trailing)
                ZStack(alignment: .bottomLeading) {
                    flowHouse(size: s, flagWidth: trailing + 32 + 0.32 * s)
                        .padding(.trailing, trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    flowLowerWords(width: column)
                        .padding(.bottom, s * 0.06)
                }
                .padding(.top, 6)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(HouseBlueprintPaper())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardWidth = $0 }
        .accessibilityElement(children: footerIsWide ? .contain : .combine)
    }

    @ViewBuilder private var flowEyebrow: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let copy = heroCopy {
                // Large text: the year (and the rental's name) on one line, the target on its own,
                // so "100-hour target" never breaks at its hyphen.
                VStack(alignment: .leading, spacing: 1) {
                    flowEyebrowText(copy.propertyName.map { "\(copy.eyebrowYear) · \($0)" } ?? copy.eyebrowYear)
                    flowEyebrowText(copy.eyebrowTarget)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(copy.eyebrow)
                .accessibilityIdentifier("today.hero.eyebrow")
            } else {
                flowEyebrowText(heroCopy?.eyebrow ?? "\(String(year)) · \(progress.goal.eyebrow)")
                    .accessibilityIdentifier("today.hero.eyebrow")
            }
            if let qualifier = heroCopy?.qualifier {
                Text(qualifier)
                    .font(.system(size: eyebrowSize, weight: .medium, design: .monospaced))
                    .textCase(.uppercase)
                    .tracking(1.3)
                    .foregroundStyle(HouseTokens.onHeroSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.hero.qualifier")
            }
        }
    }

    private func flowEyebrowText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: eyebrowSize, weight: .medium, design: .monospaced))
            .textCase(.uppercase)
            .tracking(1.3)
            .foregroundStyle(HouseTokens.drafting)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func flowStatus(_ text: String) -> some View {
        let glyph = statusSymbol.map { Text(Image(systemName: $0)) + Text(" ") } ?? Text("")
        return (glyph + Text(text))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(statusColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("today.hero.status")
    }

    private var numberView: some View {
        ZStack(alignment: .leading) {
            Text("\(displayHours)")
                .font(.system(size: min(numberSize, 96), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(HouseTokens.onHeroPrimary)
                .contentTransition(.identity)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .scaleEffect(pop ? HouseMotion.countPopScale : 1, anchor: .leading)
                .opacity(isLoading ? 0 : 1)
            if isLoading {
                PlaceholderBar(width: min(numberSize, 96) * 1.7, height: min(numberSize, 96) * 0.62, surface: .blueprint)
                    .transition(.opacity)
            }
        }
    }

    /// The words that share the house's band: loading bars, the empty lot or found hours, the
    /// look-back, or the stage and next step.
    @ViewBuilder private func flowLowerWords(width: CGFloat) -> some View {
        Group {
            if isLoading {
                VStack(alignment: .leading, spacing: 8) {
                    PlaceholderBar(width: min(width, 120), height: 12, surface: .blueprint)
                    PlaceholderBar(width: min(width, 88), height: 12, surface: .blueprint)
                }
            } else if let footer {
                footerView(footer)
            } else if isLookingBack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Looking through your calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HouseTokens.onHeroPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("today.hero.lookingBack")
                    Text("Rental work we find waits in your Inbox")
                        .font(.footnote)
                        .foregroundStyle(HouseTokens.onHeroSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stageTitle ?? artProgress.stage.spokenName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HouseTokens.onHeroPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if showsNextMilestone {
                        Text(artProgress.nextMilestoneLabel)
                            .font(.footnote)
                            .foregroundStyle(HouseTokens.onHeroSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(width: width, alignment: .leading)
        .transition(.opacity)
    }

    /// The house with its stake, at a fixed size.
    private func flowHouse(size s: CGFloat, flagWidth: CGFloat) -> some View {
        Group {
            if isLoading {
                DraftingLoader(sketch: .house, surface: .blueprint, subject: "your hours")
                    .accessibilityHidden(true)
                    .transition(.opacity)
            } else {
                HouseHeroView(
                    progress: artProgress,
                    canvas: .blueprintHero,
                    animatesConfirms: animatesChanges,
                    onLand: { _ in countUp() },
                    onCelebration: onCelebration,
                    debugConfirmStill: debugConfirmStill
                )
                .transition(.opacity)
            }
        }
        .frame(width: s, height: s)
        .overlay {
            if let stakeName {
                OnbMiniStake(name: stakeName, maxFlagWidth: flagWidth)
            }
        }
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
                Text(TodayHeroCopy.emptyLotLine(target: heroCopy?.targetHours))
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
    private func countUp(over duration: Double = HouseMotion.countUpMax) {
        let from = shownHours ?? progress.hours
        let to = progress.hours
        guard to > from, !reduceMotion, animatesChanges else { shownHours = to; return }
        let steps = max(1, min(30, Int(to.rounded(.down)) - Int(from.rounded(.down))))
        let stepTime = duration / Double(steps)
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
