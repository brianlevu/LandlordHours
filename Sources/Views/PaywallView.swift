import SwiftUI
import LucideIcons

struct PaywallView: View {
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @ObservedObject var subscriptionManager = SubscriptionManager.shared
    @Binding var showPaywall: Bool
    var onDismiss: (() -> Void)?

    // Hero animation
    @State private var heroScale: CGFloat = 0.5
    @State private var heroOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    // Features stagger
    @State private var featureOffsets: [CGFloat] = Array(repeating: 32, count: 5)
    @State private var featureOpacities: [Double] = Array(repeating: 0, count: 5)
    // Bottom section
    @State private var bottomOffset: CGFloat = 40
    @State private var bottomOpacity: Double = 0

    private let proFeatures: [(icon: String, title: String, desc: String, color: Color, wash: Color)] = [
        ("sparkles",       "AI Smart Entry",       "Describe your work, AI does the rest",   AppColors.primary,  AppColors.primarySurface),
        ("camera",         "Photo Evidence",        "Attach photos to every time entry",       AppColors.coral,    AppColors.coralWash),
        ("cloud",          "iCloud Backup",         "Your records, safe and synced forever",   AppColors.sky,      AppColors.skyWash),
        ("file-text",      "Audit-Ready Reports",   "Clean PDF exports for tax filing",        AppColors.sage,     AppColors.sageWash),
        ("building-2",     "Unlimited Properties",  "Track every rental you own",              AppColors.honey,    AppColors.honeyWash),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                        .padding(.top, 56)
                        .padding(.bottom, 32)

                    featuresSection
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)

                    freeNotice
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)

                    pricingAndCTA
                        .padding(.horizontal, 24)
                        .padding(.bottom, 48)
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
                        .frame(width: 32, height: 32)
                    LucideIcon(image: Lucide.x, size: 12)
                        .foregroundStyle(colors.textSecondary)
                }
            }
            .padding(.top, 16)
            .padding(.trailing, 20)
        }
        .onAppear { animateIn() }
    }

    // MARK: - Hero
    private var heroSection: some View {
        VStack(spacing: 20) {
            ZStack {
                // Outer pulse ring
                Circle()
                    .fill(AppColors.primary.opacity(0.07))
                    .frame(width: 148, height: 148)
                    .scaleEffect(pulseScale)

                // Inner lavender circle
                Circle()
                    .fill(colors.primarySurface)
                    .frame(width: 112, height: 112)

                LucideIcon(image: Lucide.crown, size: 48)
                    .foregroundStyle(AppColors.primary)
            }
            .scaleEffect(heroScale)
            .opacity(heroOpacity)

            VStack(spacing: 8) {
                Text("Go Pro")
                    .font(AppTypography.headline)
                    .foregroundStyle(colors.textPrimary)

                Text("Track every hour.\nKeep every deduction.")
                    .font(AppTypography.body)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(heroOpacity)
        }
    }

    // MARK: - Features
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionPill(icon: Lucide.sparkles, label: "WHAT'S INCLUDED")
                .padding(.bottom, 4)

            ForEach(Array(proFeatures.enumerated()), id: \.offset) { index, feature in
                featureRow(feature, index: index)
            }
        }
    }

    private func featureRow(_ feature: (icon: String, title: String, desc: String, color: Color, wash: Color), index: Int) -> some View {
        HStack(spacing: 14) {
            JellyBadge(systemName: feature.icon, color: feature.color, wash: feature.wash, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(AppTypography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(colors.textPrimary)
                Text(feature.desc)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            LucideIcon(image: Lucide.check, size: 16)
                .foregroundStyle(AppColors.sage)
        }
        .padding(14)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 8, x: 0, y: 2)
        .offset(y: featureOffsets[index])
        .opacity(featureOpacities[index])
    }

    // MARK: - Free Notice
    private var freeNotice: some View {
        HStack(spacing: 10) {
            LucideIcon(image: Lucide.info, size: 14)
                .foregroundStyle(colors.textTertiary)
            Text("Free plan: 1 property \u{00B7} 20 entries/month \u{00B7} basic reports")
                .font(AppTypography.bodySmall)
                .foregroundStyle(colors.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        .offset(y: bottomOffset)
        .opacity(bottomOpacity)
    }

    // MARK: - Pricing + CTA
    private var pricingAndCTA: some View {
        VStack(spacing: 16) {
            // Price display
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("$30")
                        .font(AppTypography.heroNumber)
                        .foregroundStyle(colors.textPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("one-time")
                            .font(AppTypography.caption)
                            .foregroundStyle(colors.textSecondary)
                        Text("yours forever \u{2713}")
                            .font(AppTypography.label)
                            .foregroundStyle(AppColors.sage)
                    }
                }
                Text("Less than one hour of billable time")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(colors.textSecondary)
            }
            .padding(.bottom, 4)

            // Trial note
            if subscriptionManager.isTrialActive {
                HStack(spacing: 6) {
                    LucideIcon(image: Lucide.clock, size: 12)
                        .foregroundStyle(AppColors.honey)
                    Text("\(subscriptionManager.trialDaysRemaining) day\(subscriptionManager.trialDaysRemaining == 1 ? "" : "s") left in free trial")
                        .font(AppTypography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(colors.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppColors.honeyWash)
                .clipShape(Capsule())
            }

            // CTA Button
            if subscriptionManager.isLoading {
                ProgressView("Processing...")
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            } else if subscriptionManager.hasPurchased {
                Button {
                    showPaywall = false
                    onDismiss?()
                } label: {
                    HStack(spacing: 8) {
                        LucideIcon(image: Lucide.check, size: 20)
                            .foregroundStyle(.white)
                        Text("You're Pro! Tap to continue")
                    }
                    .font(AppTypography.buttonLarge)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(AppColors.sage)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
                }
            } else {
                Button {
                    Task { await subscriptionManager.purchasePro() }
                } label: {
                    Group {
                        if let product = subscriptionManager.proProduct {
                            Text("Unlock Pro \u{00B7} \(product.displayPrice)")
                        } else {
                            Text("Unlock Pro \u{00B7} $30")
                        }
                    }
                    .font(AppTypography.buttonLarge)
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(colorScheme == .dark ? Color.white : AppColors.charcoal)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
                }
                .disabled(subscriptionManager.products.isEmpty)
            }

            // Error message
            if let error = subscriptionManager.purchaseError {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.error)
                    .multilineTextAlignment(.center)
            }

            // Dismiss link
            Button {
                showPaywall = false
                onDismiss?()
            } label: {
                Text(subscriptionManager.hasPurchased ? "Close" : "Maybe Later")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(colors.textTertiary)
            }
        }
        .offset(y: bottomOffset)
        .opacity(bottomOpacity)
    }

    // MARK: - Helpers
    private func sectionPill(icon: UIImage, label: String) -> some View {
        HStack(spacing: 5) {
            LucideIcon(image: icon, size: 11)
                .foregroundStyle(colors.textSecondary)
            Text(label)
                .font(AppTypography.label)
                .tracking(1.5)
        }
        .foregroundStyle(colors.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(colors.backgroundTertiary)
        .clipShape(Capsule())
    }

    // MARK: - Animations
    private func animateIn() {
        // Hero bounces in
        withAnimation(.spring(response: 0.7, dampingFraction: 0.72).delay(0.05)) {
            heroScale = 1.0
            heroOpacity = 1.0
        }
        // Continuous pulse on outer ring
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(0.8)) {
            pulseScale = 1.1
        }
        // Features stagger in
        for i in 0..<proFeatures.count {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.35 + Double(i) * 0.08)) {
                featureOffsets[i] = 0
                featureOpacities[i] = 1.0
            }
        }
        // Bottom section slides up
        withAnimation(.easeOut(duration: 0.45).delay(0.75)) {
            bottomOffset = 0
            bottomOpacity = 1.0
        }
    }
}

#Preview {
    PaywallView(showPaywall: .constant(true))
}
