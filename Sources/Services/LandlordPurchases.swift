import Foundation
import RevenueCat

/// RevenueCat SDK integration — ANALYTICS/OBSERVER MODE ONLY (2026-08-26 scope decision; mirrors
/// the LensWords pattern in `RevenueCatObserver.swift` / the Bee Buddy pattern in
/// `BeeBuddyPurchases.swift` essentially verbatim, adapted to LandlordHours' naming and its
/// `-LH*` launch-argument fixture convention).
///
/// `SubscriptionManager`'s existing StoreKit 2 purchase path (`purchasePro()`, `restorePurchases()`,
/// `refreshEntitlements()`, the `Transaction.updates` listener) stays EXACTLY as it is today — this
/// file does not touch it. RevenueCat is wired here purely so its dashboards can observe
/// transactions for the future: it is configured with `purchasesAreCompletedBy: .myApp`, which
/// means RC never calls `transaction.finish()` and never owns entitlement state.
/// `SubscriptionManager` keeps doing both, unchanged — `isPro`, `hasPurchased`, `purchasePro()`,
/// and `restorePurchases()` all continue to read/write ONLY from StoreKit 2, never from RevenueCat.
///
/// ============================================================
/// TWO INDEPENDENT GATES (mirrors `Analytics.swift`'s PostHog gating; read that file's header
/// first if this is your first time here)
/// ============================================================
///  1. `isEnabled` — a single hardcoded bool.
///  2. A real (non-empty, non-placeholder) API key in Info.plist's `RevenueCatAPIKey`, itself
///     backed by the `REVENUECAT_API_KEY` build setting in `project.yml` (target `LandlordHours`).
///
/// Today's key is RevenueCat's real production `appl_` public SDK key (activated 2026-08-26, both
/// Debug and Release — observer mode just records whatever StoreKit transactions the app actually
/// makes, and RC itself segregates Debug/sandbox purchases from production ones in its dashboard).
/// The placeholder guard stays in place regardless: if `REVENUECAT_API_KEY` in `project.yml` (or
/// the `RevenueCatAPIKey` Info.plist entry it feeds) is ever missing, blank, or reverted to
/// `REPLACE_WITH_REVENUECAT_PUBLIC_SDK_KEY`, `shouldConfigure` gate #2 keeps the whole integration
/// a total no-op — no network call, no SDK initialization, no crash.
///
/// On top of those two, `shouldConfigure` ALSO refuses to configure:
///  - under XCTest (`XCTestConfigurationFilePath`), unless the narrow
///    `testHarnessLiveOverrideKey` env-var override is set (mirrors
///    `RevenueCatObserver.testHarnessLiveOverrideKey` from LensWords — reserved for a future
///    live-purchase-observation harness test; no such test exists yet in this app),
///  - under any `-LH*` launch argument — mirrors `Analytics.shouldConfigure`'s exact QA/mock-
///    scenario gate (`Analytics.swift`). This app's UI tests, mock-scenario seeding
///    (`-LHMockScenario`, the same flag `SubscriptionManager.shouldSkipStoreKitRefreshForDebugLaunch`
///    checks to skip its own StoreKit refresh on a debug/mock launch), and screenshot capture all
///    drive the app via `-LH*` arguments, and none of those runs should phone home to
///    api.revenuecat.com either,
///  - when the user has opted out of usage sharing (`Analytics.optOutKey` — the "Share Anonymous
///    Usage Data" toggle in Settings → Privacy). A user who opted out of usage sharing should not
///    have RevenueCat observing their purchase history either.
///
/// RELEASE-BUILD SAFETY (belt-and-suspenders, mirrors `BeeBuddyPurchases.normalizedAPIKey`):
/// RevenueCat's own SDK calls `fatalError()` if a Test Store (`test_`-prefixed) key ever reaches
/// `Configuration.Builder` in a non-DEBUG build — intentional upstream behavior meant to block Test
/// Store keys from reaching App Review (purchases-ios-spm `Sources/Purchasing/Configuration.swift`).
/// `normalizedAPIKey` refuses any `test_`-prefixed key when `isDebugBuild == false`, regardless of
/// what the build setting says, so a future dashboard swap that temporarily introduces a Test Store
/// key into a misconfigured Release build no-ops gracefully instead of crashing seconds after
/// launch.
///
/// Anonymous app user IDs ONLY: `Purchases.configure` here is never given an explicit `appUserID`,
/// so RC generates and persists its own anonymous ID; `logIn`/`logOut`/`alias`/attribution APIs are
/// never called anywhere in this app. No custom subscriber attributes are ever set.
enum LandlordPurchases {
    /// The single feature-gate bool. `false` would ship the integration completely dark — no
    /// network calls, no SDK initialization — regardless of whether a key is present.
    static let isEnabled = true

    /// The literal placeholder written by `project.yml` before Brian pastes a real key. Treated
    /// identically to an empty/missing key: both mean "not configured yet," never a crash or a
    /// silently-broken RC session.
    static let placeholderAPIKey = "REPLACE_WITH_REVENUECAT_PUBLIC_SDK_KEY"

    /// Compile-time build flavor, mirroring `Analytics.isDebugBuild` (Analytics.swift). Threaded as
    /// an injectable parameter everywhere below so the "reject Test Store keys outside DEBUG" rule
    /// stays a pure, unit-testable function rather than a `#if DEBUG` buried inside the check
    /// itself.
    #if DEBUG
    static let isDebugBuild = true
    #else
    static let isDebugBuild = false
    #endif

    /// Narrow escape hatch, mirroring `RevenueCatObserver.testHarnessLiveOverrideKey` (LensWords):
    /// reserved for a future test that deliberately drives RC while under XCTest. Every ordinary
    /// unit/UI test run stays gated off `api.revenuecat.com` by the XCTest check in
    /// `shouldConfigure` regardless of this key's absence; only setting it to `"1"` in the process
    /// environment opens the gate.
    static let testHarnessLiveOverrideKey = "LANDLORDHOURS_TEST_RC_LIVE"

    /// Compile-time: dev simulators mint a fresh RC anonymous "customer" on every run,
    /// polluting production analytics (86 fake LensWords customers, 2026-08).
    /// TestFlight/device/App Store builds are unaffected.
    static let isSimulatorBuild: Bool = {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }()

    /// Set exactly once, the first (and only) time `configure()` actually reaches
    /// `Purchases.configure(with:)`. Guards the SDK call itself against being invoked twice in one
    /// process. Resets to `false` on every fresh process launch (a plain static, not persisted), so
    /// production/TestFlight/App Store behavior is unchanged: still exactly one real configure per
    /// app launch.
    private(set) nonisolated(unsafe) static var hasConfigured = false

    /// Pure normalization, extracted for unit tests (no `Bundle` involved): a raw Info.plist string
    /// becomes `nil` — "no key" — when absent, whitespace-only, still the shipped placeholder, OR
    /// (outside DEBUG) a RevenueCat Test Store key (`test_`-prefixed) — RC's own SDK
    /// `fatalError()`s on those in non-DEBUG builds (see this file's header, "RELEASE-BUILD
    /// SAFETY"). `isDebugBuild` is injected (default: the real compile-time flavor) purely so this
    /// stays testable without needing two separately-compiled test binaries.
    static func normalizedAPIKey(_ raw: String?, isDebugBuild: Bool = LandlordPurchases.isDebugBuild) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != placeholderAPIKey else { return nil }
        guard isDebugBuild || !trimmed.hasPrefix("test_") else { return nil }
        return trimmed
    }

    /// Reads the API key from Info.plist. Returns `nil` when the key is absent, empty, still the
    /// shipped placeholder, or (outside DEBUG) a Test Store key — see `normalizedAPIKey`.
    static func apiKey(bundle: Bundle = .main, isDebugBuild: Bool = LandlordPurchases.isDebugBuild) -> String? {
        normalizedAPIKey(bundle.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String, isDebugBuild: isDebugBuild)
    }

    /// Pure gating decision, extracted for unit tests: configure only when BOTH the feature is
    /// enabled and a real key is present, AND (mirroring `Analytics.shouldConfigure`,
    /// Analytics.swift) none of the QA/mock-scenario/test/opt-out escape hatches are closed off. No
    /// key (even with `isEnabled == true`) is always a graceful no-op — the integration must never
    /// crash or half-initialize on a missing key.
    ///
    /// `analyticsOptedOut` mirrors the SAME user toggle PostHog honors (`Analytics.optOutKey` —
    /// "Share Anonymous Usage Data" in Settings → Privacy). Defaults to reading the real value so
    /// ordinary call sites don't need to thread it manually; tests inject an explicit value.
    static func shouldConfigure(
        isEnabled: Bool,
        apiKey: String?,
        arguments: [String] = [],
        environment: [String: String] = [:],
        analyticsOptedOut: Bool = UserDefaults.standard.bool(forKey: Analytics.optOutKey),
        isSimulator: Bool = Self.isSimulatorBuild
    ) -> Bool {
        guard isEnabled else { return false }
        guard let apiKey, !apiKey.isEmpty, apiKey != placeholderAPIKey else { return false }
        guard !analyticsOptedOut else { return false }

        let underTest = environment["XCTestConfigurationFilePath"] != nil
        let harnessOverride = environment[testHarnessLiveOverrideKey] == "1"
        if underTest && !harnessOverride { return false }

        // Dev simulator runs still mint a fresh RC anonymous "customer" on every launch even
        // outside XCTest — this closes that leak. The narrow harness override above still wins,
        // mirroring LensWords' `RevenueCatObserver.shouldConfigure`.
        if isSimulator && !harnessOverride { return false }

        // Mirrors `Analytics.shouldConfigure`'s exact QA/mock-scenario gate: any `-LH*` launch
        // argument (mock scenario seeding, UI test fixtures, screenshot capture) means this is not
        // a real launch, so RC must not phone home either.
        let qaOrDebugArgs = arguments.contains { $0.hasPrefix("-LH") }
        if qaOrDebugArgs { return false }

        return true
    }

    /// Call once from the app-launch path (`AppDelegate.application(_:didFinishLaunchingWithOptions:)`
    /// in LandlordHoursApp.swift, right after `Analytics.configure()` — this app already configures
    /// its other launch-time SDK there rather than from a SwiftUI `.task`, so this follows the same
    /// shape). Safe to call unconditionally and more than once in a process: `hasConfigured` makes
    /// every call after the first a no-op, and it is a total no-op on the very first call unless
    /// every gate above is open.
    static func configure(bundle: Bundle = .main) {
        guard !hasConfigured else { return }
        let key = apiKey(bundle: bundle)
        let info = ProcessInfo.processInfo
        guard shouldConfigure(
            isEnabled: isEnabled,
            apiKey: key,
            arguments: info.arguments,
            environment: info.environment
        ), let key else { return }
        hasConfigured = true

        // Observer mode: RC watches StoreKit 2 transactions for its dashboards but never completes
        // them. `SubscriptionManager` keeps calling `transaction.finish()` itself, exactly as
        // before — see RevenueCat's "Finishing transactions" (SDK-or-not / StoreKit 2 observer)
        // docs.
        //
        // Log level: `.debug` in DEBUG builds only, so a wrong/misconfigured key is visible in the
        // console during development instead of failing silently (RC swallows configuration
        // problems internally — see `syncPurchases`'s empty completion below); `.warn` in Release
        // — no chatty SDK logging in production builds.
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        let configuration = Configuration.Builder(withAPIKey: key)
            .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
            .build()
        Purchases.configure(with: configuration)

        // Backfills any purchase that predates RC activation into the dashboard. Anonymous — no
        // app user ID is ever set, so this attaches to whatever anonymous RC identity this device
        // already has.
        Purchases.shared.syncPurchases { _, _ in }
    }

    #if DEBUG
    /// Test-only reset. Production/TestFlight/App Store never call this — a fresh process launch
    /// already starts with `hasConfigured == false`.
    static func resetForTesting() {
        hasConfigured = false
    }
    #endif
}
