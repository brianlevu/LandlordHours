import Foundation

// MARK: - Paywall context

/// Where the one paywall was opened from. The headline and body speak to the thing tapped,
/// and after a purchase the caller continues that action (open the export, add the property).
enum PaywallContext: String, CaseIterable, Identifiable {
    /// Reports export button, or Settings › Export Reports.
    case export
    /// Adding a second property (the free plan covers one).
    case secondProperty
    /// The "Unlock Pro" nudge on Home.
    case dashboardUnlock
    /// The Pro card at the top of Settings.
    case settingsUpgrade

    var id: String { rawValue }

    func title(year: Int) -> String {
        switch self {
        case .export: return "Export your \(String(year)) record"
        case .secondProperty: return "Track every rental"
        case .dashboardUnlock: return "Export and track every rental"
        case .settingsUpgrade: return "Get LandlordHours Pro"
        }
    }

    var body: String {
        switch self {
        case .export:
            return "Turn the hours you logged into a PDF or CSV you can hand to your tax professional."
        case .secondProperty:
            return "The free plan covers one property. Pro lets you add every rental you own, each with its own hours."
        case .dashboardUnlock:
            return "Pro adds a PDF and CSV of your hours for tax time, and room for every rental you own. You pay once."
        case .settingsUpgrade:
            return "Export your records and track every rental you own. Pay once, keep it."
        }
    }

    /// What Pro gives, ordered so the thing tapped comes first.
    var benefits: [PaywallBenefit] {
        switch self {
        case .export:
            return [.exports, .byYear, .properties]
        case .secondProperty:
            return [.properties, .separateHours, .exports]
        case .dashboardUnlock, .settingsUpgrade:
            return [.exports, .properties, .restore]
        }
    }

    /// Button that continues the user's action after purchase, if there is one.
    var continueLabel: String {
        switch self {
        case .export: return "Continue to export"
        case .secondProperty: return "Add your property"
        case .dashboardUnlock, .settingsUpgrade: return "Done"
        }
    }
}

enum PaywallBenefit: String, CaseIterable {
    case exports
    case byYear
    case properties
    case separateHours
    case restore

    var title: String {
        switch self {
        case .exports: return "PDF and CSV exports"
        case .byYear: return "One record per tax year"
        case .properties: return "Unlimited properties"
        case .separateHours: return "Hours kept per rental"
        case .restore: return "Yours on every device"
        }
    }

    var detail: String {
        switch self {
        case .exports: return "Hours by property, category and person, ready to share."
        case .byYear: return "Totals, entries and the tests you track, on a clean page."
        case .properties: return "Add every rental you own. The free plan covers one."
        case .separateHours: return "Each property keeps its own log and totals."
        case .restore: return "Restore Pro from the App Store when you change phones."
        }
    }
}

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
