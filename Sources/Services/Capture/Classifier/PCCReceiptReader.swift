import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Private Cloud Compute receipt reader (interface + availability only)
//
// 2.0 ships the plumbing; reading receipts with PCC ships in 2.1 (WP7). PCC runs on Apple's
// servers (stateless; Apple-operated), so it only ever sees two things: receipts (2.1) and a
// note the user types or says into the Log time sheet (2.0, NoteReaderChain, only when the
// on-device model can't answer). Calendar, location and Gmail data never go to PCC: the
// receipt request type below can only be built from receipt content, and `mayProcess(kind:)`
// refuses every other suggestion kind.
//
// Gates, in order (`PCCGate`, shared by receipts and Log notes): user setting (default on) →
// remote flag (CaptureFlag.privateCloudCompute) → OS (iOS 27) →
// PrivateCloudComputeLanguageModel.isAvailable → quota. Anything closed → the caller uses
// the rules (and, for notes, the on-device model).

/// Receipt content for PCC. Deliberately has no calendar fields.
struct ReceiptReadRequest: Equatable {
    var recognizedText: String
    var imageData: Data?
    /// `SuggestionKey.receipt(...)` of the file.
    var sourceKey: String
}

/// What a receipt read produced.
enum ReceiptReadOutcome: Equatable {
    /// PCC can't be used now: classify with rules instead.
    case useRules(ModelUnavailableReason)
}

/// The user's Settings toggle ("Private Cloud Compute", Settings → Auto-capture). Default on.
struct PCCSettings {
    static let enabledKey = "LandlordHours.capture.pccEnabled"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
    }
}

/// Whether this build is signed with the PCC entitlement. FoundationModels traps (a crash, not
/// an error) when an app without `com.apple.developer.private-cloud-compute` calls PCC, and
/// `PrivateCloudComputeLanguageModel.availability` still says `.available`. So availability
/// alone never opens PCC: the build must also say it carries the entitlement
/// (Info.plist `LHPrivateCloudComputeEntitled` = `$(LH_PCC_ENTITLED)`, NO by default).
enum PCCEntitlement {
    static let infoKey = "LHPrivateCloudComputeEntitled"

    static var isConfigured: Bool { isConfigured(in: .main) }

    static func isConfigured(in bundle: Bundle) -> Bool {
        let raw = bundle.object(forInfoDictionaryKey: infoKey)
        if let flag = raw as? Bool { return flag }
        if let text = raw as? String { return ["yes", "true", "1"].contains(text.lowercased()) }
        return false
    }
}

/// System PCC state, behind a protocol so tests inject every state.
protocol PCCSystemStatusProviding {
    func status() -> ModelAvailability
}

struct SystemPCCStatus: PCCSystemStatusProviding {
    func status() -> ModelAvailability {
        guard PCCEntitlement.isConfigured else { return .unavailable(.notEntitled) }
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) {
            let model = PrivateCloudComputeLanguageModel()
            return Self.map(availability: model.availability, isAvailable: model.isAvailable, quota: model.quotaUsage)
        }
        #endif
        return .unavailable(.osTooOld)
    }

    #if canImport(FoundationModels)
    @available(iOS 27.0, *)
    static func map(
        availability: PrivateCloudComputeLanguageModel.Availability,
        isAvailable: Bool,
        quota: PrivateCloudComputeLanguageModel.QuotaUsage
    ) -> ModelAvailability {
        switch availability {
        case .unavailable(.deviceNotEligible):
            return .unavailable(.deviceNotEligible)
        case .unavailable:
            return .unavailable(.systemNotReady)
        case .available:
            break
        }
        guard isAvailable else { return .unavailable(.systemNotReady) }
        if case .limitReached = quota.status {
            return .unavailable(.quotaReached(resetDate: quota.resetDate))
        }
        return .available
    }

    /// Maps a PCC call failure to a fallback reason (a quota hit mid-call falls back to rules).
    @available(iOS 27.0, *)
    static func reason(for error: Error) -> ModelUnavailableReason? {
        guard let pccError = error as? PrivateCloudComputeLanguageModel.Error else { return nil }
        switch pccError {
        case .quotaLimitReached(let info): return .quotaReached(resetDate: info.resetDate)
        case .serviceUnavailable, .networkFailure: return .serviceUnavailable
        @unknown default: return .serviceUnavailable
        }
    }
    #endif
}

/// The one place that decides whether PCC may run now: the user's setting, the remote kill
/// switch, then the system (OS, eligibility, readiness, quota).
struct PCCGate {
    /// DEBUG launch argument that opens the remote-flag gate for on-device PCC testing.
    static let forceLaunchArgument = "-LHForcePCC"

    let settings: PCCSettings
    let isFlagEnabled: () -> Bool
    let system: PCCSystemStatusProviding

    init(
        settings: PCCSettings = PCCSettings(),
        isFlagEnabled: @escaping () -> Bool = { CaptureFlags().isEnabled(.privateCloudCompute) },
        system: PCCSystemStatusProviding = SystemPCCStatus()
    ) {
        self.settings = settings
        self.isFlagEnabled = isFlagEnabled
        self.system = system
    }

    func availability() -> ModelAvailability {
        guard settings.isEnabled else { return .unavailable(.disabledByUser) }
        #if DEBUG
        // Owner testing: forces the remote flag open (the entitlement and the user toggle still apply).
        if ProcessInfo.processInfo.arguments.contains(PCCGate.forceLaunchArgument) { return system.status() }
        #endif
        guard isFlagEnabled() else { return .unavailable(.disabledByFlag) }
        return system.status()
    }
}

struct PCCReceiptReader {
    let settings: PCCSettings
    let isFlagEnabled: () -> Bool
    let system: PCCSystemStatusProviding

    init(
        settings: PCCSettings = PCCSettings(),
        isFlagEnabled: @escaping () -> Bool = { CaptureFlags().isEnabled(.privateCloudCompute) },
        system: PCCSystemStatusProviding = SystemPCCStatus()
    ) {
        self.settings = settings
        self.isFlagEnabled = isFlagEnabled
        self.system = system
    }

    /// PCC is for receipts only. Calendar, location and Gmail data never go to PCC.
    static func mayProcess(kind: Suggestion.Kind) -> Bool { kind == .receipt }

    /// Whether PCC may be used right now, and if not, why.
    func availability() -> ModelAvailability {
        PCCGate(settings: settings, isFlagEnabled: isFlagEnabled, system: system).availability()
    }

    /// 2.0: never calls PCC. Returns why rules must be used (closed gate, or "ships in 2.1").
    func read(_ request: ReceiptReadRequest) async -> ReceiptReadOutcome {
        switch availability() {
        case .unavailable(let reason):
            return .useRules(reason)
        case .available:
            // WP7 (2.1) adds the PCC session here (LanguageModelSession with the PCC model and
            // a receipt image attachment). Until then receipts use rules.
            return .useRules(.notYetSupported)
        }
    }
}
