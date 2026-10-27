import SwiftUI

#if DEBUG
// MARK: - Log time v2 design sandbox: the two directions (DESIGN ONLY)
//
// A · "Say it in one line": one calm screen. The sentence field is the screen; the review card
//     builds under it while you type or after you speak. Anchors: Superlist quick add (parsed
//     tokens under the line), Fantastical (sentence → event), Toggl (timer bar).
// B · "Three doors": Say it / Type it / Time it as three rows, each a focused step, then a
//     dedicated "Check and log" step with the same card. Anchors: Apple Voice Memos / dictation
//     (listening), Things quick entry, Toggl (timer).
//
// Both share the same card (LHReadBack), the same timer (LHTimerFace), the same LHSheet shell,
// and only LH* components and tokens.

// MARK: Shared pieces

struct LogV2ReadingLine: View {
    var text = "Reading what you said"
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        HStack(spacing: 10) {
            DraftingLoader(sketch: .document, subject: "your note", lineWidth: 1.5)
                .frame(width: 44, height: 30)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AdaptiveColors(colorScheme: colorScheme).textSecondary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: LHMetrics.rowMinHeight)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("logv2.reading")
    }
}

struct LogV2LogButton: View {
    @ObservedObject var model: LogV2Model
    var body: some View {
        Button {
            model.log()
        } label: {
            Text(model.canLog ? "Log \(LHFormat.hours(model.hours))" : "Log it")
                .contentTransition(.numericText())
        }
        .buttonStyle(LHButton.primaryGlass)
        .disabled(!model.canLog)
        .accessibilityIdentifier("logv2.log")
    }
}

/// The timer steps are the same in both directions.
struct LogV2TimerRunning: View {
    @ObservedObject var model: LogV2Model
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        LHSheet("Timer", subtitle: "Keeps running if you close this", onClose: {}) {
            VStack(spacing: 16) {
                LHTimerFace(rental: "Pine Cabin", work: "Management", start: model.timerStart,
                            frozenAt: model.timerFrozen ? LogV2Sample.now : nil)
                LHSheetRowGroup {
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
}

struct LogV2TimerNote: View {
    @ObservedObject var model: LogV2Model
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LHSheet("What did you do?", subtitle: model.timerSummary, onClose: {}) {
            LHCaptureField(placeholder: "Add a few words (optional)", text: $model.note, minHeight: 104,
                           focus: $focused, onMic: {})
            Text("The timer already has the rental, the time and the day.")
                .font(.footnote)
                .foregroundStyle(AdaptiveColors(colorScheme: colorScheme).textSecondary)
        } primary: {
            Button("Next") { model.finishTimer() }
                .buttonStyle(LHButton.primaryGlass)
                .accessibilityIdentifier("logv2.timer.next")
        } secondary: {
            Button("Skip the note") { model.note = ""; model.finishTimer() }
                .buttonStyle(LHButton.tertiary)
        }
    }
}

struct LogV2Manual: View {
    @ObservedObject var model: LogV2Model
    @State private var note = ""
    var body: some View {
        LHSheet("Enter details", subtitle: LogV2Format.subtitle, onClose: {}) {
            LHReadBack(model: model) { LogV2Answer(model: model, field: $0) }
            LHField("Note (optional)", text: $note, accessibilityLabel: "Note")
        } footer: {
            LogV2LogButton(model: model)
        }
    }
}

// MARK: - Direction A · one line

struct LogV2SheetA: View {
    @ObservedObject var model: LogV2Model
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        switch model.stage {
        case .timerRunning: LogV2TimerRunning(model: model)
        case .timerNote: LogV2TimerNote(model: model)
        case .manual: LogV2Manual(model: model)
        default: oneLine
        }
    }

    private var noteBinding: Binding<String> {
        model.stage == .listening ? $model.transcript : $model.note
    }

    private var oneLine: some View {
        LHSheet("Log time", subtitle: LogV2Format.subtitle, onClose: {}) {
            LHCaptureField(placeholder: "What did you do?", text: noteBinding,
                           isListening: model.stage == .listening, level: model.level,
                           compact: model.stage == .review || model.stage == .logged,
                           focus: $focused) {
                model.stage == .listening ? model.stopListening() : model.startListening()
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
                }
                .padding(.top, 8)
                LHSheetRowGroup {
                    LHRow.Browse(title: "Start a timer", meta: "Log it when you stop", systemImage: "timer") {
                        model.startTimer()
                    }
                    .accessibilityIdentifier("logv2.startTimer")
                }
            case .listening:
                Text("Say the rental, what you did and how long.")
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .padding(.horizontal, 4)
            case .reading:
                LogV2ReadingLine()
            case .review, .logged:
                VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
                    Text(model.usedVoice ? "From what you said" : "From what you wrote")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.textSecondary)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                    LHReadBack(model: model) { LogV2Answer(model: model, field: $0) }
                }
                .transition(.opacity.combined(with: .offset(y: 8)))
            default:
                EmptyView()
            }
        } primary: {
            if model.stage == .review || model.stage == .reading || model.stage == .logged {
                LogV2LogButton(model: model)
            }
        } secondary: {
            if model.stage == .entry {
                Button("Enter details yourself") {
                    model.apply(state: "manual")
                }
                .buttonStyle(LHButton.tertiary)
                .accessibilityIdentifier("logv2.manual")
            }
        }
    }
}

// MARK: - Direction B · three doors

struct LogV2SheetB: View {
    @ObservedObject var model: LogV2Model
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        switch model.stage {
        case .entry: doors
        case .typing: typeStep
        case .listening, .reading: sayStep
        case .review, .logged: checkStep
        case .timerRunning: LogV2TimerRunning(model: model)
        case .timerNote: LogV2TimerNote(model: model)
        case .manual: LogV2Manual(model: model)
        }
    }

    private var doors: some View {
        LHSheet("Log time", subtitle: LogV2Format.subtitle, onClose: {}) {
            LHSheetRowGroup {
                LHRow.Browse(title: "Say it", meta: "Tell it like you'd tell a friend", systemImage: "mic.fill") {
                    model.startListening()
                }
                .accessibilityIdentifier("logv2.door.say")
                LHDivider(leadingInset: 64)
                LHRow.Browse(title: "Type it", meta: "A few words is enough", systemImage: "keyboard") {
                    withAnimation(AppAnimation.flow) { model.stage = .typing }
                }
                .accessibilityIdentifier("logv2.door.type")
                LHDivider(leadingInset: 64)
                LHRow.Browse(title: "Time it", meta: "Start now, log when you stop", systemImage: "timer") {
                    model.startTimer()
                }
                .accessibilityIdentifier("logv2.door.time")
            }
            VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
                LHSectionHeader("Log again")
                LHSheetRowGroup {
                    ForEach(Array(LogV2Sample.recents.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { LHDivider(leadingInset: 64) }
                        LHRow.Browse(title: r.title, value: LHFormat.hours(r.hours),
                                     systemImage: "arrow.counterclockwise", tint: .neutral) {
                            model.note = r.note
                            model.submitNote()
                        }
                    }
                }
            }
            .padding(.top, 8)
        } primary: {
            EmptyView()
        } secondary: {
            Button("Enter details yourself") { model.apply(state: "manual") }
                .buttonStyle(LHButton.tertiary)
                .accessibilityIdentifier("logv2.manual")
        }
    }

    private var typeStep: some View {
        LHSheet("Type it", subtitle: LogV2Format.subtitle, onClose: { model.reset() }) {
            LHCaptureField(placeholder: "What did you do?", text: $model.note, focus: $focused) {
                model.startListening()
            }
            .onAppear { focused = true }
            Text("Try \u{201C}fixed the sink at Pine Cabin, 1 hour\u{201D}")
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, 4)
        } footer: {
            Button("Next") { model.submitNote() }
                .buttonStyle(LHButton.primaryGlass)
                .disabled(model.note.trimmingCharacters(in: .whitespaces).count < 3)
                .accessibilityIdentifier("logv2.next")
        }
    }

    private var sayStep: some View {
        LHSheet("Say it", subtitle: LogV2Format.subtitle, onClose: { model.reset() }) {
            VStack(alignment: .leading, spacing: 24) {
                Group {
                    if model.stage == .reading {
                        Text(model.note)
                    } else if model.transcript.isEmpty {
                        Text("Say the rental, what you did and how long.").foregroundStyle(colors.textTertiary)
                    } else {
                        Text(model.transcript)
                    }
                }
                .font(.title2.weight(.semibold))
                .foregroundStyle(colors.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                .accessibilityIdentifier("logv2.transcript")
                if model.stage == .reading {
                    LogV2ReadingLine()
                } else {
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
            }
            .padding(.top, 8)
        } primary: {
            Button("Done") { model.stopListening() }
                .buttonStyle(LHButton.primaryGlass)
                .disabled(model.stage == .reading)
                .accessibilityIdentifier("logv2.done")
        } secondary: {
            Button("Type instead") {
                model.note = model.transcript
                withAnimation(AppAnimation.flow) { model.stage = .typing }
            }
            .buttonStyle(LHButton.tertiary)
        }
    }

    private var checkStep: some View {
        LHSheet("Check and log", subtitle: LogV2Format.subtitle, onClose: {}) {
            if !model.note.isEmpty {
                Button {
                    withAnimation(AppAnimation.flow) { model.stage = .typing }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\u{201C}\(model.note)\u{201D}")
                            .font(.body)
                            .foregroundStyle(colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Edit")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(colors.action)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, minHeight: LHMetrics.rowMinHeight, alignment: .leading)
                    .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                }
                .buttonStyle(LHButton.press)
                .accessibilityLabel("Your note: \(model.note). Edit")
                .accessibilityIdentifier("logv2.quote")
            }
            LHReadBack(model: model) { LogV2Answer(model: model, field: $0) }
        } primary: {
            LogV2LogButton(model: model)
        } secondary: {
            Button("Start over") { model.reset() }
                .buttonStyle(LHButton.tertiary)
        }
    }
}
#endif
