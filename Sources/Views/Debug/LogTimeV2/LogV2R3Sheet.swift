import SwiftUI

#if DEBUG
// MARK: - Log time v2, round 3: A's flow in "bold numerals + crafted object + editorial calm"
//
//   -LHLogV2 A -LHLogV2Variant beam     A1 · Beam: giant Fraunces duration over a timber beam
//   -LHLogV2 A -LHLogV2Variant object   A2 · Object: a blueprint dial plate holds the duration
//
// Same flow as A (one input, mic, Log again, timer, the app fills things in) and every r2 trust
// fix: no assumed hours (manual included); the open question is the one that needs an answer; a
// disabled Log says what's missing; assumed values are footnoted; the timer logs one duration.
// The review's object is the rental's own house (real art, LHThumb); Log plays the house beat
// (windows 0.40, stageFade 0.25 when the log crosses a stage), then the sheet closes and the toast
// shows. Steps push.

enum LogV2Variant: String { case beam, object, r2 }

struct LogV2SheetR3: View {
    @ObservedObject var model: LogV2Model
    let variant: LogV2Variant
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var ax: Bool { typeSize.isAccessibilitySize }

    private enum Step: Hashable { case line, listen, timer, note }

    private var step: Step {
        switch model.stage {
        case .listening: return .listen
        case .timerRunning: return .timer
        case .timerNote: return .note
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
            }
        }
        .animation(reduceMotion ? AppAnimation.reduced : AppAnimation.flow, value: step)
        .background(colors.background)
    }

    private var push: AnyTransition { reduceMotion ? .opacity : .push(from: model.forward ? .trailing : .leading) }

    private var isReview: Bool { [.review, .closing, .logged, .manual].contains(model.stage) }

    // MARK: One screen: entry → reading → review

    private var line: some View {
        LogV2PageSheet("Log time", subtitle: LogV2Format.subtitle) {
            LHCaptureField(placeholder: "What did you do?", text: $model.note, compact: isReview,
                           onPage: true, prominentMic: true, focus: $focused) { model.startListening() }
                .onChange(of: model.note) { _, _ in model.noteChangedLive() }
                .onAppear { if model.wantsKeyboard { focused = true } }
                .onChange(of: model.wantsKeyboard) { _, on in focused = on }

            switch model.stage {
            case .entry:
                if model.note.isEmpty {
                    Text("Try \u{201C}fixed the sink at Pine Cabin, 1 hour\u{201D}")
                        .font(.footnote).foregroundStyle(colors.textSecondary).padding(.horizontal, 4)
                }
                entryRows
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity, removal: .move(edge: .bottom).combined(with: .opacity)))
            case .reading:
                LogV2ReadingLine()
            case .review, .closing, .logged, .manual:
                recordCard
                    // The card rises into the space the "Log again" rows leave (no crossfade over them).
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .push(from: .bottom), removal: .opacity))
            default:
                EmptyView()
            }
        } primary: {
            if isReview || model.stage == .reading { logButton }
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

    private var entryRows: some View {
        VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
                LHSectionHeader("Log again")
                LHRowGroup {
                    ForEach(Array(LogV2Sample.recents.prefix(2).enumerated()), id: \.element.id) { i, r in
                        if i > 0 { LHDivider(leadingInset: 72) }
                        LHRow.Browse(title: r.title, value: LHFormat.hours(r.hours), action: { model.note = r.note }) {
                            LHThumb.row(model.stage(for: i == 0 ? LogV2Sample.pine.id : LogV2Sample.oak.id), lit: false)
                        }
                    }
                }
            }
            LHRowGroup {
                LHRow.Browse(title: "Start a timer", meta: "Log it when you stop", systemImage: "timer") { model.startTimer() }
                    .accessibilityIdentifier("logv2.startTimer")
            }
        }
        .padding(.top, 8)
    }

    // MARK: The record card (white, on the page)

    private var recordCard: some View {
        VStack(spacing: 20) {
            if variant == .beam { beamComposition } else { objectComposition }
        }
        .padding(.horizontal, LHMetrics.cardPadding)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
        .overlay {
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous).strokeBorder(colors.border, lineWidth: LHMetrics.hairline)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("logv2.card")
    }

    private var house: some View {
        LHHouseReadback(before: model.stageBefore, after: model.stageAfter, crosses: model.crossesStage,
                        celebrating: model.celebrating, size: variant == .beam ? 120 : 108)
            .opacity(model.rentalId == nil ? 0.35 : 1)
    }

    private var sentence: some View {
        Text(model.readBack.isEmpty ? "Your details." : model.readBack)
            .font(LHFont.fraunces(.title))
            .foregroundStyle(colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("logv2.readback")
    }

    /// "Pine Cabin · 59 → 60 of 100 hours" and, when a stage is crossed, what it builds.
    private var progressLine: String? {
        guard let name = model.rentalName, !hoursNeeded else { return nil }
        let a = Int(model.hoursBefore.rounded(.down)), b = Int(model.hoursAfter.rounded(.down))
        var text = "\(name) · \(a) → \(b) of \(Int(model.goal))h"
        if model.crossesStage {
            switch model.stageAfter {
            case .frame70: text += ". More framing goes up."
            case .framing: text += ". The frame is finished."
            case .half: text += ". The roof goes on."
            case .complete: text += ". The house is finished."
            default: break
            }
        }
        return text
    }

    private var hoursNeeded: Bool { model.sources[.hours] == .needed }

    private var hoursPrompt: some View {
        HStack(spacing: 8) {
            Text("How long did it take?").font(.headline).foregroundStyle(colors.textPrimary)
            LHTag("Needs you", tone: .caution)
        }
        .accessibilityElement(children: .combine)
    }

    private var timerNoteLine: String? {
        guard model.fromTimer, let h = model.hours else { return nil }
        return "From the timer: \(LHFormat.hours(h)), not rounded."
    }

    // A1 · Beam: house, sentence, then the giant duration over the beam.
    private var beamComposition: some View {
        VStack(spacing: 12) {
            sentence.multilineTextAlignment(.center)
            if model.sources[.rental] == .needed { rentalQuestion }
            VStack(spacing: 2) {
                if hoursNeeded { hoursPrompt }
                LHDurationNumerals(hours: hoursNeeded ? nil : model.hours, size: 84)
                LHDurationBeam(hours: model.hours ?? 0) { model.setHours($0) }
                    .padding(.horizontal, -LHMetrics.cardPadding)
                if hoursNeeded {
                    Text("Drag the beam. It snaps to 15 minutes.").font(.footnote).foregroundStyle(colors.textSecondary)
                } else if let t = timerNoteLine {
                    Text(t).font(.footnote).foregroundStyle(colors.textSecondary)
                }
            }
            HStack(spacing: 12) {
                house
                if let p = progressLine {
                    Text(p).font(.subheadline).foregroundStyle(colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            detailsLine
        }
        .frame(maxWidth: .infinity)
    }

    // A2 · Object: house and sentence side by side, then the blueprint dial.
    private var objectComposition: some View {
        VStack(spacing: 14) {
            let layout = ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
            layout {
                house
                VStack(alignment: .leading, spacing: 6) {
                    sentence
                    if let p = progressLine {
                        Text(p).font(.subheadline).foregroundStyle(colors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.sources[.rental] == .needed { rentalQuestion }
            if hoursNeeded { hoursPrompt }
            LHDurationDial(hours: model.hours ?? 0, isSet: !hoursNeeded, side: ax ? 220 : 236) { model.setHours($0) }
            if let t = timerNoteLine {
                Text(t).font(.footnote).foregroundStyle(colors.textSecondary)
            }
            detailsLine
        }
        .frame(maxWidth: .infinity)
    }

    // The one open question when the rental is unknown: pick a house.
    private var rentalQuestion: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Which rental?").font(.headline).foregroundStyle(colors.textPrimary)
                LHTag("Needs you", tone: .caution)
            }
            LHFlowLayout(spacing: 12) {
                ForEach(model.properties, id: \.id) { p in
                    Button { withAnimation(AppAnimation.flow) { model.setRental(p.id) } } label: {
                        VStack(spacing: 4) {
                            LHThumb.header(model.stage(for: p.id), lit: false)
                            Text(p.name).font(.footnote.weight(.semibold)).foregroundStyle(colors.textPrimary)
                                .multilineTextAlignment(.center).frame(width: 92)
                        }
                        .padding(8)
                        .frame(minWidth: 100, minHeight: 100)
                        .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                    }
                    .buttonStyle(LHButton.press)
                    .accessibilityLabel(p.name)
                }
                if model.isFree {
                    VStack(spacing: 4) {
                        Image(systemName: "lock.fill").font(.title3).foregroundStyle(colors.textSecondary).frame(height: 56)
                        Text("Add a rental").font(.footnote.weight(.semibold)).foregroundStyle(colors.action)
                    }
                    .padding(8).frame(minWidth: 100, minHeight: 100)
                    .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                    .accessibilityHint("Opens Pro")
                }
            }
            if model.isFree {
                Text("Free covers one rental. Your hours here stay free.").font(.footnote).foregroundStyle(colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("logv2.rentalQuestion")
    }

    // Work · Who · Day (+ Rental when known) as quiet menus, and the assumptions footnote.
    private var detailsLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            LHDivider().padding(.bottom, 4)
            LHFlowLayout(spacing: 16) {
                if model.rentalId != nil && model.sources[.rental] != .needed {
                    menu(model.rentalName ?? "", icon: "house") {
                        ForEach(model.properties, id: \.id) { p in Button(p.name) { model.setRental(p.id) } }
                        if model.isFree {
                            Button { } label: { Label("Add a rental · Pro", systemImage: "lock.fill") }
                        }
                    }
                }
                menu(model.work?.inboxLabel ?? "Work", icon: "wrench.and.screwdriver") {
                    ForEach(ActivityCategory.allCases.filter(\.countsForREPS), id: \.self) { c in Button(c.inboxLabel) { model.setWork(c) } }
                }
                if model.spouseTracking {
                    menu(model.who == .spouse ? "Your spouse" : "You", icon: "person") {
                        Button("You") { model.setWho(.selfParticipant) }
                        Button("Your spouse") { model.setWho(.spouse) }
                    }
                }
                menu(LogV2Format.day(model.day), icon: "calendar") {
                    Button("Today") { model.setDay(LogV2Sample.now) }
                    Button("Yesterday") { model.setDay(Calendar.current.date(byAdding: .day, value: -1, to: LogV2Sample.now)!) }
                }
            }
            if let a = assumedLine {
                Text(a).font(.footnote).foregroundStyle(colors.textSecondary).accessibilityIdentifier("logv2.assumed")
            }
            if model.isFree {
                Text("Free covers one rental. Your hours here stay free.")
                    .font(.footnote).foregroundStyle(colors.textSecondary)
                    .accessibilityIdentifier("logv2.freeLine")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func menu<C: View>(_ title: String, icon: String, @ViewBuilder items: () -> C) -> some View {
        Menu { items() } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.action)
            .frame(minHeight: LHMetrics.minTap)
        }
    }

    private var assumedLine: String? {
        var parts: [String] = []
        for f in [LogV2Field.rental, .work, .who, .day] where model.fieldsShown.contains(f) {
            guard case .assumed(let why) = model.sources[f] ?? .needed, let v = model.value(f) else { continue }
            if why == "From the timer" { continue }
            parts.append(why.isEmpty ? v : "\(v) (\(why.lowercased()))")
        }
        guard !parts.isEmpty else { return nil }
        let lead = model.stage == .manual ? "Filled in for you" : (model.fromTimer ? "Not from the timer" : "Not in your note")
        return "\(lead): \(parts.joined(separator: ", "))."
    }

    private var logButton: some View {
        Button { model.log() } label: {
            Text(logLabel).contentTransition(.numericText())
        }
        .buttonStyle(LHButton.primaryGlass)
        .disabled(!model.canLog && !model.celebrating)
        .allowsHitTesting(!model.celebrating)
        .accessibilityIdentifier("logv2.log")
    }

    private var logLabel: String {
        if model.celebrating { return "Logged \(LHFormat.hours(model.hours))" }
        if model.canLog { return "Log \(LHFormat.hours(model.hours))" }
        if model.sources[.rental] == .needed { return "Pick a rental to log" }
        if hoursNeeded { return "Set the time to log" }
        return "Log it"
    }

    // MARK: Listening (B's Say it screen)

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
                .font(LHFont.fraunces(.title))
                .foregroundStyle(colors.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
                .accessibilityIdentifier("logv2.transcript")
                HStack(spacing: 12) {
                    LHLevelMeter(level: model.level, tint: colors.action)
                    Text("Listening").font(.subheadline.weight(.semibold)).foregroundStyle(colors.action)
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

    // MARK: Timer (variant-shaped face) and its note step

    private var elapsedNow: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let end = model.timerFrozen ? LogV2Sample.now : ctx.date
            let h = max(0, end.timeIntervalSince(model.timerStart)) / 3600
            timerFace(hours: h, seconds: Int(end.timeIntervalSince(model.timerStart)) % 60)
        }
    }

    @ViewBuilder private func timerFace(hours h: Double, seconds: Int) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(colors.positive).frame(width: 8, height: 8).accessibilityHidden(true)
                Text("Management at Pine Cabin").font(.headline).foregroundStyle(colors.textPrimary)
            }
            if variant == .beam {
                LHThumb(stage: model.stage(for: LogV2Sample.pine.id), lit: false, size: 120)
                LHDurationNumerals(hours: (h * 60).rounded(.down) / 60, size: 84)
                LHDurationBeam(hours: h, interactive: false).padding(.horizontal, -LHMetrics.cardPadding)
            } else {
                LHDurationDial(hours: (h * 60).rounded(.down) / 60, interactive: false, side: ax ? 220 : 260)
            }
            Text("Started \(model.timerStart.formatted(date: .omitted, time: .shortened)) · \(String(format: "%02d", seconds))s")
                .font(.subheadline).foregroundStyle(colors.textSecondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, LHMetrics.cardPadding)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
        .accessibilityIdentifier("logv2.timer.face")
    }

    private var timer: some View {
        LogV2PageSheet("Timer", subtitle: "Keeps running if you close this") {
            elapsedNow
            Text("You'll see it on your Lock Screen.")
                .font(.footnote).foregroundStyle(colors.textSecondary).frame(maxWidth: .infinity)
        } primary: {
            Button("Stop and log") { model.stopTimer() }
                .buttonStyle(LHButton.primaryGlass)
                .accessibilityIdentifier("logv2.timer.stop")
        } secondary: {
            Button("Discard timer") {}.buttonStyle(LHButton.destructiveTertiary)
        }
    }

    private var timerNote: some View {
        LogV2PageSheet("What did you do?", subtitle: model.timerSummary) {
            LHCaptureField(placeholder: "Add a few words (optional)", text: $model.note, minHeight: 104,
                           onPage: true, prominentMic: true, focus: $focused, onMic: {})
            Text("The timer has the rental, the time and the day.")
                .font(.footnote).foregroundStyle(colors.textSecondary)
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
#endif
