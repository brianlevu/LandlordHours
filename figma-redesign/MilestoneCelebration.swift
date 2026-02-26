// MilestoneCelebration.swift
// LandlordHours
//
// A premium "Milestone Celebration" overlay with layered confetti,
// spring-driven hero animations, and haptic feedback.
//
// Usage:
//   @State private var celebration: CelebrationType? = nil
//
//   SomeView()
//       .milestoneCelebration($celebration)
//
//   // Trigger:
//   celebration = .goalMet
//
// Requires: iOS 17+, SwiftUI, UIKit (haptics)

import SwiftUI

// MARK: - CelebrationType

/// Defines every milestone the app can celebrate.
/// Each case carries its own icon, copy, and color palette.
enum CelebrationType: Identifiable, Equatable {
    case propertyAdded
    case goalMet
    case taskDone
    case weeklyStreak
    case hoursLogged

    var id: String { title }

    // MARK: Display Properties

    /// SF Symbol name for the hero icon.
    var icon: String {
        switch self {
        case .propertyAdded: return "house.fill"
        case .goalMet:       return "checkmark.seal.fill"
        case .taskDone:      return "star.fill"
        case .weeklyStreak:  return "flame.fill"
        case .hoursLogged:   return "clock.fill"
        }
    }

    /// Large headline shown below the icon.
    var title: String {
        switch self {
        case .propertyAdded: return "Property Added!"
        case .goalMet:       return "Goal Met!"
        case .taskDone:      return "Great Work!"
        case .weeklyStreak:  return "On Fire!"
        case .hoursLogged:   return "Hours Logged!"
        }
    }

    /// Supporting line beneath the title.
    var subtitle: String {
        switch self {
        case .propertyAdded: return "Your journey begins"
        case .goalMet:       return "You've qualified — amazing work"
        case .taskDone:      return "Keep up the momentum"
        case .weeklyStreak:  return "3 weeks in a row"
        case .hoursLogged:   return "Every hour counts"
        }
    }

    /// Primary accent used for the icon badge and highlights.
    var accentColor: Color {
        switch self {
        case .propertyAdded: return Color(celebrationHex: 0x7B68EE) // violet
        case .goalMet:       return Color(celebrationHex: 0x34D399) // green
        case .taskDone:      return Color(celebrationHex: 0xF5C563) // gold
        case .weeklyStreak:  return Color(celebrationHex: 0xFF8A7A) // coral
        case .hoursLogged:   return Color(celebrationHex: 0x6CB4EE) // sky blue
        }
    }

    /// Softer tint used for the radial gradient background.
    var gradientColor: Color {
        switch self {
        case .propertyAdded: return Color(celebrationHex: 0xA78BFA)
        case .goalMet:       return Color(celebrationHex: 0x6EE7B7)
        case .taskDone:      return Color(celebrationHex: 0xFDE68A)
        case .weeklyStreak:  return Color(celebrationHex: 0xFFB4A9)
        case .hoursLogged:   return Color(celebrationHex: 0x93C5FD)
        }
    }

    /// Five-color palette for confetti particles.
    var confettiColors: [Color] {
        switch self {
        case .propertyAdded:
            return [
                Color(celebrationHex: 0x7B68EE),
                Color(celebrationHex: 0xA78BFA),
                Color(celebrationHex: 0xEDE8FF),
                Color(celebrationHex: 0xB8AFFE),
                .white
            ]
        case .goalMet:
            return [
                Color(celebrationHex: 0x34D399),
                Color(celebrationHex: 0x6EE7B7),
                Color(celebrationHex: 0xECFDF5),
                Color(celebrationHex: 0x059669),
                .white
            ]
        case .taskDone:
            return [
                Color(celebrationHex: 0xF5C563),
                Color(celebrationHex: 0xFDE68A),
                Color(celebrationHex: 0xFFF4DA),
                Color(celebrationHex: 0xD97706),
                .white
            ]
        case .weeklyStreak:
            return [
                Color(celebrationHex: 0xFF8A7A),
                Color(celebrationHex: 0xFFB4A9),
                Color(celebrationHex: 0xFFE8E4),
                Color(celebrationHex: 0xE55A4A),
                .white
            ]
        case .hoursLogged:
            return [
                Color(celebrationHex: 0x6CB4EE),
                Color(celebrationHex: 0x93C5FD),
                Color(celebrationHex: 0xE0F0FF),
                Color(celebrationHex: 0x3B82F6),
                .white
            ]
        }
    }
}

// MARK: - Color Hex Convenience

extension Color {
    /// Create a `Color` from a hex integer, e.g. `Color(celebrationHex: 0x7B68EE)`.
    /// Uses a unique label to avoid collisions with other hex initializers in the project.
    fileprivate init(celebrationHex hex: UInt, opacity: Double = 1.0) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >>  8) & 0xFF) / 255.0,
            blue:  Double( hex        & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}

// MARK: - Confetti Particle Model

/// A single confetti particle with full physics state.
struct ConfettiParticle {
    var position: CGPoint
    var velocity: CGPoint
    var rotation: Double          // current angle in radians
    var rotationSpeed: Double     // radians / second
    var opacity: Double
    var scale: Double
    var color: Color
    var isCircle: Bool            // true = circle (3-5pt), false = rectangle (2x8pt)
    var size: CGFloat             // radius for circles, width for rectangles
    var age: Double = 0           // seconds since spawn
    static let lifespan: Double = 2.5
    static let fadeStart: Double = 1.5 // opacity starts dropping here
}

// MARK: - ConfettiView (Canvas + TimelineView, 60 fps)

/// Renders 40-50 confetti particles using a Metal-backed `Canvas`.
/// Particles burst outward from the center, then drift down under gravity.
struct ConfettiView: View {
    let colors: [Color]
    let trigger: Bool // flip to `true` to start the burst

    @State private var particles: [ConfettiParticle] = []
    @State private var lastTime: Date? = nil
    @State private var hasBurst = false

    // Physics constants
    private let gravity: CGFloat   = 400   // pt/s^2
    private let particleCount      = 45    // 40-50 range

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    for particle in particles where particle.opacity > 0.01 {
                        // Build a transform: translate -> rotate -> scale
                        var ctx = context
                        ctx.translateBy(x: particle.position.x, y: particle.position.y)
                        ctx.rotate(by: .radians(particle.rotation))
                        ctx.scaleBy(x: particle.scale, y: particle.scale)
                        ctx.opacity = particle.opacity

                        if particle.isCircle {
                            let r = particle.size
                            let rect = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
                            ctx.fill(Circle().path(in: rect), with: .color(particle.color))
                        } else {
                            // Thin rectangle: 2pt x 8pt
                            let rect = CGRect(x: -1, y: -4, width: 2, height: 8)
                            ctx.fill(Rectangle().path(in: rect), with: .color(particle.color))
                        }
                    }
                }
                .onChange(of: timeline.date) { _, newDate in
                    updatePhysics(now: newDate, canvasSize: geo.size)
                }
            }
            .onChange(of: trigger) { _, shouldBurst in
                if shouldBurst && !hasBurst {
                    spawnParticles(in: geo.size)
                    hasBurst = true
                }
            }
        }
        .allowsHitTesting(false) // confetti never blocks taps
    }

    // MARK: Spawn

    /// Creates all particles at the center with random outward velocities.
    private func spawnParticles(in size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var batch: [ConfettiParticle] = []
        batch.reserveCapacity(particleCount)

        for _ in 0..<particleCount {
            // Random angle (full circle) and magnitude (200-500 pt/s)
            let angle = Double.random(in: 0 ..< 2 * .pi)
            let speed = Double.random(in: 200...500)
            let vx = cos(angle) * speed
            let vy = sin(angle) * speed

            let isCircle = Bool.random()
            let particleSize: CGFloat = isCircle
                ? CGFloat.random(in: 3...5)   // circle radius
                : CGFloat.random(in: 2...3)   // rect width (height fixed at 8)

            let particle = ConfettiParticle(
                position: center,
                velocity: CGPoint(x: vx, y: vy),
                rotation: Double.random(in: 0 ..< 2 * .pi),
                rotationSpeed: Double.random(in: -8...8),  // rad/s
                opacity: 1.0,
                scale: Double.random(in: 0.8...1.2),
                color: colors.randomElement() ?? .white,
                isCircle: isCircle,
                size: particleSize
            )
            batch.append(particle)
        }

        particles = batch
        lastTime = Date()
    }

    // MARK: Physics Step

    /// Integrates position, velocity (with gravity), rotation, and opacity.
    private func updatePhysics(now: Date, canvasSize: CGSize) {
        guard let last = lastTime, !particles.isEmpty else { return }
        let dt = now.timeIntervalSince(last)
        guard dt > 0, dt < 0.5 else {
            // Guard against huge jumps (e.g. coming back from background)
            lastTime = now
            return
        }
        lastTime = now

        for i in particles.indices {
            // Age
            particles[i].age += dt

            // Position integration
            particles[i].position.x += particles[i].velocity.x * dt
            particles[i].position.y += particles[i].velocity.y * dt

            // Gravity (downward only)
            particles[i].velocity.y += gravity * dt

            // Light air resistance for a floatier feel
            particles[i].velocity.x *= (1 - 0.3 * dt)

            // Rotation
            particles[i].rotation += particles[i].rotationSpeed * dt

            // Opacity: full until fadeStart, then linearly fade to 0 by lifespan
            let age = particles[i].age
            if age > ConfettiParticle.fadeStart {
                let fadeDuration = ConfettiParticle.lifespan - ConfettiParticle.fadeStart
                let progress = (age - ConfettiParticle.fadeStart) / fadeDuration
                particles[i].opacity = max(0, 1 - progress)
            }
        }

        // Remove dead particles to stop rendering overhead
        particles.removeAll { $0.opacity <= 0.01 }
    }
}

// MARK: - MilestoneCelebrationView

/// The full-screen overlay composed of three Z-layers:
///   1. Radial gradient background
///   2. Confetti particle canvas
///   3. Hero content (icon + title + subtitle)
struct MilestoneCelebrationView: View {
    let type: CelebrationType
    var onDismiss: () -> Void

    // MARK: Animation State

    // --- Background (Base Layer) ---
    @State private var backgroundOpacity: Double = 0

    // --- Hero icon (Top Layer) ---
    @State private var iconScale: Double = 0
    @State private var iconOpacity: Double = 0

    // --- Title ---
    @State private var titleOffset: CGFloat = 20
    @State private var titleOpacity: Double = 0

    // --- Subtitle ---
    @State private var subtitleOffset: CGFloat = 15
    @State private var subtitleOpacity: Double = 0

    // --- Confetti trigger ---
    @State private var confettiBurst: Bool = false

    // --- Dismiss ---
    @State private var isDismissing: Bool = false
    @State private var dismissScale: Double = 1
    @State private var dismissOpacity: Double = 1

    // Auto-dismiss timer
    @State private var autoDismissTask: Task<Void, Never>? = nil

    // Haptic generator (pre-warmed for minimal latency)
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ZStack {
            // -------------------------------------------------------
            // LAYER 1 — Base: Animated radial gradient background
            // -------------------------------------------------------
            RadialGradient(
                gradient: Gradient(colors: [
                    type.gradientColor.opacity(0.6),
                    type.accentColor.opacity(0.3),
                    Color.black.opacity(0.7)
                ]),
                center: .center,
                startRadius: 0,
                endRadius: 500
            )
            .ignoresSafeArea()
            .opacity(backgroundOpacity)

            // -------------------------------------------------------
            // LAYER 2 — Middle: Confetti particle system
            // -------------------------------------------------------
            ConfettiView(colors: type.confettiColors, trigger: confettiBurst)
                .ignoresSafeArea()

            // -------------------------------------------------------
            // LAYER 3 — Top: Hero content
            // -------------------------------------------------------
            VStack(spacing: 20) {
                // Icon badge: 100pt circle, accent fill, white SF Symbol at 60pt
                ZStack {
                    Circle()
                        .fill(type.accentColor)
                        .frame(width: 100, height: 100)
                        .shadow(color: type.accentColor.opacity(0.4), radius: 20, y: 8)

                    Image(systemName: type.icon)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)

                // Title
                Text(type.title)
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .offset(y: titleOffset)
                    .opacity(titleOpacity)

                // Subtitle
                Text(type.subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(y: subtitleOffset)
                    .opacity(subtitleOpacity)
            }
        }
        // Whole-overlay dismiss transforms
        .scaleEffect(dismissScale)
        .opacity(dismissOpacity)
        // Tap anywhere to dismiss
        .contentShape(Rectangle())
        .onTapGesture {
            dismiss()
        }
        .onAppear {
            haptic.prepare()
            runEntrySequence()
            scheduleAutoDismiss()
        }
        .onDisappear {
            autoDismissTask?.cancel()
        }
    }

    // MARK: - Animation Timeline
    //
    //   0ms:   Background fades in (0 -> 0.8), easeOut 0.3s
    // 100ms:   Icon scales 0 -> 1.2 -> 1.0 (spring response 0.5, damping 0.6)
    //          + Haptic .medium fires
    // 200ms:   Confetti burst spawns
    // 400ms:   Title slides up 20pt + fades in (spring response 0.6, damping 0.8)
    // 550ms:   Subtitle slides up 15pt + fades in (spring response 0.6, damping 0.8)

    private func runEntrySequence() {
        // 0ms — Background
        withAnimation(.easeOut(duration: 0.3)) {
            backgroundOpacity = 0.8
        }

        // 100ms — Icon pop + haptic
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            haptic.impactOccurred()

            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            // Briefly overshoot handled by the spring's underdamped bounce.
            // The spring with dampingFraction 0.6 naturally overshoots to ~1.2
            // before settling at 1.0, achieving the desired 0 -> ~1.2 -> 1.0 arc.
        }

        // 200ms — Confetti burst
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            confettiBurst = true
        }

        // 400ms — Title
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                titleOffset = 0
                titleOpacity = 1.0
            }
        }

        // 550ms — Subtitle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                subtitleOffset = 0
                subtitleOpacity = 1.0
            }
        }
    }

    // MARK: - Dismiss

    /// Reverse animation: scale down + fade out, 0.3s easeIn, then call onDismiss.
    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        autoDismissTask?.cancel()

        withAnimation(.easeIn(duration: 0.3)) {
            dismissScale = 0.85
            dismissOpacity = 0
        }

        // Allow the animation to finish before removing from the view hierarchy.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }

    /// Auto-dismiss after 3 seconds if the user hasn't tapped.
    private func scheduleAutoDismiss() {
        autoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !isDismissing else { return }
            dismiss()
        }
    }
}

// MARK: - ViewModifier

/// Attaches a milestone celebration overlay to any view.
///
/// ```swift
/// @State private var celebration: CelebrationType? = nil
///
/// MyView()
///     .milestoneCelebration($celebration)
/// ```
struct MilestoneCelebrationModifier: ViewModifier {
    @Binding var celebration: CelebrationType?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let type = celebration {
                    MilestoneCelebrationView(type: type) {
                        celebration = nil
                    }
                    .transition(.identity) // we handle our own transitions
                }
            }
            // Using .animation here so the overlay removal is also animated.
            .animation(.easeInOut(duration: 0.15), value: celebration == nil)
    }
}

// MARK: - View Extension

extension View {
    /// Presents a full-screen milestone celebration overlay.
    ///
    /// Set the binding to a `CelebrationType` to trigger; it resets to `nil`
    /// automatically when the user taps or after 3 seconds.
    ///
    /// ```swift
    /// @State private var celebration: CelebrationType? = nil
    ///
    /// Button("Celebrate") { celebration = .goalMet }
    ///     .milestoneCelebration($celebration)
    /// ```
    func milestoneCelebration(_ celebration: Binding<CelebrationType?>) -> some View {
        modifier(MilestoneCelebrationModifier(celebration: celebration))
    }
}

// MARK: - Preview

#Preview("Property Added") {
    ZStack {
        Color(celebrationHex: 0x1A1A2E).ignoresSafeArea()

        MilestoneCelebrationView(type: .propertyAdded) {
            print("Dismissed")
        }
    }
}

#Preview("Goal Met") {
    ZStack {
        Color(celebrationHex: 0x1A1A2E).ignoresSafeArea()

        MilestoneCelebrationView(type: .goalMet) {
            print("Dismissed")
        }
    }
}

#Preview("Interactive") {
    InteractiveCelebrationPreview()
}

/// A small preview harness that lets you trigger each celebration type.
private struct InteractiveCelebrationPreview: View {
    @State private var celebration: CelebrationType? = nil

    var body: some View {
        VStack(spacing: 16) {
            Text("Tap a button to celebrate")
                .font(.headline)

            Group {
                Button("Property Added")  { celebration = .propertyAdded }
                Button("Goal Met")        { celebration = .goalMet }
                Button("Task Done")       { celebration = .taskDone }
                Button("Weekly Streak")   { celebration = .weeklyStreak }
                Button("Hours Logged")    { celebration = .hoursLogged }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(celebrationHex: 0x7B68EE))
        }
        .milestoneCelebration($celebration)
    }
}

