import SwiftUI
import LucideIcons

// MARK: - Today's row of rentals (2.1, option E)
//
// Under the hero, one horizontally swipeable row of tiles: "All rentals" first when the profile
// has one shared total, then every rental in the Properties order, "See all" at six or more, and
// a dashed "Add" tile. The focused tile shows the full house on blueprint paper; the others a
// flat silhouette (with a progress bar when the rental has its own target). At accessibility
// text sizes the row becomes a list of up to three rows plus "See all N rentals".
// The rules (which tiles, words, stages) live in HomeRentalsLogic.swift.

/// The tile's house: the full keyframe on blueprint paper when focused, a flat silhouette otherwise.
struct HomeTileArt: View {
    let size: CGFloat
    let full: Bool
    let keyframe: HouseKeyframe
    /// Progress to the tile's own target; nil: no bar.
    let fraction: Double?
    var checked = false
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ZStack {
            if full {
                InboxBlueprintPaper(cornerRadius: size * 0.28)
                Image(decorative: keyframe.builtImageName)
                    .resizable().interpolation(.high).scaledToFit()
                    .scaleEffect(1.18).offset(y: -size * 0.02)
            } else {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(colors.backgroundTertiary)
                HomeHouseSilhouette()
                    .fill(colors.draftingInk, style: FillStyle(eoFill: true))
                    .frame(width: size * 0.5, height: size * 0.5)
                    .offset(y: -size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .overlay(alignment: .bottom) {
            if let fraction, !full {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(colors.border)
                        Capsule().fill(colors.action).frame(width: max(3, g.size.width * min(1, fraction)))
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, size * 0.18).padding(.bottom, size * 0.1)
            }
        }
        .overlay(alignment: .topTrailing) {
            if checked {
                ZStack {
                    Circle().fill(colors.action)
                    LucideIcon(image: Lucide.check, size: 12).foregroundStyle(colors.onAction)
                }
                .frame(width: 22, height: 22).offset(x: 6, y: -6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A flat house, one colour: the quiet stand-in for a rental that isn't focused.
struct HomeHouseSilhouette: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        p.move(to: pt(0.5, 0.06)); p.addLine(to: pt(0.96, 0.46)); p.addLine(to: pt(0.04, 0.46)); p.closeSubpath()
        p.addRect(CGRect(x: r.minX + r.width * 0.16, y: r.minY + r.height * 0.44, width: r.width * 0.68, height: r.height * 0.5))
        p.addRect(CGRect(x: r.minX + r.width * 0.43, y: r.minY + r.height * 0.66, width: r.width * 0.14, height: r.height * 0.28))
        return p
    }
}

struct HomeRentalRow: View {
    let rentals: HomeRentals
    let focus: TodayFocusChoice
    let selection: HomeSelection
    var onSelect: (TodayFocusChoice) -> Void
    var onToggleSum: () -> Void
    var onSeeAll: () -> Void
    var onAdd: () -> Void
    /// DEBUG autoplay: scroll the row to this tile id.
    var scrollRequest: String? = nil

    @Namespace private var ring
    @State private var rowWidth: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var tileWidth: CGFloat { HomeLayout.tileWidth(rowWidth: rowWidth) }
    private var tap: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 1.0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if HomeLayout.usesList(isAccessibilitySize: typeSize.isAccessibilitySize) { list } else { tiles }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.rentals")
    }

    // MARK: Header

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center) { headerText; Spacer(minLength: 8); addUpButton }
            VStack(alignment: .leading, spacing: 6) { headerText; addUpButton }
        }
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Your rentals", tableName: "Home")
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .textCase(.uppercase).tracking(1.3)
                .foregroundStyle(colors.draftingInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("today.rentals.header")
            Group {
                if selection.summing {
                    Text("Tap rentals to add them up", tableName: "Home")
                } else {
                    Text("\(OnbFormat.hours(rentals.loggedHours)) logged this year", tableName: "Home")
                }
            }
            .font(.footnote.weight(.medium)).monospacedDigit()
            .foregroundStyle(colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("today.rentals.total")
        }
    }

    private var addUpButton: some View {
        Button(action: onToggleSum) {
            Text(selection.summing ? String(localized: "Done", table: "Home") : String(localized: "Add up rentals", table: "Home"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selection.summing ? colors.onAction : colors.action)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 7).frame(minHeight: 34)
                .background(Capsule().fill(selection.summing ? colors.action : colors.actionSurface))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.lhPressable)
        .accessibilityHint(selection.summing ? "" : String(localized: "Then tap rentals to add their hours together", table: "Home"))
        .accessibilityIdentifier("today.rentals.addUp")
    }

    // MARK: Row

    private var tiles: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(rentals.tiles) { tile in tileButton(tile) }
                    if rentals.showsSeeAll { seeAllTile }
                    addTile
                }
                .padding(.vertical, 4).padding(.horizontal, 2)
            }
            .scrollClipDisabled()
            // Opens on the focus, or on the first rental picked when it starts adding up.
            .onAppear { proxy.scrollTo(selection.summed.first.map(TodayFocusChoice.rental) ?? focus, anchor: .center) }
            .onChange(of: focus) { _, f in withAnimation(tap) { proxy.scrollTo(f, anchor: .center) } }
            .onChange(of: selection.summed.first) { _, id in
                guard let id else { return }
                withAnimation(tap) { proxy.scrollTo(TodayFocusChoice.rental(id), anchor: .center) }
            }
            .onChange(of: scrollRequest) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.6)) { proxy.scrollTo(id, anchor: .trailing) }
            }
        }
    }

    private func tileButton(_ tile: HomeRentalTile) -> some View {
        let selected = selection.isSelected(tile.focus, focus: focus)
        let picked = selection.isPicked(tile.focus)
        let art = tileWidth - 20
        return Button { onSelect(tile.focus) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HomeTileArt(size: art, full: selection.showsFullHouse(tile.focus, focus: focus), keyframe: tile.keyframe,
                            fraction: tile.fraction, checked: picked)
                Text(tile.name).font(.footnote.weight(.semibold)).foregroundStyle(colors.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(tile.hoursLine).font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                Text(tile.tileLine).font(.caption2).foregroundStyle(colors.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: art, alignment: .leading)
            .padding(10)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(colors.action, lineWidth: 2)
                        .matchedGeometryEffect(id: selection.summing ? "sum-\(tile.name)" : "ring", in: ring)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.lhPressable)
        .id(tile.focus)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.spoken(selected: selected && !selection.summing, picked: picked))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(Self.identifier(tile))
    }

    static func identifier(_ tile: HomeRentalTile) -> String {
        tile.isAll ? "today.rentals.tile.all" : "today.rentals.tile.\(tile.name)"
    }

    private var seeAllTile: some View {
        Button(action: onSeeAll) {
            VStack(spacing: 8) {
                LucideIcon(image: Lucide.layoutGrid, size: 24).foregroundStyle(colors.action)
                Text("See all", tableName: "Home").font(.footnote.weight(.semibold)).foregroundStyle(colors.action)
                Text("\(rentals.rentalCount) rentals", tableName: "Home").font(.caption2).foregroundStyle(colors.textSecondary)
            }
            .frame(width: 84, height: tileWidth + 36)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.lhPressable)
        .id("seeall")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "See all \(rentals.rentalCount) rentals", table: "Home"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("today.rentals.seeAll")
    }

    private var addTile: some View {
        Button(action: onAdd) {
            VStack(spacing: 8) {
                LucideIcon(image: Lucide.circlePlus, size: 24).foregroundStyle(colors.action)
                Text("Add", tableName: "Home").font(.footnote.weight(.semibold)).foregroundStyle(colors.action)
            }
            .frame(width: 64, height: tileWidth + 36)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(colors.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.lhPressable)
        .id("add")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Add a rental", table: "Home"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("today.rentals.add")
    }

    // MARK: Large text: a list instead of a row

    private var list: some View {
        let shown = Array(rentals.tiles.prefix(HomeLayout.listLimit))
        return VStack(spacing: 8) {
            ForEach(shown) { tile in listRow(tile) }
            if rentals.tiles.count > HomeLayout.listLimit {
                Button(action: onSeeAll) {
                    Text("See all \(rentals.rentalCount) rentals", tableName: "Home")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(colors.action)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.lhPressable)
                .accessibilityIdentifier("today.rentals.seeAll")
            }
            Button(action: onAdd) {
                Text("Add a rental", tableName: "Home")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(colors.action)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.lhPressable)
            .accessibilityIdentifier("today.rentals.add")
        }
    }

    private func listRow(_ tile: HomeRentalTile) -> some View {
        let selected = selection.isSelected(tile.focus, focus: focus)
        let picked = selection.isPicked(tile.focus)
        return Button { onSelect(tile.focus) } label: {
            HStack(spacing: 12) {
                HomeTileArt(size: 56, full: selection.showsFullHouse(tile.focus, focus: focus), keyframe: tile.keyframe,
                            fraction: tile.fraction, checked: picked)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.name).font(.headline).foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(localized: "\(tile.hoursLine) · \(tile.tileLine)", table: "Home"))
                        .font(.subheadline).foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { if selected { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(colors.action, lineWidth: 2) } }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.lhPressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.spoken(selected: selected && !selection.summing, picked: picked))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(Self.identifier(tile))
    }
}

// MARK: - See all: a grid of every house

struct HomeGridSheet: View {
    let rentals: HomeRentals
    let focus: TodayFocusChoice
    let onPick: (TodayFocusChoice) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) { title; Spacer(); total }
                        VStack(alignment: .leading, spacing: 4) { title; total }
                    }
                    .padding(.top, 24)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 140), spacing: 12)], spacing: 12) {
                        ForEach(rentals.tiles) { tile in cell(tile) }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("today.rentals.grid")
    }

    private var title: some View {
        Text("All rentals", tableName: "Home").font(.title2.weight(.semibold)).foregroundStyle(colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var total: some View {
        Text("\(OnbFormat.hours(rentals.loggedHours)) logged this year", tableName: "Home")
            .font(.footnote.weight(.medium)).foregroundStyle(colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func cell(_ tile: HomeRentalTile) -> some View {
        Button { onPick(tile.focus) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HomeTileArt(size: 88, full: true, keyframe: tile.keyframe, fraction: nil)
                Text(tile.name).font(.subheadline.weight(.semibold)).foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tile.hoursLine).font(.footnote.weight(.medium)).monospacedDigit().foregroundStyle(colors.textPrimary)
                Text(tile.tileLine).font(.caption).foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { if focus == tile.focus { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(colors.action, lineWidth: 2) } }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.lhPressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.spoken(selected: focus == tile.focus))
        .accessibilityAddTraits(focus == tile.focus ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("today.rentals.grid.\(tile.isAll ? "all" : tile.name)")
    }
}
