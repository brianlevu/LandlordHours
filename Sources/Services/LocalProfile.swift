import Foundation
import os.log

private let profileLogger = Logger(subsystem: "com.openclaw.landlordhours", category: "Profile")

// MARK: - Auth / profile keys

/// Unscoped keys that identify who is using the app on this device.
///
/// 1.1 replaced the fake email sign-in with local profiles. An existing email
/// user's ID (`email-<address>`) is kept byte-for-byte as an opaque local profile
/// ID, so no data key, attachment file or CloudKit record moves.
enum ProfileKeys {
    static let appleUserId = "appleUserId"
    static let appleUserName = "appleUserName"
    static let appleUserEmail = "appleUserEmail"

    /// Legacy (≤1.0.6) email "sign-in". Read-only fallback after 1.1.
    static let emailUserId = "emailUserId"
    static let emailUserName = "emailUserName"
    static let emailUserEmail = "emailUserEmail"

    /// 1.1 local profile (no account). Holds either a migrated `email-…` ID or `local-<UUID>`.
    static let localProfileId = "localProfileId"
    static let localProfileName = "localProfileName"
    static let localProfileEmail = "localProfileEmail"

    static let loginType = "loginType"

    /// The profile that was active before the last sign-out / switch. Used to carry
    /// Pro over to the next profile on this device.
    static let previousProfileId = "previousProfileId"

    /// Every key cleared by sign-out (the previous-profile pointer is kept on purpose).
    static let signOutKeys = [
        appleUserId, appleUserName, appleUserEmail,
        emailUserId, emailUserName, emailUserEmail,
        localProfileId, localProfileName, localProfileEmail,
        loginType
    ]

    static let emailProfilePrefix = "email-"
    static let localProfilePrefix = "local-"

    /// Resolves the active profile ID: Apple ID first, then a local profile, then the
    /// legacy email ID (only present if migration has not run yet).
    static func resolveUserId(_ defaults: UserDefaults = .standard) -> String? {
        nonEmpty(defaults.string(forKey: appleUserId))
            ?? nonEmpty(defaults.string(forKey: localProfileId))
            ?? nonEmpty(defaults.string(forKey: emailUserId))
    }

    static func newLocalProfileId() -> String {
        localProfilePrefix + UUID().uuidString
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

// MARK: - Email → local profile migration

enum ProfileMigration {
    enum Outcome: Equatable {
        /// An Apple ID is active; nothing touched.
        case skippedAppleUser
        /// No legacy email profile is active.
        case nothingToMigrate
        /// The email profile now lives under `localProfileId` (same ID).
        case migrated(profileId: String)
        /// A different local profile is already active; the email keys are left alone.
        case conflictLeftAlone(localId: String, emailId: String)
    }

    /// Converts a ≤1.0.6 email "account" into a 1.1 local profile without changing its ID.
    ///
    /// Crash-safe and idempotent: local keys are written first and the email keys are
    /// deleted last, and `UserScope` resolves `localProfileId ?? emailUserId`, so every
    /// intermediate state resolves to the same ID X.
    @discardableResult
    static func migrateEmailProfile(defaults: UserDefaults = .standard) -> Outcome {
        if let apple = defaults.string(forKey: ProfileKeys.appleUserId), !apple.isEmpty {
            return .skippedAppleUser
        }
        guard let emailId = defaults.string(forKey: ProfileKeys.emailUserId), !emailId.isEmpty else {
            return .nothingToMigrate
        }

        let existingLocal = defaults.string(forKey: ProfileKeys.localProfileId)
        if let existingLocal, !existingLocal.isEmpty, existingLocal != emailId {
            profileLogger.warning("Email profile migration skipped: a different local profile is active")
            return .conflictLeftAlone(localId: existingLocal, emailId: emailId)
        }

        // Step 1: write the local profile (same ID) and labels.
        if existingLocal != emailId {
            defaults.set(emailId, forKey: ProfileKeys.localProfileId)
        }
        if defaults.string(forKey: ProfileKeys.localProfileName) == nil,
           let name = defaults.string(forKey: ProfileKeys.emailUserName), !name.isEmpty {
            defaults.set(name, forKey: ProfileKeys.localProfileName)
        }
        if defaults.string(forKey: ProfileKeys.localProfileEmail) == nil,
           let email = defaults.string(forKey: ProfileKeys.emailUserEmail), !email.isEmpty {
            defaults.set(email, forKey: ProfileKeys.localProfileEmail)
        }
        defaults.set(LoginType.local.rawValue, forKey: ProfileKeys.loginType)

        // Step 2: only now remove the legacy email keys — the ID last, so a crash in
        // between leaves `emailUserId` set and the next launch finishes the cleanup.
        defaults.removeObject(forKey: ProfileKeys.emailUserName)
        defaults.removeObject(forKey: ProfileKeys.emailUserEmail)
        defaults.removeObject(forKey: ProfileKeys.emailUserId)
        return .migrated(profileId: emailId)
    }
}

// MARK: - Pro carry-over

/// Pro is bought by the App Store account on this device, not by a profile, but it is
/// cached per profile ID (`u.<id>.isProUser`). When the active profile changes on the
/// same device, carry the cached flag over so Pro never disappears while StoreKit
/// re-checks `Transaction.currentEntitlements` (see `SubscriptionManager.reload()`).
enum ProEntitlementCarryOver {
    static let proKeys = ["isProUser", "hasPurchasedPro"]

    /// Copies `true` Pro flags from `fromId` to `toId`. Never removes Pro.
    /// Returns true if anything was copied.
    @discardableResult
    static func carry(from fromId: String?, to toId: String?, defaults: UserDefaults = .standard) -> Bool {
        guard let fromId, let toId, fromId != toId else { return false }
        var copied = false
        for key in proKeys {
            let source = UserScope.key(key, userId: fromId)
            let target = UserScope.key(key, userId: toId)
            if defaults.bool(forKey: source) && !defaults.bool(forKey: target) {
                defaults.set(true, forKey: target)
                copied = true
            }
        }
        return copied
    }

    /// Carries Pro from the profile that was active before the last sign-out/switch
    /// to the profile active now, then forgets the pointer.
    @discardableResult
    static func carryFromPreviousProfile(defaults: UserDefaults = .standard) -> Bool {
        let previous = defaults.string(forKey: ProfileKeys.previousProfileId)
        let current = ProfileKeys.resolveUserId(defaults)
        let copied = carry(from: previous, to: current, defaults: defaults)
        if current != nil {
            defaults.removeObject(forKey: ProfileKeys.previousProfileId)
        }
        return copied
    }
}

// MARK: - Profile discovery

struct DiscoveredProfile: Identifiable, Equatable {
    enum Source: String, Hashable {
        case device
        case iCloud
    }

    let id: String
    var entryCount: Int
    var propertyCount: Int
    var lastEntryDate: Date?
    var sources: Set<Source>
    /// Display name saved for this profile, if known (device only).
    var name: String?

    var isOnDevice: Bool { sources.contains(.device) }
    var isICloudOnly: Bool { !isOnDevice && sources.contains(.iCloud) }

    var displayLabel: String {
        if id.hasPrefix(ProfileKeys.emailProfilePrefix) {
            return ProfileDiscovery.maskedEmail(String(id.dropFirst(ProfileKeys.emailProfilePrefix.count)))
        }
        if let name, !name.isEmpty { return name }
        return "Profile without an account"
    }
}

/// A single CloudKit record reduced to what discovery needs.
struct CloudRecordSummary: Equatable {
    let appUserId: String?
    let recordType: String
    let date: Date?
}

/// Abstracts the discovery-only iCloud fetch so it can be faked in tests.
@MainActor
protocol CloudProfileRecordSource: AnyObject {
    func fetchProfileRecordSummaries() async throws -> [CloudRecordSummary]
}

enum ProfileDiscovery {
    static let entriesSuffix = ".LandlordHours.entries"
    static let propertiesSuffix = ".LandlordHours.properties"

    /// Profiles that can be restored: legacy `email-*` profiles plus `local-*`
    /// profiles left on the device by "Switch profile". Apple IDs come back via
    /// Sign in with Apple and DEBUG `debug-*` scenarios are never offered.
    static func isRestorableProfileId(_ id: String) -> Bool {
        id.hasPrefix(ProfileKeys.emailProfilePrefix) || id.hasPrefix(ProfileKeys.localProfilePrefix)
    }

    /// Scans `u.<id>.LandlordHours.entries|properties` keys for inactive restorable profiles.
    static func deviceProfiles(defaults: UserDefaults = .standard, excluding activeId: String?) -> [DiscoveredProfile] {
        var ids = Set<String>()
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("u.") {
            for suffix in [entriesSuffix, propertiesSuffix] where key.hasSuffix(suffix) {
                let start = key.index(key.startIndex, offsetBy: 2)
                let end = key.index(key.endIndex, offsetBy: -suffix.count)
                guard start < end else { continue }
                let id = String(key[start..<end])
                if isRestorableProfileId(id) && id != activeId {
                    ids.insert(id)
                }
            }
        }

        var results: [DiscoveredProfile] = []
        for id in ids {
            var decodeFailed = false
            var entries: [TimeEntry] = []
            var properties: [RentalProperty] = []
            if let data = defaults.data(forKey: UserScope.key("LandlordHours.entries", userId: id)) {
                do { entries = try JSONDecoder().decode([TimeEntry].self, from: data) } catch { decodeFailed = true }
            }
            if let data = defaults.data(forKey: UserScope.key("LandlordHours.properties", userId: id)) {
                do { properties = try JSONDecoder().decode([RentalProperty].self, from: data) } catch { decodeFailed = true }
            }
            // An empty profile has nothing to restore; a corrupt one is still offered so
            // the records are never hidden.
            guard decodeFailed || !entries.isEmpty || !properties.isEmpty else { continue }
            results.append(DiscoveredProfile(
                id: id,
                entryCount: entries.count,
                propertyCount: properties.count,
                lastEntryDate: entries.map(\.date).max(),
                sources: [.device],
                name: savedName(for: id, defaults: defaults)
            ))
        }
        return sorted(results)
    }

    /// Groups discovery-only CloudKit records by `appUserId`.
    static func cloudProfiles(from records: [CloudRecordSummary], excluding activeId: String?) -> [DiscoveredProfile] {
        var byId: [String: DiscoveredProfile] = [:]
        for record in records {
            guard let owner = record.appUserId, isRestorableProfileId(owner), owner != activeId else { continue }
            var profile = byId[owner] ?? DiscoveredProfile(
                id: owner, entryCount: 0, propertyCount: 0, lastEntryDate: nil, sources: [.iCloud], name: nil
            )
            switch record.recordType {
            case "TimeEntry":
                profile.entryCount += 1
                if let date = record.date {
                    profile.lastEntryDate = max(profile.lastEntryDate ?? date, date)
                }
            case "Property":
                profile.propertyCount += 1
            default:
                break
            }
            byId[owner] = profile
        }
        // Only offer profiles that actually hold records worth restoring.
        return sorted(byId.values.filter { $0.entryCount > 0 || $0.propertyCount > 0 })
    }

    /// Merges device and iCloud results by ID. Device counts win (they are what this
    /// iPhone will show); sources are unioned.
    static func merge(device: [DiscoveredProfile], cloud: [DiscoveredProfile]) -> [DiscoveredProfile] {
        var byId: [String: DiscoveredProfile] = [:]
        for profile in device { byId[profile.id] = profile }
        for profile in cloud {
            if var existing = byId[profile.id] {
                existing.sources.formUnion(profile.sources)
                byId[profile.id] = existing
            } else {
                byId[profile.id] = profile
            }
        }
        return sorted(Array(byId.values))
    }

    /// `brian@gmail.com` → `b•••@gmail.com`
    static func maskedEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let first = parts[0].first else { return email.isEmpty ? "Earlier profile" : "•••" }
        return "\(first)•••@\(parts[1])"
    }

    private static func savedName(for id: String, defaults: UserDefaults) -> String? {
        if defaults.string(forKey: ProfileKeys.localProfileId) == id {
            return defaults.string(forKey: ProfileKeys.localProfileName)
        }
        return defaults.string(forKey: UserScope.key(ProfileRestore.profileNameKey, userId: id))
    }

    private static func sorted(_ profiles: [DiscoveredProfile]) -> [DiscoveredProfile] {
        profiles.sorted {
            let lhs = $0.lastEntryDate ?? .distantPast
            let rhs = $1.lastEntryDate ?? .distantPast
            if lhs != rhs { return lhs > rhs }
            return $0.id < $1.id
        }
    }
}

// MARK: - Restore

enum ProfileRestore {
    /// Scoped key that remembers a local profile's display name after it is switched away.
    static let profileNameKey = "profile.displayName"

    /// Makes `profile` the active local profile. Call `AppViewModel.signIn()` afterwards.
    ///
    /// For an iCloud-only profile, `u.X.cloudkit.migrationDone` is set **before** the
    /// profile becomes active, so `CloudKitSyncService.start()` pulls before it ever
    /// pushes; otherwise empty local state (and default GoalSettings-X / TaxProfile-X
    /// records) would overwrite the iCloud copies.
    static func activate(_ profile: DiscoveredProfile, defaults: UserDefaults = .standard) {
        let id = profile.id
        if !profile.isOnDevice {
            defaults.set(true, forKey: UserScope.key("cloudkit.migrationDone", userId: id))
            // Force a full zone fetch for this profile.
            defaults.removeObject(forKey: UserScope.key("cloudkit.zoneChangeToken", userId: id))
            defaults.removeObject(forKey: UserScope.key("cloudkit.changeToken", userId: id))
            // A restored profile has already been through onboarding.
            defaults.set(true, forKey: UserScope.key("hasCompletedOnboarding", userId: id))
        }
        defaults.set(id, forKey: ProfileKeys.localProfileId)
        if let name = profile.name ?? defaults.string(forKey: UserScope.key(profileNameKey, userId: id)), !name.isEmpty {
            defaults.set(name, forKey: ProfileKeys.localProfileName)
        } else {
            defaults.removeObject(forKey: ProfileKeys.localProfileName)
        }
        if id.hasPrefix(ProfileKeys.emailProfilePrefix) {
            defaults.set(String(id.dropFirst(ProfileKeys.emailProfilePrefix.count)), forKey: ProfileKeys.localProfileEmail)
        } else {
            defaults.removeObject(forKey: ProfileKeys.localProfileEmail)
        }
        defaults.set(LoginType.local.rawValue, forKey: ProfileKeys.loginType)
    }
}
