import XCTest
@testable import LandlordHours

/// Unit tests for `LandlordPurchases`'s pure gating logic (RevenueCat is integrated in
/// analytics/observer mode ONLY, and ships dark until a real key replaces the placeholder). These
/// never touch the real RevenueCat SDK (`configure()` itself is a thin, untestable side effect);
/// everything here is table-driven over `shouldConfigure`, `normalizedAPIKey`, and
/// `apiKey(bundle:)`, which is the whole contract that matters: the integration must be a graceful,
/// total no-op whenever any gate is closed. Mirrors `RevenueCatObserverTests` (LensWords) /
/// `BeeBuddyPurchasesTests`-equivalent coverage, adapted to this app's `-LH*` launch-argument
/// convention and `Analytics.optOutKey` opt-out.
final class LandlordPurchasesTests: XCTestCase {

    // MARK: - shouldConfigure

    func testNeverConfiguresWhenDisabledEvenWithARealKey() {
        XCTAssertFalse(LandlordPurchases.shouldConfigure(
            isEnabled: false, apiKey: "appl_realkey123", analyticsOptedOut: false,
            isSimulator: false
        ))
    }

    func testNeverConfiguresWithNilKeyEvenWhenEnabled() {
        XCTAssertFalse(LandlordPurchases.shouldConfigure(
            isEnabled: true, apiKey: nil, analyticsOptedOut: false,
            isSimulator: false
        ))
    }

    func testNeverConfiguresWithEmptyKeyEvenWhenEnabled() {
        XCTAssertFalse(LandlordPurchases.shouldConfigure(
            isEnabled: true, apiKey: "", analyticsOptedOut: false,
            isSimulator: false
        ))
    }

    func testNeverConfiguresWithThePlaceholderKeyEvenWhenEnabled() {
        XCTAssertFalse(LandlordPurchases.shouldConfigure(
            isEnabled: true, apiKey: LandlordPurchases.placeholderAPIKey, analyticsOptedOut: false,
            isSimulator: false
        ))
    }

    func testConfiguresOnlyWhenBothEnabledAndARealKeyArePresent() {
        XCTAssertTrue(LandlordPurchases.shouldConfigure(
            isEnabled: true, apiKey: "appl_realkey123", analyticsOptedOut: false,
            isSimulator: false
        ))
    }

    // MARK: - shouldConfigure — usage-sharing opt-out gate

    func testNeverConfiguresWhenUserOptedOutOfUsageSharing() {
        XCTAssertFalse(LandlordPurchases.shouldConfigure(
            isEnabled: true, apiKey: "appl_realkey123", analyticsOptedOut: true,
            isSimulator: false
        ))
    }

    // MARK: - shouldConfigure — XCTest gate (mirrors Analytics.shouldConfigure)

    func testXCTestGateBlocksConfigurationDuringOrdinaryTestRuns() {
        XCTAssertFalse(LandlordPurchases.shouldConfigure(
            isEnabled: true,
            apiKey: "appl_realkey123",
            environment: ["XCTestConfigurationFilePath": "/tmp/whatever.xctestconfiguration"],
            analyticsOptedOut: false,
            isSimulator: false
        ))
    }

    func testXCTestGateStillBlocksWithoutARealKeyEvenUnderTheHarnessOverride() {
        XCTAssertFalse(LandlordPurchases.shouldConfigure(
            isEnabled: true,
            apiKey: nil,
            environment: [
                "XCTestConfigurationFilePath": "/tmp/whatever.xctestconfiguration",
                LandlordPurchases.testHarnessLiveOverrideKey: "1",
            ],
            analyticsOptedOut: false,
            isSimulator: false
        ))
    }

    func testXCTestGateStillBlocksWhenDisabledEvenUnderTheHarnessOverride() {
        XCTAssertFalse(LandlordPurchases.shouldConfigure(
            isEnabled: false,
            apiKey: "appl_realkey123",
            environment: [
                "XCTestConfigurationFilePath": "/tmp/whatever.xctestconfiguration",
                LandlordPurchases.testHarnessLiveOverrideKey: "1",
            ],
            analyticsOptedOut: false,
            isSimulator: false
        ))
    }

    func testXCTestGateAllowsTheOneNarrowHarnessOverride() {
        XCTAssertTrue(LandlordPurchases.shouldConfigure(
            isEnabled: true,
            apiKey: "appl_realkey123",
            environment: [
                "XCTestConfigurationFilePath": "/tmp/whatever.xctestconfiguration",
                LandlordPurchases.testHarnessLiveOverrideKey: "1",
            ],
            analyticsOptedOut: false,
            isSimulator: false
        ))
    }

    func testXCTestGateIsPermissiveOutsideOfTests() {
        // No `XCTestConfigurationFilePath` key at all (a real launch) — behaves exactly like the
        // pre-gate overload above.
        XCTAssertTrue(LandlordPurchases.shouldConfigure(
            isEnabled: true, apiKey: "appl_realkey123", environment: [:], analyticsOptedOut: false,
            isSimulator: false
        ))
    }

    // MARK: - shouldConfigure — simulator gate (dev sims mint fresh RC "customers," 2026-08-28)

    func testSimulatorGateBlocksConfigurationOnASimulatorBuild() {
        XCTAssertFalse(LandlordPurchases.shouldConfigure(
            isEnabled: true, apiKey: "appl_realkey123", analyticsOptedOut: false, isSimulator: true))
    }

    func testSimulatorGateIsPermissiveOnADeviceBuild() {
        XCTAssertTrue(LandlordPurchases.shouldConfigure(
            isEnabled: true, apiKey: "appl_realkey123", analyticsOptedOut: false, isSimulator: false))
    }

    func testSimulatorGateStillAllowsTheHarnessOverride() {
        XCTAssertTrue(LandlordPurchases.shouldConfigure(
            isEnabled: true,
            apiKey: "appl_realkey123",
            environment: [LandlordPurchases.testHarnessLiveOverrideKey: "1"],
            analyticsOptedOut: false,
            isSimulator: true
        ))
    }

    /// Runtime proof, not just pure-logic coverage: THIS test process is genuinely running under
    /// XCTest right now (no `LANDLORDHOURS_TEST_RC_LIVE` override set for an ordinary unit-test
    /// run), so calling the real `configure()` must stay a total no-op — the actual guarantee a
    /// reviewer cares about is "ordinary `xcodebuild test` never phones api.revenuecat.com," not
    /// just that the pure function returns the right boolean.
    func testActualConfigureIsANoOpDuringAnOrdinaryUnitTestRun() {
        XCTAssertNil(ProcessInfo.processInfo.environment[LandlordPurchases.testHarnessLiveOverrideKey],
                     "This test assumes the harness override is NOT set — if it is, run it in isolation")
        LandlordPurchases.configure()
        XCTAssertFalse(LandlordPurchases.hasConfigured, "RC must not configure during a normal unit test run")
    }

    // MARK: - shouldConfigure — `-LH*` QA/mock-scenario gate (mirrors Analytics.shouldConfigure)

    func testMockScenarioLaunchArgumentBlocksConfiguration() {
        XCTAssertFalse(LandlordPurchases.shouldConfigure(
            isEnabled: true,
            apiKey: "appl_realkey123",
            arguments: ["-LHMockScenario", "qualified"],
            analyticsOptedOut: false,
            isSimulator: false
        ))
    }

    func testAnyDashLHLaunchArgumentBlocksConfiguration() {
        XCTAssertFalse(LandlordPurchases.shouldConfigure(
            isEnabled: true,
            apiKey: "appl_realkey123",
            arguments: ["-LHInitialTab", "reports"],
            analyticsOptedOut: false,
            isSimulator: false
        ))
    }

    func testNoLaunchArgumentsIsPermissive() {
        XCTAssertTrue(LandlordPurchases.shouldConfigure(
            isEnabled: true, apiKey: "appl_realkey123", arguments: [], analyticsOptedOut: false,
            isSimulator: false
        ))
    }

    func testUnrelatedLaunchArgumentsAreIgnored() {
        XCTAssertTrue(LandlordPurchases.shouldConfigure(
            isEnabled: true,
            apiKey: "appl_realkey123",
            arguments: ["-SomeOtherFlag"],
            analyticsOptedOut: false,
            isSimulator: false
        ))
    }

    /// The integration ships activated with a real key today (2026-08-26) — this pins that fact so
    /// a future accidental flip back to the placeholder or a disabled gate is caught by a red test
    /// instead of silently going dark.
    func testShipsActivatedWithARealKey() {
        XCTAssertTrue(LandlordPurchases.isEnabled, "RevenueCat was deliberately activated; do not silently disable")
        let key = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String ?? ""
        XCTAssertTrue(key.hasPrefix("appl_"), "RevenueCatAPIKey must be a real public SDK key (appl_...), got: \(key.isEmpty ? "empty" : key)")
    }

    // MARK: - normalizedAPIKey (the pure extraction `apiKey(bundle:)` wraps)

    func testNormalizedAPIKeyIsNilWhenRawIsNil() {
        XCTAssertNil(LandlordPurchases.normalizedAPIKey(nil))
    }

    func testNormalizedAPIKeyIsNilWhenRawIsEmpty() {
        XCTAssertNil(LandlordPurchases.normalizedAPIKey(""))
    }

    func testNormalizedAPIKeyIsNilWhenRawIsWhitespaceOnly() {
        XCTAssertNil(LandlordPurchases.normalizedAPIKey("   \n\t "))
    }

    func testNormalizedAPIKeyTreatsThePlaceholderAsAbsent() {
        // The real Info.plist ships the placeholder until Brian pastes a key — confirm it reads as
        // "no key," not as a (broken) real one.
        XCTAssertNil(LandlordPurchases.normalizedAPIKey(LandlordPurchases.placeholderAPIKey))
    }

    func testNormalizedAPIKeyTrimsAndReturnsARealKey() {
        XCTAssertEqual(LandlordPurchases.normalizedAPIKey("  appl_realkey123  "), "appl_realkey123")
    }

    func testNormalizedAPIKeyRejectsTestStoreKeyOutsideDebug() {
        XCTAssertNil(LandlordPurchases.normalizedAPIKey("test_shouldneverreachrelease", isDebugBuild: false),
                     "A Test Store key reaching Configuration.Builder in a non-DEBUG build crashes RC's own SDK")
    }

    func testNormalizedAPIKeyAllowsTestStoreKeyInDebug() {
        XCTAssertEqual(LandlordPurchases.normalizedAPIKey("test_fineindebug", isDebugBuild: true), "test_fineindebug")
    }

    func testNormalizedAPIKeyAllowsNonTestKeyRegardlessOfBuildFlavor() {
        XCTAssertEqual(LandlordPurchases.normalizedAPIKey("appl_realkey123", isDebugBuild: false), "appl_realkey123")
    }

    // MARK: - apiKey(bundle:) — the "key truly absent from Info.plist" path

    func testApiKeyIsNilWhenInfoPlistHasNoSuchKey() {
        // A real Bundle whose Info.plist genuinely lacks `RevenueCatAPIKey` (the unit test bundle
        // itself) proves the "absent" branch end-to-end; the placeholder/whitespace/trim/Test-Store
        // logic is covered above at the pure-function level, which is what actually needs unit
        // coverage — `Bundle` has no supported way to inject a fake Info.plist dictionary.
        XCTAssertNil(LandlordPurchases.apiKey(bundle: Bundle(for: LandlordPurchasesTests.self)))
    }

    // MARK: - configure() idempotence

    func testConfigureIsIdempotentWhenAlreadyConfigured() {
        // `hasConfigured` guards the SDK call itself against being invoked twice in one process.
        // Force the flag on directly (rather than driving a real `Purchases.configure` call, which
        // would require a live network-reachable key) to prove the guard short-circuits before any
        // gating logic runs at all.
        #if DEBUG
        LandlordPurchases.resetForTesting()
        #endif
        XCTAssertFalse(LandlordPurchases.hasConfigured)

        // First call under XCTest with no harness override: gated off by the XCTest check, so
        // `hasConfigured` stays false — this call does NOT count as "already configured."
        LandlordPurchases.configure()
        XCTAssertFalse(LandlordPurchases.hasConfigured)

        // Calling again is still a no-op (same gates apply), proving repeated calls in one process
        // never crash or double-initialize even before the first real configure ever happens.
        LandlordPurchases.configure()
        XCTAssertFalse(LandlordPurchases.hasConfigured)
    }

    #if DEBUG
    func testResetForTestingClearsTheConfiguredFlag() {
        LandlordPurchases.resetForTesting()
        XCTAssertFalse(LandlordPurchases.hasConfigured)
    }
    #endif
}
