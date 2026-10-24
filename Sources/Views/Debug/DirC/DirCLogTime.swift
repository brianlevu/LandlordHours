import SwiftUI

#if DEBUG
// MARK: - Log time: an opaque sheet on paper, the rules continue inside it

struct DirCLogTimeSheet: View {
    @Bindable var store: DirCStore
    @Environment(\.dircPitch) private var pitch
    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @State private var who = 0
    private let c = DirCColors()

    init(store: DirCStore) {
        self.store = store
        _note = State(initialValue: C("Fixed the garbage disposal at \(store.book.name)"))
    }

    var body: some View {
        let p = c.p
        ScrollView {
            DirCRuledStack(pitch: pitch) {
                header
                DirCLedgerLine {
                    TextField(C("What did you do?"), text: $note,
                              prompt: Text(C("What did you do?")).foregroundStyle(p.textSecondary), axis: .vertical)
                        .font(.body)
                        .foregroundStyle(p.ink)
                        .lineLimit(3...6)
                        .padding(14)
                        .frame(minHeight: 104, alignment: .topLeading)
                        .background(p.surfaceInner, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                DirCRuleLine {
                    DirCLedgerLine {
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            Image(systemName: "sparkle").font(.subheadline.weight(.light)).foregroundStyle(p.action)
                                .accessibilityHidden(true)
                            Text(C("Filled from your note.")).font(.subheadline).foregroundStyle(p.textSecondary)
                            Spacer(minLength: 8)
                            DirCLink(title: C("Undo")) {}
                        }
                    }
                }
                DirCLedgerLine {
                    Text(C("HRS")).font(DirCFont.stamp).foregroundStyle(p.action)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                } main: {
                    if #available(iOS 18.0, *) {
                        DirCDrum(store: store)
                            .alignmentGuide(.lastTextBaseline) { d in d.height / 2 + 16 }
                    } else {
                        Stepper(DirCFormat.hours(store.drum ?? 1.5), value: Binding(get: { store.drum ?? 1.5 }, set: { store.drum = $0 }),
                                in: 0.25...12, step: 0.25)
                    }
                }
                valueRow(C("Rental"), store.book.name)
                valueRow(C("Kind of work"), ActivityCategory.repairs.stdLabel)
                valueRow(C("Date"), C("Today, Oct 23"))
                DirCRuleLine {
                    DirCLedgerLine { Text(C("Who")).font(DirCFont.smallCaps).foregroundStyle(p.textSecondary) }
                }
                DirCLedgerLine {
                    Picker(C("Who"), selection: $who) {
                        Text(C("Me")).tag(0)
                        Text(C("Spouse")).tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.vertical, 12)
                }
                Color.clear.frame(height: pitch)
            }
            .background(alignment: .top) { DirCRules(overscan: 1200) }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background { DirCPaper() }
        .overlay { DirCMarginRule().ignoresSafeArea() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DirCHoldButton(store: store) { commit() }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
                .background { p.canvas.overlay(alignment: .top) { Rectangle().fill(p.rule).frame(height: 0.5) }.ignoresSafeArea() }
        }
        .overlay { DirCFinger(store: store) }
    }

    private var header: some View {
        let p = c.p
        return DirCRuleLine(pitches: 2) {
            DirCLedgerLine {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: "23")
                    Text(C("OCT"))
                }
                .font(DirCFont.stamp).foregroundStyle(p.action)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityHidden(true)
            } main: {
                HStack(alignment: .lastTextBaseline) {
                    Text(C("New entry")).font(.title2.weight(.semibold)).foregroundStyle(p.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(p.ink)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(DirCPress())
                    .accessibilityLabel(C("Close"))
                    .alignmentGuide(.lastTextBaseline) { d in d[VerticalAlignment.center] + 7 }
                }
            }
        }
    }

    /// Label in small caps on the first rule, value on the second: an entry form, not a settings list.
    private func valueRow(_ label: String, _ value: String) -> some View {
        let p = c.p
        return DirCRuledStack(pitch: pitch) {
            DirCRuleLine {
                DirCLedgerLine { Text(label).font(DirCFont.smallCaps).foregroundStyle(p.textSecondary) }
            }
            DirCRuleLine {
                DirCLedgerLine {
                    HStack(alignment: .lastTextBaseline) {
                        Text(value).font(.body).foregroundStyle(p.ink).dircRuled(.body)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.light)).foregroundStyle(p.textSecondary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func commit() {
        let h = store.drum ?? 1.5
        store.commitTick += 1
        DirCHaptic.log(".impact(flexibility: .rigid)", "hold-to-commit filled (0.6s), entry committed")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            store.showLog = false
            try? await Task.sleep(for: .milliseconds(520))
            store.applyEntry(hours: h)
        }
    }
}

// MARK: - The odometer drum (signature control, part 1)

@available(iOS 18.0, *)
struct DirCDrum: View {
    @Bindable var store: DirCStore
    @Environment(\.dircPitch) private var pitch
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var position = ScrollPosition(idType: Double.self)
    /// Scroll offset measured from "first value centred", in points.
    @State private var offset: CGFloat = 0
    /// Geometry changes before the first positioning are layout, not the user turning the wheel.
    @State private var ready = false
    private let c = DirCColors()

    static let values: [Double] = Array(stride(from: 0.25, through: 12, by: 0.25))

    private var item: CGFloat { pitch * 2 }
    private var visible: Int { typeSize.isAccessibilitySize ? 1 : 3 }

    private func index(of v: Double) -> Int { Self.values.firstIndex(of: v) ?? 5 }

    var body: some View {
        let p = c.p
        let height = item * CGFloat(visible)
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(Self.values.enumerated()), id: \.element) { i, v in
                    let d = min(abs(CGFloat(i) * item - offset) / item, 1)
                    Text(DirCFormat.hours(v))
                        .font(DirCFont.drumCentre)
                        .monospacedDigit()
                        // Neighbours step down to textSecondary rather than 40% ink: AA holds (6.0:1 / 7.6:1).
                        .foregroundStyle(d < 0.5 ? p.ink : p.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .scaleEffect(1 - 0.5 * d, anchor: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: item)
                        .id(v)
                        .accessibilityHidden(true)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition($position)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.vertical, visible == 1 ? 0 : item, for: .scrollContent)
        .scrollIndicators(.hidden)
        .frame(height: height)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
            offset = y
            guard ready else { return }
            let i = min(max(Int((y / item).rounded()), 0), Self.values.count - 1)
            if store.drum != Self.values[i] { store.drum = Self.values[i] }
        }
        .task {
            let start = store.drum ?? 1.5
            jump(to: start, animated: false)
            try? await Task.sleep(for: .milliseconds(120))
            jump(to: start, animated: false)
            try? await Task.sleep(for: .milliseconds(80))
            ready = true
        }
        .onChange(of: store.drumTarget) { _, t in if let t { jump(to: t, animated: true) } }
        .background {
            // The odometer window: the paper under the wheel is plain; two ink rules frame the centre value.
            p.canvas.overlay {
                VStack(spacing: 0) {
                    Rectangle().fill(p.ink).frame(height: 0.5)
                    Spacer()
                    Rectangle().fill(p.ink).frame(height: 0.5)
                }
                .frame(height: item)
            }
            .padding(.leading, -12).padding(.trailing, -20)
        }
        .sensoryFeedback(trigger: store.drum) { _, new in
            guard let new else { return nil }
            return new.truncatingRemainder(dividingBy: 1) == 0 ? .alignment : .selection
        }
        .onChange(of: store.drum) { _, new in
            guard let new else { return }
            DirCHaptic.log(new.truncatingRemainder(dividingBy: 1) == 0 ? ".alignment" : ".selection", "drum detent → \(DirCFormat.hours(new))")
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { store.frames["drum"] = $0 }
        .accessibilityElement()
        .accessibilityLabel(C("Hours"))
        .accessibilityValue(DirCFormat.hours(store.drum ?? 1.5))
        .accessibilityAdjustableAction { dir in
            let v = store.drum ?? 1.5
            jump(to: dir == .increment ? min(12, v + 0.25) : max(0.25, v - 0.25), animated: true)
        }
    }

    private func jump(to v: Double, animated: Bool) {
        let y = CGFloat(index(of: v)) * item   // scrollTo(y:) is measured from the content top, insets excluded
        if animated {
            withAnimation(.spring(duration: 0.22, bounce: 0)) { position.scrollTo(y: y) }
        } else {
            position.scrollTo(y: y)
        }
    }
}

// MARK: - Hold to commit (signature control, part 2): 0.6s linear oxblood fill, release early cancels

struct DirCHoldButton: View {
    @Bindable var store: DirCStore
    let onCommit: () -> Void
    @State private var progress: Double = 0
    @State private var committed = false
    @State private var pressing = false
    @State private var timer: Task<Void, Never>?
    private let c = DirCColors()

    private var title: String {
        committed ? C("Entered") : C("Hold to enter \(DirCFormat.hours(store.drum ?? 1.5))")
    }

    var body: some View {
        let p = c.p
        label(p.action, p.actionWash)
            .overlay {
                GeometryReader { geo in
                    label(p.onAction, p.action)
                        .mask(alignment: .leading) { Rectangle().frame(width: geo.size.width * progress) }
                }
            }
            .clipShape(Capsule())
            .scaleEffect(pressing ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: pressing)
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: 0.6, maximumDistance: 40) {
                finish()
            } onPressingChanged: { down in
                down ? begin(timed: false) : end()
            }
            .onChange(of: store.demoPressing) { _, down in down ? begin(timed: true) : end() }
            .onAppear { if let f = store.holdFreeze { progress = f; pressing = true } }
            .sensoryFeedback(.impact(flexibility: .rigid), trigger: store.commitTick)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { store.frames["hold"] = $0 }
            .accessibilityElement()
            .accessibilityLabel(C("Enter \(DirCFormat.hours(store.drum ?? 1.5))"))
            .accessibilityHint(C("Hold for a moment to enter it."))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { finish() }
    }

    private func label(_ ink: Color, _ fill: Color) -> some View {
        HStack(spacing: 8) {
            if committed { Image(systemName: "checkmark").font(.body.weight(.semibold)) }
            Text(title).font(.body.weight(.semibold)).monospacedDigit().lineLimit(2).multilineTextAlignment(.center)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, minHeight: 52)
        .padding(.horizontal, 16)
        .background(fill)
    }

    private func begin(timed: Bool) {
        guard !committed else { return }
        pressing = true
        DirCHaptic.log("(none)", "hold began, oxblood fills left to right over 0.6s")
        withAnimation(.linear(duration: 0.6 * (1 - progress))) { progress = 1 }
        if timed {
            timer = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                if !Task.isCancelled && pressing { finish() }
            }
        }
    }

    private func end() {
        timer?.cancel()
        pressing = false
        guard !committed else { return }
        DirCHaptic.log("(none)", "released early, fill snaps back (0.2s ease-out), nothing entered")
        withAnimation(DirCMotion.release) { progress = 0 }
    }

    private func finish() {
        guard !committed else { return }
        committed = true
        pressing = false
        progress = 1
        onCommit()
    }
}

// MARK: - The demo finger (videos only)

struct DirCFinger: View {
    let store: DirCStore
    var body: some View {
        GeometryReader { geo in
            if let at = store.finger {
                let o = geo.frame(in: .global).origin
                Circle().fill(Color.gray.opacity(store.fingerDown ? 0.55 : 0.35))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5))
                    .frame(width: 40, height: 40)
                    .scaleEffect(store.fingerDown ? 0.85 : 1)
                    .position(x: at.x - o.x, y: at.y - o.y)
                    .animation(.easeOut(duration: 0.12), value: store.fingerDown)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Scripted runs for the videos

@MainActor
struct DirCDemo {
    let store: DirCStore
    let reduceMotion: Bool

    private func wait(_ s: Double) async { try? await Task.sleep(for: .milliseconds(Int(s * 1000))) }

    private func point(_ key: String, dx: CGFloat = 0) -> CGPoint? {
        guard let r = store.frames[key] else { return nil }
        return CGPoint(x: r.midX + dx, y: r.midY)
    }

    private func tap(_ key: String, then action: () -> Void) async {
        guard let at = point(key) else { action(); return }
        withAnimation(.easeOut(duration: 0.25)) { store.finger = at }
        await wait(0.35)
        store.fingerDown = true
        await wait(0.12)
        action()
        store.fingerDown = false
        await wait(0.25)
    }

    func run(_ demo: String) async {
        await wait(1.4)
        switch demo {
        case "confirm", "stage", "goal":
            guard let item = store.todayItems.first else { return }
            await tap("row.\(item.id)") { store.confirm(item, reduceMotion: reduceMotion) }
            store.finger = nil
            await wait(demo == "goal" ? 5 : 3)
            if demo == "confirm", store.books.count > 1 {
                let next = store.books[1].id
                await tap("tab.\(next)") { withAnimation(DirCMotion.segment) { store.focus = next } }
                store.finger = nil
                await wait(1.8)
                let back = store.books[0].id
                await tap("tab.\(back)") { withAnimation(DirCMotion.segment) { store.focus = back } }
                store.finger = nil
                await wait(1.5)
            }
        case "signature":
            await tap("plus") { store.showLog = true }
            store.finger = nil
            await wait(1.3)
            if let r = store.frames["drum"] {
                withAnimation(.easeOut(duration: 0.25)) { store.finger = CGPoint(x: r.midX, y: r.midY + 30) }
                await wait(0.35)
                store.fingerDown = true
                for v in [1.75, 2.0, 2.25, 2.5, 2.75, 3.0, 2.75, 2.5, 2.25, 2.0] {
                    store.drumTarget = v
                    if let f = store.finger { store.finger = CGPoint(x: f.x, y: f.y + (v > (store.drum ?? v) ? 6 : -6)) }
                    await wait(0.26)
                }
                store.fingerDown = false
                await wait(0.6)
            }
            if let at = point("hold") {
                withAnimation(.easeOut(duration: 0.25)) { store.finger = at }
                await wait(0.4)
                // An early release: the fill snaps back, nothing is entered.
                store.fingerDown = true; store.demoPressing = true
                await wait(0.32)
                store.fingerDown = false; store.demoPressing = false
                await wait(1.0)
                // The full hold.
                store.fingerDown = true; store.demoPressing = true
                await wait(0.75)
                store.fingerDown = false; store.demoPressing = false
                await wait(0.2)
                store.finger = nil
            }
            await wait(3.5)
        default:
            break
        }
    }
}
#endif
