import SwiftUI

struct TodayView: View {
    @Environment(MockStore.self) private var store
    @Binding var showSettings: Bool
    var goInbox: () -> Void
    var scrollToMetrics = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    HeroCard()
                    if store.hasProperties {
                        if store.pendingCount > 0 { ToConfirmBlock(goInbox: goInbox) }
                        MetricGrid().id("metrics")
                    } else {
                        NoPropertiesEmpty()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 120)
            }
            .background(LH.canvas)
            .task {
                guard scrollToMetrics else { return }
                try? await Task.sleep(for: .milliseconds(400))
                proxy.scrollTo("metrics", anchor: .center)
            }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Text("MA")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(LH.action)
                            .frame(width: 36, height: 36)
                            .background(LH.actionWash, in: Circle())
                    }
                    .buttonStyle(Pressable())
                    .accessibilityLabel("Settings")
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
    }
}

// MARK: - Hero

struct HeroCard: View {
    @Environment(MockStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var progress: Double { min(store.hoursLogged / store.goal, 1) }
    private var expected: Double { store.expectedToday / store.goal }
    private enum Status { case starting, onPace, behind }
    private var status: Status {
        if !store.hasProperties || store.hoursLogged == 0 { return .starting }
        return store.pace >= 0 ? .onPace : .behind
    }
    private var statusColor: Color {
        switch status {
        case .starting: LH.secondaryText
        case .onPace: LH.positive
        case .behind: LH.caution
        }
    }

    private let dir = LHDirection.current

    var body: some View {
        Group {
            if dir == .clayhouse { clayHero } else { linearHero }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lhCard()
        .accessibilityElement(children: .combine)
    }

    private var bigNumber: some View {
        Text("\(Int(store.hoursLogged))")
            .font(.system(size: 48, weight: .semibold))
            .monospacedDigit()
            .contentTransition(.numericText(value: store.hoursLogged))
            .animation(Motion.snappy(reduce), value: store.hoursLogged)
    }

    private var footerRow: some View {
        HStack {
            Text("\(fmtDur(max(store.goal - store.hoursLogged, 0))) to go")
                .contentTransition(.numericText(value: store.hoursLogged))
            Spacer()
            Text("By Dec 31")
        }
        .font(.footnote)
        .foregroundStyle(LH.secondaryText)
        .monospacedDigit()
    }

    private var clayHero: some View {
        VStack(spacing: 0) {
            Text("2026 · REPS goal").eyebrow().frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                SegmentRing(progress: progress, expected: store.hasProperties ? expected : 0,
                            color: status == .starting ? LH.fill : statusColor)
                    .frame(width: 196, height: 196)
                VStack(spacing: 0) {
                    bigNumber
                    Text("of \(Int(store.goal))h").font(.title3).foregroundStyle(LH.secondaryText)
                }
            }
            .padding(.vertical, 18)
            statusLine
            footerRow.padding(.top, 14)
        }
    }

    @ViewBuilder private var progressGraphic: some View {
        let c = status == .starting ? LH.secondaryText : statusColor
        switch dir {
        case .waypoint:
            VStack(alignment: .leading, spacing: 12) {
                RouteLine(logged: store.hoursLogged, expected: store.hasProperties ? store.expectedToday : 0, color: c)
                HStack {
                    Text("Weeks").font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(LH.secondaryText)
                    Spacer()
                    Text("Jan → Dec").font(.caption2).foregroundStyle(LH.secondaryText)
                }
                HeatStrip(currentWeek: store.hasProperties ? 42 : 0)
            }
        case .inkwell:
            RuledStrip(logged: store.hoursLogged, expected: store.hasProperties ? store.expectedToday : 10)
        default:
            ProgressTrack(progress: progress, tick: store.hasProperties ? expected : nil, color: status == .starting ? LH.fill : statusColor)
        }
    }

    private var linearHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("2026 · REPS goal").eyebrow()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(store.hoursLogged))")
                    .font(.system(size: 48, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: store.hoursLogged))
                    .animation(Motion.snappy(reduce), value: store.hoursLogged)
                Text("of \(Int(store.goal))h")
                    .font(.title2)
                    .foregroundStyle(LH.secondaryText)
            }
            .padding(.top, 6)

            statusLine
                .padding(.top, 2)

            progressGraphic
                .padding(.top, 20)

            footerRow
                .padding(.top, 10)
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch status {
        case .starting:
            Label("Getting started", systemImage: "circle.dashed")
                .foregroundStyle(LH.secondaryText)
                .font(.body.weight(.medium))
        case .onPace:
            Label { Text("On pace · \(fmtDur(store.pace)) ahead") } icon: {
                Image(systemName: "arrow.up.circle.fill")
            }
            .foregroundStyle(LH.positive)
            .font(.body.weight(.semibold))
        case .behind:
            Label { Text("Behind by \(fmtDur(-store.pace))") } icon: {
                Image(systemName: "exclamationmark.circle.fill")
            }
            .foregroundStyle(LH.caution)
            .font(.body.weight(.semibold))
        }
    }
}

struct ProgressTrack: View {
    var progress: Double
    var tick: Double?
    var color: Color
    var height: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LH.fill)
                Capsule().fill(color)
                    .frame(width: max(geo.size.width * progress, progress > 0 ? height : 0))
                    .animation(Motion.collapse(reduce), value: progress)
                if let tick {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.75))
                        .frame(width: 2, height: height + 8)
                        .offset(x: geo.size.width * tick - 1)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - To confirm

struct ToConfirmBlock: View {
    @Environment(MockStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var selected: Suggestion?
    var goInbox: () -> Void
    var maxRows = 3

    var body: some View {
        let top = Array(store.pending.prefix(maxRows))
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("To confirm").sectionLabel()
                Spacer()
                Button(action: goInbox) {
                    HStack(spacing: 2) {
                        Text("See all")
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(LH.action)
                }
                .buttonStyle(Pressable())
            }
            .padding(.horizontal, 4)

            ZStack(alignment: .top) {
                // Deck: a second card peeking behind (Copilot)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LH.card)
                    .scaleEffect(x: 0.94, y: 1)
                    .opacity(store.pendingCount > 3 ? 0.6 : 0)
                    .offset(y: 8)

                VStack(spacing: 0) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { idx, s in
                        Button { selected = s } label: { CompactSuggestionRow(s: s) }
                            .buttonStyle(Pressable())
                            .accessibilityIdentifier("today-row-\(s.id)")
                        if idx < top.count - 1 {
                            Divider().padding(.leading, 48)
                        }
                    }
                    Button(action: goInbox) {
                        Text("Review \(store.pendingCount)")
                            .contentTransition(.numericText(value: Double(store.pendingCount)))
                    }
                    .buttonStyle(TintedCapsule())
                    .padding(.top, 12)
                }
                .padding(16)
                .lhCard()
            }
        }
        .sheet(item: $selected) { s in
            SuggestionDetailSheet(suggestion: s) { hours in
                store.confirm(s.id, hours: hours, reduceMotion: reduce)
            } onDismissItem: {
                store.dismiss(s.id, reduceMotion: reduce)
            }
        }
    }
}


struct CompactSuggestionRow: View {
    let s: Suggestion
    var body: some View {
        HStack(spacing: 12) {
            if LHConcept.current != .none {
                ConceptRowIcon(cat: s.category, size: 36)
            } else if LHDirection.current == .baseline {
                SourceTile(kind: s.kind, size: 36)
            } else {
                CategoryIcon(cat: s.category, size: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Text(s.noun).fontWeight(.semibold)) \(s.joiner) \(Text(nbsp(s.property)).fontWeight(.semibold))")
                    .font(.body)
                    .lineLimit(LHConcept.current == .none ? 2 : 1)
                Text("\(s.kind.label) · \(s.when)")
                    .font(.subheadline)
                    .foregroundStyle(LH.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Group {
                if let h = s.hours {
                    Text(fmtDur(h))
                } else if let m = s.capMinutes {
                    Text("≤" + fmtDur(Double(m) / 60))
                } else {
                    Text("Add hours").foregroundStyle(LH.caution)
                }
            }
            .font(.body)
            .monospacedDigit()
            .fixedSize()
            if LHConcept.current != .none {
                ConceptPropertyThumb(prop: Prop.named(s.property), size: 32)
            } else if LHDirection.current != .baseline {
                PropertyMark(prop: Prop.named(s.property), size: 32)
            }
        }
        .padding(.vertical, 10)
        .frame(height: LHConcept.current == .none ? nil : 62)
    }
}

// MARK: - Metrics

struct MetricGrid: View {
    @Environment(MockStore.self) private var store
    var body: some View {
        if LHDirection.current == .baseline { baseline } else { DirectionMetricGrid() }
    }
    private var baseline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This year").sectionLabel().padding(.horizontal, 4)
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    MetricCard(symbol: "chart.pie", label: "50% rule", value: "64", unit: "%",
                               status: "Above 50%", statusSymbol: "checkmark.circle.fill", statusColor: LH.positive)
                    MetricCard(symbol: "calendar", label: "This week", value: "9h 30m", unit: nil,
                               status: "2h more than last week", statusSymbol: nil, statusColor: LH.secondaryText,
                               bars: [1, 2, 0, 3.5, 1, 0, 2])
                }
                GridRow {
                    MetricCard(symbol: "person.2", label: "Spouse", value: "38h 30m", unit: nil,
                               status: "Counts if filing jointly", statusSymbol: nil, statusColor: LH.secondaryText)
                    MetricCard(symbol: "hourglass", label: "Days left", value: "74", unit: nil,
                               status: store.pace >= 0 ? "7h a week keeps pace" : "8h a week to catch up",
                               statusSymbol: nil, statusColor: LH.secondaryText)
                }
            }
        }
    }
}

struct MetricCard: View {
    var symbol: String
    var label: String
    var value: String
    var unit: String?
    var status: String
    var statusSymbol: String?
    var statusColor: Color
    var bars: [Double]? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(LH.secondaryText)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 28, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
                if let unit { Text(unit).font(.title3).foregroundStyle(LH.secondaryText) }
            }
            if let bars {
                MiniBars(values: bars).padding(.vertical, 2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let statusSymbol { Image(systemName: statusSymbol) }
                Text(status).lineLimit(2, reservesSpace: bars == nil)
            }
            .font(.subheadline.weight(statusSymbol == nil ? .regular : .medium))
            .foregroundStyle(statusColor)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lhCard()
    }
}

struct MiniBars: View {
    var values: [Double]
    var body: some View {
        let m = values.max() ?? 1
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(values.indices, id: \.self) { i in
                Capsule()
                    .fill(i == 3 ? LH.action : LH.fill)
                    .frame(width: 5, height: max(4, 26 * values[i] / m))
            }
        }
        .frame(height: 26, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

// MARK: - Empty

struct NoPropertiesEmpty: View {
    var body: some View {
        EmptyStateView(symbol: "house", art: .emptyToday, title: "Add your first property",
                       message: "Once we know where your rentals are, we'll start noticing the work you do for them.",
                       action: "Add property", actionSymbol: "plus")
            .padding(.top, 24)
    }
}

struct EmptyStateView: View {
    var symbol: String
    var art: ArtKind? = nil
    var title: String
    var message: String
    var action: String?
    var actionSymbol: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            if let art, LHDirection.current != .baseline {
                DirectionArt(kind: art)
                    .frame(width: 170, height: 140)
                    .padding(.bottom, 4)
            } else {
                Circle()
                    .fill(LH.fill)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(LH.secondaryText)
                    }
            }
            Text(title)
                .font(.body.weight(.semibold))
                .padding(.top, 16)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(LH.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
                .padding(.top, 4)
            if let action {
                Button {} label: {
                    Label(action, systemImage: actionSymbol ?? "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(LH.card, in: Capsule())
                        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.08), radius: 8, y: 3)
                }
                .buttonStyle(Pressable())
                .padding(.top, 20)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Direction metric cards

struct DirectionMetricGrid: View {
    @Environment(MockStore.self) private var store
    private let dir = LHDirection.current
    private let week: [Double] = [1, 2, 0, 3.5, 1, 0, 2]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This year").sectionLabel().padding(.horizontal, 4)
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    card("chart.pie", "50% rule") {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("64").font(.system(size: 28, weight: .semibold)).monospacedDigit()
                            Text("%").font(.title3).foregroundStyle(LH.secondaryText)
                        }
                        fiftyGraphic
                        Label("Above 50%", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium)).foregroundStyle(LH.positive)
                    }
                    card("calendar", "This week") {
                        Text("9h 30m").font(.system(size: 28, weight: .semibold)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.8)
                        weekGraphic
                        Text("2h more than last week").font(.subheadline).foregroundStyle(LH.secondaryText)
                    }
                }
                GridRow {
                    card("person.2", "Spouse") {
                        HStack(alignment: .center) {
                            Text("38h 30m").font(.system(size: 28, weight: .semibold)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.7)
                            if dir == .clayhouse { Spacer(minLength: 4); DualRing(outer: 173.5 / 750, inner: 38.5 / 750) }
                        }
                        spouseGraphic
                        Text("Counts if filing jointly").font(.subheadline).foregroundStyle(LH.secondaryText)
                    }
                    card("hourglass", "Days left") {
                        Text("74").font(.system(size: 28, weight: .semibold)).monospacedDigit()
                        if dir == .inkwell {
                            TallyMarks(count: 12, color: Ink.graphite)
                        }
                        Text(store.pace >= 0 ? "7h a week keeps pace" : "8h a week to catch up")
                            .font(.subheadline).foregroundStyle(LH.secondaryText)
                    }
                }
            }
        }
    }

    @ViewBuilder private var fiftyGraphic: some View {
        switch dir {
        case .waypoint: TwoLaneBar(share: 0.64).padding(.vertical, 4)
        case .clayhouse: HalfGauge(value: 0.64).frame(maxWidth: .infinity, alignment: .leading)
        default:
            HStack(spacing: 8) {
                TallyMarks(count: 13, color: LH.action)
                Text(":").font(.headline).foregroundStyle(LH.secondaryText)
                TallyMarks(count: 7, color: Ink.graphite)
            }
        }
    }

    @ViewBuilder private var weekGraphic: some View {
        switch dir {
        case .waypoint: MiniBars(values: week).padding(.vertical, 2)
        case .clayhouse: Pebbles(values: week).padding(.vertical, 4)
        default:
            HStack(alignment: .bottom, spacing: 7) {
                ForEach(week.indices, id: \.self) { i in
                    VStack(spacing: 2) {
                        TallyMarks(count: Int(week[i].rounded(.up)), color: Ink.ink, height: 10)
                            .frame(height: 10)
                        Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(.system(size: 9, weight: .medium)).foregroundStyle(LH.secondaryText)
                    }
                }
            }
        }
    }

    @ViewBuilder private var spouseGraphic: some View {
        switch dir {
        case .waypoint: SpouseRoute(me: 173.5, spouse: 38.5).padding(.vertical, 4)
        case .clayhouse: EmptyView()
        default:
            VStack(alignment: .leading, spacing: 4) {
                TallyMarks(count: 17, color: LH.action, height: 10)
                TallyMarks(count: 4, color: Ink.rose, height: 10)
            }
        }
    }

    private func card<C: View>(_ symbol: String, _ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(LH.secondaryText)
                .lineLimit(1)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .lhCard()
    }
}
