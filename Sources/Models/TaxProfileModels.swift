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

    /// Settings picker words (the same four options as onboarding). The 750 line says what it
    /// counts: the rental hours logged in this app.
    var title: String {
        switch self {
        case .reps750: return String(localized: "750 hours · Rental hours you log here")
        case .mp500: return String(localized: "500 hours · Material participation")
        case .mp100: return String(localized: "100 hours · More than anyone else")
        case .record: return String(localized: "Just keep a record")
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

// MARK: - Goal setup answers (2.0 goal-first onboarding)

/// What the owner rents out. Short stays means guests stay 7 days or less, on average.
enum RentalMix: String, CaseIterable, Codable {
    case shortStays, longTerm, both

    /// Whether any rental is a short-term one (the 100 and 500 hour tests are counted per rental).
    var hasShortStays: Bool { self != .longTerm }
}

/// Who does real estate as a main job: the owner, the spouse, or nobody.
enum RealEstatePro: String, CaseIterable, Codable {
    case me, spouse, nobody
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
        ud.removeObject(forKey: rentalMixKey)
        ud.removeObject(forKey: proKey)
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

    // MARK: Goal setup answers (what the target was suggested from)

    private var rentalMixKey: String { UserScope.key("goalSetup.rentalMix") }
    private var proKey: String { UserScope.key("goalSetup.realEstatePro") }

    /// The owner's answer to "What do you rent out?". nil for profiles that never answered
    /// (1.x and upgraders). On this device only: nothing in iCloud changes.
    var rentalMix: RentalMix? {
        UserDefaults.standard.string(forKey: rentalMixKey).flatMap(RentalMix.init(rawValue:))
    }

    /// The owner's answer to "who does real estate as a main job". nil when never answered.
    var realEstatePro: RealEstatePro? {
        UserDefaults.standard.string(forKey: proKey).flatMap(RealEstatePro.init(rawValue:))
    }

    func setGoalSetup(rental: RentalMix?, pro: RealEstatePro?) {
        let ud = UserDefaults.standard
        if let rental { ud.set(rental.rawValue, forKey: rentalMixKey) } else { ud.removeObject(forKey: rentalMixKey) }
        if let pro { ud.set(pro.rawValue, forKey: proKey) } else { ud.removeObject(forKey: proKey) }
        objectWillChange.send()
    }

    /// Whose own hours the 750 count follows: the spouse's when the spouse is the real estate
    /// professional (one spouse alone must reach it), otherwise the owner's.
    var repsParticipant: Participant { realEstatePro == .spouse ? .spouse : .selfParticipant }

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

    /// 2.1: the same answer, kept per rental. Keys are "<year>|<rental id>", or "<year>|all" for
    /// a grouped activity. The 2.0 per-year map above is never rewritten or deleted (a downgrade
    /// and the migration both still read it); `migrateParticipationAnswers` copies it in.
    @Published private(set) var participationAnswers: [String: Bool] = [:]
    private var participationAnswersKey: String { scopedKey("noOneParticipatedMore.v2") }
    private var participationMigrationKey: String { scopedKey("noOneParticipatedMore.v2.migration") }

    static func participationAnswerKey(year: Int, propertyId: UUID?) -> String {
        "\(year)|\(propertyId?.uuidString ?? "all")"
    }

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
        loadParticipationAnswers()
        // The grouped activity's answer needs no rentals; each rental's follows when they load.
        migrateParticipationAnswers(properties: [])
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
        participationAnswers = [:]
    }

    func resetForDataReset() {
        filingStatus = .marriedJoint
        spouseTracking = true
        taxYear = Calendar.current.component(.year, from: Date())
        groupingElection = false
        nonREWorkHours = 0
        noOneParticipatedMoreByYear = [:]
        participationAnswers = [:]

        let ud = UserDefaults.standard
        for field in ["filingStatus", "spouseTracking", "taxYear", "groupingElection", "nonREWorkHours", "noOneParticipatedMore",
                      "noOneParticipatedMore.v2", "noOneParticipatedMore.v2.migration"] {
            ud.removeObject(forKey: scopedKey(field))
        }
        onDidChange?()
    }

    // MARK: - 100-Hour Test Confirmation

    /// The grouped activity's answer for the year (the "all rentals" answer): nil = unanswered,
    /// true = no one else participated more, false = someone else did. Since 2.1 each rental has
    /// its own answer: use `noOneParticipatedMore(forYear:propertyId:)` anywhere a rental is named.
    func noOneParticipatedMore(forYear year: Int) -> Bool? {
        noOneParticipatedMore(forYear: year, propertyId: nil)
    }

    /// Records (or clears) the grouped activity's answer for a tax year.
    func setNoOneParticipatedMore(_ value: Bool?, forYear year: Int) {
        setNoOneParticipatedMore(value, forYear: year, propertyId: nil)
    }

    /// The answer for one rental (nil `propertyId`: the grouped activity) in a tax year.
    func noOneParticipatedMore(forYear year: Int, propertyId: UUID?) -> Bool? {
        participationAnswers[Self.participationAnswerKey(year: year, propertyId: propertyId)]
    }

    /// Records (or clears, when `value` is nil) one rental's answer and persists it.
    func setNoOneParticipatedMore(_ value: Bool?, forYear year: Int, propertyId: UUID?) {
        let key = Self.participationAnswerKey(year: year, propertyId: propertyId)
        if let value { participationAnswers[key] = value } else { participationAnswers.removeValue(forKey: key) }
        saveParticipationAnswers()
    }

    /// A closure the tax engine reads: this year's answer for a rental (nil id: the grouped one).
    func participationAnswerLookup(year: Int) -> (UUID?) -> Bool? {
        { [weak self] id in self?.noOneParticipatedMore(forYear: year, propertyId: id) }
    }

    /// Drops every answer for a deleted rental.
    func forgetParticipationAnswers(for propertyId: UUID) {
        let suffix = "|" + propertyId.uuidString
        let before = participationAnswers.count
        participationAnswers = participationAnswers.filter { !$0.key.hasSuffix(suffix) }
        if participationAnswers.count != before { saveParticipationAnswers() }
    }

    // MARK: 2.0 → 2.1 migration (one answer per year → one per rental)

    /// Copies the 2.0 per-year answers to the per-rental store. Every rental that existed when
    /// the migration first ran inherits each year's answer (it was given for all of them), and
    /// the grouped activity gets it too. A rental created later starts unanswered. The 2.0 map is
    /// left exactly as it was. Safe to call any number of times (a rental that arrives later from
    /// iCloud is picked up the first time it is seen, if it predates the migration).
    func migrateParticipationAnswers(properties: [RentalProperty], now: Date = Date()) {
        let legacy = noOneParticipatedMoreByYear
        var state = loadMigrationState() ?? MigrationState(stamp: now, done: [])
        var changed = false
        for (year, value) in legacy {
            let key = Self.participationAnswerKey(year: year, propertyId: nil)
            if participationAnswers[key] == nil && !state.groupedDone.contains(year) {
                participationAnswers[key] = value
                state.groupedDone.insert(year)
                changed = true
            }
        }
        for property in properties where property.createdAt <= state.stamp && !state.done.contains(property.id.uuidString) {
            for (year, value) in legacy {
                let key = Self.participationAnswerKey(year: year, propertyId: property.id)
                if participationAnswers[key] == nil { participationAnswers[key] = value; changed = true }
            }
            state.done.insert(property.id.uuidString)
            changed = true
        }
        if changed || loadMigrationState() == nil {
            if changed { saveParticipationAnswers() }
            saveMigrationState(state)
        }
    }

    private struct MigrationState: Codable {
        var stamp: Date
        var done: Set<String>
        var groupedDone: Set<Int> = []

        init(stamp: Date, done: Set<String>) { self.stamp = stamp; self.done = done }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            stamp = try c.decode(Date.self, forKey: .stamp)
            done = try c.decodeIfPresent(Set<String>.self, forKey: .done) ?? []
            groupedDone = try c.decodeIfPresent(Set<Int>.self, forKey: .groupedDone) ?? []
        }
    }

    private func loadMigrationState() -> MigrationState? {
        UserDefaults.standard.data(forKey: participationMigrationKey).flatMap { try? JSONDecoder().decode(MigrationState.self, from: $0) }
    }

    private func saveMigrationState(_ state: MigrationState) {
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: participationMigrationKey) }
    }

    private func loadParticipationAnswers() {
        guard let data = UserDefaults.standard.data(forKey: participationAnswersKey),
              let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            participationAnswers = [:]
            return
        }
        participationAnswers = decoded
    }

    private func saveParticipationAnswers() {
        // Local to this device (not in the iCloud TaxProfile record), so no sync push.
        if let data = try? JSONEncoder().encode(participationAnswers) { UserDefaults.standard.set(data, forKey: participationAnswersKey) }
    }

    /// 2.0 setter kept for tests and old call sites: writes the per-year map only.
    func setLegacyNoOneParticipatedMore(_ value: Bool?, forYear year: Int) {
        if let value { noOneParticipatedMoreByYear[year] = value } else { noOneParticipatedMoreByYear.removeValue(forKey: year) }
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
