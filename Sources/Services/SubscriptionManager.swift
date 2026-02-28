import Foundation
import StoreKit
import os.log

private let logger = Logger(subsystem: "com.openclaw.landlordhours", category: "StoreKit")

class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    @Published var isPro = false
    @Published var trialDaysRemaining = 7
    @Published var hasPurchased = false
    @Published var isLoading = false
    @Published var products: [Product] = []
    @Published var purchaseError: String?
    
    private let proProductID = "com.openclaw.landlordhours.pro"
    private var trialStartKey: String { UserScope.key("trialStartDate") }
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
            await loadProducts()
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    if transaction.productID == self.proProductID {
                        await self.unlockPro()
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
        // Check if user purchased pro
        if UserDefaults.standard.bool(forKey: isProKey) {
            isPro = true
            return
        }
        
        // Check trial
        if let trialStart = UserDefaults.standard.object(forKey: trialStartKey) as? Date {
            let daysPassed = Calendar.current.dateComponents([.day], from: trialStart, to: Date()).day ?? 0
            trialDaysRemaining = max(0, 7 - daysPassed)
            
            if trialDaysRemaining == 0 {
                isPro = false
            } else {
                isPro = true
            }
        } else {
            // Only start a trial if a user is signed in, so we don't
            // create an orphaned trial under the unscoped key.
            if UserScope.userId != nil {
                UserDefaults.standard.set(Date(), forKey: trialStartKey)
                trialDaysRemaining = 7
                isPro = true
            } else {
                trialDaysRemaining = 0
                isPro = false
            }
        }
    }
    
    @MainActor
    func purchasePro() async {
        isLoading = true
        purchaseError = nil
        
        do {
            // Find the pro product
            guard let product = products.first(where: { $0.id == proProductID }) else {
                purchaseError = "Product not found. Please try again."
                isLoading = false
                return
            }
            
            // Purchase the product
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                // Verify and finish transaction
                if case .verified(let transaction) = verification {
                    await unlockPro()
                    await transaction.finish()
                }
                
            case .userCancelled:
                purchaseError = nil // User cancelled, no error
                
            case .pending:
                purchaseError = "Purchase is pending approval."
                
            @unknown default:
                purchaseError = "Unknown error occurred."
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

            // Check for verified transactions
            let productID = proProductID
            if let result = await Transaction.latest(for: productID) {
                if case .verified(_) = result {
                    unlockPro()
                    isLoading = false
                    return
                }
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
    
    var isTrialActive: Bool {
        return trialDaysRemaining > 0 && !hasPurchased
    }
    
    /// Reload subscription state for the current user (call after sign-in)
    func reload() {
        hasPurchased = UserDefaults.standard.bool(forKey: hasPurchasedKey)
        checkSubscriptionStatus()
    }

    /// Reset subscription state on sign-out without starting a new trial
    func resetForSignOut() {
        isPro = false
        hasPurchased = false
        trialDaysRemaining = 0
    }

    var showPaywall: Bool {
        return !isPro
    }
    
    var proProduct: Product? {
        products.first(where: { $0.id == proProductID })
    }
}
