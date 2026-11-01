import XCTest
@testable import LandlordHours

/// §B.3 `duoUnfold` on token `duoDoor` (§B.2), §1.27 Motion and must-prove 2, 3, 7, 8, 9: the door
/// clock is driven by hinge events only, and every door layer is a pure function of the clock.
final class UnfoldDoorTests: XCTestCase {

    // MARK: Which hinge events move the door

    func testClosedToOpenSwingsTheDoorOpenIn0_80() {
        for open in [HingeStatus.partiallyOpen, .fullyOpen] {
            let move = UnfoldDoor.move(from: .closed, to: open, reduceMotion: false, current: 0)
            XCTAssertEqual(move, UnfoldMove(from: 0, to: 1, duration: 0.80, style: .swing))
        }
    }

    func testOpenToClosedRunsTheSameClockBackIn0_50() {
        for open in [HingeStatus.partiallyOpen, .fullyOpen] {
            let move = UnfoldDoor.move(from: open, to: .closed, reduceMotion: false, current: 1)
            XCTAssertEqual(move, UnfoldMove(from: 1, to: 0, duration: 0.50, style: .swing))
        }
    }

    func testReduceMotionIsA0_20CrossfadeBothWays() {
        XCTAssertEqual(UnfoldDoor.move(from: .closed, to: .fullyOpen, reduceMotion: true, current: 0),
                       UnfoldMove(from: 0, to: 1, duration: 0.20, style: .crossfade))
        XCTAssertEqual(UnfoldDoor.move(from: .fullyOpen, to: .closed, reduceMotion: true, current: 1),
                       UnfoldMove(from: 1, to: 0, duration: 0.20, style: .crossfade))
    }

    func testColdLaunchAlreadyOpenNeverPlays() {
        // The first report has no previous hinge: it only records the state (must-prove 2).
        XCTAssertNil(UnfoldDoor.move(from: nil, to: .fullyOpen, reduceMotion: false, current: 1))
        XCTAssertNil(UnfoldDoor.move(from: nil, to: .closed, reduceMotion: false, current: 1))
        // A hinge that goes away (the scene moved to a display with none) moves nothing.
        XCTAssertNil(UnfoldDoor.move(from: .fullyOpen, to: nil, reduceMotion: false, current: 1))
    }

    func testOpeningWiderOrNarrowerNeverReplays() {
        XCTAssertNil(UnfoldDoor.move(from: .partiallyOpen, to: .fullyOpen, reduceMotion: false, current: 1))
        XCTAssertNil(UnfoldDoor.move(from: .fullyOpen, to: .partiallyOpen, reduceMotion: false, current: 1))
        XCTAssertNil(UnfoldDoor.move(from: .closed, to: .closed, reduceMotion: false, current: 0))
        XCTAssertNil(UnfoldDoor.move(from: .fullyOpen, to: .fullyOpen, reduceMotion: false, current: 1))
    }

    func testAnInterruptedFoldReopensFromWhereTheDoorIs() {
        // Folded halfway back, then opened again: the door continues from 0.4, never jumps to 0,
        // and takes only the rest of the 0.80 s.
        let move = UnfoldDoor.move(from: .closed, to: .fullyOpen, reduceMotion: false, current: 0.4)
        XCTAssertEqual(move?.from, 0.4)
        XCTAssertEqual(move?.to, 1)
        XCTAssertEqual(move?.duration ?? 0, 0.48, accuracy: 1e-9)
        // And a fold from halfway open runs back over its share of 0.50 s.
        let back = UnfoldDoor.move(from: .fullyOpen, to: .closed, reduceMotion: false, current: 0.5)
        XCTAssertEqual(back?.duration ?? 0, 0.25, accuracy: 1e-9)
    }

    func testAnOpenWithTheDoorAlreadyOpenDoesNothing() {
        XCTAssertNil(UnfoldDoor.move(from: .closed, to: .fullyOpen, reduceMotion: false, current: 1))
        XCTAssertNil(UnfoldDoor.move(from: .fullyOpen, to: .closed, reduceMotion: false, current: 0))
    }

    func testBadClockValuesAreClamped() {
        XCTAssertEqual(UnfoldDoor.move(from: .closed, to: .fullyOpen, reduceMotion: false, current: -3)?.from, 0)
        XCTAssertEqual(UnfoldDoor.move(from: .closed, to: .fullyOpen, reduceMotion: false, current: .nan)?.from, 0)
        XCTAssertNil(UnfoldDoor.move(from: .closed, to: .fullyOpen, reduceMotion: false, current: 7))
    }

    func testEveryRunFitsTheMotionCap() {
        // §B.1: duoUnfold is the one exception at <= 0.80 s.
        for from in [HingeStatus.closed, .partiallyOpen, .fullyOpen] {
            for to in [HingeStatus.closed, .partiallyOpen, .fullyOpen] {
                for rm in [false, true] {
                    for t in stride(from: 0.0, through: 1.0, by: 0.1) {
                        if let m = UnfoldDoor.move(from: from, to: to, reduceMotion: rm, current: t) {
                            XCTAssertLessThanOrEqual(m.duration, 0.80 + 1e-9)
                            XCTAssertGreaterThan(m.duration, 0)
                        }
                    }
                }
            }
        }
    }

    // MARK: The clock over time

    func testTheClockIsLinearAndClamped() {
        let m = UnfoldMove(from: 0, to: 1, duration: 0.80, style: .swing)
        XCTAssertEqual(m.value(at: -1), 0)
        XCTAssertEqual(m.value(at: 0), 0)
        XCTAssertEqual(m.value(at: 0.40), 0.5, accuracy: 1e-9)
        XCTAssertEqual(m.value(at: 0.80), 1)
        XCTAssertEqual(m.value(at: 5), 1)
        XCTAssertTrue(m.isFinished(at: 0.80))
        XCTAssertFalse(m.isFinished(at: 0.79))
        let back = UnfoldMove(from: 1, to: 0, duration: 0.50, style: .swing)
        XCTAssertEqual(back.value(at: 0.25), 0.5, accuracy: 1e-9)
    }

    // MARK: A touch, and a door left half-open

    func testATouchMidUnfoldJumpsTheDoorToItsEnd() {
        XCTAssertEqual(UnfoldDoor.touch(current: 0.1), 1)
        XCTAssertEqual(UnfoldDoor.touch(current: 0.99), 1)
        XCTAssertNil(UnfoldDoor.touch(current: 1))   // at rest a touch is just a touch
        XCTAssertNil(UnfoldDoor.touch(current: 0))   // folded: nothing to finish
    }

    func testADoorLeftDarkOnAnOpenFoldSettlesLit() {
        // Must-prove 3: if the open event never lands (missed while the scene moved displays), the
        // work pane must not stay veiled. After 1 s on a fold with no run, the door settles lit.
        XCTAssertTrue(UnfoldDoor.isStranded(current: 0, running: false, posture: .open, secondsSinceHingeEvent: 1.0))
        XCTAssertTrue(UnfoldDoor.isStranded(current: 0.3, running: false, posture: .propped, secondsSinceHingeEvent: nil))
        XCTAssertFalse(UnfoldDoor.isStranded(current: 0, running: false, posture: .open, secondsSinceHingeEvent: 0.5))
        XCTAssertFalse(UnfoldDoor.isStranded(current: 0, running: true, posture: .open, secondsSinceHingeEvent: 3))
        XCTAssertFalse(UnfoldDoor.isStranded(current: 1, running: false, posture: .open, secondsSinceHingeEvent: 3))
        // Folded (the outer display): a shut door is right, never "stranded".
        XCTAssertFalse(UnfoldDoor.isStranded(current: 0, running: false, posture: .flat, secondsSinceHingeEvent: 9))
    }

    // MARK: The pose: every layer is a pure function of t (§B.3 windows)

    func testRestIsOpenAndLitWithNothingOverThePane() {
        for style in [UnfoldStyle.swing, .crossfade] {
            let p = DoorPose(t: 1, style: style)
            XCTAssertEqual(p.leafTurn, 1)
            XCTAssertEqual(p.leafAngleDegrees, -78)
            XCTAssertEqual(p.doorLight, 1)
            XCTAssertEqual(p.doorLayerOpacity, 1)
            XCTAssertFalse(p.drawsVeil)
            XCTAssertTrue(p.isAtRest)
        }
        XCTAssertEqual(DoorPose.rest, DoorPose(t: 1, style: .swing))
    }

    func testSwingWindows() {
        // The leaf turns over t 0–0.42, the hall and step light over 0.05–0.50, the veil wipes over 0.12–0.76.
        let shut = DoorPose(t: 0, style: .swing)
        XCTAssertEqual(shut.leafTurn, 0)
        XCTAssertEqual(shut.doorLight, 0)
        XCTAssertEqual(shut.paneReveal, 0)
        XCTAssertTrue(shut.drawsVeil)
        XCTAssertEqual(shut.veilOpacity, 1)

        XCTAssertEqual(DoorPose(t: 0.42, style: .swing).leafTurn, 1, accuracy: 1e-9)
        XCTAssertEqual(DoorPose(t: 0.05, style: .swing).doorLight, 0, accuracy: 1e-9)
        XCTAssertEqual(DoorPose(t: 0.50, style: .swing).doorLight, 1, accuracy: 1e-9)
        XCTAssertEqual(DoorPose(t: 0.12, style: .swing).paneReveal, 0, accuracy: 1e-9)
        XCTAssertEqual(DoorPose(t: 0.76, style: .swing).paneReveal, 1, accuracy: 1e-9)
        XCTAssertFalse(DoorPose(t: 0.76, style: .swing).drawsVeil)

        // Ease-out cubic: past the midpoint of its window early.
        XCTAssertGreaterThan(DoorPose(t: 0.21, style: .swing).leafTurn, 0.5)
        // The leaf darkens 0.12 and casts a 0.35 shadow as it turns.
        let open = DoorPose(t: 0.42, style: .swing)
        XCTAssertEqual(open.leafDarken, -0.12, accuracy: 1e-9)
        XCTAssertEqual(open.leafShadow, 0.35, accuracy: 1e-9)
    }

    func testSwingIsMonotonic() {
        var last = DoorPose(t: 0, style: .swing)
        for i in 1...100 {
            let p = DoorPose(t: Double(i) / 100, style: .swing)
            XCTAssertGreaterThanOrEqual(p.leafTurn, last.leafTurn)
            XCTAssertGreaterThanOrEqual(p.doorLight, last.doorLight)
            XCTAssertGreaterThanOrEqual(p.paneReveal, last.paneReveal)
            last = p
        }
    }

    func testReduceMotionNeverTurnsTheLeafOrWipes() {
        // A crossfade from the closed state to the lit end state: no leaf turn, no wipe.
        for i in 0...10 {
            let t = Double(i) / 10
            let p = DoorPose(t: t, style: .crossfade)
            XCTAssertEqual(p.leafTurn, 1, "the open leaf only fades in")
            XCTAssertEqual(p.paneReveal, 0, "the veil never wipes; it fades")
            XCTAssertEqual(p.doorLayerOpacity, t, accuracy: 1e-9)
            XCTAssertEqual(p.veilOpacity, 1 - t, accuracy: 1e-9)
        }
    }

    func testFramingStagesPlayThePaneLightOnly() {
        // `started`, `frame70`, `framing` have no door; "All rentals" is the skyline: pane light only.
        let p = DoorPose(t: 0.3, style: .swing, hasDoor: false)
        XCTAssertEqual(p.doorLayerOpacity, 0)
        XCTAssertEqual(p.paneReveal, DoorPose(t: 0.3, style: .swing).paneReveal)
        XCTAssertTrue(p.drawsVeil)
    }

    func testPoseClampsBadClocks() {
        XCTAssertEqual(DoorPose(t: -1, style: .swing), DoorPose(t: 0, style: .swing))
        XCTAssertEqual(DoorPose(t: 4, style: .swing), DoorPose(t: 1, style: .swing))
        XCTAssertEqual(DoorPose(t: .nan, style: .swing), DoorPose(t: 1, style: .swing))
    }
}
