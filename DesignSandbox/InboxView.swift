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
                        EmptyStateView(symbol: "tray", title: "Nothing waiting",
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
        .sensoryFeedback(.success, trigger: store.confirmTick)
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
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 22))
                .foregroundStyle(LH.action)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 40, height: 40)
                .background(LH.actionWash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("We found 14 things from the last 90 days.")
                    .font(.body.weight(.semibold))
                Text("Keep the ones that were work. Nothing is saved until you confirm.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    stat(Double(store.pendingCount), "to confirm")
                    stat(store.hoursLogged, "h logged in 2026")
                }
                .padding(.top, 8)
            }
        }
    }

    private func stat(_ v: Double, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(fmt(v))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: v))
                .animation(Motion.snappy(reduce), value: v)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// Flighty result-row anatomy: big quantity on the left, eyebrow + bold-noun title + meta.
struct SuggestionRow: View {
    let s: Suggestion

    var body: some View {
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
                .foregroundStyle(.secondary)

                Text("\(Text(s.noun).fontWeight(.semibold)) \(s.joiner) \(Text(s.property).fontWeight(.semibold))")
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
        VStack(spacing: 0) {
            if let m = s.capMinutes, s.hours == nil {
                Text("\(m)").font(.system(size: 28, weight: .semibold)).monospacedDigit()
                Text("Minutes").font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
            } else if let h = s.hours {
                Text(fmt(h)).font(.system(size: 28, weight: .semibold)).monospacedDigit()
                    .contentTransition(.numericText(value: h))
                Text(h == 1 ? "Hour" : "Hours").font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
            } else {
                Text("—").font(.system(size: 28, weight: .semibold)).foregroundStyle(.tertiary)
                Text("Hours").font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
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
        } else {
            Text("Suggested").transition(.opacity)
        }
    }

    @ViewBuilder private var detailLine: some View {
        switch s.kind {
        case .receipt:
            Text("\(Text(s.detail).foregroundStyle(.secondary)) · \(Text("Needs hours").foregroundStyle(LH.caution).fontWeight(.medium))")
        case .location:
            Text("\(Text(s.detail).foregroundStyle(.secondary))")
        default:
            Text(s.detail).foregroundStyle(.secondary)
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
