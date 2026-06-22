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

    func reload() {}
}

// MARK: - Confetti Shape Types

private enum ConfettiShape {
    case dot          // Small circle
    case square       // Tiny square
    case rectangle    // Thin rectangle
    case crescent     // Half-moon / arc
    case squiggle     // Short curved line
}

// MARK: - Confetti Piece

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let shape: ConfettiShape
    let color: Color
    let size: CGFloat          // Base size
    let startX: CGFloat        // Starting X position (0...1 ratio)
    let xDrift: CGFloat        // Horizontal drift during fall
    let fallDistance: CGFloat   // How far it falls (screen heights)
    let spinDegrees: Double    // 2D rotation
    let flipAxis: (x: CGFloat, y: CGFloat, z: CGFloat)
    let flipDegrees: Double    // 3D tumble
    let delay: Double          // Stagger
    let duration: Double       // Individual animation duration
    let opacity: Double        // Base opacity
}

// MARK: - Single Piece View

private struct ConfettiPieceShape: View {
    let shape: ConfettiShape
    let size: CGFloat

    var body: some View {
        switch shape {
        case .dot:
            Circle()
                .frame(width: size, height: size)
        case .square:
            RoundedRectangle(cornerRadius: 1.5)
                .frame(width: size, height: size)
        case .rectangle:
            RoundedRectangle(cornerRadius: 1)
                .frame(width: size * 0.35, height: size)
        case .crescent:
            CrescentShape()
                .frame(width: size, height: size)
        case .squiggle:
            SquiggleShape()
                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: size * 0.6, height: size)
        }
    }
}

// Crescent / half-moon shape
private struct CrescentShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        // Outer arc
        p.addArc(center: center, radius: r, startAngle: .degrees(-30), endAngle: .degrees(210), clockwise: false)
        // Inner arc cutting back
        p.addArc(center: CGPoint(x: center.x + r * 0.3, y: center.y), radius: r * 0.75,
                 startAngle: .degrees(210), endAngle: .degrees(-30), clockwise: true)
        p.closeSubpath()
        return p
    }
}

// Short squiggle / curve
private struct SquiggleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: rect.midX - rect.width * 0.2, y: rect.midY - rect.height * 0.3),
            control2: CGPoint(x: rect.midX + rect.width * 0.2, y: rect.midY + rect.height * 0.3)
        )
        return p
    }
}

// MARK: - Confetti Particle View

private struct ConfettiParticleView: View {
    let piece: ConfettiPiece
    let animate: Bool
    let screenHeight: CGFloat

    var body: some View {
        ConfettiPieceShape(shape: piece.shape, size: piece.size)
            .foregroundStyle(piece.color)
            .rotation3DEffect(
                .degrees(animate ? piece.flipDegrees : 0),
                axis: (x: piece.flipAxis.x, y: piece.flipAxis.y, z: piece.flipAxis.z)
            )
            .rotationEffect(.degrees(animate ? piece.spinDegrees : 0))
            .offset(
                x: animate ? piece.xDrift : 0,
                y: animate ? piece.fallDistance * screenHeight : -80
            )
            .opacity(animate ? 0 : piece.opacity)
    }
}

// MARK: - Confetti Rain View (Tiimo-style — no overlay, just confetti)

struct ConfettiRainView: View {
    let particleCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false
    @State private var pieces: [ConfettiPiece] = []

    // Dark purple palette matching Tiimo
    private let confettiColors: [Color] = [
        AppColors.celebrationDeepPurple,
        AppColors.celebrationPurple,
        AppColors.primary,
        AppColors.celebrationIndigo,
        AppColors.celebrationLavender,
        AppColors.reportsAccentSoft,
        AppColors.celebrationNightPurple,
    ]

    init(particleCount: Int = 55) {
        self.particleCount = particleCount
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { piece in
                    ConfettiParticleView(
                        piece: piece,
                        animate: animate,
                        screenHeight: geo.size.height
                    )
                    .position(
                        x: piece.startX * geo.size.width,
                        y: 0
                    )
                    .animation(
                        // Gentle ease-in at start, very slow ease-out = floaty drift
                        reduceMotion ? nil : Animation.timingCurve(0.1, 0.4, 0.2, 1.0, duration: piece.duration).delay(piece.delay),
                        value: animate
                    )
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                pieces = (0..<particleCount).map { _ in makePiece() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    animate = true
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func makePiece() -> ConfettiPiece {
        // Pick shape with distribution matching Tiimo:
        // crescents + squiggles are most common, then dots, then squares/rectangles
        let shapeRoll = Double.random(in: 0...1)
        let shape: ConfettiShape
        if shapeRoll < 0.25 {
            shape = .crescent
        } else if shapeRoll < 0.45 {
            shape = .squiggle
        } else if shapeRoll < 0.65 {
            shape = .dot
        } else if shapeRoll < 0.82 {
            shape = .rectangle
        } else {
            shape = .square
        }

        let size: CGFloat
        switch shape {
        case .dot: size = CGFloat.random(in: 6...14)
        case .square: size = CGFloat.random(in: 6...10)
        case .rectangle: size = CGFloat.random(in: 16...28)
        case .crescent: size = CGFloat.random(in: 12...22)
        case .squiggle: size = CGFloat.random(in: 14...22)
        }

        return ConfettiPiece(
            shape: shape,
            color: confettiColors.randomElement()!,
            size: size,
            startX: CGFloat.random(in: 0.02...0.98),
            xDrift: CGFloat.random(in: -40...40),           // Gentle horizontal sway
            fallDistance: CGFloat.random(in: 0.8...1.4),     // Full screen drift
            spinDegrees: Double.random(in: -200...200),      // Gentle spin, not frantic
            flipAxis: (
                x: CGFloat.random(in: 0...1),
                y: CGFloat.random(in: 0...1),
                z: CGFloat.random(in: 0...0.3)
            ),
            flipDegrees: Double.random(in: 180...720),       // Gentle 3D tumble
            delay: Double.random(in: 0...0.8),               // Wide stagger = cascading waves
            duration: Double.random(in: 3.0...4.5),          // Slow, floaty drift
            opacity: Double.random(in: 0.55...0.9)
        )
    }
}

// MARK: - Celebration Overlay View
// Now just shows confetti rain — no dark overlay, no icon/text.
// The confetti plays on top of the existing screen content.

struct CelebrationOverlayView: View {
    let type: CelebrationType
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showConfetti = false
    @State private var dismissing = false

    var body: some View {
        ZStack {
            if showConfetti {
                ConfettiRainView(particleCount: 55)
            }
        }
        .opacity(dismissing ? 0 : 1)
        .onTapGesture {
            dismiss()
        }
        .onAppear {
            showConfetti = true
            // Auto-dismiss after confetti drifts off screen
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
                dismiss()
            }
        }
    }

    private func dismiss() {
        guard !dismissing else { return }
        animate(.easeOut(duration: 0.3)) {
            dismissing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }

    private func animate(_ animation: Animation = AppAnimation.smooth, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }
}

#Preview {
    ZStack {
        AppColors.background.ignoresSafeArea()
        VStack {
            Text("Some content underneath")
                .font(.title)
            Text("Confetti plays on top")
        }
        CelebrationOverlayView(type: .propertyAdded) {}
    }
}
