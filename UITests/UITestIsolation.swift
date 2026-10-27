import XCTest
#if canImport(StoreKitTest)
import StoreKit
import StoreKitTest
#endif

/// Makes every UI test start clean regardless of order. The free-user journeys buy Pro
/// through the local StoreKit config and leave mock profiles behind; without this, a later
/// test (e.g. the sign-in restore list) sees extra profiles and a Pro purchase.
enum UITestIsolation {
    /// DEBUG fixture flag: wipes every local/email profile and the active sign-in keys
    /// before the launch's own seed runs (`LegacyProfileFixture.resetAllRestorableProfiles`).
    static let resetProfilesArgument = "-LHResetProfilesForTesting"

    #if canImport(StoreKitTest)
    /// Kept alive for the whole run so its settings stay applied.
    nonisolated(unsafe) private static var session: SKTestSession?
    #endif

    /// Clears StoreKit test transactions so no test inherits a purchase. Dialogs stay off so
    /// a journey's purchase completes without the local confirm sheet (the tap that opens the
    /// sheet is what the journeys count).
    /// Ask to Buy / failed-transaction journeys (WP-P). Reset by `resetStoreKit()`.
    static func setAskToBuy(_ on: Bool) {
        #if canImport(StoreKitTest)
        session?.askToBuyEnabled = on
        #endif
    }

    static func setFailTransactions(_ on: Bool) {
        #if canImport(StoreKitTest)
        session?.failTransactionsEnabled = on
        if on { session?.failureError = .unknown }
        #endif
    }

    /// Ready once per runner process: set by `warmStoreKit()` once storekitd accepted the session.
    nonisolated(unsafe) private static var storeKitWarm = false

    private final class ProbeBox: @unchecked Sendable { var error: Error? }

    private static func probe(_ session: SKTestSession) throws {
        let done = DispatchSemaphore(value: 0)
        let box = ProbeBox()
        nonisolated(unsafe) let session = session
        Task.detached {
            do { try await session.buyProduct(identifier: "com.openclaw.landlordhours.pro") } catch { box.error = error }
            done.signal()
        }
        if done.wait(timeout: .now() + 15) == .timedOut {
            throw NSError(domain: "UITestIsolation", code: 1, userInfo: [NSLocalizedDescriptionKey: "StoreKit probe timed out after 15 s"])
        }
        if let error = box.error { throw error }
    }

    /// Cold-start guard. On a freshly created simulator the first `SKTestSession` can fail to save
    /// its configuration (SKInternalErrorDomain 4); every StoreKit call then returns
    /// SKServiceErrorDomain 2, so the first test class on a new sim failed. A throwing call
    /// (`buyProduct`) is the readiness probe: it succeeds only when storekitd accepted the
    /// session. On failure, rebuild the session after a short pause.
    /// Bounded: 5 attempts, then fail loudly with the last error.
    private static func warmStoreKit() {
        #if canImport(StoreKitTest)
        guard !storeKitWarm else { return }
        var lastError = "no attempt ran"
        // On a fresh simulator storekitd rejects the first session (notEntitled, then
        // SKServiceErrorDomain 2 on every call) until the app has been launched once. Launch and
        // quit it before the first session so the run starts clean.
        let app = XCUIApplication()
        app.launch()
        app.terminate()
        for attempt in 1...5 {
            do {
                session = nil
                let made = try SKTestSession(configurationFileNamed: "LandlordHours")
                made.disableDialogs = true
                session = made
                // Readiness probe: unlike the other session calls (which only log), buyProduct
                // throws when storekitd could not take the configuration.
                try probe(made)
                made.clearTransactions()
                storeKitWarm = true
                print("UITestIsolation: StoreKit warm after \(attempt) attempt(s)")
                return
            } catch {
                lastError = "\(error)"
                print("UITestIsolation: StoreKit attempt \(attempt) failed: \(error)")
            }
            Thread.sleep(forTimeInterval: 2)
        }
        XCTFail("StoreKit test session never became ready: \(lastError)")
        #endif
    }

    static func resetStoreKit() {
        #if canImport(StoreKitTest)
        warmStoreKit()
        guard let session else { return }
        session.resetToDefaultState()
        session.askToBuyEnabled = false
        session.failTransactionsEnabled = false
        session.disableDialogs = true
        session.clearTransactions()
        #endif
    }
}

extension UITestIsolation {
    /// The 2.0 goal step: two plain answers (what you rent out, who does real estate as a main
    /// job); the suggested target is then already selected. Ids: rental-short|long|both and
    /// pro-me|spouse|none. Ends on the target cards.
    static func answerGoalQuestions(_ app: XCUIApplication, rental: String = "rental-short", pro: String = "pro-me", timeout: TimeInterval = 15) {
        for id in [rental, pro] {
            let card = app.buttons[id]
            XCTAssertTrue(card.waitForExistence(timeout: timeout), "missing \(id)")
            let deadline = Date().addingTimeInterval(timeout)
            while !card.isHittable && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
            card.tap()
        }
    }
}
