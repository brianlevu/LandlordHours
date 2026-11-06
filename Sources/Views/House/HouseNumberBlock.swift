import SwiftUI

// MARK: - HouseNumberBlock: the number under the house (standard §H.1 H4, H10; §1.27 shared keys)
//
// One view for compact Today, the rental page and the house pane (package A2; C, F and J consume
// it). The Fraunces numeral, then:
//   · one rental: "of 100 hours · Maple St", then the pace sentence;
//   · "All rentals": "312 hours across 3 rentals · 3 of 3 behind" (or "· All on pace"), then
//     "Tap a house to see its pace." (or "Every rental is on pace."). Never a goal, never a stage.
// Strings are in `Shared.xcstrings`.

/// What "All rentals" says: the hours across the rentals and how many are behind their own pace.
/// There is no goal here, summed or otherwise (§H.1 H10).
struct AllRentalsSummary: Equatable, Sendable {
    let hours: Double
    let rentalCount: Int
    let behindCount: Int

    var allOnPace: Bool { behindCount == 0 }
    var wholeHours: Int { Int(max(0, hours.isFinite ? hours : 0).rounded(.down)) }

    init(hours: Double, rentalCount: Int, behindCount: Int) {
        self.hours = hours.isFinite ? max(0, hours) : 0
        self.rentalCount = max(0, rentalCount)
        self.behindCount = min(max(0, behindCount), self.rentalCount)
    }

    /// "312 hours across 3 rentals".
    var hoursAcrossLine: String {
        String(localized: "allRentals.hoursAcross", defaultValue: "\(wholeHours) hours across \(rentalCount) rentals", table: "Shared")
    }

    /// "3 of 3 behind", or "All on pace" when none is (the shelf label).
    var behindLabel: String {
        allOnPace
            ? String(localized: "allRentals.allOnPace", defaultValue: "All on pace", table: "Shared")
            : String(localized: "allRentals.behind", defaultValue: "\(behindCount) of \(rentalCount) behind", table: "Shared")
    }

    /// The number line: "312 hours across 3 rentals · 3 of 3 behind".
    var numberLine: String { "\(hoursAcrossLine) · \(behindLabel)" }

    /// The pace line under it.
    var paceLine: String {
        allOnPace
            ? String(localized: "allRentals.everyOnPace", defaultValue: "Every rental is on pace.", table: "Shared")
            : String(localized: "allRentals.tapHouse", defaultValue: "Tap a house to see its pace.", table: "Shared")
    }
}

struct HouseNumberBlock: View {
    enum Content: Equatable {
        case rental(hours: Double, goal: Double, name: String, pace: TodayPaceSentence)
        case allRentals(AllRentalsSummary)
    }

    let content: Content
    /// The numeral's size (84 default, 64 under 700pt of height, 54 at AX; H3/H7).
    let numeralSize: CGFloat
    /// While the first iCloud pull is pending the number shows a dash.
    var isPending = false
    /// The pace line opens a question ("did anyone else do more?"); one rental only.
    var onPaceTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var whole: Int {
        switch content {
        case let .rental(hours, _, _, _): return Int(max(0, hours.isFinite ? hours : 0).rounded(.down))
        case let .allRentals(summary): return summary.wholeHours
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(isPending ? "—" : "\(whole)")
                .font(LHFont.heroNumeral(size: numeralSize))
                .tracking(-2)
                .foregroundStyle(colors.textPrimary)
                .contentTransition(.numericText(value: Double(whole)))
                .animation(reduceMotion ? nil : AppAnimation.count, value: whole)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityIdentifier("house.number")
            Text(subtitle)
                .font(.body)
                .foregroundStyle(colors.textSecondary)
                .accessibilityIdentifier("house.numberLine")
            paceLine
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("house.numberBlock")
    }

    private var subtitle: String {
        switch content {
        case let .rental(_, goal, name, _):
            return String(localized: "hero.ofGoal", defaultValue: "of \(Int(goal.rounded())) hours · \(name)", table: "Shared")
        case let .allRentals(summary):
            return summary.numberLine
        }
    }

    @ViewBuilder private var paceLine: some View {
        switch content {
        case let .rental(_, _, _, pace):
            let line = Self.paceText(pace, colors: colors)
                .font(.subheadline)
                .contentTransition(.opacity)
                .accessibilityIdentifier("house.pace")
            if let onPaceTap {
                Button(action: onPaceTap) { line }
                    .buttonStyle(LHButton.press)
            } else {
                line
            }
        case let .allRentals(summary):
            Text(summary.paceLine)
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .accessibilityIdentifier("house.pace")
        }
    }

    /// The lead in its tone ink (semibold), the rest `textSecondary`.
    static func paceText(_ pace: TodayPaceSentence, colors: AdaptiveColors) -> Text {
        let rest = Text(pace.rest).foregroundStyle(colors.textSecondary)
        guard let lead = pace.lead else { return rest }
        let ink: Color
        switch pace.tone {
        case .behind: ink = colors.behind
        case .positive: ink = colors.positiveOnPage
        case .neutral: ink = colors.textPrimary
        }
        return Text(lead).foregroundStyle(ink).fontWeight(.semibold) + Text(verbatim: " ") + rest
    }
}
