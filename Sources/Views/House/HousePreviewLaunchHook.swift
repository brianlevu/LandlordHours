import SwiftUI

#if DEBUG
// MARK: - DEBUG launch hook for house captures (v2: the crafted house)
//
//   -LHHousePreview <hours> <goal> <scheme>
//       hours: countable hours (e.g. 212, 499.5)
//       goal:  reps | mp500 | mp100
//       scheme: light | dark
//   Optional:
//   -LHHouseScene hero|confirm|milestone|backfill   (default hero)
//   -LHHouseConfirmHours <h>    confirm scene: hours added (default 2); the hero plays the stage change
//   -LHHouseConfirmDelay <s>    confirm scene: seconds before the hours land (default 1.5)
//   -LHHouseUnlit               hero/confirm: windows dark before the hours land (windowsOn plays)
//   -LHHouseMilestone 100|500|750|goal   milestone scene: which celebration (default: the
//                               highest one this goal has earned at these hours)
//   -LHHouseStartDelay <s>      milestone/backfill scene: hold the first frame this long
//   -LHHouseSettled             milestone/backfill scene: start at the end state
//   -LHHouseSuggestions <n>     backfill scene: suggestion count (default 14)
//
// The app's normal root is replaced, so nothing else (onboarding, sync prompts) runs on screen.
// Compiled out of Release.

struct HousePreviewLaunch: Equatable {
    enum Scene: String { case hero, confirm, milestone, backfill }

    var hours: Double
    var goal: HouseGoal
    var scheme: ColorScheme
    var scene: Scene = .hero
    var confirmHours: Double = 2
    var confirmDelay: Double = 1.5
    var unlit = false
    var milestone: String? = nil
    var startDelay: Double = 0
    var settled = false
    var suggestions = 14

    static let current: HousePreviewLaunch? = parse(ProcessInfo.processInfo.arguments)

    static func parse(_ args: [String]) -> HousePreviewLaunch? {
        guard let i = args.firstIndex(of: "-LHHousePreview"), args.indices.contains(i + 3),
              let hours = Double(args[i + 1]),
              let goal = HouseGoal(argument: args[i + 2]) else { return nil }
        let scheme: ColorScheme = args[i + 3].lowercased() == "dark" ? .dark : .light
        var config = HousePreviewLaunch(hours: hours, goal: goal, scheme: scheme)
        func value(_ flag: String) -> String? {
            guard let j = args.firstIndex(of: flag), args.indices.contains(j + 1) else { return nil }
            return args[j + 1]
        }
        if let raw = value("-LHHouseScene"), let scene = Scene(rawValue: raw.lowercased()) { config.scene = scene }
        if let raw = value("-LHHouseConfirmHours"), let h = Double(raw) { config.confirmHours = h }
        if let raw = value("-LHHouseConfirmDelay"), let s = Double(raw) { config.confirmDelay = s }
        if let raw = value("-LHHouseMilestone") { config.milestone = raw.lowercased() }
        if let raw = value("-LHHouseStartDelay"), let s = Double(raw) { config.startDelay = s }
        if let raw = value("-LHHouseSuggestions"), let n = Int(raw) { config.suggestions = n }
        config.settled = args.contains("-LHHouseSettled")
        config.unlit = args.contains("-LHHouseUnlit")
        return config
    }

    /// The celebration the milestone scene shows: the explicit one, else the highest this goal
    /// has earned at these hours (as if every hour had just been confirmed).
    var resolvedCelebration: HouseCelebration {
        switch milestone {
        case "goal": return .goalMet(goal)
        case "100": return .stage(.foundation100)
        case "500": return .stage(.roof500)
        case "750": return goal == .reps750 ? .goalMet(.reps750) : .stage(.keys750)
        default:
            return HouseProgress.celebrations(from: 0, to: max(hours, 0.01), goal: goal).last ?? .stage(.foundation100)
        }
    }
}

struct HousePreviewRoot: View {
    let config: HousePreviewLaunch
    @State private var hours: Double
    @State private var lit: Bool

    init(config: HousePreviewLaunch) {
        self.config = config
        _hours = State(initialValue: config.hours)
        _lit = State(initialValue: !config.unlit)
    }

    var body: some View {
        content
            .preferredColorScheme(config.scheme)
            .environment(\.colorScheme, config.scheme)
    }

    @ViewBuilder
    private var content: some View {
        switch config.scene {
        case .hero, .confirm:
            VStack {
                CraftHouseView(stage: CraftStage.stage(hours: hours, goal: config.goal.targetHours), windowsLit: lit, side: 390)
                Spacer()
            }
            .padding(.top, 60)
            .frame(maxWidth: .infinity)
            .background { LHPage() }
            .task {
                guard config.scene == .confirm else { return }
                try? await Task.sleep(for: .seconds(config.confirmDelay))
                hours += config.confirmHours
                lit = true
            }
        case .milestone:
            MilestoneCelebrationView(
                celebration: config.resolvedCelebration,
                hours: hours,
                windowsLit: !config.unlit,
                goalHours: config.goal.targetHours,
                startSettled: config.settled,
                startDelay: config.startDelay,
                onContinue: {}
            )
        case .backfill:
            BackfillRevealView(
                foundHours: hours,
                suggestionCount: config.suggestions,
                startSettled: config.settled,
                startDelay: config.startDelay
            )
        }
    }
}
#endif
