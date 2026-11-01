import SwiftUI
import StoreKit

// MARK: - The Pro paywall, 2.3 ("paywall B", frame p1)
//
// Pro is a yearly subscription with Apple's free trial. The page leads with the trial timeline
// (Today → the reminder → the renewal), then the price card, then "In Pro". The foot is pinned:
// the primary, the cancel rule, and Restore · Terms · Privacy (DESIGN-STANDARD §1.23, 2.3).
//
// App Review 3.1.2: the billed amount is StoreKit's `displayPrice`, never a literal. It is the
// largest price text on the page (`.largeTitle` bold, `PriceDisplay`), the renewal and how to
// cancel sit beside the button, and the title never says "free".
//
// Offers (`PaywallOffer`): `.freeTrial` (eligible for the intro offer) leads with the timeline and
// "Start free trial"; `.subscribe` (trial used) shows the card and "Subscribe"; `.owned` shows the
// plan the person has: "Pro for life" for founding buyers (never a trial), or the running plan.
// After a trial starts, the page becomes the trial-start moment (frame p2).

/// The purchase surface the paywall talks to. `SubscriptionManager` in the app; a fake in tests
/// and in the DEBUG state previews.
@MainActor
protocol ProPurchasing: AnyObject {
    var isPro: Bool { get }
    var plan: Plan { get }
    /// A purchase is still waiting on the App Store (also after the purchase deadline).
    var isPurchaseInFlight: Bool { get }
    /// The App Store's localized price for the yearly plan, or nil until products load.
    var proDisplayPrice: String? { get }
    /// Days of the free trial this account can still get, nil when none.
    var introTrialDays: Int? { get }
    func loadProducts() async
    func purchasePro(lateOutcome: @escaping @MainActor (SubscriptionManager.PurchaseOutcome) -> Void) async -> SubscriptionManager.PurchaseOutcome
    func restorePurchases() async -> Bool
}

extension SubscriptionManager: ProPurchasing {
    var proDisplayPrice: String? { proProduct?.displayPrice }
}

@MainActor
final class PaywallModel: ObservableObject {
    @Published private(set) var phase: PaywallPhase
    @Published private(set) var price: String?
    @Published private(set) var trialDays: Int?
    @Published private(set) var plan: Plan
    /// The offer on screen when the purchase or restore started (kept while the success shows).
    @Published private(set) var shownOffer: PaywallOffer?

    let context: PaywallContext
    let entry: LockEntry
    private let store: ProPurchasing
    /// DEBUG previews pin a phase so every state can be captured.
    private let pinned: Bool
    private let pinnedOffer: PaywallOffer?

    private let pinnedPlan: Plan?

    init(context: PaywallContext, entry: LockEntry, store: ProPurchasing, pinnedPhase: PaywallPhase? = nil,
         pinnedOffer: PaywallOffer? = nil, pinnedPlan: Plan? = nil) {
        self.pinnedPlan = pinnedPlan
        self.context = context
        self.entry = entry
        self.store = store
        self.pinned = pinnedPhase != nil
        self.pinnedOffer = pinnedOffer
        self.phase = pinnedPhase ?? (store.proDisplayPrice == nil ? .priceLoading : .ready)
        self.price = store.proDisplayPrice
        self.trialDays = store.introTrialDays
        self.plan = pinnedPlan ?? store.plan
    }

    /// What the page offers: a trial, a plain subscription, or the plan already owned.
    var offer: PaywallOffer {
        if let pinnedOffer { return pinnedOffer }
        // A purchase or restore that just landed shows its success on the page, not "owned".
        if phase == .success {
            if let shownOffer, shownOffer != .owned { return shownOffer }
            return .subscribe
        }
        return PaywallOffer.resolve(plan: plan, eligibleForIntroOffer: trialDays != nil, introTrialDays: trialDays)
    }

    var offeredTrialDays: Int? {
        if case .freeTrial(let days) = offer { return days }
        return nil
    }

    var priceDisplay: PriceDisplay? { price.map { PriceDisplay(billed: $0, trialDays: offeredTrialDays) } }
    var canBuy: Bool { PaywallFlow.canBuy(phase) && price != nil && !store.isPurchaseInFlight }
    /// The purchase deadline passed but the App Store may still answer.
    var isFinishingPurchase: Bool { phase == .failed && store.isPurchaseInFlight }
    var canRestore: Bool { PaywallFlow.canRestore(phase) }
    /// The purchase started Apple's free trial (the page becomes the trial-start moment).
    var startedTrial: Bool {
        guard phase == .success else { return false }
        if case .trial = plan { return true }
        return false
    }

    func start() async {
        guard !pinned else { return }
        if price == nil {
            phase = .priceLoading
            await store.loadProducts()
            sync()
        }
        if phase == .priceLoading || phase == .priceFailed {
            phase = PaywallFlow.afterPriceLoad(found: price != nil)
        }
    }

    func retryPrice() async {
        guard !pinned else { return }
        phase = .priceLoading
        await store.loadProducts()
        sync()
        phase = PaywallFlow.afterPriceLoad(found: price != nil)
    }

    /// Returns true when Pro was unlocked.
    @discardableResult
    func buy() async -> Bool {
        guard !pinned, canBuy else { return false }
        Analytics.paywallCtaTapped(context: context)
        shownOffer = offer
        phase = .buying
        let context = context
        let outcome = await store.purchasePro(lateOutcome: { late in
            // The App Store answered after the deadline: log what really happened. Captures the
            // context, not the model, so it still logs if the paywall was closed meanwhile.
            Self.logPurchase(late, context: context)
        })
        plan = store.plan
        trialDays = store.introTrialDays
        phase = PaywallFlow.afterPurchase(outcome)
        if outcome == .timedOut {
            Analytics.purchaseTimeout(context: context)
        } else {
            Self.logPurchase(outcome, context: context)
        }
        return outcome == .purchased
    }

    private static func logPurchase(_ outcome: SubscriptionManager.PurchaseOutcome, context: PaywallContext) {
        if outcome == .purchased {
            Analytics.purchaseCompleted(context: context)
            Analytics.purchaseSucceeded(context: context)
        } else if let reason = PaywallFlow.failureReason(outcome) {
            Analytics.purchaseFailed(context: context, outcome: reason)
        }
    }

    @discardableResult
    func restore() async -> Bool {
        guard !pinned, canRestore else { return false }
        shownOffer = offer
        phase = .restoring
        let found = await store.restorePurchases()
        plan = store.plan
        phase = PaywallFlow.afterRestore(found: found)
        return found
    }

    /// Ask to Buy approved (or a purchase elsewhere) while the paywall is open.
    func entitlementChanged(isPro: Bool) {
        plan = pinnedPlan ?? store.plan
        guard !pinned else { return }
        phase = PaywallFlow.afterEntitlementChange(isPro: isPro, from: phase)
    }

    private func sync() {
        price = store.proDisplayPrice
        trialDays = store.introTrialDays
        plan = pinnedPlan ?? store.plan
    }
}

// MARK: - The paywall

struct PaywallView: View {
    let context: PaywallContext
    var entry: LockEntry
    var year: Int
    var propertyName: String?
    var confirmedHours: Double?
    var onUnlocked: (() -> Void)?
    var onClose: (() -> Void)?

    @StateObject private var model: PaywallModel
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    @State private var successTick = 0
    @State private var didFinish = false
    @State private var showManage = false
    /// The clock the timeline reads (fixed once per presentation).
    @State private var now = PaywallClock.now()

    /// Keeps the 1.x call shape (`PaywallView(context:onUnlocked:onClose:)`) that Properties uses.
    init(context: PaywallContext,
         entry: LockEntry? = nil,
         year: Int = Calendar.current.component(.year, from: Date()),
         propertyName: String? = nil,
         confirmedHours: Double? = nil,
         store: ProPurchasing? = nil,
         pinnedPhase: PaywallPhase? = nil,
         pinnedOffer: PaywallOffer? = nil,
         pinnedPlan: Plan? = nil,
         onUnlocked: (() -> Void)? = nil,
         onClose: (() -> Void)? = nil) {
        let resolvedEntry = entry ?? Self.defaultEntry(for: context)
        self.context = context
        self.entry = resolvedEntry
        self.year = year
        self.propertyName = propertyName
        self.confirmedHours = confirmedHours
        self.onUnlocked = onUnlocked
        self.onClose = onClose
        _model = StateObject(wrappedValue: PaywallModel(context: context, entry: resolvedEntry,
                                                        store: store ?? SubscriptionManager.shared,
                                                        pinnedPhase: pinnedPhase, pinnedOffer: pinnedOffer,
                                                        pinnedPlan: pinnedPlan))
    }

    static func defaultEntry(for context: PaywallContext) -> LockEntry {
        switch context {
        case .export: return .exportPage
        case .secondProperty: return .propertiesLimit
        case .todayUnlock: return .todayRecord
        case .settings: return .settingsPro
        case .carePlan: return .carePlan
        case .learning: return .learning
        }
    }

    /// Apple's standard EULA (no custom EULA is configured for the app).
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://altaiventures.co/products/dormer/privacy/")!

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        // A real container (not a Group), so the trial start keeps its own identifier inside it.
        ZStack {
            if model.startedTrial, let renewal = model.plan.subscription?.expiresAt {
                TrialStartView(renewal: renewal, price: model.price,
                               onAddRentals: { finish(then: { Self.openAddRental() }) },
                               onMakePDF: { finish(then: { Self.openRecords() }) },
                               onDone: { finish(then: onUnlocked) })
                    .transition(.opacity)
            } else if case .owned = model.offer {
                PaywallOwnedView(plan: model.plan, price: model.price, onClose: close, onManage: { showManage = true })
            } else {
                page
            }
        }
        .animation(AppAnimation.reveal, value: model.startedTrial)
        .onAppear {
            Analytics.paywallViewed(context: context)
            Analytics.paywallShown(context: context, entry: entry)
            RatingPromptCoordinator.shared.notePaywallShown()
        }
        .task { await model.start() }
        .onChange(of: subscriptionManager.isPro) { _, isPro in model.entitlementChanged(isPro: isPro) }
        .onChange(of: model.phase) { _, phase in
            if phase == .success {
                // The trial-start moment plays its own haptic with the windows (one, not two).
                if !model.startedTrial { successTick += 1 }
                UIAccessibility.post(notification: .announcement,
                                     argument: String(localized: "paywall.success.announce", defaultValue: "Pro is on", table: "Pricing"))
            }
        }
        .sensoryFeedback(.success, trigger: successTick)
        .manageSubscriptionsSheet(isPresented: $showManage)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall.\(context.rawValue)")
    }

    // MARK: Page (p1)

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 16)
                if let days = model.offeredTrialDays {
                    LHTimeline(steps: Self.timeline(now: now, trialDays: days, price: model.price))
                        .padding(.top, 20)
                        .accessibilityIdentifier("paywall.timeline")
                }
                priceCard
                    .padding(.top, model.offeredTrialDays == nil ? 20 : LHMetrics.sectionGap)
                inPro
                    .padding(.top, LHMetrics.sectionGap)
                Text(String(localized: "paywall.notNow", defaultValue: "Not now? You keep logging at one rental for free, and every hour stays.", table: "Pricing"))
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 12)
                    .accessibilityIdentifier("paywall.notNow")
            }
            .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        .background { LHPage() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(model.offeredTrialDays != nil
                 ? String(localized: "paywall.title.trial", defaultValue: "How your trial works", table: "Pricing")
                 : String(localized: "paywall.title.subscribe", defaultValue: "Dormer Pro", table: "Pricing"))
                .font(LHFont.screenTitle(size: 28))
                .foregroundStyle(colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("paywall.title")
            Button { close() } label: { Image(systemName: "xmark") }
                .buttonStyle(LHButton.icon)
                .accessibilityLabel(String(localized: "common.close", defaultValue: "Close", table: "Pricing"))
                .accessibilityIdentifier("paywall.close")
        }
    }

    /// Today → the reminder → the renewal, dated from today and the product's trial length.
    static func timeline(now: Date, trialDays: Int, price: String?, calendar: Calendar = .current) -> [LHTimelineStep] {
        let schedule = TrialSchedule.preview(from: now, trialDays: trialDays, calendar: calendar)
        let reminderIn = max(0, trialDays - TrialSchedule.reminderLeadDays)
        let lead = TrialSchedule.reminderLeadDays
        let reminderDate = PricingFormat.short(schedule.reminder)
        let renewalDate = PricingFormat.short(schedule.renewal)
        let renews = price.map {
            String(localized: "paywall.timeline.renew.text",
                   defaultValue: "Pro renews at \($0) a year. Cancel at least a day before and you pay nothing.", table: "Pricing")
        } ?? String(localized: "paywall.timeline.renew.noPrice",
                    defaultValue: "Pro renews each year. Cancel at least a day before and you pay nothing.", table: "Pricing")
        return [
            LHTimelineStep(id: 0, symbol: "lock.open",
                           title: String(localized: "paywall.timeline.today.title", defaultValue: "Today", table: "Pricing"),
                           text: String(localized: "paywall.timeline.today.text",
                                        defaultValue: "Pro is on: every rental, your PDF, care plans and lessons.", table: "Pricing"),
                           reached: true),
            LHTimelineStep(id: 1, symbol: "bell",
                           title: String(localized: "paywall.timeline.reminder.title",
                                         defaultValue: "In \(reminderIn) days · \(reminderDate)", table: "Pricing"),
                           text: String(localized: "paywall.timeline.reminder.text",
                                        defaultValue: "We remind you that the trial ends in \(lead) days.", table: "Pricing")),
            LHTimelineStep(id: 2, symbol: "calendar",
                           title: String(localized: "paywall.timeline.renew.title",
                                         defaultValue: "In \(trialDays) days · \(renewalDate)", table: "Pricing"),
                           text: renews),
        ]
    }

    // MARK: Price card

    private var priceCard: some View {
        let shape = RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "paywall.card.name", defaultValue: "Dormer Pro", table: "Pricing"))
                    .font(.headline)
                    .foregroundStyle(colors.textPrimary)
                Spacer(minLength: 8)
                if let days = model.offeredTrialDays {
                    LHTag(String(localized: "paywall.card.tag", defaultValue: "\(days) days free", table: "Pricing"), tone: .action)
                        .accessibilityIdentifier("paywall.trialTag")
                }
            }
            priceRow
                .padding(.top, 6)
            if model.phase != .success, let display = model.priceDisplay {
                Text(display.planLine)
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .padding(.top, 4)
                    .accessibilityIdentifier("paywall.body")
            }
            statusLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LHMetrics.cardPadding)
        .background(colors.backgroundSecondary, in: shape)
        .overlay { shape.strokeBorder(colors.pageCardEdge, lineWidth: 1) }
    }

    @ViewBuilder private var priceRow: some View {
        switch model.phase {
        case .success:
            Label(String(localized: "paywall.success", defaultValue: "Pro is on", table: "Pricing"), systemImage: "checkmark.circle.fill")
                .font(.title.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(colors.textPrimary)
                .labelStyle(PaywallSuccessLabelStyle(tint: colors.positive))
                .transition(.opacity)
                .accessibilityIdentifier("paywall.success")
        case .priceFailed:
            EmptyView()
        case .priceLoading:
            PlaceholderBar(width: 140, height: 40)
                .accessibilityIdentifier("paywall.priceLoading")
        default:
            if let display = model.priceDisplay {
                PaywallPriceRow(display: display, colors: colors)
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch model.phase {
        case .priceFailed:
            Label(String(localized: "paywall.status.priceFailed", defaultValue: "Couldn’t reach the App Store.", table: "Pricing"),
                  systemImage: "exclamationmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(colors.caution)
                .padding(.top, 8)
                .accessibilityIdentifier("paywall.priceFailed")
        case .askToBuy:
            Label(String(localized: "paywall.status.askToBuy", defaultValue: "Waiting for approval. Pro turns on when it comes through.", table: "Pricing"),
                  systemImage: "clock")
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .padding(.top, 8)
                .accessibilityIdentifier("paywall.askToBuy")
        case .failed:
            Text(model.isFinishingPurchase
                 ? String(localized: "paywall.status.finishing", defaultValue: "Still finishing your purchase…", table: "Pricing")
                 : String(localized: "paywall.status.failed", defaultValue: "Couldn’t finish the purchase. Nothing was charged. Try again in a moment.", table: "Pricing"))
                .font(.subheadline)
                .foregroundStyle(colors.caution)
                .padding(.top, 8)
                .accessibilityIdentifier("paywall.failed")
        case .restoreNone:
            Text(subscriptionManager.restoreFailureMessage
                 ?? String(localized: "paywall.status.restoreNone", defaultValue: "No purchase found on this Apple Account.", table: "Pricing"))
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .padding(.top, 8)
                .accessibilityIdentifier("paywall.restoreNone")
        default:
            EmptyView()
        }
    }

    // MARK: Retired 2.2 names (kept only so ConversionPathTests, a frozen file, still compiles;
    // the conductor removes them with that file's three 2.2 paywall tests)

    /// 2.3 has no record preview on the paywall: its share of the viewport is zero.
    static let previewShare: CGFloat = 0
    static let previewShareAccessibility: CGFloat = 0
    /// The "In Pro" rows under their 2.2 name.
    static var benefitRows: [(symbol: String, title: String, meta: String)] { inProRows }

    // MARK: In Pro

    static var inProRows: [(symbol: String, title: String, meta: String)] {
        [("house", String(localized: "paywall.inPro.rentals.title", defaultValue: "Every rental", table: "Pricing"),
          String(localized: "paywall.inPro.rentals.meta", defaultValue: "Log at as many as you own", table: "Pricing")),
         ("doc.text", String(localized: "paywall.inPro.pdf.title", defaultValue: "The PDF for your CPA", table: "Pricing"),
          String(localized: "paywall.inPro.pdf.meta", defaultValue: "Plus the spreadsheet", table: "Pricing")),
         ("checklist", String(localized: "paywall.inPro.care.title", defaultValue: "Care plans and lessons", table: "Pricing"),
          String(localized: "paywall.inPro.care.meta", defaultValue: "For each rental", table: "Pricing"))]
    }

    private var inPro: some View {
        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            LHSectionHeader(String(localized: "paywall.inPro.header", defaultValue: "In Pro", table: "Pricing"))
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            LHRowGroup(onPage: true) {
                ForEach(Array(Self.inProRows.enumerated()), id: \.offset) { i, item in
                    if i > 0 { LHDivider(leadingInset: LHRow.browseDividerInset) }
                    LHRow.Browse(title: item.title, meta: item.meta, systemImage: item.symbol, showsChevron: false)
                }
            }
        }
        .accessibilityIdentifier("paywall.benefits")
    }

    // MARK: Foot (pinned)

    private var buyLabel: String {
        switch model.phase {
        case .priceLoading: return String(localized: "paywall.cta.loading", defaultValue: "Getting the price", table: "Pricing")
        case .priceFailed: return String(localized: "paywall.cta.retry", defaultValue: "Try again", table: "Pricing")
        case .buying: return String(localized: "paywall.cta.buying", defaultValue: "Waiting for the App Store", table: "Pricing")
        case .askToBuy: return String(localized: "paywall.cta.done", defaultValue: "Done", table: "Pricing")
        case .success: return nextStep
        default:
            return model.priceDisplay?.buttonTitle
                ?? String(localized: "paywall.cta.trial", defaultValue: "Start free trial", table: "Pricing")
        }
    }

    /// After a purchase the button carries on with what the person was doing.
    private var nextStep: String {
        PaywallCopy.localized(context, year: year, propertyName: propertyName, confirmedHours: confirmedHours).nextStep
    }

    private var foot: some View {
        VStack(spacing: 4) {
            Button {
                switch model.phase {
                case .askToBuy: close()
                case .success: finish(then: onUnlocked)
                case .priceFailed: Task { await model.retryPrice() }
                default: Task { await model.buy() }
                }
            } label: {
                HStack(spacing: 10) {
                    if model.phase == .buying || model.phase == .priceLoading || model.phase == .restoring {
                        ProgressView().tint(colors.onAction)
                    }
                    Text(buyLabel).contentTransition(.opacity)
                }
            }
            .buttonStyle(LHButton.primary)
            // Never drawn disabled (a 40% label fails AA): while the App Store works the button
            // shows a spinner and ignores taps; a failed price load turns it into "Try again".
            .allowsHitTesting(![.buying, .priceLoading, .restoring].contains(model.phase)
                              && (model.canBuy || [.askToBuy, .success, .priceFailed].contains(model.phase)))
            .animation(AppAnimation.quick, value: model.phase)
            .accessibilityIdentifier(model.phase == .success ? "paywall.continue"
                                     : (model.phase == .priceFailed ? "paywall.retryPrice" : "paywall.buy"))
            if model.phase != .success {
                Text(String(localized: "paywall.cancelRule", defaultValue: "Cancel any time in Settings, at least a day before it renews.", table: "Pricing"))
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .accessibilityIdentifier("paywall.cancelRule")
                links
            }
        }
        .padding(.horizontal, LHMetrics.gutter)
        .padding(.top, 12)
        .frame(maxWidth: LHMetrics.readingColumn)
        .frame(maxWidth: .infinity)
        .background { LHFootFade(color: colors.pageBottom) }
    }

    /// Restore · Terms · Privacy on one line; stacked at large sizes so no link breaks.
    private var links: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { restoreLink; termsLink; privacyLink }
            VStack(spacing: 0) { restoreLink; HStack(spacing: 20) { termsLink; privacyLink } }
            VStack(spacing: 0) { restoreLink; termsLink; privacyLink }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(colors.action)
    }

    private var restoreLink: some View {
        Button {
            Task { await model.restore() }
        } label: {
            Text(model.phase == .restoring
                 ? String(localized: "paywall.restore.checking", defaultValue: "Checking…", table: "Pricing")
                 : String(localized: "paywall.restore", defaultValue: "Restore purchase", table: "Pricing"))
                .lineLimit(1)
        }
        .buttonStyle(LHButton.press)
        .frame(minHeight: LHMetrics.minTap)
        .disabled(!model.canRestore)
        .accessibilityIdentifier("paywall.restore")
    }

    private var termsLink: some View {
        Button { openURL(Self.termsURL) } label: {
            Text(String(localized: "paywall.terms", defaultValue: "Terms", table: "Pricing")).lineLimit(1)
        }
        .buttonStyle(LHButton.press)
        .frame(minHeight: LHMetrics.minTap)
        .accessibilityLabel(String(localized: "paywall.terms.a11y", defaultValue: "Terms of Use", table: "Pricing"))
        .accessibilityIdentifier("paywall.terms")
    }

    private var privacyLink: some View {
        Button { openURL(Self.privacyURL) } label: {
            Text(String(localized: "paywall.privacy", defaultValue: "Privacy", table: "Pricing")).lineLimit(1)
        }
        .buttonStyle(LHButton.press)
        .frame(minHeight: LHMetrics.minTap)
        .accessibilityLabel(String(localized: "paywall.privacy.a11y", defaultValue: "Privacy Policy", table: "Pricing"))
        .accessibilityIdentifier("paywall.privacy")
    }

    // MARK: Actions

    private func finish(then continuation: (() -> Void)?) {
        guard !didFinish else { return }
        didFinish = true
        close()
        if let continuation {
            // Let the paywall finish dismissing before the next screen is presented.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                continuation()
            }
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    static func openAddRental() {
        NotificationCenter.default.post(name: .switchToPropertiesAndOpenAddProperty, object: nil)
    }

    static func openRecords() {
        NotificationCenter.default.post(name: .switchToTab, object: ShellTab.recordsIndex)
    }
}

/// "<price> a year" on one baseline; stacked when it doesn't fit. The billed amount is
/// `.largeTitle` bold rounded, the largest price text on the page (App Review, `PriceDisplay`).
struct PaywallPriceRow: View {
    let display: PriceDisplay
    let colors: AdaptiveColors
    var trailing: String? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) { billed; caption }
            VStack(alignment: .leading, spacing: 0) { billed; caption }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trailing ?? display.accessibilityLabel)
        .accessibilityIdentifier("paywall.price")
    }

    private var billed: some View {
        Text(display.billed)
            .font(.largeTitle.weight(.bold))
            .fontDesign(.rounded)
            .monospacedDigit()
            .foregroundStyle(colors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var caption: some View {
        Text(trailing ?? display.period)
            .font(.title3.weight(.semibold))
            .foregroundStyle(colors.textPrimary)
    }
}

/// The success label: the check in `positive`, the words in the label's ink.
struct PaywallSuccessLabelStyle: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon.foregroundStyle(tint).accessibilityHidden(true)
            configuration.title
        }
    }
}

// MARK: - Owned: the plan the person already has (never a trial for founding buyers)

struct PaywallOwnedView: View {
    let plan: Plan
    let price: String?
    var onClose: () -> Void
    var onManage: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Text(PlanCopy.title(plan))
                        .font(LHFont.screenTitle(size: 28))
                        .foregroundStyle(colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("paywall.title")
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .buttonStyle(LHButton.icon)
                        .accessibilityLabel(String(localized: "common.close", defaultValue: "Close", table: "Pricing"))
                        .accessibilityIdentifier("paywall.close")
                }
                .padding(.top, 16)
                Text(PlanCopy.body(plan, price: price))
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)
                    .padding(.top, 8)
                    .accessibilityIdentifier("paywall.owned")
                if PlanCopy.showsManage(plan) {
                    if let line = PlanCopy.alsoSubscribedLine(plan) {
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(colors.textSecondary)
                            .padding(.top, 16)
                            .accessibilityIdentifier("paywall.alsoSubscribed")
                    }
                    Button(String(localized: "plan.manage", defaultValue: "Manage subscriptions", table: "Pricing"), action: onManage)
                        .buttonStyle(LHButton.secondary)
                        .padding(.top, 16)
                        .accessibilityIdentifier("paywall.manage")
                }
            }
            .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background { LHPage() }
    }
}

/// The words for a plan, used by the owned paywall and Settings.
enum PlanCopy {
    static func title(_ plan: Plan) -> String {
        switch plan {
        case .founding: return String(localized: "plan.founding.title", defaultValue: "Pro for life", table: "Pricing")
        case .trial: return String(localized: "plan.trial.title", defaultValue: "Your trial is on", table: "Pricing")
        case .pro: return String(localized: "plan.pro.title", defaultValue: "Pro is on", table: "Pricing")
        case .free: return String(localized: "plan.free.title", defaultValue: "Free plan", table: "Pricing")
        }
    }

    static func body(_ plan: Plan, price: String?) -> String {
        switch plan {
        case .founding:
            return String(localized: "plan.founding.body", defaultValue: "You bought Dormer Pro for life. Every rental, the PDF, care plans and lessons stay open.", table: "Pricing")
        case .trial(let sub):
            let date = PricingFormat.short(sub.expiresAt)
            if !sub.willAutoRenew {
                return String(localized: "plan.trial.bodyEnds", defaultValue: "Everything in Pro is open until \(date). It won’t renew.", table: "Pricing")
            }
            if let price {
                return String(localized: "plan.trial.body", defaultValue: "Everything in Pro is open until \(date). Then \(price) a year unless you cancel.", table: "Pricing")
            }
            return String(localized: "plan.trial.bodyNoPrice", defaultValue: "Everything in Pro is open until \(date). Then it renews each year unless you cancel.", table: "Pricing")
        case .pro(let sub):
            let date = PricingFormat.short(sub.expiresAt)
            return sub.willAutoRenew
                ? String(localized: "plan.pro.renews", defaultValue: "Pro renews on \(date).", table: "Pricing")
                : String(localized: "plan.pro.ends", defaultValue: "Pro ends on \(date). It won’t renew.", table: "Pricing")
        case .free:
            return String(localized: "plan.free.body", defaultValue: "You log at one rental for free.", table: "Pricing")
        }
    }

    /// Founding buyers who also hold the yearly plan: one line pointing at Manage subscriptions.
    static func alsoSubscribedLine(_ plan: Plan) -> String? {
        guard case .founding(alsoSubscribed: true) = plan else { return nil }
        return String(localized: "plan.founding.alsoSubscribed",
                      defaultValue: "You also have a yearly plan. You don’t need it with Pro for life. You can cancel it in Manage subscriptions.",
                      table: "Pricing")
    }

    static func showsManage(_ plan: Plan) -> Bool {
        switch plan {
        case .trial, .pro, .founding(alsoSubscribed: true): return true
        case .free, .founding(alsoSubscribed: false): return false
        }
    }

    /// The short plan tag in Settings.
    static func tag(_ plan: Plan) -> String {
        switch plan {
        case .founding: return String(localized: "plan.tag.founding", defaultValue: "Pro for life", table: "Pricing")
        case .trial: return String(localized: "plan.tag.trial", defaultValue: "Pro · Trial", table: "Pricing")
        case .pro: return String(localized: "plan.tag.pro", defaultValue: "Pro", table: "Pricing")
        case .free: return String(localized: "plan.tag.free", defaultValue: "Free plan", table: "Pricing")
        }
    }
}

enum PricingFormat {
    /// "Nov 14".
    static func short(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// The paywall's clock. DEBUG captures pin it (`-LHPricingNow <ISO date>`) so the dates in the
/// timeline match the approved frames; otherwise it's the real time.
enum PaywallClock {
    static func now() -> Date {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-LHPricingNow"), args.indices.contains(i + 1),
           let date = ISO8601DateFormatter().date(from: args[i + 1]) {
            return date
        }
        #endif
        return Date()
    }
}

// MARK: - The paywall's words, from the package catalog

extension PaywallCopy {
    /// The success step the paywall's button becomes, localized in `ConversionPath.xcstrings`.
    /// Standard C.4: "your CPA". `ProGate`'s `make` is the unlocalized original.
    static func localized(_ context: PaywallContext, year: Int, propertyName: String? = nil,
                          confirmedHours: Double? = nil) -> PaywallCopy {
        let yearText = String(year)
        let name = propertyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch context {
        case .export:
            return PaywallCopy(
                headline: String(localized: "The record your CPA gets", table: "ConversionPath"),
                planLine: String(localized: "Export \(yearText) as a PDF or spreadsheet, any time.", table: "ConversionPath"),
                nextStep: String(localized: "Export \(yearText)", table: "ConversionPath"))
        case .secondProperty:
            return PaywallCopy(
                headline: String(localized: "Track every rental", table: "ConversionPath"),
                planLine: name.isEmpty
                    ? String(localized: "Add your next rental and every place after it. Your hours stay put.", table: "ConversionPath")
                    : String(localized: "Add \(name) and every place after it. Your hours stay put.", table: "ConversionPath"),
                nextStep: name.isEmpty
                    ? String(localized: "Add a rental", table: "ConversionPath")
                    : String(localized: "Add \(name)", table: "ConversionPath"))
        case .todayUnlock:
            return PaywallCopy(
                headline: String(localized: "Your hours, on paper", table: "ConversionPath"),
                planLine: confirmedHours.map { hours in
                    let whole = ProGate.wholeHours(hours)
                    return String(localized: "Turn \(whole) confirmed hours into a clean record.", table: "ConversionPath")
                } ?? String(localized: "Turn your confirmed hours into a clean record.", table: "ConversionPath"),
                nextStep: String(localized: "See your record", table: "ConversionPath"))
        case .settings:
            return PaywallCopy(
                headline: String(localized: "Dormer Pro", table: "ConversionPath"),
                planLine: String(localized: "Every rental, the PDF and spreadsheet, and the record of where each hour came from.", table: "ConversionPath"),
                nextStep: String(localized: "Done", table: "ConversionPath"))
        case .carePlan:
            return PaywallCopy(
                headline: String(localized: "paywall.care.headline", defaultValue: "A care plan for each rental", table: "Pricing"),
                planLine: String(localized: "paywall.care.line", defaultValue: "The upkeep each season brings, per rental. You log it and set the hours.", table: "Pricing"),
                nextStep: String(localized: "paywall.care.next", defaultValue: "See the care plan", table: "Pricing"))
        case .learning:
            return PaywallCopy(
                headline: String(localized: "paywall.learn.headline", defaultValue: "Short lessons in plain words", table: "Pricing"),
                planLine: String(localized: "paywall.learn.line", defaultValue: "What counts toward your hours, one card at a time. Each ends with what to ask your CPA.", table: "Pricing"),
                nextStep: String(localized: "paywall.learn.next", defaultValue: "Keep reading", table: "Pricing"))
        }
    }
}

extension PaywallCopy {
    /// Retired: the 2.2 "Unlock for <price>" button. 2.3's primary is "Start free trial" or
    /// "Subscribe" (`PriceDisplay.buttonTitle`) and never carries a price. Kept only for the frozen
    /// ConversionPathTests; nothing in the app calls it.
    @available(*, deprecated, message: "2.2 paywall; use PriceDisplay.buttonTitle")
    static func buyTitle(billed: String?, large: Bool) -> String {
        guard let billed, !large else { return String(localized: "Unlock", table: "ConversionPath") }
        return String(localized: "Unlock for \(billed)", table: "ConversionPath")
    }
}
