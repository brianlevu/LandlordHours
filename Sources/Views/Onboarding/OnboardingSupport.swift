import SwiftUI
import UIKit
import ObjectiveC

// MARK: - Status bar over the blueprint band

/// Light status-bar content over the blueprint band WITHOUT forcing the window dark (a dark
/// window would also give a light-mode user a dark keyboard). SwiftUI has no status-bar-style
/// API, so this overrides `preferredStatusBarStyle` on the root hosting controller's class.
/// `.default` hands control back to the system everywhere else.
@MainActor
enum OnbStatusBar {
    private static var style: UIStatusBarStyle = .default
    private static var installedOn: AnyClass?

    static func set(_ newStyle: UIStatusBarStyle) {
        style = newStyle
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let root = (windows.first(where: \.isKeyWindow) ?? windows.first)?.rootViewController else { return }
        let cls: AnyClass = type(of: root)
        if installedOn !== cls {
            let sel = #selector(getter: UIViewController.preferredStatusBarStyle)
            let block: @convention(block) (AnyObject) -> Int = { _ in
                MainActor.assumeIsolated { OnbStatusBar.style.rawValue }
            }
            class_replaceMethod(cls, sel, imp_implementationWithBlock(block), "q@:")
            installedOn = cls
        }
        root.setNeedsStatusBarAppearanceUpdate()
    }
}

// MARK: - Capture / UI-test launch hooks (DEBUG only; Release reads nothing)
//
//   -LHOnboardingStep <0…6 | welcome | goal | calendar | who | property | notify | staked>
//   -LHOnbGoal reps750|mp500|mp100|record|none   -LHOnbWho me|both   -LHOnbName "…"
//   -LHOnbStaked 1        step 4 after the stake dropped (the flag is up)
//   -LHOnbHoldStake 1     after "Save it", stay on step 4 (stake-moment captures)
//   -LHOnbFocus 1         focus the name field (keyboard frames)
//   -LHOnbScrollBottom 1  scroll step content to the end (AX3 frames)
//   -LHOnbUpgradeHours <h> What's new house at h hours
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

    @MainActor static func apply(to flow: OnbFlow) {
        if let raw = value("-LHOnbGoal") {
            flow.goal = raw == "none" ? nil : OnbGoal(rawValue: raw)
        } else if startStep != nil, flow.cohort == .new, (startStep ?? .welcome) != .welcome {
            flow.goal = .reps750
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
    @MainActor static func apply(to flow: OnbFlow) {}
    #endif
}
