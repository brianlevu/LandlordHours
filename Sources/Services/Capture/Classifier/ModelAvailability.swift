import Foundation

// MARK: - Model availability (app-level)
//
// One availability type for both Apple models, so the chain, tests and Settings can reason
// about "why is the model not used" without importing FoundationModels (iOS 26+/27+).
enum ModelAvailability: Equatable {
    case available
    case unavailable(ModelUnavailableReason)

    var isAvailable: Bool { self == .available }
}

enum ModelUnavailableReason: Equatable {
    /// The OS predates the model (SystemLanguageModel iOS 26, PCC iOS 27).
    case osTooOld
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    /// On-device model assets still downloading.
    case modelNotReady
    /// PCC: the system is not ready yet.
    case systemNotReady
    /// PCC: the user's quota is used up until `resetDate`.
    case quotaReached(resetDate: Date?)
    /// PCC: offline or the service did not answer.
    case serviceUnavailable
    /// The user turned it off in Settings.
    case disabledByUser
    /// Remote kill switch (CaptureFlag).
    case disabledByFlag
    /// The interface exists but the feature ships later (PCC receipts: 2.1).
    case notYetSupported
}
