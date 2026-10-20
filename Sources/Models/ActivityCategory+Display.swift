import SwiftUI

// MARK: - ActivityCategory display helpers still used by Today, Track and notifications
//
// Moved out of the 1.x Reports file when Reports was rebuilt (WP-R). New screens use the
// Blueprint tool art (`blueprintToolName`, `inboxLabel`, `inboxInk`) instead.
extension ActivityCategory {
    var lucideIconName: String {
        switch self {
        case .repairs: return "wrench"
        case .management: return "folder"
        case .leasing: return "key"
        case .bookkeeping: return "file-text"
        case .legal: return "landmark"
        case .insurance: return "shield"
        case .travel: return "car"
        case .renovations: return "hammer"
        case .investing: return "trending-up"
        case .financing: return "dollar-sign"
        case .contractNegotiation: return "file-cog"
        }
    }

    /// The category's ink from the one 2.0 colour map (AppColors.categoryInkHex).
    var color: Color { AppColors.categoryInk(self) }

    var chipLabel: String {
        switch self {
        case .repairs: return "Repairs"
        case .management: return "Management"
        case .leasing: return "Leasing"
        case .bookkeeping: return "Bookkeeping"
        case .legal: return "Legal"
        case .insurance: return "Insurance"
        case .travel: return "Travel"
        case .renovations: return "Renovations"
        case .investing: return "Investing"
        case .financing: return "Financing"
        case .contractNegotiation: return "Contracts"
        }
    }
}
