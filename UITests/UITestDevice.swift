import UIKit

/// The device word the catalog's device variations resolve to on this run ("iPad" or "iPhone"),
/// so a test can still assert the exact text for its device.
enum UITestDevice {
    static var name: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }
}
