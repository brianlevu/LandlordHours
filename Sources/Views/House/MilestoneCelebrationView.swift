import SwiftUI

/// The milestone celebration (concept §1 "Motion" + "Milestone", approved blueprint-r6 frame):
/// full blueprint, Continue at the top from the first frame, the house large with the stage
/// landing and an in-scene brass sign, "based on your records" copy, and Share anchored at the
/// bottom. Tap the scene to skip to the settled state. Under 3 s. Reduce Motion: one 200 ms
/// crossfade.
///
/// Building stages (slab 100, roof 500, finished > 750) are the IRS thresholds for every goal.
/// The KEYS moment (key swings in, windows light) is the owner's own goal: REPS on the finished
/// house, MP-500 on the roofed house, MP-100 at the slab.
struct MilestoneCelebrationView: View {
    let celebration: HouseCelebration
    /// The countable hours after the confirm (the copy only claims a test when hours pass it).
    let hours: Double
    var date: Date = Date()
    /// The app's colour scheme for the house art. The celebration itself is dark-styled (light
    /// status bar over the blueprint bleed), so the caller passes its own scheme here.
    var artScheme: ColorScheme? = nil
    /// DEBUG/capture: start already settled.
    var startSettled = false
    /// DEBUG/capture: wait this long before the motion starts (so a recording has no cold launch).
    var startDelay: Double = 0
    var onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var environmentScheme

    @State private var stageIn = 0.0          // 0 = before, 1 = after (crossfade / fill / lights)
    @State private var roofDrop: CGFloat = -HouseMotion.roofDropPoints
    @State private var keySwing = 0.0         // 0 = out of frame, 1 = hung (springs past and settles)
    @State private var signShown = false
    @State private var settled = false
    @State private var shownTick = 0
    @State private var landingTick = 0
    @State private var windowTick = 0
    @State private var shareImage: UIImage?

    private var scheme: ColorScheme { artScheme ?? environmentScheme }
    private var year: Int { Calendar.current.component(.year, from: date) }

    var body: some View {
        GeometryReader { g in
            let houseSize = min(g.size.width - 24, 360, g.size.height * 0.46)
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

                    Spacer(minLength: 4)

                    if let eyebrow = Self.eyebrow(for: celebration) {
                        Text(eyebrow)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .textCase(.uppercase)
                            .tracking(1.3)
                            .foregroundStyle(HouseTokens.drafting)
                            .padding(.bottom, 6)
                    }
                    Text(Self.title(for: celebration))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(HouseTokens.onHeroPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .zIndex(1)

                    house(size: houseSize)
                        .frame(width: houseSize, height: houseSize)
                        .padding(.top, 4)
                        .contentShape(Rectangle())
                        .onTapGesture { skip() }

                    Text(Self.hoursLine(for: celebration, hours: hours, year: year))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(HouseTokens.onHeroPrimary)
                        .multilineTextAlignment(.center)
                    Text(Self.detail(for: celebration, hours: hours))
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
                        .padding(.top, 12)

                    Spacer(minLength: 16)

                    shareButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                }
            }
        }
        .sensoryFeedback(.success, trigger: shownTick)
        .sensoryFeedback(.impact(weight: .heavy), trigger: landingTick)
        .sensoryFeedback(.impact(weight: .light), trigger: windowTick)
        .preferredColorScheme(.dark)
        .task { await play() }
        .task { renderShareImage() }
    }

    // MARK: Share

    @ViewBuilder
    private var shareButton: some View {
        let label = HStack(spacing: 8) {
            Image(systemName: "square.and.arrow.up")
            Text("Share")
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(HouseTokens.blueprint)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(Color.white, in: Capsule())

        if let shareImage {
            let image = Image(uiImage: shareImage)
            ShareLink(item: image, preview: SharePreview(Self.hoursLine(for: celebration, hours: hours, year: year), image: image)) {
                label
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("milestone-share")
        } else {
            label.opacity(0.6)
                .accessibilityLabel("Share")
                .accessibilityIdentifier("milestone-share")
        }
    }

    @MainActor
    private func renderShareImage() {
        let card = HouseShareCard(celebration: celebration, hours: hours, year: year)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        shareImage = renderer.uiImage
    }

    // MARK: House layers

    private func house(size s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            switch celebration {
            case .stage(.foundation100):
                // Slab cures from wet (darker) to dry over 800 ms.
                HouseArtView(keyframe: .k00_lot)
                HouseArtView(keyframe: .k01_slab)
                    .brightness(-0.12 * (1 - stageIn))
                    .opacity(stageIn)
            case .stage(.roof500):
                // The completed frame, then the roof lands from 12 pt above and fills in.
                HouseArtView(keyframe: .k11_frame100)
                HouseArtView(keyframe: .k12_roof)
                    .mask(RoofRegionMask())
                    .offset(y: roofDrop)
                    .opacity(0.35 + 0.65 * stageIn)
                    .opacity(settled ? 0 : 1)
                HouseArtView(keyframe: .k12_roof)
                    .opacity(settled ? 1 : 0)
            case .stage(.keys750), .goalMet(.reps750):
                // The windows light: the finished keyframe crossfades in over the siding.
                HouseArtView(keyframe: .k17_siding100)
                HouseArtView(keyframe: .k18_finished)
                    .opacity(stageIn)
            case .goalMet(.mp500):
                // Lights come on inside the roofed frame.
                HouseArtView(keyframe: .k12_roof)
                InteriorGlow(keyframe: .k12_roof, center: CGPoint(x: 0.47, y: 0.55))
                    .opacity(stageIn)
            case .goalMet(.mp100):
                HouseArtView(keyframe: .k01_slab)
                InteriorGlow(keyframe: .k01_slab, center: CGPoint(x: 0.47, y: 0.74))
                    .opacity(stageIn * 0.7)
            }
            if let key = Self.keyPlacement(for: celebration) {
                HouseKey(size: s * 0.085)
                    .rotationEffect(.degrees(key.restAngle - 40 * (1 - keySwing)), anchor: .top)
                    .opacity(min(1, keySwing * 3))
                    .position(x: key.point.x * s, y: key.point.y * s)
            }
            HouseSign(number: Self.signNumber(for: celebration), size: s)
                .scaleEffect(signShown ? 1 : 0.7, anchor: .bottom)
                .opacity(signShown ? 1 : 0)
                .position(x: s * 0.80, y: s * 0.70)
        }
        .frame(width: s, height: s)
        .environment(\.colorScheme, scheme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.sceneLabel(for: celebration))
        .accessibilityAddTraits(.isImage)
    }

    // MARK: Motion

    private func play() async {
        let ns: (Double) -> UInt64 = { UInt64(max(0, $0) * 1_000_000_000) }
        if startSettled { finish(animated: false); return }
        try? await Task.sleep(nanoseconds: ns(startDelay + HouseMotion.milestoneLeadIn))
        if Task.isCancelled || settled { return }
        shownTick += 1
        if reduceMotion {
            roofDrop = 0
            withAnimation(.easeInOut(duration: HouseMotion.reducedCrossfade)) {
                stageIn = 1
                keySwing = 1
                signShown = true
            }
            try? await Task.sleep(nanoseconds: ns(HouseMotion.reducedCrossfade))
            settled = true
            return
        }
        switch celebration {
        case .stage(.foundation100):
            withAnimation(.easeOut(duration: HouseMotion.slabCureDuration)) { stageIn = 1 }
            try? await Task.sleep(nanoseconds: ns(HouseMotion.slabCureDuration))
        case .stage(.roof500):
            withAnimation(.easeOut(duration: 0.25)) { stageIn = 0.35 }
            withAnimation(.spring(response: HouseMotion.roofSpringResponse, dampingFraction: HouseMotion.roofSpringDamping)) { roofDrop = 0 }
            try? await Task.sleep(nanoseconds: ns(HouseMotion.roofLandingDelay))
            if Task.isCancelled || settled { return }
            landingTick += 1
            withAnimation(.easeOut(duration: HouseMotion.roofFillDuration)) { stageIn = 1 }
            try? await Task.sleep(nanoseconds: ns(HouseMotion.roofFillDuration))
            withAnimation(.easeInOut(duration: 0.2)) { settled = true }
        case .stage(.keys750), .goalMet:
            withAnimation(.easeInOut(duration: HouseMotion.windowsLightDuration)) { stageIn = 1 }
            for _ in 0..<3 {
                windowTick += 1
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
            if Self.keyPlacement(for: celebration) != nil {
                // The key swings in past rest and settles (10 degrees of overshoot).
                withAnimation(.spring(response: 0.5, dampingFraction: 0.45)) { keySwing = 1 }
            }
            try? await Task.sleep(nanoseconds: ns(HouseMotion.windowsLightDuration - 0.27))
        }
        if Task.isCancelled { return }
        try? await Task.sleep(nanoseconds: ns(HouseMotion.plaqueDelay - 0.25))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { signShown = true }
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
            keySwing = 1
            signShown = true
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

    // MARK: Copy and placement

    static func eyebrow(for celebration: HouseCelebration) -> String? {
        if case .goalMet = celebration { return "Goal met" }
        return nil
    }

    static func title(for celebration: HouseCelebration) -> String {
        switch celebration {
        case .stage(.foundation100): return "Foundation’s poured."
        case .stage(.roof500): return "Roof’s on."
        case .stage(.keys750): return "Every stage is built."
        case .goalMet: return "Keys in the door."
        }
    }

    static func signNumber(for celebration: HouseCelebration) -> Int {
        Int(celebration.thresholdHours)
    }

    /// "502 confirmed hours in 2026": the actual whole hours, never below the threshold shown.
    static func hoursLine(for celebration: HouseCelebration, hours: Double, year: Int) -> String {
        "\(max(Int(celebration.thresholdHours), Int(hours.rounded(.down)))) confirmed hours in \(String(year))"
    }

    /// Never says "qualified" (a CPA's call). Claims a test only when the hours pass it.
    static func detail(for celebration: HouseCelebration, hours: Double) -> String {
        switch celebration {
        case .stage(.foundation100):
            return hours > 100
                ? "Past 100 hours for material participation test 3, based on your records."
                : "Material participation test 3 needs more than 100 hours. You’re at the line."
        case .stage(.roof500):
            return hours > 500
                ? "Material participation test 1 met, based on your records."
                : "Material participation test 1 needs more than 500 hours. You’re at the line."
        case .stage(.keys750):
            return "More than 750 hours, based on your records. The house keeps your count."
        case .goalMet(.reps750):
            return "The 750-hour part of REPS is met, based on your records."
        case .goalMet(.mp500):
            return "More than 500 hours: material participation test 1 met, based on your records."
        case .goalMet(.mp100):
            return "More than 100 hours, based on your records. Test 3 also asks that no one else did more."
        }
    }

    static func sceneLabel(for celebration: HouseCelebration) -> String {
        let n = Int(celebration.thresholdHours)
        switch celebration {
        case .stage(.foundation100): return "The foundation is poured. A brass sign reads 100 hours."
        case .stage(.roof500): return "The roof is on. A brass sign reads 500 hours."
        case .stage(.keys750): return "The house is finished, windows lit. A brass sign reads 750 hours."
        case .goalMet: return "A key hangs in the door and the lights are on. A brass sign reads \(n) hours."
        }
    }

    /// Where the key hangs (unit point in the camera) and its resting angle.
    static func keyPlacement(for celebration: HouseCelebration) -> (point: CGPoint, restAngle: Double)? {
        switch celebration {
        case .goalMet(.reps750): return (CGPoint(x: 0.605, y: 0.665), 0)
        case .goalMet(.mp500): return (CGPoint(x: 0.60, y: 0.66), 0)
        case .goalMet(.mp100): return (CGPoint(x: 0.52, y: 0.70), -70)   // lying on the slab
        case .stage: return nil
        }
    }
}

/// Keeps the roof region of the 320 pt camera (everything above the eaves, soft edge).
private struct RoofRegionMask: View {
    var body: some View {
        LinearGradient(
            stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.54), .init(color: .clear, location: 0.6)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// Warm light inside the built structure (masked to its silhouette): the lights are on.
private struct InteriorGlow: View {
    let keyframe: HouseKeyframe
    let center: CGPoint

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            RadialGradient(colors: [HouseTokens.window.opacity(0.95), HouseTokens.window.opacity(0)],
                           center: UnitPoint(x: center.x, y: center.y), startRadius: 0, endRadius: s * 0.3)
                .blendMode(.plusLighter)
                .mask(Image(decorative: keyframe.builtImageName).resizable().scaledToFit())
        }
        .accessibilityHidden(true)
    }
}

/// A brass key (SF Symbol, filled in brass with a dark edge), hanging from its top.
struct HouseKey: View {
    let size: CGFloat
    var body: some View {
        Image(systemName: "key.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(LinearGradient(colors: [HouseTokens.brassLight, HouseTokens.brass, HouseTokens.brassDark], startPoint: .top, endPoint: .bottom))
            .rotationEffect(.degrees(90))
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}

/// The milestone plaque as an in-scene sign: a brass plate on a timber post, standing on the lot
/// and sheared to the lot's front-right face (slope -0.49 in the camera), with a ground shadow.
struct HouseSign: View {
    let number: Int
    /// The house camera size; the sign scales with it.
    let size: CGFloat

    var body: some View {
        let w = size * 0.2
        let h = size * 0.13
        ZStack(alignment: .top) {
            Ellipse()
                .fill(Color.black.opacity(0.25))
                .frame(width: w * 0.7, height: h * 0.22)
                .blur(radius: 2)
                .offset(x: w * 0.12, y: h * 1.62)
            // Post
            RoundedRectangle(cornerRadius: 1)
                .fill(LinearGradient(colors: [HouseTokens.timberLight, HouseTokens.timberDark], startPoint: .leading, endPoint: .trailing))
                .frame(width: max(3, w * 0.08), height: h * 0.75)
                .offset(y: h * 0.95)
            // Plate
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LinearGradient(colors: [HouseTokens.brassLight, HouseTokens.brass, HouseTokens.brassDark], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(HouseTokens.brassEngrave.opacity(0.55), lineWidth: 1)
                    .padding(2.5)
                VStack(spacing: -1) {
                    Text("\(number)")
                        .font(.system(size: h * 0.48, weight: .heavy, design: .serif))
                        .monospacedDigit()
                    Text("HOURS")
                        .font(.system(size: max(6, h * 0.14), weight: .bold))
                        .tracking(1)
                }
                .foregroundStyle(HouseTokens.brassEngrave)
            }
            .frame(width: w, height: h)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 2)
        }
        .frame(width: w, height: h * 1.8, alignment: .top)
        .transformEffect(CGAffineTransform(a: 1, b: -0.49, c: 0, d: 1, tx: 0, ty: w * 0.245))
        .accessibilityHidden(true)
    }
}

/// The share image: the house, the number and the words, no app chrome. 360 pt square (1080 px).
struct HouseShareCard: View {
    let celebration: HouseCelebration
    let hours: Double
    let year: Int

    private var keyframe: HouseKeyframe {
        switch celebration {
        case .stage(.foundation100), .goalMet(.mp100): return .k01_slab
        case .stage(.roof500), .goalMet(.mp500): return .k12_roof
        case .stage(.keys750), .goalMet(.reps750): return .k18_finished
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HouseBlueprintPaper()
            HouseArtView(keyframe: keyframe)
                .frame(width: 270, height: 270)
                .position(x: 225, y: 215)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(max(Int(celebration.thresholdHours), Int(hours.rounded(.down))))")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("confirmed hours in \(String(year))")
                    .font(.headline)
                    .foregroundStyle(HouseTokens.onHeroSecondary)
                Spacer()
                Text("LandlordHours")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(HouseTokens.drafting)
            }
            .padding(22)
        }
        .frame(width: 360, height: 360)
    }
}

#Preview("500h celebration") {
    MilestoneCelebrationView(celebration: .stage(.roof500), hours: 502, onContinue: {})
}

#Preview("MP 500 goal met") {
    MilestoneCelebrationView(celebration: .goalMet(.mp500), hours: 501, startSettled: true, onContinue: {})
}
