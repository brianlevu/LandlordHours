import SwiftUI

/// The 100 / 500 / 750 celebration (concept §1 "Motion" + "Milestone" screen). Full blueprint,
/// the house at 290 pt, the stage lands, a brass plaque, "based on your records" copy, and
/// Continue at the top from the first frame. Tap anywhere to skip to the settled state.
/// Under 3 s every time. Reduce Motion: everything crossfades together in 200 ms.
struct MilestoneCelebrationView: View {
    let milestone: HouseMilestone
    /// The countable hours after the confirm (the copy only claims a test when hours pass it).
    let hours: Double
    var date: Date = Date()
    /// The app's colour scheme for the house art. The celebration itself is always dark-styled
    /// (light status bar over the blueprint bleed), so the caller passes its own scheme here.
    var artScheme: ColorScheme? = nil
    /// DEBUG/capture: start already settled.
    var startSettled = false
    var onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var environmentScheme

    // Animation state
    @State private var stageIn = 0.0          // 0 = before keyframe, 1 = after (crossfade / fill)
    @State private var roofDrop: CGFloat = -HouseMotion.roofDropPoints
    @State private var plaqueShown = false
    @State private var settled = false
    @State private var shownTick = 0
    @State private var landingTick = 0
    @State private var windowTick = 0
    @State private var runID = UUID()

    private let houseSize: CGFloat = 290

    var body: some View {
        ZStack {
            HouseBlueprintPaper()
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { skip() }
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onContinue) {
                        Text("Continue")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(HouseTokens.blueprint)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 44)
                            .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("milestone-continue")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Text(Self.title(for: milestone))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(HouseTokens.onHeroPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
                    .padding(.bottom, 20)          // the roof's 12 pt drop stays clear of the title
                    .accessibilityAddTraits(.isHeader)
                    .zIndex(1)

                house
                    .frame(width: houseSize, height: houseSize)
                    .contentShape(Rectangle())
                    .onTapGesture { skip() }

                Text("\(milestone.rawValue) confirmed hours in \(String(Calendar.current.component(.year, from: date)))")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HouseTokens.onHeroPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)
                Text(Self.detail(for: milestone, hours: hours))
                    .font(.body)
                    .foregroundStyle(HouseTokens.onHeroSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
                    .padding(.top, 6)
                Text(date.formatted(date: .long, time: .omitted))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .textCase(.uppercase)
                    .tracking(1.3)
                    .foregroundStyle(HouseTokens.drafting)
                    .padding(.top, 14)
                Spacer(minLength: 12)
            }
        }
        .sensoryFeedback(.success, trigger: shownTick)
        .sensoryFeedback(.impact(weight: .heavy), trigger: landingTick)
        .sensoryFeedback(.impact(weight: .light), trigger: windowTick)
        .preferredColorScheme(.dark)
        .task(id: runID) { await play() }
    }

    // MARK: House layers

    private var scheme: ColorScheme { artScheme ?? environmentScheme }

    @ViewBuilder
    private var house: some View {
        ZStack {
            switch milestone {
            case .foundation100:
                // Slab cures from wet (darker) to dry over 800 ms.
                HouseArtView(keyframe: .k00_lot)
                HouseArtView(keyframe: .k01_slab)
                    .brightness(-0.12 * (1 - stageIn))
                    .opacity(stageIn)
            case .roof500:
                // The completed frame, then the roof lands from 12 pt above and fills in.
                HouseArtView(keyframe: .k11_frame100)
                HouseArtView(keyframe: .k12_roof)
                    .mask(RoofRegionMask())
                    .offset(y: roofDrop)
                    .opacity(0.35 + 0.65 * stageIn)
                    .opacity(settled ? 0 : 1)
                HouseArtView(keyframe: .k12_roof)
                    .opacity(settled ? 1 : 0)
            case .keys750:
                // Windows light: the finished keyframe crossfades in over the siding.
                HouseArtView(keyframe: .k17_siding100)
                HouseArtView(keyframe: .k18_finished)
                    .opacity(stageIn)
            }
            HousePlaque(number: milestone.rawValue)
                .scaleEffect(plaqueShown ? 1 : 0.6, anchor: .bottom)
                .opacity(plaqueShown ? 1 : 0)
                .position(x: houseSize * 0.80, y: houseSize * 0.80)
        }
        .environment(\.colorScheme, scheme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HouseProgress(hours: hours, goal: .reps750).stage.spokenName + ". Brass plaque, \(milestone.rawValue) hours.")
        .accessibilityAddTraits(.isImage)
    }

    // MARK: Motion

    private func play() async {
        if startSettled { finish(animated: false); return }
        try? await Task.sleep(nanoseconds: UInt64(HouseMotion.milestoneLeadIn * 1_000_000_000))
        if Task.isCancelled || settled { return }
        shownTick += 1
        if reduceMotion {
            roofDrop = 0
            withAnimation(.easeInOut(duration: HouseMotion.reducedCrossfade)) {
                stageIn = 1
                plaqueShown = true
            }
            try? await Task.sleep(nanoseconds: UInt64(HouseMotion.reducedCrossfade * 1_000_000_000))
            settled = true
            return
        }
        switch milestone {
        case .foundation100:
            withAnimation(.easeOut(duration: HouseMotion.slabCureDuration)) { stageIn = 1 }
            try? await Task.sleep(nanoseconds: UInt64(HouseMotion.slabCureDuration * 1_000_000_000))
        case .roof500:
            withAnimation(.easeOut(duration: 0.25)) { stageIn = 0.35 }
            withAnimation(.spring(response: HouseMotion.roofSpringResponse, dampingFraction: HouseMotion.roofSpringDamping)) { roofDrop = 0 }
            try? await Task.sleep(nanoseconds: UInt64(HouseMotion.roofLandingDelay * 1_000_000_000))
            if Task.isCancelled || settled { return }
            landingTick += 1
            withAnimation(.easeOut(duration: HouseMotion.roofFillDuration)) { stageIn = 1 }
            try? await Task.sleep(nanoseconds: UInt64(HouseMotion.roofFillDuration * 1_000_000_000))
            withAnimation(.easeInOut(duration: 0.2)) { settled = true }
        case .keys750:
            withAnimation(.easeInOut(duration: HouseMotion.windowsLightDuration)) { stageIn = 1 }
            for _ in 0..<3 {
                windowTick += 1
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
            try? await Task.sleep(nanoseconds: UInt64((HouseMotion.windowsLightDuration - 0.27) * 1_000_000_000))
        }
        if Task.isCancelled { return }
        try? await Task.sleep(nanoseconds: UInt64((HouseMotion.plaqueDelay - 0.25) * 1_000_000_000))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { plaqueShown = true }
        settled = true
    }

    /// Tap to skip: jump to the settled state.
    private func skip() {
        guard !settled else { return }
        finish(animated: true)
    }

    private func finish(animated: Bool) {
        let apply = {
            stageIn = 1
            roofDrop = 0
            plaqueShown = true
            settled = true
        }
        if animated && !reduceMotion {
            withAnimation(.easeOut(duration: HouseMotion.reducedCrossfade)) { apply() }
        } else {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { apply() }
        }
    }

    // MARK: Copy

    static func title(for milestone: HouseMilestone) -> String {
        switch milestone {
        case .foundation100: return "Foundation's poured."
        case .roof500: return "Roof's on."
        case .keys750: return "Keys in the door."
        }
    }

    /// Never says "qualified" (a CPA's call). Claims a test only when the hours pass it.
    static func detail(for milestone: HouseMilestone, hours: Double) -> String {
        switch milestone {
        case .foundation100:
            return hours > 100
                ? "Past 100 hours for material participation test 3, based on your records."
                : "Material participation test 3 needs more than 100 hours. You're at the line."
        case .roof500:
            return hours > 500
                ? "Material participation test 1 met, based on your records."
                : "Material participation test 1 needs more than 500 hours. You're at the line."
        case .keys750:
            return "The 750-hour part of REPS is met, based on your records."
        }
    }
}

/// Keeps the roof region of the 320 pt camera (everything above the eaves, soft edge).
private struct RoofRegionMask: View {
    var body: some View {
        GeometryReader { g in
            LinearGradient(
                stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.54), .init(color: .clear, location: 0.6)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

/// Brass milestone plaque: 100 / 500 / 750, engraved.
struct HousePlaque: View {
    let number: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [HouseTokens.brassLight, HouseTokens.brass, HouseTokens.brassDark], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(HouseTokens.brassEngrave.opacity(0.55), lineWidth: 1.2)
                .padding(4)
            VStack(spacing: 0) {
                Text("\(number)")
                    .font(.system(size: 24, weight: .heavy, design: .serif))
                    .monospacedDigit()
                Text("HOURS")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.5)
            }
            .foregroundStyle(HouseTokens.brassEngrave)
        }
        .frame(width: 78, height: 58)
        .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
        .accessibilityHidden(true)
    }
}

#Preview("500h celebration") {
    MilestoneCelebrationView(milestone: .roof500, hours: 502, onContinue: {})
}

#Preview("750h settled") {
    MilestoneCelebrationView(milestone: .keys750, hours: 751, startSettled: true, onContinue: {})
}
