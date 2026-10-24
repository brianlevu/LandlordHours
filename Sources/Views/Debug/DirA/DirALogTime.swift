import SwiftUI

#if DEBUG
// MARK: - Log time (§1.12 secondary screen): opaque .large sheet on plaster

struct DALogTimeSheet: View {
    let demo: String?
    var scrollTo: String? = nil
    /// The Duo's in-pane Log time drops the mono date eyebrow (standard v2 retires mono eyebrows on screens).
    var showsEyebrow = true
    let onLog: (Double, String) -> Void
    let onClose: () -> Void

    @State private var quarters: Int = 6          // 1h 30m, filled from the note
    @State private var note = "Fixed the leaking kitchen faucet, then picked up a new cartridge."
    @State private var aiFilled = true
    @State private var who = 0
    @State private var sparkleDrawn = false
    private var env = DAEnv()
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(demo: String?, scrollTo: String? = nil, showsEyebrow: Bool = true, rental: String = "Santa Ray Ave", onLog: @escaping (Double, String) -> Void, onClose: @escaping () -> Void) {
        self.demo = demo; self.scrollTo = scrollTo; self.showsEyebrow = showsEyebrow; self.rental = rental; self.onLog = onLog; self.onClose = onClose
    }

    private var c: DAColors { env.c }
    private var hours: Double { Double(quarters) / 4 }
    /// The rental the time lands on (the Duo passes the house shown beside it).
    private let rental: String

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                noteField.padding(.top, 8)
                if aiFilled { aiRow.padding(.top, 8) }
                quickPicks.padding(.top, 20)
                value.padding(.top, 16)
                DATape(quarters: $quarters).padding(.top, 12).id("tape")
                values.padding(.top, 24)
                whoControl.padding(.top, 16)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            // Capture hook: -LHDirScroll tape brings the tape into view (AX3 frames).
            if scrollTo == "tape" { DADemo.after(0.6) { proxy.scrollTo("tape", anchor: .center) } }
        }
        }
        .safeAreaInset(edge: .bottom) { logButton }
        .background(c.sheet.ignoresSafeArea())
        .onAppear(perform: runDemo)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                if showsEyebrow { Text(DL("FRI, OCT 23")).font(DAFont.mono).tracking(DAFont.monoTracking).foregroundStyle(c.draftingInk) }
                Text(DL("Log time")).font(.title2.weight(.semibold)).foregroundStyle(c.ink).accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(c.ink)
                    .frame(width: 44, height: 44)
                    .background(c.surfaceInner, in: Circle())
            }
            .buttonStyle(DAPress())
            .accessibilityLabel(DL("Close"))
        }
        .frame(minHeight: 56)
        .padding(.top, 12)
    }

    private var noteField: some View {
        ZStack(alignment: .topTrailing) {
            Text(note)
                .font(.body).foregroundStyle(c.ink)
                .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                .padding(.leading, 14).padding(.trailing, 52).padding(.vertical, 12)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "mic").font(.body.weight(.medium)).foregroundStyle(c.action)
                .frame(width: 44, height: 44).padding(4)
                .accessibilityLabel(DL("Dictate"))
        }
        .background(c.surfaceInner, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(c.border, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(DL("Note: \(note)"))
    }

    /// AI fill row 44 (not a 13pt footnote): sparkles draw on, plain words, Undo.
    private var aiRow: some View {
        HStack(spacing: 8) {
            ZStack {
                if sparkleDrawn {
                    Image(systemName: "sparkles").foregroundStyle(c.action)
                        .daDrawOnTransition()
                }
            }
            .frame(width: 24, height: 24)
            .onAppear { DADemo.after(0.35) { withAnimation { sparkleDrawn = true } } }
            Text(DL("Filled from your note.")).font(.subheadline).foregroundStyle(c.textSecondary)
            Spacer()
            Button(DL("Undo")) { withAnimation(.easeOut(duration: 0.2)) { aiFilled = false } }
                .font(.subheadline.weight(.semibold)).foregroundStyle(c.action)
                .buttonStyle(DAPress()).frame(minHeight: 44)
        }
        .frame(minHeight: 44)
    }

    /// Quick picks above the tape (critic #4): the common logs stay one tap.
    private var quickPicks: some View {
        let picks: [(String, Int)] = [(DL("30m"), 2), (DL("1h"), 4), (DL("2h"), 8)]
        return HStack(spacing: 8) {
            ForEach(picks, id: \.1) { p in
                let selected = quarters == p.1
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0)) { quarters = p.1 }
                } label: {
                    Text(p.0).font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(selected ? c.onAction : c.ink)
                        .padding(.horizontal, 16)
                        .frame(minWidth: 64, minHeight: 44)
                        .background(selected ? c.action : c.surfaceInner, in: Capsule())
                        .overlay(Capsule().strokeBorder(selected ? .clear : c.border, lineWidth: 0.5))
                }
                .buttonStyle(DAPress())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    /// Fraunces 56 (opsz 96, wght 600), rolls with numericText.
    private var value: some View {
        Text(StdFormat.hours(hours))
            .font(DAFont.fraunces(size: 56, opsz: 96, wght: 600))
            .tracking(-1)
            .foregroundStyle(c.ink)
            .contentTransition(.numericText(value: hours))
            .animation(.spring(duration: 0.20, bounce: 0), value: quarters)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(DL("Hours: \(StdFormat.hours(hours))"))
    }

    private var values: some View {
        DASection {
            valueRow(DL("Rental"), rental, glyph: "house")
            DAHairline().padding(.leading, 16)
            valueRow(DL("Kind of work"), L("Repairs"), glyph: "wrench.and.screwdriver")
            DAHairline().padding(.leading, 16)
            valueRow(DL("Date"), DL("Today, Oct 23"), glyph: "calendar")
        }
    }

    private func valueRow(_ label: String, _ value: String, glyph: String) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Label { Text(label).foregroundStyle(c.ink) } icon: { Image(systemName: glyph).foregroundStyle(c.draftingInk) }
                .font(.body)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            HStack(spacing: 6) {
                Text(value).font(.body).foregroundStyle(c.textSecondary).multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(c.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(.vertical, typeSize.isAccessibilitySize ? 8 : 0)
    }

    private var whoControl: some View {
        Picker(DL("Who"), selection: $who) {
            Text(DL("Me")).tag(0)
            Text(DL("Spouse")).tag(1)
        }
        .pickerStyle(.segmented)
        .frame(minHeight: 36)
    }

    @ViewBuilder private var logButton: some View {
        let title = DL("Log \(StdFormat.hours(hours)) at \(rental)")
        Group {
            if #available(iOS 26.0, *) {
                Button { onLog(hours, rental) } label: {
                    Text(title).font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 40)
                        .contentTransition(.numericText(value: hours))
                }
                .buttonStyle(.glassProminent)
                .tint(c.action)
                .foregroundStyle(c.onAction)
                .controlSize(.large)
            } else {
                Button(title) { onLog(hours, rental) }.buttonStyle(DAPrimaryStyle())
            }
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
        .background(c.sheet)
        .accessibilityIdentifier("da.log")
    }

    /// Signature-control video: slow drag up to 3h, back to 1h 15m, then the quick picks.
    private func runDemo() {
        guard demo == "tape" else { return }
        var t = 2.0
        let path = Array(6...12) + Array((5...11).reversed())
        for q in path {
            let target = q
            DADemo.after(t) { withAnimation(.easeInOut(duration: 0.16)) { quarters = target } }
            t += 0.22
        }
        t += 0.8
        for q in [2, 8, 4] {
            let target = q
            DADemo.after(t) { withAnimation(.spring(duration: 0.35, bounce: 0)) { quarters = target } }
            t += 1.2
        }
    }
}

// MARK: - The tape measure (§1.6 signature control)

/// A ruler 72pt tall on plaster: a tick every 15m (1pt, 8pt), a major tick every hour (1.5pt, 16pt,
/// SF Mono 11 label), a fixed terracotta index hairline at centre; the tape scrolls under the finger
/// with view-aligned detents at 15m. `.selection` per 15m, `.alignment` on each whole hour.
/// 0–24h; 30pt per hour, so about 12h show across an iPhone. At AX3+ the tape stands vertical.
struct DATape: View {
    @Binding var quarters: Int
    @State private var position: Int?
    private var env = DAEnv()
    @Environment(\.dynamicTypeSize) private var typeSize

    init(quarters: Binding<Int>) { _quarters = quarters }

    static let hSlot: CGFloat = 7.5       // 15m, horizontal (30pt per hour, ~12h across)
    static let vSlot: CGFloat = 12        // 15m, vertical at AX3+ (48pt per hour)
    private var slot: CGFloat { vertical ? Self.vSlot : Self.hSlot }
    static let maxQuarters = 96          // 24h

    private var c: DAColors { env.c }
    private var vertical: Bool { typeSize >= .accessibility3 }

    var body: some View {
        GeometryReader { g in
            let span = vertical ? g.size.height : g.size.width
            ScrollView(vertical ? .vertical : .horizontal) {
                let layout = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
                layout {
                    ForEach(0...Self.maxQuarters, id: \.self) { q in tick(q).id(q) }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position, anchor: .center)
            .contentMargins(vertical ? .vertical : .horizontal, span / 2 - slot / 2, for: .scrollContent)
            .overlay { index(vertical: vertical) }
        }
        .frame(height: vertical ? 240 : 72)
        .background(c.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(c.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { position = quarters }
        .onChange(of: position) { _, p in if let p, p != quarters { quarters = p } }
        .onChange(of: quarters) { _, q in if position != q { withAnimation(.spring(duration: 0.35, bounce: 0)) { position = q } } }
        .sensoryFeedback(trigger: quarters) { _, new in new % 4 == 0 ? .alignment : .selection }
        .accessibilityElement()
        .accessibilityLabel(DL("Hours"))
        .accessibilityValue(StdFormat.hours(Double(quarters) / 4))
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: quarters = min(quarters + 1, Self.maxQuarters)
            case .decrement: quarters = max(quarters - 1, 0)
            @unknown default: break
            }
        }
    }

    private func tick(_ q: Int) -> some View {
        let major = q % 4 == 0
        return ZStack(alignment: vertical ? .leading : .top) {
            Color.clear
            if vertical {
                HStack(spacing: 6) {
                    Rectangle().fill(major ? c.ink : c.textSecondary).frame(width: major ? 40 : 20, height: major ? 1.5 : 1)
                    if major { label(q) }
                }
                .padding(.leading, 12)
            } else {
                VStack(spacing: 4) {
                    Rectangle().fill(major ? c.ink : c.textSecondary).frame(width: major ? 1.5 : 1, height: major ? 16 : 8)
                    if major { label(q) }
                }
                .padding(.top, 10)
            }
        }
        .frame(width: vertical ? nil : slot, height: vertical ? slot : nil)
        .frame(maxWidth: vertical ? .infinity : nil, maxHeight: vertical ? nil : .infinity)
    }

    private func label(_ q: Int) -> some View {
        Text(verbatim: "\(q / 4)")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(c.draftingInk)
            .fixedSize()
            .frame(width: vertical ? nil : slot)
    }

    private func index(vertical: Bool) -> some View {
        Group {
            if vertical {
                Rectangle().fill(c.terracotta).frame(height: 2).frame(maxHeight: .infinity)
            } else {
                Rectangle().fill(c.terracotta).frame(width: 2).frame(maxWidth: .infinity)
            }
        }
        .allowsHitTesting(false)
    }
}
#endif
