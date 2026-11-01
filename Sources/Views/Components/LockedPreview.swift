import SwiftUI

// MARK: - THE locked preview (redesign-specs §0)
//
// One lock for the whole app. It replaces the four 1.x idioms (the Unlock card, the "PRO" text,
// the "Upgrade" row and the lone lock glyph).
// - The real content renders; its first block stays sharp.
// - Below the fold the content blurs (10pt; 4pt for a row) under a fade to the surface.
// - On top: one line saying what is locked, one saying what stays active and free, and one
//   "Unlock Pro" capsule that opens the paywall ABOUT this entry point.
// - After a purchase the blur lifts (10 → 0 over 300ms, ease-out) and the caller carries on.
//
// Sizes: `.page` (a whole surface), `.card` (one block), `.row` (a ghost row).

enum LockSize: Equatable { case page, card, row }

struct LockedPreview<Sharp: View, Locked: View>: View {
    let size: LockSize
    let entry: LockEntry
    let line: String
    let keeps: String
    var unlocked = false
    /// The fade's target colour: the canvas for pages, the card for cards.
    var surface: Color? = nil
    /// A stamp drawn on top of the blur (e.g. "PREVIEW" over a blurred page), never blurred.
    var stamp: String? = nil
    /// Side inset of a `.row` lock's line and button (0 inside a List row, which insets already).
    var rowInset: CGFloat = 16
    var onUnlock: () -> Void
    @ViewBuilder var sharp: () -> Sharp
    @ViewBuilder var locked: () -> Locked

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reported = false

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var blur: CGFloat { unlocked ? 0 : (size == .row ? 4 : 10) }
    private var motion: Animation { reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.3) }

    var body: some View {
        Group {
            switch size {
            case .row: row
            case .page, .card: block
            }
        }
        .animation(motion, value: unlocked)
        .onAppear {
            guard !unlocked, !reported else { return }
            reported = true
            Analytics.lockPreviewShown(entry: entry)
        }
    }

    private var block: some View {
        VStack(alignment: .leading, spacing: 0) {
            sharp()
            ZStack(alignment: .top) {
                locked()
                    .blur(radius: blur)
                    .allowsHitTesting(unlocked)
                    .accessibilityHidden(!unlocked)
                if !unlocked {
                    let fill = surface ?? colors.background
                    VStack(spacing: 0) {
                        LinearGradient(colors: [fill.opacity(0), fill.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 48)
                        fill.opacity(0.85)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
                    cta
                        .padding(.top, size == .page ? 72 : 40)
                        .transition(.opacity)
                    if let stamp {
                        LockStamp(text: stamp)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 14)
                            .padding(.trailing, 18)
                            .transition(.opacity)
                    }
                }
            }
            .clipped()
        }
    }

    private var cta: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(line)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                    .accessibilityIdentifier("lock.line")
                Text(keeps)
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .accessibilityIdentifier("lock.keeps")
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            UnlockProButton(entry: entry, action: onUnlock)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lock.\(entry.rawValue)")
    }

    private var row: some View {
        VStack(spacing: 0) {
            locked()
                .blur(radius: blur)
                .opacity(unlocked ? 1 : 0.6)
                .allowsHitTesting(unlocked)
                .accessibilityHidden(!unlocked)
            if !unlocked {
                let layout = dts.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                    : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line).font(.subheadline.weight(.semibold)).foregroundStyle(colors.textPrimary)
                            .accessibilityIdentifier("lock.line")
                        Text(keeps).font(.footnote).foregroundStyle(colors.textSecondary)
                            .accessibilityIdentifier("lock.keeps")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    UnlockProButton(entry: entry, action: onUnlock).fixedSize()
                }
                .padding(.horizontal, rowInset)
                .padding(.top, 4)
                .padding(.bottom, 14)
                .transition(.opacity)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("lock.\(entry.rawValue)")
            }
        }
    }
}

extension LockedPreview where Sharp == EmptyView {
    /// A row (or block) with nothing kept sharp.
    init(size: LockSize, entry: LockEntry, line: String, keeps: String, unlocked: Bool = false, surface: Color? = nil,
         rowInset: CGFloat = 16, onUnlock: @escaping () -> Void, @ViewBuilder content: @escaping () -> Locked) {
        self.init(size: size, entry: entry, line: line, keeps: keeps, unlocked: unlocked, surface: surface,
                  rowInset: rowInset, onUnlock: onUnlock, sharp: { EmptyView() }, locked: content)
    }
}

/// The one "Unlock Pro" action: a 44pt primary capsule with `lock.fill`, spelled the same
/// everywhere.
struct UnlockProButton: View {
    var entry: LockEntry
    var title = "Unlock Pro"
    var fullWidth = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            // Glyph and words drawn explicitly: some containers (List rows) render a Label as
            // icon-only, which hid "Unlock Pro" in Settings.
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").accessibilityHidden(true)
                Text(title)
            }
        }
        .buttonStyle(ProUnlockButtonStyle(fullWidth: fullWidth))
        .accessibilityLabel(title)
        .accessibilityHint("Opens Dormer Pro")
        .accessibilityIdentifier("lock.unlock")
    }
}

struct ProUnlockButtonStyle: ButtonStyle {
    var fullWidth = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        configuration.label
            .font(fullWidth ? AppTypography.buttonLarge : .subheadline.weight(.semibold))
            .foregroundStyle(colors.onAction)
            .lineLimit(fullWidth ? 2 : 1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: fullWidth ? 52 : 44)
            .background(Capsule().fill(colors.action))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : AppAnimation.feedback, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Tinted (44pt, action on actionSurface, 15 semibold). Settings' "See Pro".
struct ProTintedButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.action)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(Capsule().fill(colors.actionSurface))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : AppAnimation.feedback, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

// MARK: - The one paywall host

/// Installed once on the shell. Presents `ProPaywallPresenter.shared.request` full screen, and
/// the 2.3 plan moments as sheets (`PlanMomentsHost`): the day-12 reminder and the free-rental pick.
struct ProPaywallHost: ViewModifier {
    @ObservedObject var presenter: ProPaywallPresenter = .shared
    @EnvironmentObject private var viewModel: AppViewModel

    func body(content: Content) -> some View {
        content
            .background { PlanMomentsHost() }
            .fullScreenCover(item: $presenter.request) { request in
                PaywallView(
                    context: request.context,
                    entry: request.entry,
                    year: request.year,
                    propertyName: request.propertyName,
                    confirmedHours: request.confirmedHours,
                    onUnlocked: request.onUnlocked,
                    onClose: { presenter.dismiss() }
                )
                .environmentObject(viewModel)
            }
    }
}

/// A plan moment the shell shows on its own (never while the paywall is up).
enum PlanMoment: Identifiable, Equatable {
    case day12(renewal: Date, originalTransactionID: UInt64)
    case pickFree(PickFreeRentalSheet.Reason)

    var id: String {
        switch self {
        case .day12(_, let id): return "day12.\(id)"
        case .pickFree: return "pickFree"
        }
    }

    /// What to show for this plan right now: the reminder first, then the pick.
    static func next(plan: Plan, shouldShowDay12: Bool, needsPick: Bool, lastPlanKind: String?) -> PlanMoment? {
        if shouldShowDay12, case .trial(let sub) = plan {
            return .day12(renewal: sub.expiresAt, originalTransactionID: sub.originalTransactionID)
        }
        if needsPick {
            switch lastPlanKind {
            case "trial": return .pickFree(.trialEnded)
            case "pro": return .pickFree(.proEnded)
            default: return .pickFree(.unknown)
            }
        }
        return nil
    }
}

/// Watches the plan and shows the day-12 sheet and the pick sheet. Keeps the day-12 local
/// notification in step (`TrialReminderScheduler`) and remembers the last plan kind per profile,
/// so the pick sheet can say "Your trial has ended" rather than guess.
struct PlanMomentsHost: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var store = EntitlementStore.shared
    @ObservedObject private var presenter = ProPaywallPresenter.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var moment: PlanMoment?

    static let lastPlanKey = "pricing.lastPlan.v1"

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                #if DEBUG
                PricingDebugLaunch.applyIfNeeded(app: viewModel)
                #endif
                evaluate()
            }
            .onChange(of: store.plan) { _, _ in evaluate() }
            .onChange(of: viewModel.properties.count) { _, _ in evaluate() }
            .onChange(of: presenter.request == nil) { _, closed in if closed { evaluate() } }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                evaluate()
                // Auto-renew turned off in Settings › Subscriptions arrives as a renewal change:
                // re-read StoreKit so the day-12 reminder is cancelled (a plan change re-runs evaluate).
                Task { await SubscriptionManager.shared.refreshEntitlements() }
            }
            .sheet(item: $moment, onDismiss: dismissed) { moment in
                switch moment {
                case .day12(let renewal, let id):
                    Day12ReminderSheet(renewal: renewal, price: subscriptionManager.proDisplayPrice,
                                       freeRentalName: viewModel.freeRentalName,
                                       onAnswered: { store.markDay12ReminderShown(for: id) })
                        .presentationDetents([.fraction(0.72), .large])
                        .presentationDragIndicator(.visible)
                        .environmentObject(viewModel)
                case .pickFree(let reason):
                    PickFreeRentalSheet(reason: reason, onSeePro: {
                        self.moment = nil
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(450))
                            ProPaywallPresenter.shared.present(entry: .freeRentalPick)
                        }
                    })
                    .presentationDetents([.fraction(0.7), .large])
                    .presentationDragIndicator(.visible)
                    .environmentObject(viewModel)
                }
            }
    }

    private var lastPlanKind: String? { UserDefaults.standard.string(forKey: UserScope.key(Self.lastPlanKey)) }

    private func evaluate() {
        let plan = store.plan
        Task { await TrialReminderScheduler.shared.sync(plan: plan, price: subscriptionManager.proDisplayPrice) }
        defer {
            // Remember Pro plans only; "free" never overwrites how Pro ended.
            if plan.hasProAccess { UserDefaults.standard.set(plan.kind, forKey: UserScope.key(Self.lastPlanKey)) }
        }
        guard presenter.request == nil, moment == nil, viewModel.isSignedIn else { return }
        #if DEBUG
        if let forced = PricingDebugLaunch.forcedMoment() { moment = forced; return }
        #endif
        moment = PlanMoment.next(plan: plan, shouldShowDay12: store.shouldShowDay12Reminder(),
                                 needsPick: store.needsFreeRentalPick(rentals: viewModel.rentalUsages),
                                 lastPlanKind: lastPlanKind)
    }

    /// A swipe-down on the pick sheet keeps the most-used rental (without using up the pick).
    private func dismissed() {
        if store.needsFreeRentalPick(rentals: viewModel.rentalUsages) {
            store.keepDefaultFreeRental(rentals: viewModel.rentalUsages)
            FreeRentalSync.shared.localPickChanged()
        }
    }
}

extension View {
    /// Lets any screen open the one paywall through `ProPaywallPresenter.shared`.
    func proPaywallHost() -> some View { modifier(ProPaywallHost()) }

    /// Presents the paywall from a local `PaywallContext?`/request binding as a full-screen cover.
    func proPaywall(_ request: Binding<ProPaywallRequest?>) -> some View {
        modifier(LocalPaywallCover(request: request))
    }
}

private struct LocalPaywallCover: ViewModifier {
    @Binding var request: ProPaywallRequest?
    @EnvironmentObject private var viewModel: AppViewModel

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $request) { request in
            PaywallView(
                context: request.context,
                entry: request.entry,
                year: request.year,
                propertyName: request.propertyName,
                confirmedHours: request.confirmedHours,
                onUnlocked: request.onUnlocked,
                onClose: { self.request = nil }
            )
            .environmentObject(viewModel)
        }
    }
}

/// A drafting-ink stamp, unblurred, on top of a locked preview (≥5:1 on the canvas and card).
struct LockStamp: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let ink = AdaptiveColors(colorScheme: colorScheme).draftingInk
        Text(text)
            .font(.caption.weight(.bold)).tracking(1.5)
            .foregroundStyle(ink)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 4).fill(AdaptiveColors(colorScheme: colorScheme).backgroundSecondary))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(ink, lineWidth: 1.5))
            .rotationEffect(.degrees(-6))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityIdentifier("lock.stamp")
    }
}
