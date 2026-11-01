import Foundation

// MARK: - Inbox quiet (seam; owner: package F)
//
// `InboxViewModel.visible` reads the main list through here. Package F fills it in; until then it
// returns its input unchanged.
extension InboxLogic {
    static func mainList(_ suggestions: [Suggestion]) -> [Suggestion] {
        suggestions
    }
}
