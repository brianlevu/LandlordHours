import SwiftUI

struct InboxView: View {
    @Environment(MockStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var selected: Suggestion?
    var openDetail: String?

    private var groups: [(String, [Suggestion])] {
        var order: [String] = []
        var map: [String: [Suggestion]] = [:]
        for s in store.suggestions {
            if map[s.group] == nil { order.append(s.group) }
            map[s.group, default: []].append(s)
        }
        return order.map { ($0, map[$0]!) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.suggestions.isEmpty {
                    VStack {
                        Spacer()
                        EmptyStateView(symbol: "tray", art: .emptyInbox, title: "Nothing waiting",
                                       message: "We'll ask when something looks like rental work.")
                        Spacer()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .background(LH.canvas)
                } else {
                    list
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                if !store.suggestions.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Select") {}
                    }
                }
            }
        }
        .sheet(item: $selected) { s in
            SuggestionDetailSheet(suggestion: s) { hours in
                store.confirm(s.id, hours: hours, reduceMotion: reduce)
            } onDismissItem: {
                store.dismiss(s.id, reduceMotion: reduce)
            }
        }
        .sensoryFeedback(LHDirection.current == .inkwell ? .impact(flexibility: .rigid) : .success, trigger: store.confirmTick)
        .sensoryFeedback(.impact(weight: .light), trigger: store.dismissTick)
        .task {
            if let openDetail, let s = store.suggestions.first(where: { $0.id == openDetail }) {
                try? await Task.sleep(for: .milliseconds(350))
                selected = s
            }
        }
    }

    private var list: some View {
        List {
            Section {
                BackfillBanner()
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            }
            ForEach(groups, id: \.0) { title, items in
                Section {
                    ForEach(items) { s in
                        Button {
                            if s.state == .pending { selected = s }
                        } label: {
                            SuggestionRow(s: s)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("row-\(s.id)")
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 16))
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 72 }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if s.state == .pending {
                                Button {
                                    store.confirm(s.id, hours: s.hours ?? Double(s.capMinutes ?? 0) / 60, reduceMotion: reduce)
                                } label: {
                                    Label("Log", systemImage: "checkmark")
                                }
                                .tint(Color(uiColor: .systemGreen))
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.dismiss(s.id, reduceMotion: reduce)
                            } label: {
                                Label("Not work", systemImage: "xmark")
                            }
                            .tint(Color(uiColor: .systemGray))
                        }
                    }
                } header: {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(LH.secondaryText)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(20)
        .contentMargins(.bottom, 100, for: .scrollContent)
    }
}

struct BackfillBanner: View {
    @Environment(MockStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if LHDirection.current == .baseline {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 22))
                    .foregroundStyle(LH.action)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 40, height: 40)
                    .background(LH.actionWash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                DirectionArt(kind: .inboxBanner)
                    .frame(width: 64, height: 64)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("We found 14 things from the last 90 days.")
                    .font(.body.weight(.semibold))
                Text("Keep the ones that were work. Nothing is saved until you confirm.")
                    .font(.subheadline)
                    .foregroundStyle(LH.secondaryText)
                HStack(spacing: 16) {
                    stat(Double(store.pendingCount), "to confirm", text: "\(store.pendingCount)")
                    stat(store.hoursLogged, "logged", text: fmtDur(store.hoursLogged))
                }
                .padding(.top, 8)
            }
        }
    }

    private func stat(_ v: Double, _ label: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(text)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: v))
                .animation(Motion.snappy(reduce), value: v)
            Text(label).font(.subheadline).foregroundStyle(LH.secondaryText)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// Flighty result-row anatomy: big quantity on the left, eyebrow + bold-noun title + meta.
struct SuggestionRow: View {
    let s: Suggestion

    var body: some View {
        if LHDirection.current == .baseline { baselineBody } else { DirectionSuggestionRow(s: s) }
    }

    private var baselineBody: some View {
        HStack(alignment: .center, spacing: 8) {
            leading
                .frame(width: 64)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Label {
                        Text("\(s.kind.label) · \(s.when)")
                    } icon: {
                        Image(systemName: s.kind.symbol).foregroundStyle(s.kind.tint)
                    }
                    .labelStyle(TightLabel())
                    .lineLimit(1)
                    Spacer(minLength: 6)
                    trailing
                }
                .font(.subheadline)
                .foregroundStyle(LH.secondaryText)

                Text("\(Text(s.noun).fontWeight(.semibold)) \(s.joiner) \(Text(nbsp(s.property)).fontWeight(.semibold))")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                detailLine
                    .font(.subheadline)
            }
            .padding(.vertical, 12)
        }
        .frame(minHeight: 76)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var leading: some View {
        let h: Double? = s.hours ?? s.capMinutes.map { Double($0) / 60 }
        VStack(spacing: 0) {
            if s.hours == nil && s.capMinutes != nil {
                Text("Up to").font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(LH.secondaryText)
            }
            if let h {
                let (hh, mm) = fmtHM(h)
                if hh > 0 {
                    Text("\(hh)h").font(.system(size: 26, weight: .semibold)).monospacedDigit()
                        .contentTransition(.numericText(value: Double(hh)))
                }
                if mm > 0 {
                    Text("\(mm)m").font(.system(size: hh > 0 ? 17 : 26, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(hh > 0 ? LH.secondaryText : Color.primary)
                        .contentTransition(.numericText(value: Double(mm)))
                }
            } else {
                Text("—").font(.system(size: 26, weight: .semibold)).foregroundStyle(LH.secondaryText)
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        if s.state == .logged {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .symbolEffect(.bounce, value: s.state)
                Text("Logged")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(LH.positive)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    @ViewBuilder private var detailLine: some View {
        switch s.kind {
        case .receipt:
            Text("\(Text(s.detail).foregroundStyle(LH.secondaryText)) · \(Text("Needs hours").foregroundStyle(LH.caution).fontWeight(.medium))")
        case .location:
            HStack(spacing: 6) {
                Text("Time at the property").foregroundStyle(LH.secondaryText)
                BetaTag()
            }
        default:
            Text(s.detail).foregroundStyle(LH.secondaryText)
        }
    }
}

struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: - Direction row: hours | category icon | text | property mark

struct DirectionSuggestionRow: View {
    let s: Suggestion
    private let dir = LHDirection.current
    @State private var hop: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            hoursColumn.frame(width: 50)
            CategoryIcon(cat: s.category, size: dir == .inkwell ? 32 : 36)
                .offset(y: hop)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    SourceBadge(kind: s.kind, confirmed: s.state == .logged)
                    Text(dir == .inkwell ? s.when : "\(s.kind.label) · \(s.when)")
                        .lineLimit(1)
                }
                .font(.subheadline)
                .foregroundStyle(LH.secondaryText)
                Text("\(Text(s.noun).fontWeight(.semibold)) \(s.joiner) \(Text(nbsp(s.property)).fontWeight(.semibold))")
                    .font(.body)
                    .lineLimit(2)
                detail.font(.subheadline)
            }
            Spacer(minLength: 4)
            PropertyMark(prop: Prop.named(s.property), size: dir == .inkwell ? 30 : 36)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
        .onChange(of: s.state) { _, new in
            guard new == .logged, dir == .clayhouse, !reduce else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { hop = -6 }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55).delay(0.16)) { hop = 0 }
        }
    }

    @ViewBuilder private var hoursColumn: some View {
        let h: Double? = s.hours ?? s.capMinutes.map { Double($0) / 60 }
        VStack(spacing: 0) {
            if s.hours == nil && s.capMinutes != nil {
                Text("Up to").font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(LH.secondaryText)
            }
            if let h {
                let (hh, mm) = fmtHM(h)
                if hh > 0 {
                    Text("\(hh)h").font(.system(size: 24, weight: .semibold)).monospacedDigit()
                        .contentTransition(.numericText(value: Double(hh)))
                }
                if mm > 0 {
                    Text("\(mm)m").font(.system(size: hh > 0 ? 16 : 24, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(hh > 0 ? LH.secondaryText : Color.primary)
                }
            } else {
                Text("—").font(.system(size: 24, weight: .semibold)).foregroundStyle(LH.secondaryText)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if s.state == .logged {
            switch dir {
            case .inkwell:
                HStack(spacing: 8) {
                    Text("\(s.category.label) · \(Prop.named(s.property).seal)").foregroundStyle(LH.secondaryText)
                    LoggedStamp(animated: true)
                }
            case .waypoint:
                HStack(spacing: 4) {
                    PinDrop()
                    Text("Logged").fontWeight(.semibold).foregroundStyle(LH.positive)
                }
            default:
                Label("Logged", systemImage: "checkmark.circle.fill")
                    .labelStyle(TightLabel())
                    .fontWeight(.semibold)
                    .foregroundStyle(LH.positive)
                    .symbolEffect(.bounce, value: s.state)
            }
        } else {
            switch s.kind {
            case .receipt:
                Text("\(Text(s.detail).foregroundStyle(LH.secondaryText)) · \(Text("Needs hours").foregroundStyle(LH.caution).fontWeight(.medium))")
            case .location:
                HStack(spacing: 6) {
                    Text("Time at the property").foregroundStyle(LH.secondaryText)
                    BetaTag()
                }
            default:
                Text(s.category.label).foregroundStyle(s.category.tone)
                    .fontWeight(.medium)
            }
        }
    }
}

/// Waypoint's confirm: a green check pin drops onto the row.
struct PinDrop: View {
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white, LH.positive)
            .offset(y: landed || reduce ? 0 : -16)
            .opacity(landed ? 1 : 0)
            .onAppear {
                withAnimation(reduce ? .easeOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.86)) { landed = true }
            }
    }
}
