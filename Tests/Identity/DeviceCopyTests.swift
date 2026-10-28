import XCTest
import UIKit
@testable import LandlordHours

/// The iCloud screen's footnote names the device it runs on: "this iPad" on iPad, "this iPhone" on
/// iPhone, from one catalog entry with device variations (never built by joining strings).
final class DeviceCopyTests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    func testICloudFooterNamesTheDevice() {
        let footer = IdentityCopy.footer
        if isPad {
            XCTAssertEqual(footer, "Your records live on this iPad and in your own iCloud. We never see them. Photos stay on this iPad.")
            XCTAssertFalse(footer.contains("iPhone"))
        } else {
            XCTAssertEqual(footer, "Your records live on this iPhone and in your own iCloud. We never see them. Photos stay on this iPhone.")
        }
    }

    func testOtherDeviceStringsFollowTheIdiom() {
        XCTAssertEqual(String(localized: "Delete from this iPhone?", table: "Identity"),
                       isPad ? "Delete from this iPad?" : "Delete from this iPhone?")
        XCTAssertEqual(String(localized: "Opens iPhone Settings", table: "Identity"),
                       isPad ? "Opens iPad Settings" : "Opens iPhone Settings")
    }
}
