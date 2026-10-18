import SwiftUI

struct RecordsView: View {
    @Environment(MockStore.self) private var store
    @State private var showReport = false
    var goInbox: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                            Text("Search records")
                            Spacer()
                        }
                        .font(.body)
                        .foregroundStyle(LH.secondaryText)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(LH.tertiaryFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                FilterChip(title: "2026", selected: true)
                                FilterChip(title: "Property", menu: true)
                                FilterChip(title: "Source", menu: true)
                                FilterChip(title: "Who", menu: true)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                .listSectionSpacing(12)

                ForEach(MockStore.records) { group in
                    Section {
                        ForEach(group.entries) { e in
                            RecordRow(e: e)
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                .alignmentGuide(.listRowSeparatorLeading) { _ in LHDirection.current == .inkwell ? 44 : 52 }
                        }
                    } header: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(group.id).sectionLabel()
                            Spacer()
                            Text(fmtDur(group.total))
                                .font(.footnote.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(LH.secondaryText)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.bottom, 150, for: .scrollContent)
            .navigationTitle("Records")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Export") { showReport = true }
                        .fontWeight(.semibold)
                }
            }
            .navigationDestination(isPresented: $showReport) { ReportView() }
            .overlay(alignment: .bottom) {
                if store.pendingCount > 0 {
                    AttentionPill(count: store.pendingCount, action: goInbox)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 82)
                }
            }
        }
    }
}

struct FilterChip: View {
    var title: String
    var selected = false
    var menu = false
    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            if menu { Image(systemName: "chevron.down").font(.caption.weight(.semibold)) }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(selected ? LH.onAction : .primary)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(selected ? AnyShapeStyle(LH.action) : AnyShapeStyle(LH.card), in: Capsule())
        .overlay { if !selected { Capsule().strokeBorder(LH.separator, lineWidth: 0.5) } }
    }
}

struct RecordRow: View {
    let e: RecordEntry
    var body: some View {
        if LHDirection.current == .baseline { baselineBody } else { DirectionRecordRow(e: e) }
    }
    private var baselineBody: some View {
        HStack(alignment: .top, spacing: 12) {
            SourceTile(kind: e.kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title)
                    .font(.body)
                    .lineLimit(1)
                Text(e.property)
                    .font(.subheadline)
                    .foregroundStyle(LH.secondaryText)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    StatusDot(color: e.kind.tint)
                    Text(e.status)
                        .font(.subheadline)
                        .foregroundStyle(LH.secondaryText)
                        .lineLimit(1)
                }
                .padding(.top, 1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(fmtDur(e.hours)).font(.body).monospacedDigit()
                Text(e.date).font(.subheadline).foregroundStyle(LH.secondaryText)
            }
        }
        .padding(.vertical, 12)
    }
}

/// Mercury's floating "needs attention" pill.
struct AttentionPill: View {
    var count: Int
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "tray.full.fill").foregroundStyle(LH.caution)
                Text("\(count) things to confirm").foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(LH.caution)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background {
                Capsule().fill(LH.card)
                Capsule().fill(LH.cautionWash)
            }
            .overlay(Capsule().strokeBorder(LH.caution.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(Pressable())
    }
}

// MARK: - Properties tab (minimal so the tab isn't empty)

struct PropertiesView: View {
    @Environment(MockStore.self) private var store
    var body: some View {
        NavigationStack {
            List {
                if store.hasProperties {
                    Section {
                        PropertyRow(name: "Pine Cabin", meta: "Short-term · Big Bear Lake", hours: 128, share: 0.6)
                        PropertyRow(name: "Oak Street Duplex", meta: "Long-term · Riverside", hours: 84, share: 0.4)
                    } footer: {
                        Text("Your 750-hour goal counts all properties together.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Properties")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { } label: { Image(systemName: "plus") }
                }
            }
            .overlay {
                if !store.hasProperties {
                    EmptyStateView(symbol: "house", title: "No properties yet",
                                   message: "Add one to start noticing rental work.",
                                   action: "Add property", actionSymbol: "plus")
                }
            }
        }
    }
}

struct PropertyRow: View {
    var name: String
    var meta: String
    var hours: Double
    var share: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.body.weight(.semibold))
                    Text(meta).font(.subheadline).foregroundStyle(LH.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(fmtDur(hours)).font(.body).monospacedDigit()
                    Text("\(Int(share * 100))% of yours").font(.subheadline).foregroundStyle(LH.secondaryText)
                }
            }
            ProgressTrack(progress: share, tick: nil, color: LH.action, height: 6)
        }
        .padding(.vertical, 8)
    }
}

struct DirectionRecordRow: View {
    let e: RecordEntry
    private let dir = LHDirection.current
    private var confirmed: Bool { e.status.contains("confirmed") }
    private var sourceWord: String {
        switch e.kind {
        case .calendar: "From calendar"
        case .receipt: "From receipt"
        case .location: "From location"
        case .timer: "Timer"
        case .manual: "Added by you"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryIcon(cat: e.category, size: dir == .inkwell ? 32 : 40)
                .padding(.top, dir == .inkwell ? 4 : 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.title).font(.body).lineLimit(1)
                HStack(spacing: 6) {
                    if dir != .waypoint { PropertyMark(prop: Prop.named(e.property), size: 20) }
                    Text(e.property).font(.subheadline).foregroundStyle(LH.secondaryText).lineLimit(1)
                }
                HStack(spacing: 6) {
                    SourceBadge(kind: e.kind, confirmed: confirmed && dir == .waypoint)
                    if dir != .inkwell {
                        Text(confirmed ? "Confirmed" : sourceWord).font(.subheadline).foregroundStyle(LH.secondaryText).lineLimit(1)
                    }
                    if confirmed && dir == .inkwell { LoggedStamp() }
                }
                .padding(.top, 1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(fmtDur(e.hours)).font(.body).monospacedDigit()
                Text(e.date).font(.subheadline).foregroundStyle(LH.secondaryText)
            }
            if dir == .waypoint {
                MapTile(prop: Prop.named(e.property), size: 40)
            }
        }
        .padding(.vertical, 12)
    }
}
