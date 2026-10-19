import XCTest
import SwiftUI
@testable import LandlordHours

/// 2.0 brand typography (docs/design/2.0-brand-system.md §3): Fraunces is bundled and registered,
/// used only at 28pt and up, and scales with Dynamic Type.
final class BrandTypographyTests: XCTestCase {

    func testFrauncesIsBundledAndRegistered() {
        XCTAssertNotNil(Bundle.main.url(forResource: "Fraunces", withExtension: "ttf"), "Fraunces.ttf missing from the app bundle")
        XCTAssertNotNil(Bundle.main.url(forResource: "Fraunces-OFL", withExtension: "txt"), "OFL licence text missing from the app bundle")
        XCTAssertTrue(LHFont.isFrauncesAvailable, "UIAppFonts did not register Fraunces; families: \(UIFont.familyNames.sorted())")
    }

    func testDisplayStylesNeverGoBelowTheFrauncesFloor() {
        for style in LHDisplayStyle.allCases {
            XCTAssertGreaterThanOrEqual(style.size, LHFont.frauncesMinimumSize, "\(style) is under 28pt")
        }
    }

    func testDisplayFontUsesFraunces() {
        for style in LHDisplayStyle.allCases {
            let font = LHFont.frauncesUIFont(style)
            XCTAssertEqual(font.familyName, LHFont.frauncesFamily)
            XCTAssertEqual(font.pointSize, style.size, accuracy: 0.5, "\(style) at the default content size")
        }
    }

    func testDisplayFontFollowsDynamicType() {
        let regular = LHFont.frauncesUIFont(.largeTitle, contentSize: .large)
        let bigger = LHFont.frauncesUIFont(.largeTitle, contentSize: .accessibilityExtraLarge)
        let smaller = LHFont.frauncesUIFont(.largeTitle, contentSize: .extraSmall)
        XCTAssertGreaterThan(bigger.pointSize, regular.pointSize)
        XCTAssertLessThanOrEqual(smaller.pointSize, regular.pointSize)
    }

    func testAxisTagEncoding() {
        // 'wght' = 0x77676874
        XCTAssertEqual(LHFont.axisTag("wght"), 0x7767_6874)
    }
}

extension BrandTypographyTests {
    func testSmallestDynamicTypeKeepsTheFloor() {
        for style in LHDisplayStyle.allCases {
            let font = LHFont.frauncesUIFont(style, contentSize: .extraSmall)
            XCTAssertGreaterThanOrEqual(font.pointSize, LHFont.frauncesMinimumSize)
        }
    }
}

extension BrandTypographyTests {
    func testHeroNumberScalesWithDynamicTypeAndIsCapped() {
        XCTAssertEqual(LHFont.heroNumberSize(contentSize: .large), LHFont.heroNumberBaseSize, accuracy: 0.5)
        XCTAssertGreaterThan(LHFont.heroNumberSize(contentSize: .extraExtraExtraLarge), LHFont.heroNumberBaseSize)
        XCTAssertLessThan(LHFont.heroNumberSize(contentSize: .extraSmall), LHFont.heroNumberBaseSize)
        for size in [UIContentSizeCategory.accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
                     .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge] {
            XCTAssertLessThanOrEqual(LHFont.heroNumberSize(contentSize: size), LHFont.heroNumberMaxSize, "\(size.rawValue)")
        }
        XCTAssertEqual(LHFont.heroNumberSize(contentSize: .accessibilityExtraExtraExtraLarge), LHFont.heroNumberMaxSize, accuracy: 0.5)
    }
}
