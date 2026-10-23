import Foundation

// MARK: - 2.1 plan surfaces: the rules behind the rental page card, Check my goal and the
// Inbox cleaner card. Plain rules on stored answers; nothing here calls a model.

// MARK: Rental page card

enum RentalPlanCard {
    /// The card offers the two choices only where each rental can have its own target.
    static func isEditable(_ ctx: RentalPlanContext) -> Bool { RentalPlanning.mode(ctx) == .perRental }

    /// The plan this rental would have if the owner had never touched it.
    static func defaultPlan(for property: RentalProperty, _ ctx: RentalPlanContext) -> RentalPlan {
        var untouched = ctx
        untouched.overrides.removeValue(forKey: property.id)
        return RentalPlanning.plan(for: property, untouched)
    }

    /// The target "Track a goal" gives this rental (an existing pinned number is kept).
    static func trackTarget(for property: RentalProperty, _ ctx: RentalPlanContext) -> Int {
        if case .trackPinned(let h)? = ctx.overrides[property.id] { return h }
        return RentalPlanning.ownTargetHours(goal: ctx.goal, whoDoesMost: ctx.whoDoesMost[property.id])
    }

    /// Writes the owner's choice. When it matches what the app would pick anyway the override is
    /// cleared, so an untouched rental keeps re-deriving when the goal changes.
    @MainActor
    static func choose(track: Bool, for property: RentalProperty, _ ctx: RentalPlanContext, store: RentalPlanStore) {
        let defaultTracks = defaultPlan(for: property, ctx).track.hasOwnTarget
        if defaultTracks == track {
            store.setOverride(nil, for: property.id)
        } else if track, case .trackPinned? = ctx.overrides[property.id] {
            // Keep a pinned number when the owner re-picks "Track".
        } else {
            store.setOverride(track ? .track : .record, for: property.id)
        }
    }

    /// The short line under the choices: what the rental gets and why.
    static func explanation(for property: RentalProperty, _ ctx: RentalPlanContext) -> String {
        let plan = RentalPlanning.plan(for: property, ctx)
        switch plan.track {
        case .ownTarget(let h):
            let why = RentalPlanWords.targetReason(whoDoesMost: ctx.whoDoesMost[property.id], hours: h)
            return String(localized: "It has its own \(h)-hour target. \(why).", table: "Home")
        case .recordOnly(let reason):
            let h = trackTarget(for: property, ctx)
            let why = RentalPlanWords.reason(reason)
            return String(localized: "\(why). Pick Track a goal and it will have its own \(h)-hour target.", table: "Home")
        case .sharedTotal(let h):
            return readOnlyLine(hours: h)
        }
    }

    /// Under 750, grouping or a record goal: one line, no choices.
    static func readOnlyLine(_ ctx: RentalPlanContext) -> String {
        switch RentalPlanning.mode(ctx) {
        case .shared(let h): return readOnlyLine(hours: h)
        case .record: return String(localized: "Your goal is to keep a record. Every rental’s hours are kept, with no target.", table: "Home")
        case .perRental: return ""
        }
    }

    private static func readOnlyLine(hours: Int) -> String {
        String(localized: "Counts toward your \(hours). Every rental’s hours go into one total.", table: "Home")
    }
}

// MARK: Check my goal

enum GoalCheckWords {
    static func answer(_ who: WhoDoesMost) -> String {
        switch who {
        case .me: return String(localized: "Me", table: "Home")
        case .meAndSpouse: return String(localized: "Me and my spouse", table: "Home")
        case .someoneElse: return String(localized: "A cleaner, manager or contractor", table: "Home")
        case .notSure: return String(localized: "Not sure", table: "Home")
        }
    }

    /// The collapsed row's short answer.
    static func shortAnswer(_ who: WhoDoesMost?) -> String {
        guard let who else { return String(localized: "Not answered yet", table: "Home") }
        if who == .someoneElse { return String(localized: "Someone else", table: "Home") }
        return answer(who)
    }

    static func question(_ name: String) -> String {
        String(localized: "Who does most of the hands-on work at \(name)?", table: "Home")
    }

    /// "100 hours", "Record only", "Counts toward 750".
    static func trackValue(_ track: RentalTrack) -> String {
        switch track {
        case .ownTarget(let h): return String(localized: "\(h) hours", table: "Home")
        case .recordOnly: return String(localized: "Record only", table: "Home")
        case .sharedTotal(let h): return String(localized: "Counts toward \(h)", table: "Home")
        }
    }

    /// The reason printed under a diff row, for the track the app would use.
    static func reason(_ row: GoalCheckRow) -> String {
        switch row.proposed {
        case .ownTarget(let h): return RentalPlanWords.targetReason(whoDoesMost: row.whoDoesMost, hours: h)
        case .recordOnly(let r): return RentalPlanWords.reason(r)
        case .sharedTotal: return String(localized: "Every rental’s hours go into one total", table: "Home")
        }
    }

    /// The Switch button: names the rental when only one moves.
    static func switchTitle(_ rows: [GoalCheckRow]) -> String {
        let changed = rows.filter(\.changes)
        if changed.count == 1, let row = changed.first {
            switch row.proposed {
            case .ownTarget(let h): return String(localized: "Switch \(row.name) to \(h)", table: "Home")
            case .recordOnly: return String(localized: "Switch \(row.name) to record only", table: "Home")
            case .sharedTotal(let h): return String(localized: "Switch \(row.name) to \(h)", table: "Home")
            }
        }
        return String(localized: "Switch \(changed.count) rentals", table: "Home")
    }

    /// Under 750, grouping or a record goal the screen explains instead of asking.
    static func sharedExplanation(_ mode: RentalPlanMode) -> String {
        switch mode {
        case .shared(let h):
            return String(localized: "Every rental counts toward one \(h)-hour total, so there is nothing to set per rental. To track rentals one by one, change your goal.", table: "Home")
        case .record:
            return String(localized: "Your goal is to keep a record. Every rental’s hours are kept, with no target. To track a target, change your goal.", table: "Home")
        case .perRental:
            return ""
        }
    }
}

enum GoalCheckActions {
    /// "Keep what I have": the answers are saved, and every rental that would move is pinned to
    /// what it has now (a target keeps its number, a record stays a record).
    @MainActor
    static func keep(_ ctx: RentalPlanContext, draft: [UUID: WhoDoesMost], store: RentalPlanStore) {
        for row in GoalCheck.rows(ctx, draft: draft) where row.changes {
            switch row.current {
            case .ownTarget(let h): store.setOverride(.trackPinned(hours: h), for: row.propertyId)
            case .recordOnly: store.setOverride(.record, for: row.propertyId)
            case .sharedTotal: break
            }
        }
        saveAnswers(draft, store: store)
    }

    /// "Switch": the answers are saved and the targets work themselves out again.
    @MainActor
    static func switchToProposed(draft: [UUID: WhoDoesMost], store: RentalPlanStore) {
        saveAnswers(draft, store: store)
    }

    @MainActor
    static func saveAnswers(_ draft: [UUID: WhoDoesMost], store: RentalPlanStore) {
        for (id, who) in draft where store.whoDoesMost[id] != who { store.setWhoDoesMost(who, for: id) }
    }
}

// MARK: Telling the owner (toast)

enum RentalPlanAnnouncer {
    /// Compares with the last tracks and returns the sentence to show (nil: nothing moved).
    /// Pass the context taken AFTER the change.
    @MainActor
    @discardableResult
    static func announce(_ ctx: RentalPlanContext, store: RentalPlanStore = .shared, toasts: LHToastCenter? = .shared) -> String? {
        guard let sentence = store.reconcile(ctx) else { return nil }
        toasts?.show(LHToastSpec(kind: .success, message: sentence, identifier: "plan.toast"))
        return sentence
    }
}

// MARK: Inbox cleaner card

/// The answers already given on cleaner cards, so a card goes once it is answered. Scoped per
/// profile like the other setup answers.
@MainActor
enum CleanerFactInbox {
    static let answeredBaseKey = "LandlordHours.rentalPlan.cleanerFactsAnswered"

    /// The facts still waiting for a tap. The shipped source is the stub, which returns none.
    static func pending(source: CleanerFactSource, properties: [RentalProperty], answered: Set<String>) -> [CleanerFact] {
        source.facts(for: properties).filter { fact in
            properties.contains { $0.id == fact.propertyId } && !answered.contains(key(fact))
        }
    }

    static func key(_ fact: CleanerFact) -> String { "\(fact.propertyId.uuidString)|\(fact.eventTitle)" }

    static func answered(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: UserScope.key(answeredBaseKey)) ?? [])
    }

    static func markAnswered(_ fact: CleanerFact, defaults: UserDefaults = .standard) {
        var set = answered(defaults: defaults)
        set.insert(key(fact))
        defaults.set(Array(set).sorted(), forKey: UserScope.key(answeredBaseKey))
    }

    /// The three buttons write who does most here (or nothing for "Not sure" beyond the answer).
    enum Answer { case theyDoMore, iDoMore, notSure }

    static func who(for answer: Answer) -> WhoDoesMost {
        switch answer {
        case .theyDoMore: return .someoneElse
        case .iDoMore: return .me
        case .notSure: return .notSure
        }
    }

    /// The live source: the stub in a shipped build; DEBUG `-LHCleanerFact` injects one fact.
    static var source: CleanerFactSource {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LHCleanerFact") { return DebugCleanerFactSource() }
#endif
        return RentalPlanStore.shared.cleanerFacts
    }
}

#if DEBUG
/// One fact for captures and UI tests: a weekly "Turnover clean" at the first short-stay rental.
struct DebugCleanerFactSource: CleanerFactSource {
    func facts(for properties: [RentalProperty]) -> [CleanerFact] {
        guard let p = properties.first(where: { $0.propertyType == .str }) ?? properties.first else { return [] }
        return [CleanerFact(propertyId: p.id, propertyName: p.name, eventTitle: "Turnover clean")]
    }
}
#endif
