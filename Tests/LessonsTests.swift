import XCTest
import Combine
@testable import LandlordHours

// MARK: - Lessons content

final class LessonsContentTests: XCTestCase {
    private func loaded() throws -> [Lesson] { try LearnLibrary.loadLessons(bundle: .main) }

    func testThreeLessonsOfThreeCardsEndOnTheCPALine() throws {
        let lessons = try loaded()
        XCTAssertEqual(lessons.map(\.id), ["counts", "spouse", "log"])
        XCTAssertEqual(LearnLibrary.lessons, lessons, "The shared list is the bundle load")
        for lesson in lessons {
            XCTAssertEqual(lesson.cards.count, 3, lesson.id)
            XCTAssertEqual(lesson.minutes, 2)
            guard case .questions(let questions) = lesson.cards[2].body else { return XCTFail("\(lesson.id): the last card is questions") }
            XCTAssertEqual(questions.count, 3, lesson.id)
            XCTAssertEqual(lesson.cards[2].title, "Talk to your CPA")
            for card in lesson.cards.dropLast() {
                if case .questions = card.body { XCTFail("\(lesson.id): only the last card asks questions") }
            }
        }
    }

    func testNoRawKeysStraightApostrophesOrRetiredWords() throws {
        let banned = ["qualif", "audit-proof", "audit-ready", "defensible", "evidence", "proof", "compliance", "tax-ready", "guarantee"]
        for lesson in try loaded() {
            var lines = [lesson.title]
            for card in lesson.cards {
                lines += [card.title, card.text] + (card.note.map { [$0] } ?? [])
                switch card.body {
                case .counts(let yes, let no): lines += yes + no
                case .lines(let rows): lines += rows.flatMap { [$0.label, $0.value] }
                case .questions(let questions): lines += questions
                case .none: break
                }
            }
            for line in lines {
                XCTAssertFalse(line.isEmpty)
                XCTAssertFalse(line.hasPrefix("lesson."), "A raw key reached the screen: \(line)")
                XCTAssertFalse(line.contains("'"), "Use curly apostrophes: \(line)")
                for word in banned {
                    XCTAssertNil(line.range(of: "\\b\(word)", options: [.regularExpression, .caseInsensitive]), "“\(word)” in: \(line)")
                }
            }
        }
    }

    /// The critic's blocker: spouse hours add up for the 500-hour test whether or not you file jointly,
    /// and never for the 750.
    func testSpouseRulesAreStatedCorrectly() throws {
        let spouse = try XCTUnwrap(try loaded().first { $0.id == "spouse" })
        let first = spouse.cards[0], second = spouse.cards[1]
        XCTAssertTrue(first.text.contains("Your hours don’t add together for the 750"))
        XCTAssertTrue(second.text.contains("add up, on each rental"))
        for card in spouse.cards {
            XCTAssertFalse((card.text + card.title + (card.note ?? "")).localizedCaseInsensitiveContains("jointly"),
                           "Spouse hours count for the 500 either way; no filing-status condition")
            XCTAssertFalse((card.text + (card.note ?? "")).localizedCaseInsensitiveContains("file"))
        }
        guard case .lines(let rows) = second.body else { return XCTFail("500-hour card shows value lines") }
        XCTAssertEqual(rows.last?.value, "530h together")
    }

    func testEveryLessonCarriesTheNotAdviceKey() {
        let line = LearnLibrary.notAdvice
        XCTAssertEqual(line, "General learning, not tax advice.")
        XCTAssertNotEqual(line, "learn.notAdvice")
    }

    func testMissingManifestThrows() {
        XCTAssertThrowsError(try LearnLibrary.loadLessons(bundle: Bundle(for: Self.self))) { error in
            XCTAssertEqual(error as? LearnLibrary.LoadError, .missingManifest)
        }
    }

    func testFormatFillsPositionalArguments() {
        XCTAssertEqual(LearnLibrary.format("lesson.cardOf", 2, 3), "Card 2 of 3")
        XCTAssertEqual(LearnLibrary.format("lesson.card.title", 420, 750), "You’re at 420 of 750. Here’s what usually counts.")
        XCTAssertEqual(LearnLibrary.format("lesson.nope"), "", "A missing key is empty, never the key")
    }
}

// MARK: - The note from the person's own log

final class LessonInsightsTests: XCTestCase {
    func testNamesTheTwoBiggestKindsOfWorkWhenTheyAreMoreThanHalf() {
        let share = LessonInsights.share(entries: [(.repairs, 200), (.leasing, 120), (.bookkeeping, 60), (.travel, 40)])
        XCTAssertEqual(share, LessonInsights.Share(hours: 420, phrase: "repairs and showings"))
    }

    func testSaysNothingWhenTheTopTwoAreNotMoreThanHalf() {
        let entries: [(ActivityCategory, Double)] = [(.repairs, 30), (.leasing, 30), (.bookkeeping, 30), (.travel, 30), (.legal, 30), (.insurance, 30)]
        XCTAssertNil(LessonInsights.share(entries: entries.map { (category: $0.0, hours: $0.1) }))
    }

    func testInvestorWorkIsNeverCountedOrNamed() {
        XCTAssertNil(LessonInsights.share(entries: [(.investing, 40), (.financing, 10)]))
        let share = LessonInsights.share(entries: [(.repairs, 10), (.investing, 100)])
        XCTAssertEqual(share, LessonInsights.Share(hours: 10, phrase: "repairs"), "Investor hours stay out of the total")
    }

    func testEmptyAndBadHoursGiveNothing() {
        XCTAssertNil(LessonInsights.share(entries: []))
        XCTAssertNil(LessonInsights.share(entries: [(.repairs, .nan), (.leasing, -4), (.management, 0.4)]))
    }
}

// MARK: - Milestones, read state, access

final class LessonMilestoneTests: XCTestCase {
    private let ids = ["counts", "spouse", "log"]

    private func card(_ hours: Double, goal: Int = 750, is750: Bool = true, handled: Int = 0, read: Set<String> = []) -> LearnMilestone.Card? {
        LearnMilestone.card(hours: hours, goal: goal, wantsGoal750: is750, handled: handled, read: read, lessonIDs: ids)
    }

    func testReachedIsTheHighestMilestoneAtOrBelowTheHours() {
        XCTAssertNil(LearnMilestone.reached(hours: 0))
        XCTAssertNil(LearnMilestone.reached(hours: 99.9))
        XCTAssertEqual(LearnMilestone.reached(hours: 100), 100)
        XCTAssertEqual(LearnMilestone.reached(hours: 420), 400)
        XCTAssertEqual(LearnMilestone.reached(hours: 2_000), 750)
        XCTAssertNil(LearnMilestone.reached(hours: .nan))
        XCTAssertNil(LearnMilestone.reached(hours: .infinity), "Infinite hours are not a milestone")
    }

    func testTheCardShowsOnlyAtAMilestoneThatIsNotHandled() {
        XCTAssertNil(card(60), "Below the first milestone")
        let shown = card(420)
        XCTAssertEqual(shown, LearnMilestone.Card(milestone: 400, hours: 420, goal: 750, lessonID: "counts", isFirstLesson: true))
        XCTAssertNil(card(420, handled: 400), "Dismissed or read")
        XCTAssertEqual(card(520, handled: 400)?.milestone, 500, "The next milestone brings it back")
    }

    func testOnlyForTheSevenFiftyGoalAndWhileALessonIsUnread() {
        XCTAssertNil(card(420, is750: false))
        XCTAssertNil(card(420, goal: 0))
        XCTAssertNil(card(420, read: Set(ids)), "Everything read: nothing to offer")
        let next = card(420, read: ["counts"])
        XCTAssertEqual(next?.lessonID, "spouse")
        XCTAssertEqual(next?.isFirstLesson, false)
    }

    func testAccessRouting() {
        XCTAssertEqual(LessonAccess.route(lessonID: "counts", firstLessonID: "counts", allowed: true), .full)
        XCTAssertEqual(LessonAccess.route(lessonID: "spouse", firstLessonID: "counts", allowed: true), .full)
        XCTAssertEqual(LessonAccess.route(lessonID: "counts", firstLessonID: "counts", allowed: false), .preview)
        XCTAssertEqual(LessonAccess.route(lessonID: "spouse", firstLessonID: "counts", allowed: false), .paywall)
    }
}

final class LessonProgressStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "lesson-progress-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testReadStateIsPerProfile() {
        var profile = "a."
        let store = LessonProgressStore(defaults: defaults, key: { profile + $0 })
        store.markRead("counts")
        store.handleMilestone(400)
        XCTAssertTrue(store.isRead("counts"))
        XCTAssertEqual(store.handledMilestone, 400)
        profile = "b."
        XCTAssertFalse(store.isRead("counts"), "Another profile starts with nothing read")
        XCTAssertEqual(store.handledMilestone, 0)
        profile = "a."
        XCTAssertEqual(store.readIDs, ["counts"])
    }

    func testMilestoneOnlyMovesUpAndReadIsIdempotent() {
        let store = LessonProgressStore(defaults: defaults, key: { "t.\($0)" })
        store.handleMilestone(500)
        store.handleMilestone(250)
        XCTAssertEqual(store.handledMilestone, 500)
        store.markRead("log"); store.markRead("log")
        XCTAssertEqual(store.readIDs, ["log"])
        store.reset()
        XCTAssertTrue(store.readIDs.isEmpty)
        XCTAssertEqual(store.handledMilestone, 0)
    }

    func testChangesNotifyObservers() {
        let store = LessonProgressStore(defaults: defaults, key: { "t.\($0)" })
        var count = 0
        let token = store.objectWillChange.sink { count += 1 }
        store.markRead("counts")
        store.markRead("counts")
        store.handleMilestone(100)
        XCTAssertEqual(count, 2, "One change per real change")
        token.cancel()
    }
}
