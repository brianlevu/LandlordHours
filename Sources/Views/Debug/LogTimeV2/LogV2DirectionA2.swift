import SwiftUI

#if DEBUG
// MARK: - Log time v2 · Direction A, round 2 (after the independent critique, 2026-10-27)
//
// What changed from r1 (B stays at r1 for comparison):
//   - The sheet sits on the app's tinted page (`background`) with white rows and cards, the way 2.2
//     Today, Rentals and Settings do. Proposed as `LHSheet(surface: .page)` (a parameter, not a new
//     component); `LogV2PageSheet` below is that parameter, inlined so production LHSheet is untouched.
//   - The mic is a filled action button (44pt) at rest; listening is B's "Say it" screen (big live
//     words), pushed in.
//   - The review is one white card of value tokens (LHChip in a wrapping layout), a truthful header,
//     one line naming every assumed value, and at most one open answer. No chevrons.
//   - A disabled Log says why ("Answer 1 question"). Hours are never assumed, manual included. The
//     timer logs the minutes it ran, so the note step and the card show one duration.
//   - Steps push (`.push(from:)`, `flow`); Reduce Motion crossfades. The toast waits for the sheet.
//
// New components after r2: LHCaptureField (+ LHLevelMeter) and LHTimerFace only.

// MARK: Page-surface sheet (proposed LHSheet(surface: .page))

struct LogV2PageSheet<Content: View, Footer: View, Secondary: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content
    @ViewBuilder var primary: Footer
    @ViewBuilder var secondary: Secondary

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var ax: Bool { typeSize.isAccessibilitySize }

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content,
         @ViewBuilder primary: () -> Footer, @ViewBuilder secondary: () -> Secondary) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if ax { titleBlock }
                content
                if ax { VStack(spacing: 8) { secondary }.frame(maxWidth: .infinity) }
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(colors.background)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                if !ax { titleBlock } else { Spacer(minLength: 0) }
                Button {} label: { Image(systemName: "xmark") }
                    .buttonStyle(LHButton.icon)
                    .accessibilityLabel("Close")
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(colors.background)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                if !ax { secondary }
                primary
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            .background(colors.background)
            .overlay(alignment: .top) {
                LinearGradient(colors: [colors.background.opacity(0), colors.background], startPoint: .top, endPoint: .bottom)
                    .frame(height: 24)
                    .offset(y: -24)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(colors.textPrimary)
                .lineLimit(ax ? nil : 2)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(ax ? nil : 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Review card: value tokens (LHChip in a wrapping layout)

struct LogV2TokenCard: View {
    @ObservedObject var model: LogV2Model
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private func icon(_ f: LogV2Field) -> String {
        switch f {
        case .rental: return "house"
        case .hours: return "clock"
        case .work: return "wrench.and.screwdriver"
        case .who: return "person"
        case .day: return "calendar"
        }
    }

    private func needed(_ f: LogV2Field) -> Bool { model.sources[f] == .needed }

    private func title(_ f: LogV2Field) -> String {
        if needed(f) {
            switch f {
            case .rental: return "Which rental?"
            case .hours: return "How long?"
            default: return f.question
            }
        }
        return model.value(f) ?? LHFormat.unknown
    }

    /// Order: the two that matter most first (time, rental), then work, who, day.
    private var order: [LogV2Field] { model.fieldsShown.sorted { rank($0) < rank($1) } }
    private func rank(_ f: LogV2Field) -> Int { [.hours: 0, .rental: 1, .work: 2, .who: 3, .day: 4][f] ?? 9 }

    private var header: String {
        if model.stage == .manual { return "Your details" }
        if model.fromTimer { return model.note.isEmpty ? "From the timer" : "From the timer and your note" }
        return model.usedVoice ? "From what you said" : "From your note"
    }

    /// One line naming every value the note didn't give.
    private var assumedLine: String? {
        var parts: [String] = []
        for f in order {
            guard case .assumed(let why) = model.sources[f] ?? .needed, let v = model.value(f) else { continue }
            switch why {
            case "": parts.append(v)
            case "From the timer": continue
            default: parts.append("\(v) (\(why.lowercased()))")
            }
        }
        guard !parts.isEmpty else { return nil }
        let lead = model.stage == .manual ? "Filled in for you" : (model.fromTimer ? "Not from the timer" : "Not in your note")
        return "\(lead): \(parts.joined(separator: ", "))."
    }

    private var timerLine: String? {
        guard model.fromTimer, let h = model.hours else { return nil }
        return "The timer ran \(LHFormat.hours(h)) at Pine Cabin, today."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(header)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.textSecondary)
                .accessibilityAddTraits(.isHeader)
            LHFlowLayout(spacing: 8) {
                ForEach(order) { f in
                    LHChip(title(f), systemImage: needed(f) ? "questionmark.circle" : icon(f),
                           isSelected: model.expanded == f) { model.toggle(f) }
                        .accessibilityLabel("\(f.label): \(title(f))")
                        .accessibilityHint(needed(f) ? "Needs an answer" : "Change")
                        .accessibilityIdentifier("logv2.token.\(f.rawValue)")
                }
            }
            if let timerLine {
                Text(timerLine).font(.footnote).foregroundStyle(colors.textSecondary)
            }
            if let assumedLine {
                Text(assumedLine)
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .accessibilityIdentifier("logv2.assumed")
            }
            if let open = model.expanded {
                LHDivider()
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(open.question)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(colors.textPrimary)
                        if needed(open) { LHTag("Needs you", tone: .caution) }
                    }
                    LogV2Answer(model: model, field: open)
                }
                .id(open)
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .padding(LHMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
        .overlay {
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
                    .strokeBorder(colors.border, lineWidth: LHMetrics.hairline)
            }
        }
        .animation(AppAnimation.flow, value: model.expanded)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("logv2.card")
    }
}

// MARK: Log button with its reason

struct LogV2LogButtonA2: View {
    @ObservedObject var model: LogV2Model
    var body: some View {
        Button { model.log() } label: {
            Text(label).contentTransition(.numericText())
        }
        .buttonStyle(LHButton.primaryGlass)
        .disabled(!model.canLog)
        .accessibilityIdentifier("logv2.log")
    }

    private var label: String {
        if model.canLog { return "Log \(LHFormat.hours(model.hours))" }
        let n = model.openQuestions
        return n == 1 ? "Answer 1 question" : (n > 1 ? "Answer \(n) questions" : "Log it")
    }
}

// MARK: The sheet

struct LogV2SheetA2: View {
    @ObservedObject var model: LogV2Model
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private enum Step: Hashable { case line, listen, timer, note, manual }

    private var step: Step {
        switch model.stage {
        case .listening: return .listen
        case .timerRunning: return .timer
        case .timerNote: return .note
        case .manual: return .manual
        default: return .line
        }
    }

    var body: some View {
        ZStack {
            switch step {
            case .line: line.transition(push)
            case .listen: listen.transition(push)
            case .timer: timer.transition(push)
            case .note: timerNote.transition(push)
            case .manual: manual.transition(push)
            }
        }
        .animation(reduceMotion ? AppAnimation.reduced : AppAnimation.flow, value: step)
        .background(colors.background)
    }

    private var push: AnyTransition {
        reduceMotion ? .opacity : .push(from: model.forward ? .trailing : .leading)
    }

    // Entry, reading and review: one screen.
    private var line: some View {
        LogV2PageSheet("Log time", subtitle: LogV2Format.subtitle) {
            LHCaptureField(placeholder: "What did you do?", text: $model.note,
                           compact: model.stage == .review || model.stage == .closing || model.stage == .logged,
                           onPage: true, prominentMic: true, focus: $focused) {
                model.startListening()
            }
            .onChange(of: model.note) { _, _ in model.noteChangedLive() }
            .onAppear { if model.wantsKeyboard { focused = true } }
            .onChange(of: model.wantsKeyboard) { _, on in focused = on }

            switch model.stage {
            case .entry:
                if model.note.isEmpty {
                    Text("Try \u{201C}fixed the sink at Pine Cabin, 1 hour\u{201D}")
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                        .padding(.horizontal, 4)
                }
                VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
                    LHSectionHeader("Log again")
                    LHChipStrip {
                        ForEach(LogV2Sample.recents) { r in
                            LHChip("\(r.title) · \(LHFormat.hours(r.hours))", isSelected: false) {
                                model.note = r.note
                            }
                        }
                    }
                    .padding(.horizontal, -LHMetrics.gutter)
                    // Inset at the leading edge (the strip's own 20pt), faded at the trailing edge.
                    .mask {
                        HStack(spacing: 0) {
                            Rectangle()
                            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 32)
                        }
                        .padding(.horizontal, -LHMetrics.gutter)
                    }
                    .accessibilityIdentifier("logv2.recents")
                }
                .padding(.top, 8)
                LHRowGroup {
                    LHRow.Browse(title: "Start a timer", meta: "Log it when you stop", systemImage: "timer") {
                        model.startTimer()
                    }
                    .accessibilityIdentifier("logv2.startTimer")
                }
            case .reading:
                LogV2ReadingLine()
            case .review, .closing, .logged:
                LogV2TokenCard(model: model)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            default:
                EmptyView()
            }
        } primary: {
            if model.stage != .entry { LogV2LogButtonA2(model: model) }
        } secondary: {
            if model.stage == .entry {
                Button("Enter details yourself") {
                    model.forward = true
                    model.apply(state: "manual")
                }
                .buttonStyle(LHButton.tertiary)
                .accessibilityIdentifier("logv2.manual")
            }
        }
    }

    // B's "Say it" screen, as A's listening state.
    private var listen: some View {
        LogV2PageSheet("Say it", subtitle: LogV2Format.subtitle) {
            VStack(alignment: .leading, spacing: 24) {
                Group {
                    if model.transcript.isEmpty {
                        Text("Say the rental, what you did and how long.").foregroundStyle(colors.textTertiary)
                    } else {
                        Text(model.transcript)
                    }
                }
                .font(.title2.weight(.semibold))
                .foregroundStyle(colors.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                .contentTransition(.opacity)
                .accessibilityIdentifier("logv2.transcript")
                HStack(spacing: 12) {
                    LHLevelMeter(level: model.level, tint: colors.action)
                    Text("Listening")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.action)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: LHMetrics.minTap)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("logv2.listening")
            }
            .padding(.top, 8)
        } primary: {
            Button("Done") { model.stopListening() }
                .buttonStyle(LHButton.primaryGlass)
                .accessibilityIdentifier("logv2.done")
        } secondary: {
            Button("Type instead") {
                model.forward = false
                model.note = model.transcript
                model.stage = .entry
            }
            .buttonStyle(LHButton.tertiary)
        }
    }

    private var timer: some View {
        LogV2PageSheet("Timer", subtitle: "Keeps running if you close this") {
            VStack(spacing: 16) {
                LHTimerFace(rental: "Pine Cabin", work: "Management", start: model.timerStart,
                            frozenAt: model.timerFrozen ? LogV2Sample.now : nil)
                LHRowGroup {
                    LHRow.Browse(title: "Pine Cabin", meta: "Rental", systemImage: "house", action: {})
                    LHDivider(leadingInset: 64)
                    LHRow.Browse(title: "Management", meta: "Work", systemImage: "wrench.and.screwdriver", action: {})
                }
                Text("You'll see it on your Lock Screen.")
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        } primary: {
            Button("Stop and log") { model.stopTimer() }
                .buttonStyle(LHButton.primaryGlass)
                .accessibilityIdentifier("logv2.timer.stop")
        } secondary: {
            Button("Discard timer") {}
                .buttonStyle(LHButton.destructiveTertiary)
        }
    }

    private var timerNote: some View {
        LogV2PageSheet("What did you do?", subtitle: model.timerSummary) {
            LHCaptureField(placeholder: "Add a few words (optional)", text: $model.note, minHeight: 104,
                           onPage: true, prominentMic: true, focus: $focused, onMic: {})
            Text("The timer has the rental, the time and the day.")
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
        } primary: {
            Button("Next") { model.finishTimer() }
                .buttonStyle(LHButton.primaryGlass)
                .accessibilityIdentifier("logv2.timer.next")
        } secondary: {
            Button("Skip the note") { model.note = ""; model.finishTimer() }
                .buttonStyle(LHButton.tertiary)
        }
    }

    private var manual: some View {
        LogV2PageSheet("Enter details", subtitle: LogV2Format.subtitle) {
            LogV2TokenCard(model: model)
            LHCaptureField(placeholder: "Note (optional)", text: $model.note, compact: true, onPage: true,
                           prominentMic: true, focus: $focused, onMic: {})
        } primary: {
            LogV2LogButtonA2(model: model)
        } secondary: {
            EmptyView()
        }
    }
}
#endif
