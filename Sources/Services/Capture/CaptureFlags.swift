import Foundation
import PostHog

// MARK: - Capture feature flags (remote kill switches)
//
// Auto-capture features ship behind PostHog flags so a bad detector can be switched off
// without a release. PostHog may not answer: analytics opted out, never configured (tests, QA
// launches, DEBUG), offline, or flags not loaded yet. Resolution order:
//   1. a live remote value — used, and cached;
//   2. the last cached remote value (a kill switch stays killed for users who later opt out
//      or go offline);
//   3. the minimum-build gate: below the flag's minimum build → off;
//   4. the flag's built-in default.

enum CaptureFlag: String, CaseIterable {
    /// Master switch for calendar auto-capture (inbox + notifications).
    case autoCapture = "capture-auto"
    /// Private Cloud Compute for receipts and summaries.
    case privateCloudCompute = "capture-pcc"
    /// Location dwell detection (opt-in beta).
    case locationBeta = "capture-location-beta"
    /// On-device Gmail reader.
    case gmailReader = "capture-gmail"
    /// Apple's on-device model reading Log time notes (rules still fill when off).
    case noteModel = "capture-note-model"

    /// Value when nothing remote has ever been seen and the build passes the minimum gate.
    var defaultValue: Bool {
        switch self {
        case .autoCapture, .noteModel: return true
        // PCC is off until the entitlement ships and the owner turns the flag on remotely.
        case .privateCloudCompute, .locationBeta, .gmailReader: return false
        }
    }
}

/// Where remote flag values come from. Returns nil when no live value is available.
protocol CaptureFlagRemoteSource {
    func value(for flag: CaptureFlag) -> Bool?
}

/// PostHog-backed source. Never asks PostHog when analytics is off or the user opted out.
struct PostHogCaptureFlagSource: CaptureFlagRemoteSource {
    func value(for flag: CaptureFlag) -> Bool? {
        guard Analytics.isConfigured, !Analytics.isOptedOut else { return nil }
        guard let raw = PostHogSDK.shared.getFeatureFlag(flag.rawValue) else { return nil }
        if let bool = raw as? Bool { return bool }
        if let string = raw as? String { return !string.isEmpty && string != "false" && string != "off" }
        return nil
    }
}

struct CaptureFlags {
    static let cacheKeyPrefix = "LandlordHours.captureFlag."

    private let remote: CaptureFlagRemoteSource
    private let defaults: UserDefaults
    private let currentBuild: Int
    private let minimumBuilds: [CaptureFlag: Int]

    init(
        remote: CaptureFlagRemoteSource = PostHogCaptureFlagSource(),
        defaults: UserDefaults = .standard,
        currentBuild: Int = CaptureFlags.bundleBuildNumber,
        minimumBuilds: [CaptureFlag: Int] = [:]
    ) {
        self.remote = remote
        self.defaults = defaults
        self.currentBuild = currentBuild
        self.minimumBuilds = minimumBuilds
    }

    static var bundleBuildNumber: Int {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return Int(raw.filter(\.isNumber)) ?? 0
    }

    static func cacheKey(for flag: CaptureFlag) -> String { cacheKeyPrefix + flag.rawValue }

    func isEnabled(_ flag: CaptureFlag) -> Bool {
        let key = Self.cacheKey(for: flag)
        if let live = remote.value(for: flag) {
            defaults.set(live, forKey: key)
            return live
        }
        if let cached = defaults.object(forKey: key) as? Bool {
            return cached
        }
        if let minimum = minimumBuilds[flag], currentBuild < minimum {
            return false
        }
        return flag.defaultValue
    }
}

// MARK: - Event-ended prompt consent (per profile, opt-in)
//
// End-of-event notifications are opt-in. Off by default for new profiles AND for profiles
// upgraded from 1.x, even when calendar and notification permission were already granted.
// The inbox opt-in screens (WP3) turn it on through `AppViewModel.eventPromptsEnabled` (or
// `set(_:profileId:)`); the refresher reads it on every run and clears pending prompts when off.
enum CapturePromptConsent {
    static let baseKey = "LandlordHours.capture.eventPromptsEnabled"

    static func isEnabled(profileId: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: UserScope.key(baseKey, userId: profileId))
    }

    static func set(_ enabled: Bool, profileId: String, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: UserScope.key(baseKey, userId: profileId))
    }
}
