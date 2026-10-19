import XCTest
@testable import LandlordHours

/// WP-H: the house maps countable hours to keyframes and words. Every boundary the brief names
/// (99.99, 100, 499.99, 500, 750, 750.01) for every goal, plus the 1h empty-lot line.
final class HouseProgressTests: XCTestCase {

    private func p(_ hours: Double, _ goal: HouseGoal = .reps750) -> HouseProgress {
        HouseProgress(hours: hours, goal: goal)
    }

    // MARK: Keyframes (identical for every goal: one absolute scale)

    func testKeyframeBoundariesForEveryGoal() {
        let expected: [(Double, HouseKeyframe)] = [
            (0, .k00_lot),
            (0.99, .k00_lot),
            (1, .k00_lot),
            (99.99, .k00_lot),
            (100, .k01_slab),
            (139.99, .k01_slab),
            (140, .k02_frame010),
            (120, .k01_slab),
            (212, .k03_frame020),
            (460, .k10_frame090),
            (499.99, .k10_frame090),
            (500, .k12_roof),
            (549.99, .k12_roof),
            (550, .k13_siding020),
            (680, .k15_siding060),
            (749.99, .k16_siding080),
            (750, .k17_siding100),
            (750.01, .k18_finished),
            (751, .k18_finished),
            (5000, .k18_finished),
        ]
        for goal in HouseGoal.allCases {
            for (hours, keyframe) in expected {
                XCTAssertEqual(p(hours, goal).keyframe, keyframe, "\(hours)h \(goal)")
            }
        }
    }

    func testFramingNeverRunsAheadOfHours() {
        // Floor rule: each framing keyframe only once its full 40h share is confirmed.
        for (i, keyframe) in HouseKeyframe.framing.dropLast().enumerated() {
            let start = 100 + Double(i + 1) * 40
            XCTAssertEqual(HouseProgress.keyframe(for: start), keyframe)
            XCTAssertNotEqual(HouseProgress.keyframe(for: start - 0.01), keyframe)
        }
        // k11 (frame complete, no roof) is never a resting keyframe; it is the 500h "before" frame.
        let resting = Set(stride(from: 0.0, through: 900, by: 0.25).map(HouseProgress.keyframe(for:)))
        XCTAssertFalse(resting.contains(.k11_frame100))
        XCTAssertEqual(resting.count, HouseKeyframe.allCases.count - 1)
    }

    func testKeyframesAreMonotonic() {
        var last = 0
        for h in stride(from: 0.0, through: 800, by: 0.5) {
            let index = HouseProgress.keyframe(for: h).index
            XCTAssertGreaterThanOrEqual(index, last, "\(h)h went backwards")
            last = index
        }
    }

    func testBadInputDrawsNothing() {
        XCTAssertEqual(p(-5).keyframe, .k00_lot)
        XCTAssertEqual(p(-5).hours, 0)
        XCTAssertEqual(p(.nan).keyframe, .k00_lot)
        XCTAssertEqual(p(.infinity).hours, 0)
    }

    // MARK: Stages

    func testStageBoundaries() {
        XCTAssertEqual(p(0).stage, .emptyLot)
        XCTAssertEqual(p(0.99).stage, .emptyLot)
        XCTAssertEqual(p(1).stage, .groundwork)
        XCTAssertEqual(p(99.99).stage, .groundwork)
        XCTAssertEqual(p(100).stage, .slab)
        XCTAssertEqual(p(140).stage, .framing)
        XCTAssertEqual(p(499.99).stage, .framing)
        XCTAssertEqual(p(500).stage, .roofed)
        XCTAssertEqual(p(550).stage, .siding)
        XCTAssertEqual(p(750).stage, .siding)
        XCTAssertEqual(p(750.01).stage, .finished)
        XCTAssertEqual(p(750.01).stage.spokenName, "House finished")
    }

    // MARK: Next milestone

    func testNextStepLabelAtEveryBoundaryPerGoal() {
        // REPS: the keys are the finish.
        XCTAssertEqual(p(99.99).nextMilestoneLabel, "Foundation at 100h")
        XCTAssertEqual(p(100).nextMilestoneLabel, "Roof at 500h")
        XCTAssertEqual(p(499.99).nextMilestoneLabel, "Roof at 500h")
        XCTAssertEqual(p(500).nextMilestoneLabel, "Keys after 750h")
        XCTAssertEqual(p(750).nextMilestoneLabel, "Keys after 750h")
        XCTAssertEqual(p(750.01).nextMilestoneLabel, "House finished")
        XCTAssertNil(p(750.01).nextStep)
        // MP 500: keys on the roofed house, then the house keeps building.
        XCTAssertEqual(p(99.99, .mp500).nextMilestoneLabel, "Foundation at 100h")
        XCTAssertEqual(p(499.99, .mp500).nextMilestoneLabel, "Roof at 500h")
        XCTAssertEqual(p(500, .mp500).nextMilestoneLabel, "Keys after 500h")
        XCTAssertEqual(p(500.01, .mp500).nextMilestoneLabel, "Finished after 750h")
        XCTAssertEqual(p(750, .mp500).nextMilestoneLabel, "Finished after 750h")
        XCTAssertNil(p(750.01, .mp500).nextStep)
        // MP 100: keys at the slab.
        XCTAssertEqual(p(99.99, .mp100).nextMilestoneLabel, "Foundation at 100h")
        XCTAssertEqual(p(100, .mp100).nextMilestoneLabel, "Keys after 100h")
        XCTAssertEqual(p(100.01, .mp100).nextMilestoneLabel, "Roof at 500h")
        XCTAssertEqual(p(500, .mp100).nextMilestoneLabel, "Finished after 750h")
        XCTAssertNil(p(750.01, .mp100).nextStep)
    }

    func testCelebrationsUseTheOwnersGoalForTheKeys() {
        XCTAssertEqual(HouseProgress.celebrations(from: 99, to: 100, goal: .reps750), [.stage(.foundation100)])
        XCTAssertEqual(HouseProgress.celebrations(from: 499, to: 500, goal: .reps750), [.stage(.roof500)])
        XCTAssertEqual(HouseProgress.celebrations(from: 750, to: 751, goal: .reps750), [.goalMet(.reps750)])
        XCTAssertEqual(HouseProgress.celebrations(from: 749, to: 750, goal: .reps750), [])
        // MP 500: the roof lands AT 500, the keys come past it.
        XCTAssertEqual(HouseProgress.celebrations(from: 499, to: 500, goal: .mp500), [.stage(.roof500)])
        XCTAssertEqual(HouseProgress.celebrations(from: 500, to: 501, goal: .mp500), [.goalMet(.mp500)])
        XCTAssertEqual(HouseProgress.celebrations(from: 499, to: 501, goal: .mp500), [.goalMet(.mp500)])
        XCTAssertEqual(HouseProgress.celebrations(from: 750, to: 751, goal: .mp500), [.stage(.keys750)])
        // MP 100: keys at the slab.
        XCTAssertEqual(HouseProgress.celebrations(from: 99, to: 101, goal: .mp100), [.goalMet(.mp100)])
        XCTAssertEqual(HouseProgress.celebrations(from: 90, to: 600, goal: .mp100), [.goalMet(.mp100), .stage(.roof500)])
        XCTAssertEqual(HouseProgress.celebrations(from: 600, to: 400, goal: .mp100), [])
    }

    func testHoursToNextMilestone() {
        XCTAssertEqual(p(212).hoursToNextMilestone, 288)
        XCTAssertEqual(p(99.5).hoursToNextMilestone ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(p(700).hoursToNextMilestone, 50)
        // Exactly 750: the keys need MORE than 750, so there is still an hour to go.
        XCTAssertEqual(p(750).hoursToNextMilestone, 1)
        XCTAssertNil(p(751).hoursToNextMilestone)
    }

    // MARK: Goals

    func testGoalMetUsesMoreThanTheTarget() {
        XCTAssertFalse(p(750, .reps750).isGoalMet)
        XCTAssertTrue(p(750.01, .reps750).isGoalMet)
        XCTAssertFalse(p(499.99, .mp500).isGoalMet)
        XCTAssertFalse(p(500, .mp500).isGoalMet)
        XCTAssertTrue(p(500.01, .mp500).isGoalMet)
        XCTAssertFalse(p(99.99, .mp100).isGoalMet)
        XCTAssertFalse(p(100, .mp100).isGoalMet)
        XCTAssertTrue(p(100.01, .mp100).isGoalMet)
    }

    func testGoalMilestonesAndTargets() {
        XCTAssertEqual(HouseGoal.reps750.milestone, .keys750)
        XCTAssertEqual(HouseGoal.mp500.milestone, .roof500)
        XCTAssertEqual(HouseGoal.mp100.milestone, .foundation100)
        XCTAssertEqual(HouseGoal.reps750.targetHours, 750)
        XCTAssertEqual(HouseGoal.mp500.targetHours, 500)
        XCTAssertEqual(HouseGoal.mp100.targetHours, 100)
        XCTAssertEqual(HouseGoal(.reps), .reps750)
        XCTAssertEqual(HouseGoal(.both), .reps750)
        XCTAssertEqual(HouseGoal(.str), .mp100)
        XCTAssertEqual(HouseGoal(argument: "mp500"), .mp500)
        XCTAssertEqual(HouseGoal(argument: "REPS"), .reps750)
        XCTAssertNil(HouseGoal(argument: "nope"))
    }

    // MARK: Milestone crossings

    func testMilestonesCrossed() {
        XCTAssertEqual(HouseProgress.milestonesCrossed(from: 99.99, to: 100), [.foundation100])
        XCTAssertEqual(HouseProgress.milestonesCrossed(from: 98, to: 99.99), [])
        XCTAssertEqual(HouseProgress.milestonesCrossed(from: 499.99, to: 500), [.roof500])
        XCTAssertEqual(HouseProgress.milestonesCrossed(from: 498, to: 751), [.roof500, .keys750])
        XCTAssertEqual(HouseProgress.milestonesCrossed(from: 749, to: 750), [], "750 is not MORE than 750")
        XCTAssertEqual(HouseProgress.milestonesCrossed(from: 750, to: 750.01), [.keys750])
        XCTAssertEqual(HouseProgress.milestonesCrossed(from: 600, to: 400), [], "deleting hours never celebrates")
        XCTAssertEqual(HouseProgress.milestonesCrossed(from: 0, to: 900), HouseMilestone.allCases)
    }

    // MARK: Accessibility words

    func testAccessibilityLabelStatesHoursGoalAndNextMilestone() {
        let label = p(212).accessibilityLabel
        XCTAssertTrue(label.contains("212 of 750 hours"), label)
        XCTAssertTrue(label.contains("REPS goal"), label)
        XCTAssertTrue(label.contains("roof at 500 hours"), label)
        XCTAssertTrue(label.contains("288 hours to go"), label)
        XCTAssertFalse(label.contains("qualif"), "never say qualified")

        let mp = p(120, .mp500).accessibilityLabel
        XCTAssertTrue(mp.contains("120 of 500 hours"), mp)
        XCTAssertTrue(mp.contains("material participation"), mp)

        let done = p(751).accessibilityLabel
        XCTAssertTrue(done.contains("Every stage is built"), done)
        XCTAssertTrue(p(500, .mp500).accessibilityLabel.contains("keys after 500 hours"))
        XCTAssertTrue(done.contains("based on your records"), done)

        XCTAssertTrue(p(499.6).accessibilityLabel.contains("1 hour to go"))
        XCTAssertTrue(p(0).accessibilityLabel.contains("An empty lot"))
    }

    func testWholeHoursRoundDown() {
        XCTAssertEqual(p(499.99).wholeHours, 499)
        XCTAssertEqual(p(750.01).wholeHours, 750)
    }

    // MARK: Countable hours

    func testCountableHoursExcludeInvestorTasksAndUnjointSpouse() {
        let property = UUID()
        let cal = Calendar(identifier: .gregorian)
        let d2026 = cal.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let d2025 = cal.date(from: DateComponents(year: 2025, month: 5, day: 1))!
        let entries = [
            TimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs, hours: 10, date: d2026),
            TimeEntry(propertyId: property, participant: .spouse, category: .leasing, hours: 5, date: d2026),
            TimeEntry(propertyId: property, participant: .selfParticipant, category: .investing, hours: 7, date: d2026),
            TimeEntry(propertyId: property, participant: .selfParticipant, category: .financing, hours: 2, date: d2026),
            TimeEntry(propertyId: property, participant: .selfParticipant, category: .contractNegotiation, hours: 1, date: d2026),
            TimeEntry(propertyId: property, participant: .selfParticipant, category: .repairs, hours: 3, date: d2025),
        ]
        XCTAssertEqual(HouseProgress.countableHours(entries: entries, year: 2026, includeSpouse: false, calendar: cal), 10)
        XCTAssertEqual(HouseProgress.countableHours(entries: entries, year: 2026, includeSpouse: true, calendar: cal), 15)
        XCTAssertEqual(HouseProgress.countableHours(entries: entries, year: 2025, includeSpouse: true, calendar: cal), 3)
        XCTAssertEqual(HouseProgress.countableHours(entries: [], year: 2026, includeSpouse: true, calendar: cal), 0)
    }

    // MARK: Keyframe metadata

    func testManifestStagesAndAssetNames() {
        XCTAssertEqual(HouseKeyframe.allCases.count, 19)
        XCTAssertEqual(HouseKeyframe.k14_siding040.builtImageName, "bp_house_k14_siding040_built")
        XCTAssertEqual(HouseKeyframe.k14_siding040.linesImageName, "bp_house_k14_siding040_lines")
        XCTAssertEqual(HouseKeyframe.allCases.map(\.manifestStage), [0, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 4, 4, 4, 4, 4, 5])
        XCTAssertEqual(HouseKeyframe.confirmSequenceBase, .k14_siding040)
        XCTAssertNotNil(HouseKeyframe.k15_siding060.confirmBoardOffset)
        XCTAssertNil(HouseKeyframe.k00_lot.confirmBoardOffset)
        XCTAssertNil(HouseKeyframe.k04_frame030.confirmBoardOffset)
        XCTAssertNil(HouseKeyframe.k18_finished.confirmBoardOffset)
    }
}

