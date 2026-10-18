import SwiftUI
import LucideIcons

/// The one Pro paywall. It opens at the moment of need, speaks to the thing tapped
/// (`context`), and after a purchase or restore it hands control back through `onUnlocked`
/// so the caller can carry on (open the export, open Add Property).
struct PaywallView: View {
    let context: PaywallContext
    var year: Int = Calendar.current.component(.year, from: Date())
    /// Called once Pro is unlocked from this sheet, after it closes.
    var onUnlocked: (() -> Void)?
    /// Overrides the close behaviour when the paywall is not presented as a sheet.
    var onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    @State private var appeared = false
    @State private var didUnlockHere = false
    @State private var didFinish = false
    @State private var isRestoring = false
    @State private var priceLoadFinished = false

    private var showsUnlockedState: Bool { didUnlockHere || subscriptionManager.isPro }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LHMobileCanvas()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if !showsUnlockedState {
                        benefits
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 72)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomPanel
            }

            closeButton
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            Analytics.paywallViewed(context: context)
            RatingPromptCoordinator.shared.notePaywallShown()
            subscriptionManager.purchaseError = nil
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.2)) { appeared = true }
            }
            Task { await loadPriceIfNeeded() }
        }
        // A container keeps the children's own identifiers (paywall.buy, paywall.restore).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall.\(context.rawValue)")
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            LucideIcon(image: showsUnlockedState ? Lucide.badgeCheck : contextIcon, size: 24)
                .foregroundStyle(showsUnlockedState ? colors.positiveText : colors.actionText)
                .frame(width: 52, height: 52)
                .background(showsUnlockedState ? colors.positiveSurface : colors.actionSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)

            Text(showsUnlockedState ? "Pro is active" : context.title(year: year))
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("paywall.title")

            Text(showsUnlockedState
                 ? "Thanks. Pro stays with your Apple Account, and you can restore it on any device."
                 : context.body)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(colors.textSecondaryOnCanvas)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paywall.body")
        }
    }

    private var contextIcon: UIImage {
        switch context {
        case .export: return Lucide.fileText
        case .secondProperty: return Lucide.building2
        case .dashboardUnlock, .settingsUpgrade: return Lucide.sparkles
        }
    }

    // MARK: Benefits

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(context.benefits.enumerated()), id: \.element) { index, benefit in
                HStack(alignment: .top, spacing: 12) {
                    LucideIcon(image: Lucide.check, size: 16)
                        .foregroundStyle(colors.actionText)
                        .frame(width: 28, height: 28)
                        .background(colors.actionSurface)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(benefit.title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                        Text(benefit.detail)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 14)
                .accessibilityElement(children: .combine)

                if index < context.benefits.count - 1 {
                    Divider().overlay(colors.border.opacity(0.4))
                        .padding(.leading, 40)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(colors.border.opacity(colorScheme == .dark ? 0.5 : 0.3), lineWidth: 1)
        }
    }

    // MARK: Price + actions

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            Divider().overlay(colors.border.opacity(0.35))
            VStack(spacing: 12) {
                if showsUnlockedState {
                    unlockedActions
                } else {
                    priceBlock
                    buyButton
                    restoreButton
                    if let error = subscriptionManager.purchaseError {
                        errorMessage(error)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .background(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.96 : 0.94).ignoresSafeArea(edges: .bottom))
    }

    @ViewBuilder
    private var priceBlock: some View {
        if let product = subscriptionManager.proProduct {
            VStack(spacing: 2) {
                Text(product.displayPrice)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("paywall.price")
                Text("One-time purchase. No subscription.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(product.displayPrice), one-time purchase. No subscription.")
        } else if !priceLoadFinished {
            HStack(spacing: 8) {
                ProgressView()
                Text("Getting the price from the App Store")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
        } else {
            Text("We couldn't load the price. Check your connection, then try again.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 60)
        }
    }

    private var buyButton: some View {
        Button {
            Task { await buy() }
        } label: {
            ZStack {
                if subscriptionManager.isLoading && !isRestoring {
                    ProgressView().tint(colors.onAction)
                } else {
                    Text(subscriptionManager.proProduct == nil && priceLoadFinished ? "Try again" : "Unlock Pro")
                }
            }
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(colors.onAction)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(colors.action)
            .clipShape(Capsule())
        }
        .buttonStyle(.lhPressable)
        .disabled(subscriptionManager.isLoading || (subscriptionManager.proProduct == nil && !priceLoadFinished))
        .accessibilityIdentifier("paywall.buy")
    }

    private var restoreButton: some View {
        Button {
            Task { await restore() }
        } label: {
            Group {
                if isRestoring {
                    ProgressView()
                } else {
                    Text("Restore purchases")
                }
            }
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(colors.actionText)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.lhPressable)
        .disabled(subscriptionManager.isLoading)
        .accessibilityIdentifier("paywall.restore")
    }

    private var unlockedActions: some View {
        Button {
            finish()
        } label: {
            Text(context.continueLabel)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(colors.onAction)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(colors.action)
                .clipShape(Capsule())
        }
        .buttonStyle(.lhPressable)
        .accessibilityIdentifier("paywall.continue")
    }

    private func errorMessage(_ error: String) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                LucideIcon(image: Lucide.circleAlert, size: 14)
                    .foregroundStyle(colors.destructive)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                Text(error)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            #if DEBUG
            if AdminAccess.isCurrentUserAdmin {
                Button("Use local Pro for testing") {
                    subscriptionManager.unlockPro()
                    markUnlocked()
                }
                .font(AppTypography.buttonSmall)
                .foregroundStyle(colors.actionText)
            }
            #endif
        }
        .padding(12)
        .background(colors.destructiveSurface.opacity(colorScheme == .dark ? 0.35 : 0.6))
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("paywall.error")
    }

    private var closeButton: some View {
        Button {
            close()
        } label: {
            LucideIcon(image: Lucide.x, size: 18)
                .foregroundStyle(colors.textPrimary)
                .frame(width: 44, height: 44)
                .background(colors.backgroundTertiary)
                .clipShape(Circle())
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("paywall.close")
        .padding(.top, 16)
        .padding(.trailing, 20)
    }

    // MARK: Actions

    private func loadPriceIfNeeded() async {
        if subscriptionManager.proProduct == nil {
            await subscriptionManager.loadProducts()
        }
        priceLoadFinished = true
    }

    private func buy() async {
        if subscriptionManager.proProduct == nil {
            priceLoadFinished = false
            await loadPriceIfNeeded()
            return
        }
        let outcome = await subscriptionManager.purchasePro()
        if outcome == .purchased {
            Analytics.purchaseCompleted(context: context)
            markUnlocked()
        }
    }

    private func restore() async {
        isRestoring = true
        let restored = await subscriptionManager.restorePurchases()
        isRestoring = false
        if restored { markUnlocked() }
    }

    /// Shows the "Pro is active" state for a moment, then carries on with what the user
    /// was doing.
    private func markUnlocked() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if reduceMotion {
            didUnlockHere = true
        } else {
            withAnimation(.easeOut(duration: 0.2)) { didUnlockHere = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { finish() }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        let continuation = didUnlockHere ? onUnlocked : nil
        close()
        if let continuation {
            // Let the sheet finish dismissing before the next screen is presented.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { continuation() }
        }
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

#Preview {
    PaywallView(context: .export, year: 2026)
}
