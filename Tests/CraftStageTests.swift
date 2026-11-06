import XCTest
@testable import LandlordHours

/// Plan package 0a: the one stage function, the H1 placement table and hero sizes, the motion
/// switch, the "All rentals" totals, the drop ledger and the toast placement.
final class CraftStageTests: XCTestCase {

    // MARK: The one stage function (standard §H.3)

    func testThresholdsAreSharesOfTheGoal() {
        // (goal, the first hour of frame70, framing, half, complete)
        let table: [(Double, Double, Double, Double)] = [(100, 20, 47, 60), (500, 100, 235, 300), (750, 150, 352.5, 450)]
        for (goal, f70, framing, half) in table {
            XCTAssertEqual(CraftStage.stage(hours: 0, goal: goal), .started)
            XCTAssertEqual(CraftStage.stage(hours: f70 - 0.01, goal: goal), .started)
            XCTAssertEqual(CraftStage.stage(hours: f70, goal: goal), .frame70)
            XCTAssertEqual(CraftStage.stage(hours: framing - 0.01, goal: goal), .frame70)
            XCTAssertEqual(CraftStage.stage(hours: framing, goal: goal), .framing)
            XCTAssertEqual(CraftStage.stage(hours: half - 0.01, goal: goal), .framing)
            XCTAssertEqual(CraftStage.stage(hours: half, goal: goal), .half)
            XCTAssertEqual(CraftStage.stage(hours: goal - 0.01, goal: goal), .half)
            XCTAssertEqual(CraftStage.stage(hours: goal, goal: goal), .complete)
            XCTAssertEqual(CraftStage.stage(hours: goal * 3, goal: goal), .complete)
        }
    }

    func testBadInputDrawsTheFirstStage() {
        XCTAssertEqual(CraftStage.stage(hours: -40, goal: 750), .started)
        XCTAssertEqual(CraftStage.stage(hours: .nan, goal: 750), .started)
        XCTAssertEqual(CraftStage.stage(hours: .infinity, goal: 750), .started)
        XCTAssertEqual(CraftStage.stage(hours: 300, goal: 0), .started)
        XCTAssertEqual(CraftStage.stage(hours: 300, goal: -1), .started)
        XCTAssertEqual(CraftStage.stage(hours: 300, goal: .nan), .started)
    }

    func testMatchesTheReferenceMock() {
        // DirCraftToday's `CraftFocus.art(hours:goal:)`, the approved reference.
        XCTAssertEqual(CraftStage.stage(hours: 86, goal: 100), .half)
        XCTAssertEqual(CraftStage.stage(hours: 212, goal: 750), .frame70)
        XCTAssertEqual(CraftStage.stage(hours: 40, goal: 500), .started)
    }

    func testOrderAndAssetNames() {
        XCTAssertEqual(CraftStage.allCases, [.started, .frame70, .framing, .half, .complete])
        XCTAssertTrue(CraftStage.started < .complete)
        XCTAssertEqual(CraftStage.half.assetName, "craft_half")
        XCTAssertEqual(CraftStage.half.assetName(lit: true), "craft_half")
        XCTAssertEqual(CraftStage.half.assetName(lit: false), "craft_half-unlit")
        XCTAssertEqual(CraftStage.frame70.thumbnailName, "craft_thumb_frame70")
        XCTAssertEqual(CraftStage.allCases.filter(\.isFraming), [.started, .frame70, .framing])
    }

    func testEveryStillAndTwinIsInTheCatalog() {
        for stage in CraftStage.allCases {
            XCTAssertNotNil(UIImage(named: stage.assetName(lit: true)), stage.rawValue)
            XCTAssertNotNil(UIImage(named: stage.assetName(lit: false)), stage.rawValue + "-unlit")
        }
    }

    func testSpokenNames() {
        XCTAssertEqual(CraftStage.started.spokenName, "Framing started")
        XCTAssertEqual(CraftStage.frame70.spokenName, "Frame going up")
        XCTAssertEqual(CraftStage.framing.spokenName, "Frame finished")
        XCTAssertEqual(CraftStage.half.spokenName, "Roof on, siding going up")
        XCTAssertEqual(CraftStage.complete.spokenName, "House finished")
    }

    // MARK: Placement (§H.1)

    func testPlacementTable() {
        XCTAssertEqual(CraftStage.started.stageScale, 1.18)
        XCTAssertEqual(CraftStage.frame70.stageScale, 1.08)
        for s in [CraftStage.framing, .half, .complete] {
            XCTAssertEqual(s.stageScale, 1.0)
            XCTAssertEqual(s.stageLift(side: 390), 0)
        }
        XCTAssertEqual(CraftStage.started.stageLift(side: 390), 30)
        XCTAssertEqual(CraftStage.frame70.stageLift(side: 390), 12)
        XCTAssertEqual(CraftStage.started.stageLift(side: 195), 15, accuracy: 0.0001, "Lifts scale with side / 390")
        XCTAssertEqual(CraftStage.started.stageLift(side: 0), 0)
        XCTAssertEqual(CraftStage.groundLine, 0.92)
    }

    func testHeroSides() {
        XCTAssertEqual(CraftHeroSize.hero(windowWidth: 402, windowHeight: 874, accessibility: false), 390)
        XCTAssertEqual(CraftHeroSize.hero(windowWidth: 393, windowHeight: 852, accessibility: false), 380)
        XCTAssertEqual(CraftHeroSize.hero(windowWidth: 375, windowHeight: 667, accessibility: false), 297)
        XCTAssertEqual(CraftHeroSize.hero(windowWidth: 382, windowHeight: 644, accessibility: false), 287, "Duo closed (H7)")
        XCTAssertEqual(CraftHeroSize.hero(windowWidth: 402, windowHeight: 874, accessibility: true), 295, "H3")
        XCTAssertEqual(CraftHeroSize.hero(windowWidth: 300, windowHeight: 874, accessibility: false), 288, "Clamped to W − 12")
        XCTAssertEqual(CraftHeroSize.hero(windowWidth: 0, windowHeight: 874, accessibility: false), 0)
        XCTAssertEqual(CraftHeroSize.medium(windowWidth: 402, windowHeight: 874, accessibility: false), 300)
        XCTAssertEqual(CraftHeroSize.medium(windowWidth: 402, windowHeight: 874, accessibility: true), 220)
        XCTAssertEqual(CraftHeroSize.numeralCap(windowHeight: 874, accessibility: false), nil)
        XCTAssertEqual(CraftHeroSize.numeralCap(windowHeight: 644, accessibility: false), 64)
        XCTAssertEqual(CraftHeroSize.numeralCap(windowHeight: 874, accessibility: true), 54)
    }

    // MARK: Motion (§H.6)

    func testStageMotionSwitch() {
        XCTAssertEqual(CraftMotion.stageMotion(from: .frame70, to: .framing), .timberDrop)
        XCTAssertEqual(CraftMotion.stageMotion(from: .started, to: .framing), .timberDrop, "The drop's fade-in covers the jump")
        XCTAssertEqual(CraftMotion.stageMotion(from: .started, to: .frame70), .stageFade)
        XCTAssertEqual(CraftMotion.stageMotion(from: .frame70, to: .half), .stageFade, "Never the stages in between")
        XCTAssertEqual(CraftMotion.stageMotion(from: .started, to: .complete), .stageFade)
        XCTAssertEqual(CraftMotion.stageMotion(from: .half, to: .framing), .stageFade, "A delete never drops timber")
        for s in CraftStage.allCases { XCTAssertEqual(CraftMotion.stageMotion(from: s, to: s), CraftStageMotion.none) }
    }

    func testFirstLogOfTheDayDropsThenLightsTheWindows() {
        let plan = CraftMotion.plan(oldHours: 340, newHours: 360, goal: 750, wasLit: false, isLit: true, reduceMotion: false)
        XCTAssertEqual(plan.from, .frame70)
        XCTAssertEqual(plan.to, .framing)
        XCTAssertEqual(plan.stageMotion, .timberDrop)
        XCTAssertTrue(plan.windowsOn)
        XCTAssertTrue(plan.holdsWindowsDarkThroughDrop)
        XCTAssertEqual(plan.windowsDelay, 2.5, accuracy: 0.0001, "0.20 fade-in + 2.0 clip + 0.30 crossfade")
        XCTAssertEqual(plan.windowsDuration, 0.40)
        XCTAssertEqual(plan.totalDuration, 2.9, accuracy: 0.0001)
        XCTAssertTrue(plan.knock)
    }

    func testDropPlaysOncePerStagePerRental() {
        let plan = CraftMotion.plan(oldHours: 340, newHours: 360, goal: 750, wasLit: true, isLit: true,
                                    reduceMotion: false, dropAlreadyPlayed: true)
        XCTAssertEqual(plan.stageMotion, .stageFade)
        XCTAssertFalse(plan.windowsOn)
        XCTAssertFalse(plan.knock)
    }

    func testReduceMotionCrossfadesAndKeepsTheKnock() {
        let plan = CraftMotion.plan(oldHours: 340, newHours: 360, goal: 750, wasLit: false, isLit: true, reduceMotion: true)
        XCTAssertEqual(plan.stageMotion, .stageFade)
        XCTAssertFalse(plan.holdsWindowsDarkThroughDrop)
        XCTAssertEqual(plan.windowsDelay, CraftMotion.reducedStageCrossfade + CraftMotion.windowsAfterSettle, accuracy: 0.0001)
        XCTAssertTrue(plan.knock, "§B.3: the knock is kept under Reduce Motion")
    }

    func testWindowsWithoutAStageChange() {
        let plan = CraftMotion.plan(oldHours: 10, newHours: 12, goal: 750, wasLit: false, isLit: true, reduceMotion: false)
        XCTAssertEqual(plan.stageMotion, CraftStageMotion.none)
        XCTAssertTrue(plan.windowsOn)
        XCTAssertEqual(plan.windowsDelay, 0.30, accuracy: 0.0001)
        let quiet = CraftMotion.plan(oldHours: 10, newHours: 12, goal: 750, wasLit: true, isLit: true, reduceMotion: false)
        XCTAssertTrue(quiet.isEmpty)
        XCTAssertEqual(quiet.totalDuration, 0)
    }

    func testClipDim() {
        XCTAssertEqual(CraftMotion.clipDim(windowsLit: true, dark: true), 1)
        XCTAssertEqual(CraftMotion.clipDim(windowsLit: false, dark: true), 0.66)
        XCTAssertEqual(CraftMotion.clipDim(windowsLit: false, dark: false), 0.76)
    }

    // MARK: All rentals (H10)

    func testAllRentalsSumsHoursAgainstTheLargestGoal() {
        let all = CraftHeroTotals.allRentals([CraftHeroTotals(hours: 60, goal: 100),
                                              CraftHeroTotals(hours: 300, goal: 750),
                                              CraftHeroTotals(hours: 20, goal: 500)])
        XCTAssertEqual(all.hours, 380)
        XCTAssertEqual(all.goal, 750)
        XCTAssertEqual(all.stage, CraftStage.stage(hours: 380, goal: 750))
        XCTAssertEqual(CraftHeroTotals(hours: 60, goal: 100).stage, .half)
        let none = CraftHeroTotals.allRentals([])
        XCTAssertEqual(none.hours, 0)
        XCTAssertEqual(none.stage, .started)
        XCTAssertEqual(CraftHeroTotals(hours: -5, goal: .nan).hours, 0)
    }

    // MARK: Drop ledger

    func testDropLedgerRemembersPerRentalAndYear() {
        let defaults = UserDefaults(suiteName: "craftdrop-\(UUID().uuidString)")!
        let ledger = CraftDropLedger(defaults: defaults, userId: "u1")
        let a = UUID(), b = UUID()
        XCTAssertFalse(ledger.hasPlayed(rentalID: a, year: 2026))
        ledger.markPlayed(rentalID: a, year: 2026)
        ledger.markPlayed(rentalID: a, year: 2026)
        XCTAssertTrue(ledger.hasPlayed(rentalID: a, year: 2026))
        XCTAssertFalse(ledger.hasPlayed(rentalID: b, year: 2026))
        XCTAssertFalse(ledger.hasPlayed(rentalID: a, year: 2027))
        XCTAssertFalse(ledger.hasPlayed(rentalID: nil, year: 2026), "All rentals is its own focus")
        ledger.markPlayed(rentalID: nil, year: 2026)
        XCTAssertTrue(ledger.hasPlayed(rentalID: nil, year: 2026))
        XCTAssertFalse(CraftDropLedger(defaults: defaults, userId: "u2").hasPlayed(rentalID: a, year: 2026), "Per profile")
        XCTAssertEqual((defaults.stringArray(forKey: UserScope.key(CraftDropLedger.baseKey, userId: "u1")) ?? []).count, 2)
    }
}

// MARK: - Toast placement (standard §1.19, §H.8)

@MainActor
final class ToastPlacementTests: XCTestCase {
    private func makeCenter(_ announced: @escaping (String) -> Void = { _ in }) -> LHToastCenter {
        LHToastCenter(sleep: { _ in try? await Task.sleep(for: .seconds(3600)) }, announce: announced)
    }

    func testBottomUntilAHeroScreenClaimsTheTop() {
        let center = makeCenter()
        XCTAssertEqual(center.placement, .bottom)
        let today = center.claimTopPlacement()
        XCTAssertEqual(center.placement, .top)
        center.releaseTopPlacement(today)
        XCTAssertEqual(center.placement, .bottom)
    }

    func testOverlappingClaimsSurviveATabSwitch() {
        let center = makeCenter()
        let today = center.claimTopPlacement()
        let rental = center.claimTopPlacement()   // the next screen appears before the old one disappears
        center.releaseTopPlacement(today)
        XCTAssertEqual(center.placement, .top)
        center.releaseTopPlacement(rental)
        XCTAssertEqual(center.placement, .bottom)
        center.releaseTopPlacement(rental)
        XCTAssertEqual(center.placement, .bottom, "A double release is harmless")
    }

    func testTheChipHidesOnlyWhileATopToastShows() {
        let center = makeCenter()
        center.show(.success, "Logged 2h")
        XCTAssertFalse(center.hidesHeroChip, "Bottom toasts leave the chip alone")
        let claim = center.claimTopPlacement()
        XCTAssertTrue(center.hidesHeroChip)
        center.dismissCurrent()
        XCTAssertFalse(center.hidesHeroChip)
        center.releaseTopPlacement(claim)
    }

    func testTopToastsAreAnnounced() {
        var announced: [String] = []
        let center = makeCenter { announced.append($0) }
        _ = center.claimTopPlacement()
        center.show(.success, "Logged 2h at Pine Cabin", actionTitle: "Undo") {}
        XCTAssertEqual(announced, ["Logged 2h at Pine Cabin. Undo is available."])
    }

    func testClearKeepsTheScreensClaim() {
        let center = makeCenter()
        _ = center.claimTopPlacement()
        center.show(.success, "x")
        center.clear()
        XCTAssertNil(center.current)
        XCTAssertEqual(center.placement, .top)
    }
}
