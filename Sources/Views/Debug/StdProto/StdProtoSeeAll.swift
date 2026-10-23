import SwiftUI

#if DEBUG
// MARK: - See all: one grouped list, LHRow.Browse with the 36pt house tile

struct StdSeeAllScreen: View {
    let seed: StdSeed
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    private var r: HomeProtoSeed { seed.rentals }

    private func title(_ s: HomeProtoSeed.Section) -> String {
        switch s {
        case .needsAttention: return L("Needs attention")
        case .onPace: return L("On pace")
        case .done: return L("Done")
        case .recordOnly: return L("Record only")
        case .counts: return L("Counts toward \(r.sharedTarget ?? 750)")
        }
    }

    private func ink(_ s: HomeProtoSeed.Section) -> Color {
        switch s {
        case .needsAttention: return colors.caution
        case .onPace, .done: return colors.positive
        case .recordOnly, .counts: return colors.draftingInk
        }
    }

    var body: some View {
        List {
            ForEach(HomeProtoSeed.Section.allCases, id: \.self) { s in
                let list = r.rentals(in: s)
                if !list.isEmpty {
                    Section {
                        ForEach(list) { rental in
                            StdBrowseRow(title: rental.name, meta: meta(rental), value: value(rental), valueInk: valueInk(rental, s), chevron: false, metaLines: 3, progress: bar(rental, s)) {
                                HomeProtoArt(size: 36, keyframe: HomeProtoStage.keyframe(for: rental))
                            }
                            .stdMeasure("row.\(rental.id)")
                            .listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
                    .listRowBackground(colors.backgroundSecondary)
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 48 }
                            .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] + 16 }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 0) {
                            if s == firstSection {
                                // Flat back control, the same style as every close button (no glass hairline).
                                Button {} label: { Image(systemName: "chevron.left") }
                                    .buttonStyle(StdButtonStyle(.icon))
                                    .accessibilityLabel(L("Back to Today"))
                                    .padding(.bottom, 8)
                                StdScreenTitle(title: L("All rentals"), subtitle: subtitle)
                                    .stdMeasure("title")
                                    .padding(.bottom, 24)
                            }
                            StdSectionHeader(title: title(s), count: list.count, ink: ink(s))
                        }
                        .stdHeaderInsets()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY - $0.safeAreaInsets.bottom } action: { y in
            StdGeom.log(String(format: "STDGEOM fold %.1f 0 0 0", y))
        }
        .listSectionSpacing(24)
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(colors.background.ignoresSafeArea())
        .environment(\.defaultMinListRowHeight, 44)
        .toolbar(.hidden, for: .navigationBar)
    }

    /// The summary the stat tiles used to carry, as one line (D3: rows lead).
    private var subtitle: String {
        if let shared = r.sharedTarget { return L("\(Int(r.totalHours)) of \(shared) hours, all rentals together") }
        return L("\(r.rentals.count) rentals · \(Int(r.totalHours))h logged in 2026")
    }

    private var firstSection: HomeProtoSeed.Section? {
        HomeProtoSeed.Section.allCases.first { !r.rentals(in: $0).isEmpty }
    }

    /// 3pt progress in the section's intent ink (critique #7); record-only rows get none.
    private func bar(_ rental: HomeProtoRental, _ section: HomeProtoSeed.Section) -> (Double, Color)? {
        switch rental.target {
        case .own(let t): return (rental.hours / Double(t), ink(section))
        case .counts: return (rental.hours / max(r.totalHours, 1), colors.action)
        case .record: return nil
        }
    }

    private func valueInk(_ rental: HomeProtoRental, _ section: HomeProtoSeed.Section) -> Color {
        switch section {
        case .needsAttention, .onPace, .done: return ink(section)
        case .recordOnly, .counts: return colors.textPrimary
        }
    }

    private func meta(_ rental: HomeProtoRental) -> String {
        switch rental.target {
        case .record(let reason): return reason.hasPrefix("Long") ? L("Long-stay rental: hours kept, no target") : L("A manager does most")
        case .counts: return L("\(Int((rental.hours / max(r.totalHours, 1) * 100).rounded()))% of the total")
        case .own(let t):
            switch rental.pace {
            case .behind: return L("\(rental.weeklyNeed ?? 0)h a week to reach \(t)")
            case .done: let month = rental.reached ?? ""; return L("Reached \(t) in \(month)")
            default: return L("On pace for \(t)")
            }
        }
    }

    private func value(_ rental: HomeProtoRental) -> String {
        switch rental.target {
        case .own(let t) where rental.pace != .done: return L("\(Int(rental.hours)) of \(t)")
        default: return StdFormat.hours(rental.hours.rounded(.down))
        }
    }

}
#endif
