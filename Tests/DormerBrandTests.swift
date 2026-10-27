import SwiftUI
import XCTest
@testable import LandlordHours

/// The 2.2 rename to Dormer: the name under the icon, the identifiers that must NOT change, and the
/// mark's geometry (design/brand/dormer/make_dormer_icon.py is the source).
final class DormerBrandTests: XCTestCase {

    func testHomeScreenNameIsDormerThroughTheStringCatalog() {
        let localized = Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String
        let raw = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
        XCTAssertEqual(localized ?? raw, "Dormer")
        XCTAssertEqual(raw, "Dormer", "the development-language value in Info.plist matches the catalog")
        XCTAssertNotNil(Bundle.main.path(forResource: "InfoPlist", ofType: "strings"),
                        "CFBundleDisplayName goes through InfoPlist.xcstrings, so it can be localized")
    }

    func testIdentifiersAreUnchanged() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.openclaw.landlordhours")
        XCTAssertEqual(Bundle.main.infoDictionary?["CFBundleExecutable"] as? String, "LandlordHours")
    }

    func testAppIconIsTheAppIconSet() {
        let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        XCTAssertEqual(primary?["CFBundleIconName"] as? String, "AppIcon")
    }

    func testWordmarkSaysDormer() {
        XCTAssertEqual(DormerBrand.name, "Dormer")
    }

    /// The counter is a room, not a filled block: it stays open under both fill rules, and the
    /// stem, gable walls and point are ink.
    func testMarkCounterIsOpenUnderBothFillRules() {
        let rect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        let path = DormerMarkShape().path(in: rect)
        let room = CGPoint(x: 470, y: 512)
        let stem = CGPoint(x: 258, y: 512)
        let top = CGPoint(x: 450, y: 240)
        let point = CGPoint(x: 870, y: 470)
        let outside = CGPoint(x: 950, y: 200)
        for eo in [false, true] {
            XCTAssertFalse(path.contains(room, eoFill: eo), "counter open (eoFill \(eo))")
            XCTAssertTrue(path.contains(stem, eoFill: eo), "stem is ink (eoFill \(eo))")
            XCTAssertTrue(path.contains(top, eoFill: eo), "top wall is ink (eoFill \(eo))")
            XCTAssertTrue(path.contains(point, eoFill: eo), "gable point is ink (eoFill \(eo))")
            XCTAssertFalse(path.contains(outside, eoFill: eo))
        }
    }

    /// The mark sits where it sits on the app icon: inside the squircle's safe area, stem heavier
    /// than the walls (letter contrast).
    func testMarkGeometryMatchesTheIcon() {
        let b = DormerMarkShape().path(in: CGRect(x: 0, y: 0, width: 1024, height: 1024)).boundingRect
        XCTAssertEqual(b.minX, 172.96, accuracy: 0.5)
        XCTAssertEqual(b.minY, 183.36, accuracy: 0.5)
        XCTAssertEqual(b.maxY, 840.64, accuracy: 0.5)
        XCTAssertEqual(b.maxX, 888.0, accuracy: 1.0, "rounded point, past its own shoulder")
        let g = DormerMarkGeometry.self
        let stem = g.inner[0].x - g.outer[0].x
        let top = g.inner[0].y - g.outer[0].y
        XCTAssertGreaterThan(stem, top * 1.4)
    }

    func testCroppedMarkFillsItsFrame() {
        let b = DormerMarkShape(cropped: true).path(in: CGRect(x: 0, y: 0, width: 100, height: 100)).boundingRect
        XCTAssertEqual(b.width, 100, accuracy: 1.0)
        XCTAssertEqual(b.midY, 50, accuracy: 1.0)
    }
}
