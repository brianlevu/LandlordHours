import Foundation

#if DEBUG
// MARK: - DEBUG seeding for Properties captures and UI tests (compiled out of Release)
//
//   -LHPropertiesSeed four|twelve|limit|empty
//        after -LHMockScenario: replace the rentals and this year's entries with the sandbox set
//        (Pine Cabin 212h, Oak Street Duplex 520h, the long-named lofts 128h, Maple Court 0h; or
//        twelve rentals; or Pine Cabin alone as a FREE user at the limit; or none).
//        four/twelve are Pro; limit/empty are free. Goal REPS, spouse hours off.
//        brian: Delaney Ct (long), Santa Ray Ave (short), Yeandle Ave (long), 0h, Pro.
//   -LHPropertiesGoal mp100    the material participation goal, no grouping election
//                              (rows read "80h of 100h" / "212h · past 100h")
extension AppViewModel {
    func applyPropertiesSeedIfNeeded(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let i = arguments.firstIndex(of: "-LHPropertiesSeed"), arguments.indices.contains(i + 1) else { return }
        let set = arguments[i + 1]
        let wasSuppressed = suppressCelebrations
        suppressCelebrations = true
        defer { suppressCelebrations = wasSuppressed }

        let goal = arguments.firstIndex(of: "-LHPropertiesGoal").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        GoalManager.shared.propertyGoals = []
        // The app's goal setting offers REPS (750h) or material participation (100h).
        GoalManager.shared.globalGoalType = goal.flatMap(HouseGoal.init(argument:)) == .mp100 ? .str : .reps
        TaxProfileManager.shared.spouseTracking = false
        TaxProfileManager.shared.groupingElection = false

        struct Seed { let name: String; let address: String; let type: PropertyType; let hours: Double; var aliases: [String] = []; var home = false }
        let pine = Seed(name: "Pine Cabin", address: "88 Ridge Rd, Big Bear", type: .str, hours: 212, aliases: ["Cabin", "Big Bear"])
        let oak = Seed(name: "Oak Street Duplex", address: "214 Oak St, Pasadena", type: .ltr, hours: 520, aliases: ["Oak St", "The duplex"], home: true)
        let lofts = Seed(name: "The Arroyo Seco Schoolhouse Lofts, Unit 4B", address: "1 Arroyo Blvd, Pasadena", type: .ltr, hours: 128)
        let maple = Seed(name: "Maple Court", address: "12 Maple Ct, Glendale", type: .ltr, hours: 0)
        let seeds: [Seed]
        switch set {
        case "twelve":
            seeds = [pine, oak, lofts, maple,
                     Seed(name: "Birch Lane House", address: "5 Birch Ln", type: .ltr, hours: 148),
                     Seed(name: "Harbor View 2", address: "40 Harbor Dr", type: .str, hours: 336),
                     Seed(name: "Cedar Triplex", address: "77 Cedar Ave", type: .ltr, hours: 91),
                     Seed(name: "Lakeside A-Frame", address: "3 Shore Rd", type: .str, hours: 455),
                     Seed(name: "Elm St Fourplex", address: "908 Elm St", type: .ltr, hours: 27),
                     Seed(name: "Sunset Bungalow", address: "19 Sunset Pl", type: .ltr, hours: 503),
                     Seed(name: "Granite Flats", address: "2 Quarry Rd", type: .ltr, hours: 12),
                     Seed(name: "Willow Cottage", address: "61 Willow Way", type: .str, hours: 240)]
        case "brian":
            // 2.0.1 home-screen captures: three rentals, no hours yet, added in this order.
            seeds = [Seed(name: "Delaney Ct", address: "1 Delaney Ct", type: .ltr, hours: 0),
                     Seed(name: "Santa Ray Ave", address: "2 Santa Ray Ave", type: .str, hours: 0),
                     Seed(name: "Yeandle Ave", address: "3 Yeandle Ave", type: .ltr, hours: 0)]
        case "limit": seeds = [pine]
        case "empty": seeds = []
        default: seeds = [pine, oak, lofts, maple]
        }

        // Captures show the screen itself, not the first-run guided overlay.
        GuidedOnboardingStore.skip()
        let pro = set == "four" || set == "twelve" || set == "brian"
        UserDefaults.standard.set(pro, forKey: UserScope.key("isProUser"))
        UserDefaults.standard.set(pro, forKey: UserScope.key("hasPurchasedPro"))
        SubscriptionManager.shared.reload()

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: Date())) ?? startOfToday
        func day(_ back: Int, hour: Int = 10) -> Date {
            let d = calendar.date(byAdding: .day, value: -back, to: startOfToday) ?? startOfToday
            return calendar.date(byAdding: .hour, value: hour, to: max(d, startOfYear)) ?? d
        }

        var newProperties: [RentalProperty] = []
        var newEntries: [TimeEntry] = []
        for (index, seed) in seeds.enumerated() {
            var property = RentalProperty(name: seed.name, address: seed.address, propertyType: seed.type,
                                          aliases: seed.aliases, isOwnerOccupied: seed.home)
            property.createdAt = Date(timeIntervalSince1970: 1_760_000_000 + Double(index) * 60)
            newProperties.append(property)
            guard seed.hours > 0 else { continue }

            // Recent three (as the sandbox shows them), then the rest by kind of work.
            let recent: [(ActivityCategory, Double, String, String?, Int)] = seed.name == oak.name
                ? [(.repairs, 1.5, "HVAC service", "calendar", 3), (.leasing, 1, "Lease signing", "calendar", 8), (.management, 0.5, "Tenant call", nil, 10)]
                : [(.repairs, 2, "Plumber", "calendar", 3), (.leasing, 1, "Showing", "calendar", 7), (.bookkeeping, 1.5, "Monthly books", nil, 11)]
            let mix: [(ActivityCategory, Double)] = seed.type == .ltr
                ? [(.repairs, 0.38), (.management, 0.27), (.leasing, 0.2), (.bookkeeping, 0.15)]
                : [(.repairs, 0.42), (.management, 0.27), (.leasing, 0.18), (.bookkeeping, 0.13)]
            var targets: [ActivityCategory: Double] = [:]
            var assigned = 0.0
            for (k, share) in mix.dropLast() { let h = (seed.hours * share).rounded(); targets[k] = h; assigned += h }
            targets[mix.last!.0] = seed.hours - assigned
            var back = 14
            if seed.hours >= 10 {
                for r in recent {
                    newEntries.append(TimeEntry(propertyId: property.id, participant: .selfParticipant, category: r.0, hours: r.1,
                                                date: day(r.4), notes: r.2, importSource: r.3))
                    targets[r.0, default: 0] -= r.1
                }
            }
            for (k, _) in mix {
                var remaining = max(0, targets[k] ?? 0)
                while remaining > 0.0001 {
                    let h = min(8, remaining)
                    newEntries.append(TimeEntry(propertyId: property.id, participant: .selfParticipant, category: k, hours: h,
                                                date: day(back), notes: ""))
                    remaining -= h
                    back += 1
                }
            }
        }
        properties = newProperties
        let year = calendar.component(.year, from: Date())
        timeEntries.removeAll { calendar.component(.year, from: $0.date) == year }
        timeEntries = newEntries
        saveData()
        GoalManager.shared.saveGoals()
    }
}
#endif
