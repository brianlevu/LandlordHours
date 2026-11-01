import XCTest
import SwiftUI
import Combine
@testable import LandlordHours

/// The clock applies `UnfoldDoor`'s rules over time: hinge reports, a touch, a stranded door.
@MainActor
final class UnfoldClockTests: XCTestCase {

    func testRestsOpenAndLit() {
        let clock = UnfoldClock()
        XCTAssertEqual(clock.t, 1)
        XCTAssertEqual(clock.pose, .rest)
        XCTAssertFalse(clock.isRunning)
    }

    func testTheFirstReportOnlyRecords() {
        let clock = UnfoldClock()
        clock.hingeChanged(from: nil, to: .fullyOpen, reduceMotion: false)
        XCTAssertEqual(clock.hinge, .fullyOpen)
        XCTAssertNotNil(clock.lastHingeEvent)
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.t, 1)
    }

    func testFoldThenUnfoldRunsTheDoor() async throws {
        let clock = UnfoldClock()
        clock.hingeChanged(from: .fullyOpen, to: .closed, reduceMotion: false)
        XCTAssertTrue(clock.isRunning)
        XCTAssertEqual(clock.style, .swing)
        try await waitUntil { !clock.isRunning }
        XCTAssertEqual(clock.t, 0)

        clock.hingeChanged(from: .closed, to: .fullyOpen, reduceMotion: false)
        XCTAssertTrue(clock.isRunning)
        XCTAssertEqual(clock.t, 0, "the first frame at the new size is the door at t = 0")
        try await waitUntil { !clock.isRunning }
        XCTAssertEqual(clock.t, 1)
        XCTAssertEqual(clock.pose, .rest)
    }

    func testReduceMotionCrossfadesAndEndsAtRest() async throws {
        let clock = UnfoldClock(t: 0)
        clock.hingeChanged(from: .closed, to: .partiallyOpen, reduceMotion: true)
        XCTAssertEqual(clock.style, .crossfade)
        XCTAssertEqual(clock.pose.leafTurn, 1, "no leaf turn under Reduce Motion")
        try await waitUntil { !clock.isRunning }
        XCTAssertEqual(clock.pose, .rest)
        XCTAssertEqual(clock.style, .swing)
    }

    func testATouchFinishesTheRun() {
        let clock = UnfoldClock(t: 0)
        clock.hingeChanged(from: .closed, to: .fullyOpen, reduceMotion: false)
        XCTAssertTrue(clock.isRunning)
        clock.finish()
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.t, 1)
        // At rest a touch changes nothing.
        clock.finish()
        XCTAssertEqual(clock.t, 1)
    }

    func testAStrandedDoorSettlesLitOnlyOnAFold() {
        let clock = UnfoldClock(t: 0)
        let now = Date()
        clock.hingeChanged(from: .fullyOpen, to: .closed, reduceMotion: false, now: now)   // runs 0 → 0: nothing
        XCTAssertFalse(clock.isRunning)
        clock.settleIfStranded(posture: .flat, now: now.addingTimeInterval(5))
        XCTAssertEqual(clock.t, 0, "folded: a shut door is right")
        clock.settleIfStranded(posture: .open, now: now.addingTimeInterval(0.4))
        XCTAssertEqual(clock.t, 0, "too soon: the open event may still land")
        clock.settleIfStranded(posture: .open, now: now.addingTimeInterval(1.2))
        XCTAssertEqual(clock.t, 1)
    }

    func testASettledDoorStillPlaysOnTheNextUnfold() async throws {
        // A settle lit the door while the hinge read closed; once the window is on the outer display
        // the door rests shut again, so the next unfold plays.
        let clock = UnfoldClock(t: 1)
        clock.hingeChanged(from: .fullyOpen, to: .closed, reduceMotion: true)
        try await waitUntil { !clock.isRunning }
        clock.settleIfStranded(posture: .open, now: Date().addingTimeInterval(5))
        XCTAssertEqual(clock.t, 1)
        clock.postureChanged(to: .flat)
        XCTAssertEqual(clock.t, 0)
        clock.hingeChanged(from: .closed, to: .fullyOpen, reduceMotion: false)
        XCTAssertTrue(clock.isRunning)
        clock.finish()
    }

    func testAColdLaunchAndAnIPadStayLit() {
        let clock = UnfoldClock()
        clock.postureChanged(to: .flat)        // no hinge report: an iPhone, an iPad, a cold launch
        XCTAssertEqual(clock.t, 1)
        clock.postureChanged(to: .open)
        XCTAssertEqual(clock.t, 1)
    }

    func testRunningIsPublished() {
        let clock = UnfoldClock(t: 0)
        var changes = 0
        let sub = clock.objectWillChange.sink { changes += 1 }
        clock.hingeChanged(from: .closed, to: .fullyOpen, reduceMotion: false)
        XCTAssertTrue(clock.isRunning)
        let before = changes
        clock.finish()
        XCTAssertFalse(clock.isRunning)
        XCTAssertGreaterThan(changes, before)
        sub.cancel()
    }

    // MARK: The hooks' reading of the split

    func testOnlyAPhysicalFoldHasAPosture() {
        let ipad = LayoutMode.resolve(previous: nil, size: CGSize(width: 1180, height: 820), division: nil, live: false)
        XCTAssertEqual(ipad.mode, .twoPane)
        XCTAssertEqual(DuoHooks.posture(ipad), .flat, "an iPad two-pane window never plays the door")
        let open = LayoutMode.resolve(previous: nil, size: CGSize(width: 951, height: 669),
                                      division: PaneDivision(rect: CGRect(x: 463.5, y: 0, width: 24, height: 669)), live: false)
        XCTAssertEqual(DuoHooks.posture(open), .open)
        let propped = LayoutMode.resolve(previous: nil, size: CGSize(width: 669, height: 951),
                                         division: PaneDivision(rect: CGRect(x: 0, y: 463.5, width: 669, height: 24)), live: false)
        XCTAssertEqual(propped.mode, .stacked)
        XCTAssertEqual(DuoHooks.posture(propped), .propped)
        XCTAssertEqual(DuoHooks.posture(.compact(CGSize(width: 382, height: 644))), .flat)
    }

    func testOnlyTheHalfBuiltHouseHasADoorToSwing() {
        // §B.3 names `half` and `complete`; `complete` waits on a separate leaf layer from the art lane
        // (the porch post stands in front of the leaf), so it plays the pane light only for now.
        XCTAssertNotNil(DoorArt.doorRect(stage: .half))
        for stage in [CraftStage.started, .frame70, .framing, .complete] {
            XCTAssertNil(DoorArt.doorRect(stage: stage), "\(stage)")
        }
    }

    func testAPoseWithNoDoorKeepsThePaneLight() {
        let clock = UnfoldClock(t: 0)
        XCTAssertEqual(clock.pose(hasDoor: false).doorLayerOpacity, 0)
        XCTAssertTrue(clock.pose(hasDoor: false).drawsVeil)
    }

    func testTheVeilStopsNeverRunBackwards() {
        for i in 0...20 {
            let stops = UnfoldLight.stops(reveal: Double(i) / 20)
            XCTAssertEqual(stops.count, 3)
            XCTAssertLessThanOrEqual(stops[1].location, stops[2].location)
            XCTAssertGreaterThanOrEqual(stops[1].location, 0)
            XCTAssertLessThanOrEqual(stops[2].location, 1)
        }
        // Shut: veiled from the fold. Fully revealed: clear to the far edge.
        XCTAssertEqual(UnfoldLight.stops(reveal: 0)[2].location, 0)
        XCTAssertEqual(UnfoldLight.stops(reveal: 1)[1].location, 1)
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { XCTFail("timed out"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
