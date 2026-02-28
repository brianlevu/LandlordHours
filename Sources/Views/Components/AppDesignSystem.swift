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

// MARK: - Shimmer Effect

/// Animated shimmer gradient overlay for skeleton loading states.
/// Usage: `.modifier(ShimmerEffect())` or `.shimmer()`
struct ShimmerEffect: ViewModifier {
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
                .blendMode(.sourceAtop)
            )
            .onAppear {
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
