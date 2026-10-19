import SwiftUI

#if DEBUG
// MARK: - DEBUG launch hook for house captures
//
//   -LHHousePreview <hours> <goal> <scheme>
//       hours: countable hours (e.g. 212, 499.5)
//       goal:  reps | mp500 | mp100
//       scheme: light | dark
//   Optional:
//   -LHHouseScene hero|confirm|milestone|backfill   (default hero)
//   -LHHouseConfirmHours <h>    confirm scene: hours added by the confirm (default 2)
//   -LHHouseConfirmDelay <s>    confirm scene: seconds before the confirm plays (default 1.5)
//   -LHHouseConfirmStill <n>    show board frame n (0...12) statically over the hero
//   -LHHouseMilestone 100|500|750   milestone scene: which celebration (default: highest reached)
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
    var confirmStill: Int? = nil
    var milestone: HouseMilestone? = nil
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
        if let raw = value("-LHHouseConfirmStill"), let n = Int(raw) { config.confirmStill = n }
        if let raw = value("-LHHouseMilestone"), let n = Int(raw) { config.milestone = HouseMilestone(rawValue: n) }
        if let raw = value("-LHHouseSuggestions"), let n = Int(raw) { config.suggestions = n }
        config.settled = args.contains("-LHHouseSettled")
        return config
    }

    /// The celebration the milestone scene shows: the explicit one, else the highest reached.
    var resolvedMilestone: HouseMilestone {
        milestone ?? HouseMilestone.allCases.last { $0.isReached(by: hours) } ?? .foundation100
    }
}

struct HousePreviewRoot: View {
    let config: HousePreviewLaunch
    @State private var hours: Double
    @State private var celebration: HouseMilestone?

    init(config: HousePreviewLaunch) {
        self.config = config
        _hours = State(initialValue: config.hours)
    }

    var body: some View {
        switch config.scene {
        case .hero, .confirm:
            content
                .preferredColorScheme(config.scheme)
                .environment(\.colorScheme, config.scheme)
        case .milestone, .backfill:
            // Full-blueprint screens style themselves dark; the art follows `artScheme`.
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch config.scene {
        case .hero, .confirm:
            ZStack(alignment: .top) {
                HouseTokens.canvas(config.scheme).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Today")
                        .font(.largeTitle.bold())
                        .foregroundStyle(config.scheme == .dark ? Color.white : Color(hex: "121B33"))
                        .padding(.top, 8)
                    HouseHeroCard(
                        progress: HouseProgress(hours: hours, goal: config.goal),
                        onMilestone: { celebration = $0 },
                        debugConfirmStill: config.confirmStill
                    )
                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .task {
                guard config.scene == .confirm, config.confirmStill == nil else { return }
                try? await Task.sleep(nanoseconds: UInt64(config.confirmDelay * 1_000_000_000))
                hours += config.confirmHours
            }
            .fullScreenCover(item: $celebration) { milestone in
                MilestoneCelebrationView(milestone: milestone, hours: hours, artScheme: config.scheme) { celebration = nil }
            }
        case .milestone:
            MilestoneCelebrationView(
                milestone: config.resolvedMilestone,
                hours: hours,
                artScheme: config.scheme,
                startSettled: config.settled,
                onContinue: {}
            )
        case .backfill:
            BackfillRevealView(
                foundHours: hours,
                suggestionCount: config.suggestions,
                artScheme: config.scheme,
                startSettled: config.settled
            )
        }
    }
}
#endif
