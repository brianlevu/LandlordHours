import SwiftUI
import LucideIcons

#if DEBUG
// MARK: - Shared house art for tiles and rows (real bp_house_k* assets, never a glyph)

/// The blueprint paper with the grid optional, so a quiet tile can drop it.
struct HomeProtoPaper: View {
    var cornerRadius: CGFloat
    var grid: Bool = true

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: "2447B5"), AppColors.brand, Color(hex: "18348C")],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Canvas { context, size in
                    let step: CGFloat = 22
                    var path = Path()
                    var x: CGFloat = 0
                    while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                    var y: CGFloat = 0
                    while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                    context.stroke(path, with: .color(Color(hex: AppColors.Hex.drafting).opacity(0.12)), lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .opacity(grid ? 1 : 0)
            }
            .accessibilityHidden(true)
    }
}

/// `.plain`: the full blueprint with grid, house at 1.18 (rows, focused tile, Check my goal).
/// `.quiet`: an unfocused tile: gridless paper at 82% over the tertiary surface, house a little smaller and calmer.
struct HomeProtoArt: View {
    enum Style { case plain, quiet }
    let size: CGFloat
    let keyframe: HouseKeyframe
    var style: Style = .plain
    /// The linework pass, only from 80pt up (the PropertyHouseTile rule).
    var lines = false
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var quiet: Bool { style == .quiet }

    var body: some View {
        let radius = size * 0.28
        ZStack {
            if quiet { RoundedRectangle(cornerRadius: radius, style: .continuous).fill(colors.backgroundTertiary) }
            HomeProtoPaper(cornerRadius: radius, grid: !quiet).opacity(quiet ? 0.82 : 1)
            ZStack {
                Image(decorative: keyframe.builtImageName).resizable().interpolation(.high).scaledToFit()
                if lines && size >= 80 {
                    HouseLineworkImage(name: keyframe.linesImageName).foregroundStyle(HouseTokens.drafting).opacity(0.8)
                }
            }
            .id(keyframe)
            .transition(.opacity)
            .aspectRatio(1, contentMode: .fit)
            .saturation(quiet ? 0.9 : 1)
            .scaleEffect(quiet ? 0.96 : 1.18)
            .offset(y: quiet ? 0 : -size * 0.02)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: keyframe)
        .accessibilityHidden(true)
    }
}

private func mono() -> Font { .system(.caption2, design: .monospaced).weight(.medium) }

// MARK: - One list row (See all, AX Today, Check my goal summary)

struct HomeProtoListRow<Right: View, Tag: View>: View {
    let keyframe: HouseKeyframe
    let name: String
    let plan: String
    var hairline: (fraction: Double, color: Color)? = nil
    @ViewBuilder var right: Right
    @ViewBuilder var tag: Tag
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HomeProtoArt(size: 56, keyframe: keyframe)
            textBlock
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(minHeight: 72, alignment: .top)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var textBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            if typeSize.isAccessibilitySize {
                nameText
                right
                planText
                tag
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    nameText
                    Spacer(minLength: 4)
                    right.fixedSize()
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    planText
                    Spacer(minLength: 4)
                    tag.fixedSize().layoutPriority(1)
                }
            }
            if let hairline {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(colors.border)
                        Capsule().fill(hairline.color).frame(width: max(2, g.size.width * min(1, hairline.fraction)))
                    }
                }
                .frame(height: 2).padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nameText: some View {
        Text(name).font(.headline).foregroundStyle(colors.textPrimary)
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1).truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
    }

    private var planText: some View {
        Text(plan).font(.footnote).foregroundStyle(colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The right-hand number: "64" in 15/600 rounded tabular, " of 100" in 15/400 secondary.
struct HomeProtoNumber: View {
    let main: String
    var rest: String? = nil
    var check = false
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 4) {
            (Text(main).font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(colors.textPrimary)
             + Text(rest.map { " " + $0 } ?? "").font(.subheadline).foregroundStyle(colors.textSecondary))
                .monospacedDigit()
            if check { LucideIcon(image: Lucide.check, size: 14).foregroundStyle(colors.positive) }
        }
    }
}

struct HomeProtoPaceTag: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.caption.weight(.semibold)).foregroundStyle(color)
        }
    }
}

/// One rental as a See-all row (also the large-text Today list).
struct HomeProtoRentalRow: View {
    let seed: HomeProtoSeed
    let r: HomeProtoRental
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    static func paceName(_ r: HomeProtoRental) -> String? {
        switch r.pace {
        case .behind: return String(localized: "behind", table: "HomeProto")
        case .onPace: return String(localized: "on pace", table: "HomeProto")
        case .done: return String(localized: "done", table: "HomeProto")
        case nil: return nil
        }
    }

    var body: some View {
        let whole = Int(r.hours.rounded(.down))
        var hairline: (Double, Color)?
        if case .own(let t) = r.target, r.hours < Double(t) { hairline = (r.hours / Double(t), HomeProtoPaceStyle.color(r, colors)) }
        let paceName = Self.paceName(r)
        return HomeProtoListRow(keyframe: HomeProtoStage.keyframe(for: r), name: r.name, plan: seed.planLine(r), hairline: hairline) {
            if case .own(let t) = r.target {
                if r.hours >= Double(t) { HomeProtoNumber(main: "\(whole)h", check: true) }
                else { HomeProtoNumber(main: "\(whole)", rest: String(localized: "of \(t)", table: "HomeProto")) }
            } else {
                HomeProtoNumber(main: "\(whole)h")
            }
        } tag: {
            if let paceName, r.pace != .done { HomeProtoPaceTag(text: paceName, color: HomeProtoPaceStyle.color(r, colors)) }
        }
    }
}

// MARK: - See all: a grouped list (Option A)

struct HomeProtoSeeAll: View {
    let seed: HomeProtoSeed
    let onPick: (HomeProtoFocus) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private func title(_ s: HomeProtoSeed.Section) -> String {
        switch s {
        case .needsAttention: return String(localized: "Needs attention", table: "HomeProto")
        case .onPace: return String(localized: "On pace", table: "HomeProto")
        case .done: return String(localized: "Done", table: "HomeProto")
        case .recordOnly: return String(localized: "Record only", table: "HomeProto")
        case .counts: return String(localized: "Counts toward \(seed.sharedTarget ?? 750)", table: "HomeProto")
        }
    }

    private func ink(_ s: HomeProtoSeed.Section) -> Color {
        switch s {
        case .needsAttention: return colors.caution
        case .onPace, .done: return colors.positive
        case .recordOnly: return colors.textTertiary
        case .counts: return colors.draftingInk
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("All rentals", tableName: "HomeProto")
                        .font(LHFont.fraunces(.largeTitle)).foregroundStyle(colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(Int(seed.totalHours.rounded(.down)))h logged this year · 2026", tableName: "HomeProto")
                        .font(.system(size: 15)).foregroundStyle(colors.textSecondary).monospacedDigit()
                        .padding(.top, 4)
                    chips.padding(.top, 16)
                    ForEach(HomeProtoSeed.Section.allCases, id: \.self) { s in
                        let list = seed.rentals(in: s)
                        if !list.isEmpty { section(s, list).id(s) }
                    }
                    addRow.padding(.top, 16)
                }
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 24)
            }
            .background(colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(String(localized: "Needs attention first", table: "HomeProto")) {}
                        Button(String(localized: "By name", table: "HomeProto")) {}
                        Button(String(localized: "By hours", table: "HomeProto")) {}
                    } label: {
                        LucideIcon(image: Lucide.ellipsis, size: 20).foregroundStyle(colors.action)
                    }
                    .accessibilityLabel(String(localized: "Sort", table: "HomeProto"))
                }
            }
        }
    }

    // MARK: Chips

    @ViewBuilder private var chips: some View {
        if typeSize.isAccessibilitySize {
            Text(chipLine).font(.system(size: 15, weight: .medium)).foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true).monospacedDigit()
        } else if let target = seed.sharedTarget {
            HStack(spacing: 12) {
                chip("\(Int(seed.totalHours.rounded(.down)))", String(localized: "of \(target)", table: "HomeProto"), nil)
                chip("\(seed.rentals.count)", String(localized: "rentals", table: "HomeProto"), nil)
                chip(String(localized: "on pace", table: "HomeProto"), String(localized: "pace", table: "HomeProto"), colors.positive, small: true)
            }
        } else {
            HStack(spacing: 12) {
                chip("\(seed.rentals.count)", String(localized: "rentals", table: "HomeProto"), nil)
                chip("\(seed.onPaceCount)", String(localized: "on pace", table: "HomeProto"), colors.positive)
                if seed.behindCount > 0 {
                    chip("\(seed.behindCount)", String(localized: "behind", table: "HomeProto"), colors.caution)
                } else {
                    chip("\(seed.rentals(in: .done).count)", String(localized: "done", table: "HomeProto"), colors.positive)
                }
            }
        }
    }

    private var chipLine: String {
        if let target = seed.sharedTarget {
            return String(localized: "\(Int(seed.totalHours)) of \(target) · \(seed.rentals.count) rentals · on pace", table: "HomeProto")
        }
        return String(localized: "\(seed.rentals.count) rentals · \(seed.onPaceCount) on pace · \(seed.behindCount) behind", table: "HomeProto")
    }

    private func chip(_ value: String, _ label: String, _ dot: Color?, small: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(small ? .title3 : .title2, design: .rounded).weight(.bold)).monospacedDigit()
                .foregroundStyle(colors.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 5) {
                Text(label).font(mono()).textCase(.uppercase).tracking(1.3).foregroundStyle(colors.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Sections

    private func section(_ s: HomeProtoSeed.Section, _ list: [HomeProtoRental]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title(s)).font(mono()).textCase(.uppercase).tracking(1.3).foregroundStyle(ink(s))
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Rectangle().fill(colors.border).frame(height: 0.5).padding(.leading, 84) }
                    row(r)
                }
            }
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.top, 24)
    }

    private func row(_ r: HomeProtoRental) -> some View {
        Button { onPick(.rental(r.id)) } label: { HomeProtoRentalRow(seed: seed, r: r) }
            .buttonStyle(.lhPressable)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(seed.spoken(r) + (HomeProtoRentalRow.paceName(r).map { ", " + $0 } ?? ""))
            .accessibilityHint(String(localized: "Shows this rental on Today", table: "HomeProto"))
    }

    private var addRow: some View {
        Button {} label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(colors.action)
                Text("Add a rental", tableName: "HomeProto").font(.system(size: 17, weight: .semibold)).foregroundStyle(colors.action)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(colors.actionSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.lhPressable)
    }
}

// MARK: - All 19 stages at tile size (clipping check)

struct HomeProtoStageSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(HouseKeyframe.allCases, id: \.self) { k in
                    VStack(spacing: 4) {
                        HomeProtoArt(size: 88, keyframe: k)
                        Text(k.rawValue.prefix(3)).font(mono()).foregroundStyle(colors.textSecondary)
                    }
                }
            }
            .padding(20)
        }
        .background(colors.background)
    }
}
#endif
