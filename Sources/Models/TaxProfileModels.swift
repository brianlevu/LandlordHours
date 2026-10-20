import SwiftUI

// MARK: - Hour Goal Type

enum HourGoalType: String, CaseIterable, Codable {
    case reps = "REPS"
    case str = "STR (Short-Term Rental)"
    case both = "Both"

    var description: String {
        switch self {
        case .reps:
            return "750 hours plus the 50% rule (REPS)"
        case .str:
            return "100 hours - STR Material Participation"
        case .both:
            return "Track both REPS and STR goals"
        }
    }

    var hoursRequired: Double {
        switch self {
        case .reps:
            return 750
        case .str:
            return 100
        case .both:
            return 750 // Use higher as primary
        }
    }
}

// MARK: - Goal choice (2.0: the four goals onboarding and Settings offer)

/// What the owner is building toward. 1.x stored three `HourGoalType`s; 2.0 adds material
/// participation at 500 hours (MP test 1) beside 100 hours (test 3). The 500 target is stored
/// next to `.str`, so `HourGoalType` (synced and read by 1.x) never changes and every existing
/// stored goal reads back exactly as before: `.reps` → 750, `.str` → 100, `.both` → record.
enum GoalChoice: String, CaseIterable, Identifiable {
    case reps750, mp500, mp100, record

    var id: String { rawValue }

    init(hourGoalType: HourGoalType, materialParticipationTarget: Int) {
        switch hourGoalType {
        case .reps: self = .reps750
        case .both: self = .record
        case .str: self = materialParticipationTarget == 500 ? .mp500 : .mp100
        }
    }

    var hourGoalType: HourGoalType {
        switch self {
        case .reps750: return .reps
        case .mp500, .mp100: return .str
        case .record: return .both
        }
    }

    /// 500 only for MP 500; 0 (none) otherwise.
    var materialParticipationTarget: Int { self == .mp500 ? 500 : 0 }

    /// The house goal. "Keep a record" keeps the REPS scale, as 1.x's "Both" did.
    var houseGoal: HouseGoal {
        switch self {
        case .reps750, .record: return .reps750
        case .mp500: return .mp500
        case .mp100: return .mp100
        }
    }

    var targetHours: Double { houseGoal.targetHours }

    /// Settings picker words (the same four options as onboarding).
    var title: String {
        switch self {
        case .reps750: return "750 hours · Real estate professional"
        case .mp500: return "500 hours · Material participation"
        case .mp100: return "100 hours · Material participation"
        case .record: return "Just keep a record"
        }
    }

    /// Widget labels: (long, short).
    var widgetLabels: (String, String) {
        switch self {
        case .reps750: return ("750h REPS", "750h")
        case .mp500: return ("500h MP", "500h")
        case .mp100: return ("100h STR", "100h")
        case .record: return ("750h REPS + STR", "750h")
        }
    }
}

// MARK: - Property Goal

struct PropertyGoal: Identifiable, Codable {
    var id: UUID
    var propertyId: UUID
    var goalType: HourGoalType
    var modifiedAt: Date

    init(id: UUID = UUID(), propertyId: UUID, goalType: HourGoalType = .both) {
        self.id = id
        self.propertyId = propertyId
        self.goalType = goalType
        self.modifiedAt = Date()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        propertyId = try c.decode(UUID.self, forKey: .propertyId)
        goalType = try c.decode(HourGoalType.self, forKey: .goalType)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
    }
}

// MARK: - Goal Manager

class GoalManager: ObservableObject {
    static let shared = GoalManager()

    /// Called when goals change, so sync can be triggered
    var onDidChange: (() -> Void)?

    @Published var propertyGoals: [PropertyGoal] = []
    @Published var globalGoalType: HourGoalType = .reps

    private var goalsKey: String { UserScope.key("propertyGoals") }
    private var globalGoalKey: String { UserScope.key("globalGoalType") }

    private init() {
        loadGoals()
    }

    func loadGoals() {
        if let data = UserDefaults.standard.data(forKey: goalsKey),
           let goals = try? JSONDecoder().decode([PropertyGoal].self, from: data) {
            propertyGoals = goals
        } else {
            propertyGoals = []
        }

        if let raw = UserDefaults.standard.string(forKey: globalGoalKey),
           let type = HourGoalType(rawValue: raw) {
            globalGoalType = type
        } else {
            globalGoalType = .reps
        }
    }

    func saveGoals() {
        if let data = try? JSONEncoder().encode(propertyGoals) {
            UserDefaults.standard.set(data, forKey: goalsKey)
        }
        UserDefaults.standard.set(globalGoalType.rawValue, forKey: globalGoalKey)
        onDidChange?()
    }

    func resetForSignOut() {
        propertyGoals = []
        globalGoalType = .reps
    }

    func resetForDataReset() {
        propertyGoals = []
        globalGoalType = .reps
        let ud = UserDefaults.standard
        ud.removeObject(forKey: goalsKey)
        ud.removeObject(forKey: globalGoalKey)
        onDidChange?()
    }

    func setGoal(for propertyId: UUID, type: HourGoalType) {
        if let index = propertyGoals.firstIndex(where: { $0.propertyId == propertyId }) {
            propertyGoals[index].goalType = type
        } else {
            propertyGoals.append(PropertyGoal(propertyId: propertyId, goalType: type))
        }
        saveGoals()
    }

    func getGoal(for propertyId: UUID) -> HourGoalType {
        propertyGoals.first(where: { $0.propertyId == propertyId })?.goalType ?? globalGoalType
    }

    func setGlobalGoal(_ type: HourGoalType) {
        globalGoalType = type
        // A plain goal type change drops the 500-hour target: `.str` then means 100 hours, as in 1.x.
        UserDefaults.standard.removeObject(forKey: mpTargetKey)
        saveGoals()
    }

    // MARK: 2.0 goal choice (adds material participation at 500 hours)

    /// Per profile, next to `globalGoalType`; synced in the GoalSettings record.
    private var mpTargetKey: String { UserScope.key("materialParticipationTarget") }

    var materialParticipationTarget: Int { UserDefaults.standard.integer(forKey: mpTargetKey) }

    var goalChoice: GoalChoice {
        GoalChoice(hourGoalType: globalGoalType, materialParticipationTarget: materialParticipationTarget)
    }

    /// The goal the house and every 2.0 surface measure against.
    var houseGoal: HouseGoal { goalChoice.houseGoal }

    func setGoalChoice(_ choice: GoalChoice) {
        globalGoalType = choice.hourGoalType
        applyMaterialParticipationTarget(choice.materialParticipationTarget)
        saveGoals()
    }

    /// Saves a house goal (REPS, MP 500 or MP 100).
    func setHouseGoal(_ goal: HouseGoal) {
        switch goal {
        case .reps750: setGoalChoice(.reps750)
        case .mp500: setGoalChoice(.mp500)
        case .mp100: setGoalChoice(.mp100)
        }
    }

    /// iCloud: the target arrives with the goal type; 0 or a missing field means none.
    func applyMaterialParticipationTarget(_ target: Int) {
        if target == 500 {
            UserDefaults.standard.set(500, forKey: mpTargetKey)
        } else {
            UserDefaults.standard.removeObject(forKey: mpTargetKey)
        }
        objectWillChange.send()
    }
}

// MARK: - Filing Status

enum FilingStatus: String, CaseIterable, Codable {
    case single = "Single"
    case marriedJoint = "Married, Joint"
    case marriedSeparate = "Married, Separate"
    case headOfHousehold = "Head of Household"
    case qualifyingWidow = "Qualifying Widow(er)"
}

// MARK: - Tax Profile Manager

final class TaxProfileManager: ObservableObject {
    static let shared = TaxProfileManager()

    /// Called when any field changes, so sync can be triggered
    var onDidChange: (() -> Void)?

    private func scopedKey(_ field: String) -> String {
        UserScope.key("LandlordHours.taxProfile." + field)
    }

    /// True while `reload()` / `resetForSignOut()` apply stored or default values. Their
    /// didSets must neither write back (resetForSignOut runs after the profile ID is cleared,
    /// so writes would land in unscoped keys) nor fire `onDidChange` (which schedules a
    /// CloudKit push of defaults over the iCloud TaxProfile before the first pull).
    private(set) var isApplyingStoredValues = false

    private func save(_ key: String, _ value: Any) {
        guard !isApplyingStoredValues else { return }
        UserDefaults.standard.set(value, forKey: key)
        onDidChange?()
    }

    private func applyingStoredValues(_ body: () -> Void) {
        isApplyingStoredValues = true
        defer { isApplyingStoredValues = false }
        body()
    }

    @Published var filingStatus: FilingStatus {
        didSet { save(scopedKey("filingStatus"), filingStatus.rawValue) }
    }
    @Published var spouseTracking: Bool {
        didSet { save(scopedKey("spouseTracking"), spouseTracking) }
    }
    @Published var taxYear: Int {
        didSet { save(scopedKey("taxYear"), taxYear) }
    }
    @Published var groupingElection: Bool {
        didSet { save(scopedKey("groupingElection"), groupingElection) }
    }
    @Published var nonREWorkHours: Double {
        didSet { save(scopedKey("nonREWorkHours"), nonREWorkHours) }
    }

    /// IRS Test 3 (100-hour) confirmation, keyed by tax year.
    /// A missing entry means unanswered (nil). The whole map is user-scoped like the
    /// other tax-profile fields, so each user + tax year carries its own answer.
    /// Mutated only through `setNoOneParticipatedMore(_:forYear:)` so loads don't re-persist.
    @Published private(set) var noOneParticipatedMoreByYear: [Int: Bool] = [:]

    private var participationKey: String { scopedKey("noOneParticipatedMore") }

    private init() {
        // Set defaults first (didSet won't fire during init)
        filingStatus = .marriedJoint
        spouseTracking = true
        taxYear = Calendar.current.component(.year, from: Date())
        groupingElection = false
        nonREWorkHours = 0
        reload()
    }

    func reload() {
        applyingStoredValues {
            let ud = UserDefaults.standard
            if let raw = ud.string(forKey: scopedKey("filingStatus")),
               let status = FilingStatus(rawValue: raw) {
                filingStatus = status
            } else {
                filingStatus = .marriedJoint
            }
            if ud.object(forKey: scopedKey("spouseTracking")) != nil {
                spouseTracking = ud.bool(forKey: scopedKey("spouseTracking"))
            } else {
                spouseTracking = true
            }
            let savedYear = ud.integer(forKey: scopedKey("taxYear"))
            taxYear = savedYear > 0 ? savedYear : Calendar.current.component(.year, from: Date())
            groupingElection = ud.bool(forKey: scopedKey("groupingElection"))
            nonREWorkHours = ud.double(forKey: scopedKey("nonREWorkHours"))
        }
        loadParticipationConfirmations()
    }

    func resetForSignOut() {
        applyingStoredValues {
            filingStatus = .marriedJoint
            spouseTracking = true
            taxYear = Calendar.current.component(.year, from: Date())
            groupingElection = false
            nonREWorkHours = 0
        }
        noOneParticipatedMoreByYear = [:]
    }

    func resetForDataReset() {
        filingStatus = .marriedJoint
        spouseTracking = true
        taxYear = Calendar.current.component(.year, from: Date())
        groupingElection = false
        nonREWorkHours = 0
        noOneParticipatedMoreByYear = [:]

        let ud = UserDefaults.standard
        for field in ["filingStatus", "spouseTracking", "taxYear", "groupingElection", "nonREWorkHours", "noOneParticipatedMore"] {
            ud.removeObject(forKey: scopedKey(field))
        }
        onDidChange?()
    }

    // MARK: - 100-Hour Test Confirmation

    /// Answer for the given tax year: nil = unanswered, true = no one else participated
    /// more, false = someone else did.
    func noOneParticipatedMore(forYear year: Int) -> Bool? {
        noOneParticipatedMoreByYear[year]
    }

    /// Records (or clears, when `value` is nil) the confirmation for a tax year and persists it.
    func setNoOneParticipatedMore(_ value: Bool?, forYear year: Int) {
        if let value {
            noOneParticipatedMoreByYear[year] = value
        } else {
            noOneParticipatedMoreByYear.removeValue(forKey: year)
        }
        saveParticipationConfirmations()
    }

    private func loadParticipationConfirmations() {
        guard let data = UserDefaults.standard.data(forKey: participationKey),
              let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            noOneParticipatedMoreByYear = [:]
            return
        }
        noOneParticipatedMoreByYear = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
    }

    private func saveParticipationConfirmations() {
        // Persist as [String: Bool] since JSON object keys must be strings.
        let encodable = Dictionary(uniqueKeysWithValues: noOneParticipatedMoreByYear.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(encodable) {
            save(participationKey, data)
        }
    }
}
