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

// MARK: - Shimmer Effect

/// Animated shimmer gradient overlay for skeleton loading states.
/// Usage: `.modifier(ShimmerEffect())` or `.shimmer()`
struct ShimmerEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.3),
                        Color.white.opacity(0)
                    ],
                    startPoint: .init(x: phase - 0.3, y: 0.5),
                    endPoint: .init(x: phase + 0.3, y: 0.5)
                )
                .blendMode(BlendMode.sourceAtop)
            )
            .onAppear {
                guard !reduceMotion else {
                    phase = 0.5
                    return
                }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 2
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}

// MARK: - Premium Mobile Surfaces

/// Soft app canvas inspired by high-polish mobile wellness apps, tuned for tax-product trust.
struct LHMobileCanvas: View {
    var body: some View {
        ZStack {
            AuroraBackground()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.34),
                    Color.clear,
                    AppColors.skyWash.opacity(0.18)
                ],
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

// MARK: - Guided First-Run Overlay

struct GuidedOnboardingOverlay: View {
    let step: GuidedOnboardingStep
    var spotlightOverride: CGRect?
    var isReplay: Bool = false
    let onPrimary: () -> Void
    let onSecondary: () -> Void
    let onSkip: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        GeometryReader { proxy in
            let rect = spotlightRect(in: proxy.size, override: spotlightOverride)

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { }
                    .accessibilityHidden(true)

                dimLayer(spotlight: rect)
                    .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: rect.cornerRadius, style: .continuous)
                    .strokeBorder(AppColors.primaryLight, lineWidth: 3)
                    .frame(width: rect.rect.width, height: rect.rect.height)
                    .position(x: rect.rect.midX, y: rect.rect.midY)
                    .shadow(color: AppColors.primary.opacity(0.32), radius: 18, y: 6)
                    .allowsHitTesting(false)

                coachCard(in: proxy.size, spotlight: rect.rect)
            }
            .animation(reduceMotion ? nil : AppAnimation.smooth, value: step)
        }
        .contentShape(Rectangle())
    }

    private func dimLayer(spotlight: GuidedSpotlight) -> some View {
        Color.black.opacity(colorScheme == .dark ? 0.62 : 0.48)
            .mask {
                Rectangle()
                    .overlay {
                        RoundedRectangle(cornerRadius: spotlight.cornerRadius, style: .continuous)
                            .frame(width: spotlight.rect.width, height: spotlight.rect.height)
                            .position(x: spotlight.rect.midX, y: spotlight.rect.midY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
    }

    private func coachCard(in size: CGSize, spotlight: CGRect) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                LHIconTile(icon: content.icon, color: AppColors.primary, wash: colors.primarySurface, size: 42, isActive: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text(content.body)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Button("Skip") {
                    onSkip()
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(colors.textSecondary)
                .accessibilityIdentifier("guidedSetup.skip")
            }

            HStack(spacing: 10) {
                Button {
                    onPrimary()
                } label: {
                    Text(content.primary)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.onAction)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("guidedSetup.primary")

                if let secondary = content.secondary {
                    Button {
                        onSecondary()
                    } label: {
                        Text(secondary)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColors.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(colors.primarySurface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("guidedSetup.secondary")
                }
            }
        }
        .padding(16)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous)
                .strokeBorder(colors.border.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.10), radius: 10, y: 4)
        .padding(.horizontal, 20)
        .frame(width: size.width)
        .position(cardPosition(in: size, spotlight: spotlight))
        .accessibilityElement(children: .combine)
    }

    private var content: GuidedOnboardingContent {
        switch step {
        case .propertyTab:
            return GuidedOnboardingContent(
                icon: Lucide.building2,
                title: "Open Properties",
                body: "Properties is where every hour starts. Go there first, then add your rental.",
                primary: "Open Properties",
                secondary: "Skip setup"
            )
        case .addProperty:
            return GuidedOnboardingContent(
                icon: Lucide.circlePlus,
                title: addPropertyTitle,
                body: "Use a simple name and address. You can edit the details later.",
                primary: "Add Property",
                secondary: nil
            )
        case .trackTab:
            return GuidedOnboardingContent(
                icon: Lucide.clock,
                title: "Log one real activity",
                body: "One saved entry proves the core flow: property, category, hours, and notes in one record.",
                primary: "Open Track",
                secondary: "Skip for now"
            )
        case .firstActivity:
            return GuidedOnboardingContent(
                icon: Lucide.filePenLine,
                title: "Write what you did",
                body: "A short sentence is enough. The app keeps the evidence tied to your property and tax year.",
                primary: "Use sample note",
                secondary: "I’ll type my own"
            )
        }
    }

    private var addPropertyTitle: String {
        isReplay ? "Add or review a property" : "Add your first property"
    }

    private func spotlightRect(in size: CGSize, override: CGRect?) -> GuidedSpotlight {
        if let override, override.width > 8, override.height > 8 {
            return GuidedSpotlight(rect: override, cornerRadius: min(32, override.height / 2))
        }

        switch step {
        case .propertyTab:
            return tabSegmentSpotlight(index: 1, in: size)
        case .addProperty:
            return GuidedSpotlight(
                rect: CGRect(x: 24, y: min(max(size.height * 0.42, 280), size.height - 320), width: size.width - 48, height: 72),
                cornerRadius: 28
            )
        case .trackTab:
            return tabSegmentSpotlight(index: 2, in: size)
        case .firstActivity:
            return GuidedSpotlight(
                rect: CGRect(x: 24, y: 128, width: size.width - 48, height: 112),
                cornerRadius: 22
            )
        }
    }

    private func tabSegmentSpotlight(index: Int, in size: CGSize) -> GuidedSpotlight {
        let tabCount: CGFloat = 5
        let tabBarInset: CGFloat = 20
        let segmentWidth = (size.width - tabBarInset * 2) / tabCount
        let horizontalInset: CGFloat = 3
        let height: CGFloat = 78
        let bottomInset: CGFloat = 2
        let y = max(size.height - height - bottomInset, 0)
        return GuidedSpotlight(
            rect: CGRect(
                x: tabBarInset + segmentWidth * CGFloat(index) + horizontalInset,
                y: y,
                width: segmentWidth - horizontalInset * 2,
                height: height
            ),
            cornerRadius: 28
        )
    }

    private func cardPosition(in size: CGSize, spotlight: CGRect) -> CGPoint {
        let cardHeight: CGFloat = content.secondary == nil ? 158 : 176
        let topCandidate = spotlight.minY - cardHeight / 2 - 28
        let bottomCandidate = spotlight.maxY + cardHeight / 2 + 28
        let y: CGFloat

        if topCandidate > 96 {
            y = topCandidate
        } else if bottomCandidate < size.height - 112 {
            y = bottomCandidate
        } else {
            y = min(max(size.height * 0.34, 130), size.height - 220)
        }

        return CGPoint(x: size.width / 2, y: y)
    }
}

private struct GuidedSpotlight {
    let rect: CGRect
    let cornerRadius: CGFloat
}

private struct GuidedOnboardingContent {
    let icon: UIImage
    let title: String
    let body: String
    let primary: String
    let secondary: String?
}

struct GuidedSpotlightTargetKey: PreferenceKey {
    static var defaultValue: [GuidedOnboardingStep: Anchor<CGRect>] = [:]

    static func reduce(value: inout [GuidedOnboardingStep: Anchor<CGRect>], nextValue: () -> [GuidedOnboardingStep: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func guidedSpotlightTarget(_ step: GuidedOnboardingStep) -> some View {
        anchorPreference(key: GuidedSpotlightTargetKey.self, value: .bounds) { [step: $0] }
    }
}

// MARK: - Skeleton Shapes

/// A rounded placeholder rectangle that shimmers. Adapts to light/dark.
struct SkeletonRect: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var radius: CGFloat = 6
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : AppColors.snow)
            .frame(width: width, height: height)
            .shimmer()
    }
}

/// A circular placeholder that shimmers.
struct SkeletonCircle: View {
    var size: CGFloat = 44
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Circle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : AppColors.snow)
            .frame(width: size, height: size)
            .shimmer()
    }
}

// MARK: - Skeleton Dashboard

/// Full skeleton placeholder for the Dashboard screen while data loads.
struct DashboardSkeleton: View {
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 24) {
            // Header skeleton
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonRect(width: 100, height: 12)
                    SkeletonRect(width: 140, height: 28, radius: 8)
                }
                Spacer()
                SkeletonRect(width: 40, height: 40, radius: 14)
            }

            // Ring card skeleton
            VStack(spacing: 16) {
                SkeletonCircle(size: 180)
                SkeletonRect(width: 200, height: 16, radius: 8)
                SkeletonRect(width: 260, height: 12)
                HStack(spacing: 12) {
                    SkeletonRect(height: 38, radius: 14)
                    SkeletonRect(height: 38, radius: 14)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .padding(.horizontal, 24)
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 28))

            // Week card skeleton
            VStack(spacing: 14) {
                HStack {
                    SkeletonRect(width: 90, height: 14, radius: 8)
                    Spacer()
                    SkeletonRect(width: 50, height: 18, radius: 8)
                }
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { _ in
                        VStack(spacing: 6) {
                            SkeletonRect(width: 32, height: 32, radius: 10)
                            SkeletonRect(width: 24, height: 10, radius: 4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(22)
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 24))

            // Recent activity skeleton
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SkeletonRect(width: 130, height: 16, radius: 8)
                    Spacer()
                    SkeletonRect(width: 55, height: 14, radius: 8)
                }
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { i in
                        HStack(spacing: 14) {
                            SkeletonRect(width: 44, height: 44, radius: 12)
                            VStack(alignment: .leading, spacing: 4) {
                                SkeletonRect(width: 120, height: 13, radius: 6)
                                SkeletonRect(width: 80, height: 10, radius: 4)
                            }
                            Spacer()
                            SkeletonRect(width: 40, height: 14, radius: 6)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        if i < 2 {
                            Divider().padding(.leading, 74)
                        }
                    }
                }
                .background(colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 40)
    }
}

// MARK: - Branded Loading Indicator

/// A compact branded loading view — animated ring + optional message.
/// Use in place of ProgressView() for a cohesive look.
struct LHLoadingView: View {
    var message: String? = nil
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Track
                Circle()
                    .stroke(AppColors.primarySurface, style: StrokeStyle(lineWidth: 4, dash: [3, 5]))
                    .frame(width: 44, height: 44)

                // Animated arc
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryLight],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
            }

            if let message {
                Text(message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Full-Screen Loading

/// Full-screen branded loading state. Use when an entire view is waiting for data.
struct LHFullScreenLoading: View {
    var message: String = "Loading..."
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        VStack {
            Spacer()
            LHLoadingView(message: message)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.background)
    }
}
