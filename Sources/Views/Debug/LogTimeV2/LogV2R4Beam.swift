import SwiftUI

#if DEBUG
// MARK: - Log time v2, round 4: A1 Beam (owner's pick), after the round-3 critique
//
//   -LHLogV2 A -LHLogV2Variant beam      (round 3's Beam: -LHLogV2Variant beamR3; Object: object)
//
// What changed from round 3:
//   1. The ruler is centred under the numerals, the card's full inner width, clipped to the card;
//      the reading line spans ticks and beam only, so no label sits under it. 30m · 1h · 2h · 4h
//      presets (LHChip) sit under the ruler, as Opal has them.
//   2. The note is shown once. While typing it is the field; when the note is done (keyboard Done,
//      focus leaves, or voice Done) the field grows into the record card and the note becomes the
//      Fraunces sentence (tap it to edit; the card shrinks back into the field).
//   3. The field → card change is one matched move of the white surface (no crossfade over rows).
//   4. The house moment: after Log the rental's house steps forward to ~70% of the width with the
//      windows lighting (0.40) and, when this log crosses a stage, the next stage fading in
//      (stageFade). It holds 1.9 s, then the sheet closes and the toast shows. Houses use the
//      production Rentals tile recipe (RentalTileHouse: night exposure + backlight in dark).
//   5. "Which rental?" collapses the duration to its numerals, so nothing hides under the footer;
//      the free-plan line sits under the sentence.

struct LogV2SheetR4Beam: View {
    @ObservedObject var model: LogV2Model
    @FocusState private var focused: Bool
    @Namespace private var ns
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
            case .listen: LogV2SheetR3(model: model, variant: .beam).transition(push)
            case .timer: LogV2SheetR3(model: model, variant: .beam).transition(push)
            case .note: LogV2SheetR3(model: model, variant: .beam).transition(push)
            }
            if model.celebrating { houseMoment.transition(.opacity) }
        }
        .animation(reduceMotion ? AppAnimation.reduced : AppAnimation.flow, value: step)
        .animation(reduceMotion ? AppAnimation.reduced : AppAnimation.flow, value: model.celebrating)
        .background(colors.background)
    }

    private var push: AnyTransition { reduceMotion ? .opacity : .push(from: model.forward ? .trailing : .leading) }

    private var showsCard: Bool { [.review, .closing, .logged, .manual].contains(model.stage) }
    private var rentalNeeded: Bool { model.sources[.rental] == .needed }
    private var hoursNeeded: Bool { model.sources[.hours] == .needed }

    // MARK: The one screen

    private var line: some View {
        LogV2PageSheet("Log time", subtitle: LogV2Format.subtitle) {
            if showsCard {
                recordCard
                    .matchedGeometryEffect(id: "surface", in: ns)
            } else {
                LHCaptureField(placeholder: "What did you do?", text: $model.note, onPage: true,
                               prominentMic: true, focus: $focused) { model.startListening() }
                    .matchedGeometryEffect(id: "surface", in: ns)
                    .onChange(of: model.note) { _, text in
                        // Return on the keyboard finishes the note.
                        if text.contains("\n") {
                            model.note = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                            focused = false
                        }
                    }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused, model.stage == .entry, model.note.trimmingCharacters(in: .whitespaces).count >= 6 {
                            model.submitNow()
                        }
                    }
                    .onAppear { if model.wantsKeyboard { focused = true } }
                    .onChange(of: model.wantsKeyboard) { _, on in focused = on }
                    .submitLabel(.done)
                if model.stage == .reading {
                    LogV2ReadingLine()
                } else {
                    if model.note.isEmpty {
                        Text("Try \u{201C}fixed the sink at Pine Cabin, 1 hour\u{201D}")
                            .font(.footnote).foregroundStyle(colors.textSecondary).padding(.horizontal, 4)
                    }
                    entryRows
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
        } primary: {
            if showsCard { logButton }
            else if model.note.trimmingCharacters(in: .whitespaces).count >= 3 && model.stage == .entry {
                Button("Next") { focused = false; model.submitNow() }
                    .buttonStyle(LHButton.primaryGlass)
                    .accessibilityIdentifier("logv2.next")
            }
        } secondary: {
            if model.stage == .entry && model.note.isEmpty {
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
                        LHRow.Browse(title: r.title, value: LHFormat.hours(r.hours), action: {
                            model.note = r.note
                            model.submitNow()
                        }) {
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

    // MARK: The record card

    private var recordCard: some View {
        VStack(spacing: 8) {
            sentence
            if let a = assumedLine {
                Text(a).font(.footnote).foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                    .accessibilityIdentifier("logv2.assumed")
            }
            if model.isFree {
                Text("Free covers one rental. Your hours here stay free.")
                    .font(.footnote).foregroundStyle(colors.textSecondary).multilineTextAlignment(.center)
                    .accessibilityIdentifier("logv2.freeLine")
            }
            if rentalNeeded { rentalQuestion }
            durationBlock
            houseRow
            detailsLine
        }
        .padding(.horizontal, LHMetrics.cardPadding)
        .padding(.vertical, LHMetrics.cardPadding)
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

    /// The note, once: read back in Fraunces. Tap to edit (the card shrinks back into the field).
    private var sentence: some View {
        Button {
            model.forward = false
            withAnimation(reduceMotion ? AppAnimation.reduced : AppAnimation.flow) { model.stage = .entry }
            focused = true
        } label: {
            (Text(model.readBack.isEmpty ? "Your details." : model.readBack)
                .font(LHFont.fraunces(.title))
                .tracking(-0.3)
                .foregroundStyle(colors.textPrimary)
             + Text("  ") + Text(Image(systemName: "pencil")).font(.title3).foregroundStyle(colors.textSecondary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(LHButton.press)
        .accessibilityLabel(model.readBack)
        .accessibilityHint("Edit your note")
        .accessibilityIdentifier("logv2.readback")
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

    // Numerals, ruler, presets. Collapsed to the numerals while "Which rental?" is open.
    @ViewBuilder private var durationBlock: some View {
        VStack(spacing: 4) {
            if hoursNeeded && !rentalNeeded {
                HStack(spacing: 8) {
                    Text("How long did it take?").font(.headline).foregroundStyle(colors.textPrimary)
                    LHTag("Needs you", tone: .caution)
                }
                .accessibilityElement(children: .combine)
            }
            // Fraunces at 84 carries a tall line box; trim it so the numeral sits on the ruler (D4).
            LHDurationNumerals(hours: hoursNeeded ? nil : model.hours, size: rentalNeeded ? 56 : 84)
                .padding(.vertical, rentalNeeded ? -10 : -14)
            if !rentalNeeded {
                LHDurationBeam(hours: model.hours ?? 0) { model.setHours($0) }
                HStack(spacing: 8) {
                    ForEach([0.5, 1, 2, 4], id: \.self) { h in
                        LHChip(LHFormat.hours(h), isSelected: model.hours == h && !hoursNeeded) {
                            withAnimation(AppAnimation.standard) { model.setHours(h) }
                        }
                    }
                }
                .accessibilityIdentifier("logv2.presets")
                if model.fromTimer, let h = model.hours {
                    Text("From the timer: \(LHFormat.hours(h)), not rounded.").font(.footnote).foregroundStyle(colors.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

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

    @ViewBuilder private var houseRow: some View {
        if model.rentalId != nil && !rentalNeeded {
            let layout = ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                LogV2House(model: model, width: 132)
                    .matchedGeometryEffect(id: "house", in: ns, isSource: !model.celebrating)
                if let p = progressLine {
                    Text(p).font(.subheadline).foregroundStyle(colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var rentalQuestion: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Which rental?").font(.headline).foregroundStyle(colors.textPrimary)
                LHTag("Needs you", tone: .caution)
            }
            HStack(spacing: 10) {
                ForEach(model.properties, id: \.id) { p in
                    Button { withAnimation(AppAnimation.flow) { model.setRental(p.id) } } label: {
                        VStack(spacing: 4) {
                            RentalTileHouse(stage: model.stage(for: p.id), lit: false).frame(width: 72)
                            Text(p.name).font(.footnote.weight(.semibold)).foregroundStyle(colors.textPrimary)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, minHeight: 104)
                        .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                    }
                    .buttonStyle(LHButton.press)
                    .accessibilityLabel(p.name)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("logv2.rentalQuestion")
    }

    private var detailsLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            LHDivider().padding(.bottom, 4)
            LHFlowLayout(spacing: 16) {
                if model.rentalId != nil && !rentalNeeded {
                    menu(model.rentalName ?? "") {
                        ForEach(model.properties, id: \.id) { p in Button(p.name) { model.setRental(p.id) } }
                        if model.isFree { Button { } label: { Label("Add a rental · Pro", systemImage: "lock.fill") } }
                    }
                }
                menu(model.work?.inboxLabel ?? "Work") {
                    ForEach(ActivityCategory.allCases.filter(\.countsForREPS), id: \.self) { c in Button(c.inboxLabel) { model.setWork(c) } }
                }
                if model.spouseTracking {
                    menu(model.who == .spouse ? "Your spouse" : "You") {
                        Button("You") { model.setWho(.selfParticipant) }
                        Button("Your spouse") { model.setWho(.spouse) }
                    }
                }
                menu(LogV2Format.day(model.day)) {
                    Button("Today") { model.setDay(LogV2Sample.now) }
                    Button("Yesterday") { model.setDay(Calendar.current.date(byAdding: .day, value: -1, to: LogV2Sample.now)!) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func menu<C: View>(_ title: String, @ViewBuilder items: () -> C) -> some View {
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

    private var logButton: some View {
        Button { model.log() } label: { Text(logLabel).contentTransition(.numericText()) }
            .buttonStyle(LHButton.primaryGlass)
            .disabled(!model.canLog && !model.celebrating)
            .allowsHitTesting(!model.celebrating)
            .accessibilityIdentifier("logv2.log")
    }

    private var logLabel: String {
        if model.celebrating { return "Logged \(LHFormat.hours(model.hours))" }
        if model.canLog { return "Log \(LHFormat.hours(model.hours))" }
        if rentalNeeded { return "Pick a rental to log" }
        if hoursNeeded { return "Set the time to log" }
        return "Log it"
    }

    // MARK: The house moment (after Log, before the toast)

    private var houseMoment: some View {
        GeometryReader { geo in
            VStack(spacing: 16) {
                Spacer(minLength: 0)
                LogV2House(model: model, width: min(geo.size.width * 0.78, 340))
                    .matchedGeometryEffect(id: "house", in: ns, isSource: model.celebrating)
                VStack(spacing: 6) {
                    Text("Logged \(LHFormat.hours(model.hours)) at \(model.rentalName ?? "").")
                        .font(LHFont.fraunces(.title))
                        .foregroundStyle(colors.textPrimary)
                    if let p = model.crossesStage ? stageLine : nil {
                        Text(p).font(.body).foregroundStyle(colors.textSecondary)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, LHMetrics.gutter)
                Spacer(minLength: 0)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colors.background)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("logv2.houseMoment")
    }

    private var stageLine: String? {
        switch model.stageAfter {
        case .frame70: return "More framing goes up."
        case .framing: return "The frame is finished."
        case .half: return "The roof goes on."
        case .complete: return "The house is finished."
        default: return nil
        }
    }
}

/// The rental's house for the review and the moment: the production Rentals tile house
/// (RentalTileHouse: transparent still, night exposure and backlight in dark), the next stage
/// drafted behind it when this log crosses one, and the beat on Log (windows 0.40; stageFade when
/// the stage changes).
struct LogV2House: View {
    @ObservedObject var model: LogV2Model
    var width: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: CraftStage { model.celebrating && model.crossesStage ? model.stageAfter : model.stageBefore }

    var body: some View {
        ZStack {
            if model.crossesStage && !model.celebrating {
                RentalTileHouse(stage: model.stageAfter, lit: false)
                    .colorMultiply(AdaptiveColors(colorScheme: colorScheme).drafting)
                    .opacity(0.6)
                    .accessibilityHidden(true)
            }
            ZStack {
                RentalTileHouse(stage: shown, lit: false)
                RentalTileHouse(stage: shown, lit: true)
                    .opacity(model.celebrating ? 1 : 0)
                    .animation(reduceMotion ? AppAnimation.windowsReduced : AppAnimation.windows.delay(0.25), value: model.celebrating)
            }
            .id(shown)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
        }
        .frame(width: width)
        .animation(reduceMotion ? AppAnimation.reduced : AppAnimation.stageFade, value: shown)
        .accessibilityElement()
        .accessibilityLabel(CraftHouseView.accessibilityLabel(stage: shown, lit: model.celebrating))
        .accessibilityIdentifier("logv2.house")
    }
}
#endif
