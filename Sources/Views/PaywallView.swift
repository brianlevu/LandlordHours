import SwiftUI
import LucideIcons

struct PaywallView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @ObservedObject var subscriptionManager = SubscriptionManager.shared
    @Binding var showPaywall: Bool
    var onDismiss: (() -> Void)?

    // Hero animation
    @State private var heroScale: CGFloat = 0.5
    @State private var heroOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    // Features stagger
    @State private var featureOffsets: [CGFloat] = Array(repeating: 32, count: 3)
    @State private var featureOpacities: [Double] = Array(repeating: 0, count: 3)
    // Bottom section
    @State private var bottomOffset: CGFloat = 40
    @State private var bottomOpacity: Double = 0

    private let proFeatures: [(icon: UIImage, title: String, desc: String, color: Color, wash: Color)] = [
        (Lucide.fileText,   "Accountant-ready exports", "Clean PDF reports by tax year, property, and category.", AppColors.action, AppColors.primarySurface),
        (Lucide.building2,  "Portfolio tracking",       "Add every rental you manage without hitting a property cap.", AppColors.informational, AppColors.informationalSurface),
        (Lucide.badgeCheck, "Lifetime recovery",        "Restore Pro from the App Store whenever you move devices.", AppColors.positive, AppColors.positiveSurface),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LHMobileCanvas()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    heroSection
                        .padding(.top, 70)

                    featuresSection
                        .padding(.horizontal, 24)

                    pricingAndCTA
                        .padding(.horizontal, 24)
                        .padding(.bottom, 34)
                }
            }

            // Close button
            Button {
                showPaywall = false
                onDismiss?()
            } label: {
                ZStack {
                    Circle()
                        .fill(colors.backgroundTertiary)
                        .frame(width: 44, height: 44)
                    LucideIcon(image: Lucide.x, size: 18)
                        .foregroundStyle(AppColors.charcoal)
                }
            }
            .accessibilityLabel("Close")
            .padding(.top, 16)
            .padding(.trailing, 20)
        }
        .onAppear { animateIn() }
    }

    // MARK: - Hero
    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(subscriptionManager.hasPurchased ? AppColors.positiveSurface : AppColors.actionSurface)
                        .frame(width: 58, height: 58)
                        .scaleEffect(pulseScale)

                    LucideIcon(image: subscriptionManager.hasPurchased ? Lucide.badgeCheck : Lucide.sparkles, size: 26)
                        .foregroundStyle(subscriptionManager.hasPurchased ? AppColors.successGreen : AppColors.action)
                }
                .scaleEffect(heroScale)
                .opacity(heroOpacity)

                VStack(alignment: .leading, spacing: 4) {
                    Text(subscriptionManager.hasPurchased ? "Pro is active" : "LandlordHours Pro")
                        .font(.system(size: 31, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(subscriptionManager.hasPurchased ? "Lifetime access is unlocked on this account." : "Export clean records and track every rental with one lifetime purchase.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(heroOpacity)

            HStack(spacing: 8) {
                trustChip("One-time purchase", icon: Lucide.receiptText)
                trustChip("No renewal", icon: Lucide.refreshCwOff)
            }
            .opacity(heroOpacity)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Features
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Built for tax review")
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)

            VStack(spacing: 0) {
                ForEach(Array(proFeatures.enumerated()), id: \.offset) { index, feature in
                    featureRow(feature, index: index)

                    if index < proFeatures.count - 1 {
                        Divider()
                            .background(colors.border.opacity(0.35))
                            .padding(.leading, 62)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(colors.border.opacity(0.28), lineWidth: 1)
            }
        }
    }

    private func featureRow(_ feature: (icon: UIImage, title: String, desc: String, color: Color, wash: Color), index: Int) -> some View {
        HStack(spacing: 14) {
            LHIconTile(icon: feature.icon, color: feature.color, wash: feature.wash, size: 44, isActive: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Text(feature.desc)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            LucideIcon(image: Lucide.check, size: 16)
                .foregroundStyle(AppColors.successGreen)
        }
        .padding(.vertical, 12)
        .offset(y: featureOffsets[index])
        .opacity(featureOpacities[index])
    }

    // MARK: - Pricing + CTA
    private var pricingAndCTA: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                if let product = subscriptionManager.proProduct {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.displayPrice)
                                .font(.system(size: 48, weight: .black, design: .rounded))
                                .foregroundStyle(colors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Text("Lifetime access. Paid once through the App Store.")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(colors.textSecondary)
                        }

                        Spacer()

                        VStack(spacing: 5) {
                            Text("PRO")
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundStyle(AppColors.action)
                            Text("no renewal")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(colors.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(colors.actionSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        LucideIcon(image: Lucide.store, size: 22)
                            .foregroundStyle(AppColors.primary)
                        Text("Pro availability check")
                            .font(AppTypography.title3)
                            .foregroundStyle(colors.textPrimary)
                        Text("We will check the App Store before showing a price or starting purchase.")
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(colors.textSecondary)
                            .lineSpacing(3)
                    }
                }

                primaryAction

                Text(subscriptionManager.proProduct == nil ? "You can keep using free tracking while Pro is unavailable." : "Free plan still includes basic time tracking and the learning center.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(18)
            .background(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [colors.backgroundSecondary, AppColors.darkPlum.opacity(0.72)]
                        : [Color.white, AppColors.lavenderPale, AppColors.reportsAccentWash.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(AppColors.action.opacity(0.18), lineWidth: 1)
            }

            if !subscriptionManager.hasPurchased {
                Button {
                    Task {
                        await subscriptionManager.restorePurchases()
                        if subscriptionManager.isPro {
                            showPaywall = false
                            onDismiss?()
                        }
                    }
                } label: {
                    Text("Restore purchase")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.action)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.lhPressable)
            }

            if let error = subscriptionManager.purchaseError {
                errorMessage(error)
            }

            Button {
                showPaywall = false
                onDismiss?()
            } label: {
                Text(subscriptionManager.hasPurchased ? "Close" : "Continue free")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(colors.textSecondary)
            }
        }
        .offset(y: bottomOffset)
        .opacity(bottomOpacity)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if subscriptionManager.isLoading {
            ProgressView("Checking App Store...")
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        } else if subscriptionManager.hasPurchased {
            Button {
                showPaywall = false
                onDismiss?()
            } label: {
                HStack(spacing: 8) {
                    LucideIcon(image: Lucide.check, size: 20)
                        .foregroundStyle(AppColors.onAction)
                    Text("Continue with Pro")
                }
                .font(AppTypography.buttonLarge)
                .foregroundStyle(AppColors.onAction)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(colors.action)
                .clipShape(Capsule())
            }
            .buttonStyle(.lhPressable)
        } else {
            Button {
                Task { await subscriptionManager.purchasePro() }
            } label: {
                Group {
                    if let product = subscriptionManager.proProduct {
                        Text("Buy lifetime Pro - \(product.displayPrice)")
                    } else {
                        Text(subscriptionManager.purchaseError == nil ? "Check Pro availability" : "Try Pro purchase again")
                    }
                }
                .font(AppTypography.buttonLarge)
                .foregroundStyle(AppColors.onAction)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(colors.action)
                .clipShape(Capsule())
            }
            .buttonStyle(.lhPressable)
        }
    }

    private func errorMessage(_ error: String) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                LucideIcon(image: Lucide.circleAlert, size: 14)
                    .foregroundStyle(AppColors.error)
                    .padding(.top, 1)
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(colors.textPrimary)
                    .multilineTextAlignment(.leading)
            }

            #if DEBUG
            if AdminAccess.isCurrentUserAdmin {
                Button {
                    subscriptionManager.unlockPro()
                    showPaywall = false
                    onDismiss?()
                } label: {
                    Text("Use local Pro for testing")
                        .font(AppTypography.buttonSmall)
                        .foregroundStyle(AppColors.primary)
                }
            }
            #endif
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(AppColors.error.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                .stroke(AppColors.error.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
    }

    // MARK: - Helpers
    private func trustChip(_ text: String, icon: UIImage) -> some View {
        HStack(spacing: 6) {
            LucideIcon(image: icon, size: 13)
                .foregroundStyle(AppColors.action)
            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.62 : 0.78))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(colors.border.opacity(0.22), lineWidth: 1)
        }
    }

    private func sectionPill(icon: UIImage, label: String) -> some View {
        HStack(spacing: 5) {
            LucideIcon(image: icon, size: 11)
                .foregroundStyle(colors.textSecondary)
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(colors.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(colors.backgroundTertiary)
        .clipShape(Capsule())
    }
    // MARK: - Animations
    private func animateIn() {
        guard !reduceMotion else {
            heroScale = 1.0
            heroOpacity = 1.0
            featureOffsets = Array(repeating: 0, count: proFeatures.count)
            featureOpacities = Array(repeating: 1, count: proFeatures.count)
            bottomOffset = 0
            bottomOpacity = 1.0
            return
        }

        animate(.easeOut(duration: 0.22).delay(0.05)) {
            heroScale = 1.0
            heroOpacity = 1.0
        }

        for i in 0..<proFeatures.count {
            animate(.easeOut(duration: 0.22).delay(0.18 + Double(i) * 0.04)) {
                featureOffsets[i] = 0
                featureOpacities[i] = 1.0
            }
        }

        animate(.easeOut(duration: 0.24).delay(0.36)) {
            bottomOffset = 0
            bottomOpacity = 1.0
        }
    }

    private func animate(_ animation: Animation = AppAnimation.smooth, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }
}

#Preview {
    PaywallView(showPaywall: .constant(true))
}
