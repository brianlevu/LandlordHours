import Foundation

// MARK: - How long: one-tap chips for a care entry (2.3, package B)
//
// A care row opens Log time with How long EMPTY. The app never prefills a guessed number: identical
// repeated hours read as templated. Instead it offers chips, and one tap sets the hours:
//   "Last time 1h 20m"   the person's own latest log of this task (this rental first)
//   "Typical 1–2h"       the range of their own logs of it (2 or more, not all the same);
//                        a tap sets the middle of their own logs (the median)
//   "30m" "1h" "2h"      fixed short options, never derived from anything
// No history: only the fixed options. Nothing here is ever applied without a tap.

struct CareHourChip: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable { case lastTime, typical, fixed }
    let kind: Kind
    /// What one tap sets.
    let hours: Double
    let title: String

    var id: String { kind == .fixed ? "fixed-\(Int((hours * 60).rounded()))" : kind.rawValue }
}

enum CareHourChips {
    /// The fixed short options.
    static let fixed: [Double] = [0.5, 1, 2]
    static let maxChips = 4

    /// The chips for a task from the person's own history (newest first, as
    /// `CareDoneLog.history` returns it).
    static func chips(history: [CareLog]) -> [CareHourChip] {
        var out: [CareHourChip] = []
        let hours = history.map(\.hours).filter { $0 > 0 }
        if let last = history.first(where: { $0.hours > 0 }) {
            out.append(CareHourChip(kind: .lastTime, hours: minutes(last.hours), title: CareText.lastTime(LHFormat.hours(last.hours))))
        }
        if hours.count >= 2, let lo = hours.min(), let hi = hours.max(), minutes(lo) != minutes(hi) {
            out.append(CareHourChip(kind: .typical, hours: minutes(median(hours)), title: CareText.typical(range(lo, hi))))
        }
        let taken = Set(out.map { minutes($0.hours) })
        for value in fixed where !taken.contains(value) && out.count < maxChips {
            out.append(CareHourChip(kind: .fixed, hours: value, title: LHFormat.hours(value)))
        }
        return out
    }

    /// The median of the person's own logs.
    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// Rounds to the whole minute (entries keep minutes; nothing is snapped to a template).
    static func minutes(_ hours: Double) -> Double { (hours * 60).rounded() / 60 }

    /// "1–2h" when both ends are whole hours; else "45m–1h 30m".
    static func range(_ lo: Double, _ hi: Double) -> String {
        let a = minutes(lo), b = minutes(hi)
        if a >= 1, b >= 1, a.truncatingRemainder(dividingBy: 1) == 0, b.truncatingRemainder(dividingBy: 1) == 0 {
            return String(localized: "care.chip.rangeHours", defaultValue: "\(Int(a))–\(Int(b))h", table: "CarePlan")
        }
        return String(localized: "care.chip.range", defaultValue: "\(LHFormat.hours(a))–\(LHFormat.hours(b))", table: "CarePlan")
    }
}
