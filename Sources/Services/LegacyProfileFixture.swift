#if DEBUG
import Foundation

/// DEBUG-only journey fixture: writes UserDefaults exactly as LandlordHours 1.0.6 left
/// them for an email "account", so the 1.1 upgrade path (email → local profile
/// migration, no sign-in wall, Restore other data) can be exercised end to end.
///
/// Launch arguments (read before migration runs in `AppViewModel.init`):
/// - `-LHSeedLegacyEmailProfile`: email profile A signed in (2 properties, 5 entries)
///   plus a signed-out email profile B (1 property, 1 entry) left on the device.
/// - `-LHSeedLegacySignedOut`: the same two profiles, but nobody signed in (a 1.0.6
///   user who had signed out), so 1.1 shows the welcome screen with "Restore earlier data".
enum LegacyProfileFixture {
    static let activeEmail = "upgrade.tester@example.com"
    static let activeId = "email-" + activeEmail
    static let activeName = "Upgrade Tester"
    static let inactiveEmail = "old.profile@example.com"
    static let inactiveId = "email-" + inactiveEmail

    static var requestedMode: Mode? {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-LHSeedLegacyEmailProfile") { return .signedIn }
        if args.contains("-LHSeedLegacySignedOut") { return .signedOut }
        return nil
    }

    enum Mode {
        case signedIn
        case signedOut
    }

    /// Writes the 1.0.6-shaped state into `defaults`. Pure data seeding; never migrates.
    @MainActor
    static func seed(_ mode: Mode, defaults: UserDefaults = .standard, now: Date = Date()) {
        // 1.0.6 had no local profiles and no Apple user on this device.
        for key in ProfileKeys.signOutKeys + [ProfileKeys.previousProfileId] {
            defaults.removeObject(forKey: key)
        }
        for id in [activeId, inactiveId] {
            AppViewModel.clearScopedAccountData(for: id)
            defaults.removeObject(forKey: UserScope.key("LandlordHours.properties", userId: id))
            defaults.removeObject(forKey: UserScope.key("LandlordHours.entries", userId: id))
        }

        let calendar = Calendar.current
        func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: now) ?? now }

        // Profile A — 2 properties, 5 entries.
        let oak = RentalProperty(id: UUID(uuidString: "6F1E2D3C-0000-4000-8000-00000000A001")!, name: "Oak Street Duplex", address: "123 Oak St", propertyType: .ltr)
        let pine = RentalProperty(id: UUID(uuidString: "6F1E2D3C-0000-4000-8000-00000000A002")!, name: "Pine Lake Cabin", address: "9 Shore Rd", propertyType: .str)
        let entriesA: [TimeEntry] = [
            TimeEntry(propertyId: oak.id, participant: .selfParticipant, category: .repairs, hours: 3, date: daysAgo(1), notes: "Fixed porch steps"),
            TimeEntry(propertyId: oak.id, participant: .selfParticipant, category: .management, hours: 1.5, date: daysAgo(3), notes: "Tenant call"),
            TimeEntry(propertyId: pine.id, participant: .selfParticipant, category: .repairs, hours: 2, date: daysAgo(5), notes: "Replaced smoke detectors"),
            TimeEntry(propertyId: pine.id, participant: .selfParticipant, category: .management, hours: 4, date: daysAgo(8), notes: "Guest turnover"),
            TimeEntry(propertyId: oak.id, participant: .selfParticipant, category: .repairs, hours: 2.5, date: daysAgo(12), notes: "Painted hallway")
        ]
        write(properties: [oak, pine], entries: entriesA, for: activeId, defaults: defaults)

        // Profile B — signed out in 1.0.6, data left on the device.
        let elm = RentalProperty(id: UUID(uuidString: "6F1E2D3C-0000-4000-8000-00000000B001")!, name: "Elm Court", address: "45 Elm Ct", propertyType: .ltr)
        let entriesB = [
            TimeEntry(propertyId: elm.id, participant: .selfParticipant, category: .management, hours: 1, date: daysAgo(40), notes: "Lease renewal")
        ]
        write(properties: [elm], entries: entriesB, for: inactiveId, defaults: defaults)

        if mode == .signedIn {
            defaults.set(activeId, forKey: ProfileKeys.emailUserId)
            defaults.set(activeEmail, forKey: ProfileKeys.emailUserEmail)
            defaults.set(activeName, forKey: ProfileKeys.emailUserName)
            defaults.set(LoginType.email.rawValue, forKey: ProfileKeys.loginType)
        }
    }

    private static func write(properties: [RentalProperty], entries: [TimeEntry], for id: String, defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(properties), forKey: UserScope.key("LandlordHours.properties", userId: id))
        defaults.set(try? JSONEncoder().encode(entries), forKey: UserScope.key("LandlordHours.entries", userId: id))
        defaults.set(true, forKey: UserScope.key("hasCompletedOnboarding", userId: id))
        defaults.set(true, forKey: UserScope.key("legacyDataMigrated", userId: id))
        defaults.set(true, forKey: UserScope.key(GuidedOnboardingStore.completedKey, userId: id))
    }
}

extension AppViewModel {
    func seedLegacyEmailFixtureIfNeeded() {
        if ProcessInfo.processInfo.arguments.contains("-LHResetProfilesForTesting") {
            LegacyProfileFixture.resetAllRestorableProfiles()
        }
        guard let mode = LegacyProfileFixture.requestedMode else { return }
        LegacyProfileFixture.seed(mode)
    }
}

extension LegacyProfileFixture {
    /// Fresh-install state for UI captures: no active profile and no restorable
    /// `email-*` / `local-*` data. DEBUG launch argument only.
    static func resetAllRestorableProfiles(defaults: UserDefaults = .standard) {
        for key in ProfileKeys.signOutKeys + [ProfileKeys.previousProfileId] {
            defaults.removeObject(forKey: key)
        }
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("u.\(ProfileKeys.emailProfilePrefix)") || key.hasPrefix("u.\(ProfileKeys.localProfilePrefix)") {
            defaults.removeObject(forKey: key)
        }
    }
}
#endif
