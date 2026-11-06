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

/// DEBUG-only launch hook for captures of a restore that fails.
///
/// `-LHRestoreOutcome timeout` makes the App Store sync hang, so the restore deadline (cut to
/// 1 s) ends it; `-LHRestoreOutcome failure` makes the sync fail as if offline. Installed at
/// launch (LandlordHoursApp.init). Only the App Store call is replaced; the restore path, the
/// paywall and Settings run as shipped, and Restore is tapped for real (PaywallCaptureUITests).
enum RestoreFailureLaunch {
    enum Outcome: String { case timeout, failure }

    static var outcome: Outcome? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LHRestoreOutcome"), i + 1 < args.count else { return nil }
        return Outcome(rawValue: args[i + 1])
    }

    @MainActor
    static func prepare(_ manager: SubscriptionManager = .shared) {
        switch outcome {
        case .timeout?:
            SubscriptionManager.restoreSyncTimeout = 1
            manager.syncWithAppStore = { try await Task.sleep(nanoseconds: 3_600_000_000_000) }
        case .failure?:
            manager.syncWithAppStore = { throw URLError(.notConnectedToInternet) }
        case nil:
            break
        }
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
