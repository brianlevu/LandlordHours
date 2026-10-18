import Foundation
import StoreKit
import os.log

private let logger = Logger(subsystem: "com.openclaw.landlordhours", category: "StoreKit")

class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    @Published var isPro = false
    @Published var hasPurchased = false
    @Published var isLoading = false
    @Published var products: [Product] = []
    @Published var purchaseError: String? {
        didSet { if purchaseError != nil { RatingPromptCoordinator.shared.noteError() } }
    }
    
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
    
    enum PurchaseOutcome: Equatable {
        case purchased
        case cancelled
        case pending
        case failed
    }

    @MainActor
    @discardableResult
    func purchasePro() async -> PurchaseOutcome {
        var outcome: PurchaseOutcome = .failed
        isLoading = true
        purchaseError = nil
        
        do {
            if products.isEmpty {
                await loadProducts()
            }

            // Find the pro product
            guard let product = products.first(where: { $0.id == proProductID }) else {
                purchaseError = "We couldn't reach the App Store to load Pro. Check your connection and try again."
                isLoading = false
                return .failed
            }
            
            // Purchase the product
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                // Verify and finish transaction
                if case .verified(let transaction) = verification {
                    unlockPro()
                    await transaction.finish()
                    outcome = .purchased
                } else {
                    purchaseError = "The App Store couldn't confirm this purchase. Please try again."
                }
                
            case .userCancelled:
                purchaseError = nil // User cancelled, no error
                outcome = .cancelled
                
            case .pending:
                purchaseError = "Purchase is pending approval. We'll unlock Pro after it is approved."
                outcome = .pending
                
            @unknown default:
                purchaseError = "Purchase could not be completed. Please try again."
            }
        } catch {
            purchaseError = "Purchase failed: \(error.localizedDescription)"
        }
        
        isLoading = false
        return outcome
    }
    
    /// Returns true when an earlier Pro purchase was found and applied.
    @MainActor
    @discardableResult
    func restorePurchases() async -> Bool {
        isLoading = true
        purchaseError = nil

        do {
            // Sync with App Store
            try await AppStore.sync()

            await refreshEntitlements()
            if isPro {
                isLoading = false
                Analytics.purchaseRestored()
                return true
            }

            purchaseError = "We didn't find an earlier Pro purchase for this Apple Account."
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }

        isLoading = false
        return false
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
