import SwiftUI

// MARK: - Capture / UI-test launch hooks (DEBUG only; Release reads nothing)
//
//   -LHOnboardingStep <0…6 | welcome | goal | calendar | who | property | notify | staked>
//   -LHOnbGoal reps750|mp500|mp100|record|none   -LHOnbWho me|both   -LHOnbName "…"
//   -LHOnbStaked 1        step 4 after the stake dropped (the flag is up)
//   -LHOnbHoldStake 1     after "Save it", stay on step 4 (stake-moment captures)
//   -LHOnbFocus 1         focus the name field (keyboard frames)
//   -LHOnbRental short|long|both · -LHOnbPro me|spouse|none · -LHOnbGoalPhase rental|pro|target
//   -LHOnbScrollBottom 1  scroll step content to the end (AX3 frames)
//   -LHOnbUpgradeHours <h> What's new house at h hours
//   -LHOnbAccountSheet 1  Welcome with the "Have an account?" sheet open (captures)
enum OnbDebugLaunch {
    #if DEBUG
    private static func value(_ flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
    private static func flag(_ name: String) -> Bool { value(name) == "1" }

    static var startStep: OnbStep? { value("-LHOnboardingStep").flatMap(OnbStep.init(launchValue:)) }
    static var scrollToBottom: Bool { flag("-LHOnbScrollBottom") }
    static var focusName: Bool { flag("-LHOnbFocus") }
    static var holdAfterStake: Bool { flag("-LHOnbHoldStake") }
    static var accountSheet: Bool { flag("-LHOnbAccountSheet") }

    @MainActor static func apply(to flow: OnbFlow) {
        if let raw = value("-LHOnbGoal") {
            flow.goal = raw == "none" ? nil : OnbGoal(rawValue: raw)
        } else if startStep != nil, flow.cohort == .new, (startStep ?? .welcome) != .welcome {
            flow.goal = .reps750
        }
        // The goal step: -LHOnbRental short|long|both, -LHOnbPro me|spouse|none, -LHOnbGoalPhase rental|pro|target.
        if let raw = value("-LHOnbRental") {
            flow.rental = ["short": RentalMix.shortStays, "long": .longTerm, "both": .both][raw]
        }
        if let raw = value("-LHOnbPro") {
            flow.pro = ["me": RealEstatePro.me, "spouse": .spouse, "none": .nobody][raw]
        }
        if let rental = flow.rental, let pro = flow.pro, value("-LHOnbGoal") == nil {
            flow.goal = OnbGoalSuggestion.make(rental: rental, pro: pro).suggested
        }
        if let raw = value("-LHOnbGoalPhase") {
            flow.goalPhase = ["rental": OnbGoalPhase.rental, "pro": .pro, "target": .target][raw] ?? .rental
            if flow.goalPhase != .target, value("-LHOnbGoal") == nil { flow.goal = nil }
        }
        if let raw = value("-LHOnbWho"), let who = OnbWho(rawValue: raw) { flow.who = who }
        if let name = value("-LHOnbName") { flow.name = name }
        if let raw = value("-LHOnbUpgradeHours"), let h = Double(raw) { flow.upgradeHours = h }
        guard let step = startStep, flow.cohort == .new else { return }
        let past = OnbRouting.newUserSequence.firstIndex(of: step) ?? 0
        if past > OnbRouting.newUserSequence.firstIndex(of: .calendar)! { flow.calendar = .notNow }
        if step == .calendar { flow.calendarRows = 3 }
        if step == .notify || step == .staked || flag("-LHOnbStaked") {
            if flow.name.isEmpty { flow.name = "Oak Street duplex" }
            flow.stakeDropped = true
            flow.flagOpen = true
        }
        if step == .notify { flow.calendar = .allowed }
    }
    #else
    static var startStep: OnbStep? { nil }
    static var scrollToBottom: Bool { false }
    static var focusName: Bool { false }
    static var holdAfterStake: Bool { false }
    static var accountSheet: Bool { false }
    @MainActor static func apply(to flow: OnbFlow) {}
    #endif
}
