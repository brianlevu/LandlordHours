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


// MARK: - The paywall (standard §1.23, v2)
//
// The plain canvas, no blueprint band, no house. A sheet header names the thing tapped (the first
// line), then the record preview (page 1, its title is `pdf.title`, ≤ 40% of the viewport; 35% here
// so "What you get" stays above the fold), the plan card (radius 20: name + "Pay once" tag, the
// price in `.largeTitle.rounded.bold`, one line, the `.primary`, the `.tertiary` Restore, the status
// line, the legal links), then "What you get" as 56pt `LHRow.Browse` rows. Close is `.icon`. No
// countdowns, no scarcity, no Dynamic Type clamp. The status bar follows the appearance.

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
    /// DEBUG: hold the page in its loading state (capture).
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
    @Environment(\.colorScheme) private var colorScheme

    @State private var page: RecordPageModel?
    @State private var successTick = 0
    @State private var didFinish = false

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
    static let privacyURL = URL(string: "https://altaiventures.co/products/dormer/privacy/")!

    /// The record preview's share of the scroll viewport (≤ 0.40, standard §1.23).
    static let previewShare: CGFloat = 0.35
    /// At accessibility sizes the page's title wraps: the preview takes the full 40% cap.
    static let previewShareAccessibility: CGFloat = 0.40

    private var copy: PaywallCopy {
        PaywallCopy.localized(context, year: year, propertyName: propertyName, confirmedHours: confirmedHours)
    }
    private var big: Bool { dts >= .xxLarge }
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    preview
                        .padding(.top, 4)
                    planCard
                        .padding(.top, 16)
                    restoreArea
                        .padding(.top, 4)
                    benefits
                        .id("benefits")
                        .padding(.top, LHMetrics.sectionGap)
                }
                .padding(.horizontal, LHMetrics.gutter)
                .padding(.bottom, LHMetrics.sectionGap)
                .frame(maxWidth: LHMetrics.readingColumn)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .onAppear {
                if startsBelowFold {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        proxy.scrollTo("benefits", anchor: .top)
                    }
                }
            }
        }
        .background(LHCanvas())
        .onAppear {
            Analytics.paywallViewed(context: context)
            Analytics.paywallShown(context: context, entry: entry)
            RatingPromptCoordinator.shared.notePaywallShown()
        }
        .task { await model.start() }
        .task { await loadPage() }
        .onChange(of: subscriptionManager.isPro) { _, isPro in model.entitlementChanged(isPro: isPro) }
        .onChange(of: model.phase) { _, phase in
            if phase == .success {
                successTick += 1
                UIAccessibility.post(notification: .announcement,
                                     argument: String(localized: "Pro is yours", table: "ConversionPath"))
            }
        }
        .sensoryFeedback(.success, trigger: successTick)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall.\(context.rawValue)")
    }

    // MARK: Header (the LHSheet header: 56, title left in the sheet style, one `.icon` close right)

    /// The first line names the thing tapped (the export, the second rental, the record).
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(copy.headline)
                .font(.title2.weight(.semibold))
                .foregroundStyle(colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("paywall.title")
            Button { close() } label: { Image(systemName: "xmark") }
                .buttonStyle(LHButton.icon)
                .accessibilityLabel(String(localized: "Close", table: "ConversionPath"))
                .accessibilityIdentifier("paywall.close")
        }
        .padding(.horizontal, LHMetrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(minHeight: 56)
        .frame(maxWidth: .infinity)
        .background(colors.background)
    }

    // MARK: Record preview (page 1; title = pdf.title)

    /// The page sized to the space: as many entry lines as fit (4, 2, none, then the rentals
    /// alone), so the preview ends on a whole line and is never cut or faded mid-text.
    private var preview: some View {
        Group {
            if let page, !holdsPageLoading {
                let highlight = RecordPageHighlight.forContext(context, propertyName: propertyName)
                ViewThatFits(in: .vertical) {
                    paper(page, highlight, entries: 4)
                    paper(page, highlight, entries: 2)
                    paper(page, highlight, entries: 0)
                    paper(page, highlight, entries: 0, rentals: 1)
                    paper(page, highlight, entries: 0, rentals: 0)
                    paper(page, highlight, entries: 0, rentals: 0, compact: true)
                }
                .transition(.opacity)
            } else {
                DraftingLoader(sketch: .document, surface: .adaptive, subject: String(localized: "your record", table: "ConversionPath"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .containerRelativeFrame(.vertical, alignment: .top) { height, _ in
            (height * (dts.isAccessibilitySize ? Self.previewShareAccessibility : Self.previewShare)).rounded()
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .animation(AppAnimation.reveal, value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(page?.isSample == true
                            ? String(localized: "Sample page from your PDF", table: "ConversionPath")
                            : String(localized: "Page 1 of your PDF record", table: "ConversionPath"))
        .accessibilityIdentifier("paywall.page")
    }

    private func paper(_ page: RecordPageModel, _ highlight: RecordPageHighlight, entries: Int, rentals: Int = 3,
                       compact: Bool = false) -> some View {
        RecordPagePreview(model: page, highlight: highlight, entryLimit: entries, rentalLimit: rentals, fillsHeight: false, compact: compact)
            .clipShape(RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous)
                .strokeBorder(colors.border, lineWidth: LHMetrics.hairline))
    }

    // MARK: Plan card

    /// The plan card holds only the decision: name + tag, the price, one line, the status and the
    /// `.primary`. Restore sits right under it as a `.tertiary` with the legal links (visible
    /// without scrolling); "No subscription" joins the benefit rows, so the card stays compact.
    private var planCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Name and tag on one line when they fit; stacked otherwise (never a mid-word break).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { planName; payOnceTag; Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 6) { planName; payOnceTag }
            }
            priceRow
            Text(copy.planLine)
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .accessibilityIdentifier("paywall.body")
            statusLine
            buyButton
                .padding(.top, 2)
        }
        .padding(LHMetrics.cardPadding)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
        .overlay {
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
                    .strokeBorder(colors.border, lineWidth: LHMetrics.hairline)
            }
        }
    }

    @ViewBuilder private var restoreArea: some View {
        if model.phase != .success && model.phase != .buying {
            Button {
                Task { await model.restore() }
            } label: {
                HStack(spacing: 8) {
                    if model.phase == .restoring { ProgressView().controlSize(.small).tint(colors.action) }
                    Text(model.phase == .restoring
                         ? String(localized: "Checking…", table: "ConversionPath")
                         : String(localized: "Restore purchase", table: "ConversionPath"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(LHButton.tertiary)
            .disabled(!model.canRestore)
            .accessibilityIdentifier("paywall.restore")
        }
        if model.phase == .restoreNone {
            // A restore that errored or timed out says so; "no purchase" only when the App
            // Store answered and found nothing.
            Text(subscriptionManager.restoreFailureMessage ?? String(localized: "No purchase found on this Apple Account.", table: "ConversionPath"))
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("paywall.restoreNone")
        }
        // Terms and Privacy stay visible without scrolling, next to the purchase (App Review).
        legalLinks
            .frame(maxWidth: .infinity)
    }

    private var planName: some View {
        Text(String(localized: "Dormer Pro", table: "ConversionPath"))
            .font(.headline)
            .foregroundStyle(colors.textPrimary)
    }

    private var payOnceTag: some View {
        LHTag(String(localized: "Pay once", table: "ConversionPath"), tone: .action)
    }

    @ViewBuilder private var priceRow: some View {
        switch model.phase {
        case .success:
            Label(String(localized: "Pro is yours", table: "ConversionPath"), systemImage: "checkmark.circle.fill")
                .font(.title.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(colors.textPrimary)
                .labelStyle(PaywallSuccessLabelStyle(tint: colors.positive))
                .transition(.opacity)
                .accessibilityIdentifier("paywall.success")
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
            Label(String(localized: "Couldn’t reach the App Store.", table: "ConversionPath"), systemImage: "exclamationmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(colors.caution)
                .accessibilityIdentifier("paywall.priceFailed")
        case .askToBuy:
            Label(String(localized: "Waiting for approval. Pro unlocks when it comes through.", table: "ConversionPath"), systemImage: "clock")
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .accessibilityIdentifier("paywall.askToBuy")
        default: EmptyView()
        }
    }

    private var buyLabel: String {
        switch model.phase {
        case .priceLoading: return String(localized: "Getting the price", table: "ConversionPath")
        case .priceFailed: return String(localized: "Try again", table: "ConversionPath")
        case .buying: return String(localized: "Waiting for the App Store", table: "ConversionPath")
        case .askToBuy: return String(localized: "Done", table: "ConversionPath")
        case .success: return copy.nextStep
        default: return PaywallCopy.buyTitle(billed: model.priceDisplay?.billed, large: big)
        }
    }

    private var buyButton: some View {
        VStack(spacing: 8) {
            Button {
                switch model.phase {
                case .askToBuy: close()
                case .success: finish()
                case .priceFailed: Task { await model.retryPrice() }
                default: Task { await model.buy() }
                }
            } label: {
                HStack(spacing: 10) {
                    if model.phase == .buying || model.phase == .priceLoading { ProgressView().tint(colors.onAction) }
                    Text(buyLabel)
                        .contentTransition(.opacity)
                }
            }
            .buttonStyle(LHButton.primary)
            // Never drawn disabled (a 40% label fails AA): while the App Store works the button
            // shows a spinner and ignores taps; a failed price load turns it into "Try again".
            .disabled(!(model.canBuy || [.askToBuy, .success, .buying, .priceLoading, .priceFailed].contains(model.phase)))
            .allowsHitTesting(model.phase != .buying && model.phase != .priceLoading)
            .animation(AppAnimation.quick, value: model.phase)
            .accessibilityIdentifier(model.phase == .success ? "paywall.continue" : (model.phase == .priceFailed ? "paywall.retryPrice" : "paywall.buy"))
            if model.phase == .failed {
                Text(model.isFinishingPurchase
                     ? String(localized: "Still finishing your purchase…", table: "ConversionPath")
                     : String(localized: "Couldn’t finish the purchase. Nothing was charged. Try again in a moment.", table: "ConversionPath"))
                    .font(.subheadline)
                    .foregroundStyle(colors.caution)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("paywall.failed")
            }
        }
    }

    private var legalLinks: some View {
        // Each link stays on one line; at large sizes they stack instead of breaking.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { termsLink; Text(verbatim: "·").accessibilityHidden(true); privacyLink }
            VStack(alignment: .center, spacing: 0) { termsLink; privacyLink }
        }
        .font(.footnote)
        .foregroundStyle(colors.textSecondary)
    }

    private var termsLink: some View {
        Button { openURL(Self.termsURL) } label: {
            Text(String(localized: "Terms\u{00A0}of\u{00A0}Use", table: "ConversionPath")).lineLimit(1).layoutPriority(1)
        }
        .buttonStyle(LHButton.press)
        .frame(minHeight: LHMetrics.minTap)
        .accessibilityIdentifier("paywall.terms")
    }

    private var privacyLink: some View {
        Button { openURL(Self.privacyURL) } label: {
            Text(String(localized: "Privacy\u{00A0}Policy", table: "ConversionPath")).lineLimit(1).layoutPriority(1)
        }
        .buttonStyle(LHButton.press)
        .frame(minHeight: LHMetrics.minTap)
        .accessibilityIdentifier("paywall.privacy")
    }

    // MARK: What you get

    /// The four rows, one meta line each (short enough to stay on one line at XXL).
    static var benefitRows: [(symbol: String, title: String, meta: String)] {
        [("house", String(localized: "Every rental", table: "ConversionPath"), String(localized: "Free covers one", table: "ConversionPath")),
         ("doc.richtext", String(localized: "PDF and spreadsheet", table: "ConversionPath"), String(localized: "Ready for your CPA", table: "ConversionPath")),
         ("calendar.badge.checkmark", String(localized: "Where each hour came from", table: "ConversionPath"), String(localized: "On every line", table: "ConversionPath")),
         ("arrow.clockwise", String(localized: "On every device", table: "ConversionPath"), String(localized: "Restore when you switch", table: "ConversionPath"))]
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            LHSectionHeader(String(localized: "What you get", table: "ConversionPath"))
                .accessibilityAddTraits(.isHeader)
            LHRowGroup {
                ForEach(Array(Self.benefitRows.enumerated()), id: \.offset) { i, item in
                    if i > 0 { LHDivider(leadingInset: LHRow.browseDividerInset) }
                    LHRow.Browse(title: item.title, meta: item.meta, systemImage: item.symbol, showsChevron: false)
                }
                LHDivider(leadingInset: LHRow.browseDividerInset)
                LHRow.Browse(title: String(localized: "No subscription", table: "ConversionPath"),
                             meta: String(localized: "Pay once, keep it", table: "ConversionPath"),
                             systemImage: "infinity", showsChevron: false)
                if model.familyShareable {
                    LHDivider(leadingInset: LHRow.browseDividerInset)
                    LHRow.Browse(title: String(localized: "Family Sharing", table: "ConversionPath"),
                                 meta: String(localized: "Share it with your family", table: "ConversionPath"),
                                 systemImage: "person.2", showsChevron: false)
                }
            }
        }
        .accessibilityIdentifier("paywall.benefits")
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
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                continuation()
            }
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
}

/// "$29.99 one payment, no subscription" on one baseline; stacked when it doesn't fit. The billed amount is
/// `.largeTitle.rounded.bold`, the largest price text on the page (App Review, `PriceDisplay`).
struct PaywallPriceRow: View {
    let display: PriceDisplay
    let colors: AdaptiveColors

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
            .font(.largeTitle.weight(.bold))
            .fontDesign(.rounded)
            .monospacedDigit()
            .foregroundStyle(colors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var caption: some View {
        Text(String(localized: "one payment, no subscription", table: "ConversionPath"))
            .font(.subheadline)
            .foregroundStyle(colors.textSecondary)
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

// MARK: - The paywall's words, from the package catalog

extension PaywallCopy {
    /// The headline, plan line and success step the paywall shows, localized in
    /// `ConversionPath.xcstrings`. Standard C.4: "your CPA" (the word "accountant" is the PDF's
    /// only). `ProGate`'s `make` is the unlocalized original this replaces on screen.
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
        }
    }

    /// The buy button: "Unlock for $29.99" with the App Store's localized price; at large text
    /// sizes, or before the price arrives, "Unlock".
    static func buyTitle(billed: String?, large: Bool) -> String {
        guard let billed, !large else { return String(localized: "Unlock", table: "ConversionPath") }
        return String(localized: "Unlock for \(billed)", table: "ConversionPath")
    }
}
