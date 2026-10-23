import SwiftUI
import UIKit

#if DEBUG
// MARK: - Time-of-day sky for the hero ("your work shows up")
//
// The hero paper follows the phone clock: dawn (5–8) a soft warm gradient, day (8–17) the
// blueprint blue, dusk (17–20) warmer, night (20–5) deep navy with the house's windows lit.
// It is a state, not a scene (standard B.4): read on appear and at each hour boundary by one
// sleeping task, so CPU stays at idle; a change of phase is a 3s crossfade (none with Reduce Motion). The card is theme-fixed, so
// light and dark mode share it. Every gradient stop keeps the hero text at AA: worst pair 4.94:1
// (amber status on the dawn horizon), see StdSkyPhase.colors.
//
// `-LHSkyTime dawn|day|dusk|night` pins a phase for captures.

enum StdSkyPhase: String, CaseIterable {
    case dawn, day, dusk, night

    static let forced: StdSkyPhase? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LHSkyTime"), args.indices.contains(i + 1) else { return nil }
        return StdSkyPhase(rawValue: args[i + 1])
    }()

    static func at(_ date: Date) -> StdSkyPhase {
        if let forced { return forced }
        switch Calendar.current.component(.hour, from: date) {
        case 5..<8: return .dawn
        case 8..<17: return .day
        case 17..<20: return .dusk
        default: return .night
        }
    }

    /// Top → bottom. Minimum contrast against every hero text colour (white, #C9D6F5, amber
    /// #FFB454, green #7FE3A8, cyan #8FD3FF): dawn 4.94, day 5.14, dusk 5.46, night 8.32.
    var colors: [Color] {
        switch self {
        case .dawn: return [Self.c(0x2A3D90), Self.c(0x45408A), Self.c(0x5E3F6E)]
        case .day: return [HouseTokens.blueprint, HouseTokens.blueprintDeep]
        case .dusk: return [Self.c(0x24296E), Self.c(0x4A2C63), Self.c(0x6A324E)]
        case .night: return [Self.c(0x0B1230), Self.c(0x121A45), Self.c(0x1A2456)]
        }
    }

    private static func c(_ rgb: Int) -> Color {
        Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

/// The sky paper: one gradient per phase stacked, the current one at full opacity, plus the grid.
struct StdHeroSky: View {
    let phase: StdSkyPhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(StdSkyPhase.allCases, id: \.self) { p in
                LinearGradient(colors: p.colors, startPoint: .top, endPoint: .bottom)
                    .opacity(p == phase ? 1 : 0)
            }
            Canvas { context, size in
                let step: CGFloat = 22
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                context.stroke(path, with: .color(HouseTokens.drafting.opacity(0.07)), lineWidth: 0.5)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 3), value: phase)
        .accessibilityHidden(true)
    }
}

/// Night: the windows of the built house glow warm. The window panes are found once per keyframe
/// by colour (bright warm glass: value ≥ 0.97, saturation 0.15–0.45, hue 35–56°) and cached as a mask.
enum StdWindowGlow {
    private static var cache: [String: UIImage] = [:]

    static func mask(for imageName: String) -> UIImage? {
        if let hit = cache[imageName] { return hit }
        guard let src = UIImage(named: imageName)?.cgImage else { return nil }
        let w = src.width, h = src.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
        var found = 0
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = px[i + 3]
            var keep = false
            if a > 200 {
                let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
                let mx = max(r, g, b), mn = min(r, g, b)
                let s = mx > 0 ? (mx - mn) / mx : 0
                var hue = 0.0
                if mx != mn {
                    if mx == r { hue = 60 * ((g - b) / (mx - mn)) }
                    else if mx == g { hue = 60 * ((b - r) / (mx - mn) + 2) }
                    else { hue = 60 * ((r - g) / (mx - mn) + 4) }
                    if hue < 0 { hue += 360 }
                }
                keep = mx >= 0.97 && s >= 0.15 && s <= 0.45 && hue >= 35 && hue <= 56
            }
            if keep {
                px[i] = 255; px[i + 1] = 255; px[i + 2] = 255; px[i + 3] = 255; found += 1
            } else {
                px[i] = 0; px[i + 1] = 0; px[i + 2] = 0; px[i + 3] = 0
            }
        }
        guard found > 40, let out = ctx.makeImage() else { cache[imageName] = UIImage(); return nil }
        let img = UIImage(cgImage: out, scale: UIImage(named: imageName)?.scale ?? 3, orientation: .up)
        cache[imageName] = img
        return img
    }
}

/// The built house at night: dimmed, with its window panes lit and a soft warm halo around them.
struct StdNightHouse: View {
    let builtImageName: String
    let night: Bool

    var body: some View {
        ZStack {
            Image(decorative: builtImageName).resizable().interpolation(.high).scaledToFit()
                .brightness(night ? -0.22 : 0)
                .saturation(night ? 0.75 : 1)
            if night, let mask = StdWindowGlow.mask(for: builtImageName), mask.cgImage != nil {
                let glow = Color(red: 1.0, green: 0.80, blue: 0.48)
                Image(uiImage: mask).renderingMode(.template).resizable().interpolation(.high).scaledToFit()
                    .foregroundStyle(glow)
                    .blur(radius: 3).opacity(0.8)
                    .blendMode(.plusLighter)
                Image(uiImage: mask).renderingMode(.template).resizable().interpolation(.high).scaledToFit()
                    .foregroundStyle(glow)
            }
        }
        .animation(.easeInOut(duration: 3), value: night)
    }
}
#endif
