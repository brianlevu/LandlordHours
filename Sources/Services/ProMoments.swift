import Foundation

// PaywallContext and the paywall copy live in ProGate.swift (WP-P).

// MARK: - Rating prompt

enum RatingPromptTrigger: String {
    /// The user finished sharing their first export.
    case exportShared = "export_shared"
    /// The user logged their tenth entry (or more).
    case entriesMilestone = "entries_milestone"
}

/// Pure guard logic for Apple's rating prompt. No custom stars, no pre-prompt: when this
/// says yes, we call the system `requestReview` and iOS decides whether to show it.
struct RatingPromptPolicy {
    static let minimumDaysSinceInstall = 7
    static let minimumEntries = 10

    struct State: Equatable {
        var now: Date
        var installDate: Date?
        var entryCount: Int
        var sessionShowedPaywall: Bool
        var sessionHadError: Bool
        var lastRequestedVersion: String?
        var currentVersion: String
        /// True once an export has been shared before (so only the FIRST shared export triggers).
        var hasSharedExportBefore: Bool
    }

    static func shouldRequest(trigger: RatingPromptTrigger, state: State) -> Bool {
        if trigger == .exportShared && state.hasSharedExportBefore { return false }
        guard let installDate = state.installDate else { return false }
        let days = state.now.timeIntervalSince(installDate) / 86_400
        guard days >= Double(minimumDaysSinceInstall) else { return false }
        guard state.entryCount >= minimumEntries else { return false }
        guard !state.sessionShowedPaywall, !state.sessionHadError else { return false }
        guard state.lastRequestedVersion != state.currentVersion else { return false }
        return true
    }
}

/// Holds the rating prompt's persistent and per-session state, and decides when to ask.
/// The view layer watches `pendingRequest` and calls SwiftUI's `requestReview`.
final class RatingPromptCoordinator: ObservableObject {
    static let shared = RatingPromptCoordinator()

    static let installDateKey = "LandlordHours.rating.installDate"
    static let lastRequestedVersionKey = "LandlordHours.rating.lastRequestedVersion"
    static let sharedExportKey = "LandlordHours.rating.hasSharedExport"

    /// Set when the policy says yes; the view consumes it and clears it.
    @Published var pendingRequest: RatingPromptTrigger?

    private(set) var sessionShowedPaywall = false
    private(set) var sessionHadError = false

    private let defaults: UserDefaults
    private let now: () -> Date
    private let currentVersion: String
    private let isEnabled: Bool

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
        isEnabled: Bool = RatingPromptCoordinator.defaultEnabled
    ) {
        self.defaults = defaults
        self.now = now
        self.currentVersion = currentVersion
        self.isEnabled = isEnabled
    }

    /// Off under XCTest and any `-LH*` QA launch, so test runs never trigger the system prompt.
    static var defaultEnabled: Bool {
        let info = ProcessInfo.processInfo
        if info.environment["XCTestConfigurationFilePath"] != nil { return false }
        return !info.arguments.contains { $0.hasPrefix("-LH") }
    }

    /// Call once per launch. The first launch with this code is treated as the install date.
    func recordLaunch() {
        if defaults.object(forKey: Self.installDateKey) == nil {
            defaults.set(now(), forKey: Self.installDateKey)
        }
    }

    func notePaywallShown() { sessionShowedPaywall = true }
    func noteError() { sessionHadError = true }

    /// Resets per-session flags (a fresh process starts clean; exposed for tests).
    func resetSession() {
        sessionShowedPaywall = false
        sessionHadError = false
        pendingRequest = nil
    }

    func state() -> RatingPromptPolicy.State {
        RatingPromptPolicy.State(
            now: now(),
            installDate: defaults.object(forKey: Self.installDateKey) as? Date,
            entryCount: 0,
            sessionShowedPaywall: sessionShowedPaywall,
            sessionHadError: sessionHadError,
            lastRequestedVersion: defaults.string(forKey: Self.lastRequestedVersionKey),
            currentVersion: currentVersion,
            hasSharedExportBefore: defaults.bool(forKey: Self.sharedExportKey)
        )
    }

    /// Evaluates the trigger. Returns true when a request was queued for the view to show.
    @discardableResult
    func consider(_ trigger: RatingPromptTrigger, entryCount: Int) -> Bool {
        var current = state()
        current.entryCount = entryCount
        if trigger == .exportShared {
            // Only the first shared export ever counts, whether or not the guards pass now.
            defaults.set(true, forKey: Self.sharedExportKey)
        }
        guard isEnabled, RatingPromptPolicy.shouldRequest(trigger: trigger, state: current) else { return false }
        defaults.set(currentVersion, forKey: Self.lastRequestedVersionKey)
        pendingRequest = trigger
        Analytics.ratingPromptRequested(trigger: trigger)
        return true
    }
}
