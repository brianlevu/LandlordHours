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
    /// True from the moment a purchase starts until the App Store answers, even after the
    /// purchase deadline: the paywall keeps Buy off so a second purchase can't start meanwhile.
    @Published private(set) var isPurchaseInFlight = false
    
    private let proProductID = "com.openclaw.landlordhours.pro"
    private var isProKey: String { UserScope.key("isProUser") }
    private var hasPurchasedKey: String { UserScope.key("hasPurchasedPro") }
    private var transactionListener: Task<Void, Never>?

    #if DEBUG
    /// Longest a restore waits on `AppStore.sync()` (it can sit on an Apple Account sign-in that
    /// never comes back). Tests and the DEBUG `-LHRestoreOutcome` hook shorten it.
    static var restoreSyncTimeout: TimeInterval = 90
    /// Longest a purchase waits on the App Store. A purchase that completes after this still
    /// unlocks Pro and is finished; the paywall stops spinning and says it's still finishing.
    static var purchaseTimeout: TimeInterval = 300

    /// DEBUG-only seams for the two App Store calls that put up system UI. Tests swap in a call
    /// that never returns to prove restore and purchase still end. Release can't reassign them.
    var syncWithAppStore: @MainActor () async throws -> Void = { try await AppStore.sync() }
    var purchaseProduct: @MainActor (Product) async throws -> Product.PurchaseResult = { try await $0.purchase() }
    #else
    static let restoreSyncTimeout: TimeInterval = 90
    static let purchaseTimeout: TimeInterval = 300
    private let syncWithAppStore: @MainActor () async throws -> Void = { try await AppStore.sync() }
    private let purchaseProduct: @MainActor (Product) async throws -> Product.PurchaseResult = { try await $0.purchase() }
    #endif

    /// Message for a restore that failed (error or timeout), as opposed to one that found nothing.
    @Published private(set) var restoreFailureMessage: String?

    /// In a unit-test host StoreKit stays untouched until the tests attach their StoreKit test
    /// session (`attachStoreKit()`). StoreKit picks a process's environment on its first call:
    /// a call made before the session exists binds the whole process to the Sandbox store, so the
    /// session's purchases never reach the app and `AppStore.sync()` waits on a sign-in forever.
    #if DEBUG
    private(set) var isStoreKitAttached = !SubscriptionManager.isUnitTestHost
    #else
    let isStoreKitAttached = true
    #endif

    private init() {
        // Load purchased status
        hasPurchased = UserDefaults.standard.bool(forKey: UserScope.key("hasPurchasedPro"))
        checkSubscriptionStatus()

        guard isStoreKitAttached else { return }
        // Listen for unfinished/pending transactions (e.g. interrupted purchases, Ask to Buy)
        startListenerIfNeeded()

        // Load products from App Store
        Task {
            if !Self.shouldSkipStoreKitRefreshForDebugLaunch {
                await refreshEntitlements()
            }
            await loadProducts()
        }
    }

    static var isUnitTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    #if DEBUG
    /// Unit tests: call once the StoreKit test session exists. Later StoreKit calls go to it.
    func attachStoreKit() {
        isStoreKitAttached = true
    }

    /// Tests: start the listener (idempotent).
    func startTransactionListener() {
        startListenerIfNeeded()
    }

    /// Tests: stop the listener so a transaction from one test can't land in the next.
    func stopTransactionListener() {
        transactionListener?.cancel()
        transactionListener = nil
    }
    #endif

    /// Starts the Transaction.updates listener. Idempotent, so it can never run twice.
    private func startListenerIfNeeded() {
        guard isStoreKitAttached, transactionListener == nil else { return }
        transactionListener = listenForTransactions()
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
        guard isStoreKitAttached else { return }
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
        guard isStoreKitAttached else { return }
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
        /// The App Store hadn't answered by the deadline. The purchase may still finish; its
        /// real outcome goes to `lateOutcome`.
        case timedOut
    }

    @MainActor
    @discardableResult
    func purchasePro() async -> PurchaseOutcome {
        await purchasePro(lateOutcome: { _ in })
    }

    /// `lateOutcome` gets the real outcome of a purchase that answered after the deadline.
    @MainActor
    @discardableResult
    func purchasePro(lateOutcome: @escaping @MainActor (PurchaseOutcome) -> Void) async -> PurchaseOutcome {
        guard isStoreKitAttached else { return .failed }
        guard !isPurchaseInFlight else {
            purchaseError = "Still finishing your purchase…"
            return .failed
        }
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
            
            // Purchase the product. The handling runs inside the deadline's operation so a
            // purchase that completes after the deadline still unlocks Pro and is finished.
            let purchase = purchaseProduct
            isPurchaseInFlight = true
            let finished: (PurchaseOutcome, String?)? = await StoreDeadline.run(
                seconds: Self.purchaseTimeout,
                onLate: { [self] late in
                    if late.0 == .purchased { purchaseError = nil }
                    lateOutcome(late.0)
                }
            ) { [self] in
                defer { isPurchaseInFlight = false }
                do {
                    let result = try await purchase(product)
                    switch result {
                    case .success(let verification):
                        // Verify and finish transaction
                        if case .verified(let transaction) = verification {
                            unlockPro()
                            await transaction.finish()
                            return (.purchased, nil)
                        }
                        return (.failed, "The App Store couldn't confirm this purchase. Please try again.")
                    case .userCancelled:
                        return (.cancelled, nil) // User cancelled, no error
                    case .pending:
                        return (.pending, "Purchase is pending approval. We'll unlock Pro after it is approved.")
                    @unknown default:
                        return (.failed, "Purchase could not be completed. Please try again.")
                    }
                } catch {
                    return (.failed, "Purchase failed: \(error.localizedDescription)")
                }
            }
            if let finished {
                outcome = finished.0
                purchaseError = finished.1
            } else {
                outcome = .timedOut
                purchaseError = "Still finishing your purchase…"
            }
        }

        isLoading = false
        return outcome
    }
    
    /// Returns true when an earlier Pro purchase was found and applied.
    @MainActor
    @discardableResult
    func restorePurchases() async -> Bool {
        guard isStoreKitAttached else { return false }
        isLoading = true
        purchaseError = nil
        restoreFailureMessage = nil
        defer { isLoading = false }

        // StoreKit 2 keeps entitlements in sync on its own; a purchase already on this device
        // restores without asking for an Apple Account sign-in.
        await refreshEntitlements()
        if isPro {
            Analytics.purchaseRestored()
            return true
        }

        // Sync with App Store, bounded: it can wait on a sign-in sheet that never resolves.
        let sync = syncWithAppStore
        let synced: Result<Void, Error>? = await StoreDeadline.run(seconds: Self.restoreSyncTimeout) {
            do { try await sync(); return .success(()) } catch { return .failure(error) }
        }
        switch synced {
        case nil:
            let message = Self.restoreTimedOutMessage
            purchaseError = message
            restoreFailureMessage = message
            return false
        case .failure(let error)?:
            // Fixed, plain copy: a system error string can be technical ("StoreKitError 1").
            var cancelled = false
            if case .userCancelled? = error as? StoreKitError { cancelled = true }
            let message = cancelled ? Self.restoreCancelledMessage : Self.restoreFailedMessage
            purchaseError = message
            restoreFailureMessage = message
            return false
        case .success?:
            break
        }

        await refreshEntitlements()
        if isPro {
            Analytics.purchaseRestored()
            return true
        }
        purchaseError = "We didn't find an earlier Pro purchase for this Apple Account."
        return false
    }

    static let restoreTimedOutMessage = String(localized: "The App Store didn't answer. Try again in a moment.")
    static let restoreFailedMessage = String(localized: "Couldn't reach the App Store. Check your connection and try again.")
    static let restoreCancelledMessage = String(localized: "Restore was cancelled.")

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
        restoreFailureMessage = nil
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

/// Bounds an App Store call that can wait forever (a sign-in or purchase sheet that never
/// resolves). Returns the operation's value, or nil once `seconds` pass. The operation is NOT
/// cancelled on timeout: it keeps running so a late purchase is still unlocked and finished.
/// Exactly one of the two paths resumes the continuation, so it can't leak or double-resume.
enum StoreDeadline {
    /// `onLate` gets the value when the operation finishes after the deadline (decided under the
    /// same lock as the resume, so a finish can't be both on time and late, or neither).
    @MainActor
    static func run<T>(
        seconds: TimeInterval,
        onLate: (@MainActor (T) -> Void)? = nil,
        _ operation: @escaping @MainActor () async -> T
    ) async -> T? {
        let once = ResumeOnce<T?>()
        return await withCheckedContinuation { continuation in
            once.install(continuation)
            let timer = Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                if !Task.isCancelled { once.resume(nil) }
            }
            Task { @MainActor in
                let value = await operation()
                timer.cancel()
                if !once.resume(value) { onLate?(value) }
            }
        }
    }
}

private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    func install(_ continuation: CheckedContinuation<T, Never>) {
        lock.lock(); defer { lock.unlock() }
        self.continuation = continuation
    }

    /// Returns false when the continuation was already resumed (this call came too late).
    @discardableResult
    func resume(_ value: T) -> Bool {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
        return pending != nil
    }
}
