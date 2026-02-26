import Foundation
import StoreKit

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

    private init() {
        // Load purchased status
        hasPurchased = UserDefaults.standard.bool(forKey: UserScope.key("hasPurchasedPro"))
        checkSubscriptionStatus()
        
        // Load products from App Store
        Task {
            await loadProducts()
        }
    }
    
    @MainActor
    func loadProducts() async {
        do {
            // Request products from App Store
            let storeProducts = try await Product.products(for: [proProductID])
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            print("Failed to load products: \(error)")
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
            UserDefaults.standard.set(Date(), forKey: trialStartKey)
            trialDaysRemaining = 7
            isPro = true
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
