import Foundation

/// "Read my notes with Apple's model" (Settings › Auto-capture). One switch for the Log time note:
/// off means no model of any kind reads it (the on-device model and Private Cloud Compute both
/// stay closed). The rules still run, so the sheet keeps filling from the user's own words and says
/// "Matched from your words". Private Cloud Compute keeps its own setting nested under this one.
struct NoteReadingSettings {
    static let enabledKey = "LandlordHours.noteReading.modelEnabled"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
    }
}
