import XCTest
import SwiftUI
@testable import LandlordHours

/// Package A (foundations): the pure parts of the LH* components, the hero sizing and the shell's
/// tab routing. Standard §1.2, §1.9, §1.11, §1.25, §1.27, §H.1, §H.7.
final class FoundationsTests: XCTestCase {

    // MARK: LHFormat.hours (§1.2)

    func testHoursFormatCanonicalCases() {
        XCTAssertEqual(LHFormat.hours(2), "2h")
        XCTAssertEqual(LHFormat.hours(0.5), "30m")
        XCTAssertEqual(LHFormat.hours(1.5), "1h 30m")
        XCTAssertEqual(LHFormat.hours(12.5), "12h 30m")
        XCTAssertEqual(LHFormat.hours(0), "0m")
    }

    func testHoursFormatUnknownIsDash() {
        XCTAssertEqual(LHFormat.hours(nil), "—")
        XCTAssertEqual(LHFormat.hours(-1), "—")
        XCTAssertEqual(LHFormat.hours(.nan), "—")
        XCTAssertEqual(LHFormat.hours(.infinity), "—")
    }

    func testHoursFormatRoundsToTheMinute() {
        XCTAssertEqual(LHFormat.hours(1.0 / 60 * 0.4), "0m")      // 24 s
        XCTAssertEqual(LHFormat.hours(0.999), "1h")               // 59.94 min → 60
        XCTAssertEqual(LHFormat.hours(0.25), "15m")
        XCTAssertEqual(LHFormat.minutes(1.75), 105)
    }

    func testSpokenHours() {
        XCTAssertEqual(LHFormat.spokenHours(nil), "unknown")
        XCTAssertEqual(LHFormat.spokenHours(0), "0 minutes")
        XCTAssertTrue(LHFormat.spokenHours(1.5).contains("1 hour"))
        XCTAssertTrue(LHFormat.spokenHours(0.5).contains("30 minutes"))
    }

    // MARK: LHStepper (§1.9)

    func testStepperSnapsAndClamps() {
        let range = 0.0...24.0
        XCTAssertEqual(LHStepper.stepped(1.5, by: 0.25, step: 0.25, range: range), 1.75)
        XCTAssertEqual(LHStepper.stepped(0, by: -0.25, step: 0.25, range: range), 0)
        XCTAssertEqual(LHStepper.stepped(24, by: 0.25, step: 0.25, range: range), 24)
        XCTAssertEqual(LHStepper.stepped(1.1, by: 0.25, step: 0.25, range: range), 1.25)   // snaps to the 15m grid
        XCTAssertEqual(LHStepper.stepped(3, by: 1, step: 0, range: range), 3)              // no step: clamp only
    }

    // MARK: LHTile.StatGrid (§1.27 widths)

    func testStatGridIsTwoUpOnlyInWideColumns() {
        XCTAssertEqual(LHTile.StatGrid<EmptyView>.columns(width: 440, accessibility: false), 2)
        XCTAssertEqual(LHTile.StatGrid<EmptyView>.columns(width: 362, accessibility: false), 1)
        XCTAssertEqual(LHTile.StatGrid<EmptyView>.columns(width: 600, accessibility: true), 1)
    }

    // MARK: LHTag cap (§1.16)

    func testTagsCapAtTwoWithOverflow() {
        let tags = ["a", "b", "c", "d"].map { LHTag($0) }
        let capped = LHTag.capped(tags)
        XCTAssertEqual(capped.shown.count, 2)
        XCTAssertEqual(capped.overflow, 2)
        XCTAssertEqual(LHTag.capped([LHTag("x")]).overflow, 0)
    }

    // MARK: LayoutBand (§1.27)

    func testBandBoundaries() {
        XCTAssertEqual(LayoutBand.resolve(previous: nil, width: 402), .a)
        XCTAssertEqual(LayoutBand.resolve(previous: nil, width: 599), .a)
        XCTAssertEqual(LayoutBand.resolve(previous: nil, width: 600), .b)
        XCTAssertEqual(LayoutBand.resolve(previous: nil, width: 899), .b)
        XCTAssertEqual(LayoutBand.resolve(previous: nil, width: 900), .b)   // band C retired (AD1)
        XCTAssertEqual(LayoutBand.resolve(previous: nil, width: 1366), .b)
    }

    func testBandHysteresis() {
        // A → B only past 608; B → A only under 592.
        XCTAssertEqual(LayoutBand.resolve(previous: .a, width: 604), .a)
        XCTAssertEqual(LayoutBand.resolve(previous: .a, width: 608), .b)
        XCTAssertEqual(LayoutBand.resolve(previous: .b, width: 595), .b)
        XCTAssertEqual(LayoutBand.resolve(previous: .b, width: 591), .a)
        // Band C is retired (AD1): a wide window stays in B from either side.
        XCTAssertEqual(LayoutBand.resolve(previous: .b, width: 908), .b)
        XCTAssertEqual(LayoutBand.resolve(previous: .a, width: 1000), .b)
        XCTAssertEqual(LayoutBand.allCases, [.a, .b])
    }

    func testBandBadWidthKeepsPrevious() {
        XCTAssertEqual(LayoutBand.resolve(previous: .b, width: .nan), .b)
        XCTAssertEqual(LayoutBand.resolve(previous: nil, width: 0), .a)
    }

    // MARK: CraftHeroSide (§H.1 H1, H3, H6, H8; §H.5)

    func testHeroSideReferenceWindows() {
        func side(_ w: CGFloat, _ h: CGFloat, ax: Bool = false, band: LayoutBand = .a, kind: CraftHeroSide.Kind = .hero) -> CGFloat {
            CraftHeroSide.resolve(previous: nil, kind: kind, window: CGSize(width: w, height: h), band: band, accessibility: ax).side
        }
        XCTAssertEqual(side(402, 874), 390)            // H1 default
        XCTAssertEqual(side(393, 852), 380)
        XCTAssertEqual(side(375, 667), 297)            // SE class
        XCTAssertEqual(side(402, 874, ax: true), 295)  // H3
        XCTAssertEqual(side(382, 644), 287)            // H7 Duo closed
        // H6 band B (amended 2026-10-27): H1's share of the height given, clamped 290…480 and to W − 12.
        XCTAssertEqual(side(820, 1180, band: .b), 480)
        XCTAssertEqual(side(1032, 1176, band: .b), 480)   // 13" portrait, under the 200 header allowance
        XCTAssertEqual(side(834, 1010, band: .b), 450)    // 11" portrait
        XCTAssertEqual(side(1376, 832, band: .b), 371)    // 13" landscape
        XCTAssertEqual(side(1210, 634, band: .b), 290)    // 11" landscape: never under 290
        XCTAssertEqual(side(820, 1180, ax: true, band: .b), 390)   // AX: H3's share, 220…390
        XCTAssertEqual(side(1210, 634, ax: true, band: .b), 220)
        XCTAssertEqual(side(402, 874, kind: .medium), 300)
        XCTAssertEqual(side(402, 874, ax: true, kind: .medium), 220)
        XCTAssertEqual(side(820, 1180, band: .b, kind: .medium), 300)
    }

    func testHeroSideHysteresisH8() {
        let first = CraftHeroSide.resolve(previous: nil, kind: .hero, window: CGSize(width: 402, height: 874), band: .a, accessibility: false)
        // A resize under 40pt of height keeps the side.
        let small = CraftHeroSide.resolve(previous: first, kind: .hero, window: CGSize(width: 402, height: 850), band: .a, accessibility: false)
        XCTAssertEqual(small, first)
        // 40pt or more recomputes.
        let big = CraftHeroSide.resolve(previous: first, kind: .hero, window: CGSize(width: 402, height: 834), band: .a, accessibility: false)
        XCTAssertEqual(big.side, 372)
        // A band change or the accessibility state always recomputes.
        let ax = CraftHeroSide.resolve(previous: first, kind: .hero, window: CGSize(width: 402, height: 874), band: .a, accessibility: true)
        XCTAssertEqual(ax.side, 295)
        let wide = CraftHeroSide.resolve(previous: first, kind: .hero, window: CGSize(width: 820, height: 874), band: .b, accessibility: false)
        XCTAssertEqual(wide.side, 390)
    }

    // MARK: Band-B content column (§1.27 interim)

    func testContentColumnInset() {
        // Band A (every iPhone) is never inset, whatever the width.
        XCTAssertEqual(LHMetrics.columnInset(band: .a, width: 402), 0)
        XCTAssertEqual(LHMetrics.columnInset(band: .a, width: 1032), 0)
        // Band B centres a 672 column.
        XCTAssertEqual(LHMetrics.columnInset(band: .b, width: 1032), 180)   // 13" portrait
        XCTAssertEqual(LHMetrics.columnInset(band: .b, width: 1376), 352)   // 13" landscape
        XCTAssertEqual(LHMetrics.columnInset(band: .b, width: 834), 81)     // 11" portrait
        XCTAssertEqual(LHMetrics.columnInset(band: .b, width: 672), 0)
        XCTAssertEqual(LHMetrics.columnInset(band: .b, width: 610), 0)      // narrower than the column
        XCTAssertEqual(LHMetrics.columnInset(band: .b, width: .infinity), 0)
    }

    func testEmptyStateDioramaSide() {
        XCTAssertEqual(LHEmptyState.Page.side(viewportHeight: 874), 240)
        XCTAssertEqual(LHEmptyState.Page.side(viewportHeight: 800), 224)   // 28% of 800
        XCTAssertEqual(LHEmptyState.Page.side(viewportHeight: 600), 220)   // never under the 220 diorama minimum
    }

    // MARK: The hero's words

    func testHeroAccessibilityLabel() {
        let label = CraftHouseView.accessibilityLabel(stage: .frame70, lit: true)
        XCTAssertTrue(label.hasPrefix("House, "))
        XCTAssertTrue(label.contains(CraftStage.frame70.spokenName))
        XCTAssertTrue(label.hasSuffix("lights on"))
        XCTAssertTrue(CraftHouseView.accessibilityLabel(stage: .complete, lit: false).hasSuffix("lights off"))
    }

    func testNightLiftOnlyForStagesWithoutMoonRim() {
        XCTAssertEqual(CraftHouseView.nightLift(.started), 0)
        XCTAssertEqual(CraftHouseView.nightLift(.framing), 0)
        XCTAssertEqual(CraftHouseView.nightLift(.half), 0.065)
        XCTAssertEqual(CraftHouseView.nightLift(.complete), 0.065)
    }

    // MARK: Shell (§1.25, §H.7)

    func testShellItemsAreTheFiveTabsInOrder() {
        XCTAssertEqual(ShellItem.allCases, [.today, .inbox, .records, .rentals, .logTime])
        XCTAssertEqual(ShellItem.allCases.map(\.systemImage), ["sun.horizon", "tray", "book.closed", "house", "plus"])
        XCTAssertEqual(ShellItem.rentals.title, "Rentals")
        XCTAssertEqual(ShellItem.logTime.title, "Log time")
    }

    func testLegacyIndicesRouteToTabs() {
        XCTAssertEqual(ShellItem(legacyIndex: ShellTab.todayIndex), .today)
        XCTAssertEqual(ShellItem(legacyIndex: ShellTab.propertiesIndex), .rentals)
        XCTAssertEqual(ShellItem(legacyIndex: ShellTab.logTimeIndex), .logTime)
        XCTAssertEqual(ShellItem(legacyIndex: ShellTab.reportsIndex), .today)    // Reports opens on Today
        XCTAssertEqual(ShellItem(legacyIndex: ShellTab.settingsIndex), .today)   // Settings opens on Today
        XCTAssertEqual(ShellItem(legacyIndex: ShellTab.inboxIndex), .inbox)
        XCTAssertEqual(ShellItem(legacyIndex: ShellTab.recordsIndex), .records)
        XCTAssertEqual(ShellItem(legacyIndex: 99), .today)
        for item in ShellItem.allCases {
            XCTAssertEqual(ShellItem(legacyIndex: item.legacyIndex), item)
        }
    }

    func testTodayRoutes() {
        XCTAssertEqual(TodayRoute(legacyIndex: ShellTab.todayIndex), .dashboard)
        XCTAssertEqual(TodayRoute(legacyIndex: ShellTab.reportsIndex), .reports)
        XCTAssertEqual(TodayRoute(legacyIndex: ShellTab.settingsIndex), .settings)
        XCTAssertNil(TodayRoute(legacyIndex: ShellTab.inboxIndex))
    }

    func testIntentDestinationsStillResolve() {
        XCTAssertEqual(ShellItem(legacyIndex: LandlordHoursIntentDestination.track.tabIndex), .logTime)
        XCTAssertEqual(ShellItem(legacyIndex: LandlordHoursIntentDestination.properties.tabIndex), .rentals)
        XCTAssertEqual(ShellItem(legacyIndex: LandlordHoursIntentDestination.settings.tabIndex), .today)
        XCTAssertEqual(TodayRoute(legacyIndex: LandlordHoursIntentDestination.settings.tabIndex), .settings)
    }

    // MARK: Tokens (§B.2, §H.4)

    func testPageTokensMatchTheStandard() {
        XCTAssertEqual(BrandHex.duskTop, "EAE3D7")
        XCTAssertEqual(BrandHex.duskMid, "D8CFC0")
        XCTAssertEqual(BrandHex.duskBottom, "E8E0D3")
        XCTAssertEqual(BrandHex.darkNightTop, "0B1230")
        XCTAssertEqual(BrandHex.darkNightBottom, "080C1D")
        XCTAssertEqual(BrandHex.pageCardEdge, "A3966F")
        XCTAssertEqual(BrandHex.darkPageCardEdge, "2A3560")
        XCTAssertEqual(BrandHex.behind, "9A3624")
        XCTAssertEqual(BrandHex.positiveOnPage, "0C5A30")
        XCTAssertEqual(BrandHex.heroChipHairline, "C9BFA8")
        XCTAssertEqual(LHPage.midLocation, 0.32)
    }

    func testComponentMetrics() {
        XCTAssertEqual(LHButton.Metrics.primaryHeight, 52)
        XCTAssertEqual(LHButton.Metrics.controlHeight, 44)
        XCTAssertEqual(LHTag.height, 20)
        XCTAssertEqual(LHChip.height, 34)
        XCTAssertEqual(LHField.height, 52)
        XCTAssertEqual(LHField.multilineMinHeight, 104)
        XCTAssertEqual(LHSegmented<Int>.height, 36)
        XCTAssertEqual(LHSegmented<Int>.minSegmentWidth, 64)
        XCTAssertEqual(LHMetrics.gutter, 20)
        XCTAssertEqual(LHMetrics.cardRadius, 20)
        XCTAssertEqual(LHRow.actionDividerInset, 50)
        XCTAssertEqual(LHStepper.repeatDelay, 0.4)
        XCTAssertEqual(LHStepper.repeatInterval, 0.12)
    }

    func testRingClamp() {
        XCTAssertEqual(LHRing<EmptyView>.clamped(1.4), 1)
        XCTAssertEqual(LHRing<EmptyView>.clamped(-0.2), 0)
        XCTAssertEqual(LHRing<EmptyView>.clamped(.nan), 0)
        XCTAssertEqual(LHRing<EmptyView>.clamped(0.27), 0.27)
    }
}
