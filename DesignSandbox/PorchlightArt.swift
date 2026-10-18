import SwiftUI

/// Porchlight street composited from the generated art (houses, lamps, maples, ground strip).
/// Light comes from the left in every asset (shadows fall right), so the sun/moon sit left.
/// Sky is code; lit windows and lit lamps are overlays drawn above a night tint so they glow.
struct StreetSceneArt: View {
    var hours: Double
    var litWindows: [String: Int]
    var lampHalo: CGFloat = 1
    @Environment(\.colorScheme) private var scheme

    static let available = UIImage(named: "pl-house-cabin") != nil && UIImage(named: "pl-ground-autumn") != nil

    // Window rects measured from the renders (scripts/design-sandbox/porchlight_windows.py).
    static let cabinWindows: [CGRect] = [
        CGRect(x: 0.214, y: 0.577, width: 0.088, height: 0.105), CGRect(x: 0.347, y: 0.577, width: 0.088, height: 0.105),
        CGRect(x: 0.708, y: 0.577, width: 0.097, height: 0.105), CGRect(x: 0.467, y: 0.348, width: 0.092, height: 0.097),
    ]
    static let duplexWindows: [CGRect] = [
        CGRect(x: 0.389, y: 0.650, width: 0.083, height: 0.173), CGRect(x: 0.259, y: 0.317, width: 0.088, height: 0.163),
        CGRect(x: 0.614, y: 0.317, width: 0.081, height: 0.163),
    ]

    private var night: Bool { scheme == .dark }
    private var nightTint: Color { night ? Color(red: 0.40, green: 0.46, blue: 0.70) : .white }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let groundH = w * 313 / 1400
            let lawnY = h - groundH * 0.92          // where houses stand
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: night ? [Color(hex: 0x0C1738), Color(hex: 0x263468)] : [Color(hex: 0xF9A86E), Color(hex: 0xFBE3D0)],
                               startPoint: .top, endPoint: .bottom)
                if night {
                    Stars().frame(width: w, height: lawnY)
                    Circle().fill(Color(hex: 0xF4F1E0)).frame(width: 30, height: 30)
                        .overlay(Circle().fill(Color(hex: 0x0C1738)).frame(width: 26, height: 26).offset(x: 8, y: -4))
                        .position(x: w * 0.12, y: h * 0.16)
                } else {
                    Circle().fill(Color(hex: 0xFFF1D6)).frame(width: 70, height: 70)
                        .shadow(color: Color(hex: 0xFFD7A0), radius: 34)
                        .position(x: w * 0.14, y: h * 0.36)
                }
                Hills().fill(night ? Color(hex: 0x1D2A55) : Color(hex: 0xEDB394))
                    .frame(width: w, height: h * 0.26).position(x: w / 2, y: lawnY - h * 0.06)

                // Trees and houses, tinted for night
                Group {
                    art("pl-maple-autumn").frame(width: 92, height: 92).position(x: w * 0.10, y: lawnY - 40)
                    art("pl-house-cabin")
                        .hueRotation(.degrees(118))          // Pine Cabin painted pine green
                        .frame(width: w * 0.40, height: w * 0.40)
                        .position(x: w * 0.36, y: lawnY - w * 0.40 * 0.32)
                    art("pl-maple-autumn").frame(width: 70, height: 70).position(x: w * 0.60, y: lawnY - 30)
                    art("pl-house-duplex")
                        .frame(width: w * 0.36, height: w * 0.36)
                        .position(x: w * 0.80, y: lawnY - w * 0.36 * 0.45)
                }
                .colorMultiply(nightTint)

                // Lit-window overlays
                windows(StreetSceneArt.cabinWindows, lit: litWindows["pine"] ?? 0,
                        frame: CGRect(x: w * 0.36 - w * 0.20, y: lawnY - w * 0.40 * 0.32 - w * 0.20, width: w * 0.40, height: w * 0.40))
                windows(StreetSceneArt.duplexWindows, lit: litWindows["oak"] ?? 0,
                        frame: CGRect(x: w * 0.80 - w * 0.18, y: lawnY - w * 0.36 * 0.45 - w * 0.18, width: w * 0.36, height: w * 0.36))

                // Ground strip
                art("pl-ground-autumn").frame(width: w, height: groundH).position(x: w / 2, y: h - groundH / 2)
                    .colorMultiply(nightTint)

                // 15 lamps x 50h along the sidewalk; tall ones at 100h and 500h
                let litCount = Int(hours / 50)
                let partial = (hours - Double(litCount) * 50) / 50
                ForEach(0..<15, id: \.self) { i in
                    let tall = i == 1 || i == 9
                    let lh: CGFloat = tall ? 62 : 46
                    let state = i < litCount ? 1.0 : (i == litCount ? partial : 0)
                    ArtLamp(state: state, night: night, halo: lampHalo)
                        .frame(width: lh, height: lh)
                        .position(x: w * (0.033 + CGFloat(i) * 0.0667), y: h - groundH * 0.30 - lh / 2 + 2)
                }
            }
        }
        .clipped()
    }

    private func art(_ name: String) -> some View {
        Image(uiImage: UIImage(named: name) ?? UIImage()).resizable().scaledToFit()
    }

    private func windows(_ rects: [CGRect], lit: Int, frame f: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(rects.indices, id: \.self) { i in
                let r = rects[i]
                let on = i < lit
                RoundedRectangle(cornerRadius: 1)
                    .fill(on ? PL.windowLit : (night ? Color(hex: 0x141A33) : Color(hex: 0x3C4257)))
                    .overlay(on ? AnyView(Rectangle().fill(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .topLeading, endPoint: .center))) : AnyView(
                        Path { p in p.move(to: .init(x: 2, y: f.height * r.height - 2)); p.addLine(to: .init(x: f.width * r.width * 0.5, y: 2)) }
                            .stroke(.white.opacity(0.18), lineWidth: 1.5)))
                    .shadow(color: on ? PL.windowLit.opacity(night ? 1 : 0.7) : .clear, radius: on ? (night ? 10 : 5) : 0)
                    .frame(width: f.width * r.width, height: f.height * r.height)
                    .position(x: f.minX + f.width * (r.minX + r.width / 2), y: f.minY + f.height * (r.minY + r.height / 2))
                    .animation(.easeOut(duration: 0.32).delay(Double(i) * 0.12), value: lit)
            }
        }
    }
}

struct ArtLamp: View {
    var state: Double
    var night: Bool
    var halo: CGFloat
    var body: some View {
        ZStack {
            if state >= 1 {
                Image(uiImage: UIImage(named: "pl-lamp-lit") ?? UIImage()).resizable().scaledToFit()
                    .opacity(night ? 1 : 0.6)
                Circle().fill(RadialGradient(colors: [PL.lampLit.opacity(night ? 0.9 : 0.6), .clear], center: .center, startRadius: 1, endRadius: 14))
                    .frame(width: 28, height: 28).scaleEffect(halo)
                    .offset(y: -22)
            } else {
                Image(uiImage: UIImage(named: "pl-lamp-unlit") ?? UIImage()).resizable().scaledToFit()
                    .colorMultiply(night ? Color(red: 0.55, green: 0.6, blue: 0.8) : .white)
                if state > 0 {
                    Circle().fill(PL.lampLit.opacity(0.18 + 0.3 * state)).frame(width: 6, height: 6).offset(y: -22)
                }
            }
        }
    }
}
