import SwiftUI

struct TodayView: View {
    @Environment(MockStore.self) private var store
    @Binding var showSettings: Bool
    var goInbox: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    HeroCard()
                    if store.hasProperties {
                        if store.pendingCount > 0 { ToConfirmBlock(goInbox: goInbox) }
                        MetricGrid()
                    } else {
                        NoPropertiesEmpty()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 120)
            }
            .background(LH.canvas)
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
        case .starting: .secondary
        case .onPace: LH.positive
        case .behind: LH.caution
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("2026 · REPS goal").eyebrow()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(fmt(store.hoursLogged))
                    .font(.system(size: 48, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: store.hoursLogged))
                    .animation(Motion.snappy(reduce), value: store.hoursLogged)
                Text("of \(Int(store.goal)) h")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)

            statusLine
                .padding(.top, 2)

            ProgressTrack(progress: progress, tick: store.hasProperties ? expected : nil, color: status == .starting ? LH.fill : statusColor)
                .padding(.top, 20)

            HStack {
                Text("\(fmt(max(store.goal - store.hoursLogged, 0))) h to go")
                    .contentTransition(.numericText(value: store.hoursLogged))
                Spacer()
                Text("By Dec 31")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.top, 10)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lhCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var statusLine: some View {
        switch status {
        case .starting:
            Label("Getting started", systemImage: "circle.dashed")
                .foregroundStyle(.secondary)
                .font(.body.weight(.medium))
        case .onPace:
            Label { Text("On pace · \(fmt(store.pace)) h ahead") } icon: {
                Image(systemName: "arrow.up.circle.fill")
            }
            .foregroundStyle(LH.positive)
            .font(.body.weight(.semibold))
        case .behind:
            Label { Text("Behind by \(fmt(-store.pace)) h") } icon: {
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
    var goInbox: () -> Void

    var body: some View {
        let top = Array(store.pending.prefix(3))
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("To confirm").eyebrow()
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
                        CompactSuggestionRow(s: s)
                        if idx < top.count - 1 {
                            Divider().padding(.leading, 64)
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
    }
}

struct CompactSuggestionRow: View {
    let s: Suggestion
    var body: some View {
        HStack(spacing: 12) {
            SourceTile(kind: s.kind, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Text(s.noun).fontWeight(.semibold)) \(s.joiner) \(Text(s.property).fontWeight(.semibold))")
                    .font(.body)
                    .lineLimit(2)
                Text("\(s.kind.label) · \(s.when)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Group {
                if let h = s.hours {
                    Text("\(fmt(h)) h")
                } else if let m = s.capMinutes {
                    Text("≤\(m / 60)h \(m % 60)m")
                } else {
                    Text("Add hours").foregroundStyle(LH.caution)
                }
            }
            .font(.body)
            .monospacedDigit()
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Metrics

struct MetricGrid: View {
    @Environment(MockStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This year").eyebrow().padding(.horizontal, 4)
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    MetricCard(symbol: "chart.pie", label: "50% rule", value: "64", unit: "%",
                               status: "Above 50%", statusSymbol: "checkmark.circle.fill", statusColor: LH.positive)
                    MetricCard(symbol: "calendar", label: "This week", value: "9.5", unit: "h",
                               status: "2 h more than last week", statusSymbol: nil, statusColor: .secondary,
                               bars: [1, 2, 0, 3.5, 1, 0, 2])
                }
                GridRow {
                    MetricCard(symbol: "person.2", label: "Spouse", value: "38.5", unit: "h",
                               status: "Counts if filing jointly", statusSymbol: nil, statusColor: .secondary)
                    MetricCard(symbol: "hourglass", label: "Days left", value: "74", unit: nil,
                               status: store.pace >= 0 ? "7 h a week keeps pace" : "8 h a week to catch up",
                               statusSymbol: nil, statusColor: .secondary)
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
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 28, weight: .semibold)).monospacedDigit()
                    if let unit { Text(unit).font(.title3).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 4)
                if let bars {
                    MiniBars(values: bars)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let statusSymbol { Image(systemName: statusSymbol) }
                Text(status).lineLimit(2, reservesSpace: true)
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
        EmptyStateView(symbol: "house", title: "Add your first property",
                       message: "Once we know where your rentals are, we'll start noticing the work you do for them.",
                       action: "Add property", actionSymbol: "plus")
            .padding(.top, 24)
    }
}

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String
    var action: String?
    var actionSymbol: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(LH.fill)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            Text(title)
                .font(.body.weight(.semibold))
                .padding(.top, 16)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
