import SwiftUI
import MapKit

// §4 Properties: list (tab root), detail (pushed), add/edit (.large sheet).

enum PropsState: String { case list, twelve, twelveBottom, empty, limit, loading }

struct S2PropertiesList: View {
    var state: PropsState = .list
    var openDetail: S2Property? = nil
    /// Material participation without a grouping election: the 500h test is per property, so the
    /// row can say "212h of 500h". Otherwise it says "212h this year" and the house is a stage.
    var perPropertyGoal = false
    var showInfo = false
    @State private var infoShown = false
    var onUnlock: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dts
    @State private var path: [S2Property] = []
    @State private var query = ""

    private var props: [S2Property] {
        switch state {
        case .twelve, .twelveBottom: S2Data.twelve
        case .empty: []
        case .limit: [S2Data.pine]
        default: S2Data.four
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        if props.count > 8 { search }
                        switch state {
                        case .empty: empty
                        case .loading: loading
                        default: listCard
                        }
                        Color.clear.frame(height: 24).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
                .background(LHB.canvas.ignoresSafeArea())
                .overlay(alignment: .top) { TopEdgeFade() }
                .onAppear {
                    if state == .twelveBottom { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo("bottom", anchor: .bottom) } }
                    if let openDetail { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { path = [openDetail] } }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: S2Property.self) { S2PropertyDetail(p: $0) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            let stack = dts.isAccessibilitySize
            (stack ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .center))) {
                DisplayTitle(text: "Properties", reserve: stack ? 40 : 220)
                if !stack { Spacer() }
                if !props.isEmpty {
                    Button { } label: { Label("Add property", systemImage: "plus") }
                        .buttonStyle(S2Tinted())
                        .fixedSize()
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                if state == .loading {
                    PlaceholderBar(width: 170, height: 14).padding(.top, 4)
                } else if !props.isEmpty {
                    let total = props.reduce(0) { $0 + $1.hours }
                    HStack(spacing: 6) {
                        Text("\(props.count) \(props.count == 1 ? "rental" : "rentals") · \(Int(total))h this year")
                            .font(.subheadline).foregroundStyle(LHB.textSecondary)
                        if !perPropertyGoal {
                            Button { infoShown = true } label: {
                                Image(systemName: "info.circle").font(.subheadline).foregroundStyle(LHB.action)
                                    .frame(width: 32, height: 32).contentShape(Rectangle())
                            }
                            .accessibilityLabel("About the house stages")
                            .popover(isPresented: $infoShown, arrowEdge: .top) {
                                Text("Stages follow the 500-hour test for a single property.")
                                    .font(.subheadline).foregroundStyle(LHB.textPrimary)
                                    .padding(14).frame(width: 260)
                                    .presentationCompactAdaptation(.popover)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .onAppear { if showInfo { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { infoShown = true } } }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(LHB.textTertiary)
            Text("Search rentals").foregroundStyle(LHB.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 14).frame(minHeight: 44)
        .background(LHB.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(LHB.border, lineWidth: 0.5))
    }

    private var listCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(props.enumerated()), id: \.element.id) { i, p in
                NavigationLink(value: p) { S2PropertyRow(p: p, perPropertyGoal: perPropertyGoal) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") {}
                        Button("Delete", systemImage: "trash", role: .destructive) {}
                    }
                    .accessibilityIdentifier("props.row.\(p.id)")
                if i < props.count - 1 || state == .limit { InsetDivider(leading: 16 + 40 + 12) }
            }
            if state == .limit {
                LockedPreview(size: .row, line: "Free covers one rental.", keeps: "Pine Cabin keeps tracking. Nothing is lost.", onUnlock: onUnlock) {
                    HStack(spacing: 12) {
                        PropertySeal(monogram: "", size: 40, dashed: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your next rental").font(.body.weight(.semibold)).foregroundStyle(LHB.textPrimary)
                            Text("0h this year").font(.subheadline).foregroundStyle(LHB.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).frame(minHeight: 76)
                }
            }
        }
        .s2Card()
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "house").font(.system(size: 24, weight: .medium)).foregroundStyle(LHB.action)
                .frame(width: 56, height: 56).background(Circle().fill(LHB.actionSurface))
            Text("Add your first property").font(.headline).foregroundStyle(LHB.textPrimary)
            Text("Once we know where your rentals are, every hour you confirm goes up on the house.")
                .font(.subheadline).foregroundStyle(LHB.textSecondary).multilineTextAlignment(.center)
            Button("Add property") {}.buttonStyle(S2Primary()).padding(.top, 8)
        }
        .padding(20).frame(maxWidth: .infinity).s2Card()
    }

    private var loading: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 12) {
                    Circle().fill(LHB.border.opacity(0.5)).frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 8) {
                        PlaceholderBar(width: i == 1 ? 150 : 120, height: 14)
                        PlaceholderBar(width: 170, height: 10)
                    }
                    Spacer()
                    DraftingLoader(kind: .house, color: LHB.draftingInk).frame(width: 48, height: 48)
                }
                .padding(.horizontal, 16).frame(minHeight: 76)
                if i < 2 { InsetDivider(leading: 68) }
            }
        }
        .s2Card()
    }
}

struct S2PropertyRow: View {
    let p: S2Property
    var perPropertyGoal = false
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        let ax = dts.isAccessibilitySize
        (ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))) {
            PropertySeal(p, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name).font(.body.weight(.semibold)).foregroundStyle(LHB.textPrimary).lineLimit(ax ? 5 : 2)
                    .allowsTightening(true)
                    .multilineTextAlignment(.leading)
                Text("\(perPropertyGoal ? houseLine(p.hours) : "\(Int(p.hours))h this year") · \(p.kindMeta)").font(.subheadline).foregroundStyle(LHB.textSecondary)
                    .monospacedDigit()
            }
            if !ax { Spacer(minLength: 8) }
            if dts < .xxLarge { PropertyHouse(hours: p.hours, size: 48) }
            if !ax { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(LHB.textTertiary) }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(p.name), \(Int(p.hours)) hours this year of the 500 hour line, \(p.kindLabel)")
    }
}

// MARK: - Detail

struct S2PropertyDetail: View {
    let p: S2Property
    var scrolled = false

    private var kinds: [(S2Cat, Double)] { S2Data.kinds(for: p) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    hero
                    VStack(alignment: .leading, spacing: 10) {
                        S2Header("By kind of work")
                        VStack(spacing: 14) {
                            ForEach(kinds, id: \.0) { k in
                                HStack(spacing: 10) {
                                    ToolTile(cat: k.0, size: 24)
                                    Text(k.0.label).font(.subheadline).foregroundStyle(LHB.textPrimary).frame(width: 100, alignment: .leading)
                                    GeometryReader { g in
                                        Capsule().fill(k.0.ink.opacity(0.85)).frame(width: g.size.width * k.1 / max(1, kinds.map(\.1).max() ?? 1), height: 8)
                                            .frame(maxHeight: .infinity)
                                    }
                                    Text("\(Int(k.1))h").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(LHB.textPrimary)
                                        .frame(width: 40, alignment: .trailing)
                                }
                                .frame(height: 24)
                            }
                        }
                        .padding(16).s2Card()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        S2Header(title: "Recent") { SeeAll(label: "See all in Records") }
                        VStack(spacing: 0) {
                            ForEach(Array(S2Data.recent(for: p).enumerated()), id: \.element.id) { i, e in
                                HStack(spacing: 12) {
                                    ToolTile(cat: e.cat, size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(e.title).font(.body.weight(.semibold)).foregroundStyle(LHB.textPrimary)
                                        Text("\(e.date) · \(e.source)").font(.subheadline).foregroundStyle(LHB.textSecondary)
                                    }
                                    Spacer()
                                    Text(hm(e.hours)).font(.system(.body, design: .rounded, weight: .semibold)).monospacedDigit().foregroundStyle(LHB.textPrimary)
                                }
                                .padding(.horizontal, 16).frame(minHeight: 64)
                                if i < 2 { InsetDivider(leading: 64) }
                            }
                        }
                        .s2Card()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        S2Header("Details").id("details")
                        VStack(spacing: 0) {
                            detail("Address", p.address)
                            InsetDivider()
                            detail("How guests stay", p.longStays ? "Months or longer" : "A few nights at a time")
                            InsetDivider()
                            detail("Other names", p.aliases.isEmpty ? "None" : p.aliases.joined(separator: ", "))
                            InsetDivider()
                            detail("I live here", p.liveHere ? "Yes" : "No")
                            Map(initialPosition: .region(MKCoordinateRegion(center: .init(latitude: 34.1467, longitude: -118.1445), span: .init(latitudeDelta: 0.008, longitudeDelta: 0.008)))) {
                                Marker(p.name, coordinate: .init(latitude: 34.1467, longitude: -118.1445)).tint(LHB.brand)
                            }
                            .allowsHitTesting(false)
                            .frame(height: 140)
                            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20, style: .continuous))
                        }
                        .s2Card()
                    }
                    Color.clear.frame(height: 60)
                }
                .padding(.horizontal, 20).padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .background(LHB.canvas.ignoresSafeArea())
            .onAppear { if scrolled { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo("details", anchor: .top) } } }
        }
        .navigationTitle(p.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") {} } }
    }

    private func detail(_ l: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(l).foregroundStyle(LHB.textPrimary)
            Spacer()
            Text(v).foregroundStyle(LHB.textSecondary).multilineTextAlignment(.trailing)
        }
        .font(.body).padding(.horizontal, 16).padding(.vertical, 14).frame(minHeight: 52)
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            S2Paper(radius: 24)
            HouseArt(key: S2House.propertyKeyframe(p.hours))
                .frame(width: 150, height: 150)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 4).padding(.bottom, 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    PropertySeal(p, size: 32).environment(\.colorScheme, .dark)
                    Text("\(p.longStays ? "Long stays" : "A few nights") · \(p.address.split(separator: ",").first ?? "")")
                        .drafting().lineLimit(1).minimumScaleFactor(0.8)
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(p.hours))").roundedNumber(56).foregroundStyle(.white)
                    Text("h this year").font(.title3.weight(.medium)).foregroundStyle(LHB.onHeroSecondary)
                }
                .padding(.top, 4)
                Text("\(p.entries) entries · last on \(p.last)").font(.subheadline).foregroundStyle(LHB.onHeroSecondary)
                Text(houseStage(p.hours))
                    .font(.footnote.weight(.semibold)).foregroundStyle(p.hours >= 500 ? LHB.positiveOnHero : .white)
            }
            .padding(20)
        }
        .frame(height: 188)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Add / edit

enum EditState: String { case add, edit, editDelete }

struct S2PropertyEdit: View {
    var state: EditState = .add
    @State private var name = ""
    @State private var address = ""
    @State private var longStays = true
    @State private var aliases: [String] = []
    @State private var newAlias = ""
    @State private var liveHere = false
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    private var isEdit: Bool { state != .add }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Text(isEdit ? "Edit property" : "New property").font(.title2.weight(.semibold)).foregroundStyle(LHB.textPrimary)
                    Spacer(); GlassClose()
                }
                group {
                    field("Name", text: $name, placeholder: "Pine Cabin").focused($nameFocused)
                    InsetDivider()
                    field("Address", text: $address, placeholder: "Street, city")
                }
                VStack(alignment: .leading, spacing: 8) {
                    S2Header("How do guests stay?")
                    StaySegment(longStays: $longStays)
                    Text("This changes how hours are counted for this place.").font(.footnote).foregroundStyle(LHB.textSecondary).padding(.horizontal, 4)
                }
                VStack(alignment: .leading, spacing: 8) {
                    S2Header("Other names")
                    VStack(alignment: .leading, spacing: 12) {
                        if !aliases.isEmpty {
                            FlowChips(items: aliases) { a in withAnimation(.easeOut(duration: 0.18)) { aliases.removeAll { $0 == a } } }
                        }
                        HStack {
                            TextField("Add another name", text: $newAlias).foregroundStyle(LHB.textPrimary)
                            Button("Add") { if newAlias.count >= 3 { aliases.append(newAlias); newAlias = "" } }
                                .font(.body.weight(.semibold)).foregroundStyle(newAlias.count >= 3 ? LHB.action : LHB.textTertiary)
                                .frame(minHeight: 44)
                        }
                        .padding(.horizontal, 14).frame(minHeight: 48)
                        .background(LHB.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(16).background(LHB.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Text("The names you use for this place in your calendar, like “the cabin”. We use them to match events. Use at least 3 characters. You can add up to 10 other names.")
                        .font(.footnote).foregroundStyle(LHB.textSecondary).padding(.horizontal, 4)
                }
                group {
                    Toggle(isOn: $liveHere) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("I live here").font(.body).foregroundStyle(LHB.textPrimary)
                            Text("We won’t suggest time spent at home as work.").font(.subheadline).foregroundStyle(LHB.textSecondary)
                        }
                    }
                    .toggleStyle(S2Switch())
                    .padding(16)
                }
                if isEdit {
                    Button("Delete property", role: .destructive) { confirmDelete = true }
                        .font(.body).foregroundStyle(LHB.destructive)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(20)
        }
        .background(LHB.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button(isEdit ? "Save" : "Add property") {}.buttonStyle(S2Primary()).disabled(name.isEmpty)
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)
                .background(LinearGradient(stops: [.init(color: LHB.canvas.opacity(0), location: 0), .init(color: LHB.canvas, location: 0.14)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        }
        .alert("Delete Pine Cabin and its 41 entries?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its 41 entries and their photos are deleted too, on this iPhone and in iCloud. This can’t be undone.")
        }
        .onAppear {
            if isEdit {
                name = S2Data.pine.name; address = S2Data.pine.address; longStays = false
                aliases = ["Cabin", "Big Bear", "Ridge Rd place"]; liveHere = true
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { nameFocused = true }
            }
            if state == .editDelete { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { confirmDelete = true } }
        }
    }

    private func group<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 0) { c() }.background(LHB.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func field(_ l: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 12) {
            Text(l).foregroundStyle(LHB.textPrimary).frame(width: 76, alignment: .leading)
            TextField(placeholder, text: text).foregroundStyle(LHB.textPrimary)
        }
        .padding(.horizontal, 16).frame(minHeight: 52)
    }
}

struct StaySegment: View {
    @Binding var longStays: Bool
    var body: some View {
        HStack(spacing: 2) {
            seg("Months or longer", on: longStays) { longStays = true }
            seg("A few nights at a time", on: !longStays) { longStays = false }
        }
        .padding(3)
        .background(Capsule().fill(LHB.card))
        .overlay(Capsule().strokeBorder(LHB.border, lineWidth: 0.5))
    }
    private func seg(_ t: String, on: Bool, _ a: @escaping () -> Void) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { a() } } label: {
            Text(t).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
                .foregroundStyle(on ? LHB.onAction : LHB.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Capsule().fill(on ? LHB.action : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// 36pt alias chips with a 12pt xmark (44pt hit area).
struct FlowChips: View {
    let items: [String]
    var onDelete: (String) -> Void
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { a in
                HStack(spacing: 2) {
                    Text(a).font(.subheadline.weight(.medium)).foregroundStyle(LHB.textPrimary).padding(.leading, 14)
                    Button { onDelete(a) } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(LHB.textSecondary)
                            .frame(width: 32, height: 36).contentShape(Rectangle().inset(by: -6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(a)")
                }
                .frame(height: 36)
                .background(Capsule().fill(LHB.tertiary))
                .overlay(Capsule().strokeBorder(LHB.border, lineWidth: 0.5))
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x + z.width > w, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += z.width + spacing; rowH = max(rowH, z.height)
        }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, rowH: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x + z.width > b.maxX, x > b.minX { x = b.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += z.width + spacing; rowH = max(rowH, z.height)
        }
    }
}
