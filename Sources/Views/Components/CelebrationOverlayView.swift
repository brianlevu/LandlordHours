import SwiftUI
import LucideIcons

// MARK: - Celebration Type

enum CelebrationType: Identifiable, Equatable {
    case propertyAdded
    case goalMet
    case greatWork
    case weeklyStreak
    case hoursLogged(milestone: Int)

    var id: String {
        switch self {
        case .propertyAdded: return "propertyAdded"
        case .goalMet: return "goalMet"
        case .greatWork: return "greatWork"
        case .weeklyStreak: return "weeklyStreak"
        case .hoursLogged(let m): return "hoursLogged_\(m)"
        }
    }

    var title: String {
        switch self {
        case .propertyAdded: return "Property Added!"
        case .goalMet: return "Goal Met!"
        case .greatWork: return "Great Work!"
        case .weeklyStreak: return "On Fire!"
        case .hoursLogged(let m): return "\(m) Hours!"
        }
    }

    var subtitle: String {
        switch self {
        case .propertyAdded: return "Your journey begins"
        case .goalMet: return "You\u{2019}ve qualified \u{2014} amazing work"
        case .greatWork: return "Keep up the momentum"
        case .weeklyStreak: return "3 weeks in a row"
        case .hoursLogged: return "Every hour counts"
        }
    }

    var accent: Color {
        switch self {
        case .propertyAdded: return AppColors.primary
        case .goalMet: return AppColors.success
        case .greatWork: return AppColors.honey
        case .weeklyStreak: return AppColors.coral
        case .hoursLogged: return AppColors.sky
        }
    }

    var gradient: Color {
        switch self {
        case .propertyAdded: return Color(hex: "A78BFA")
        case .goalMet: return Color(hex: "6EE7B7")
        case .greatWork: return Color(hex: "FDE68A")
        case .weeklyStreak: return Color(hex: "FFB4A9")
        case .hoursLogged: return Color(hex: "93C5FD")
        }
    }

    var confettiColors: [Color] {
        switch self {
        case .propertyAdded:
            return [Color(hex: "7B68EE"), Color(hex: "A78BFA"), Color(hex: "EDE8FF"), Color(hex: "B8AFFE"), .white]
        case .goalMet:
            return [Color(hex: "34D399"), Color(hex: "6EE7B7"), Color(hex: "ECFDF5"), Color(hex: "059669"), .white]
        case .greatWork:
            return [Color(hex: "F5C563"), Color(hex: "FDE68A"), Color(hex: "FFF4DA"), Color(hex: "D97706"), .white]
        case .weeklyStreak:
            return [Color(hex: "FF8A7A"), Color(hex: "FFB4A9"), Color(hex: "FFE8E4"), Color(hex: "E55A4A"), .white]
        case .hoursLogged:
            return [Color(hex: "6CB4EE"), Color(hex: "93C5FD"), Color(hex: "E0F0FF"), Color(hex: "3B82F6"), .white]
        }
    }

    var iconImage: UIImage {
        switch self {
        case .propertyAdded: return Lucide.house
        case .goalMet: return Lucide.circleCheck
        case .greatWork: return Lucide.sparkles
        case .weeklyStreak: return Lucide.flame
        case .hoursLogged: return Lucide.clock
        }
    }
}

// MARK: - Milestone Tracker

/// Tracks which hour milestones have already been celebrated to avoid duplicates.
final class MilestoneTracker {
    static let shared = MilestoneTracker()

    private var key: String { UserScope.key("LandlordHours.celebratedMilestones") }

    private var celebrated: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: key) }
    }

    func shouldCelebrate(_ type: CelebrationType, year: Int) -> Bool {
        let id = "\(year)_\(type.id)"
        return !celebrated.contains(id)
    }

    func markCelebrated(_ type: CelebrationType, year: Int) {
        let id = "\(year)_\(type.id)"
        var set = celebrated
        set.insert(id)
        celebrated = set
    }

    /// Reload from UserDefaults (e.g. after user switch)
    func reload() {
        // No in-memory cache to reset — `celebrated` reads directly from UserDefaults
    }
}

// MARK: - Confetti Particle

private struct ConfettiParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var rotation: CGFloat
    var rotSpeed: CGFloat
    var opacity: CGFloat
    var scale: CGFloat
    var color: Color
    var isCircle: Bool
    var size: CGFloat
    var age: CGFloat
}

// MARK: - Confetti Canvas

private struct ConfettiCanvasView: View {
    let colors: [Color]
    let particleCount: Int = 45
    let startTime: Date

    @State private var particles: [ConfettiParticle] = []

    private let gravity: CGFloat = 400
    private let lifespan: CGFloat = 2.5
    private let fadeStart: CGFloat = 1.5

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = CGFloat(context.date.timeIntervalSince(startTime))
            Canvas { gfx, size in
                drawParticles(context: gfx, size: size, elapsed: elapsed)
            }
        }
        .onAppear {
            spawnParticles()
        }
    }

    private func spawnParticles() {
        particles = (0..<particleCount).map { _ in
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed: CGFloat = 200 + CGFloat.random(in: 0...300)
            let isCircle = Bool.random()

            return ConfettiParticle(
                x: 0, y: 0,
                vx: cos(angle) * speed,
                vy: sin(angle) * speed,
                rotation: CGFloat.random(in: 0...(2 * .pi)),
                rotSpeed: CGFloat.random(in: -8...8),
                opacity: 1,
                scale: 0.8 + CGFloat.random(in: 0...0.4),
                color: colors.randomElement() ?? .white,
                isCircle: isCircle,
                size: isCircle ? (3 + CGFloat.random(in: 0...2)) : (2 + CGFloat.random(in: 0...1)),
                age: 0
            )
        }
    }

    private func drawParticles(context: GraphicsContext, size: CGSize, elapsed: CGFloat) {
        let cx = size.width / 2
        let cy = size.height / 2

        for particle in particles {
            let t = elapsed
            guard t < lifespan else { continue }

            let px = cx + particle.x + particle.vx * t
            let py = cy + particle.y + particle.vy * t + 0.5 * gravity * t * t
            let damping = pow(1 - 0.3 * min(t, 1), max(t, 1))
            let dampedPx = cx + (particle.vx * t * damping) + particle.x
            let _ = dampedPx // Use simpler physics

            let rot = particle.rotation + particle.rotSpeed * t

            var alpha: CGFloat = 1
            if t > fadeStart {
                let fadeProgress = (t - fadeStart) / (lifespan - fadeStart)
                alpha = max(0, 1 - fadeProgress)
            }
            guard alpha > 0.01 else { continue }

            var ctx = context
            ctx.opacity = alpha * Double(particle.opacity)

            let transform = CGAffineTransform.identity
                .translatedBy(x: px, y: py)
                .rotated(by: rot)
                .scaledBy(x: particle.scale, y: particle.scale)

            if particle.isCircle {
                let circle = Path(ellipseIn: CGRect(
                    x: -particle.size, y: -particle.size,
                    width: particle.size * 2, height: particle.size * 2
                ))
                ctx.fill(circle.applying(transform), with: .color(particle.color))
            } else {
                let rect = Path(CGRect(x: -1, y: -4, width: 2, height: 8))
                ctx.fill(rect.applying(transform), with: .color(particle.color))
            }
        }
    }
}

// MARK: - Celebration Overlay View

struct CelebrationOverlayView: View {
    let type: CelebrationType
    let onDismiss: () -> Void

    @State private var showBackground = false
    @State private var showIcon = false
    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var showConfetti = false
    @State private var dismissing = false
    @State private var confettiStartTime = Date()

    var body: some View {
        ZStack {
            // Radial gradient background
            RadialGradient(
                colors: [
                    type.gradient.opacity(0.6),
                    type.accent.opacity(0.3),
                    Color.black.opacity(0.75)
                ],
                center: .center,
                startRadius: 0,
                endRadius: 500
            )
            .ignoresSafeArea()
            .opacity(showBackground ? 1 : 0)

            // Confetti
            if showConfetti {
                ConfettiCanvasView(colors: type.confettiColors, startTime: confettiStartTime)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Hero content
            VStack(spacing: 20) {
                // Icon badge
                ZStack {
                    Circle()
                        .fill(type.accent)
                        .frame(width: 100, height: 100)
                        .shadow(color: type.accent.opacity(0.4), radius: 30, y: 8)

                    Image(uiImage: type.iconImage.withRenderingMode(.alwaysTemplate))
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.white)
                }
                .scaleEffect(showIcon ? 1 : 0)
                .opacity(showIcon ? 1 : 0)

                // Title
                Text(type.title)
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(.white)
                    .offset(y: showTitle ? 0 : 20)
                    .opacity(showTitle ? 1 : 0)

                // Subtitle
                Text(type.subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(y: showSubtitle ? 0 : 15)
                    .opacity(showSubtitle ? 1 : 0)
            }
        }
        .scaleEffect(dismissing ? 0.85 : 1)
        .opacity(dismissing ? 0 : 1)
        .onTapGesture {
            dismiss()
        }
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        // Background fades in
        withAnimation(.easeOut(duration: 0.3)) {
            showBackground = true
        }

        // Icon springs in at 100ms
        withAnimation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.1)) {
            showIcon = true
        }

        // Confetti at 200ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            confettiStartTime = Date()
            showConfetti = true
        }

        // Title at 350ms
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.35)) {
            showTitle = true
        }

        // Subtitle at 500ms
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.5)) {
            showSubtitle = true
        }

        // Auto-dismiss after 3s
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            dismiss()
        }
    }

    private func dismiss() {
        guard !dismissing else { return }
        withAnimation(.easeIn(duration: 0.3)) {
            dismissing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(hex: "FAF7F2").ignoresSafeArea()
        CelebrationOverlayView(type: .goalMet) {}
    }
}
