import SwiftUI

// MARK: - LandlordHours Logo
// Wave-house icon — house silhouette filled with flowing violet gradient waves
// Matches the app icon (Variant A) from figma-redesign/app-icons.html

struct LHLogo: View {
    var size: CGFloat = 80
    var showText: Bool = true
    var animated: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: size * 0.2) {
            logoMark
            if showText {
                logoText
            }
        }
        .onAppear {
            if animated && !reduceMotion {
                withAnimation(AppAnimation.logoEntrance.delay(0.1)) {
                    appeared = true
                }
            } else {
                appeared = true
            }
        }
    }

    // MARK: - Logo Mark (Wave House Icon)
    private var logoMark: some View {
        WaveHouseIcon(size: size)
            .shadow(color: AppColors.primary.opacity(0.3), radius: size * 0.15, y: size * 0.06)
            .scaleEffect(appeared ? 1 : 0.3)
            .opacity(appeared ? 1 : 0)
    }

    // MARK: - Logo Text
    private var logoText: some View {
        VStack(spacing: size * 0.04) {
            (
                Text("Landlord")
                    .foregroundColor(AppColors.charcoal)
                +
                Text("Hours")
                    .foregroundColor(AppColors.primary)
            )
            .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
    }
}

// MARK: - Wave House Icon (self-contained, any size)
/// The primary brand mark — a house silhouette clipped with flowing violet gradient waves
struct WaveHouseIcon: View {
    var size: CGFloat = 80

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width
            let scale = s / 1024

            // Helper to scale points from 1024 coordinate space
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * scale, y: y * scale)
            }

            // 1. Background fill
            let bgRect = CGRect(origin: .zero, size: canvasSize)
            context.fill(Path(bgRect), with: .color(AppColors.logoCanvas))

            // 2. House clip path
            var housePath = Path()
            housePath.move(to: p(512, 140))
            housePath.addLine(to: p(168, 390))
            housePath.addLine(to: p(168, 880))
            housePath.addQuadCurve(to: p(198, 910), control: p(168, 910))
            housePath.addLine(to: p(826, 910))
            housePath.addQuadCurve(to: p(856, 880), control: p(856, 910))
            housePath.addLine(to: p(856, 390))
            housePath.closeSubpath()
            // Chimney
            housePath.move(to: p(700, 180))
            housePath.addLine(to: p(700, 280))
            housePath.addLine(to: p(780, 280))
            housePath.addLine(to: p(780, 250))
            housePath.addQuadCurve(to: p(740, 180), control: p(780, 180))
            housePath.closeSubpath()

            context.clipToLayer { ctx in
                ctx.fill(housePath, with: .color(.white))
            }

            // 3. Base gradient (lightest violet)
            let bgGradient = Gradient(colors: [AppColors.logoWaveLightStart, AppColors.primaryLight])
            context.fill(Path(bgRect), with: .linearGradient(bgGradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: s)))

            // 4. Wave 1 — light violet
            var wave1 = Path()
            wave1.move(to: p(0, 380))
            wave1.addQuadCurve(to: p(400, 370), control: p(200, 310))
            wave1.addQuadCurve(to: p(800, 360), control: p(600, 430))
            wave1.addQuadCurve(to: p(1024, 350), control: p(900, 330))
            wave1.addLine(to: p(1024, 1024))
            wave1.addLine(to: p(0, 1024))
            wave1.closeSubpath()
            let w1Gradient = Gradient(colors: [AppColors.logoWaveMidStart, AppColors.logoWaveMidEnd])
            context.fill(wave1, with: .linearGradient(w1Gradient, startPoint: .zero, endPoint: CGPoint(x: s, y: s)))

            // 5. Wave 2 — mid violet
            var wave2 = Path()
            wave2.move(to: p(0, 520))
            wave2.addQuadCurve(to: p(480, 510), control: p(250, 440))
            wave2.addQuadCurve(to: p(900, 480), control: p(700, 580))
            wave2.addQuadCurve(to: p(1024, 470), control: p(980, 450))
            wave2.addLine(to: p(1024, 1024))
            wave2.addLine(to: p(0, 1024))
            wave2.closeSubpath()
            let w2Gradient = Gradient(colors: [AppColors.logoWaveStrongStart, AppColors.primary])
            context.fill(wave2, with: .linearGradient(w2Gradient, startPoint: .zero, endPoint: CGPoint(x: s, y: s)))

            // 6. Wave 3 — deep violet
            var wave3 = Path()
            wave3.move(to: p(0, 660))
            wave3.addQuadCurve(to: p(420, 650), control: p(220, 590))
            wave3.addQuadCurve(to: p(850, 620), control: p(650, 720))
            wave3.addQuadCurve(to: p(1024, 610), control: p(950, 580))
            wave3.addLine(to: p(1024, 1024))
            wave3.addLine(to: p(0, 1024))
            wave3.closeSubpath()
            let w3Gradient = Gradient(colors: [AppColors.logoWaveDeepStart, AppColors.logoWaveDeepEnd])
            context.fill(wave3, with: .linearGradient(w3Gradient, startPoint: .zero, endPoint: CGPoint(x: s * 0.5, y: s)))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

// MARK: - Compact Logo (for headers, nav bars)
struct LHCompactLogo: View {
    var size: CGFloat = 32

    var body: some View {
        WaveHouseIcon(size: size)
            .shadow(color: AppColors.primary.opacity(0.25), radius: size * 0.12, y: size * 0.05)
    }
}

// MARK: - Wordmark (text-only logo)
struct LHWordmark: View {
    var fontSize: CGFloat = 28

    var body: some View {
        HStack(spacing: 0) {
            Text("Landlord")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.charcoal)
            Text("Hours")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.primary)
        }
    }
}

// MARK: - Previews
#Preview("Logo Sizes") {
    VStack(spacing: 40) {
        LHLogo(size: 120, showText: true, animated: true)

        HStack(spacing: 24) {
            WaveHouseIcon(size: 64)
            WaveHouseIcon(size: 48)
            LHCompactLogo(size: 32)
        }

        LHWordmark(fontSize: 28)
    }
    .padding()
    .background(AppColors.background)
}
