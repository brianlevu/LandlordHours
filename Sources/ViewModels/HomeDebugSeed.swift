import Foundation

#if DEBUG
// MARK: - DEBUG seeding for the 2.1 home screen (compiled out of Release)
//
//   -LHHomeSeed brian|reps750|eight   after -LHMockScenario: replace the rentals, this year's
//                                     entries, the goal and the owner's per-rental answers.
//
//   brian    Goal 100 hours and more than anyone else. Delaney Ct (long stays, 84h, a manager does
//            most), Santa Ray Ave (a few nights, 12h, the owner does most), Yeandle Ave (long
//            stays, 0h). Added in that order, so the default focus (Santa Ray Ave) is NOT the
//            first rental in the list.
//   reps750  Goal 750, the owner is the real estate professional. Six long-stay rentals, 212h in all.
//   eight    Goal 100 hours. Eight rentals: two at 100 (Tahoe Cabin 64h, Lake House 112h), three at
//            500 (Palm Studio 230h, Birch Flat 310h, Maple Duplex 140h, a long stay the owner
//            switched to a target), three record only (Oak Street 40h, Cedar Row 22h, Pine Court 0h).
//
// Pro, spouse hours off, no grouping, guided onboarding skipped. Same data as the approved
// prototype (proto/home-options), on the real rules.
extension AppViewModel {
    func applyHomeSeedIfNeeded(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let i = arguments.firstIndex(of: "-LHHomeSeed"), arguments.indices.contains(i + 1) else { return }
        let set = arguments[i + 1]

        struct Seed {
            let name: String
            let type: PropertyType
            let hours: Double
            var who: WhoDoesMost? = nil
            var override: RentalOverride? = nil
        }
        let goal: GoalChoice
        let pro: RealEstatePro
        let seeds: [Seed]
        switch set {
        case "reps750":
            goal = .reps750; pro = .me
            seeds = [Seed(name: "Maple Duplex", type: .ltr, hours: 71), Seed(name: "Oak Street", type: .ltr, hours: 58),
                     Seed(name: "Birch Flat", type: .ltr, hours: 40), Seed(name: "Cedar Row", type: .ltr, hours: 22),
                     Seed(name: "Pine Court", type: .ltr, hours: 14), Seed(name: "Elm Lane", type: .ltr, hours: 7)]
        case "eight":
            goal = .mp100; pro = .nobody
            seeds = [Seed(name: "Tahoe Cabin", type: .str, hours: 64, who: .me),
                     Seed(name: "Lake House", type: .str, hours: 112, who: .meAndSpouse),
                     Seed(name: "Palm Studio", type: .str, hours: 230, who: .someoneElse),
                     Seed(name: "Birch Flat", type: .str, hours: 310, who: .notSure),
                     Seed(name: "Maple Duplex", type: .ltr, hours: 140, who: .someoneElse, override: .track),
                     Seed(name: "Oak Street", type: .ltr, hours: 40, who: .someoneElse),
                     Seed(name: "Cedar Row", type: .ltr, hours: 22),
                     Seed(name: "Pine Court", type: .ltr, hours: 0, who: .someoneElse)]
        default:
            goal = .mp100; pro = .nobody
            seeds = [Seed(name: "Delaney Ct", type: .ltr, hours: 84, who: .someoneElse),
                     Seed(name: "Santa Ray Ave", type: .str, hours: 12, who: .me),
                     Seed(name: "Yeandle Ave", type: .ltr, hours: 0)]
        }

        let wasSuppressed = suppressCelebrations
        suppressCelebrations = true
        defer { suppressCelebrations = wasSuppressed }

        GoalManager.shared.propertyGoals = []
        GoalManager.shared.setGoalChoice(goal)
        GoalManager.shared.setGoalSetup(rental: seeds.contains { $0.type == .str } ? .both : .longTerm, pro: pro)
        TaxProfileManager.shared.spouseTracking = false
        TaxProfileManager.shared.groupingElection = false
        GuidedOnboardingStore.skip()
        UserDefaults.standard.set(true, forKey: UserScope.key("isProUser"))
        UserDefaults.standard.set(true, forKey: UserScope.key("hasPurchasedPro"))
        SubscriptionManager.shared.reload()

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: Date())) ?? startOfToday
        func day(_ back: Int) -> Date {
            let d = calendar.date(byAdding: .day, value: -back, to: startOfToday) ?? startOfToday
            return calendar.date(byAdding: .hour, value: 10, to: max(d, startOfYear)) ?? d
        }

        var newProperties: [RentalProperty] = []
        var newEntries: [TimeEntry] = []
        let store = RentalPlanStore.shared
        store.resetAll()
        let kinds: [ActivityCategory] = [.repairs, .management, .leasing, .bookkeeping]
        for (index, seed) in seeds.enumerated() {
            var property = RentalProperty(name: seed.name, address: "\(index + 1) \(seed.name)", propertyType: seed.type)
            property.createdAt = Date(timeIntervalSince1970: 1_760_000_000 + Double(index) * 60)
            newProperties.append(property)
            if let who = seed.who { store.setWhoDoesMost(who, for: property.id) }
            if let override = seed.override { store.setOverride(override, for: property.id) }
            var remaining = seed.hours
            var back = 2 + index
            while remaining > 0.0001 {
                let h = min(8, remaining)
                newEntries.append(TimeEntry(propertyId: property.id, participant: .selfParticipant,
                                            category: kinds[back % kinds.count], hours: h, date: day(back), notes: ""))
                remaining -= h
                back += 1
            }
        }
        properties = newProperties
        let year = calendar.component(.year, from: Date())
        timeEntries.removeAll { calendar.component(.year, from: $0.date) == year }
        timeEntries = newEntries
        saveData()
        GoalManager.shared.saveGoals()
        _ = store.reconcile(rentalPlanContext, announce: false)
    }
}
#endif
