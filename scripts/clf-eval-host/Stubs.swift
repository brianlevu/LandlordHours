import Foundation
// Host-only stand-in: ClassifierChain.forStore references the inbox store.
@MainActor final class SuggestionStore { var muteRules: [CaptureMuteRule] = [] }
