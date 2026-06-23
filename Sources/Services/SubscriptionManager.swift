import Foundation
import StoreKit
import os.log

private let logger = Logger(subsystem: "com.openclaw.landlordhours", category: "StoreKit")

class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    @Published var isPro = false
    @Published var trialDaysRemaining = 0
    @Published var hasPurchased = false
    @Published var isLoading = false
    @Published var products: [Product] = []
    @Published var purchaseError: String?
    
    private let proProductID = "com.openclaw.landlordhours.pro"
    private var isProKey: String { UserScope.key("isProUser") }
    private var hasPurchasedKey: String { UserScope.key("hasPurchasedPro") }
    private var transactionListener: Task<Void, Never>?

    private init() {
        // Load purchased status
        hasPurchased = UserDefaults.standard.bool(forKey: UserScope.key("hasPurchasedPro"))
        checkSubscriptionStatus()

        // Listen for unfinished/pending transactions (e.g. interrupted purchases, Ask to Buy)
        transactionListener = listenForTransactions()

        // Load products from App Store
        Task {
            if !Self.shouldSkipStoreKitRefreshForDebugLaunch {
                await refreshEntitlements()
            }
            await loadProducts()
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    if self.isActiveProTransaction(transaction) {
                        await self.unlockPro()
                    } else if transaction.productID == self.proProductID {
                        await self.refreshEntitlements()
                    }
                    await transaction.finish()
                }
            }
        }
    }
    
    @MainActor
    func loadProducts() async {
        do {
            // Request products from App Store
            logger.debug("Loading products for: \(self.proProductID)")
            let storeProducts = try await Product.products(for: [proProductID])
            logger.debug("Loaded \(storeProducts.count) products")
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            logger.error("Failed to load products: \(error.localizedDescription)")
        }
    }
    
    func checkSubscriptionStatus() {
        trialDaysRemaining = 0
        isPro = UserDefaults.standard.bool(forKey: isProKey)
    }

    @MainActor
    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if isActiveProTransaction(transaction) {
                unlockPro()
                return
            }
        }

        if let latest = await Transaction.latest(for: proProductID),
           case .verified(let transaction) = latest,
           transaction.productID == proProductID,
           !isActiveProTransaction(transaction) {
            lockPro()
        }
    }
    
    @MainActor
    func purchasePro() async {
        isLoading = true
        purchaseError = nil
        
        do {
            if products.isEmpty {
                await loadProducts()
            }

            // Find the pro product
            guard let product = products.first(where: { $0.id == proProductID }) else {
                purchaseError = "LandlordHours Pro is temporarily unavailable in the App Store. Please try again later."
                isLoading = false
                return
            }
            
            // Purchase the product
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                // Verify and finish transaction
                if case .verified(let transaction) = verification {
                    unlockPro()
                    await transaction.finish()
                }
                
            case .userCancelled:
                purchaseError = nil // User cancelled, no error
                
            case .pending:
                purchaseError = "Purchase is pending approval. We'll unlock Pro after it is approved."
                
            @unknown default:
                purchaseError = "Purchase could not be completed. Please try again."
            }
        } catch {
            purchaseError = "Purchase failed: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    @MainActor
    func restorePurchases() async {
        isLoading = true
        purchaseError = nil

        do {
            // Sync with App Store
            try await AppStore.sync()

            await refreshEntitlements()
            if isPro {
                isLoading = false
                return
            }

            purchaseError = "No previous purchase found."
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    @MainActor
    func unlockPro() {
        UserDefaults.standard.set(true, forKey: isProKey)
        UserDefaults.standard.set(true, forKey: hasPurchasedKey)
        hasPurchased = true
        isPro = true
    }

    @MainActor
    private func lockPro() {
        UserDefaults.standard.set(false, forKey: isProKey)
        hasPurchased = false
        isPro = false
    }
    
    var isTrialActive: Bool {
        false
    }
    
    /// Reload subscription state for the current user (call after sign-in)
    func reload() {
        hasPurchased = UserDefaults.standard.bool(forKey: hasPurchasedKey)
        checkSubscriptionStatus()
        guard !Self.shouldSkipStoreKitRefreshForDebugLaunch else { return }
        Task { await refreshEntitlements() }
    }

    private static var shouldSkipStoreKitRefreshForDebugLaunch: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-LHMockScenario")
        #else
        false
        #endif
    }

    /// Reset subscription state on sign-out without starting a new trial
    func resetForSignOut() {
        isPro = false
        hasPurchased = false
        trialDaysRemaining = 0
    }

    var showPaywall: Bool {
        false
    }
    
    var proProduct: Product? {
        products.first(where: { $0.id == proProductID })
    }

    private func isActiveProTransaction(_ transaction: Transaction) -> Bool {
        transaction.productID == proProductID &&
        transaction.revocationDate == nil &&
        transaction.isUpgraded == false
    }
}
