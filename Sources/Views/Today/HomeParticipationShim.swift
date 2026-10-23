import SwiftUI

// TEMPORARY SHIM — delete before handoff. feat/home21-data adds `propertyName:` to
// ParticipationConfirmationSheet; until it merges, Today calls it through this.
extension ParticipationConfirmationSheet {
    init(year: Int, currentAnswer: Bool?, propertyName: String?, onAnswer: @escaping (Bool?) -> Void) {
        self.init(year: year, currentAnswer: currentAnswer, onAnswer: onAnswer)
    }
}
