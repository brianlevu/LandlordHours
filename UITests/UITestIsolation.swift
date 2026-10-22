import XCTest
#if canImport(StoreKitTest)
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

    static func resetStoreKit() {
        #if canImport(StoreKitTest)
        if session == nil {
            session = try? SKTestSession(configurationFileNamed: "LandlordHours")
        }
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
