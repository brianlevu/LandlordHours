import SwiftUI
import Observation

// MARK: - 2.0 onboarding: state, routing and the rules every screen counts from
//
// Approved design: AgentScratch/landlordhours/2026-10-19/onboarding/design.md, sandbox branch
// `sandbox-onboarding` (607007d); v2 (standard §1.24, §H.5): Welcome is the crafted house on the
// dusk/night page; every other step is one question on the plain canvas. Upgraders from 1.x get
// a short What's new (house, calendar, visit-end note) instead.
//
// Everything with a rule lives here as pure code so it is unit-tested: step routing (the note is
// only asked after a calendar grant; a skipped property never reaches Staked), the skip path,
// and where "N found" comes from (the profile's real inbox, never a sample).

enum OnbStep: String, CaseIterable {
    case welcome, goal, calendar, who, property, notify, staked
    /// Upgraders: "Your hours now build a house."
    case wnHouse

    /// v2: only Welcome sits on the dusk/night page (standard §H.5); every other step is on the canvas.
    var isOnPage: Bool { self == .welcome }

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
        guard let hours = targetHours else { return String(localized: "Keep a record", table: "ConversionPath") }
        return String(localized: "Aim for \(hours) hours", table: "ConversionPath")
    }

    /// The spouse note on "Who puts in the hours?" (REPS: one spouse must reach 750 alone).
    static func spouseNote(for goal: OnbGoal?) -> String {
        switch goal {
        case .mp500, .mp100: return String(localized: "Your hours count together for this target.", table: "ConversionPath")
        case .record: return String(localized: "You’ll each have your own count.", table: "ConversionPath")
        case .reps750, nil: return String(localized: "You’ll each have your own count. For 750, one of you has to get there alone.", table: "ConversionPath")
        }
    }
}

// MARK: - The goal step: two questions, then a suggested target (pure)

/// Q1 "What do you rent out?" and Q2 "Do you or your spouse do real estate as a main job?"
/// pick the suggested target. Nothing here says what most owners do: the suggestion is only
/// "based on your answers".
struct OnbGoalSuggestion: Equatable {
    let suggested: OnbGoal
    /// The other targets, in the order shown. "Just keep a record" is not here: it is always last.
    let alternatives: [OnbGoal]

    /// Every card in order: the suggestion, the other targets, then the record.
    var ordered: [OnbGoal] { [suggested] + alternatives + [.record] }

    /// - Real estate is your main job, or your spouse's: 750 (on that person's own count).
    /// - Nobody, short stays (or both kinds): 100 and more than anyone else; 500 is the safer one.
    /// - Nobody, long-term only: 500.
    static func make(rental: RentalMix, pro: RealEstatePro) -> OnbGoalSuggestion {
        switch pro {
        case .me, .spouse:
            return OnbGoalSuggestion(suggested: .reps750, alternatives: [.mp500, .mp100])
        case .nobody:
            return rental.hasShortStays
                ? OnbGoalSuggestion(suggested: .mp100, alternatives: [.mp500, .reps750])
                : OnbGoalSuggestion(suggested: .mp500, alternatives: [.mp100, .reps750])
        }
    }
}

/// Where the goal step is: the two questions, then the target.
enum OnbGoalPhase: Equatable { case rental, pro, target }

/// The words on the target cards. Every 750 card says what it counts.
enum OnbGoalCopy {
    static func title(_ goal: OnbGoal, pro: RealEstatePro?) -> String {
        switch goal {
        case .reps750:
            switch pro {
            case .me?: return String(localized: "750 hours, on your own count", table: "ConversionPath")
            case .spouse?: return String(localized: "750 hours, your spouse’s own count", table: "ConversionPath")
            default: return String(localized: "750 hours", table: "ConversionPath")
            }
        case .mp500: return String(localized: "500 hours", table: "ConversionPath")
        case .mp100: return String(localized: "100 hours, and more than anyone else", table: "ConversionPath")
        case .record: return String(localized: "Just keep a record", table: "ConversionPath")
        }
    }

    /// The note under the target rows, for the selected goal (standard §C.5 line 5: the spouse rule
    /// lives on "Who puts in the hours?", not here).
    static func detail(_ goal: OnbGoal, pro: RealEstatePro?, isSuggested: Bool, rental: RentalMix?) -> String {
        switch goal {
        case .reps750:
            switch pro {
            case .spouse?: return String(localized: "Counts the rental hours you log here. Other real-estate work isn’t tracked yet. Only your spouse’s own hours count.", table: "ConversionPath")
            default: return String(localized: "Counts the rental hours you log here. Other real-estate work isn’t tracked yet.", table: "ConversionPath")
            }
        case .mp500: return String(localized: "Counts the hours you put in yourself. No comparison with anyone else.", table: "ConversionPath")
        case .mp100: return String(localized: "You’ll also say if a manager or cleaner worked more hours than you.", table: "ConversionPath")
        case .record: return String(localized: "No target. Just your hours, with dates.", table: "ConversionPath")
        }
    }

    /// The option row's title: the target alone, so it never truncates (standard §1.24, D7).
    static func rowTitle(_ goal: OnbGoal) -> String {
        switch goal {
        case .reps750: return String(localized: "750 hours", table: "ConversionPath")
        case .mp500: return String(localized: "500 hours", table: "ConversionPath")
        case .mp100: return String(localized: "100 hours", table: "ConversionPath")
        case .record: return String(localized: "Just keep a record", table: "ConversionPath")
        }
    }

    /// The option row's one meta line (≤ 22 characters, so it fits one line at XXL on a 402pt window).
    static func rowMeta(_ goal: OnbGoal, pro: RealEstatePro?) -> String {
        switch goal {
        case .reps750:
            switch pro {
            case .me?: return String(localized: "Your own count", table: "ConversionPath")
            case .spouse?: return String(localized: "Your spouse’s count", table: "ConversionPath")
            default: return String(localized: "One person’s own count", table: "ConversionPath")
            }
        case .mp500: return String(localized: "The 500-hour test", table: "ConversionPath")
        case .mp100: return String(localized: "More than anyone else", table: "ConversionPath")
        case .record: return String(localized: "No target", table: "ConversionPath")
        }
    }

    /// The option row's SF glyph.
    static func symbol(_ goal: OnbGoal) -> String {
        switch goal {
        case .reps750: return "briefcase"
        case .mp500: return "house"
        case .mp100: return "calendar"
        case .record: return "doc.text"
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

    /// Whether the hours show as more than nothing ("5m", "1.5h"). The "found" moment is gated on
    /// this, never on the raw sum, so a tiny total can't render "0h found".
    var hasDisplayableHours: Bool { OnbFormat.isDisplayable(hours) }
}

enum OnbFormat {
    /// "23h", "23.5h"; under an hour in whole minutes ("5m", "45m"). Never rounds up past what
    /// the rows add to.
    static func hours(_ h: Double) -> String {
        if h < 1 { return "\(Int((h * 60).rounded(.down)))m" }
        let tenths = (h * 10).rounded(.down) / 10
        return tenths == tenths.rounded() ? "\(Int(tenths))h" : String(format: "%.1fh", tenths)
    }

    /// At least one whole minute: what `hours(_:)` shows is not zero.
    static func isDisplayable(_ h: Double) -> Bool { (h * 60).rounded(.down) >= 1 }

    static func suggestions(_ n: Int) -> String {
        n == 1 ? String(localized: "1 suggestion", table: "ConversionPath") : String(localized: "\(n) suggestions", table: "ConversionPath")
    }

    /// "23 hours", "23.5 hours", "1 hour"; under an hour in whole minutes ("45 minutes"). Never
    /// rounds up past what the rows add to.
    static func hoursInWords(_ h: Double) -> String {
        if h < 1 {
            let minutes = Int((h * 60).rounded(.down))
            return minutes == 1 ? String(localized: "1 minute", table: "ConversionPath") : String(localized: "\(minutes) minutes", table: "ConversionPath")
        }
        let tenths = (h * 10).rounded(.down) / 10
        if tenths == tenths.rounded() {
            let whole = Int(tenths)
            return whole == 1 ? String(localized: "1 hour", table: "ConversionPath") : String(localized: "\(whole) hours", table: "ConversionPath")
        }
        return String(localized: "\(String(format: "%.1f", tenths)) hours", table: "ConversionPath")
    }
}

// MARK: - Placing what was found (pure)

enum OnbPlacement {
    /// The property every unplaced suggestion goes to: the owner's only property. With several
    /// properties nothing is guessed; the Inbox asks on Confirm.
    static func soleProperty(_ properties: [RentalProperty]) -> UUID? {
        properties.count == 1 ? properties.first?.id : nil
    }
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
    /// The scan found items, but none would count (only investing, financing or negotiation):
    /// never "0h found" or a slab.
    case nothingCountable(count: Int)
    /// No calendar (declined, denied, or blocked): "Your house is staked."
    case plain

    static func make(calendar: OnbCalendar, scan: OnbScanState, found: OnbFound) -> OnbStakedHeadline {
        guard calendar == .allowed else { return .plain }
        switch scan {
        case .finished:
            // "Nh found" only when the found work would count toward hours.
            if found.count > 0 && found.hasDisplayableHours { return .found(found) }
            return found.count > 0 ? .nothingCountable(count: found.count) : .nothingFound
        case .running, .idle: return .lookingBack(found)
        case .blocked: return .plain
        }
    }

    /// Staked's button: "Review N suggestions" opens the Inbox; otherwise "Go to Today".
    var reviewCount: Int? {
        switch self {
        case .found(let f): return f.count
        case .nothingCountable(let count): return count
        default: return nil
        }
    }

    /// The drafting line under "Your house is staked." when nothing found counts.
    static func nothingCountableLine(_ count: Int) -> String {
        count == 1
            ? String(localized: "We found 1 thing, but none count toward your hours yet.", table: "ConversionPath")
            : String(localized: "We found \(count) things, but none count toward your hours yet.", table: "ConversionPath")
    }
}

enum OnbCopy {
    /// The quiet line above the property name field.
    static func propertyHint(calendar: OnbCalendar, scan: OnbScanState, found: OnbFound) -> String? {
        guard calendar == .allowed, found.count > 0 else { return nil }
        switch scan {
        case .finished: return String(localized: "\(OnbFormat.suggestions(found.count)) waiting", table: "ConversionPath")
        case .running, .idle: return String(localized: "\(OnbFormat.suggestions(found.count)) so far · still looking", table: "ConversionPath")
        case .blocked: return nil
        }
    }

    /// The count line beside the house on Staked ("0 of 750 hours", "0 hours in the book").
    static func countLine(goal: OnbGoal?) -> String {
        if let h = goal?.targetHours { return String(localized: "0 of \(h) hours", table: "ConversionPath") }
        return String(localized: "0 hours in the book", table: "ConversionPath")
    }

    /// Staked, when the look-back found countable hours: "23 hours found. 0 counted." Found hours
    /// are never counted until the owner confirms them, so the second number is what is
    /// confirmed so far (nothing, in a new profile).
    static func foundHeadline(_ found: OnbFound, counted: Double = 0) -> String {
        String(localized: "\(OnbFormat.hoursInWords(found.hours)) found. \(Int(counted.rounded(.down))) counted.", table: "ConversionPath")
    }

    /// The line under the found headline: where the hours came from and what confirming does.
    static func foundBody(count: Int, goal: OnbGoal?) -> String {
        switch (count == 1, goal?.targetHours) {
        case (true, let h?): return String(localized: "From 1 calendar event in the last 90 days. Confirm it if it was rental work, and it counts toward your \(h) hours.", table: "ConversionPath")
        case (false, let h?): return String(localized: "From \(count) calendar events in the last 90 days. Confirm the rental ones and they count toward your \(h) hours.", table: "ConversionPath")
        case (true, nil): return String(localized: "From 1 calendar event in the last 90 days. Confirm it if it was rental work, and it goes in your record.", table: "ConversionPath")
        case (false, nil): return String(localized: "From \(count) calendar events in the last 90 days. Confirm the rental ones and they go in your record.", table: "ConversionPath")
        }
    }

    /// Staked, with no found hours: "You’re set up for 100 hours."
    static func setUpHeadline(goal: OnbGoal?) -> String {
        if let h = goal?.targetHours { return String(localized: "You’re set up for \(h) hours.", table: "ConversionPath") }
        return String(localized: "You’re set up to keep a record.", table: "ConversionPath")
    }

    static func setUpBody(goal: OnbGoal?) -> String {
        goal?.targetHours == nil
            ? String(localized: "Every hour you log from here goes in your record, dated the day it happened.", table: "ConversionPath")
            : String(localized: "Every hour you log from here counts toward it, dated the day it happened.", table: "ConversionPath")
    }

    /// Upgraders, first screen: "Your 312 hours, on the way to 750."
    static func upgradeHeadline(hours: Double, goal: HouseGoal, isRecord: Bool) -> String {
        let whole = Int(hours.rounded(.down))
        if isRecord {
            return whole >= 1 ? String(localized: "Your \(whole) hours, safe in your record.", table: "ConversionPath") : String(localized: "Your records, safe where they are.", table: "ConversionPath")
        }
        let target = Int(goal.targetHours)
        return whole >= 1 ? String(localized: "Your \(whole) hours, on the way to \(target).", table: "ConversionPath") : String(localized: "Your hours, on the way to \(target).", table: "ConversionPath")
    }

    static func upgradeBody(isRecord: Bool) -> String {
        isRecord
            ? String(localized: "Same hours, same PDF. Today now shows your hours, and the house shows how far along you are.", table: "ConversionPath")
            : String(localized: "Same hours, same PDF. Today now shows your count against your target, and the house shows how far along you are.", table: "ConversionPath")
    }

    /// Only the 750 target: what it counts.
    static let upgradeRepsNote = String(localized: "The 750 counts the rental hours you log here. Other real-estate work isn’t tracked yet.", table: "ConversionPath")
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
    case goalAnswered(rental: RentalMix, pro: RealEstatePro)
    case calendarResult(OnbCalendar)
    case whoSelected(OnbWho)
    case propertyAdded(hasAddress: Bool, skipped: Bool)
    case notifyResult(String)
}

@MainActor
struct OnbServices {
    /// Welcome's "Start building": a local profile when none is signed in.
    var ensureProfile: () -> Void = {}
    /// Welcome's Sign in with Apple for a NEW Apple user: makes their profile (returning users
    /// and Restore never come through here; they open on Today).
    var signUpWithApple: () -> Void = {}
    var saveGoal: (OnbGoal) -> Void = { _ in }
    /// What the target was suggested from: the kind of rental and who works in real estate.
    var saveGoalAnswers: (_ rental: RentalMix, _ pro: RealEstatePro) -> Void = { _, _ in }
    var saveWho: (OnbWho) -> Void = { _ in }
    var addProperty: (_ name: String, _ address: String, _ type: PropertyType) -> Void = { _, _, _ in }
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

extension OnbServices {
    /// ContentView shows onboarding while `!isSignedIn || showOnboarding`. Making a profile
    /// flips isSignedIn, so unless showOnboarding is already true the shell mounts for a frame,
    /// onboarding is torn down and its flow restarts on Welcome (the first tap looks ignored).
    /// Runs `keepShown` before every profile this flow creates.
    func holdingOnboarding(_ keepShown: @escaping () -> Void) -> OnbServices {
        var s = self
        let makeProfile = ensureProfile, appleSignUp = signUpWithApple
        s.ensureProfile = { keepShown(); makeProfile() }
        s.signUpWithApple = { keepShown(); appleSignUp() }
        return s
    }
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
    /// The goal step's answers. The target is suggested from both.
    var goalPhase: OnbGoalPhase = .rental
    var rental: RentalMix?
    var pro: RealEstatePro?
    /// Which kind of rental the first property is (asked only when the owner has both kinds).
    var firstPropertyIsShortStay = true
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
    /// Upgraders who chose "keep a record" have no target to be "on the way to".
    var upgradeIsRecord = false

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
    var suggestion: OnbGoalSuggestion? {
        guard let rental, let pro else { return nil }
        return .make(rental: rental, pro: pro)
    }
    /// The kind the first property is saved as.
    var firstPropertyType: PropertyType {
        switch rental {
        case .longTerm?: return .ltr
        case .shortStays?: return .str
        case .both?: return firstPropertyIsShortStay ? .str : .ltr
        case nil: return .ltr
        }
    }
    var stakedHeadline: OnbStakedHeadline { .make(calendar: calendar, scan: scan, found: found) }
    var propertyHint: String? { OnbCopy.propertyHint(calendar: calendar, scan: scan, found: found) }
    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var displayName: String { trimmedName.isEmpty ? String(localized: "Your rental", table: "ConversionPath") : trimmedName }

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
        // Inside the goal step, back goes to the earlier question first.
        if step == .goal, cohort == .new, goalPhase != .rental {
            forward = false
            withAnimation(animation) { goalPhase = goalPhase == .target ? .pro : .rental }
            return
        }
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

    /// 0 · Sign in with Apple, new Apple user: their profile, then on like "Start building".
    func signUpWithApple(_ animation: Animation? = nil) {
        services.signUpWithApple()
        next(animation)
    }

    /// 1a · "What do you rent out?": one tap moves on to the next question.
    func answerRental(_ answer: RentalMix, _ animation: Animation? = nil) {
        rental = answer
        forward = true
        withAnimation(animation) { goalPhase = .pro }
    }

    /// 1b · "Do you or your spouse do real estate as a main job?": one tap shows the suggested
    /// target, already selected. The spouse path starts "Who puts in the hours?" on both of you.
    func answerPro(_ answer: RealEstatePro, _ animation: Animation? = nil) {
        pro = answer
        if let rental { goal = OnbGoalSuggestion.make(rental: rental, pro: answer).suggested }
        who = answer == .spouse ? .both : .me
        forward = true
        withAnimation(animation) { goalPhase = .target }
    }

    /// 1c · The goal button (disabled until a card is tapped).
    func confirmGoal(_ animation: Animation? = nil) {
        guard let goal else { return }
        services.saveGoal(goal)
        if let rental, let pro { services.saveGoalAnswers(rental, pro) }
        services.track(.goalSelected(goal))
        if let rental, let pro { services.track(.goalAnswered(rental: rental, pro: pro)) }
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
        services.addProperty(trimmedName, address, firstPropertyType)
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
