import SwiftUI

#if DEBUG
// MARK: - Log time, note first: say it, check it, log it (direction 2026-10-22, in the standard's components)

struct StdLogTimeSheet: View {
    enum Phase { case empty, filled, gap }

    let seed: StdSeed
    let launch: StdProtoLaunch
    let onClose: () -> Void

    @State private var phase: Phase
    @State private var note: String
    @State private var hours: Double
    @State private var who = 0
    @State private var rowsShown = 0
    @State private var successTick = 0
    /// The sheet fits its content (no dead canvas): header + content + pinned button.
    @State private var headerH: CGFloat = 0
    @State private var contentH: CGFloat = 0
    @State private var buttonH: CGFloat = 0
    @State private var detent: PresentationDetent = .large
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    private static var filledNote: String { L("Fixed the leaking tap at Santa Ray Ave, took about an hour and a half") }
    private static var gapNote: String { L("Showed the place to two families this morning") }

    init(seed: StdSeed, launch: StdProtoLaunch, onClose: @escaping () -> Void) {
        self.seed = seed
        self.launch = launch
        self.onClose = onClose
        let phase: Phase = launch.demo == "logtime" ? .empty : (launch.state == "filled" ? .filled : launch.state == "gap" ? .gap : .empty)
        _phase = State(initialValue: phase)
        _note = State(initialValue: phase == .filled ? Self.filledNote : phase == .gap ? Self.gapNote : "")
        _hours = State(initialValue: phase == .filled ? 1.5 : 1)
        _rowsShown = State(initialValue: phase == .empty ? 0 : 5)
    }

    private var rentalName: String { seed.rentals.rentals.first?.name ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            StdSheetHeader(eyebrow: L("Today · Fri, Oct 23"), title: L("Log time"), onClose: onClose)
                .padding(.horizontal, 20).padding(.top, 12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerH = $0 }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    noteField
                    if phase == .empty {
                        recents
                        detailsLine
                    } else {
                        fillCaption
                        rows
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentH = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(colors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button(primaryTitle) {}
                .buttonStyle(StdButtonStyle(.primary))
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
                .background(colors.background)
                .accessibilityIdentifier("log.primary")
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { buttonH = $0 }
        }
        .presentationDetents(fitHeight.map { [.height($0), .large] } ?? [.large], selection: $detent)
        .onChange(of: fitHeight) { _, h in
            withAnimation(StdMotion.flow) { detent = h.map { .height($0) } ?? .large }
        }
        .sensoryFeedback(.success, trigger: successTick)
        .task { await demo() }
    }

    /// Content height plus the grabber band and the home-indicator inset; nil when it needs the full sheet.
    private var fitHeight: CGFloat? {
        guard headerH > 0, contentH > 0, buttonH > 0 else { return nil }
        let h = (headerH + contentH + buttonH + 34).rounded(.up)
        return h < 780 ? h : nil
    }

    /// Large text keeps the label short so the button stays at two lines or fewer.
    private var primaryTitle: String {
        switch phase {
        case .gap: return L("Pick a rental")
        case .empty, .filled:
            return typeSize.isAccessibilitySize ? L("Log \(StdFormat.hours(hours))") : L("Log \(StdFormat.hours(hours)) at \(rentalName)")
        }
    }

    // MARK: The note (LHField multi-line, min 104; placeholder in textTertiary)

    private var noteField: some View {
        ZStack(alignment: .topLeading) {
            if note.isEmpty {
                Text(L("What did you do? Try “fixed the sink at Santa Ray Ave, 1 hour”"))
                    .font(.body).foregroundStyle(colors.textTertiary)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            Text(note).font(.body).foregroundStyle(colors.textPrimary)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .padding(.trailing, 44)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            Button {} label: { Image(systemName: "mic.fill") }
                .buttonStyle(StdButtonStyle(.icon))
                .padding(8)
                .accessibilityLabel(L("Talk instead"))
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.backgroundSecondary))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(phase == .empty ? colors.border : colors.action, lineWidth: phase == .empty ? 1 : 1.5)
            .animation(StdMotion.quick, value: phase))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("What did you do?"))
        .stdMeasure("field.note")
    }

    // MARK: Empty: recent chips + the details line (the manual door)

    private var recents: some View {
        VStack(alignment: .leading, spacing: 8) {
            StdSectionHeader(title: L("Recent"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    StdChip(text: L("Repairs · Santa Ray · 1h"))
                    StdChip(text: L("Management · Santa Ray · 1h 30m"))
                    StdChip(text: L("Bookkeeping · Delaney · 15m"))
                }
            }
            .scrollClipDisabled()
        }
    }

    private var detailsLine: some View {
        Button { unfold() } label: {
            HStack(spacing: 8) {
                Text(L("Details")).font(.body).foregroundStyle(colors.textPrimary)
                Spacer(minLength: 8)
                Text(L("\(rentalName) · \(StdFormat.hours(hours)) · Today")).font(.body).foregroundStyle(colors.textSecondary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(colors.textTertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.backgroundSecondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(StdPressStyle())
    }

    // MARK: Filled: caption with Undo, then the rows (sheetUnfold)

    private var fillCaption: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(spacing: 6))
        return layout {
            Label {
                Text(L("Filled from your note."))
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(colors.timberInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(L("Undo")) {}.buttonStyle(StdButtonStyle(.tertiary))
        }
        .font(.subheadline)
        .transition(.opacity)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            valueRow(0, L("Rental"), phase == .gap ? nil : rentalName, fromNote: phase == .filled)
            divider(1)
            valueRow(1, L("Kind of work"), phase == .gap ? ActivityCategory.leasing.stdLabel : ActivityCategory.repairs.stdLabel, fromNote: true)
            divider(2)
            hoursRow.stdUnfold(index: 2, shown: rowsShown)
            divider(3)
            valueRow(3, L("Date"), L("Today"), fromNote: false)
            divider(4)
            HStack {
                Text(L("Who")).font(.body).foregroundStyle(colors.textPrimary)
                Spacer(minLength: 12)
                StdSegmented(options: [L("Me"), L("Spouse")], selection: $who).frame(maxWidth: 200)
            }
            .padding(.horizontal, 16).frame(minHeight: 56)
            .stdUnfold(index: 4, shown: rowsShown)
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.backgroundSecondary))
        .stdMeasure("card.rows")
    }

    private func divider(_ index: Int) -> some View {
        Rectangle().fill(colors.border).frame(height: 0.5).padding(.leading, 16).stdUnfold(index: index, shown: rowsShown)
    }

    /// LHRow.Value: label left, value right + chevron; a timber sparkle marks what came from the note.
    private func valueRow(_ index: Int, _ label: String, _ value: String?, fromNote: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.body).foregroundStyle(colors.textPrimary)
            Spacer(minLength: 12)
            Text(value ?? L("Choose")).font(.body)
                .foregroundStyle(value == nil ? colors.action : colors.textSecondary)
                .fontWeight(value == nil ? .semibold : .regular)
                .lineLimit(1)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(colors.textTertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .stdUnfold(index: index, shown: rowsShown)
    }

    private var hoursRow: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Hours")).font(.body).foregroundStyle(colors.textPrimary)
                if phase == .gap {
                    Label { Text(L("Didn't say how long")) } icon: { Image(systemName: "circle.fill").font(.caption2) }
                        .font(.footnote).foregroundStyle(colors.caution)
                }
            }
            Spacer(minLength: 8)
            StdStepper(hours: $hours)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .frame(minHeight: 56)
    }

    private func unfold() {
        StdMotionLog.mark("sheetUnfold")
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : StdMotion.flow) { phase = .filled }
        for i in 0..<5 {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : StdMotion.reveal.delay(Double(min(i, 3)) * 0.03)) { rowsShown = i + 1 }
        }
    }

    private func demo() async {
        guard launch.demo == "logtime" else { return }
        func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
        await pause(1.8)
        let full = Self.filledNote
        var typed = ""
        for word in full.split(separator: " ") {
            typed += (typed.isEmpty ? "" : " ") + word
            note = typed
            await pause(0.09)
        }
        await pause(0.6)
        hours = 1.5
        unfold()
        await pause(2.4)
        StdMotionLog.mark("buttonStateChange")
        successTick += 1
    }
}

private struct StdUnfold: ViewModifier {
    let index: Int
    let shown: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(index < shown ? 1 : 0)
            .offset(y: index < shown || reduceMotion ? 0 : 6)
    }
}

extension View {
    fileprivate func stdUnfold(index: Int, shown: Int) -> some View { modifier(StdUnfold(index: index, shown: shown)) }
}
#endif
