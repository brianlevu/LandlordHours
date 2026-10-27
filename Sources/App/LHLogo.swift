import SwiftUI

// MARK: - Dormer logo (2.2): the V3 mark and "Dormer" in Fraunces
//
// The mark, its geometry and the icon tile live in Sources/Shared/DormerMark.swift (shared with the
// widget extension); the generator is design/brand/dormer/make_dormer_icon.py. The 2.0 house mark B
// (LHMarkShape / LHMark in Sources/Shared/LHMark.swift) is still drawn by the widget surfaces until
// the rename pass (docs/brand/rename-inventory.md).

// MARK: - App-icon tile (self-contained, any size)
/// The Dormer tile: the in-app twin of the app icon. The name is kept from 1.x so existing call
/// sites (splash, sign-in, onboarding, the engagement lab) pick up the new mark.
struct WaveHouseIcon: View {
    var size: CGFloat = 80

    var body: some View {
        DormerTile(size: size)
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
/// "Dormer" in ink (textPrimary per appearance). Fraunces 600 at 28pt and up; below that SF Pro
/// semibold (the brand rule keeps Fraunces off small text). The name is the brand, so it is not
/// localized.
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
        Text(verbatim: DormerBrand.name)
            .font(font)
            .foregroundColor(colors.textPrimary)
            .accessibilityLabel(Text(verbatim: DormerBrand.name))
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
            DormerMarkShape(cropped: true).fill(AppColors.brand).frame(width: 48, height: 48)
        }

        LHWordmark(fontSize: 34)
    }
    .padding()
    .background(AppColors.background)
}
