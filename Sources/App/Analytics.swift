import Foundation
import PostHog

/// Thin, single choke-point wrapper around the PostHog iOS SDK for LandlordHours. Every event this
/// app ever sends goes through here, so gating (tests, QA/preview runs, DEBUG builds, user opt-out)
/// lives in one place and call sites never need to know whether analytics is actually running.
/// Modeled on the LensWords / Bee Buddy `Analytics.swift` pattern (same single-choke-point shape,
/// same PostHog host), adapted to this app's `-LH*` launch-argument fixture convention.
///
/// Privacy posture (v1, conservative by design — general-audience REPS tax-tracking app, no kids,
/// no financial account data touched by analytics): no session replay, no autocapture (screen views
/// / element interactions), small anonymous snake_case property sets only — never a property name,
/// address, note, or attachment.
///
/// Gating rules (see `shouldConfigure`):
/// - never during unit/UI tests (`XCTestConfigurationFilePath` present in the process environment),
/// - never when any `-LH*` launch argument is present — this app's UI tests, mock-scenario seeding,
///   and screenshot capture all drive the app via `-LHMockScenario`, `-LHInitialTab`,
///   `-LHOpenLearningCenter`, etc., and none of those runs should pollute production data,
/// - never in DEBUG builds — unless `-LHAnalyticsForce` is passed, which force-enables analytics in
///   the simulator (even under a `-LH*` launch) so event flow can be verified without polluting a
///   real QA capture run.
enum Analytics {
    /// Persisted user opt-out, surfaced as the "Share Anonymous Usage Data" toggle in Settings → Privacy.
    static let optOutKey = "landlordHoursAnalyticsOptOut"

    /// Written exactly once, on the main thread, from the app-launch path before any capture call
    /// can run; read-only afterwards. PostHogSDK is itself thread-safe, so this flag needs no
    /// further synchronization.
    private(set) nonisolated(unsafe) static var isConfigured = false

    #if DEBUG
    private static let isDebugBuild = true
    #else
    private static let isDebugBuild = false
    #endif

    /// The single opt-in escape hatch for the blanket QA gate below: forces analytics on (even in
    /// DEBUG, even under a `-LH*` launch) so event flow can be verified in the simulator. Every
    /// OTHER `-LH*` fixture flag keeps analytics off.
    static let forceFlag = "-LHAnalyticsForce"

    /// Pure gating decision, extracted for unit tests.
    static func shouldConfigure(
        arguments: [String],
        environment: [String: String],
        isDebugBuild: Bool
    ) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil { return false }
        let forced = arguments.contains(forceFlag)
        let qaOrDebugArgs = arguments.contains { argument in
            argument != forceFlag && argument.hasPrefix("-LH")
        }
        if !forced && qaOrDebugArgs { return false }
        if isDebugBuild && !forced { return false }
        return true
    }

    /// Pure send decision, extracted for unit tests: capture is a no-op when analytics never
    /// configured or the user opted out.
    static func shouldSend(configured: Bool, optedOut: Bool) -> Bool {
        configured && !optedOut
    }

    /// Sets up PostHog unless gated off. Call once from the app-launch path.
    static func configure() {
        let info = ProcessInfo.processInfo
        guard shouldConfigure(
            arguments: info.arguments,
            environment: info.environment,
            isDebugBuild: isDebugBuild
        ) else { return }
        guard !isConfigured else { return }

        // Verbose SDK logging only on forced verification runs, so event flow is visible in the
        // simulator console.
        let forcedForQA = info.arguments.contains(forceFlag)

        let config = PostHogConfig(
            apiKey: "phc_rwe5Z7ZJh6MDaATHMgk4gtuCcLrZc7wNUhLvdKqMY5eJ",
            host: "https://us.i.posthog.com"
        )
        // v1 privacy posture: no session replay, no autocapture (screen views / element
        // interactions) — only the explicit named events below, plus PostHog's own default
        // app-lifecycle events, ever get sent.
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.captureApplicationLifecycleEvents = true
        config.sessionReplay = false
        // Offline-friendly app (entries can be logged with no connectivity): keep a deep queue so
        // events survive stretches without a network.
        config.maxQueueSize = 3000
        config.debug = forcedForQA
        PostHogSDK.shared.setup(config)
        isConfigured = true

        if UserDefaults.standard.bool(forKey: optOutKey) {
            PostHogSDK.shared.optOut()
        }
    }

    /// Applies the user's sharing choice. Persistence is owned by whatever Settings toggle calls
    /// this; the function only informs the SDK.
    static func setOptOut(_ optedOut: Bool) {
        guard isConfigured else { return }
        if optedOut {
            PostHogSDK.shared.optOut()
        } else {
            PostHogSDK.shared.optIn()
        }
    }

    /// Current opt-out status, read straight from `UserDefaults` so SwiftUI (e.g. `@AppStorage`)
    /// and this type always agree on the source of truth. `false` (shared) is the default for a
    /// user who has never touched the Settings toggle.
    static var isOptedOut: Bool {
        UserDefaults.standard.bool(forKey: optOutKey)
    }

    /// Captures an event. No-op when analytics never configured or opted out. Kept private — call
    /// sites use the typed helpers below so the event taxonomy stays centralized and reviewable in
    /// one place.
    private static func capture(_ event: String, properties: [String: Any]? = nil) {
        #if DEBUG
        // Unit-test seam: a spy sees exactly what would be sent, and nothing reaches PostHog.
        if let spy = testSpy {
            spy(event, properties ?? [:])
            return
        }
        #endif
        guard shouldSend(
            configured: isConfigured,
            optedOut: UserDefaults.standard.bool(forKey: optOutKey)
        ) else { return }
        PostHogSDK.shared.capture(event, properties: properties)
    }

    #if DEBUG
    /// Set by unit tests to observe events. DEBUG only; never set in app code.
    nonisolated(unsafe) static var testSpy: ((String, [String: Any]) -> Void)?
    #endif

    // MARK: - Named events (v1 minimal taxonomy)

    /// The app finished launching into the foreground. Call once per cold/warm launch from the
    /// app-launch path (not from a view's `onAppear`, which can re-fire on navigation).
    static func appOpened() {
        capture("app_opened")
    }

    /// An hours entry was created (a REPS/material-participation session logged against a
    /// property). `category` is the activity category's stable snake_case key (never the raw
    /// display string, which reads like "Repairs & Maintenance"); `participant` is "self" or
    /// "spouse", never a name.
    static func sessionLogged(category: ActivityCategory, participant: Participant) {
        capture("session_logged", properties: [
            "category": category.analyticsKey,
            "participant": participant.analyticsKey
        ])
    }

    /// A rental property was added.
    static func propertyAdded() {
        capture("property_added")
    }

    /// The Reports tab/screen was viewed.
    static func reportViewed() {
        capture("report_viewed")
    }

    // MARK: - 1.1 funnel events
    // Properties are fixed enums only: no names, notes, emails or free text, ever.

    /// Any hours entry was saved. `source` is how it was made: manual, timer, voice or calendar.
    static func entryLogged(source: EntrySource) {
        capture("entry_logged", properties: ["source": source.rawValue])
    }

    /// The user finished sharing an export (the share sheet reported completion, not cancel).
    static func exportShared(format: ExportFormat) {
        capture("export_shared", properties: ["format": format.analyticsKey])
    }

    /// The paywall appeared. `context` is what the user tapped to get there.
    static func paywallViewed(context: PaywallContext) {
        capture("paywall_viewed", properties: ["context": context.rawValue])
    }

    /// A Pro purchase went through from the paywall opened in `context`.
    static func purchaseCompleted(context: PaywallContext) {
        capture("purchase_completed", properties: ["context": context.rawValue])
    }

    /// Restore found and re-applied an earlier Pro purchase.
    static func purchaseRestored() {
        capture("purchase_restored")
    }

    /// The first-run onboarding flow finished.
    static func onboardingCompleted() {
        capture("onboarding_completed")
    }

    enum ProfileKind: String {
        case apple
        case local
    }

    /// A new profile was created: with Sign in with Apple, or on this device only.
    static func profileCreated(kind: ProfileKind) {
        capture("profile_created", properties: ["kind": kind.rawValue])
    }

    /// We asked iOS to show its rating prompt. iOS decides whether it actually appears.
    static func ratingPromptRequested(trigger: RatingPromptTrigger) {
        capture("rating_prompt_requested", properties: ["trigger": trigger.rawValue])
    }
}

extension ExportFormat {
    /// Stable analytics value: "pdf" or "csv".
    var analyticsKey: String {
        switch self {
        case .pdf: return "pdf"
        case .csv: return "csv"
        }
    }
}

/// Stable, machine-readable analytics key for an activity category. Kept here (rather than on
/// `ActivityCategory` itself in Models.swift) so the analytics taxonomy lives in one file;
/// `ActivityCategory.rawValue` stays the user-facing display string ("Repairs & Maintenance") and
/// is never sent to analytics.
extension ActivityCategory {
    var analyticsKey: String {
        switch self {
        case .repairs: return "repairs"
        case .management: return "management"
        case .leasing: return "leasing"
        case .bookkeeping: return "bookkeeping"
        case .legal: return "legal"
        case .insurance: return "insurance"
        case .travel: return "travel"
        case .renovations: return "renovations"
        case .investing: return "investing"
        case .financing: return "financing"
        case .contractNegotiation: return "contract_negotiation"
        }
    }
}

/// Stable, machine-readable analytics key for a participant. Never a name — just "self"/"spouse".
extension Participant {
    var analyticsKey: String {
        switch self {
        case .selfParticipant: return "self"
        case .spouse: return "spouse"
        }
    }
}
