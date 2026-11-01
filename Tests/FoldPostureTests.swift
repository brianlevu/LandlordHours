import XCTest
@testable import LandlordHours

/// §1.27 (the Duo poses) and §B.3 `duoUnfold`: which way the fold lies, from the active `.division`
/// region the system reports. Held open the inner display is landscape 951×669 with the fold running
/// top to bottom (side-by-side panes); propped it is 669×951 with the fold across (top and bottom).
final class FoldPostureTests: XCTestCase {

    private let open = CGSize(width: 951, height: 669)
    private let propped = CGSize(width: 669, height: 951)
    private let band: CGFloat = 24

    // MARK: Posture from the division

    func testNoDivisionIsFlat() {
        // Every iPhone, every iPad window, and the closed Duo's outer display.
        XCTAssertEqual(FoldPosture.resolve(division: nil, in: CGSize(width: 382, height: 644)), .flat)
        XCTAssertEqual(FoldPosture.resolve(division: nil, in: CGSize(width: 1180, height: 820)), .flat)
        XCTAssertEqual(FoldPosture.resolve(division: nil, in: open), .flat)
    }

    func testHeldOpenIsAVerticalFold() {
        let fold = CGRect(x: (open.width - band) / 2, y: 0, width: band, height: open.height)
        XCTAssertEqual(FoldPosture.resolve(division: fold, in: open), .open)
    }

    func testProppedIsAHorizontalFold() {
        let fold = CGRect(x: 0, y: (propped.height - band) / 2, width: propped.width, height: band)
        XCTAssertEqual(FoldPosture.resolve(division: fold, in: propped), .propped)
    }

    func testTheBandIsReadNotAssumed() {
        // A wider or narrower real band (frame + margins) still reads by its shape, never by 24.
        XCTAssertEqual(FoldPosture.resolve(division: CGRect(x: 470, y: 0, width: 11, height: 669), in: open), .open)
        XCTAssertEqual(FoldPosture.resolve(division: CGRect(x: 440, y: 0, width: 70, height: 669), in: open), .open)
        XCTAssertEqual(FoldPosture.resolve(division: CGRect(x: 0, y: 455, width: 669, height: 40), in: propped), .propped)
    }

    func testASquareDivisionReadsAsVerticalLikeTheLayout() {
        // `PaneDivision.isVertical` (package J) treats height >= width as vertical; the posture agrees,
        // so the door's light and the panes never disagree about which way the fold runs.
        XCTAssertEqual(FoldPosture.resolve(division: CGRect(x: 400, y: 300, width: 30, height: 30), in: open), .open)
    }

    func testBadDivisionsAreFlat() {
        XCTAssertEqual(FoldPosture.resolve(division: .zero, in: open), .flat)
        XCTAssertEqual(FoldPosture.resolve(division: CGRect(x: 470, y: 0, width: 0, height: 669), in: open), .flat)
        XCTAssertEqual(FoldPosture.resolve(division: CGRect(x: 470, y: 0, width: CGFloat.nan, height: 669), in: open), .flat)
        XCTAssertEqual(FoldPosture.resolve(division: CGRect(x: 470, y: 0, width: CGFloat.infinity, height: 669), in: open), .flat)
        // Entirely outside the window (a stale region from the other display).
        XCTAssertEqual(FoldPosture.resolve(division: CGRect(x: 2000, y: 0, width: 24, height: 669), in: open), .flat)
        // A window with no size yet.
        XCTAssertEqual(FoldPosture.resolve(division: CGRect(x: 470, y: 0, width: 24, height: 669), in: .zero), .flat)
    }

    func testAPartlyOutsideDivisionIsClippedToTheWindow() {
        // Clipped to 24×669 inside the window: still vertical.
        XCTAssertEqual(FoldPosture.resolve(division: CGRect(x: 463.5, y: -50, width: 24, height: 800), in: open), .open)
        // A tall region clipped to a short sliver at the window's top edge reads by what is inside.
        XCTAssertEqual(FoldPosture.resolve(division: CGRect(x: 0, y: -900, width: 669, height: 920), in: propped), .propped)
    }

    // MARK: Where the fold sits for the work pane, and where the door can play

    func testTheWorkPaneMeetsTheFoldAtItsLeadingOrTopEdge() {
        XCTAssertEqual(FoldPosture.open.workPaneFoldEdge, .leading)
        XCTAssertEqual(FoldPosture.propped.workPaneFoldEdge, .top)
        XCTAssertNil(FoldPosture.flat.workPaneFoldEdge)
    }

    func testOnlyAFoldHostsTheDoor() {
        XCTAssertTrue(FoldPosture.open.hostsDoor)
        XCTAssertTrue(FoldPosture.propped.hostsDoor)
        XCTAssertFalse(FoldPosture.flat.hostsDoor)   // an iPad two-pane window is lit at rest, never a door
    }

    // MARK: Hinge status

    func testHingeOpenness() {
        XCTAssertFalse(HingeStatus.closed.isOpen)
        XCTAssertTrue(HingeStatus.partiallyOpen.isOpen)
        XCTAssertTrue(HingeStatus.fullyOpen.isOpen)
    }
}
