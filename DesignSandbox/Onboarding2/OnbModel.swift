// 2.0 onboarding (spec: AgentScratch/landlordhours/2026-10-19/onboarding/design.md).
// Launch: -LHOnboardingStep <0…6 | wn1…wn3 | today | today-reveal | today-skip | flow>
// Optional state: -LHOnbGoal reps750|mp500|mp100|record|none  -LHOnbWho me|both  -LHOnbName "…"
//                 -LHOnbPrompt 1 (show the system-prompt mock)  -LHOnbAuto happy|skip (scripted run)
//                 -LHOnbStaked 1 (step 4 after the stake drops)  -LHOnbMockLabels 0 (hide mock tags)
import SwiftUI
import Observation

enum OnbStep: String, CaseIterable {
    case welcome, goal, calendar, who, property, notify, staked
    case wnHouse            // upgraders: "Your hours now build a house."

    var isFullBleed: Bool { self == .welcome || self == .staked }
}

enum OnbGoal: String { case reps750, mp500, mp100, record }
enum OnbWho: String { case me, both }
enum OnbCalendar { case notAsked, allowed, denied }
enum OnbPrompt { case calendar, notify }
enum OnbStage { case onboarding, today, whatsNew }
enum OnbCohort { case new, upgrade }

@MainActor @Observable
final class OnbFlow {
    var cohort: OnbCohort = .new
    var sequence: [OnbStep] = [.welcome, .goal, .calendar, .who, .property, .notify, .staked]
    var index = 0
    var forward = true
    var stage: OnbStage = .onboarding

    var goal: OnbGoal? = nil
    var who: OnbWho = .me
    var name = ""
    var addressOpen = false
    var calendar: OnbCalendar = .notAsked
    var notify: Bool? = nil
    var prompt: OnbPrompt? = nil
    var promptPressed = false          // autoplay: the Allow button shows its pressed state
    var skippedProperty = false

    // Header scene
    var calendarRows = 0               // 0…3 sample rows shown (and hatched storeys)
    var stakeDropped = false
    var flagOpen = false

    // Non-blocking backfill
    var scanProgress: Double = 0       // 0…1
    var foundHours = 0
    var suggestions = 0
    var scanDone: Bool { scanProgress >= 1 }

    // Today landing
    var inboxBadge = 0
    var revealShown = false
    var upgradeHours: Double = 312

    var step: OnbStep { sequence[min(index, sequence.count - 1)] }
    /// Progress ticks: six for new users (goal…staked), three for upgraders.
    var progressTotal: Int { cohort == .new ? 6 : 3 }
    var progressValue: Int { cohort == .new ? index : index + 1 }

    var goalHours: Int? {
        switch goal {
        case .reps750: 750
        case .mp500: 500
        case .mp100: 100
        case .record, nil: nil
        }
    }

    var mockLabels: Bool { UserDefaults.standard.object(forKey: "LHOnbMockLabels") == nil || UserDefaults.standard.bool(forKey: "LHOnbMockLabels") }

    // MARK: Navigation

    func go(to step: OnbStep, reduce: Bool) {
        guard let i = sequence.firstIndex(of: step) else { return }
        forward = i >= index
        withAnimation(OnbMotion.morph(reduce)) { index = i }
    }

    func next(reduce: Bool) {
        var n = index + 1
        // The visit-end note is only asked after a calendar grant.
        if n < sequence.count, sequence[n] == .notify, calendar != .allowed { n += 1 }
        // A skipped property never reaches "staked": the empty lot waits on Today.
        if n < sequence.count, sequence[n] == .staked, skippedProperty { finish(); return }
        if n >= sequence.count { finish(); return }
        forward = true
        withAnimation(OnbMotion.morph(reduce)) { index = n }
    }

    func back(reduce: Bool) {
        var p = index - 1
        if p > 0, sequence[p] == .notify, calendar != .allowed { p -= 1 }
        guard p >= 0 else { return }
        forward = false
        withAnimation(OnbMotion.morph(reduce)) {
            if sequence[p] == .property { stakeDropped = false; flagOpen = false }
            index = p
        }
    }

    func finish() {
        withAnimation(.easeInOut(duration: 0.35)) { stage = .today }
    }

    // MARK: Backfill (runs while the user answers the remaining questions)

    func startScan(reduce: Bool) {
        guard scanProgress == 0 else { return }
        Task { @MainActor in
            let ticks = 60
            for t in 1...ticks {
                try? await Task.sleep(for: .milliseconds(150))
                let p = Double(t) / Double(ticks)
                withAnimation(.linear(duration: 0.15)) {
                    scanProgress = p
                    foundHours = Int((212 * p).rounded())
                    suggestions = Int((14 * p).rounded())
                }
            }
        }
    }

    func finishScanInstantly() {
        scanProgress = 1; foundHours = 212; suggestions = 14
    }
}

enum OnbMotion {
    /// Header morph between steps (spec: spring 0.5 / 0.85). Reduce Motion: a short cross-fade.
    static func morph(_ reduce: Bool) -> Animation { reduce ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.85) }
    /// Progress dimension line (spec: 0.35 / 0.9).
    static func progress(_ reduce: Bool) -> Animation { reduce ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.9) }
    /// In-flow reveal (notes, chips): the shipped `flow` spring.
    static func flow(_ reduce: Bool) -> Animation { reduce ? .easeInOut(duration: 0.2) : .spring(response: 0.34, dampingFraction: 0.88) }
}

/// Requested appearance from `-appearance`, independent of the window override the blueprint band needs.
struct OnbSchemeKey: EnvironmentKey { static let defaultValue: ColorScheme = .light }
extension EnvironmentValues {
    var onbScheme: ColorScheme {
        get { self[OnbSchemeKey.self] }
        set { self[OnbSchemeKey.self] = newValue }
    }
}

struct BottomInsetKey: EnvironmentKey { static let defaultValue: CGFloat = 34 }
extension EnvironmentValues {
    var onbBottomInset: CGFloat {
        get { self[BottomInsetKey.self] }
        set { self[BottomInsetKey.self] = newValue }
    }
}
