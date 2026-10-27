import SwiftUI

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

// MARK: - Error Banner

// The 1.x LHErrorBanner card is retired: save/load errors use the one toast (LHToast.swift).

// Loading: no skeletons or spinners. Use `DraftingLoader` / `PlaceholderBar`
// (Components/DraftingLoader.swift) for the one thing that waits on data.

// MARK: - Wrapping text

extension View {
    /// Lets a text wrap to the lines it needs instead of being cut to the height a sibling proposes
    /// (an ellipsis in a row or a clipped second line). Vertical only: the width stays flexible.
    func lhWrapsText() -> some View {
        fixedSize(horizontal: false, vertical: true)
    }
}
