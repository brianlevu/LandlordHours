#if DEBUG
import Foundation

// DEBUG launch seeds that are not about identity: Track timer drafts and the Welcome states.
// Both write an isolated DEBUG scope (`u.<id>.`, `IdentityScope.debugScopeKey`), so a capture
// never touches the person's `v2.` record set. Identity fixtures live in IdentityFixtures.swift.

extension AppViewModel {
    func seedLegacyEmailFixtureIfNeeded() {
        if ProcessInfo.processInfo.arguments.contains("-LHResetProfilesForTesting") {
            IdentityFixtures.resetIdentity(defaults: .standard, root: MigrationFiles.defaultRoot)
        }
        TimerDraftFixture.seedIfRequested()
        WelcomeStateFixture.seedIfRequested()
    }
}

/// DEBUG-only: `-LHSeedTimerDraft <scenario>` seeds a local profile with Track timer drafts
/// for UI tests and visual-gate captures. Scenarios: pausedShort, forgotten24h, twoPending,
/// deletedProperty, noProperties, pausedOver24h.
enum TimerDraftFixture {
    static let profileId = "local-timer-draft-fixture"
    static let oak = UUID(uuidString: "6F1E2D3C-0000-4000-8000-0000000000A1")!
    static let pine = UUID(uuidString: "6F1E2D3C-0000-4000-8000-0000000000A2")!

    @MainActor
    static func seedIfRequested(defaults: UserDefaults = .standard) {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-LHSeedTimerDraft"), args.indices.contains(index + 1) else { return }
        seed(args[index + 1], defaults: defaults)
    }

    @MainActor
    static func seed(_ scenario: String, defaults: UserDefaults = .standard, now: Date = Date()) {
        AppViewModel.clearScopedAccountData(for: profileId)
        // An isolated DEBUG scope (`u.<id>.`), never the person's `v2.` record set.
        defaults.set(profileId, forKey: IdentityScope.debugScopeKey)
        defaults.set("Frames", forKey: "u.\(profileId).profile.name")
        for key in ["hasCompletedOnboarding", "legacyDataMigrated", GuidedOnboardingStore.completedKey] {
            defaults.set(true, forKey: UserScope.key(key, userId: profileId))
        }

        func hoursAgo(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }
        func paused(_ property: UUID, _ category: ActivityCategory, startedAgo: Double, ran: Double) -> StaleTimerRecovery {
            StaleTimerRecovery(startTime: hoursAgo(startedAgo), propertyId: property, category: category,
                               elapsedHours: ran, reason: .pausedAtSwitch, pausedAt: hoursAgo(startedAgo - ran))
        }
        let oakProperty = RentalProperty(id: oak, name: "Oak Street Duplex", address: "123 Oak St", propertyType: .ltr)
        let pineProperty = RentalProperty(id: pine, name: "Pine Lake Cabin", address: "9 Shore Rd", propertyType: .str)

        var properties = [oakProperty]
        var drafts: [StaleTimerRecovery]
        switch scenario {
        case "forgotten24h":
            drafts = [StaleTimerRecovery(startTime: hoursAgo(30), propertyId: oak, category: .management, elapsedHours: 30)]
        case "twoPending":
            drafts = [paused(oak, .repairs, startedAgo: 3, ran: 1.25), paused(oak, .management, startedAgo: 1, ran: 0.2)]
        case "deletedProperty":
            properties = [pineProperty]
            drafts = [paused(oak, .repairs, startedAgo: 2, ran: 0.75)]
        case "noProperties":
            properties = []
            drafts = [paused(oak, .repairs, startedAgo: 2, ran: 0.75)]
        case "pausedOver24h":
            drafts = [paused(oak, .repairs, startedAgo: 30, ran: 26)]
        default: // pausedShort
            drafts = [paused(oak, .repairs, startedAgo: 0.5, ran: 2.0 / 60.0)]
        }
        defaults.set(try? JSONEncoder().encode(properties), forKey: UserScope.key("LandlordHours.properties", userId: profileId))
        defaults.set(try? JSONEncoder().encode([TimeEntry]()), forKey: UserScope.key("LandlordHours.entries", userId: profileId))
        defaults.set(try? JSONEncoder().encode(drafts), forKey: UserScope.key("LandlordHours.staleTimerRecoveries", userId: profileId))
    }
}

/// DEBUG-only: `-LHSeedWelcomeState deadEnd|completed` seeds an isolated DEBUG scope.
/// - deadEnd: onboarding started and never finished (Welcome shows again).
/// - completed: onboarding finished (pair with `-LHForceWelcome` to see Welcome).
enum WelcomeStateFixture {
    static let profileId = "local-welcome-fixture"

    @MainActor
    static func seedIfRequested(defaults: UserDefaults = .standard) {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-LHSeedWelcomeState"), args.indices.contains(index + 1) else { return }
        let state = args[index + 1]
        AppViewModel.clearScopedAccountData(for: profileId)
        defaults.set(profileId, forKey: IdentityScope.debugScopeKey)
        let onboardingKey = UserScope.key("hasCompletedOnboarding", userId: profileId)
        if state == "completed" {
            defaults.set(true, forKey: onboardingKey)
            defaults.set(true, forKey: UserScope.key("legacyDataMigrated", userId: profileId))
            defaults.set(true, forKey: UserScope.key(GuidedOnboardingStore.completedKey, userId: profileId))
        } else {
            defaults.removeObject(forKey: onboardingKey)
        }
    }

    static var forceWelcome: Bool { ProcessInfo.processInfo.arguments.contains("-LHForceWelcome") }
}

#endif
