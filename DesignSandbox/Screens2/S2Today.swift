import SwiftUI

// §2 Today, below the house. The hero is a static port of release/2.0 HouseHeroCard.

enum TodayState: String {
    case confirm3, confirmMore, caughtUp, caughtUpOff, noProperty, loading, timerRunning, draft, freeRecord, week, weekMid
}

struct S2Today: View {
    var state: TodayState = .confirm3
    var onPlus: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dynamicTypeSize) private var dts
    @State private var items: [S2Data.Suggestion] = []
    @State private var hours: Double = 212
    @State private var toast: String?
    @State private var bounceID: String?

    private var hasProperty: Bool { state != .noProperty }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.bottom, 20)
                    TodayHero(hours: hasProperty ? hours : 0, status: hasProperty ? "Behind by 388h" : nil)
                    if state == .timerRunning || state == .draft {
                        TimerTodayCard(running: state == .timerRunning).padding(.top, 12)
                    }
                    if hasProperty {
                        toConfirm.padding(.top, 32).id("confirm")
                        weekSection.padding(.top, 32).id("week")
                        pace.padding(.top, 12)
                        if state == .freeRecord {
                            yourRecord.padding(.top, 32).id("record")
                        }
                    } else {
                        noProperty.padding(.top, 24)
                    }
                    Color.clear.frame(height: 40 + 76)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .background(LHB.canvas.ignoresSafeArea())
            .onAppear {
                items = Array(S2Data.pending.prefix(state == .confirmMore ? 8 : 3))
                let target: String? = switch state {
                case .week, .weekMid: "week"
                case .freeRecord: "record"
                case .confirm3, .confirmMore, .caughtUp, .caughtUpOff, .loading: "confirm"
                default: nil
                }
                if let target {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { proxy.scrollTo(target, anchor: target == "confirm" ? .center : .top) }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                UndoToast(text: toast).padding(.bottom, 84).transition(.toast)
                    .accessibilityIdentifier("today.toast")
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("NE")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(LHB.textPrimary)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: Circle())
                    .accessibilityLabel("Settings")
                Spacer()
                GlassClose(systemName: "chart.bar", label: "Reports")
            }
            DisplayTitle(text: "Today’s work").padding(.top, 8)
            Text(hasProperty ? "\(Int(hours))h counted toward 750 hours this year." : "Nothing counted yet. Your house starts with one property.")
                .font(.subheadline).foregroundStyle(LHB.textSecondary)
                .contentTransition(.numericText(value: hours))
        }
    }

    // MARK: To confirm

    @ViewBuilder private var toConfirm: some View {
        VStack(alignment: .leading, spacing: 10) {
            S2Header(title: "To confirm") {
                if state == .confirm3 || state == .confirmMore, !items.isEmpty {
                    Text("\(state == .confirmMore ? 8 : items.count)")
                        .font(.footnote.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(LHB.action)
                        .padding(.horizontal, 8).frame(minHeight: 22)
                        .background(Capsule().fill(LHB.actionSurface))
                        .contentTransition(.numericText(value: Double(items.count)))
                    Spacer()
                    SeeAll()
                }
            }
            switch state {
            case .caughtUp, .caughtUpOff: caughtUp(off: state == .caughtUpOff)
            case .loading: loadingRows
            default:
                if items.isEmpty { caughtUp(off: false).transition(.opacity) } else { confirmCard }
            }
        }
    }

    private var confirmCard: some View {
        let shown = Array(items.prefix(3))
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                SwipeConfirmRow(s: s, onLog: { log(s) }, onDismiss: { dismiss(s) })
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))))
                if i < shown.count - 1 { InsetDivider(leading: 16 + 52 + 10 + 36 + 10) }
            }
            if state == .confirmMore {
                Button("Review all \(S2Data.pending.count)") {}
                    .buttonStyle(S2Tinted(fullWidth: true))
                    .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 16)
            }
        }
        .s2Card()
        .background(alignment: .bottom) {
            if state == .confirmMore {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LHB.card)
                    .scaleEffect(x: 0.96, y: 1, anchor: .bottom)
                    .opacity(0.6)
                    .offset(y: 6)
            }
        }
        .animation(S2Motion.collapse(reduce), value: items)
    }

    private func caughtUp(off: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle").font(.system(size: 28)).foregroundStyle(LHB.positive)
            Text("All caught up").font(.headline).foregroundStyle(LHB.textPrimary)
            Text(off ? "Turn on suggestions and we’ll spot the work for you." : "We’ll put new work here when your calendar looks like rental work.")
                .font(.subheadline).foregroundStyle(LHB.textSecondary)
                .multilineTextAlignment(.center)
            if off {
                Button("Turn on") {}.buttonStyle(S2Tinted()).padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .accessibilityElement(children: .combine)
    }

    private var loadingRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Looking through your calendar").font(.subheadline).foregroundStyle(LHB.textSecondary).padding(.horizontal, 4)
            DraftingLine(color: LHB.draftingInk, lineWidth: 1).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(0..<2, id: \.self) { i in
                    HStack(spacing: 10) {
                        PlaceholderBar(width: 36, height: 22).frame(width: 52)
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LHB.border.opacity(0.5)).frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 8) {
                            PlaceholderBar(width: 120, height: 10)
                            PlaceholderBar(width: i == 0 ? 170 : 140, height: 14)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).frame(minHeight: 76)
                    if i == 0 { InsetDivider(leading: 124) }
                }
            }
            .s2Card()
        }
    }

    private var noProperty: some View {
        VStack(spacing: 12) {
            Image(systemName: "house").font(.system(size: 24, weight: .medium)).foregroundStyle(LHB.action)
                .frame(width: 56, height: 56).background(Circle().fill(LHB.actionSurface))
            Text("Add your first property").font(.headline).foregroundStyle(LHB.textPrimary)
            Text("Once we know where your rentals are, every hour you confirm goes up on the house.")
                .font(.subheadline).foregroundStyle(LHB.textSecondary).multilineTextAlignment(.center)
            Button("Add property") {}.buttonStyle(S2Primary()).padding(.top, 8)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .s2Card()
    }

    // MARK: Week

    private var weekSection: some View {
        let mid = state == .weekMid
        let days: [Double?] = mid ? [1.5, 0, 3, 2, nil, nil, nil] : S2Data.week
        let todayIx = mid ? 3 : S2Data.todayIndex
        let total = days.compactMap { $0 }.reduce(0, +)
        return VStack(alignment: .leading, spacing: 10) {
            S2Header(title: "This week") {
                Text(hm(total)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(LHB.textPrimary)
            }
            WeekStrip(days: days, todayIndex: todayIx)
        }
    }

    private var pace: some View {
        let big = dts.isAccessibilitySize
        let layout = big ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            PaceCard(label: "50% rule", value: "Not checked yet", status: "Add your other work hours", tone: .neutral)
            PaceCard(label: "To finish by Dec 31", value: "53h a week", status: "Behind pace", tone: .caution)
        }
    }

    // MARK: Your record (free)

    private var yourRecord: some View {
        VStack(alignment: .leading, spacing: 10) {
            S2Header("Your record")
            LockedPreview(size: .card, line: "Your 212 hours, ready to export.", fold: 92, surface: LHB.card) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.richtext").font(.system(size: 20)).foregroundStyle(LHB.action)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your 2026 record").font(.headline).foregroundStyle(LHB.textPrimary)
                            Text("PDF and spreadsheet · 41 entries").font(.subheadline).foregroundStyle(LHB.textSecondary)
                        }
                    }
                    RecordPage(highlight: .none)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(LHB.border, lineWidth: 0.5))
                }
                .padding(16)
            }
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .s2Card()
        }
    }

    // MARK: Actions

    private func log(_ s: S2Data.Suggestion) {
        withAnimation(S2Motion.collapse(reduce)) { items.removeAll { $0.id == s.id } }
        withAnimation(reduce ? nil : .easeOut(duration: 0.6)) { hours += s.hours ?? 0 }
        show("Logged \(hm(s.hours ?? 0)) at \(s.place ?? "Pine Cabin")")
    }

    private func dismiss(_ s: S2Data.Suggestion) {
        withAnimation(S2Motion.collapse(reduce)) { items.removeAll { $0.id == s.id } }
        show("Marked not work")
    }

    private func show(_ t: String) {
        withAnimation { toast = t }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { withAnimation { if toast == t { toast = nil } } }
    }
}

// MARK: - Hero (static port of HouseHeroCard)

struct TodayHero: View {
    var hours: Double
    var status: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            S2Paper(radius: 24)
            GeometryReader { g in
                let houseSize = min(g.size.height * 0.84, g.size.width * 0.62)
                let center = CGPoint(x: g.size.width - 4 - houseSize * 0.44, y: g.size.height - 6 - houseSize * 0.417)
                let col = max(96, center.x - houseSize / 2 + houseSize * 0.04 - 24)
                HouseArt(key: S2House.keyframe(hours))
                    .frame(width: houseSize, height: houseSize)
                    .position(center)
                    .animation(.easeInOut(duration: 0.3), value: S2House.keyframe(hours))
                VStack(alignment: .leading, spacing: 2) {
                    Text("2026 · REPS goal").drafting()
                    Text("\(Int(hours))")
                        .roundedNumber(56)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: hours))
                        .padding(.top, 2)
                    Text("of 750h").font(.title3.weight(.medium)).foregroundStyle(LHB.onHeroSecondary)
                    Spacer(minLength: 8)
                    Group {
                        if let status {
                            (Text(Image(systemName: "exclamationmark.circle.fill")) + Text(" ") + Text(status))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Color(hex: 0xFFB454))
                        }
                        Text(hours < 1 ? "An empty lot" : hours < 100 ? "Breaking ground" : hours < 500 ? "Frame going up" : "Siding going up")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Text(hours < 100 ? "Foundation at 100h" : hours < 500 ? "Roof at 500h" : "Keys after 750h")
                            .font(.footnote).foregroundStyle(LHB.onHeroSecondary)
                    }
                    .frame(width: col, alignment: .leading)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: LHB.brand.opacity(0.25), radius: 16, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(hours)) of 750 hours. \(status ?? "")")
    }
}

// MARK: - Suggestion row (production SuggestionRowView anatomy) with swipes

struct S2SuggestionRow: View {
    let s: S2Data.Suggestion
    var meta: String? = nil
    var metaSymbol: String? = nil
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        Group {
            if dts.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) { hoursCol; ToolTile(cat: s.cat) }
                    text
                }
            } else {
                HStack(spacing: 10) {
                    hoursCol.frame(width: 52)
                    ToolTile(cat: s.cat)
                    text
                }
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 16)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var hoursCol: some View {
        if let h = s.hours {
            let t = Int((h * 60).rounded())
            VStack(spacing: 0) {
                if t / 60 > 0 { Text("\(t / 60)h").font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(LHB.textPrimary) }
                if t % 60 > 0 {
                    Text("\(t % 60)m").font(.system(t / 60 > 0 ? .callout : .title2, design: .rounded, weight: t / 60 > 0 ? .semibold : .bold))
                        .foregroundStyle(t / 60 > 0 ? LHB.textSecondary : LHB.textPrimary)
                }
            }
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        } else {
            Text("—").font(.system(.title2, design: .rounded, weight: .semibold)).foregroundStyle(LHB.textSecondary)
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: s.symbol).font(.system(size: 11, weight: .semibold))
                Text(s.source).lineLimit(1)
            }
            .font(.subheadline).foregroundStyle(LHB.textSecondary)
            (s.place.map { Text("\(Text(s.title).fontWeight(.semibold)) at \(Text($0).fontWeight(.semibold))") } ?? Text(s.title).fontWeight(.semibold))
                .font(.body).foregroundStyle(LHB.textPrimary).lineLimit(2)
            if let meta {
                HStack(spacing: 4) {
                    if let metaSymbol { Image(systemName: metaSymbol) }
                    Text(meta)
                }
                .font(.subheadline.weight(.medium)).foregroundStyle(LHB.textSecondary)
            } else if let b = s.badge {
                Text(b).font(.footnote.weight(.semibold)).foregroundStyle(LHB.caution)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(LHB.cautionSurface))
            } else if let c = s.cat {
                Text(c.label).font(.subheadline.weight(.medium)).foregroundStyle(c.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SwipeConfirmRow: View {
    let s: S2Data.Suggestion
    var onLog: () -> Void
    var onDismiss: () -> Void
    @State private var dx: CGFloat = 0
    @State private var checkPop = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    private let threshold: CGFloat = 96

    var body: some View {
        ZStack {
            HStack {
                actionCircle("checkmark", fill: LHB.positive, on: dx > threshold)
                    .scaleEffect(checkPop ? 1.15 : 1)
                    .opacity(dx > 8 ? 1 : 0)
                Spacer()
                actionCircle("xmark", fill: LHB.textTertiary, on: -dx > threshold)
                    .opacity(dx < -8 ? 1 : 0)
            }
            .padding(.horizontal, 20)
            S2SuggestionRow(s: s)
                .background(LHB.card)
                .offset(x: dx)
        }
        .clipped()
        .gesture(
            DragGesture(minimumDistance: 14)
                .onChanged { v in
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    dx = v.translation.width
                }
                .onEnded { v in
                    let projected = v.translation.width + (v.predictedEndTranslation.width - v.translation.width) * 0.3
                    if projected > threshold, s.hours != nil, s.place != nil {
                        withAnimation(reduce ? nil : .spring(response: 0.26, dampingFraction: 0.5)) { checkPop = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onLog() }
                    } else if projected < -threshold {
                        onDismiss()
                    } else {
                        withAnimation(S2Motion.snappy(reduce)) { dx = 0 }
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.row.\(s.id)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Log as suggested") { onLog() }
        .accessibilityAction(named: "Not work") { onDismiss() }
    }

    private func actionCircle(_ symbol: String, fill: Color, on: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(fill.opacity(on ? 1 : 0.55)))
    }
}

// MARK: - Week strip

struct WeekStrip: View {
    let days: [Double?]
    let todayIndex: Int
    @Environment(\.dynamicTypeSize) private var dts
    private let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let maxH = days.compactMap { $0 }.max() ?? 1
        let tallest = days.firstIndex { $0 == maxH && maxH > 0 }
        Group {
            if dts >= .xxLarge {
                VStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        HStack {
                            Text(names[i]).fontWeight(i == todayIndex ? .semibold : .regular)
                                .foregroundStyle(i == todayIndex ? LHB.action : LHB.textPrimary)
                            Spacer()
                            Text(days[i].map { $0 > 0 ? hm($0) : "—" } ?? "Not yet").foregroundStyle(LHB.textSecondary).monospacedDigit()
                        }
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        if i < 6 { InsetDivider() }
                    }
                }
                .s2Card()
            } else {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        VStack(spacing: 6) {
                            Spacer(minLength: 0)
                            if i == tallest {
                                Text(hm(maxH)).font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(LHB.textSecondary)
                            }
                            bar(days[i], maxH: maxH)
                            Text(S2Data.weekLetters[i])
                                .font(.caption.weight(i == todayIndex ? .semibold : .regular))
                                .foregroundStyle(i == todayIndex ? LHB.action : LHB.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(names[i]), \(days[i].map { $0 > 0 ? hm($0) : "no hours" } ?? "not yet")")
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 12)
                .frame(height: 112)
                .s2Card()
            }
        }
    }

    @ViewBuilder private func bar(_ v: Double?, maxH: Double) -> some View {
        if let v {
            if v > 0 {
                Capsule().fill(LHB.action).frame(width: 10, height: max(10, 56 * v / maxH))
            } else {
                Circle().fill(LHB.border).frame(width: 4, height: 4).padding(.top, 6)
            }
        } else {
            Capsule().strokeBorder(LHB.draftingInk.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                .frame(width: 10, height: 11)
        }
    }
}

// MARK: - Pace card

struct PaceCard: View {
    enum Tone { case neutral, caution, positive }
    let label: String
    let value: String
    let status: String
    var tone: Tone = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline).foregroundStyle(LHB.textSecondary)
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(LHB.textPrimary).lineLimit(2).minimumScaleFactor(0.8)
            HStack(spacing: 4) {
                if tone == .caution { Image(systemName: "exclamationmark.circle.fill") }
                Text(status)
            }
            .font(.footnote.weight(tone == .caution ? .semibold : .regular))
            .foregroundStyle(tone == .caution ? LHB.caution : LHB.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .s2Card()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Timer card on Today (§3d draft card)

struct TimerTodayCard: View {
    var running: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: running ? "timer" : "clock.badge.checkmark")
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(LHB.action)
                    .frame(width: 40, height: 40).background(Circle().fill(LHB.actionSurface))
                VStack(alignment: .leading, spacing: 3) {
                    if running {
                        HStack(spacing: 0) {
                            Text("Timer running · ").font(.headline)
                            Text("0:42").font(.system(.headline, design: .rounded)).monospacedDigit()
                        }
                        .foregroundStyle(LHB.textPrimary)
                        Text("Repairs at Pine Cabin · started 10:25").font(.subheadline).foregroundStyle(LHB.textSecondary)
                    } else {
                        Text("Timer ran 1h 12m at Oak Street Duplex").font(.headline).foregroundStyle(LHB.textPrimary)
                        Text("Started 10:25. It stopped when you switched profiles at 11:40.")
                            .font(.subheadline).foregroundStyle(LHB.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 16) {
                Button(running ? "Stop" : "Log 1h 12m") {}.buttonStyle(S2Tinted())
                if !running {
                    Button("Discard") {}.font(.subheadline).foregroundStyle(LHB.destructive)
                    Spacer()
                    Text("+1 more").font(.subheadline).foregroundStyle(LHB.textSecondary)
                }
            }
        }
        .padding(16)
        .s2Card()
    }
}
