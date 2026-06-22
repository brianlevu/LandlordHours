import XCTest
import StoreKit
@testable import LandlordHours

#if canImport(StoreKitTest)
import StoreKitTest

@MainActor
final class StoreKitLocalIntegrationTests: XCTestCase {
    private let proProductID = "com.openclaw.landlordhours.pro"
    private let testUserID = "storekit-local-test-user"
    private var session: SKTestSession!

    override func setUpWithError() throws {
        try super.setUpWithError()
        session = try SKTestSession(configurationFileNamed: "LandlordHours")
        session.disableDialogs = true
        session.clearTransactions()
        resetScopedStoreKitState()
    }

    override func tearDownWithError() throws {
        session.clearTransactions()
        resetScopedStoreKitState()
        session = nil
        try super.tearDownWithError()
    }

    func testLocalStoreKitConfigurationLoadsProProduct() async throws {
        let products = try await Product.products(for: [proProductID])

        let proProduct = try XCTUnwrap(products.first(where: { $0.id == proProductID }))
        XCTAssertEqual(proProduct.displayName, "LandlordHours Pro")
        XCTAssertEqual(proProduct.type, .nonConsumable)
    }

    private func resetScopedStoreKitState() {
        UserDefaults.standard.set(testUserID, forKey: "emailUserId")
        UserDefaults.standard.set("storekit-local-test@example.com", forKey: "emailUserEmail")
        UserDefaults.standard.set("StoreKit Test", forKey: "emailUserName")
        UserDefaults.standard.set(LoginType.email.rawValue, forKey: "loginType")
        UserDefaults.standard.removeObject(forKey: UserScope.key("isProUser"))
        UserDefaults.standard.removeObject(forKey: UserScope.key("hasPurchasedPro"))
        UserDefaults.standard.synchronize()
        SubscriptionManager.shared.resetForSignOut()
    }
}
#endif
