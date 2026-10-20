import SwiftUI

// §3 "+" Log time, voice, pickers and the timer.

enum LogState: String {
    case empty, quick, notCounted, typed, filled, keyboard, invalid, voiceFirst, listening, voiceFilled, voiceDenied, voiceDemo, review
}

struct LogTimeSheet: View {
    var state: LogState = .empty
    var spouse = true
    var picker: PickerKind? = nil
    var limitPicker = false

    enum PickerKind: String, Identifiable { case category, property; var id: String { rawValue } }

    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dynamicTypeSize) private var dts
    @State private var note = ""
    @State private var hours: Double = 0
    @State private var property: S2Property?
    @State private var cat: S2Cat?
    @State private var who = 0
    @State private var flash = 0.0
    @State private var filledFromNote = false
    @State private var rememberedCat = false
    /// What filled the fields: "your note" today; later "a receipt", "Mike's visit" (smart layer slot).
    var fillSource: String = "your note"
    @State private var listening = false
    @State private var showPicker: PickerKind?
    @FocusState private var focused: Bool

    private let sample = "Fixed the sink at Pine Cabin, 1 hour"
    private var valid: Bool { property != nil && hours > 0 }
    private var isReview: Bool { state == .review }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                noteField
                if state == .voiceFirst { voiceTip }
                if state == .voiceDenied { deniedLine }
                if filledFromNote {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles").foregroundStyle(LHB.timberInk)
                        Text("Filled from \(fillSource) ·").foregroundStyle(LHB.textSecondary)
                        Button("Undo") {}.foregroundStyle(LHB.action).fontWeight(.semibold)
                    }
                    .font(.footnote)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
                }
                if isReview {
                    Text("Timer ran 1h 14m").font(.footnote).foregroundStyle(LHB.textSecondary).padding(.horizontal, 4)
                }
                HoursStepper(hours: $hours, flash: flash, label: "How long?", chips: true)
                rows
                if dts.isAccessibilitySize { footer.padding(.horizontal, -20) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(LHB.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { if !dts.isAccessibilitySize { footer } }
        .sheet(item: $showPicker) { k in
            Group {
                switch k {
                case .category: CategoryPicker(selected: cat ?? .repairs)
                case .property: PropertyPicker(selected: property?.id ?? S2Data.pine.id, atLimit: limitPicker)
                }
            }
            .modifier(TypeSizeOverride())
            .presentationDetents(k == .category ? [.large] : [.medium, .large])
            .presentationBackground(LHB.canvas)
        }
        .onAppear(perform: setUp)
    }

    private func setUp() {
        // Speed defaults (≤4 taps for "2h at my only property": +, 2h, Log).
        hours = 1; property = S2Data.pine; cat = .repairs; rememberedCat = true
        switch state {
        case .quick:
            hours = 2
        case .notCounted:
            note = "Call with the lender about refinancing Pine Cabin"; cat = .financing; rememberedCat = false
        case .typed:
            note = sample
        case .filled, .voiceFilled:
            note = sample; property = S2Data.pine; cat = .repairs; hours = 1; filledFromNote = true
        case .keyboard:
            note = "Met the HVAC tech at Oak Street, walked through the duplex and"
            property = S2Data.oak; hours = 1.5
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true }
        case .invalid:
            // A user with several rentals: nothing to preselect.
            note = "Tenant call about the lease renewal"; hours = 0.5; cat = .management; property = nil; rememberedCat = false
        case .listening:
            listening = true; note = "Fixed the sink at Pine"
        case .voiceDemo:
            property = nil; cat = nil; hours = 0; rememberedCat = false
            runVoiceDemo()
        case .review:
            property = S2Data.pine; cat = .repairs; hours = 1.25; rememberedCat = false
        default: break
        }
        if let picker { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showPicker = picker } }
    }

    /// Scripted dictation for the recording: the words type in, stop, then the fields fill.
    private func runVoiceDemo() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            listening = true
            for w in sample.split(separator: " ") {
                try? await Task.sleep(nanoseconds: 300_000_000)
                note += (note.isEmpty ? "" : " ") + w
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            listening = false
            try? await Task.sleep(nanoseconds: 600_000_000)
            fill()
        }
    }

    private func fill() {
        withAnimation(reduce ? .easeOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 1)) {
            property = S2Data.pine; cat = .repairs; hours = 1; filledFromNote = true
        }
        withAnimation(.easeOut(duration: 0.3)) { flash = 0.16 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.easeIn(duration: 0.3)) { flash = 0 } }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isReview ? "Timer · Sun, Oct 19" : "Today · Sun, Oct 19").s2Section()
                Text(isReview ? "Log the timer" : "Log time").font(.title2.weight(.semibold)).foregroundStyle(LHB.textPrimary)
            }
            Spacer()
            GlassClose()
        }
    }

    // MARK: Note

    private var noteField: some View {
        ZStack(alignment: .topLeading) {
            if note.isEmpty {
                Text(isReview ? "What did you work on?" : "What did you do? Try “fixed the sink at Pine Cabin, 1 hour”")
                    .font(.body).foregroundStyle(LHB.textTertiary)
                    .padding(.horizontal, 16).padding(.vertical, 14).padding(.trailing, 40)
                    .allowsHitTesting(false)
            }
            TextField("", text: $note, axis: .vertical)
                .lineLimit(3...6)
                .font(.body)
                .foregroundStyle(LHB.textPrimary)
                .focused($focused)
                .padding(.horizontal, 16).padding(.vertical, 14).padding(.trailing, 44)
                .accessibilityLabel("Note")
                .accessibilityIdentifier("log.note")
        }
        .frame(minHeight: 96, alignment: .topLeading)
        .background(LHB.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(focused || listening ? LHB.action.opacity(0.5) : LHB.border, lineWidth: 1))
        .overlay(alignment: .bottomTrailing) { mic.padding(10) }
        .overlay(alignment: .bottomLeading) {
            if listening {
                Text("Listening… tap to stop").font(.footnote).foregroundStyle(LHB.textSecondary)
                    .padding(.leading, 16).padding(.bottom, 14)
            }
        }
    }

    private var mic: some View {
        Button { listening.toggle() } label: {
            ZStack {
                if listening {
                    MicLevelRing().frame(width: 46, height: 46)
                    RoundedRectangle(cornerRadius: 3).fill(LHB.onAction).frame(width: 12, height: 12)
                } else {
                    Image(systemName: "mic.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(LHB.onAction)
                }
            }
            .frame(width: 36, height: 36)
            .background(Circle().fill(LHB.action))
            .opacity(state == .voiceDenied ? 0.4 : 1)
        }
        .buttonStyle(S2Press())
        .frame(width: 44, height: 44)
        .accessibilityLabel(listening ? "Stop listening" : "Talk instead of type")
        .accessibilityIdentifier("log.mic")
    }

    private var voiceTip: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform").font(.system(size: 18, weight: .semibold)).foregroundStyle(LHB.action)
                .frame(width: 36, height: 36).background(Circle().fill(LHB.actionSurface))
            VStack(alignment: .leading, spacing: 8) {
                Text("Talk like you’d tell a friend. We’ll fill the rest.").font(.subheadline.weight(.semibold)).foregroundStyle(LHB.textPrimary)
                Button("Start talking") {}.buttonStyle(S2Tinted())
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .s2Card(16)
    }

    private var deniedLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Turn on the microphone in Settings to talk instead of type.").font(.subheadline).foregroundStyle(LHB.textSecondary)
            Button("Open Settings") {}.font(.subheadline.weight(.semibold)).foregroundStyle(LHB.action)
        }
        .padding(.horizontal, 4)
    }

    // MARK: Rows

    private var rows: some View {
        VStack(spacing: 0) {
            valueRow("Property", flashOn: property != nil) {
                Button { showPicker = .property } label: {
                    HStack(spacing: 8) {
                        if let property { PropertySeal(property, size: 24); Text(property.name).foregroundStyle(LHB.textPrimary) }
                        else { Text("Choose").foregroundStyle(state == .invalid ? LHB.caution : LHB.action) }
                        Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).foregroundStyle(LHB.textTertiary)
                    }
                }
                .accessibilityIdentifier("log.property")
            }
            if spouse {
                InsetDivider()
                valueRow("Who", flashOn: false) { WhoPicker(who: $who) }
            }
            InsetDivider()
            valueRow("Category", flashOn: cat != nil) {
                Button { showPicker = .category } label: {
                    HStack(spacing: 8) {
                        if let cat {
                            ToolTile(cat: cat, size: 24)
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(cat.label).foregroundStyle(LHB.textPrimary)
                                if rememberedCat && !filledFromNote { Text("Last used").font(.caption).foregroundStyle(LHB.textSecondary) }
                            }
                        }
                        else { Text("Choose").foregroundStyle(LHB.action) }
                        Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).foregroundStyle(LHB.textTertiary)
                    }
                }
                .accessibilityIdentifier("log.category")
            }
            if let cat, !cat.counts {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("\(cat.label) doesn’t count toward your hours or the house.")
                }
                .font(.footnote).foregroundStyle(LHB.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.bottom, 10)
            }
            InsetDivider()
            valueRow("Date", flashOn: false) { Text("Today, Oct 19").foregroundStyle(LHB.textPrimary) }
            InsetDivider()
            Button {} label: {
                HStack(spacing: 10) {
                    Image(systemName: "camera").foregroundStyle(LHB.action)
                    Text("Add a receipt photo").foregroundStyle(LHB.action)
                    Spacer()
                }
                .padding(.horizontal, 16).frame(minHeight: 52)
            }
        }
        .font(.body)
        .background(LHB.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func valueRow<V: View>(_ label: String, flashOn: Bool, @ViewBuilder value: () -> V) -> some View {
        let stack = dts.isAccessibilitySize
        let layout = stack ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout())
        return layout {
            Text(label).foregroundStyle(stack ? LHB.textSecondary : LHB.textPrimary)
            if !stack { Spacer(minLength: 12) }
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, stack ? 10 : 0).frame(minHeight: 52)
        .background(LHB.timber.opacity(flashOn ? flash : 0))
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 8) {
            if state == .invalid {
                Text("Pick a property to log this.").font(.footnote).foregroundStyle(LHB.caution)
            }
            HStack(spacing: 12) {
                Button { } label: {
                    Text(hours > 0 ? "Log \(hm(hours))" : "Log time").contentTransition(.numericText(value: hours))
                }
                .buttonStyle(S2Primary())
                .disabled(!valid)
                .accessibilityIdentifier("log.save")
                if focused {
                    Button("Done") { focused = false }.font(.body.weight(.semibold)).foregroundStyle(LHB.action).frame(minHeight: 44).fixedSize()
                }
            }
            if isReview {
                Button("Discard") {}.font(.body).foregroundStyle(LHB.destructive).frame(minHeight: 36)
            } else if !focused {
                Button("Start a timer instead") {}.font(.body).foregroundStyle(LHB.action).frame(minHeight: 36)
            }
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        .background(LHB.canvas.ignoresSafeArea())
        .overlay(alignment: .top) {
            LinearGradient(colors: [LHB.canvas.opacity(0), LHB.canvas], startPoint: .top, endPoint: .bottom)
                .frame(height: 20).offset(y: -20).allowsHitTesting(false)
        }
    }
}

/// The confirm sheet's hours stepper (15-minute steps).
struct HoursStepper: View {
    @Binding var hours: Double
    var flash = 0.0
    var label = "How long?"
    var chips = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dynamicTypeSize) private var dts
    private let presets: [(String, Double)] = [("30m", 0.5), ("1h", 1), ("2h", 2), ("4h", 4)]

    var body: some View {
        let m = Int((hours * 60).rounded())
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(LHB.textSecondary).padding(.horizontal, 4)
            HStack(spacing: 12) {
                step("minus") { hours = max(0, hours - 0.25) }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(m / 60)").font(.system(size: 40, weight: .semibold, design: .rounded)).contentTransition(.numericText(value: Double(m / 60)))
                    Text("h").font(.title3).foregroundStyle(LHB.textSecondary)
                    Text(String(format: "%02d", m % 60)).font(.system(size: 40, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText(value: Double(m % 60))).padding(.leading, 6)
                    Text("m").font(.title3).foregroundStyle(LHB.textSecondary)
                }
                .monospacedDigit()
                .foregroundStyle(hours > 0 ? LHB.textPrimary : LHB.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hours").accessibilityValue(hm(hours))
                Spacer(minLength: 0)
                step("plus") { hours = min(24, hours + 0.25) }
            }
            .padding(16)

            .safeAreaInset(edge: .bottom, spacing: 0) {
                if chips {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: dts.isAccessibilitySize ? 2 : 4), spacing: 8) {
                        ForEach(presets, id: \.0) { p in
                            let on = abs(hours - p.1) < 0.01
                            Button { withAnimation(reduce ? nil : .spring(response: 0.28, dampingFraction: 0.9)) { hours = p.1 } } label: {
                                Text(p.0).font(.subheadline.weight(.semibold)).monospacedDigit()
                                    .lineLimit(1).fixedSize()
                                    .padding(.horizontal, 8)
                                    .foregroundStyle(on ? LHB.onAction : LHB.textPrimary)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(Capsule().fill(on ? LHB.action : LHB.tertiary))
                                    .overlay(Capsule().strokeBorder(on ? Color.clear : LHB.border, lineWidth: 0.5))
                            }
                            .buttonStyle(S2Press())
                            .accessibilityAddTraits(on ? .isSelected : [])
                            .accessibilityIdentifier("log.chip.\(p.0)")
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 14)
                }
            }
            .background(LHB.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(LHB.timber.opacity(flash), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LHB.timber.opacity(flash)).allowsHitTesting(false))
        }
    }

    private func step(_ s: String, _ act: @escaping () -> Void) -> some View {
        Button { withAnimation(reduce ? nil : .spring(response: 0.28, dampingFraction: 0.9)) { act() } } label: {
            Image(systemName: s).font(.system(size: 17, weight: .semibold)).foregroundStyle(LHB.textPrimary)
                .frame(width: 44, height: 44)
                .background(LHB.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(LHB.border, lineWidth: 0.5))
        }
        .buttonStyle(S2Press())
        .accessibilityLabel(s == "plus" ? "More time" : "Less time")
    }
}

struct WhoPicker: View {
    @Binding var who: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<2, id: \.self) { i in
                Button { withAnimation(.easeInOut(duration: 0.15)) { who = i } } label: {
                    Text(i == 0 ? "Me" : "Spouse").font(.subheadline.weight(.semibold))
                        .foregroundStyle(who == i ? LHB.onAction : LHB.textPrimary)
                        .padding(.horizontal, 16).frame(minHeight: 32)
                        .background(Capsule().fill(who == i ? LHB.action : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(LHB.tertiary))
        .overlay(Capsule().strokeBorder(LHB.border, lineWidth: 0.5))
    }
}

/// 2pt drafting ring that follows the input level; still in silence. Reduce Motion: still.
struct MicLevelRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        TimelineView(.animation(paused: reduce)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let level = reduce ? 0 : max(0, sin(t * 7) * 0.5 + sin(t * 3.1) * 0.5)
            Circle().strokeBorder(LHB.drafting, lineWidth: 2).scaleEffect(1 + level * 0.18)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Pickers

struct CategoryPicker: View {
    var selected: S2Cat = .repairs
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Kind of work").font(.title2.weight(.semibold)).foregroundStyle(LHB.textPrimary)
                    Spacer(); GlassClose()
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: dts.isAccessibilitySize ? 1 : 3), spacing: 12) {
                    ForEach(S2Cat.grid) { c in
                        let on = c == selected
                        VStack(spacing: 8) {
                            ToolTile(cat: c, size: 56)
                            Text(c.label).font(.subheadline.weight(.semibold)).foregroundStyle(LHB.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 104)
                        .background(LHB.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(on ? LHB.action : .clear, lineWidth: 2))
                        .overlay(alignment: .topTrailing) {
                            if on {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(LHB.onAction, LHB.action).padding(8)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    S2Header("Doesn’t count toward hours")
                    VStack(spacing: 0) {
                        ForEach(Array(S2Cat.more.enumerated()), id: \.element) { i, c in
                            HStack(spacing: 12) {
                                ToolTile(cat: c, size: 36)
                                Text(c.label).font(.body).foregroundStyle(LHB.textPrimary)
                                Spacer()
                                Text("Not counted").font(.footnote.weight(.semibold)).foregroundStyle(LHB.textSecondary)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(LHB.tertiary))
                            }
                            .padding(.horizontal, 16).frame(minHeight: 60)
                            .accessibilityElement(children: .combine)
                            if i < S2Cat.more.count - 1 { InsetDivider(leading: 64) }
                        }
                    }
                    .background(LHB.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text("Investor work. Log it for your records; it never counts toward the 750 or 500-hour tests or the house.")
                        .font(.footnote).foregroundStyle(LHB.textSecondary).padding(.horizontal, 4)
                }
            }
            .padding(20)
        }
        .background(LHB.canvas)
    }
}

struct PropertyPicker: View {
    var selected: String
    var atLimit = false
    var props: [S2Property] { atLimit ? [S2Data.pine] : [S2Data.pine, S2Data.oak, S2Data.long] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Which rental?").font(.title2.weight(.semibold)).foregroundStyle(LHB.textPrimary)
                    Spacer(); GlassClose()
                }
                VStack(spacing: 0) {
                    ForEach(props) { p in
                        HStack(spacing: 12) {
                            PropertySeal(p, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.body.weight(.semibold)).foregroundStyle(LHB.textPrimary).lineLimit(2)
                                Text(p.address).font(.subheadline).foregroundStyle(LHB.textSecondary).lineLimit(1)
                            }
                            Spacer()
                            if p.id == selected { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(LHB.action) }
                        }
                        .padding(.horizontal, 16).frame(minHeight: 60)
                        InsetDivider(leading: 60)
                    }
                    if atLimit {
                        LockedPreview(size: .row, line: "Free covers one rental.", keeps: "Pine Cabin keeps tracking. Nothing is lost.") {
                            HStack(spacing: 12) {
                                PropertySeal(monogram: "OS", size: 32, dashed: true)
                                Text("Oak Street Duplex").font(.body.weight(.semibold)).foregroundStyle(LHB.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 16).frame(minHeight: 60)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(LHB.action)
                                .frame(width: 32, height: 32).background(Circle().fill(LHB.actionSurface))
                            Text("Add a property").foregroundStyle(LHB.action)
                            Spacer()
                        }
                        .padding(.horizontal, 16).frame(minHeight: 60)
                    }
                }
                .background(LHB.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(20)
        }
        .background(LHB.canvas)
    }
}

// MARK: - Timer

enum TimerState: String { case idle, running }

struct TimerSheet: View {
    var state: TimerState = .idle
    @State private var start = Date().addingTimeInterval(-(1 * 3600 + 14 * 60 + 7))

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today · Sun, Oct 19").s2Section()
                        Text("Timer").font(.title2.weight(.semibold)).foregroundStyle(LHB.textPrimary)
                    }
                    Spacer(); GlassClose()
                }
                if state == .idle { idle } else { running }
            }
            .padding(20)
        }
        .background(LHB.canvas.ignoresSafeArea())
    }

    private var idle: some View {
        VStack(spacing: 28) {
            VStack(spacing: 0) {
                row("Property") { HStack(spacing: 8) { PropertySeal(S2Data.pine, size: 24); Text("Pine Cabin") } }
                InsetDivider()
                row("Category") { HStack(spacing: 8) { ToolTile(cat: .repairs, size: 24); Text("Repairs") } }
            }
            .background(LHB.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("0:00").roundedNumber(64).foregroundStyle(LHB.textTertiary).padding(.vertical, 24)
            Button("Start timer") {}.buttonStyle(S2Primary())
            Button("Log time instead") {}.foregroundStyle(LHB.action)
        }
    }

    private func row<V: View>(_ l: String, @ViewBuilder v: () -> V) -> some View {
        HStack { Text(l); Spacer(); v() }.foregroundStyle(LHB.textPrimary).padding(.horizontal, 16).frame(minHeight: 52)
    }

    private var running: some View {
        VStack(spacing: 16) {
            LiveTimerCard(start: start)
            Button("Discard") {}.foregroundStyle(LHB.destructive).frame(minHeight: 44)
            Text("Keeps running if you close this. You’ll see it on your Lock Screen.")
                .font(.subheadline).foregroundStyle(LHB.textSecondary).multilineTextAlignment(.center)
        }
    }
}

/// The Live Activity layout at full size, on theme-fixed blueprint.
struct LiveTimerCard: View {
    let start: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let s = Int(ctx.date.timeIntervalSince(start))
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    PropertySeal(monogram: "PC", palette: .timber, size: 24).environment(\.colorScheme, .dark)
                    Text("Pine Cabin").font(.headline).foregroundStyle(.white)
                    Spacer()
                    Text("LandlordHours").drafting()
                }
                Text(String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60))
                    .roundedNumber(64).foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.easeOut(duration: 0.2), value: s)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("Repairs · started 10:25").font(.subheadline).foregroundStyle(LHB.onHeroSecondary)
                Button("Stop") {}.buttonStyle(S2OnBlueprint())
            }
            .padding(20)
            .background(S2Paper(radius: 24))
            .accessibilityElement(children: .combine)
        }
    }
}
