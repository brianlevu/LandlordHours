import Foundation

// MARK: - Lesson progress and the Today milestone card (2.3, package C)
//
// Per profile (`UserScope.key`):
//   learn.lessonsRead.v1       lesson ids whose last card was reached
//   learn.milestoneHandled.v1  the highest milestone (hours) the person read or dismissed
// The store reads and writes defaults on every call, so a profile switch needs no reload. It never
// stores a score or a date: only which lessons were read.

final class LessonProgressStore: ObservableObject {
    static let shared = LessonProgressStore()

    private let defaults: UserDefaults
    private let key: (String) -> String

    init(defaults: UserDefaults = .standard, key: @escaping (String) -> String = { UserScope.key($0) }) {
        self.defaults = defaults
        self.key = key
        #if DEBUG
        // `-LHLearnReset` starts a UI-test launch with nothing read and no milestone handled.
        if defaults === UserDefaults.standard, ProcessInfo.processInfo.arguments.contains("-LHLearnReset") { reset() }
        // `-LHLearnRead counts,spouse` then marks those lessons read.
        let args = ProcessInfo.processInfo.arguments
        if defaults === UserDefaults.standard, let i = args.firstIndex(of: "-LHLearnRead"), args.indices.contains(i + 1) {
            args[i + 1].split(separator: ",").forEach { markRead(String($0)) }
        }
        #endif
    }

    private var readKey: String { key("learn.lessonsRead.v1") }
    private var handledKey: String { key("learn.milestoneHandled.v1") }

    var readIDs: Set<String> { Set(defaults.stringArray(forKey: readKey) ?? []) }

    func isRead(_ id: String) -> Bool { readIDs.contains(id) }

    func markRead(_ id: String) {
        var ids = readIDs
        guard ids.insert(id).inserted else { return }
        defaults.set(ids.sorted(), forKey: readKey)
        objectWillChange.send()
    }

    /// The highest milestone already read or dismissed (0 = none).
    var handledMilestone: Int { defaults.integer(forKey: handledKey) }

    func handleMilestone(_ milestone: Int) {
        guard milestone > handledMilestone else { return }
        defaults.set(milestone, forKey: handledKey)
        objectWillChange.send()
    }

    /// Clears this profile's progress (tests, the DEBUG reset).
    func reset() {
        defaults.removeObject(forKey: readKey)
        defaults.removeObject(forKey: handledKey)
        objectWillChange.send()
    }
}

// MARK: - Milestones and the card's state (pure)

enum LearnMilestone {
    /// Hours at which the Today card may appear: it shows once per step, never on a timer.
    static let hours: [Int] = [100, 250, 400, 500, 650, 750]

    /// The highest milestone `hours` has reached, or nil below the first.
    static func reached(hours current: Double) -> Int? {
        guard current.isFinite else { return nil }
        return hours.last { Double($0) <= current }
    }

    /// The hours the card and its milestones read. The 750-hour test is per person across every rental,
    /// never per rental: this is the REPS participant's countable hours over all rentals, the same engine
    /// value Reports and the PDF use, whichever rental Today is focused on.
    @MainActor
    static func countedHours(app: AppViewModel, year: Int = Calendar.current.component(.year, from: Date())) -> Double {
        app.houseCountableHours(goal: .reps750, year: year)
    }

    /// What the Today card shows.
    struct Card: Equatable {
        let milestone: Int
        let hours: Int
        let goal: Int
        /// The lesson the button opens: the first one not read yet.
        let lessonID: String
        /// True for the first lesson, whose line is "Here's what usually counts".
        let isFirstLesson: Bool
    }

    /// The card, or nil: it shows only at a milestone the person hasn't read or dismissed, only for the
    /// 750-hour goal, and only while a lesson is unread.
    static func card(hours current: Double, goal: Int, wantsGoal750: Bool, handled: Int,
                     read: Set<String>, lessonIDs: [String]) -> Card? {
        guard wantsGoal750, goal > 0, let milestone = reached(hours: current), milestone > handled,
              let next = lessonIDs.first(where: { !read.contains($0) }) else { return nil }
        return Card(milestone: milestone, hours: Int(current.rounded(.down)), goal: goal,
                    lessonID: next, isFirstLesson: next == lessonIDs.first)
    }
}

// MARK: - Who sees what (pure)

enum LessonAccess: Equatable {
    /// Every card.
    case full
    /// Card 1 only, then the paywall (a free person's taste of lesson 1).
    case preview
    /// The paywall straight away.
    case paywall

    static func route(lessonID: String, firstLessonID: String?, allowed: Bool) -> LessonAccess {
        if allowed { return .full }
        return lessonID == firstLessonID ? .preview : .paywall
    }
}
