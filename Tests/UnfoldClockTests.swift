import XCTest
import SwiftUI
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
