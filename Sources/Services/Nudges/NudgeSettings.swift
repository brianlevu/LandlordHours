import Foundation

// MARK: - Pace and care nudges: what the person chose (2.3 package D)
//
// Every kind is OFF until the person turns it on. The settings and the send ledger are stored per
// profile (`UserScope.key`), so a profile switch never reads another person's choices.

enum NudgeKind: String, CaseIterable, Codable, Sendable {
    case weeklyPace, behindPace, yearEnd, carePlan

    /// Pace nudges are about hours; the care nudge is about upkeep. They are never one notification.
    var isCare: Bool { self == .carePlan }
}

struct NudgeSettings: Equatable, Codable, Sendable {
    var weeklyPace = false
    var behindPace = false
    var yearEnd = false
    var carePlan = false
    /// Quiet hours: nothing is delivered from `quietStartHour` until `quietEndHour` (24-hour clock).
    /// Start equal to end means no quiet hours.
    var quietStartHour = 20
    var quietEndHour = 8

    static let `default` = NudgeSettings()

    var anyKindOn: Bool { NudgeKind.allCases.contains(where: isOn) }

    func isOn(_ kind: NudgeKind) -> Bool {
        switch kind {
        case .weeklyPace: return weeklyPace
        case .behindPace: return behindPace
        case .yearEnd: return yearEnd
        case .carePlan: return carePlan
        }
    }

    mutating func set(_ kind: NudgeKind, _ on: Bool) {
        switch kind {
        case .weeklyPace: weeklyPace = on
        case .behindPace: behindPace = on
        case .yearEnd: yearEnd = on
        case .carePlan: carePlan = on
        }
    }

    var enabledKinds: [NudgeKind] { NudgeKind.allCases.filter(isOn) }

    /// True when `date` falls inside the quiet window.
    func isQuiet(_ date: Date, calendar: Calendar) -> Bool {
        guard quietStartHour != quietEndHour else { return false }
        let hour = calendar.component(.hour, from: date)
        if quietStartHour < quietEndHour { return hour >= quietStartHour && hour < quietEndHour }
        return hour >= quietStartHour || hour < quietEndHour
    }
}

/// One nudge handed to the system: used for the daily and monthly caps and the care "one at a time".
struct NudgeLedgerEntry: Equatable, Codable, Sendable {
    var kind: NudgeKind
    /// The care item id, or a day key for the other kinds.
    var itemID: String
    var fireDate: Date
}

final class NudgeSettingsStore {
    static let settingsKey = "nudge.settings.v1"
    static let ledgerKey = "nudge.ledger.v1"

    private let defaults: UserDefaults
    private let scoped: (String) -> String

    init(defaults: UserDefaults = .standard, scoped: @escaping (String) -> String = { UserScope.key($0) }) {
        self.defaults = defaults
        self.scoped = scoped
    }

    func load() -> NudgeSettings {
        guard let data = defaults.data(forKey: scoped(Self.settingsKey)),
              let value = try? JSONDecoder().decode(NudgeSettings.self, from: data) else { return .default }
        return value
    }

    func save(_ settings: NudgeSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: scoped(Self.settingsKey))
    }

    func loadLedger() -> [NudgeLedgerEntry] {
        guard let data = defaults.data(forKey: scoped(Self.ledgerKey)),
              let value = try? JSONDecoder().decode([NudgeLedgerEntry].self, from: data) else { return [] }
        return value
    }

    func saveLedger(_ ledger: [NudgeLedgerEntry]) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: scoped(Self.ledgerKey))
    }
}
