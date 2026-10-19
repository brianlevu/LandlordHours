import UIKit
import ObjectiveC

/// Light status-bar content over the blueprint band WITHOUT forcing the window dark (a dark
/// window would also give a light-mode user a dark keyboard). SwiftUI has no status-bar-style
/// API, so the sandbox overrides `preferredStatusBarStyle` on the root hosting controller's class.
/// Production would do this in its own root controller; this is a sandbox shim.
@MainActor
enum StatusBarStyler {
    static var style: UIStatusBarStyle = .default
    private static var installedOn: AnyClass?

    static func set(_ newStyle: UIStatusBarStyle) {
        style = newStyle
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first?.rootViewController
        else { return }
        let cls: AnyClass = type(of: root)
        if installedOn !== cls {
            let sel = #selector(getter: UIViewController.preferredStatusBarStyle)
            let block: @convention(block) (AnyObject) -> Int = { _ in
                MainActor.assumeIsolated { StatusBarStyler.style.rawValue }
            }
            class_replaceMethod(cls, sel, imp_implementationWithBlock(block), "q@:")
            installedOn = cls
        }
        root.setNeedsStatusBarAppearanceUpdate()
    }
}
