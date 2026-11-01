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

/// DEBUG-only launch hooks for the 2.3 plan states (captures and UI tests). Applied once, from
/// the shell's `PlanMomentsHost`, before Today reads the data.
///
/// `-LHPlanSeed d23`                Pine Cabin 420h and Oak Street Duplex 46h this year, the 750h goal
///                                  (the hi-fi frames' data); Pine Cabin logged 1.5h today.
/// `-LHPlanLastKind trial|pro`      how Pro ended (the pick sheet's first line).
/// `-LHFreeRentalPick <name>`       the free rental, picked `-LHFreeRentalPickedDaysAgo <n>` days ago (default 1).
/// `-LHPlanMoment day12|pickFree`   show that sheet on Today (day 12: renewal in 2 days).
/// `-LHTrialStartPreview`           with `-LHPaywallPreview`: the trial-start moment instead of the paywall.
@MainActor
enum PricingDebugLaunch {
    private static var didApply = false
    private static var didForce = false
    private static var args: [String] { ProcessInfo.processInfo.arguments }

    static func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    static func applyIfNeeded(app: AppViewModel) {
        guard !didApply else { return }
        didApply = true
        if value("-LHPlanSeed") == "d23" { seedD23(app) }
        if let kind = value("-LHPlanLastKind") {
            UserDefaults.standard.set(kind, forKey: UserScope.key(PlanMomentsHost.lastPlanKey))
        }
        if let name = value("-LHFreeRentalPick"), let rental = app.properties.first(where: { $0.name == name }) {
            let days = value("-LHFreeRentalPickedDaysAgo").flatMap(Double.init) ?? 1
            let chosenAt = Date().addingTimeInterval(-days * 86_400)
            EntitlementFreeRentalLocal().adopt(FreeRentalSelection(rentalID: rental.id, chosenAt: chosenAt, source: .picked))
        }
    }

    /// The sheet a capture asks for, once.
    static func forcedMoment() -> PlanMoment? {
        guard !didForce, let raw = value("-LHPlanMoment") else { return nil }
        didForce = true
        switch raw {
        case "day12":
            let renewal = Calendar.current.date(byAdding: .day, value: TrialSchedule.reminderLeadDays,
                                                to: Calendar.current.startOfDay(for: Date())) ?? Date()
            return .day12(renewal: renewal, originalTransactionID: 0)
        case "pickFree":
            return .pickFree(.trialEnded)
        default:
            return nil
        }
    }

    private static func seedD23(_ app: AppViewModel) {
        GoalManager.shared.setGoalChoice(.reps750)
        let plan: [(String, Double)] = [("Pine Cabin", 420), ("Oak Street Duplex", 46)]
        let wasSuppressed = app.suppressCelebrations
        app.suppressCelebrations = true
        defer { app.suppressCelebrations = wasSuppressed }
        let rentals = plan.map { item in
            app.properties.first { $0.name == item.0 } ?? RentalProperty(name: item.0, address: "", propertyType: .ltr)
        }
        app.properties = rentals
        app.timeEntries = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let year = calendar.component(.year, from: today)
        let kinds: [ActivityCategory] = [.repairs, .management, .leasing, .bookkeeping]
        for (i, rental) in rentals.enumerated() {
            var remaining = plan[i].1
            if i == 0, let at = calendar.date(byAdding: .hour, value: 9, to: today) {
                app.timeEntries.append(TimeEntry(propertyId: rental.id, participant: .selfParticipant, category: .repairs,
                                                 hours: 1.5, date: at, notes: ""))
                remaining -= 1.5
            }
            var daysBack = 2
            while remaining > 0.0001 {
                let hours = min(8, remaining)
                guard let day = calendar.date(byAdding: .day, value: -daysBack, to: today),
                      calendar.component(.year, from: day) == year,
                      let at = calendar.date(byAdding: .hour, value: 10, to: day) else { break }
                app.timeEntries.append(TimeEntry(propertyId: rental.id, participant: .selfParticipant,
                                                 category: kinds[daysBack % kinds.count], hours: hours, date: at, notes: ""))
                remaining -= hours
                daysBack += 1
            }
        }
        app.saveData()
    }
}

struct PaywallPreviewRoot: View {
    let launch: PaywallPreviewLaunch

    /// `-LHPaywallOffer subscribe` pins the no-trial offer (the trial already used);
    /// `founding` / `foundingSubscribed` pin the owned page of a founding buyer.
    private var pinnedOffer: PaywallOffer? {
        switch PricingDebugLaunch.value("-LHPaywallOffer") {
        case "subscribe"?: return .subscribe
        case "founding"?, "foundingSubscribed"?: return .owned
        default: return nil
        }
    }

    private var pinnedPlan: Plan? {
        switch PricingDebugLaunch.value("-LHPaywallOffer") {
        case "founding"?: return .founding(alsoSubscribed: false)
        case "foundingSubscribed"?: return .founding(alsoSubscribed: true)
        default: return nil
        }
    }
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var ready = false

    var body: some View {
        Group {
            if ready && ProcessInfo.processInfo.arguments.contains("-LHTrialStartPreview") {
                TrialStartView(renewal: Calendar.current.date(byAdding: .day, value: TrialSchedule.defaultTrialDays,
                                                              to: PaywallClock.now()) ?? Date(),
                               price: subscriptionManager.proDisplayPrice,
                               onAddRentals: {}, onMakePDF: {}, onDone: {})
            } else if ready {
                PaywallView(
                    context: launch.context,
                    propertyName: launch.propertyName,
                    confirmedHours: launch.hours,
                    pinnedPhase: launch.phase,
                    pinnedOffer: pinnedOffer,
                    pinnedPlan: pinnedPlan,
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
