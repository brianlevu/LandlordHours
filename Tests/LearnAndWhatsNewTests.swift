import XCTest
@testable import LandlordHours

// MARK: - Learning center content

final class LearnLibraryTests: XCTestCase {
    private func loaded() throws -> [LearnArticle] { try LearnLibrary.load(bundle: .main) }

    func testManifestLoadsEveryArticleFromTheCatalog() throws {
        let articles = try loaded()
        XCTAssertEqual(articles.count, 10)
        XCTAssertEqual(Set(articles.map(\.id)).count, articles.count, "Article ids are unique")
        XCTAssertEqual(LearnLibrary.shared, articles, "The shared list is the bundle load")
        for article in articles {
            XCTAssertFalse(article.title.isEmpty)
            XCTAssertGreaterThanOrEqual(article.paragraphs.count, 3, article.id)
            for text in [article.title] + article.paragraphs {
                XCTAssertFalse(text.hasPrefix("learn."), "A raw key reached the screen: \(text)")
                XCTAssertFalse(text.contains("'"), "Use curly apostrophes: \(text)")
            }
        }
    }

    func testStartHereIsTheThreeApprovedReadsInOrder() throws {
        let start = try loaded().filter { $0.group == .start }
        XCTAssertEqual(start.map(\.title), ["What the 750-hour goal means", "What makes a good entry", "Short stays and long stays"])
        XCTAssertEqual(start.map(\.number), [1, 2, 3])
        let all = try loaded().filter { $0.group == .all }
        XCTAssertEqual(all.map(\.number), Array(1...all.count))
        XCTAssertEqual(all.first?.title, "The 50% rule")
    }

    func testCopyNeverClaimsAnOutcomeOrUsesRetiredWords() throws {
        let banned = ["qualif", "audit-proof", "audit proof", "audit-ready", "defensible", "evidence",
                      "tax-ready", "LTR", "STR", "guarantee"]
        let lines = try loaded().flatMap { [$0.title] + $0.paragraphs }
            + ["learn.hero.eyebrow", "learn.hero.line", "learn.disclaimer", "learn.sources"].map { try LearnLibrary.text($0) }
        for line in lines {
            for word in banned {
                let options: String.CompareOptions = word == word.uppercased() ? [] : [.caseInsensitive]
                XCTAssertNil(line.range(of: "\\b\(word)", options: options.union(.regularExpression)), "“\(word)” in: \(line)")
            }
            XCTAssertNil(line.range(of: "you (qualify|are a real estate professional)", options: [.regularExpression, .caseInsensitive]),
                         "Never tells the reader where they stand: \(line)")
        }
        XCTAssertEqual(try LearnLibrary.text("learn.disclaimer"), "General information, not tax advice. Your tax pro has the final word.")
    }

    func testSpouseRulesAreStatedCorrectly() throws {
        let spouse = try XCTUnwrap(try loaded().first { $0.id == "spouse-hours" }).paragraphs.joined(separator: " ")
        XCTAssertTrue(spouse.contains("one spouse has to pass both alone"), "REPS is one spouse alone")
        XCTAssertTrue(spouse.contains("can’t combine your hours to reach 750"))
        XCTAssertTrue(spouse.contains("both spouses’ hours on a rental count together"), "Material participation combines")
        let goal = try XCTUnwrap(try loaded().first { $0.id == "goal-750" }).paragraphs.joined(separator: " ")
        XCTAssertTrue(goal.contains("one of you has to pass both tests alone"))
        let mp = try XCTUnwrap(try loaded().first { $0.id == "material-participation" }).paragraphs.joined(separator: " ")
        XCTAssertTrue(mp.contains("both spouses’ hours count together"))
    }

    func testMissingKeyOrManifestThrowsInsteadOfShowingAKey() {
        XCTAssertThrowsError(try LearnLibrary.text("learn.nope.title")) { error in
            XCTAssertEqual(error as? LearnLibrary.LoadError, .missingString("learn.nope.title"))
        }
        XCTAssertEqual(LearnLibrary.line("learn.nope.title"), "", "Fixed lines fall back to empty, never the key")
        XCTAssertThrowsError(try LearnLibrary.load(bundle: Bundle(for: Self.self))) { error in
            XCTAssertEqual(error as? LearnLibrary.LoadError, .missingManifest)
        }
    }

    func testLookupById() {
        XCTAssertEqual(LearnLibrary.article(id: "grouping")?.title, "Grouping your rentals")
        XCTAssertNil(LearnLibrary.article(id: "str-vs-ltr"), "The 1.x ids are gone")
    }
}

// MARK: - What's new: the house at the upgrader's real stage, shown once

@MainActor
final class WhatsNewHouseTests: CaptureTestCase {
    private var savedSpouseTracking = true
    private var savedGoal: HouseGoal = .reps750

    override func setUp() async throws {
        try await super.setUp()
        savedSpouseTracking = TaxProfileManager.shared.spouseTracking
        savedGoal = GoalManager.shared.houseGoal
    }

    override func tearDown() async throws {
        TaxProfileManager.shared.spouseTracking = savedSpouseTracking
        GoalManager.shared.setHouseGoal(savedGoal)
        try await super.tearDown()
    }

    private func add(_ vm: AppViewModel, _ property: UUID, _ hours: Double, _ who: Participant = .selfParticipant) {
        vm.addTimeEntry(propertyId: property, participant: who, category: .repairs, hours: hours, date: Date(), notes: "")
    }

    func testREPSUpgraderSeesTheirOwnHoursOnlyAsTheHouse() {
        let (vm, property) = makeViewModel()
        GoalManager.shared.setHouseGoal(.reps750)
        TaxProfileManager.shared.spouseTracking = true    // even tracked jointly, REPS is one spouse alone
        add(vm, property, 312)
        add(vm, property, 300, .spouse)

        let input = OnbWhatsNewSheet.houseInput(for: vm)
        XCTAssertEqual(input.goal, .reps750)
        XCTAssertEqual(input.hours, 312, accuracy: 0.001, "The spouse's 300h never build your REPS house")
        XCTAssertEqual(HouseProgress(hours: input.hours, goal: input.goal).keyframe, HouseProgress.keyframe(for: 312))
        let line = OnbWhatsNewHouseStep.stageLine(hours: input.hours, goal: input.goal)
        XCTAssertTrue(line.hasPrefix("312h · "), line)
        XCTAssertFalse(line.contains("612"), line)
    }

    func testMaterialParticipationUpgraderCombinesSpouseWhenJoint() {
        let (vm, property) = makeViewModel()
        GoalManager.shared.setHouseGoal(.mp500)
        add(vm, property, 200)
        add(vm, property, 150, .spouse)

        TaxProfileManager.shared.spouseTracking = true
        XCTAssertEqual(OnbWhatsNewSheet.houseInput(for: vm).hours, 350, accuracy: 0.001)
        TaxProfileManager.shared.spouseTracking = false
        XCTAssertEqual(OnbWhatsNewSheet.houseInput(for: vm).hours, 200, accuracy: 0.001)
    }

    func testStageLineForAnEmptyRecordStartsAtZero() {
        let line = OnbWhatsNewHouseStep.stageLine(hours: 0, goal: .reps750)
        XCTAssertTrue(line.hasPrefix("0h · "), line)
        XCTAssertEqual(OnbWhatsNewHouseStep.stageLine(hours: -4, goal: .reps750), line, "Bad input never draws hours")
    }

    func testWhatsNewShowsOnceToUpgradersOnly() {
        let defaults = UserDefaults(suiteName: "whatsnew-\(UUID().uuidString)")!
        let user = "local-wn-\(UUID().uuidString.prefix(6))"
        XCTAssertFalse(CaptureOptIn.shouldShowWhatsNew(userId: nil, hasCompletedOnboarding: true, defaults: defaults, arguments: []),
                       "No profile, no sheet")
        XCTAssertFalse(CaptureOptIn.shouldShowWhatsNew(userId: user, hasCompletedOnboarding: false, defaults: defaults, arguments: []),
                       "New users answer in onboarding")
        XCTAssertTrue(CaptureOptIn.shouldShowWhatsNew(userId: user, hasCompletedOnboarding: true, defaults: defaults, arguments: []))
        CaptureOptIn.markWhatsNewSeen(userId: user, defaults: defaults)
        XCTAssertFalse(CaptureOptIn.shouldShowWhatsNew(userId: user, hasCompletedOnboarding: true, defaults: defaults, arguments: []),
                       "Seen once (finished or swiped away), never again")
        XCTAssertFalse(CaptureOptIn.shouldShowWhatsNew(userId: user, hasCompletedOnboarding: true, defaults: defaults,
                                                       arguments: [CaptureOptIn.showWhatsNewArgument]),
                       "Even a forced test launch respects seen")
        let other = "local-wn-other"
        XCTAssertTrue(CaptureOptIn.shouldShowWhatsNew(userId: other, hasCompletedOnboarding: true, defaults: defaults, arguments: []),
                      "Seen is per profile")
    }

    func testUpgradeSequenceLeadsWithTheHouse() {
        XCTAssertEqual(OnbRouting.upgradeSequence.first, .wnHouse)
    }
}
