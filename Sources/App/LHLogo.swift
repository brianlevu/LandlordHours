import SwiftUI

// MARK: - LandlordHours Logo
// A custom SwiftUI-rendered logo combining a house + clock motif
// in a soft, modern, Tiimo-inspired style

struct LHLogo: View {
    var size: CGFloat = 80
    var showText: Bool = true
    var animated: Bool = false

    @State private var appeared = false

    var body: some View {
        VStack(spacing: size * 0.2) {
            logoMark
            if showText {
                logoText
            }
        }
        .onAppear {
            if animated {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                    appeared = true
                }
            } else {
                appeared = true
            }
        }
    }

    // MARK: - Logo Mark (Icon)
    private var logoMark: some View {
        ZStack {
            // Background circle with gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "8B5CF6"),
                            Color(hex: "6D28D9")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: Color(hex: "8B5CF6").opacity(0.35), radius: size * 0.15, y: size * 0.06)

            // House + Clock composite icon
            LogoShape()
                .fill(.white)
                .frame(width: size * 0.52, height: size * 0.52)
        }
        .scaleEffect(appeared ? 1 : 0.3)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: - Logo Text
    private var logoText: some View {
        VStack(spacing: size * 0.04) {
            Text("Landlord")
                .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
            +
            Text("Hours")
                .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "8B5CF6"))
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
    }
}

// MARK: - Logo Shape (House with clock hands)
struct LogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let ox = rect.minX + (rect.width - s) / 2
        let oy = rect.minY + (rect.height - s) / 2

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x / 24 * s, y: oy + y / 24 * s)
        }
        func v(_ x: CGFloat) -> CGFloat { x / 24 * s }

        var path = Path()

        // House roof (pointed)
        path.move(to: p(12, 1.5))
        path.addLine(to: p(1, 11))
        path.addLine(to: p(3.5, 11))
        path.addLine(to: p(3.5, 21))
        path.addQuadCurve(to: p(5, 22.5), control: p(3.5, 22.5))
        path.addLine(to: p(19, 22.5))
        path.addQuadCurve(to: p(20.5, 21), control: p(20.5, 22.5))
        path.addLine(to: p(20.5, 11))
        path.addLine(to: p(23, 11))
        path.closeSubpath()

        // Clock circle cutout in the house body
        let clockCx = ox + v(12)
        let clockCy = oy + v(16)
        let clockR = v(4.5)
        path.addEllipse(in: CGRect(x: clockCx - clockR, y: clockCy - clockR, width: clockR * 2, height: clockR * 2))

        // Clock hands (drawn as separate filled paths for the cutout)
        // Hour hand (pointing up-left ~ 10 o'clock)
        path.addRoundedRect(in: CGRect(x: clockCx - v(0.5), y: clockCy - v(3.2), width: v(1), height: v(3.2)), cornerSize: CGSize(width: v(0.5), height: v(0.5)))

        // Minute hand (pointing right ~ 3 o'clock)
        path.addRoundedRect(in: CGRect(x: clockCx, y: clockCy - v(0.5), width: v(2.8), height: v(1)), cornerSize: CGSize(width: v(0.5), height: v(0.5)))

        // Center dot
        path.addEllipse(in: CGRect(x: clockCx - v(0.8), y: clockCy - v(0.8), width: v(1.6), height: v(1.6)))

        return path
    }
}

// MARK: - Compact Logo (for headers, nav bars)
struct LHCompactLogo: View {
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "8B5CF6"),
                            Color(hex: "6D28D9")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: Color(hex: "8B5CF6").opacity(0.25), radius: size * 0.12, y: size * 0.05)

            LogoShape()
                .fill(.white)
                .frame(width: size * 0.52, height: size * 0.52)
        }
    }
}

// MARK: - Wordmark (text-only logo)
struct LHWordmark: View {
    var fontSize: CGFloat = 28

    var body: some View {
        HStack(spacing: 0) {
            Text("Landlord")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
            Text("Hours")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "8B5CF6"))
        }
    }
}

// MARK: - Previews
#Preview("Logo Sizes") {
    VStack(spacing: 40) {
        LHLogo(size: 120, showText: true, animated: true)

        HStack(spacing: 24) {
            LHLogo(size: 64, showText: false)
            LHLogo(size: 48, showText: false)
            LHCompactLogo(size: 32)
        }

        LHWordmark(fontSize: 28)
    }
    .padding()
}
