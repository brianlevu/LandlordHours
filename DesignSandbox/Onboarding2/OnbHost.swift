import SwiftUI

/// Entry for `-LHOnboardingStep`. Builds the flow state for a static frame, or runs a scripted
/// pass (`-LHOnbAuto happy|skip`) for the recordings.
struct OnbHost: View {
    let arg: String
    let scheme: ColorScheme
    @State private var flow: OnbFlow
    @Environment(\.accessibilityReduceMotion) private var reduce

    init(arg: String, scheme: ColorScheme) {
        NSLog("LHONB reduceMotion=%@", UIAccessibility.isReduceMotionEnabled ? "on" : "off")
        self.arg = arg
        self.scheme = scheme
        _flow = State(initialValue: OnbHost.makeFlow(arg))
    }

    var body: some View {
        Group {
            switch flow.cohort {
            case .new:
                ZStack {
                    if flow.stage == .onboarding {
                        OnbRoot(flow: flow).transition(.opacity)
                    } else if flow.stage == .review {
                        OnbInbox(flow: flow).transition(.opacity)
                    } else {
                        OnbToday(flow: flow).transition(.opacity)
                    }
                }
                .sheet(isPresented: $flow.revealShown) {
                    OnbFoundReveal(flow: flow)
                        .environment(\.onbScheme, scheme)
                        .presentationDragIndicator(.visible)
                }
            case .upgrade:
                OnbToday(flow: flow)
                    .sheet(isPresented: Binding(get: { flow.stage == .whatsNew }, set: { if !$0 { flow.stage = .today } })) {
                        OnbRoot(flow: flow, embedded: true)
                            .environment(\.onbScheme, scheme)
                            .presentationDetents([.large])
                            .presentationDragIndicator(.visible)
                            .interactiveDismissDisabled(false)
                    }
            }
        }
        .environment(\.onbScheme, scheme)
        // The window keeps the requested appearance (so the keyboard matches the system). Only the
        // status bar goes light while the blueprint band sits under it.
        .preferredColorScheme(scheme)
        .onChange(of: flow.stage, initial: true) { _, _ in applyStatusBar() }
        .task { try? await Task.sleep(for: .milliseconds(150)); applyStatusBar() }
        .task { await autoplay() }
        .task { await landing() }
    }

    private func applyStatusBar() {
        let overBand = flow.cohort == .new && flow.stage == .onboarding
        StatusBarStyler.set(overBand || scheme == .dark ? .lightContent : .darkContent)
    }

    // MARK: Static states

    static func makeFlow(_ arg: String) -> OnbFlow {
        let d = UserDefaults.standard
        let f = OnbFlow()
        let goal = d.string(forKey: "LHOnbGoal") ?? "reps750"
        f.goal = goal == "none" ? nil : OnbGoal(rawValue: goal) ?? .reps750
        f.who = OnbWho(rawValue: d.string(forKey: "LHOnbWho") ?? "me") ?? .me
        f.name = d.string(forKey: "LHOnbName") ?? ""
        if d.string(forKey: "LHOnbAuto") != nil || arg == "flow" { f.goal = nil; return f }

        func at(_ s: OnbStep) { f.index = f.sequence.firstIndex(of: s) ?? 0 }
        let prompt = d.bool(forKey: "LHOnbPrompt")
        switch arg {
        case "0": at(.welcome)
        case "1": at(.goal)
        case "2":
            at(.goal); f.index = 2; f.calendarRows = 3
            if prompt { f.prompt = .calendar }
        case "3":
            at(.who); f.calendar = .allowed; f.setFound(5)
        case "4":
            at(.property); f.calendar = .allowed; f.setFound(9)
            if d.bool(forKey: "LHOnbStaked") {
                if f.name.isEmpty { f.name = "Oak Street duplex" }
                f.stakeDropped = true; f.flagOpen = true
            }
        case "5":
            at(.notify); f.calendar = .allowed; f.setFound(12)
            if f.name.isEmpty { f.name = "Oak Street duplex" }
            f.stakeDropped = true; f.flagOpen = true
            if prompt { f.prompt = .notify }
        case "6":
            at(.staked); f.calendar = .allowed; f.finishScanInstantly()
            if f.name.isEmpty { f.name = "Oak Street duplex" }
            f.stakeDropped = true; f.flagOpen = true
        case "today", "today-reveal":
            f.stage = .today; f.calendar = .allowed; f.finishScanInstantly(); f.inboxBadge = 14
            if f.name.isEmpty { f.name = "Oak Street duplex" }
            f.stakeDropped = true; f.flagOpen = true
            if arg == "today-reveal" { f.revealShown = true } else { f.countShown = true }
        case "review":
            f.stage = .review; f.calendar = .allowed; f.finishScanInstantly(); f.inboxBadge = 14; f.countShown = true
            if f.name.isEmpty { f.name = "Oak Street duplex" }
            f.stakeDropped = true; f.flagOpen = true
        case "today-skip":
            f.stage = .today; f.skippedProperty = true; f.calendar = .denied
        case "today-nocal":
            // Staked, but "Not now" on the calendar: Today keeps a calm way back to the ask.
            f.stage = .today; f.calendar = .denied
            if f.name.isEmpty { f.name = "Oak Street duplex" }
            f.stakeDropped = true; f.flagOpen = true
        case "wn1", "wn2", "wn3":
            f.cohort = .upgrade
            f.goal = .reps750
            f.sequence = [.wnHouse, .calendar, .notify]
            f.stage = .whatsNew
            f.index = arg == "wn1" ? 0 : (arg == "wn2" ? 1 : 2)
            if arg == "wn2" { f.calendarRows = 3; if prompt { f.prompt = .calendar } }
            if arg == "wn3" { f.calendar = .allowed; if prompt { f.prompt = .notify } }
        default: break
        }
        return f
    }

    // MARK: Landing: suggestions arrive, the Inbox badge counts up, the reveal plays once

    private func landing() async {
        guard flow.cohort == .new else { return }
        while flow.stage == .onboarding { try? await Task.sleep(for: .milliseconds(100)); if Task.isCancelled { return } }
        guard UserDefaults.standard.string(forKey: "LHOnbAuto") != nil || arg == "flow" else { return }
        guard flow.calendar == .allowed else { return }
        try? await Task.sleep(for: .milliseconds(600))
        for i in 1...flow.suggestions {
            withAnimation(.easeOut(duration: 0.12)) { flow.inboxBadge = i }
            try? await Task.sleep(for: .milliseconds(90))
        }
        try? await Task.sleep(for: .milliseconds(1400))
        // The count already led on Staked: never repeat it in a sheet.
        if !flow.countShown { flow.revealShown = true }
    }

    // MARK: Scripted runs for the recordings (taps are simulated; every screen is the real one)

    private func wait(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }

    private func autoplay() async {
        guard let mode = UserDefaults.standard.string(forKey: "LHOnbAuto") else { return }
        let r = reduce
        await wait(UserDefaults.standard.integer(forKey: "LHOnbAutoDelay"))   // lets the recorder start on Welcome
        await wait(2400)                                   // Welcome
        flow.next(reduce: r)                               // Start building
        await wait(1300)
        withAnimation(OnbMotion.flow(r)) { flow.goal = .reps750 }
        await wait(1100)
        flow.next(reduce: r)                               // Build toward 750h
        await wait(2000)                                   // rows + hatched storeys appear
        if mode == "happy" {
            withAnimation(.easeOut(duration: 0.2)) { flow.prompt = .calendar }
            await wait(1700)
            withAnimation(.easeOut(duration: 0.1)) { flow.promptPressed = true }
            await wait(250)
            withAnimation(.easeOut(duration: 0.2)) { flow.prompt = nil; flow.promptPressed = false }
            flow.calendar = .allowed
            flow.startScan(reduce: r)
            flow.next(reduce: r)
        } else {
            flow.calendar = .denied
            flow.next(reduce: r)                           // Not now
        }
        await wait(1200)
        withAnimation(OnbMotion.flow(r)) { flow.who = .both }
        await wait(1900)
        flow.next(reduce: r)                               // Continue
        await wait(1100)
        if mode == "happy" {
            NotificationCenter.default.post(name: .onbFocus, object: nil)
            await wait(500)
            for ch in "Oak Street duplex" {
                flow.name.append(ch)
                await wait(70)
            }
            await wait(600)
            NotificationCenter.default.post(name: .onbStake, object: nil)   // Stake it → drop, flag, hold, morph
            await wait(2700)                               // Visit-end note
            withAnimation(.easeOut(duration: 0.2)) { flow.prompt = .notify }
            await wait(1500)
            withAnimation(.easeOut(duration: 0.1)) { flow.promptPressed = true }
            await wait(250)
            withAnimation(.easeOut(duration: 0.2)) { flow.prompt = nil; flow.promptPressed = false }
            flow.notify = true
            flow.next(reduce: r)
            await wait(3400)                               // Staked
            flow.finish()                                  // Go to Today
        } else {
            await wait(800)
            flow.skippedProperty = true
            flow.next(reduce: r)                           // I'll add it later → Today, empty lot
        }
    }
}
