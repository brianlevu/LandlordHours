import SwiftUI
import AVFoundation
import UIKit

// MARK: - CraftHouseView: the crafted house on the page (standard §H; plan package A)
//
// The house is a rendered diorama shown directly on the page. It is never inside a card, a rounded
// rectangle or a tinted band: the frame is `.clipped()` to a plain square only (§H.1).
//
// Ported from the approved CRAFT mock (`Debug/DirCraft/DirCraftToday.swift`, `CraftHouseArt`). The
// numbers live in package 0's pure types and are read, never copied:
//   - `CraftStage`: the stage, asset names, the H1 placement table (scale about the ground line,
//     lift at a 390 frame), the ground line at 0.92.
//   - `CraftHeroSize`: the frame sides (hero H1/H3/H7, medium, thumbnails).
//   - `CraftMotion`: the one stage-motion switch and every timing (`timberDrop`, `stageFade`,
//     `windowsOn`, the clip dim while the windows are held dark).
//
// Layers, back to front (Z3 and Z5 are reserved for §F.2 and hold nothing until it is built):
//   Z0 spill pool · Z1 contact shadow · Z2 night backlight · Z3 (reserved: behind-house props)
//   Z4 the stills and the build clip · Z5 (reserved: in-front props)
//
// Motion is bound to the values the caller passes (`stage`, `windowsLit`), never to appearing:
//   - a change that ends at `framing` from an earlier stage plays the 39-piece timber drop (clip
//     fade-in 0.20, 2.0 s, crossfade 0.30), once per stage per rental (`dropAllowed`, from
//     `CraftDropLedger`), then the knock haptic and `onStageSettled`;
//   - any other stage change is one `stageFade` (0.25 crossfade, 0.97 → 1); going down (an edit or
//     a delete) is a plain 0.25 fade with no scale and never a reverse build;
//   - the windows fade on 0.40 s after the drop's crossfade, or 0.30 s after the still settles; they
//     are held dark through the drop (the lit clip is multiplied to the unlit still's mean luma);
//   - Reduce Motion: no clip (the still crossfades 0.15, the knock is kept), the windows fade linear.
// A rental switch is the caller's: give each rental its own identity (`.id(rentalID)`) with
// `CraftHouseView.rentalSlide(edge:reduceMotion:)`, so a new rental never animates its stage.

struct CraftHouseView: View {
    /// The stage to show (`CraftStage.stage(hours:goal:)`, or `CraftHeroTotals` for All rentals).
    let stage: CraftStage
    /// Lit when hours were logged today on the shown rental (`TodayWindowState.loggedToday`).
    let windowsLit: Bool
    /// The square frame's side in points (`CraftHeroSize`, or `CraftHeroSide.resolve`).
    let side: CGFloat
    /// Scale and lift the early stages per the H1 placement table (off for small frames).
    var fillsStage = true
    /// False once this rental already played its drop for this stage (`CraftDropLedger`).
    var dropAllowed = true
    /// Called when a stage change has landed: as the last timber lands, or with the stage fade.
    /// The number rolls here (`heroCountUp`), and the caller marks the drop played.
    var onStageSettled: ((CraftStageMotion) -> Void)? = nil
    /// Swiping the house changes the rental: +1 next, −1 previous (the one allowed `DragGesture`
    /// outside rows). nil = no swipe.
    var onSwipe: ((Int) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What is on screen. nil = follow the caller's values (first appearance, no motion).
    @State private var shownStage: CraftStage?
    @State private var shownLit: Bool?
    @State private var building = false
    @State private var buildTick = 0
    @State private var pendingStage: CraftStage?
    @State private var litTask: Task<Void, Never>?
    @State private var knock = 0
    /// The last stage change went down (an edit or a delete): a quiet fade, no scale settle.
    @State private var fadingDown = false

    init(stage: CraftStage, windowsLit: Bool, side: CGFloat, fillsStage: Bool = true, dropAllowed: Bool = true,
         onStageSettled: ((CraftStageMotion) -> Void)? = nil, onSwipe: ((Int) -> Void)? = nil) {
        self.stage = stage
        self.windowsLit = windowsLit
        self.side = side
        self.fillsStage = fillsStage
        self.dropAllowed = dropAllowed
        self.onStageSettled = onStageSettled
        self.onSwipe = onSwipe
    }

    private var dark: Bool { colorScheme == .dark }
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var displayedStage: CraftStage { shownStage ?? stage }
    private var displayedLit: Bool { shownLit ?? windowsLit }
    private var target: Target { Target(stage: stage, lit: windowsLit) }

    private struct Target: Equatable {
        let stage: CraftStage
        let lit: Bool
    }

    var body: some View {
        ZStack {
            spillPool                     // Z0
            contactShadow                 // Z1
            backlight                     // Z2
            // Z3 reserved (§F.2 behind-house props). Nothing is drawn here until §F.2 is built.
            art                           // Z4
            // Z5 reserved (§F.2 in-front props).
        }
        .frame(width: side, height: side)
        .clipped()
        .contentShape(Rectangle())
        .gesture(swipe, including: onSwipe == nil ? .none : .all)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.8), trigger: knock)
        .onChange(of: target) { old, new in change(from: old, to: new) }
        .onDisappear { litTask?.cancel() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(stage: displayedStage, lit: displayedLit))
        .accessibilityAddTraits(.isImage)
        .modifier(SwipeAccessibility(onSwipe: onSwipe))
        .accessibilityIdentifier("craft.house")
    }

    // MARK: Layers

    private var windowsAnimation: Animation { reduceMotion ? AppAnimation.windowsReduced : AppAnimation.windows }

    /// Warm light from the windows on the lot: a radial ellipse 0.96 × 0.33 of the frame centred at
    /// y = 0.345 × side; × 0.2 when unlit; fades with the windows.
    private var spillPool: some View {
        let spill = colors.spillPool
        return Circle()
            .fill(RadialGradient(colors: [spill, spill.opacity(0)], center: .center, startRadius: 0, endRadius: side * 0.48))
            .frame(width: side * 0.96, height: side * 0.96)
            .scaleEffect(y: 0.34)
            .offset(y: side * 0.345)
            .opacity(displayedLit ? 1 : 0.2)
            .animation(windowsAnimation, value: displayedLit)
            .accessibilityHidden(true)
    }

    /// 0.80 × 0.07 of the frame, blur 0.035 × side (the baked render shadow is faint on a light page).
    private var contactShadow: some View {
        Ellipse()
            .fill(colors.contactShadow)
            .frame(width: side * 0.80, height: side * 0.07)
            .blur(radius: side * 0.035)
            .offset(y: side * 0.355)
            .accessibilityHidden(true)
    }

    /// Night only: a cool light behind the lot (0.50 → 0 inside 0.88 × side) plus a rim ellipse
    /// (0.34 → 0), so the silhouette reads against the page. Fades to nothing inside the frame.
    @ViewBuilder private var backlight: some View {
        if dark {
            let glow = colors.backlight
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [glow.opacity(0.50), glow.opacity(0.20), glow.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: side * 0.44))
                    .frame(width: side * 0.88, height: side * 0.88)
                    .offset(y: side * 0.03)
                Circle()
                    .fill(RadialGradient(colors: [glow.opacity(0.34), glow.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: side * 0.46))
                    .frame(width: side * 0.92, height: side * 0.92)
                    .scaleEffect(y: 0.34)
                    .offset(y: side * 0.31)
            }
            .accessibilityHidden(true)
        }
    }

    private var art: some View {
        ZStack {
            stills
                .id(displayedStage)
                .transition(reduceMotion || fadingDown ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: CraftMotion.stageFadeStartScale)),
                    removal: .opacity))
            if building, let url = Self.buildClipURL(dark: dark) {
                CraftBuildClip(url: url, tick: buildTick, onEnd: dropLanded)
                    .colorMultiply(Color(white: CraftMotion.clipDim(windowsLit: displayedLit, dark: dark)))
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        // Night ambient for the stages without a moon rim (+17 levels), SwiftUI only.
        .brightness(dark ? Self.nightLift(displayedStage) : 0)
        .scaleEffect(fillsStage ? displayedStage.stageScale : 1, anchor: UnitPoint(x: 0.5, y: CraftStage.groundLine))
        .offset(y: fillsStage ? -displayedStage.stageLift(side: side) : 0)
    }

    /// The unlit still underneath, the lit still fading over it. A missing `-unlit` twin falls back
    /// to the lit asset (a gate FAIL, §H.3).
    @ViewBuilder private var stills: some View {
        let lit = Image(decorative: displayedStage.assetName(lit: true)).resizable().interpolation(.high).scaledToFit()
        if Self.hasUnlitTwin(displayedStage) {
            ZStack {
                Image(decorative: displayedStage.assetName(lit: false)).resizable().interpolation(.high).scaledToFit()
                lit.opacity(displayedLit ? 1 : 0).animation(windowsAnimation, value: displayedLit)
            }
        } else {
            lit
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24).onEnded { value in
            if value.translation.width < -40 { onSwipe?(1) } else if value.translation.width > 40 { onSwipe?(-1) }
        }
    }

    // MARK: Motion

    private func change(from old: Target, to new: Target) {
        litTask?.cancel()
        let from = shownStage ?? old.stage
        let fromLit = shownLit ?? old.lit
        var motion = CraftMotion.stageMotion(from: from, to: new.stage)
        fadingDown = new.stage < from
        let wouldDrop = motion == .timberDrop
        if motion == .timberDrop && (!dropAllowed || reduceMotion || Self.buildClipURL(dark: dark) == nil) {
            motion = .stageFade
        }
        // Hold the windows as they were until the stage has landed.
        shownLit = fromLit
        switch motion {
        case .none:
            shownStage = new.stage
            scheduleWindows(new.lit, after: new.lit && !fromLit ? CraftMotion.windowsAfterSettle : 0)
        case .timberDrop:
            shownStage = from
            pendingStage = new.stage
            buildTick += 1
            withAnimation(.easeOut(duration: CraftMotion.dropFadeIn)) { building = true }
        case .stageFade:
            let fade = reduceMotion ? Animation.easeOut(duration: CraftMotion.reducedStageCrossfade) : AppAnimation.stageFade
            withAnimation(fade) { shownStage = new.stage }
            if wouldDrop && dropAllowed { knock += 1 }   // Reduce Motion keeps the knock
            onStageSettled?(motion)
            let settle = reduceMotion ? CraftMotion.reducedStageCrossfade : CraftMotion.stageFadeDuration
            scheduleWindows(new.lit, after: new.lit && !fromLit ? settle + CraftMotion.windowsAfterSettle : 0)
        }
    }

    /// The clip ended: the still under it becomes the new stage, the knock lands, the clip
    /// crossfades out, then (first log of the day) the windows come on.
    private func dropLanded() {
        guard building else { return }
        if let pendingStage { shownStage = pendingStage }
        pendingStage = nil
        knock += 1
        onStageSettled?(.timberDrop)
        withAnimation(.easeOut(duration: CraftMotion.dropCrossfade)) { building = false }
        scheduleWindows(windowsLit, after: windowsLit && shownLit == false ? CraftMotion.dropCrossfade : 0)
    }

    private func scheduleWindows(_ lit: Bool, after delay: Double) {
        litTask?.cancel()
        guard shownLit != lit else { return }
        guard delay > 0 else { shownLit = lit; return }
        litTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, !building else { return }
            shownLit = lit
        }
    }

    // MARK: Assets

    /// The build clip (HEVC with alpha), frame70 → framing, lit. nil when the resource is missing.
    static func buildClipURL(dark: Bool) -> URL? {
        Bundle.main.url(forResource: dark ? "craft_build_dark" : "craft_build_light", withExtension: "mov")
    }

    static func hasUnlitTwin(_ stage: CraftStage) -> Bool {
        UIImage(named: stage.assetName(lit: false)) != nil
    }

    /// Added to the house's RGB at night for the stages without a moon rim (0.065 × 255 ≈ +17).
    static func nightLift(_ stage: CraftStage) -> Double {
        stage.isFraming ? 0 : 0.065
    }

    /// "House, Frame going up, lights on".
    static func accessibilityLabel(stage: CraftStage, lit: Bool) -> String {
        let lights = lit
            ? String(localized: "hero.lightsOn", defaultValue: "lights on", table: "Foundations")
            : String(localized: "hero.lightsOff", defaultValue: "lights off", table: "Foundations")
        return String(localized: "hero.label", defaultValue: "House, \(stage.spokenName), \(lights)", table: "Foundations",
                      comment: "VoiceOver label for the house: its stage, then whether the lights are on")
    }

    // MARK: Rental switch

    /// `rentalSlide`: the diorama slides in from the trailing edge (leading when going back) with
    /// opacity; a 0.20 fade under Reduce Motion. Pair with `AppAnimation.rentalSlide`.
    static func rentalSlide(edge: Edge, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .move(edge: edge == .trailing ? .leading : .trailing).combined(with: .opacity))
    }

    static func rentalSlideAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: CraftMotion.reducedRentalFade) : AppAnimation.rentalSlide
    }
}

/// VoiceOver: adjust (swipe up/down) changes the rental when the house swipes.
private struct SwipeAccessibility: ViewModifier {
    let onSwipe: ((Int) -> Void)?
    func body(content: Content) -> some View {
        if let onSwipe {
            content
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: onSwipe(1)
                    case .decrement: onSwipe(-1)
                    @unknown default: break
                    }
                }
                .accessibilityHint(String(localized: "hero.swipeHint", defaultValue: "Swipe up or down to change the rental",
                                          table: "Foundations"))
        } else {
            content
        }
    }
}

// MARK: - Hero side with hysteresis (§H.1 H1, H3, H6, H8; §H.5)

/// The hero frame side for a window, recomputed only when the band changes, the accessibility
/// state changes, or the window height moves by ≥ 40pt (H8) — never per pixel during a resize.
struct CraftHeroSide: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Today and Welcome: H1 (band A), H3 at AX, 390 fixed in bands B and C.
        case hero
        /// The rental page: 0.343 × H (300 on 402×874), 220 at AX, 300 fixed in bands B and C.
        case medium
    }

    let side: CGFloat
    let band: LayoutBand
    let windowHeight: CGFloat
    let accessibility: Bool
    /// Band B only: the width it was resolved for. The first layout pass can report a transient width
    /// (390 on a 13" iPad), and a width-capped side must not stick (§1.27 IP4, visual gate look 2).
    var windowWidth: CGFloat = 0

    static let heightHysteresis: CGFloat = 40
    static let wideMediumSide: CGFloat = 300

    static func resolve(previous: CraftHeroSide?, kind: Kind, window: CGSize, band: LayoutBand,
                        accessibility: Bool) -> CraftHeroSide {
        if let previous, previous.band == band, previous.accessibility == accessibility,
           abs(previous.windowHeight - window.height) < heightHysteresis,
           band == .a || abs(previous.windowWidth - window.width) < 1 {
            return previous
        }
        let side: CGFloat
        switch (kind, band) {
        case (.hero, .a):
            side = CraftHeroSize.hero(windowWidth: window.width, windowHeight: window.height, accessibility: accessibility)
        case (.hero, _):
            side = CraftHeroSize.wideHero(windowWidth: window.width, windowHeight: window.height, accessibility: accessibility)
        case (.medium, .a):
            side = CraftHeroSize.medium(windowWidth: window.width, windowHeight: window.height, accessibility: accessibility)
        case (.medium, _):
            side = min(wideMediumSide, max(0, window.width - 12))
        }
        return CraftHeroSide(side: side, band: band, windowHeight: window.height, accessibility: accessibility,
                             windowWidth: band == .a ? 0 : window.width)
    }
}

// MARK: - The build clip player

/// AVPlayerLayer keeps the HEVC alpha channel, so the clip composites straight onto the page.
struct CraftBuildClip: UIViewRepresentable {
    let url: URL
    let tick: Int
    let onEnd: () -> Void

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var observer: NSObjectProtocol?
        var tick = -1
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.pixelBufferAttributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        guard view.tick != tick else { return }
        view.tick = tick
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        view.playerLayer.player = player
        if let observer = view.observer { NotificationCenter.default.removeObserver(observer) }
        view.observer = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item,
                                                               queue: .main) { _ in onEnd() }
        player.play()
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        if let observer = view.observer { NotificationCenter.default.removeObserver(observer) }
        view.playerLayer.player?.pause()
    }
}
