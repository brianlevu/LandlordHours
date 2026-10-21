import SwiftUI
import StoreKit

// MARK: - The one Pro paywall (redesign-specs §1a)
//
// Sells one thing, Pro, paid once, by showing the product itself: page 1 of the record.
// Opens at the moment of need and speaks to the thing tapped (`context`). After a purchase the
// button becomes the next step of what the user was doing, and `onUnlocked` carries it on.
//
// App Review: the billed amount (the App Store's localized price) is the largest price text on
// the page and sits first; any trial or intro line is smaller and below it (`PriceDisplay`).
// Terms of Use and Privacy Policy links sit inside the plan card, visible without scrolling.

/// The purchase surface the paywall talks to. `SubscriptionManager` in the app; a fake in tests
/// and in the DEBUG state previews.
@MainActor
protocol ProPurchasing: AnyObject {
    var isPro: Bool { get }
    /// A purchase is still waiting on the App Store (also after the purchase deadline).
    var isPurchaseInFlight: Bool { get }
    /// The App Store's localized price for Pro, or nil until products load.
    var proDisplayPrice: String? { get }
    var proIsFamilyShareable: Bool { get }
    func loadProducts() async
    func purchasePro(lateOutcome: @escaping @MainActor (SubscriptionManager.PurchaseOutcome) -> Void) async -> SubscriptionManager.PurchaseOutcome
    func restorePurchases() async -> Bool
}

extension SubscriptionManager: ProPurchasing {
    var proDisplayPrice: String? { proProduct?.displayPrice }
    var proIsFamilyShareable: Bool { proProduct?.isFamilyShareable ?? false }
}

@MainActor
final class PaywallModel: ObservableObject {
    @Published private(set) var phase: PaywallPhase
    @Published private(set) var price: String?
    @Published private(set) var familyShareable = false

    let context: PaywallContext
    let entry: LockEntry
    private let store: ProPurchasing
    /// DEBUG previews pin a phase so every state can be captured.
    private let pinned: Bool

    init(context: PaywallContext, entry: LockEntry, store: ProPurchasing, pinnedPhase: PaywallPhase? = nil) {
        self.context = context
        self.entry = entry
        self.store = store
        self.pinned = pinnedPhase != nil
        self.phase = pinnedPhase ?? (store.proDisplayPrice == nil ? .priceLoading : .ready)
        self.price = store.proDisplayPrice
        self.familyShareable = store.proIsFamilyShareable
    }

    var priceDisplay: PriceDisplay? { price.map { PriceDisplay(billed: $0, intro: nil) } }
    var canBuy: Bool { PaywallFlow.canBuy(phase) && price != nil && !store.isPurchaseInFlight }
    /// The purchase deadline passed but the App Store may still answer.
    var isFinishingPurchase: Bool { phase == .failed && store.isPurchaseInFlight }
    var canRestore: Bool { PaywallFlow.canRestore(phase) }

    func start() async {
        guard !pinned else { return }
        if price == nil {
            phase = .priceLoading
            await store.loadProducts()
            price = store.proDisplayPrice
            familyShareable = store.proIsFamilyShareable
        }
        if phase == .priceLoading || phase == .priceFailed {
            phase = PaywallFlow.afterPriceLoad(found: price != nil)
        }
    }

    func retryPrice() async {
        guard !pinned else { return }
        phase = .priceLoading
        await store.loadProducts()
        price = store.proDisplayPrice
        familyShareable = store.proIsFamilyShareable
        phase = PaywallFlow.afterPriceLoad(found: price != nil)
    }

    /// Returns true when Pro was unlocked.
    @discardableResult
    func buy() async -> Bool {
        guard !pinned, canBuy else { return false }
        Analytics.paywallCtaTapped(context: context)
        phase = .buying
        let context = context
        let outcome = await store.purchasePro(lateOutcome: { late in
            // The App Store answered after the deadline: log what really happened. Captures the
            // context, not the model, so it still logs if the paywall was closed meanwhile.
            Self.logPurchase(late, context: context)
        })
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
        phase = .restoring
        let found = await store.restorePurchases()
        phase = PaywallFlow.afterRestore(found: found)
        return found
    }

    /// Ask to Buy approved (or a purchase elsewhere) while the paywall is open.
    func entitlementChanged(isPro: Bool) {
        guard !pinned else { return }
        phase = PaywallFlow.afterEntitlementChange(isPro: isPro, from: phase)
    }
}

/// The scheme the user actually runs, read without the paywall's own dark window override.
enum PaywallScheme {
    static func user() -> ColorScheme {
        if let forced = AppearanceManager.forcedColorSchemeFromLaunchArguments { return forced }
        if let chosen = AppearanceManager.shared.preferredColorScheme { return chosen }
        return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }
}

struct PaywallView: View {
    let context: PaywallContext
    var entry: LockEntry
    var year: Int
    var propertyName: String?
    var confirmedHours: Double?
    var onUnlocked: (() -> Void)?
    var onClose: (() -> Void)?
    /// DEBUG: scroll to "What you get" on appear (capture of the below-the-fold state).
    var startsBelowFold = false
    /// DEBUG: hold the page in its drafting state (capture).
    var holdsPageLoading = false
    /// DEBUG: show the sample page even when the user has entries (capture).
    var forcesSample = false

    @StateObject private var model: PaywallModel
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var page: RecordPageModel?
    @State private var shown = false
    @State private var successTick = 0
    @State private var overHero = true
    @State private var didFinish = false
    @State private var userScheme = PaywallScheme.user()

    /// Keeps the 1.x call shape (`PaywallView(context:onUnlocked:onClose:)`) that Properties uses.
    init(context: PaywallContext,
         entry: LockEntry? = nil,
         year: Int = Calendar.current.component(.year, from: Date()),
         propertyName: String? = nil,
         confirmedHours: Double? = nil,
         store: ProPurchasing? = nil,
         pinnedPhase: PaywallPhase? = nil,
         startsBelowFold: Bool = false,
         holdsPageLoading: Bool = false,
         forcesSample: Bool = false,
         onUnlocked: (() -> Void)? = nil,
         onClose: (() -> Void)? = nil) {
        let resolvedEntry = entry ?? Self.defaultEntry(for: context)
        self.context = context
        self.entry = resolvedEntry
        self.year = year
        self.propertyName = propertyName
        self.confirmedHours = confirmedHours
        self.startsBelowFold = startsBelowFold
        self.holdsPageLoading = holdsPageLoading
        self.forcesSample = forcesSample
        self.onUnlocked = onUnlocked
        self.onClose = onClose
        _model = StateObject(wrappedValue: PaywallModel(context: context, entry: resolvedEntry,
                                                        store: store ?? SubscriptionManager.shared, pinnedPhase: pinnedPhase))
    }

    static func defaultEntry(for context: PaywallContext) -> LockEntry {
        switch context {
        case .export: return .exportPage
        case .secondProperty: return .propertiesLimit
        case .todayUnlock: return .todayRecord
        case .settings: return .settingsPro
        }
    }

    /// Apple's standard EULA (no custom EULA is configured for the app).
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://gist.github.com/brianlevu/5e4dbbf64a69c0be6b981aabcea1b8db#file-privacy-html")!

    private var copy: PaywallCopy {
        PaywallCopy.make(context, year: year, propertyName: propertyName, confirmedHours: confirmedHours)
    }
    private var big: Bool { dts >= .xxLarge }
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: userScheme) }

    var body: some View {
        // The window runs dark while the blue hero is under the status bar (light status-bar text
        // in both themes); the page keeps the user's scheme through its environment.
        content
            .environment(\.colorScheme, userScheme)
            .preferredColorScheme(overHero ? .dark : userScheme)
            .onAppear {
                Analytics.paywallViewed(context: context)
                Analytics.paywallShown(context: context, entry: entry)
                RatingPromptCoordinator.shared.notePaywallShown()
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.28).delay(0.06)) { shown = true }
            }
            .task { await model.start() }
            .task { await loadPage() }
            .onChange(of: subscriptionManager.isPro) { _, isPro in model.entitlementChanged(isPro: isPro) }
            .onChange(of: model.phase) { _, phase in
                if phase == .success {
                    successTick += 1
                    UIAccessibility.post(notification: .announcement, argument: "Pro is yours")
                }
            }
            .sensoryFeedback(.success, trigger: successTick)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("paywall.\(context.rawValue)")
    }

    private var content: some View {
        GeometryReader { g in
            let heroH = g.size.height * (big ? 0.30 : 0.46) + g.safeAreaInsets.top
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        hero(width: g.size.width, height: heroH, top: g.safeAreaInsets.top)
                        planCard
                            .padding(.horizontal, 16)
                            .padding(.top, -40)
                        benefits
                            .id("benefits")
                            .padding(.horizontal, 20)
                            .padding(.top, 32)
                            .padding(.bottom, 48)
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)
                .modifier(PaywallScrollObserver { y in
                    updateOverHero(offset: y, heroH: heroH, top: g.safeAreaInsets.top)
                })
                .onAppear {
                    if startsBelowFold { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { proxy.scrollTo("benefits", anchor: .top) } }
                }
            }
            .overlay(alignment: .top) {
                // A solid band behind the status bar: blueprint while the hero is under it, canvas
                // once scrolled past, so the clock always reads (white on blue, dark on canvas).
                (overHero ? AppColors.brand : colors.background)
                    .frame(height: g.safeAreaInsets.top)
                    .frame(maxWidth: .infinity)
                    .offset(y: -g.safeAreaInsets.top)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.2), value: overHero)
                    .accessibilityElement()
                    .accessibilityLabel("")
                    .accessibilityIdentifier(overHero ? "paywall.band.hero" : "paywall.band.canvas")
            }
            .overlay(alignment: .topTrailing) {
                PaywallCloseButton { close() }
                    .padding(.trailing, 16)
                    .padding(.top, 4)
            }
        }
        .background(colors.background.ignoresSafeArea())
    }

    /// The blue band (and the dark window) only while the hero is under the status bar.
    private func updateOverHero(offset y: CGFloat, heroH: CGFloat, top: CGFloat) {
        let over = y < heroH - top - 8
        if overHero != over { overHero = over }
    }

    // MARK: Hero

    private func hero(width: CGFloat, height: CGFloat, top: CGFloat) -> some View {
        ZStack(alignment: .top) {
            InboxBlueprintPaper(cornerRadius: 0)
            VStack(spacing: big ? 14 : 22) {
                Text(copy.headline)
                    .lhDisplayFont(.title)
                    // Display type stops growing at XXL, as in the sandbox: AX sizes keep 2–3 lines.
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(dts.isAccessibilitySize ? 4 : 2)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, dts.isAccessibilitySize ? 24 : 60)
                    .padding(.trailing, dts.isAccessibilitySize ? 36 : 0)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("paywall.title")
                // Accessibility sizes keep the page (smaller, cropped) so the record, the sample
                // stamp and the drafting state still show.
                phone(width: width * (dts.isAccessibilitySize ? 0.5 : 0.62))
                    .frame(height: dts.isAccessibilitySize ? width * 0.42 : nil, alignment: .top)
                    .clipped()
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown || reduceMotion ? 0 : 12)
            }
            .padding(.top, top + 20)
            .padding(.bottom, dts.isAccessibilitySize ? 40 : 0)
        }
        .frame(height: dts.isAccessibilitySize ? nil : height, alignment: .top)
        .clipped()
    }

    private func phone(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 44, style: .continuous)
            .strokeBorder(HouseTokens.drafting, lineWidth: 2)
            .frame(width: width, height: width * 2.05)
            .overlay(alignment: .top) {
                Group {
                    if let page, !holdsPageLoading {
                        RecordPagePreview(model: page, highlight: RecordPageHighlight.forContext(context, propertyName: propertyName))
                            .frame(width: width - 24)
                            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                            .padding(.top, 12)
                            .transition(.opacity)
                    } else {
                        DraftingLoader(sketch: .document, surface: .blueprint, subject: "your record")
                            .frame(width: width * 0.6)
                            .padding(.top, 40)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: page)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(page?.isSample == true ? "A sample page of the PDF record" : "Page 1 of your PDF record")
            .accessibilityIdentifier("paywall.page")
    }

    // MARK: Plan card

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            (dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))) {
                Text("LandlordHours Pro").font(.headline).foregroundStyle(colors.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6).allowsTightening(true)
                Text("PAY ONCE")
                    .font(.system(size: 11, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(colors.action)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(colors.actionSurface))
                Spacer(minLength: 0)
            }
            priceRow
            Text(copy.planLine)
                .font(.subheadline).foregroundStyle(colors.textSecondary)
                .lineLimit(big ? 5 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paywall.body")
            statusLine
            buyButton
            if model.phase != .success {
                Button {
                    Task { if await model.restore() { } }
                } label: {
                    Text(model.phase == .restoring ? "Checking…" : "Restore purchase")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.lhPressable)
                .font(.subheadline).foregroundStyle(colors.action)
                .disabled(!model.canRestore)
                .overlay(alignment: .bottom) {
                    if model.phase == .restoring { PaywallDraftingLine(color: colors.draftingInk).frame(width: 90).offset(y: -8) }
                }
                .accessibilityIdentifier("paywall.restore")
            }
            if model.phase == .restoreNone {
                // A restore that errored or timed out says so; "no purchase" only when the App
                // Store answered and found nothing.
                Text(subscriptionManager.restoreFailureMessage ?? "No purchase found on this Apple Account.")
                    .font(.footnote).foregroundStyle(colors.textSecondary).frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("paywall.restoreNone")
            }
            Rectangle().fill(colors.border).frame(height: 0.5)
            VStack(alignment: .leading, spacing: 8) {
                Label("No subscription", systemImage: "infinity")
                if model.familyShareable { Label("Family Sharing", systemImage: "person.2") }
            }
            .font(.subheadline).foregroundStyle(colors.textSecondary)
            .labelStyle(PaywallLabelStyle())
            legalLinks
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(colors.backgroundSecondary))
        .shadow(color: .black.opacity(userScheme == .dark ? 0 : 0.06), radius: 16, y: 6)
    }

    @ViewBuilder private var priceRow: some View {
        switch model.phase {
        case .success:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 34)).foregroundStyle(colors.positive)
                    .accessibilityHidden(true)
                Text("Pro is yours").font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(colors.textPrimary)
                    .accessibilityIdentifier("paywall.success")
            }
            .transition(.opacity)
        case .priceFailed:
            EmptyView()
        case .priceLoading:
            PlaceholderBar(width: 120, height: 40)
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
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").accessibilityHidden(true)
                    Text("Couldn’t reach the App Store.")
                    Spacer(minLength: 4)
                    retryButton
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label("Couldn’t reach the App Store.", systemImage: "exclamationmark.circle.fill")
                    retryButton
                }
            }
            .font(.subheadline).foregroundStyle(colors.caution)
            .accessibilityIdentifier("paywall.priceFailed")
        case .askToBuy:
            Label("Waiting for approval. Pro unlocks when it comes through.", systemImage: "clock")
                .font(.subheadline).foregroundStyle(colors.textSecondary).labelStyle(PaywallLabelStyle())
                .accessibilityIdentifier("paywall.askToBuy")
        default: EmptyView()
        }
    }

    private var retryButton: some View {
        Button("Try again") { Task { await model.retryPrice() } }
            .fontWeight(.semibold).foregroundStyle(colors.action)
            .frame(minHeight: 44)
            .accessibilityIdentifier("paywall.retryPrice")
    }

    private var buyLabel: String {
        switch model.phase {
        case .priceLoading, .priceFailed: return "Unlock Pro"
        case .buying: return "Waiting for the App Store"
        case .askToBuy: return "Done"
        case .success: return copy.nextStep
        default: return model.priceDisplay?.buttonTitle(large: big) ?? "Unlock Pro"
        }
    }

    private var buyButton: some View {
        VStack(spacing: 8) {
            Button {
                switch model.phase {
                case .askToBuy: close()
                case .success: finish()
                default: Task { await model.buy() }
                }
            } label: {
                // Buying: the drafting line sits under the label's own bounds, so a wrapped
                // label at large sizes is never struck through.
                VStack(spacing: 4) {
                    Text(buyLabel).contentTransition(.opacity).lineLimit(3).multilineTextAlignment(.center)
                        .minimumScaleFactor(0.75)
                    if model.phase == .buying {
                        PaywallDraftingLine(color: userScheme == .dark ? colors.onAction : HouseTokens.drafting, lineWidth: 2)
                            .frame(width: 96)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, model.phase == .buying ? 8 : 0)
            }
            .buttonStyle(InboxPrimaryButtonStyle())
            .disabled(!(model.canBuy || model.phase == .askToBuy || model.phase == .success || model.phase == .buying))
            .allowsHitTesting(model.phase != .buying)
            .animation(.easeOut(duration: 0.2), value: model.phase)
            .accessibilityIdentifier(model.phase == .success ? "paywall.continue" : "paywall.buy")
            if model.phase == .failed {
                Text(model.isFinishingPurchase ? "Still finishing your purchase…" : "That didn’t go through. Try again in a moment.")
                    .font(.subheadline).foregroundStyle(colors.caution).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("paywall.failed")
            }
        }
    }

    private var legalLinks: some View {
        // Each link stays on one line; at large sizes they stack instead of breaking.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { termsLink; Text("·").accessibilityHidden(true); privacyLink }
            VStack(alignment: .leading, spacing: 4) { termsLink; privacyLink }
        }
        .font(.footnote)
        .foregroundStyle(colors.textSecondary)
        .buttonStyle(.plain)
        .frame(minHeight: 32)
    }

    private var termsLink: some View {
        Button { openURL(Self.termsURL) } label: { Text("Terms\u{00A0}of\u{00A0}Use").lineLimit(1).fixedSize() }
            .frame(minHeight: 32)
            .accessibilityIdentifier("paywall.terms")
    }

    private var privacyLink: some View {
        Button { openURL(Self.privacyURL) } label: { Text("Privacy\u{00A0}Policy").lineLimit(1).fixedSize() }
            .frame(minHeight: 32)
            .accessibilityIdentifier("paywall.privacy")
    }

    // MARK: Benefits

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What you get")
                .font(.footnote.weight(.semibold)).textCase(.uppercase).tracking(0.3)
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(PaywallCopy.benefits, id: \.title) { item in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: item.symbol).font(.system(size: 20)).foregroundStyle(colors.action)
                        .frame(width: 28, height: 28).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.headline).foregroundStyle(colors.textPrimary)
                        Text(item.line).font(.subheadline).foregroundStyle(colors.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Actions

    private func loadPage() async {
        guard page == nil else { return }
        if forcesSample { page = .sample(year: year); return }
        page = await RecordPageModel.load(entries: viewModel.timeEntries, properties: viewModel.properties,
                                          owner: viewModel.userName, year: year)
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        let continuation = onUnlocked
        close()
        if let continuation {
            // Let the paywall finish dismissing before the next screen is presented.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { continuation() }
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
}

/// iOS 18+: the scroll view reports its own offset. iOS 17 keeps the blueprint band throughout
/// (still legible: white status text on blue).
private struct PaywallScrollObserver: ViewModifier {
    var onChange: (CGFloat) -> Void
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
                onChange(y)
            }
        } else {
            content
        }
    }
}


/// "$29.99 once, yours to keep" on one baseline; stacked when it doesn't fit.
struct PaywallPriceRow: View {
    let display: PriceDisplay
    let colors: AdaptiveColors
    @ScaledMetric(relativeTo: .largeTitle) private var billedSize: CGFloat = PriceDisplay.billedSize

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) { billed; caption }
            VStack(alignment: .leading, spacing: 0) { billed; caption }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.accessibilityLabel)
        .accessibilityIdentifier("paywall.price")
    }

    private var billed: some View {
        Text(display.billed)
            .font(.system(size: billedSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(colors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var caption: some View {
        Text(PriceDisplay.caption).font(.subheadline).foregroundStyle(colors.textSecondary)
    }
}

/// 44pt close on a solid blueprint disc with a white glyph: 9.1:1 whatever scrolls under it
/// (r4 gate: the glass close was 1.79:1 over the white plan card at light XXL).
struct PaywallCloseButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(AppColors.brand))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("paywall.close")
    }
}

struct PaywallLabelStyle: LabelStyle {
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 22
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            configuration.icon.frame(minWidth: iconWidth).accessibilityHidden(true)
            configuration.title
        }
    }
}

/// A short drafting line that draws itself left to right, then restarts (Reduce Motion: still).
struct PaywallDraftingLine: View {
    var color: Color
    var lineWidth: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        TimelineView(.animation(paused: reduce)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let p = reduce ? 1 : CGFloat((t.truncatingRemainder(dividingBy: 1.6)) / 1.6)
            GeometryReader { g in
                Path { $0.move(to: .init(x: 0, y: g.size.height / 2)); $0.addLine(to: .init(x: g.size.width, y: g.size.height / 2)) }
                    .trim(from: reduce ? 0 : max(0, p - 0.55), to: p)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
        .frame(height: max(2, lineWidth))
        .opacity(reduce ? 0.6 : 1)
        .accessibilityHidden(true)
    }
}
