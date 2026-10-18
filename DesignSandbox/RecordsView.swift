import SwiftUI

struct RecordsView: View {
    @Environment(MockStore.self) private var store
    @State private var query = ""
    @State private var showReport = false
    var goInbox: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(title: "2026", selected: true)
                            FilterChip(title: "Property", menu: true)
                            FilterChip(title: "Source", menu: true)
                            FilterChip(title: "Who", menu: true)
                        }
                        .padding(.horizontal, 16)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                .listSectionSpacing(8)

                ForEach(MockStore.records) { group in
                    Section {
                        ForEach(group.entries) { e in
                            RecordRow(e: e)
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                .alignmentGuide(.listRowSeparatorLeading) { _ in 56 }
                        }
                    } header: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(group.id).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                            Spacer()
                            Text("\(fmt(group.total)) h").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .textCase(nil)
                        .padding(.horizontal, -4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.bottom, 120, for: .scrollContent)
            .navigationTitle("Records")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search records")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Export") { showReport = true }
                        .fontWeight(.semibold)
                }
            }
            .navigationDestination(isPresented: $showReport) { ReportView() }
            .safeAreaInset(edge: .bottom) {
                if store.pendingCount > 0 {
                    AttentionPill(count: store.pendingCount, action: goInbox)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 74)
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
        HStack(spacing: 12) {
            SourceTile(kind: e.kind)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Text(e.title).fontWeight(.medium)) · \(e.property)")
                    .font(.body)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    StatusDot(color: e.kind.tint)
                    Text(e.status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(fmt(e.hours)) h").font(.body).monospacedDigit()
                Text(e.date).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 72)
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
                    Text(meta).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(fmt(hours)) h").font(.body).monospacedDigit()
                    Text("\(Int(share * 100))% of yours").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ProgressTrack(progress: share, tick: nil, color: LH.action, height: 6)
        }
        .padding(.vertical, 8)
    }
}
