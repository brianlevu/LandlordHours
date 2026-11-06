import Foundation

// MARK: - Legacy profile keys (read-only in 2.2)
//
// 1.x and 2.0 kept "who is using the app" in a handful of unscoped keys and scoped every record
// key as `u.<id>.*`. 2.2 has no profiles (iCloud is the identity, package K), but the inventory
// (`LegacyInventory`) still reads these keys to find every earlier group, and Delete all data
// removes them. Nothing in 2.2 writes them.

enum ProfileKeys {
    static let appleUserId = "appleUserId"
    static let appleUserName = "appleUserName"
    static let appleUserEmail = "appleUserEmail"

    /// ≤1.0.6 email "sign-in".
    static let emailUserId = "emailUserId"
    static let emailUserName = "emailUserName"
    static let emailUserEmail = "emailUserEmail"

    /// 1.1 / 2.0 local profile: a migrated `email-…` id or `local-<UUID>`.
    static let localProfileId = "localProfileId"
    static let localProfileName = "localProfileName"
    static let localProfileEmail = "localProfileEmail"

    static let loginType = "loginType"

    /// The profile active before the last 2.0 sign-out / switch.
    static let previousProfileId = "previousProfileId"

    /// Every unscoped sign-in key 1.x / 2.0 wrote.
    static let signOutKeys = [
        appleUserId, appleUserName, appleUserEmail,
        emailUserId, emailUserName, emailUserEmail,
        localProfileId, localProfileName, localProfileEmail,
        loginType
    ]

    static let emailProfilePrefix = "email-"
    static let localProfilePrefix = "local-"

    /// The id 2.0 would have treated as active: Apple, then local, then the legacy email.
    static func resolveUserId(_ defaults: UserDefaults = .standard) -> String? {
        nonEmpty(defaults.string(forKey: appleUserId))
            ?? nonEmpty(defaults.string(forKey: localProfileId))
            ?? nonEmpty(defaults.string(forKey: emailUserId))
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
