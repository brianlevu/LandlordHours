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
    /// 2.3: the care plan (package B calls `ProPaywallPresenter.present(entry: .carePlan)`).
    case carePlan
    /// 2.3: lessons (package C calls `ProPaywallPresenter.present(entry: .learning)`).
    case learning

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
    /// 2.3: a view-only rental's page ("See Pro" on the view-only card).
    case viewOnlyRental = "view_only_rental"
    /// 2.3: the Log time rental picker, on a view-only rental.
    case logPicker = "log_picker"
    /// 2.3: "See Pro" on the pick-your-free-rental sheet.
    case freeRentalPick = "free_rental_pick"
    /// 2.3: Settings › Free rental, the Pro row.
    case freeRentalSettings = "free_rental_settings"
    /// 2.3: the care plan's locked preview (package B).
    case carePlan = "care_plan"
    /// 2.3: a lesson past the free preview (package C).
    case learning = "learning"

    var id: String { rawValue }
}

// MARK: - Rules

enum ProGate {
    /// The free plan covers one rental.
    static let freeRentals = 1

    // MARK: 2.3: every lock reads the plan (`Plan.allows(_:)`), never `isPro`.

    /// The feature each entry point sells.
    static func feature(for entry: LockEntry) -> ProFeature {
        switch entry {
        case .exportPage, .reportsExport, .settingsExport, .todayRecord: return .export
        case .propertiesLimit, .inboxLimit, .viewOnlyRental, .logPicker, .freeRentalPick, .freeRentalSettings, .settingsPro:
            return .allRentals
        case .carePlan: return .carePlan
        case .learning: return .learning
        }
    }

    /// Whether the entry point shows its lock for this plan.
    static func isLocked(_ entry: LockEntry, plan: Plan, propertyCount: Int = 0, confirmedHours: Double = 0) -> Bool {
        let allowed = plan.allows(feature(for: entry))
        switch entry {
        case .propertiesLimit, .inboxLimit:
            return !FreeRentalPolicy.canAddRental(plan: plan, rentalCount: propertyCount)
        case .todayRecord:
            return !allowed && confirmedHours.isFinite && confirmedHours >= todayRecordMinimumHours
        default:
            return !allowed
        }
    }
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
        case .settingsPro, .viewOnlyRental, .logPicker, .freeRentalPick, .freeRentalSettings, .carePlan, .learning: return !isPro
        case .todayRecord: return showsTodayRecordLock(isPro: isPro, confirmedHours: confirmedHours)
        }
    }

    /// The paywall each entry point opens.
    static func context(for entry: LockEntry) -> PaywallContext {
        switch entry {
        case .exportPage, .reportsExport, .settingsExport: return .export
        case .propertiesLimit, .inboxLimit, .viewOnlyRental, .logPicker, .freeRentalPick, .freeRentalSettings:
            return .secondProperty
        case .settingsPro: return .settings
        case .todayRecord: return .todayUnlock
        case .carePlan: return .carePlan
        case .learning: return .learning
        }
    }

    /// The one line saying what is locked.
    static func lockLine(_ entry: LockEntry, confirmedHours: Double = 0) -> String {
        switch entry {
        case .exportPage: return "This is the record your accountant gets."
        case .reportsExport, .settingsExport: return "Export comes with Pro."
        case .propertiesLimit, .inboxLimit: return "Free covers one rental."
        case .settingsPro, .freeRentalSettings, .freeRentalPick: return "Dormer Pro"
        case .viewOnlyRental, .logPicker: return "View only on the free plan."
        case .carePlan: return "Care plans come with Pro."
        case .learning: return "Lessons come with Pro."
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
        case .settingsPro, .freeRentalSettings, .freeRentalPick: return "One rental stays free for good."
        case .viewOnlyRental, .logPicker: return "Its hours stay in your total."
        case .carePlan, .learning: return "Your hours and your free rental stay as they are."
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
        case .settings, .carePlan, .learning:
            return PaywallCopy(headline: "Dormer Pro",
                               planLine: "Every rental, the PDF and spreadsheet, care plans and lessons.",
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

// MARK: - Price display (App Review 3.1.2: the billed amount is the most conspicuous price)

/// Every price the 2.3 paywall shows, with its size, so a test can prove the billed amount
/// (StoreKit's `displayPrice`, never a literal) is first and strictly the largest. The trial is
/// always worded below it and smaller ("Free for 14 days, then <price> a year").
struct PriceDisplay: Equatable {
    enum Role: String, Equatable { case billed, period, planLine, timeline, button, tag }

    struct Element: Equatable {
        let role: Role
        let text: String
        /// Point size at the default text size (relative scaling keeps the order at every size).
        let pointSize: CGFloat
    }

    /// The App Store's localized price, e.g. "<price>". Never hardcoded.
    let billed: String
    /// Days of Apple's free trial, nil when the person can't get one (then the button subscribes).
    let trialDays: Int?

    /// `.largeTitle` bold rounded.
    static let billedSize: CGFloat = 34
    /// "a year": `.title3` semibold.
    static let periodSize: CGFloat = 20
    /// The plan line under the price and the timeline lines: `.subheadline`.
    static let lineSize: CGFloat = 15
    static let buttonSize: CGFloat = 17
    /// The "14 days free" tag: `.footnote`.
    static let tagSize: CGFloat = 13

    var offersTrial: Bool { (trialDays ?? 0) > 0 }

    /// The primary button. Never a price: the billed amount stays the one big price.
    var buttonTitle: String {
        offersTrial ? String(localized: "paywall.cta.trial", defaultValue: "Start free trial", table: "Pricing")
                    : String(localized: "paywall.cta.subscribe", defaultValue: "Subscribe", table: "Pricing")
    }

    var period: String { String(localized: "paywall.price.period", defaultValue: "a year", table: "Pricing") }

    /// "Free for 14 days, then <price> a year. Renews each year until you cancel." or, without a
    /// trial, "<price> a year. Renews each year until you cancel."
    var planLine: String {
        if let days = trialDays, days > 0 {
            return String(localized: "paywall.price.lineTrial",
                          defaultValue: "Free for \(days) days, then \(billed) a year. Renews each year until you cancel.",
                          table: "Pricing")
        }
        return String(localized: "paywall.price.line", defaultValue: "\(billed) a year. Renews each year until you cancel.",
                      table: "Pricing")
    }

    /// Everything on the page that mentions money, top to bottom (the timeline sits above the
    /// card but its renewal line is `.subheadline`, smaller than the billed amount).
    func elements() -> [Element] {
        var list = [Element(role: .billed, text: billed, pointSize: Self.billedSize),
                    Element(role: .period, text: period, pointSize: Self.periodSize),
                    Element(role: .planLine, text: planLine, pointSize: Self.lineSize)]
        if offersTrial {
            list.append(Element(role: .timeline, text: billed, pointSize: Self.lineSize))
            list.append(Element(role: .tag, text: "\(trialDays ?? 0)", pointSize: Self.tagSize))
        }
        list.append(Element(role: .button, text: buttonTitle, pointSize: Self.buttonSize))
        return list
    }

    /// The billed amount is first and strictly larger than every other price element.
    func billedIsMostProminent() -> Bool {
        let all = elements()
        guard let first = all.first, first.role == .billed else { return false }
        return all.dropFirst().allSatisfy { $0.pointSize < first.pointSize }
    }

    /// VoiceOver: "<price> a year".
    var accessibilityLabel: String {
        String(localized: "paywall.price.a11y", defaultValue: "\(billed) a year", table: "Pricing")
    }
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
