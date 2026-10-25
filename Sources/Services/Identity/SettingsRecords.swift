import Foundation

// MARK: - The settings pair, independent of the managers
//
// One pair per iCloud account: `GoalSettings-household` and `TaxProfile-household`, tagged with
// the unified id. 2.0.x devices read `GoalSettings-<their id>`, so when the unified id is a legacy
// id the pair is mirrored under that name too (§3.2). The pull accepts only these names.

struct GoalSettingsValues: Equatable, Codable {
    var globalGoalType: String
    var materialParticipationTarget: Int?
    var propertyGoalsJSON: String

    static let defaults = GoalSettingsValues(globalGoalType: HourGoalType.reps.rawValue, materialParticipationTarget: nil, propertyGoalsJSON: "[]")

    init(globalGoalType: String, materialParticipationTarget: Int?, propertyGoalsJSON: String) {
        self.globalGoalType = globalGoalType
        self.materialParticipationTarget = materialParticipationTarget
        self.propertyGoalsJSON = propertyGoalsJSON
    }

    init(record: ZoneRecord) {
        if case .string(let s)? = record.fields["globalGoalType"] { globalGoalType = s } else { globalGoalType = HourGoalType.reps.rawValue }
        switch record.fields["materialParticipationTarget"] {
        case .int(let i)?: materialParticipationTarget = Int(i)
        case .double(let d)?: materialParticipationTarget = Int(d)
        default: materialParticipationTarget = nil
        }
        if case .string(let s)? = record.fields["propertyGoalsJSON"] { propertyGoalsJSON = s } else { propertyGoalsJSON = "[]" }
    }

    /// Read from a key prefix (`v2.` or `u.<id>.`).
    init(defaults: UserDefaults, prefix: String) {
        globalGoalType = defaults.string(forKey: prefix + "globalGoalType") ?? HourGoalType.reps.rawValue
        let mp = defaults.integer(forKey: prefix + "materialParticipationTarget")
        materialParticipationTarget = mp == 0 ? nil : mp
        if let data = defaults.data(forKey: prefix + "propertyGoals"), let s = String(data: data, encoding: .utf8) {
            propertyGoalsJSON = s
        } else {
            propertyGoalsJSON = "[]"
        }
    }

    func record(name: String, owner: String?) -> ZoneRecord {
        var f: [String: ZoneFieldValue] = [
            "globalGoalType": .string(globalGoalType),
            "propertyGoalsJSON": .string(propertyGoalsJSON),
            "materialParticipationTarget": .int(Int64(materialParticipationTarget ?? 0))
        ]
        if let owner { f["appUserId"] = .string(owner) }
        return ZoneRecord(recordName: name, recordType: "GoalSettings", fields: f)
    }

    var propertyGoals: [PropertyGoal] {
        (try? JSONDecoder().decode([PropertyGoal].self, from: Data(propertyGoalsJSON.utf8))) ?? []
    }
}

struct TaxProfileValues: Equatable, Codable {
    var filingStatus: String
    var spouseTracking: Bool
    var taxYear: Int
    var groupingElection: Bool
    var nonREWorkHours: Double
    /// Your name (§2.4): the one schema change K makes (`TaxProfile.displayName`, String).
    var displayName: String?

    init(filingStatus: String, spouseTracking: Bool, taxYear: Int, groupingElection: Bool, nonREWorkHours: Double, displayName: String?) {
        self.filingStatus = filingStatus
        self.spouseTracking = spouseTracking
        self.taxYear = taxYear
        self.groupingElection = groupingElection
        self.nonREWorkHours = nonREWorkHours
        self.displayName = displayName
    }

    init(record: ZoneRecord) {
        if case .string(let s)? = record.fields["filingStatus"] { filingStatus = s } else { filingStatus = FilingStatus.marriedJoint.rawValue }
        if case .int(let i)? = record.fields["spouseTracking"] { spouseTracking = i != 0 } else { spouseTracking = true }
        if case .int(let i)? = record.fields["taxYear"] { taxYear = Int(i) } else { taxYear = Calendar.current.component(.year, from: Date()) }
        if case .int(let i)? = record.fields["groupingElection"] { groupingElection = i != 0 } else { groupingElection = false }
        switch record.fields["nonREWorkHours"] {
        case .double(let d)?: nonREWorkHours = d
        case .int(let i)?: nonREWorkHours = Double(i)
        default: nonREWorkHours = 0
        }
        if case .string(let s)? = record.fields["displayName"], !s.isEmpty { displayName = s } else { displayName = nil }
    }

    init(defaults: UserDefaults, prefix: String) {
        let p = prefix + "LandlordHours.taxProfile."
        filingStatus = defaults.string(forKey: p + "filingStatus") ?? FilingStatus.marriedJoint.rawValue
        spouseTracking = defaults.object(forKey: p + "spouseTracking") == nil ? true : defaults.bool(forKey: p + "spouseTracking")
        let year = defaults.integer(forKey: p + "taxYear")
        taxYear = year == 0 ? Calendar.current.component(.year, from: Date()) : year
        groupingElection = defaults.bool(forKey: p + "groupingElection")
        nonREWorkHours = defaults.double(forKey: p + "nonREWorkHours")
        displayName = defaults.string(forKey: IdentityKeys.displayName)
    }

    func record(name: String, owner: String?) -> ZoneRecord {
        var f: [String: ZoneFieldValue] = [
            "filingStatus": .string(filingStatus),
            "spouseTracking": .int(spouseTracking ? 1 : 0),
            "taxYear": .int(Int64(taxYear)),
            "groupingElection": .int(groupingElection ? 1 : 0),
            "nonREWorkHours": .double(nonREWorkHours)
        ]
        // Never written as nil: a 2.0.x push (which never sets it) leaves the server value alone.
        if let displayName, !displayName.isEmpty { f[TaxProfileField.displayName] = .string(displayName) }
        if let owner { f["appUserId"] = .string(owner) }
        return ZoneRecord(recordName: name, recordType: "TaxProfile", fields: f)
    }
}

/// 2.2 fields on the TaxProfile record type. Add to the DEVELOPMENT schema, then deploy to
/// Production before the first TestFlight build that writes it (`scripts/qa/check_cloudkit_schema.py`).
enum TaxProfileField {
    static let displayName = "displayName"
}
