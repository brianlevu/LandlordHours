import SwiftUI
import Observation

// MARK: - 2.0 onboarding: state, routing and the rules every screen counts from
//
// Approved design: AgentScratch/landlordhours/2026-10-19/onboarding/design.md, sandbox branch
// `sandbox-onboarding` (607007d). Welcome and Staked are full-bleed blueprint; steps 1–5 share
// one layout (blueprint band holding the lot, a sheet with one question). Upgraders from 1.x get
// a short What's new (house, calendar, visit-end note) instead.
//
// Everything with a rule lives here as pure code so it is unit-tested: step routing (the note is
// only asked after a calendar grant; a skipped property never reaches Staked), the skip path,
// and where "N found" comes from (the profile's real inbox, never a sample).

enum OnbStep: String, CaseIterable {
    case welcome, goal, calendar, who, property, notify, staked
    /// Upgraders: "Your hours now build a house."
    case wnHouse

    var isFullBleed: Bool { self == .welcome || self == .staked }

    /// Analytics `step` value.
    var analyticsKey: String { self == .wnHouse ? "whats_new_house" : rawValue }

    /// DEBUG / capture launches: `-LHOnboardingStep 0…6 | welcome | goal | … | staked`.
    init?(launchValue: String) {
        if let i = Int(launchValue), OnbRouting.newUserSequence.indices.contains(i) {
            self = OnbRouting.newUserSequence[i]
            return
        }
        self.init(rawValue: launchValue)
    }
}

enum OnbGoal: String, CaseIterable {
    case reps750, mp500, mp100, record

    /// The house goal saved for the profile. "Just keep a record" keeps the REPS scale, as 1.x
    /// did for general tracking.
    var houseGoal: HouseGoal {
        switch self {
        case .reps750, .record: return .reps750
        case .mp500: return .mp500
        case .mp100: return .mp100
        }
    }

    /// The stored goal ("Just keep a record" is 1.x's "Both").
    var goalChoice: GoalChoice {
        switch self {
        case .reps750: return .reps750
        case .mp500: return .mp500
        case .mp100: return .mp100
        case .record: return .record
        }
    }

    var targetHours: Int? {
        switch self {
        case .reps750: return 750
        case .mp500: return 500
        case .mp100: return 100
        case .record: return nil
        }
    }

    var isMaterialParticipation: Bool { self == .mp500 || self == .mp100 }

    /// The primary button names the choice (design: "Commitment is a button").
    var callToAction: String {
        switch self {
        case .reps750: return "Build toward 750h"
        case .mp500: return "Build toward 500h"
        case .mp100: return "Build toward 100h"
        case .record: return "Keep a record"
        }
    }

    /// The spouse note on "Who does the work?" (REPS: one spouse must qualify alone).
    static func spouseNote(for goal: OnbGoal?) -> String {
        switch goal {
        case .mp500, .mp100: return "Your hours count together for material participation."
        case .record: return "You'll each have your own count."
        case .reps750, nil: return "You'll each have your own count. For the 750-hour test, one of you has to get there alone."
        }
    }
}

enum OnbWho: String { case me, both }

/// The calendar answer. `notNow` is the in-app decline: no system prompt was spent.
enum OnbCalendar: Equatable {
    case notAsked, allowed, denied, notNow

    var analyticsKey: String {
        switch self {
        case .notAsked: return "not_asked"
        case .allowed: return "full"
        case .denied: return "denied"
        case .notNow: return "not_now"
        }
    }
}

enum OnbCohort: String { case new, upgrade }

/// The 90-day look-back as onboarding sees it.
enum OnbScanState: Equatable { case idle, running, finished, blocked }

// MARK: - What was found (one source: the profile's inbox)

/// Backfill suggestions still waiting in the Inbox: the same items the Inbox lists, so a number
/// shown in onboarding is always a number the user can then see there. The hours add up only
/// countable work: investing, financing and contract negotiation never feed "N found".
struct OnbFound: Equatable {
    var count: Int
    var hours: Double

    static let none = OnbFound(count: 0, hours: 0)

    static func from(_ suggestions: [Suggestion], now: Date) -> OnbFound {
        let items = InboxLogic.visible(suggestions, now: now).filter(\.isBackfill)
        let countable = items.filter { $0.proposedCategory?.countsForREPS ?? true }
        return OnbFound(count: items.count, hours: countable.reduce(0) { $0 + ($1.proposedHours ?? 0) })
    }

    var hoursText: String { OnbFormat.hours(hours) }
}

enum OnbFormat {
    /// "23h", "23.5h". Never rounds up past what the rows add to.
    static func hours(_ h: Double) -> String {
        let tenths = (h * 10).rounded(.down) / 10
        return tenths == tenths.rounded() ? "\(Int(tenths))h" : String(format: "%.1fh", tenths)
    }

    static func suggestions(_ n: Int) -> String { n == 1 ? "1 suggestion" : "\(n) suggestions" }
}

// MARK: - Routing (pure)

enum OnbRouting {
    static let newUserSequence: [OnbStep] = [.welcome, .goal, .calendar, .who, .property, .notify, .staked]
    static let upgradeSequence: [OnbStep] = [.wnHouse, .calendar, .notify]

    enum Next: Equatable {
        case step(Int)
        case finish
    }

    /// The step after `index`. The visit-end note is asked only after a calendar grant; a
    /// skipped property never reaches Staked (the empty lot waits on Today).
    static func next(from index: Int, in sequence: [OnbStep], calendar: OnbCalendar, skippedProperty: Bool) -> Next {
        var n = index + 1
        if n < sequence.count, sequence[n] == .notify, calendar != .allowed { n += 1 }
        if n < sequence.count, sequence[n] == .staked, skippedProperty { return .finish }
        return n < sequence.count ? .step(n) : .finish
    }

    /// The step before `index`, or nil on the first step.
    static func back(from index: Int, in sequence: [OnbStep], calendar: OnbCalendar) -> Int? {
        var p = index - 1
        if p > 0, sequence[p] == .notify, calendar != .allowed { p -= 1 }
        return p >= 0 ? p : nil
    }
}

// MARK: - What Staked (and the property step) say

enum OnbStakedHeadline: Equatable {
    /// "23h found": the scan finished and something is waiting in the Inbox.
    case found(OnbFound)
    /// Still looking; shows the hours already in the Inbox when there are any.
    case lookingBack(OnbFound)
    /// The scan finished and found nothing.
    case nothingFound
    /// No calendar (declined, denied, or blocked): "Your house is staked."
    case plain

    static func make(calendar: OnbCalendar, scan: OnbScanState, found: OnbFound) -> OnbStakedHeadline {
        guard calendar == .allowed else { return .plain }
        switch scan {
        case .finished: return found.count > 0 ? .found(found) : .nothingFound
        case .running, .idle: return .lookingBack(found)
        case .blocked: return .plain
        }
    }

    /// Staked's button: "Review N suggestions" opens the Inbox; otherwise "Go to Today".
    var reviewCount: Int? {
        if case .found(let f) = self { return f.count }
        return nil
    }
}

enum OnbCopy {
    /// The quiet line above the property name field.
    static func propertyHint(calendar: OnbCalendar, scan: OnbScanState, found: OnbFound) -> String? {
        guard calendar == .allowed, found.count > 0 else { return nil }
        switch scan {
        case .finished: return "\(OnbFormat.suggestions(found.count)) waiting"
        case .running, .idle: return "\(OnbFormat.suggestions(found.count)) so far · still looking"
        case .blocked: return nil
        }
    }

    /// The drafting line on Staked ("0 of 750h", "0h in the book").
    static func countLine(goal: OnbGoal?) -> String {
        if let h = goal?.targetHours { return "0 of \(h)h" }
        return "0h in the book"
    }
}

// MARK: - Side effects (live wiring in OnboardingServices+Live; fakes in tests)

/// One report from the look-back: its state, what is in the Inbox, and how far it got (0…1;
/// 0 while the total is unknown).
struct OnbScanUpdate: Equatable {
    var state: OnbScanState
    var found: OnbFound
    var progress: Double = 0
}

struct OnbCompletion: Equatable {
    var cohort: OnbCohort
    /// Land on the Inbox ("Review N suggestions").
    var openInbox: Bool
    /// Staked already led with the found hours: Today never repeats them.
    var foundShown: Bool
    var skippedProperty: Bool
    var calendar: OnbCalendar
}

enum OnbEvent: Equatable {
    case stepViewed(OnbStep, OnbCohort)
    case goalSelected(OnbGoal)
    case calendarResult(OnbCalendar)
    case whoSelected(OnbWho)
    case propertyAdded(hasAddress: Bool, skipped: Bool)
    case notifyResult(String)
}

@MainActor
struct OnbServices {
    /// Welcome's "Start building": a local profile when none is signed in.
    var ensureProfile: () -> Void = {}
    var saveGoal: (OnbGoal) -> Void = { _ in }
    var saveWho: (OnbWho) -> Void = { _ in }
    var addProperty: (_ name: String, _ address: String) -> Void = { _, _ in }
    /// The real system prompt (or the DEBUG fake). Never called for "Not now".
    var requestCalendar: () async -> CalendarAccess = { .denied }
    var setCalendarSuggestions: (Bool) -> Void = { _ in }
    /// Starts the 90-day look-back; reports its state and what is in the Inbox as it changes.
    var startBackfill: (_ update: @escaping @MainActor (OnbScanUpdate) -> Void) -> Void = { _ in }
    var requestNotifications: () async -> Bool = { false }
    var setEventPrompts: (Bool) -> Void = { _ in }
    var complete: (OnbCompletion) -> Void = { _ in }
    var track: (OnbEvent) -> Void = { _ in }
}

// MARK: - The flow

@MainActor @Observable
final class OnbFlow {
    let cohort: OnbCohort
    let sequence: [OnbStep]
    var index = 0 { didSet { if index != oldValue { stepDidChange() } } }
    var forward = true
    var finished = false

    var goal: OnbGoal?
    var who: OnbWho = .me
    var name = ""
    var address = ""
    var addressOpen = false
    var calendar: OnbCalendar = .notAsked
    var notify: Bool?
    var skippedProperty = false
    /// A permission request is in flight: the buttons wait (no double prompt).
    var isAsking = false

    // Header scene
    var calendarRows = 0
    var stakeDropped = false
    var flagOpen = false

    // The look-back (non-blocking)
    var scan: OnbScanState = .idle
    var found: OnbFound = .none
    var scanProgress: Double = 0
    /// Staked showed the found hours (so Today does not repeat them).
    var foundShown = false

    /// Upgraders: their real countable hours (the house at its real stage).
    var upgradeHours: Double = 0
    var upgradeGoal: HouseGoal = .reps750

    @ObservationIgnored let services: OnbServices

    init(cohort: OnbCohort = .new, services: OnbServices, startAt step: OnbStep? = nil) {
        self.cohort = cohort
        self.sequence = cohort == .new ? OnbRouting.newUserSequence : OnbRouting.upgradeSequence
        self.services = services
        if let step, let i = sequence.firstIndex(of: step) { index = i }
    }

    var step: OnbStep { sequence[min(index, sequence.count - 1)] }
    /// Ticks on the dimension line come from the sequence (six for new users: goal…staked;
    /// three for upgraders), so a later source step adds a tick without a redesign.
    var progressTotal: Int { cohort == .new ? sequence.count - 1 : sequence.count }
    var progressValue: Int { cohort == .new ? index : index + 1 }
    var goalHours: Int? { goal?.targetHours }
    var stakedHeadline: OnbStakedHeadline { .make(calendar: calendar, scan: scan, found: found) }
    var propertyHint: String? { OnbCopy.propertyHint(calendar: calendar, scan: scan, found: found) }
    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var displayName: String { trimmedName.isEmpty ? "Your rental" : trimmedName }

    /// Fires the first step's view event (the init sets `index` without `didSet`).
    func appeared() { services.track(.stepViewed(step, cohort)) }

    private func stepDidChange() { services.track(.stepViewed(step, cohort)) }

    // MARK: Navigation

    func next(_ animation: Animation? = nil) {
        switch OnbRouting.next(from: index, in: sequence, calendar: calendar, skippedProperty: skippedProperty) {
        case .step(let n):
            forward = true
            withAnimation(animation) { index = n }
        case .finish:
            finish(openInbox: false)
        }
    }

    func back(_ animation: Animation? = nil) {
        guard let p = OnbRouting.back(from: index, in: sequence, calendar: calendar) else { return }
        forward = false
        withAnimation(animation) {
            if sequence[p] == .property { stakeDropped = false; flagOpen = false }
            index = p
        }
    }

    func finish(openInbox: Bool) {
        guard !finished else { return }
        finished = true
        services.complete(OnbCompletion(cohort: cohort, openInbox: openInbox, foundShown: foundShown,
                                        skippedProperty: skippedProperty, calendar: calendar))
    }

    // MARK: Answers

    /// 0 · "Start building".
    func start(_ animation: Animation? = nil) {
        services.ensureProfile()
        next(animation)
    }

    /// 1 · The goal button (disabled until a card is tapped).
    func confirmGoal(_ animation: Animation? = nil) {
        guard let goal else { return }
        services.saveGoal(goal)
        services.track(.goalSelected(goal))
        next(animation)
    }

    /// 2 · "Look at my calendar": the system prompt, then on to the next step either way.
    func askCalendar(_ animation: Animation? = nil) async {
        guard !isAsking else { return }
        isAsking = true
        let access = await services.requestCalendar()
        isAsking = false
        let granted = access == .fullAccess
        calendar = granted ? .allowed : .denied
        services.setCalendarSuggestions(granted)
        services.track(.calendarResult(calendar))
        if granted { startBackfill() }
        next(animation)
    }

    /// 2 · "Not now": no system prompt is spent.
    func calendarNotNow(_ animation: Animation? = nil) {
        calendar = .notNow
        services.setCalendarSuggestions(false)
        services.track(.calendarResult(.notNow))
        next(animation)
    }

    func startBackfill() {
        guard scan == .idle else { return }
        scan = .running
        services.startBackfill { [weak self] update in
            guard let self else { return }
            self.scan = update.state
            self.found = update.found
            self.scanProgress = update.progress
        }
    }

    /// 3 · "Continue" (defaults to "Just me").
    func confirmWho(_ animation: Animation? = nil) {
        services.saveWho(who)
        services.track(.whoSelected(who))
        next(animation)
    }

    /// 4 · "Save it": creates the property. The view plays the stake drop, then calls `next`.
    @discardableResult
    func saveProperty() -> Bool {
        guard !trimmedName.isEmpty, !stakeDropped else { return false }
        let address = addressOpen ? self.address.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        services.addProperty(trimmedName, address)
        services.track(.propertyAdded(hasAddress: !address.isEmpty, skipped: false))
        return true
    }

    /// 4 · "I'll add it later": straight to Today's empty lot.
    func skipProperty(_ animation: Animation? = nil) {
        skippedProperty = true
        services.track(.propertyAdded(hasAddress: false, skipped: true))
        next(animation)
    }

    /// 5 · "Yes, after visits": the system prompt. Off unless iOS says yes.
    func askNotify(_ animation: Animation? = nil) async {
        guard !isAsking else { return }
        isAsking = true
        let granted = await services.requestNotifications()
        isAsking = false
        notify = granted
        services.setEventPrompts(granted)
        services.track(.notifyResult(granted ? "granted" : "denied"))
        next(animation)
    }

    /// 5 · "Not now": stays off; the system prompt is never spent on a no.
    func notifyNotNow(_ animation: Animation? = nil) {
        notify = false
        services.setEventPrompts(false)
        services.track(.notifyResult("declined_in_app"))
        next(animation)
    }

    /// 6 · Staked's button.
    func leaveStaked() {
        finish(openInbox: stakedHeadline.reviewCount != nil)
    }
}
