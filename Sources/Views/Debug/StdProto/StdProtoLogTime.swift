import SwiftUI

#if DEBUG
// MARK: - Log time, IA pass (spec: AgentScratch 2026-10-23 logtime-ia/spec.md)
//
// Four tiers in four places: the note (intent) → three record rows (Rental · Kind of work · How long)
// → the context line under the title ("Today · Me ⌄", unfolds) → a receipt link; the pinned Log
// button states the record. The fill runs on a scripted backend so the timings are reproducible.
//
//   Presentation (Brian picked A, 2026-10-23): opaque .large sheet, system push-back and dim of Today;
//   Liquid Glass only on the pinned Log button and the keyboard. The glass-sheet variant B is dropped.
//   -LHStdState empty|typing|filled|missing|manual|tworentals|updated|timeout|context
//   -LHStdDemo logfill|logmid  scripted runs: type → rules fill → reading → refinement → Log;
//                              logmid taps Log mid-read (the read cancels)
//   -LHLogBackend normal|slow|timeout|rulesonly   the scripted reader's timing
//   -LHStdMotionLog            prints "STDMOTION <name> <t>" and "<name>.end dur=<s>" per motion

enum StdLogField: Int, CaseIterable { case rental, kind, hours }
/// Default (nothing said yet), from your note (✦), or yours (hand-set; a later fill never touches it).
enum StdLogSource { case standard, note, yours }

struct StdLogRecord: Equatable {
    var rental: String?
    var kind: ActivityCategory?
    var hours: Double
    var src: [StdLogField: StdLogSource]
    func source(_ f: StdLogField) -> StdLogSource { src[f] ?? .standard }
}

// MARK: - Scripted reader (rules at the first 0.6 s pause, then the "model")

struct StdLogReader {
    enum Backend: String { case normal, slow, timeout, rulesonly }
    struct Read { var rentals: [String] = []; var kind: ActivityCategory?; var hours: Double? }

    static let backend: Backend = {
        let args = ProcessInfo.processInfo.arguments
        guard let j = args.firstIndex(of: "-LHLogBackend"), args.indices.contains(j + 1) else { return .normal }
        return Backend(rawValue: args[j + 1]) ?? .normal
    }()
    /// The pause after the last keystroke before the rules run.
    static let pause = 0.6
    /// On-device model: 1–8 s in the field; the script picks 2.4 s (normal) or 7 s (slow).
    static var modelDelay: Double { backend == .slow ? 7.0 : 2.4 }
    static let timeout = 8.0
    static var hasModel: Bool { backend != .rulesonly }

    let rentals: [String]

    private func names(in note: String) -> [String] {
        let n = note.lowercased()
        return rentals.filter { r in
            let words = r.lowercased().split(separator: " ")
            return n.contains(r.lowercased()) || (words.count > 1 && n.contains(words.dropLast().joined(separator: " ")))
        }
    }

    /// Rules: names, literal hours, a short keyword list. Sure, fast, shallow.
    func rules(_ note: String) -> Read {
        let n = note.lowercased()
        var r = Read(rentals: names(in: note))
        let kinds: [(String, ActivityCategory)] = [("repair", .repairs), ("showed", .leasing), ("showing", .leasing),
                                                   ("lease", .leasing), ("mortgage", .bookkeeping), ("receipts", .bookkeeping)]
        r.kind = kinds.first { n.contains($0.0) }?.1
        if let m = n.range(of: #"(\d+(\.\d+)?)\s*(h\b|hr|hour)"#, options: .regularExpression) {
            r.hours = Double(n[m].prefix { $0.isNumber || $0 == "." })
        } else if n.contains("half an hour") {
            r.hours = 0.5
        } else if n.contains("an hour") {
            r.hours = 1
        }
        return r
    }

    /// The model: reads the whole sentence ("fixed the leaking tap" is repairs; "an hour and a half" is 1h 30m).
    func model(_ note: String) -> Read {
        let n = note.lowercased()
        var r = rules(note)
        let kinds: [(String, ActivityCategory)] = [("fixed", .repairs), ("leak", .repairs), ("plumb", .repairs),
                                                   ("clean", .management), ("tenant", .management), ("paperwork", .bookkeeping)]
        r.kind = r.kind ?? kinds.first { n.contains($0.0) }?.1
        if n.contains("hour and a half") { r.hours = 1.5 }
        return r
    }
}

// MARK: - The sheet

struct StdLogTimeSheet: View {
    enum Caption: Equatable { case recents, blank, reading, filled, updated, failure }
    enum Arrive { case fill, update }

    let seed: StdSeed
    let launch: StdProtoLaunch
    let onClose: () -> Void
    var onLog: (Double) -> Void = { _ in }

    @State private var note: String
    @State private var record: StdLogRecord
    @State private var reading: Set<StdLogField>
    @State private var caption: Caption
    @State private var arrive: [StdLogField: Arrive] = [:]
    @State private var washTick: [StdLogField: Int] = [:]
    @State private var washPeak: [StdLogField: Double] = [:]
    @State private var openRow: StdLogField?
    @State private var contextOpen: Bool
    @State private var who = 0
    /// The rentals the note named when it named more than one.
    @State private var named: [String]
    /// A fill has run, so a default hours value is now "Didn't say".
    @State private var filledOnce: Bool
    @State private var slotFlash = 0.0
    @State private var fillTick = 0
    @State private var readTask: Task<Void, Never>?
    @State private var beforeRules: StdLogRecord?
    @State private var beforeModel: StdLogRecord?
    @FocusState private var noteFocused: Bool
    private let focusOnOpen: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }
    private static var filledNote: String { L("Fixed the leaking tap at Santa Ray Ave, took about an hour and a half") }
    private static var gapNote: String { L("Showed the place to two families this morning") }
    private static var twoNote: String { L("Showed Santa Ray Ave and Delaney Ct, 2 hours each") }
    private static var vagueNote: String { L("Sorted the paperwork for this month") }

    init(seed: StdSeed, launch: StdProtoLaunch, onClose: @escaping () -> Void, onLog: @escaping (Double) -> Void = { _ in }) {
        self.seed = seed
        self.launch = launch
        self.onClose = onClose
        self.onLog = onLog
        let names = seed.rentals.rentals.map(\.name)
        let first = names.first ?? ""
        let base = StdLogRecord(rental: names.count == 1 ? first : nil, kind: .repairs, hours: 1, src: [:])
        var rec = base
        var note = "", reading: Set<StdLogField> = [], caption = Caption.recents
        var open: StdLogField?, named: [String] = [], filled = false, focus = false, context = false
        let state = launch.demo == nil ? launch.state : "empty"
        switch state {
        case "typing":
            // Rules have filled what they are sure of; the model is reading the kind of work.
            note = Self.filledNote
            rec.rental = first; rec.hours = 1; rec.src = [.rental: .note, .hours: .note]
            reading = [.kind]; caption = .reading; filled = true; focus = true
        case "filled", "updated", "context":
            note = Self.filledNote
            rec = StdLogRecord(rental: first, kind: .repairs, hours: 1.5, src: [.rental: .note, .kind: .note, .hours: .note])
            caption = state == "updated" ? .updated : .filled; filled = true; context = state == "context"
        case "missing", "gap":
            note = Self.gapNote
            rec = StdLogRecord(rental: nil, kind: .leasing, hours: 1, src: [.kind: .note])
            caption = .filled; filled = true
        case "manual":
            rec = StdLogRecord(rental: names.count > 1 ? names[1] : first, kind: .leasing, hours: 0.5,
                               src: [.rental: .yours, .kind: .yours, .hours: .yours])
            caption = .blank; open = .rental
        case "tworentals":
            note = Self.twoNote
            rec = StdLogRecord(rental: nil, kind: .leasing, hours: 2, src: [.kind: .note, .hours: .note])
            named = Array(names.prefix(2)); caption = .filled; filled = true
        case "timeout":
            note = Self.vagueNote
            caption = names.count > 1 ? .failure : .blank; filled = true
        default:
            focus = true
        }
        _note = State(initialValue: note)
        _record = State(initialValue: rec)
        _reading = State(initialValue: reading)
        _caption = State(initialValue: caption)
        _openRow = State(initialValue: open)
        _named = State(initialValue: named)
        _filledOnce = State(initialValue: filled)
        _contextOpen = State(initialValue: context)
        focusOnOpen = focus || launch.demo != nil
    }

    private var rentalNames: [String] { seed.rentals.rentals.map(\.name) }
    private var reader: StdLogReader { StdLogReader(rentals: rentalNames) }
    private var isAX: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20).padding(.top, 8)
                .stdMeasure("log.header")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if contextOpen {
                        contextCard.padding(.top, 4).padding(.bottom, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    noteField.padding(.top, 2)
                    captionSlot.padding(.top, 2)
                    recordCard.padding(.top, 2)
                    // Dropping the keyboard reveals the receipt link (spec §3); while typing it would sit under the button.
                    if !noteFocused { receiptLink.padding(.top, 4).transition(.opacity) }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .modifier(StdLogSoftBottomEdge())
            .safeAreaInset(edge: .bottom, spacing: 0) { buttonBar }
        }
        .background(colors.background.ignoresSafeArea())
        .presentationDetents([.large])
        .onChange(of: note) { _, new in noteChanged(new) }
        .sensoryFeedback(.impact(weight: .light), trigger: fillTick)
        .task { await start() }
    }

    // MARK: Header: title + the context line ("Today · Me ⌄"), close on the right

    private var contextLine: String {
        let day = L("Today")
        return who == 0 ? L("\(day) · Me") : L("\(day) · Spouse")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("Log time")).font(.title2.weight(.semibold)).foregroundStyle(colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Button { toggleContext() } label: {
                    HStack(spacing: 4) {
                        Text(contextLine).fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(contextOpen ? 180 : 0))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(colors.textSecondary)
                    .frame(minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(StdPressStyle())
                .accessibilityLabel(L("Date and who: \(contextLine)"))
                .accessibilityHint(L("Shows the date and who did the work"))
            }
            Spacer(minLength: 8)
            if caption == .recents && note.isEmpty && !isAX {
                Button {} label: { Image(systemName: "stopwatch") }
                    .buttonStyle(StdButtonStyle(.icon))
                    .accessibilityLabel(L("Start a timer"))
                    .transition(.opacity)
            }
            Button(action: { readTask?.cancel(); onClose() }) { Image(systemName: "xmark") }
                .buttonStyle(StdButtonStyle(.icon))
                .accessibilityLabel(L("Close"))
        }
    }

    private var contextCard: some View {
        VStack(spacing: 0) {
            Button {} label: {
                rowLayout {
                    Text(L("Date")).font(.body).foregroundStyle(colors.textPrimary)
                    Spacer(minLength: 8)
                    Text(L("Today, Oct 23")).font(.body).foregroundStyle(colors.textSecondary)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(colors.textTertiary)
                }
                .padding(.horizontal, 16).frame(minHeight: 56).contentShape(Rectangle())
            }
            .buttonStyle(StdPressStyle())
            hairline
            rowLayout {
                Text(L("Who")).font(.body).foregroundStyle(colors.textPrimary)
                Spacer(minLength: 8)
                StdSegmented(options: [L("Me"), L("Spouse")], selection: $who).frame(maxWidth: isAX ? .infinity : 200)
            }
            .padding(.horizontal, 16).padding(.vertical, isAX ? 10 : 0).frame(minHeight: 56)
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.backgroundSecondary))
    }

    // MARK: The note (LHField multi-line, min 104, focused on open, mic inside)

    private var placeholder: String {
        caption == .blank && openRow != nil && note.isEmpty
            ? L("What did you do? (optional)")
            : L("What did you do? Try “fixed the sink at \(rentalNames.first ?? ""), 1 hour”")
    }

    private var noteField: some View {
        // The placeholder is a sibling in the ZStack so it sizes the field and wraps (the system prompt
        // truncated at AX3); textTertiary, never the system grey.
        ZStack(alignment: .topLeading) {
            if note.isEmpty {
                Text(placeholder).font(.body).foregroundStyle(colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 16).padding(.trailing, 56).padding(.vertical, 14)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextField("", text: $note, axis: .vertical)
                .font(.body)
                .foregroundStyle(colors.textPrimary)
                .tint(colors.action)
                .lineLimit(2...6)
                .focused($noteFocused)
                .padding(.leading, 16).padding(.trailing, 56).padding(.vertical, 14)
        }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .overlay(alignment: .bottomTrailing) {
                Button {} label: { Image(systemName: "mic.fill") }
                    .buttonStyle(StdButtonStyle(.icon))
                    .padding(8)
                    .accessibilityLabel(L("Talk instead of type"))
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.backgroundSecondary))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(noteFocused ? colors.action : colors.border, lineWidth: noteFocused ? 1.5 : 1)
                .animation(StdMotion.quick, value: noteFocused))
            .contentShape(Rectangle())
            .onTapGesture { noteFocused = true }
            .accessibilityLabel(L("What did you do?"))
            .stdMeasure("field.note")
    }

    // MARK: The 44pt slot shared by RECENT, the reading caption and the filled caption (nothing moves)

    private var captionSlot: some View {
        ZStack(alignment: .leading) {
            switch caption {
            case .recents: recents.transition(captionSwap)
            case .blank: Color.clear
            case .reading:
                // No loader glyph: the shimmer in the value column is the only loading cue.
                Text(L("Reading your note")).font(.footnote).foregroundStyle(colors.textSecondary)
                    .transition(captionSwap)
            case .filled: undoCaption(L("Filled from your note")).transition(captionSwap)
            case .updated: undoCaption(L("Updated")).transition(captionSwap)
            case .failure:
                Text(L("Couldn’t tell which rental. Pick it below."))
                    .font(.footnote).foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(captionSwap)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .stdMeasure("slot.caption")
    }

    /// Caption swap: the old caption blurs out (0.10), then the new one blurs in (0.14 after a 0.10
    /// delay), so two captions are never on screen together. Total 0.24.
    private var captionSwap: AnyTransition {
        let fx = StdLogArriveFX(y: 0, blur: reduceMotion ? 0 : 2, opacity: 0)
        return .asymmetric(insertion: .modifier(active: fx, identity: .identity).animation(.easeOut(duration: 0.14).delay(0.10)),
                           removal: .modifier(active: fx, identity: .identity).animation(.easeOut(duration: 0.10)))
    }

    private func undoCaption(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle").font(.caption.weight(.semibold)).foregroundStyle(colors.timberInk)
                .accessibilityHidden(true)
            Text(text).foregroundStyle(colors.textSecondary).fixedSize(horizontal: false, vertical: true)
            Text(verbatim: "·").foregroundStyle(colors.textSecondary).accessibilityHidden(true)
            undoButton
            Spacer(minLength: 0)
        }
        .font(.footnote)
    }

    private var undoButton: some View {
        Button(L("Undo")) { undo() }.buttonStyle(StdButtonStyle(.tertiary)).padding(.leading, -4)
    }

    private var recents: some View {
        HStack(spacing: 8) {
            Text(L("Recent")).font(StdFont.drafting).textCase(.uppercase).tracking(StdFont.draftingTracking)
                .foregroundStyle(colors.draftingInk)
                .fixedSize()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(seed.week.prefix(3)) { e in
                        StdChip(text: L("\(e.category.stdLabel) · \(shortName(e.rental)) · \(StdFormat.hours(e.hours))")) {
                            useRecent(e)
                        }
                    }
                }
                .padding(.trailing, 24)
            }
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.86),
                                         .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
        }
    }

    private func shortName(_ name: String) -> String {
        let words = name.split(separator: " ")
        return words.count > 1 ? words.dropLast().joined(separator: " ") : name
    }

    // MARK: The record: three LHRow.Value rows in one inner surface

    private var recordCard: some View {
        VStack(spacing: 0) {
            recordRow(.rental, label: L("Rental"))
            if !named.isEmpty && record.rental == nil { namedRentals }
            if openRow == .rental { rentalPicker }
            hairline
            recordRow(.kind, label: L("Kind of work"))
            if openRow == .kind { kindPicker }
            hairline
            hoursRow
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.backgroundSecondary))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .stdMeasure("card.record")
    }

    private var hairline: some View {
        Rectangle().fill(colors.border).frame(height: 0.5).padding(.leading, 16)
    }

    private func rowLayout<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        let layout = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
        return layout { content() }
    }

    private func recordRow(_ f: StdLogField, label: String) -> some View {
        Button { open(f) } label: {
            rowLayout {
                Text(label).font(.body).foregroundStyle(colors.textPrimary)
                if !isAX { Spacer(minLength: 8) }
                HStack(spacing: 8) {
                    valueView(f)
                    Image(systemName: openRow == f ? "chevron.up" : "chevron.right")
                        .font(.footnote.weight(.semibold)).foregroundStyle(colors.textTertiary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, isAX ? 10 : 0)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .modifier(StdLogWash(tick: washTick[f] ?? 0, peak: washPeak[f] ?? 0.12, color: colors.timber))
            .contentShape(Rectangle())
        }
        .buttonStyle(StdPressStyle())
        .stdMeasure("row.\(f)")
    }

    private func valueKey(_ f: StdLogField) -> String {
        switch f {
        case .rental: return "r-\(record.rental ?? "-")-\(record.source(.rental))"
        case .kind: return "k-\(record.kind.map { "\($0)" } ?? "-")-\(record.source(.kind))"
        case .hours: return "h-\(record.hours)-\(record.source(.hours))-\(didntSay)"
        }
    }

    /// The label stays; only the value column changes: shimmer while reading, then the value arrives.
    private func valueView(_ f: StdLogField) -> some View {
        ZStack(alignment: isAX ? .leading : .trailing) {
            if reading.contains(f) {
                StdLogShimmer().transition(.opacity.animation(.easeOut(duration: 0.10)))
            } else {
                valueContent(f).id(valueKey(f)).transition(arriveTransition(f))
            }
        }
    }

    private func arriveTransition(_ f: StdLogField) -> AnyTransition {
        let rm = reduceMotion
        switch arrive[f] ?? .fill {
        case .fill:
            // valueFill: the old value fades out (0.10); the new one fades in rising 4pt (reveal 0.22).
            return .asymmetric(insertion: .modifier(active: StdLogArriveFX(y: rm ? 0 : 4, blur: 0, opacity: 0), identity: .identity),
                               removal: .opacity.animation(.easeOut(duration: 0.10)))
        case .update:
            // valueUpdate: crossfade in place with a 2pt blur (reveal 0.22).
            return .modifier(active: StdLogArriveFX(y: 0, blur: rm ? 0 : 2, opacity: 0), identity: .identity)
        }
    }

    @ViewBuilder private func valueContent(_ f: StdLogField) -> some View {
        switch f {
        case .rental:
            if let r = record.rental {
                valueText(r, record.source(.rental), hint: record.source(.rental) == .standard && rentalNames.count == 1 ? L("· only rental") : nil)
            } else {
                chooseSlot
            }
        case .kind:
            if let k = record.kind {
                valueText(k.stdLabel, record.source(.kind), hint: record.source(.kind) == .standard ? L("· last used") : nil)
            } else {
                chooseSlot
            }
        case .hours:
            hoursValue
        }
    }

    private func valueText(_ value: String, _ src: StdLogSource, hint: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.body).foregroundStyle(src == .standard ? colors.textSecondary : colors.textPrimary)
            if let hint { Text(hint).font(.footnote).foregroundStyle(colors.textSecondary) }
            if src == .note { sparkle }
        }
        .lineLimit(isAX ? nil : 1)
    }

    private var sparkle: some View {
        Image(systemName: "sparkle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(colors.timberInk)
            .accessibilityLabel(L("from your note"))
    }

    /// Empty slot: a dashed capsule in action ink, "Choose".
    private var chooseSlot: some View {
        Text(L("Choose"))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.action)
            .padding(.horizontal, 14)
            .frame(minHeight: 30)
            .background(Capsule().strokeBorder(colors.action, style: StrokeStyle(lineWidth: 1 + slotFlash, dash: [4, 3])))
            .accessibilityLabel(L("Not chosen yet"))
    }

    private var namedRentals: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Your note names \(named.count) rentals. Log each on its own."))
                .font(.footnote).foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            StdLogFlow(spacing: 8) {
                ForEach(named, id: \.self) { n in StdChip(text: n) { pickRental(n) } }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    private var rentalPicker: some View {
        StdLogFlow(spacing: 8) {
            ForEach(rentalNames, id: \.self) { n in StdChip(text: n, selected: record.rental == n) { pickRental(n) } }
            StdChip(text: L("Add a rental")) {}
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.bottom, 12)
        .transition(.opacity)
    }

    private var kindPicker: some View {
        StdLogFlow(spacing: 8) {
            ForEach([ActivityCategory.repairs, .management, .leasing, .bookkeeping, .travel, .legal], id: \.self) { k in
                StdChip(text: k.stdLabel, selected: record.kind == k) { pickKind(k) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.bottom, 12)
        .transition(.opacity)
    }

    // MARK: How long: LHRow.Stepper (an LHStepper in a 52pt value row)

    private var didntSay: Bool { filledOnce && record.source(.hours) == .standard && !note.isEmpty }

    private var hoursValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(StdFormat.hours(record.hours))
                .font(.title3.weight(.semibold)).fontDesign(.rounded).monospacedDigit()
                .foregroundStyle(record.source(.hours) == .standard ? colors.textSecondary : colors.textPrimary)
            if record.source(.hours) == .note { sparkle }
            if didntSay { StdTag(text: L("Didn’t say"), ink: colors.caution, wash: colors.cautionSurface).fixedSize() }
        }
    }

    private var hoursRow: some View {
        let stepper = HStack(spacing: 8) {
            Button { step(-0.25) } label: { Image(systemName: "minus") }
                .buttonStyle(StdButtonStyle(.icon)).accessibilityLabel(L("Less"))
            valueView(.hours).frame(minWidth: 100)
            Button { step(0.25) } label: { Image(systemName: "plus") }
                .buttonStyle(StdButtonStyle(.icon)).accessibilityLabel(L("More"))
        }
        return rowLayout {
            Text(L("How long")).font(.body).foregroundStyle(colors.textPrimary)
            if !isAX { Spacer(minLength: 8) }
            stepper
        }
        .padding(.horizontal, 16).padding(.vertical, isAX ? 10 : 4)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .modifier(StdLogWash(tick: washTick[.hours] ?? 0, peak: washPeak[.hours] ?? 0.12, color: colors.timber))
        .sensoryFeedback(.selection, trigger: record.hours)
        .stdMeasure("row.hours")
    }

    private var receiptLink: some View {
        Button(L("Add a receipt or photo")) {}
            .buttonStyle(StdButtonStyle(.tertiary))
            .padding(.leading, -4)
    }

    // MARK: The Log button: states the record, never disabled, changes words (buttonStateChange)

    private var hoursText: String { StdFormat.hours(record.hours) }

    private var labelKey: String {
        if record.rental == nil { return "pick-rental" }
        if record.kind == nil { return "pick-kind" }
        return "log-\(hoursText)-\(record.rental ?? "")"
    }

    /// One line at every size (glass holds one line, §1.25): the full sentence when it fits, else the
    /// short form ("Log 1h 30m"); the rental row above still says where.
    @ViewBuilder private var logLabelText: some View {
        if record.rental == nil {
            Text(L("Pick a rental")).lineLimit(1)
        } else if record.kind == nil {
            ViewThatFits(in: .horizontal) {
                Text(L("Pick the kind of work")).lineLimit(1).fixedSize()
                Text(L("Pick the kind")).lineLimit(1)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                Text(L("Log \(hoursText) at \(record.rental ?? "")")).lineLimit(1).fixedSize()
                Text(L("Log \(hoursText)")).lineLimit(1)
            }
        }
    }

    private var logLabel: some View {
        ZStack {
            logLabelText
                .id(labelKey)
                .transition(.modifier(active: StdLogArriveFX(y: 0, blur: reduceMotion ? 0 : 2, opacity: 0), identity: .identity))
        }
        .font(.body.weight(.semibold))
        .multilineTextAlignment(.center)
        .foregroundStyle(colors.onAction)
        .frame(maxWidth: .infinity, minHeight: 40)
        .animation(StdMotion.reveal, value: labelKey)
        .onChange(of: labelKey) { _, _ in StdMotionLog.mark("buttonStateChange") }
    }

    @ViewBuilder private var logButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: log) { logLabel }
                .buttonStyle(.glassProminent)
                .tint(colors.action)
                .controlSize(.large)
                .accessibilityIdentifier("log.primary")
        } else {
            Button(action: log) { logLabel }
                .buttonStyle(StdButtonStyle(.primary))
                .accessibilityIdentifier("log.primary")
        }
    }

    private var buttonBar: some View {
        logButton
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background {
                // Rows fade out over 12pt above the button instead of sitting behind it.
                VStack(spacing: 0) {
                    LinearGradient(colors: [colors.background.opacity(0), colors.background], startPoint: .top, endPoint: .bottom)
                        .frame(height: 12)
                    colors.background
                }
                .padding(.top, -12)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            }
            .stdMeasure("log.button")
    }

    // MARK: Actions

    private func toggleContext() {
        noteFocused = false
        StdMotionLog.mark("sheetUnfold")
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : StdMotion.flow) { contextOpen.toggle() }
    }

    private func open(_ f: StdLogField) {
        noteFocused = false
        guard f != .hours else { return }
        StdMotionLog.mark("sheetUnfold")
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : StdMotion.flow) { openRow = openRow == f ? nil : f }
    }

    private func pickRental(_ name: String) {
        arrive[.rental] = .fill
        withAnimation(StdMotion.reveal) {
            record.rental = name
            record.src[.rental] = .yours
            reading.remove(.rental)
            openRow = nil
            named = []
        }
    }

    private func pickKind(_ k: ActivityCategory) {
        arrive[.kind] = .fill
        withAnimation(StdMotion.reveal) {
            record.kind = k
            record.src[.kind] = .yours
            reading.remove(.kind)
            openRow = nil
        }
    }

    private func step(_ delta: Double) {
        arrive[.hours] = .update
        withAnimation(StdMotion.standard) {
            record.hours = min(24, max(0, record.hours + delta))
            record.src[.hours] = .yours
            reading.remove(.hours)
        }
    }

    private func useRecent(_ e: StdEntry) {
        for f in StdLogField.allCases { arrive[f] = .fill }
        withAnimation(StdMotion.reveal) {
            record = StdLogRecord(rental: e.rental, kind: e.category, hours: e.hours,
                                  src: [.rental: .yours, .kind: .yours, .hours: .yours])
        }
    }

    /// Log works at any time: a read in flight is cancelled and what is on screen is logged.
    private func log() {
        if record.rental == nil { open(.rental); return }
        if record.kind == nil { open(.kind); return }
        if caption == .reading { StdMotionLog.mark("readCancelled") }
        readTask?.cancel()
        readTask = nil
        noteFocused = false
        StdMotionLog.mark("log \(hoursText) at \(record.rental ?? "")")
        onLog(record.hours)
    }

    private func undo() {
        let target = caption == .updated ? beforeModel : beforeRules
        guard let target else { return }
        StdMotionLog.mark("undo")
        for f in StdLogField.allCases { arrive[f] = .update }
        Task { @MainActor in
            await nextFrame()
            let changed = StdLogField.allCases.filter { valueOf($0, target) != valueOf($0, record) }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : StdMotion.reveal) { record = target }
            for (i, f) in changed.reversed().enumerated() { flash(f, peak: 0.12, delay: Double(i) * 0.05) }
            withAnimation(.easeOut(duration: 0.2)) { caption = .blank }
        }
    }

    // MARK: The fill pipeline (scripted backend)

    private func noteChanged(_ text: String) {
        readTask?.cancel()
        readTask = nil
        // clearFillCaption: a new keystroke clears the caption and any shimmer.
        if !reading.isEmpty { withAnimation(.easeOut(duration: 0.10)) { reading = [] } }
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let next: Caption = empty && openRow == nil && record.src.isEmpty ? .recents : .blank
        if caption != next { withAnimation(StdMotion.quick) { caption = next } }
        guard !empty else { return }
        readTask = Task { @MainActor in await read(text) }
    }

    private func pause(_ s: Double) async throws { try await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
    private func nextFrame() async { try? await Task.sleep(nanoseconds: 20_000_000) }

    @MainActor private func read(_ text: String) async {
        do {
            try await pause(StdLogReader.pause)
            // Rules fill.
            beforeRules = record
            StdMotionLog.mark("rulesFill")
            _ = await land(reader.rules(text), label: "valueFill.rules")
            filledOnce = true
            guard StdLogReader.hasModel else {
                withAnimation(StdMotion.quick) { caption = .filled }
                return
            }
            // Reading: only cells still unknown (default or empty, not the user's) shimmer.
            let unknown = Set(StdLogField.allCases.filter { f in
                record.source(f) == .standard || (f == .rental && record.rental == nil) || (f == .kind && record.kind == nil)
            }.filter { record.source($0) != .yours })
            withAnimation(.easeOut(duration: 0.10)) { reading = unknown }
            withAnimation(StdMotion.quick) { caption = .reading }
            StdMotionLog.mark("reading.shimmer")
            if StdLogReader.backend == .timeout {
                try await pause(StdLogReader.timeout)
                timedOut()
                return
            }
            try await pause(StdLogReader.modelDelay)
            beforeModel = record
            StdMotionLog.mark("modelLands")
            let updated = await land(reader.model(text), label: "valueFill.model")
            if !reading.isEmpty { withAnimation(.easeOut(duration: 0.10)) { reading = [] } }
            withAnimation(StdMotion.quick) { caption = updated ? .updated : .filled }
        } catch {
            // Cancelled: a new keystroke, Log, or close. Nothing to undo.
        }
    }

    /// Timeout, refusal or rate limit: the caption fades, shimmering cells return to their default.
    private func timedOut() {
        StdMotionLog.mark("readTimeout")
        let fail = rentalNames.count > 1 && record.rental == nil
        withAnimation(.easeOut(duration: 0.20)) {
            reading = []
            caption = fail ? .failure : .blank
        }
        guard fail else { return }
        withAnimation(.easeOut(duration: 0.15)) { slotFlash = 1 } completion: {
            withAnimation(.easeOut(duration: 0.30)) { slotFlash = 0 }
        }
    }

    private func valueOf(_ f: StdLogField, _ r: StdLogRecord) -> String {
        switch f {
        case .rental: return r.rental ?? ""
        case .kind: return r.kind.map { "\($0)" } ?? ""
        case .hours: return "\(r.hours)"
        }
    }

    /// Lands a read: Rental → Kind of work → How long, 50 ms apart (valueFill), or a crossfade with a
    /// brighter wash for a value the user has already seen (valueUpdate). Returns true if anything updated.
    @MainActor private func land(_ read: StdLogReader.Read, label: String) async -> Bool {
        var next = record
        var changes: [(StdLogField, Bool)] = []
        func consider(_ f: StdLogField, _ apply: (inout StdLogRecord) -> Void) {
            guard record.source(f) != .yours else { return }   // a touched field is never overwritten
            var candidate = next
            apply(&candidate)
            candidate.src[f] = .note
            guard valueOf(f, candidate) != valueOf(f, record) || record.source(f) != .note else { return }
            let isUpdate = record.source(f) == .note && valueOf(f, candidate) != valueOf(f, record)
            next = candidate
            changes.append((f, isUpdate))
        }
        if read.rentals.count == 1 { consider(.rental) { $0.rental = read.rentals[0] } }
        if let k = read.kind { consider(.kind) { $0.kind = k } }
        if let h = read.hours { consider(.hours) { $0.hours = h } }
        if read.rentals.count > 1 && record.source(.rental) != .yours {
            withAnimation(StdMotion.flow) { named = read.rentals; record.rental = nil }
        }
        guard !changes.isEmpty else { return false }

        for (f, isUpdate) in changes { arrive[f] = isUpdate ? .update : .fill }
        await nextFrame()

        let t0 = CACurrentMediaTime()
        let name = changes.contains { $0.1 } && changes.allSatisfy({ $0.1 }) ? "valueUpdate" : label
        StdMotionLog.mark(name)
        if changes.contains(where: { !$0.1 }) { fillTick += 1 }   // one light impact per fill batch, none on an update
        for (i, change) in changes.enumerated() {
            let (f, isUpdate) = change
            let delay = Double(i) * 0.05
            let anim = (reduceMotion ? Animation.easeOut(duration: 0.20) : StdMotion.reveal).delay(delay)
            let last = i == changes.count - 1
            withAnimation(anim, completionCriteria: .removed) {
                switch f {
                case .rental: record.rental = next.rental
                case .kind: record.kind = next.kind
                case .hours: record.hours = next.hours
                }
                record.src[f] = .note
                reading.remove(f)
            } completion: {
                if isUpdate { StdMotionLog.mark("valueUpdate.\(f).end dur=\(String(format: "%.3f", CACurrentMediaTime() - t0))") }
                if last { StdMotionLog.mark("\(name).end dur=\(String(format: "%.3f", CACurrentMediaTime() - t0)) cells=\(changes.count)") }
            }
            flash(f, peak: isUpdate ? 0.16 : 0.12, delay: delay)
        }
        return changes.contains { $0.1 }
    }

    /// The timber wash under a row: one keyframe run, 0 → peak (0.10) → 0 (0.20), 0.30 total.
    private func flash(_ f: StdLogField, peak: Double, delay: Double) {
        Task { @MainActor in
            try? await pause(delay)
            washPeak[f] = peak
            StdMotionLog.mark("wash.\(f) keyframes=0.10+0.20")
            washTick[f, default: 0] += 1
        }
    }

    // MARK: Open, and the scripted runs for the videos

    @MainActor private func start() async {
        if focusOnOpen {
            try? await pause(0.45)
            noteFocused = true
        }
        guard let demo = launch.demo, demo == "logfill" || demo == "logtime" || demo == "logmid" else { return }
        try? await pause(1.0)
        let text = Self.filledNote
        var typed = ""
        for ch in text {
            typed.append(ch)
            note = typed
            try? await pause(ch == " " ? 0.07 : 0.045)
        }
        if demo == "logmid" {
            // Log mid-read: the read cancels and what is on screen is logged.
            try? await pause(StdLogReader.pause + 0.9)
            log()
            return
        }
        if StdLogReader.backend == .timeout {
            // Timeout: the caption fades and the shimmering cells return to their default; no Log.
            try? await pause(StdLogReader.pause + StdLogReader.timeout + 1.0)
            noteFocused = false
            return
        }
        // Rules (0.6 s) → reading → the model lands → Updated · Undo.
        try? await pause(StdLogReader.pause + StdLogReader.modelDelay + 1.4)
        noteFocused = false
        try? await pause(1.4)
        log()
    }
}

/// Rows fade under the pinned button instead of a hairline (iOS 26+).
private struct StdLogSoftBottomEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            content
        }
    }
}

/// The row wash as one keyframe run (no chained completions, so it ends at 0.30).
private struct StdLogWash: ViewModifier {
    let tick: Int
    let peak: Double
    let color: Color
    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: tick) { view, value in
            view.background(color.opacity(value))
        } keyframes: { _ in
            CubicKeyframe(peak, duration: 0.10)
            CubicKeyframe(0, duration: 0.20)
        }
    }
}

/// Arrival: opacity + rise + blur, used by valueFill (rise 4pt), valueUpdate and buttonStateChange (2pt blur).
private struct StdLogArriveFX: ViewModifier {
    var y: CGFloat
    var blur: CGFloat
    var opacity: Double
    static let identity = StdLogArriveFX(y: 0, blur: 0, opacity: 1)
    func body(content: Content) -> some View {
        content.offset(y: y).blur(radius: blur).opacity(opacity)
    }
}

// MARK: - Reading: shimmer in the value column, and the drafting loader in the caption (same 1.6 s cycle)

private enum StdLogCycle {
    static let period = 1.6
    static func phase(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
    }
}

/// 72×20, radius 6; a soft highlight sweeps left → right once per 1.6 s. Reduced motion: a static bar
/// whose opacity breathes 60% ↔ 100%.
struct StdLogShimmer: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let colors = AdaptiveColors(colorScheme: scheme)
        // On-token: actionSurface bar (#E3E9FA / #182A5C); the sweep is the card colour (#FFFFFF / #141C3F).
        let highlight = colors.backgroundSecondary
        TimelineView(.animation) { ctx in
            let p = StdLogCycle.phase(ctx.date)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(colors.actionSurface)
                .overlay(alignment: .leading) {
                    if !reduceMotion {
                        LinearGradient(colors: [.clear, highlight, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 40)
                            .offset(x: -40 + 112 * p)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .opacity(reduceMotion ? 0.8 + 0.2 * cos(2 * .pi * p) : 1)
        }
        .frame(width: 72, height: 20)
        .accessibilityElement()
        .accessibilityLabel(L("Reading your note"))
    }
}

/// Chips that wrap (rental and kind pickers).
struct StdLogFlow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.init(width: width, height: nil))
            if x > 0 && x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, size.height)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.init(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .init(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
#endif
