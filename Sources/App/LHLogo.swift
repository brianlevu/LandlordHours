import SwiftUI

// MARK: - LandlordHours 2.0 logo — mark B "half drawn, half built"
//
// Source: design/brand/logo/mark-b.svg (1024 grid, translate(10 -11.5) for optical centring) and
// design/brand/icon/icon-b-1024.png (the approved app icon). A house elevation on blueprint blue:
// foundation, left wall, left roof slope and door are built (plaster / terracotta / timber); the
// right slope, upper right wall and window are still drafting-cyan linework.
// Brand rules: docs/design/2.0-brand-system.md §5.

// LHMarkGeometry, LHMarkShape and LHMark live in Sources/Shared/LHMark.swift (shared with the
// widget extension).

// MARK: - App-icon tile (self-contained, any size)
/// The mark on its blueprint tile — the in-app twin of the app icon. The name is kept from 1.x so
/// existing call sites (splash, sign-in, onboarding) pick up the new mark.
struct WaveHouseIcon: View {
    var size: CGFloat = 80

    var body: some View {
        ZStack {
            AppColors.brand
            LHMark(size: size)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Logo (mark + wordmark)
struct LHLogo: View {
    var size: CGFloat = 80
    var showText: Bool = true
    var animated: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: size * 0.2) {
            WaveHouseIcon(size: size)
                .shadow(color: AppColors.brand.opacity(0.22), radius: size * 0.12, y: size * 0.05)
                .scaleEffect(appeared ? 1 : 0.3)
                .opacity(appeared ? 1 : 0)
            if showText {
                LHWordmark(fontSize: max(size * 0.28, 17))
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
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
}

// MARK: - Compact Logo (for headers, nav bars)
struct LHCompactLogo: View {
    var size: CGFloat = 32

    var body: some View {
        WaveHouseIcon(size: size)
            .shadow(color: AppColors.brand.opacity(0.18), radius: size * 0.1, y: size * 0.04)
    }
}

// MARK: - Wordmark (text-only logo)
/// "Landlord" in ink + "Hours" in the action colour (blueprint in light, cyan in dark), per
/// logo/wordmark.svg. Fraunces 600 at 28pt and up; below that SF Pro semibold (the brand rule
/// keeps Fraunces off small text).
struct LHWordmark: View {
    var fontSize: CGFloat = 28

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var font: Font {
        if fontSize >= LHFont.frauncesMinimumSize && LHFont.isFrauncesAvailable {
            return Font.custom(LHFont.frauncesFamily, size: fontSize).weight(.semibold)
        }
        return Font.system(size: fontSize, weight: .semibold, design: .default)
    }

    var body: some View {
        (Text("Landlord").foregroundColor(colors.textPrimary)
         + Text("Hours").foregroundColor(colors.action))
            .font(font)
            .accessibilityLabel("LandlordHours")
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
            LHMarkShape().fill(AppColors.brand).frame(width: 48, height: 48)
        }

        LHWordmark(fontSize: 34)
    }
    .padding()
    .background(AppColors.background)
}
