import SwiftUI

/// Today for a round-3 concept: concept hero, then the baseline "To confirm" and metrics.
struct ConceptTodayView: View {
    @Environment(MockStore.self) private var store
    var autoConfirm = false
    @State private var showSettings = false
    @State private var milestone = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    if store.hasProperties {
                        if store.pendingCount > 0 { ToConfirmBlock(goInbox: {}, maxRows: LHConcept.current == .blueprint ? 2 : 3) }
                        MetricGrid()
                    } else {
                        EmptyStateView(symbol: "house", title: "Add your first property",
                                       message: "Once we know where your rentals are, every hour you confirm goes up on the board.",
                                       action: "Add property", actionSymbol: "plus")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .background(LH.canvas)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("MA").font(.subheadline.weight(.semibold)).foregroundStyle(LH.action)
                        .frame(width: 36, height: 36).background(LH.actionWash, in: Circle())
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        // The tab bar insets the content, so nothing (like the Review pill) parks under it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selection: .constant(.today), inboxBadge: store.pendingCount) {}
                .padding(.bottom, 2)
        }
        .fullScreenCover(isPresented: $milestone) { BlueprintMilestone() }
        .task {
            guard autoConfirm else { return }
            try? await Task.sleep(for: .milliseconds(1600))
            store.confirm("plumber", hours: 2, reduceMotion: false)
        }
    }

    @ViewBuilder private var hero: some View {
        switch LHConcept.current {
        case .blueprint:
            if store.hasProperties { BlueprintHero(onMilestone: { milestone = true }) } else { BlueprintEmptyHero() }
        case .porchlight: PorchlightHero()
        case .tilework: TileworkHero()
        case .none: HeroCard()
        }
    }
}

/// Concept icons for list rows.
struct ConceptRowIcon: View {
    let cat: Category
    var size: CGFloat = 36
    var body: some View {
        switch LHConcept.current {
        case .tilework:
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [TW.glaze(cat).mix(with: .white, by: 0.2), TW.glaze(cat), TW.glaze(cat).mix(with: .black, by: 0.2)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay(Image(systemName: filled(BP.tool(cat))).font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(TW.glaze(cat).mix(with: .black, by: 0.55)))
                .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
        case .porchlight:
            Circle().fill(cat.tone).frame(width: size, height: size)
                .overlay(Image(systemName: filled(cat.symbol)).font(.system(size: size * 0.44, weight: .medium)).foregroundStyle(.white))
        default:
            ToolIcon(cat: cat, size: size)
        }
    }
}

struct ConceptPropertyThumb: View {
    let prop: Prop
    var size: CGFloat = 32
    var body: some View {
        switch LHConcept.current {
        case .porchlight:
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xF9A86E), Color(hex: 0xFBE3D0)], startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
                .overlay(PLHouse(kind: prop.key == "pine" ? .cabin : .duplex, paint: prop.key == "pine" ? PL.pine : PL.brick, lit: 2, night: false)
                    .padding(EdgeInsets(top: size * 0.16, leading: size * 0.12, bottom: 0, trailing: size * 0.12)))
                .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        case .tilework:
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFBF6EA), Color(hex: 0xE9DFC9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay(Image(systemName: prop.key == "pine" ? "house.lodge.fill" : "building.2.fill").font(.system(size: size * 0.46)).foregroundStyle(Color(hex: 0x9C8A66)))
        default:
            HouseTypeThumb(prop: prop, size: size)
        }
    }
}

/// Blueprint inbox row: baseline anatomy, tool leading, house-type thumbnail trailing.
struct ConceptSuggestionRow: View {
    let s: Suggestion
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(spacing: 0) {
                let h: Double? = s.hours ?? s.capMinutes.map { Double($0) / 60 }
                if s.hours == nil && s.capMinutes != nil {
                    Text("Up to").font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(LH.secondaryText)
                }
                if let h {
                    let (hh, mm) = fmtHM(h)
                    if hh > 0 { Text("\(hh)h").font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit() }
                    if mm > 0 { Text("\(mm)m").font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(LH.secondaryText) }
                } else {
                    Text("—").font(.system(size: 24, weight: .semibold)).foregroundStyle(LH.secondaryText)
                }
            }
            .frame(width: 48)
            ConceptRowIcon(cat: s.category, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: s.kind.badgeSymbol).font(.system(size: 11, weight: .semibold))
                    Text("\(s.kind.label) · \(s.when)").lineLimit(1).fixedSize(horizontal: false, vertical: true)
                        .minimumScaleFactor(0.9)
                }
                .font(.subheadline).foregroundStyle(LH.secondaryText)
                Text("\(Text(s.noun).fontWeight(.semibold)) \(s.joiner) \(Text(nbsp(s.property)).fontWeight(.semibold))")
                    .font(.body).lineLimit(2)
                if s.state == .logged {
                    Label("Logged", systemImage: "checkmark.circle.fill").labelStyle(TightLabel())
                        .font(.subheadline.weight(.semibold)).foregroundStyle(LH.positive)
                        .symbolEffect(.bounce, value: s.state)
                } else if s.kind == .receipt {
                    Text("\(Text(s.detail).foregroundStyle(LH.secondaryText)) · \(Text("Needs hours").foregroundStyle(LH.caution).fontWeight(.medium))")
                        .font(.subheadline)
                } else {
                    Text(s.category.label).font(.subheadline.weight(.medium)).foregroundStyle(BP.material(s.category))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            ConceptPropertyThumb(prop: Prop.named(s.property), size: 40)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
    }
}
