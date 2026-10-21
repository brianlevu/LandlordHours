import Foundation
import SwiftUI

// MARK: - The one free-to-paid system (WP-P)
//
// Every place a free user meets a paid feature goes through this file:
// - `ProGate` holds the rules (what is locked, for whom) as pure functions.
// - `LockEntry` names each entry point; `ProGate.context(for:)` maps it to the paywall it opens.
// - `PaywallCopy` is the paywall's words for each context.
// - `PaywallFlow` / `PaywallPhase` are the purchase, restore and Ask to Buy state machine.
// - `PriceDisplay` keeps the billed amount the most prominent price on the page (App Review).
// - `InboxProLimit` and `ProWaitList` are the Inbox at-limit rules.
// - `ProPaywallPresenter` lets any screen (Properties, Inbox, Today…) open the one paywall and
//   continue its own action after a purchase, without owning a sheet: call
//   `ProPaywallPresenter.shared.present(.secondProperty, entry: .propertiesLimit) { … }`.
//
// redesign-specs.md §0 (LockedPreview) and §1.

// MARK: - Paywall context

/// What the paywall is about. The headline, plan line and success button speak to the thing
/// tapped, and after a purchase the caller continues that action.
///
/// Raw values are the analytics `context` values. Two keep their 1.x names so PostHog funnels
/// stay continuous: Today's lock reports "dashboardUnlock", Settings reports "settingsUpgrade".
enum PaywallContext: String, CaseIterable, Identifiable {
    /// Export (Reports, Records or Settings → Export).
    case export
    /// A second rental: Properties at the free limit, or the Inbox at-limit picker.
    case secondProperty
    /// Today's "Your record" card.
    case todayUnlock = "dashboardUnlock"
    /// The Pro card at the top of Settings.
    case settings = "settingsUpgrade"

    var id: String { rawValue }
}

// MARK: - Entry points

/// Every place a free user meets a paid feature. Raw values are the analytics `entry` values.
enum LockEntry: String, CaseIterable, Identifiable {
    /// The Export page itself (reached from Reports, Records or Settings): `.page` lock.
    case exportPage = "export_page"
    /// The export card at the bottom of Reports (the Reports free preview): `.row` lock.
    case reportsExport = "reports_export"
    /// Settings: the Export row under the Pro card, `.row` lock.
    case settingsExport = "settings_export"
    /// Properties at the free limit: the ghost "Your next rental" row.
    case propertiesLimit = "properties_limit"
    /// Settings: the Pro card on top (not a lock, a plain card).
    case settingsPro = "settings_pro"
    /// Today: the "Your record" card (free user with 10h or more).
    case todayRecord = "today_record"
    /// Inbox: a suggestion at a new rental while the free plan is full.
    case inboxLimit = "inbox_limit"

    var id: String { rawValue }
}

// MARK: - Rules

enum ProGate {
    /// The free plan covers one rental.
    static let freeRentals = 1
    /// Today shows "Your record" once a free user has this many confirmed hours.
    static let todayRecordMinimumHours: Double = 10

    static func isAtPropertyLimit(isPro: Bool, propertyCount: Int) -> Bool {
        !isPro && propertyCount >= freeRentals
    }

    static func canAddProperty(isPro: Bool, propertyCount: Int) -> Bool {
        !isAtPropertyLimit(isPro: isPro, propertyCount: propertyCount)
    }

    static func isExportLocked(isPro: Bool) -> Bool { !isPro }

    static func showsTodayRecordLock(isPro: Bool, confirmedHours: Double) -> Bool {
        !isPro && confirmedHours.isFinite && confirmedHours >= todayRecordMinimumHours
    }

    /// Whether the entry point shows its locked preview right now.
    static func isLocked(_ entry: LockEntry, isPro: Bool, propertyCount: Int = 0, confirmedHours: Double = 0) -> Bool {
        switch entry {
        case .exportPage, .reportsExport, .settingsExport: return isExportLocked(isPro: isPro)
        case .propertiesLimit, .inboxLimit: return isAtPropertyLimit(isPro: isPro, propertyCount: propertyCount)
        case .settingsPro: return !isPro
        case .todayRecord: return showsTodayRecordLock(isPro: isPro, confirmedHours: confirmedHours)
        }
    }

    /// The paywall each entry point opens.
    static func context(for entry: LockEntry) -> PaywallContext {
        switch entry {
        case .exportPage, .reportsExport, .settingsExport: return .export
        case .propertiesLimit, .inboxLimit: return .secondProperty
        case .settingsPro: return .settings
        case .todayRecord: return .todayUnlock
        }
    }

    /// The one line saying what is locked.
    static func lockLine(_ entry: LockEntry, confirmedHours: Double = 0) -> String {
        switch entry {
        case .exportPage: return "This is the record your accountant gets."
        case .reportsExport, .settingsExport: return "Export comes with Pro."
        case .propertiesLimit, .inboxLimit: return "Free covers one rental."
        case .settingsPro: return "LandlordHours Pro"
        case .todayRecord: return "Your \(wholeHours(confirmedHours)) hours, ready to export."
        }
    }

    /// What stays active and free while previewing (the paywall law).
    static func keepsLine(_ entry: LockEntry, firstPropertyName: String? = nil) -> String {
        switch entry {
        case .exportPage, .todayRecord: return "Your record keeps growing. Export unlocks with Pro."
        case .reportsExport: return "Every report here stays free."
        case .settingsExport: return "Your records stay free on this iPhone."
        case .propertiesLimit, .inboxLimit:
            let name = firstPropertyName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(name?.isEmpty == false ? name! : "Your rental") keeps tracking. Nothing is lost."
        case .settingsPro: return "Pay once. Everything you have stays free."
        }
    }

    static func wholeHours(_ hours: Double) -> String {
        "\(Int(max(0, hours.isFinite ? hours : 0).rounded(.down)))"
    }
}

// MARK: - Paywall copy

struct PaywallCopy: Equatable {
    let headline: String
    let planLine: String
    /// The success button: the next step of what the user was doing.
    let nextStep: String

    /// - propertyName: the rental the user was adding (secondProperty).
    /// - confirmedHours: Today's lock speaks to the user's own hours.
    static func make(_ context: PaywallContext, year: Int, propertyName: String? = nil, confirmedHours: Double? = nil) -> PaywallCopy {
        let name = propertyName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasName = name?.isEmpty == false
        switch context {
        case .export:
            return PaywallCopy(headline: "The record your accountant gets",
                               planLine: "Export \(String(year)) as a PDF or spreadsheet, any time.",
                               nextStep: "Export \(String(year))")
        case .secondProperty:
            return PaywallCopy(headline: "Track every rental",
                               planLine: "Add \(hasName ? name! : "your next rental") and every place after it. Your hours stay put.",
                               nextStep: hasName ? "Add \(name!)" : "Add a property")
        case .todayUnlock:
            let hours = confirmedHours.map { ProGate.wholeHours($0) }
            return PaywallCopy(headline: "Your hours, on paper",
                               planLine: "Turn \(hours.map { "\($0) confirmed" } ?? "your confirmed") hours into a clean record.",
                               nextStep: "See your record")
        case .settings:
            return PaywallCopy(headline: "LandlordHours Pro",
                               planLine: "Every rental, the PDF and spreadsheet, and the record of where each hour came from.",
                               nextStep: "Done")
        }
    }

    /// "What you get", the same four rows in every context.
    static let benefits: [(symbol: String, title: String, line: String)] = [
        ("house.fill", "Every rental", "Free covers one."),
        ("doc.richtext", "PDF and spreadsheet", "Ready for your accountant."),
        ("calendar.badge.checkmark", "Where each hour came from", "Calendar, receipt or typed, on every line."),
        ("arrow.clockwise", "Yours on every device", "Restore Pro when you change phones."),
    ]
}

// MARK: - Price display (App Review: the billed amount is the most conspicuous price)

struct PriceDisplay: Equatable {
    enum Role: String, Equatable { case billed, caption, button, intro }

    struct Element: Equatable {
        let role: Role
        let text: String
        /// Point size at the default text size (relative scaling keeps the order at every size).
        let pointSize: CGFloat
    }

    /// The App Store's localized price, e.g. "$29.99". Never hardcoded.
    let billed: String
    /// Optional trial or intro copy. Always subordinate: smaller and below the billed amount.
    let intro: String?

    static let billedSize: CGFloat = 44
    static let captionSize: CGFloat = 15
    static let buttonSize: CGFloat = 17
    static let introSize: CGFloat = 13
    static let caption = "once, yours to keep"

    /// The buy button's label. At large text sizes it drops the price ("Unlock Pro").
    func buttonTitle(large: Bool) -> String { large ? "Unlock Pro" : "Unlock for \(billed)" }

    /// Everything on the page that mentions money, top to bottom.
    func elements(large: Bool) -> [Element] {
        var list = [Element(role: .billed, text: billed, pointSize: Self.billedSize),
                    Element(role: .caption, text: Self.caption, pointSize: Self.captionSize)]
        if let intro { list.append(Element(role: .intro, text: intro, pointSize: Self.introSize)) }
        list.append(Element(role: .button, text: buttonTitle(large: large), pointSize: Self.buttonSize))
        return list
    }

    /// The billed amount is first and strictly larger than every other price element.
    func billedIsMostProminent(large: Bool) -> Bool {
        let all = elements(large: large)
        guard let first = all.first, first.role == .billed else { return false }
        return all.dropFirst().allSatisfy { $0.pointSize < first.pointSize }
    }

    /// VoiceOver: "29 dollars 99, one-time purchase" style, from the localized price.
    var accessibilityLabel: String { "\(billed), one-time purchase" }
}

// MARK: - Purchase flow

enum PaywallPhase: String, Equatable, CaseIterable {
    case priceLoading, priceFailed, ready, buying, askToBuy, failed, success, restoring, restoreNone
}

/// The paywall's state machine. Pure, so every transition is unit-tested.
enum PaywallFlow {
    static func afterPriceLoad(found: Bool) -> PaywallPhase { found ? .ready : .priceFailed }

    static func canBuy(_ phase: PaywallPhase) -> Bool {
        switch phase {
        case .ready, .failed, .restoreNone: return true
        default: return false
        }
    }

    static func canRestore(_ phase: PaywallPhase) -> Bool {
        switch phase {
        case .buying, .restoring, .success: return false
        default: return true
        }
    }

    static func afterPurchase(_ outcome: SubscriptionManager.PurchaseOutcome) -> PaywallPhase {
        switch outcome {
        case .purchased: return .success
        case .cancelled: return .ready     // Cancelled: nothing changes.
        case .pending: return .askToBuy
        case .failed: return .failed
        case .timedOut: return .failed   // Buy stays off while the purchase is still in flight.
        }
    }

    static func afterRestore(found: Bool) -> PaywallPhase { found ? .success : .restoreNone }

    /// A pending (Ask to Buy) purchase approved later arrives through Transaction.updates.
    static func afterEntitlementChange(isPro: Bool, from phase: PaywallPhase) -> PaywallPhase {
        isPro ? .success : phase
    }

    /// Analytics `outcome` values for purchase_failed.
    static func failureReason(_ outcome: SubscriptionManager.PurchaseOutcome) -> String? {
        switch outcome {
        case .failed: return "failed"
        case .pending: return "pending"
        case .cancelled: return "cancelled"
        case .purchased: return nil
        case .timedOut: return nil      // purchase_timeout, its own event
        }
    }
}

// MARK: - Inbox at the free limit

enum InboxProLimit {
    /// A pending suggestion that belongs to a rental the user doesn't have, while the free plan
    /// is full: it can't be logged without Pro (unless the user says it was at their rental).
    static func needsNewRental(_ suggestion: Suggestion, propertyIds: Set<UUID>, isPro: Bool) -> Bool {
        // Only the plain free case (exactly one rental): an unassigned item there is the "new
        // place" of redesign-specs §1c. A downgraded owner with several rentals picks among them
        // as before ("Pick a property"), so the regular Log stays available.
        guard suggestion.isPending, !isPro, propertyIds.count == ProGate.freeRentals else { return false }
        guard let id = suggestion.proposedPropertyId else { return true }
        return !propertyIds.contains(id)
    }

    struct Counts: Equatable {
        /// Pending items at a new rental (shown as "New place").
        var atLimit: Int
        /// Of those, the ones the user chose to keep for later ("Waiting on Pro").
        var waiting: Int
    }

    static func counts(_ suggestions: [Suggestion], propertyIds: Set<UUID>, isPro: Bool, waitingKeys: Set<String>) -> Counts {
        let over = suggestions.filter { needsNewRental($0, propertyIds: propertyIds, isPro: isPro) }
        return Counts(atLimit: over.count, waiting: over.filter { waitingKeys.contains($0.sourceKey) }.count)
    }

    static let sheetLine = "Free covers one rental. This visit will wait in your inbox."
    static let waitingLabel = "Waiting on Pro"
    static let newPlaceLabel = "New place"
}

/// Suggestions the user parked with "Keep it in my inbox" while at the free limit. Per profile,
/// local only. It never expires an item and never logs one to the wrong place.
final class ProWaitList {
    static let shared = ProWaitList()
    static let baseKey = "LandlordHours.proWaitList"

    private let defaults: UserDefaults
    private let keyProvider: () -> String

    init(defaults: UserDefaults = .standard, keyProvider: @escaping () -> String = { UserScope.key(ProWaitList.baseKey) }) {
        self.defaults = defaults
        self.keyProvider = keyProvider
    }

    var keys: Set<String> { Set(defaults.stringArray(forKey: keyProvider()) ?? []) }

    func contains(_ sourceKey: String) -> Bool { keys.contains(sourceKey) }

    func add(_ sourceKey: String) {
        var all = keys
        all.insert(sourceKey)
        defaults.set(all.sorted(), forKey: keyProvider())
    }

    func remove(_ sourceKey: String) {
        var all = keys
        guard all.remove(sourceKey) != nil else { return }
        defaults.set(all.sorted(), forKey: keyProvider())
    }

    /// Drops keys that are no longer pending (logged, dismissed or gone).
    func prune(keeping pending: Set<String>) {
        let kept = keys.intersection(pending)
        if kept != keys { defaults.set(kept.sorted(), forKey: keyProvider()) }
    }
}

// MARK: - Presenter (the shared API every screen calls)

struct ProPaywallRequest: Identifiable {
    let id = UUID()
    let context: PaywallContext
    let entry: LockEntry
    var year: Int = Calendar.current.component(.year, from: Date())
    var propertyName: String?
    var confirmedHours: Double?
    /// Runs after a purchase or restore, once the paywall has closed.
    var onUnlocked: (() -> Void)?
}

/// One paywall for the whole app. The shell installs `.proPaywallHost()` once; any screen calls
/// `present(…)`. Properties (wp-properties) and the Inbox use this rather than their own sheets.
@MainActor
final class ProPaywallPresenter: ObservableObject {
    static let shared = ProPaywallPresenter()
    @Published var request: ProPaywallRequest?

    func present(_ context: PaywallContext,
                 entry: LockEntry,
                 year: Int = Calendar.current.component(.year, from: Date()),
                 propertyName: String? = nil,
                 confirmedHours: Double? = nil,
                 onUnlocked: (() -> Void)? = nil) {
        request = ProPaywallRequest(context: context, entry: entry, year: year, propertyName: propertyName,
                                    confirmedHours: confirmedHours, onUnlocked: onUnlocked)
    }

    /// Opens the paywall for an entry point (its context comes from `ProGate`).
    func present(entry: LockEntry, propertyName: String? = nil, confirmedHours: Double? = nil, onUnlocked: (() -> Void)? = nil) {
        present(ProGate.context(for: entry), entry: entry, propertyName: propertyName,
                confirmedHours: confirmedHours, onUnlocked: onUnlocked)
    }

    func dismiss() { request = nil }
}
