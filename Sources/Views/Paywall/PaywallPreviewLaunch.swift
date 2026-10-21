import SwiftUI

#if DEBUG
/// DEBUG-only launch hook for captures and UI tests: opens the paywall in any state.
///
/// `-LHPaywallPreview <export|secondProperty|todayUnlock|settings>`
/// `-LHPaywallPhase <PaywallPhase raw value>` pins a state (buying, askToBuy, failed, success…).
/// `-LHPaywallSample`, `-LHPaywallPageLoading`, `-LHPaywallBelowFold`,
/// `-LHPaywallProperty "<name>"`, `-LHPaywallHours <n>`.
/// The price still comes from StoreKit (the local configuration in Debug), never a literal.
struct PaywallPreviewLaunch: Equatable {
    var context: PaywallContext
    var phase: PaywallPhase?
    var sample: Bool
    var pageLoading: Bool
    var belowFold: Bool
    var propertyName: String?
    var hours: Double?

    static let current: PaywallPreviewLaunch? = parse(ProcessInfo.processInfo.arguments)

    static func parse(_ args: [String]) -> PaywallPreviewLaunch? {
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        guard let raw = value("-LHPaywallPreview") else { return nil }
        let context = PaywallContext.allCases.first { $0.rawValue == raw || "\($0)" == raw } ?? .export
        return PaywallPreviewLaunch(
            context: context,
            phase: value("-LHPaywallPhase").flatMap(PaywallPhase.init(rawValue:)),
            sample: args.contains("-LHPaywallSample"),
            pageLoading: args.contains("-LHPaywallPageLoading"),
            belowFold: args.contains("-LHPaywallBelowFold"),
            propertyName: value("-LHPaywallProperty"),
            hours: value("-LHPaywallHours").flatMap(Double.init))
    }
}

struct PaywallPreviewRoot: View {
    let launch: PaywallPreviewLaunch
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var ready = false

    var body: some View {
        Group {
            if ready {
                PaywallView(
                    context: launch.context,
                    propertyName: launch.propertyName,
                    confirmedHours: launch.hours,
                    pinnedPhase: launch.phase,
                    startsBelowFold: launch.belowFold,
                    holdsPageLoading: launch.pageLoading,
                    forcesSample: launch.sample,
                    onClose: {}
                )
            } else {
                Color.clear
            }
        }
        .task {
            // Pinned states need the real price first (the price-loading state needs none).
            if launch.phase != .priceLoading && launch.phase != .priceFailed && subscriptionManager.proProduct == nil {
                await subscriptionManager.loadProducts()
            }
            ready = true
        }
    }
}
#endif
