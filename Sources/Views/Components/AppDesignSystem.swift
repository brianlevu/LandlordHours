import SwiftUI
import LucideIcons

// MARK: - Form Dark Background Modifier
extension View {
    func formDarkBackground() -> some View {
        if #available(iOS 16.0, *) {
            return self.scrollContentBackground(.hidden)
                .background(AppColors.background)
        } else {
            return self.background(AppColors.background)
        }
    }
}

// MARK: - Premium Mobile Surfaces

/// Soft app canvas inspired by high-polish mobile wellness apps, tuned for tax-product trust.
struct LHMobileCanvas: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AuroraBackground()

            // Light: a soft white lift. Dark: a blueprint-card tint capped at #141C3F, so the top of
            // the canvas never turns grey and secondary text on it stays above 4.5:1.
            LinearGradient(
                colors: colorScheme == .dark
                    ? [AppColors.darkBackgroundSecondary.opacity(0.7), Color.clear, Color.clear]
                    : [Color.white.opacity(0.34), Color.clear, AppColors.skyWash.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

/// Production card treatment used for primary task surfaces.
struct LHSurfaceCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var cornerRadius: CGFloat = AppCornerRadius.xxl
    var padding: CGFloat? = nil

    func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.92 : 0.86))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.05 : 0.55),
                                        Color.white.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.72),
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    func lhSurfaceCard(cornerRadius: CGFloat = AppCornerRadius.xxl, padding: CGFloat? = nil) -> some View {
        modifier(LHSurfaceCard(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Motion Primitives

struct LHMotion<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    func lhMotion<Value: Equatable>(_ animation: Animation = AppAnimation.smooth, value: Value) -> some View {
        modifier(LHMotion(animation: animation, value: value))
    }
}

struct LHPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var pressedScale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : AppAnimation.feedback, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == LHPressableButtonStyle {
    static var lhPressable: LHPressableButtonStyle { LHPressableButtonStyle() }
}

/// Rounded icon tile with a crisp glyph, subtle gloss, and tactile scale feedback.
struct LHIconTile: View {
    let icon: UIImage
    let color: Color
    var wash: Color? = nil
    var size: CGFloat = 36
    var isActive: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            (wash ?? color.opacity(0.14)).opacity(isActive ? 1 : 0.92),
                            Color.white.opacity(isActive ? 0.34 : 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.62), lineWidth: 1)
                )

            Image(uiImage: icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.42, height: size * 0.42)
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(isActive ? 0.18 : 0.08), radius: isActive ? 10 : 5, y: isActive ? 5 : 2)
        .scaleEffect(isActive ? 1.04 : 1.0)
        .lhMotion(AppAnimation.quick, value: isActive)
    }
}

struct LHSuccessToast: View {
    let title: String
    let detail: String?
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 12) {
            LHIconTile(icon: UIImage(lucideId: "circle-check") ?? UIImage(), color: AppColors.sage, wash: AppColors.sageWash, size: 38, isActive: true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.button)
                    .foregroundStyle(colors.textPrimary)
                if let detail {
                    Text(detail)
                        .font(AppTypography.caption)
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: AppColors.sage.opacity(0.12), radius: 8, y: 3)
    }
}

// MARK: - Error Banner

// The 1.x LHErrorBanner card is retired: save/load errors use the one toast (LHToast.swift).

// Loading: no skeletons or spinners. Use `DraftingLoader` / `PlaceholderBar`
// (Components/DraftingLoader.swift) for the one thing that waits on data.
