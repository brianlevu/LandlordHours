import SwiftUI

// MARK: - The Duo lane's hooks (owner: branch feat/duo-door; docs/plans/two-pane-api.md)
//
// The one file the Duo lane replaces to plug posture detection and the door into `TwoPaneLayout`.
// Until it does, the Duo gets exactly the iPad's layout with no division: two-pane when the open
// Duo's window is at least 800 × 645, compact otherwise.

extension TwoPaneHooks {
    /// The hooks the app's root installs (`TwoPaneHooks.installed`).
    @MainActor static var duo: TwoPaneHooks { .none }
}
