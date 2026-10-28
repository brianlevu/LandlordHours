import SwiftUI

#if DEBUG
// MARK: - Component sheet (DEBUG): every LH* component on one board, for captures and the gate
//
//   -LHComponentSheet [n]     opens the sheet over the app; n picks a page (1–5), default 1
//
// Page 1 buttons, tags, chips, headers, titles · 2 rows · 3 fields, segmented, stepper, cards,
// tiles, ring · 4 the hero (CraftHouseView) on the page, chip, dots, thumbnails · 5 empty states and
// the sheet scaffold · 6 a full-height LHSheet with a long title and a secondary and tertiary
// choice (the AX footer policy, §1.20). Strings here are fixtures for the board, not product copy.

enum LHComponentSheetLaunch {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-LHComponentSheet") }

    static var page: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LHComponentSheet"), args.indices.contains(i + 1),
              let n = Int(args[i + 1]) else { return 1 }
        return min(max(n, 1), 6)
    }

    /// `-LHComponentStage <stage>` and `-LHComponentLit 0|1` for the hero page.
    static var stage: CraftStage {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LHComponentStage"), args.indices.contains(i + 1) else { return .half }
        return CraftStage(rawValue: "craft_" + args[i + 1]) ?? .half
    }

    static var lit: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LHComponentLit"), args.indices.contains(i + 1) else { return true }
        return args[i + 1] != "0"
    }
}

private func fx(_ s: String) -> String { s }   // fixture text, not product copy

struct LHComponentSheet: View {
    let page: Int

    @State private var who = "me"
    @State private var hours = 1.5
    @State private var note = ""
    @State private var name = "Pine Cabin"
    @State private var toggle = true
    @State private var filter = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if page == 4 {
                heroPage
            } else if page == 6 {
                policySheet
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                        switch page {
                        case 2: rowsPage
                        case 3: controlsPage
                        case 5: emptyPage
                        default: basicsPage
                        }
                    }
                    .padding(.horizontal, LHMetrics.gutter)
                    .padding(.vertical, 16)
                }
                .background { LHCanvas() }
            }
        }
        .accessibilityIdentifier("lh.componentSheet.\(page)")
    }

    /// A row at default sizes, a column at AX sizes (fixture layout only).
    private func flow<C: View>(spacing: CGFloat, @ViewBuilder _ content: () -> C) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
                                                  : AnyLayout(HStackLayout(spacing: spacing))
        return layout { content() }
    }

    // MARK: Page 1

    @ViewBuilder private var basicsPage: some View {
        LHScreenHeader(title: fx("Components"), subtitle: fx("LHButton, LHTag, LHChip, headers"),
                       accessory: { EmptyView() }) {
            LHHeaderAction(symbol: "ellipsis", label: fx("More")) {}
        }
        LHSectionHeader(fx("Buttons"))
        VStack(spacing: 12) {
            Button(fx("Log 1h 30m")) {}.buttonStyle(LHButton.primary)
            Button(fx("Log 1h 30m")) {}.buttonStyle(LHButton.primaryGlass)
            flow(spacing: 12) {
                Button(fx("Turn on")) {}.buttonStyle(LHButton.secondary)
                Button(fx("See all 7")) {}.buttonStyle(LHButton.tertiary)
                Button(fx("Delete")) {}.buttonStyle(LHButton.destructiveTertiary)
                Button {} label: { Image(systemName: "xmark") }
                    .buttonStyle(LHButton.icon).accessibilityLabel(fx("Close"))
            }
            Button(fx("Disabled")) {}.buttonStyle(LHButton.primary).disabled(true)
                .accessibilityIdentifier("lh.componentSheet.disabledPrimary")
            flow(spacing: 12) {
                Button(fx("Disabled")) {}.buttonStyle(LHButton.secondary).disabled(true)
                Button(fx("Disabled")) {}.buttonStyle(LHButton.tertiary).disabled(true)
                Button {} label: { Image(systemName: "xmark") }
                    .buttonStyle(LHButton.icon).disabled(true).accessibilityLabel(fx("Close"))
            }
        }
        LHSectionHeader(fx("To confirm"), count: 7, trailingTitle: fx("See all"), trailingAction: {})
        flow(spacing: 8) {
            LHTag(fx("Repairs"), tone: .action)
            LHTag(fx("Not sure"), tone: .caution)
            LHTag(fx("Might be logged"), tone: .informational)
            LHTag(fx("Done"), tone: .positive)
        }
        LHSectionHeader(fx("Behind"), tone: .attention)
        LHSectionHeader(fx("Yesterday"), style: .day)
        flow(spacing: 8) {
            LHChip(fx("All"), isSelected: filter == 0) { filter = 0 }
            LHChip(fx("Repairs"), isSelected: filter == 1) { filter = 1 }
            LHChip(fx("Showings"), systemImage: "key", isSelected: filter == 2) { filter = 2 }
        }
        LHScreenHeader(title: fx("Pine Cabin"), style: .detail, accessory: { EmptyView() }, trailing: { EmptyView() })
        LHSheetHeader(title: fx("Log time"), subtitle: fx("Today, Thu Oct 22"), onClose: {})
        LHFootnote.cpa
    }

    // MARK: Page 2

    @ViewBuilder private var rowsPage: some View {
        LHSectionHeader(fx("To confirm"), count: 3)
        LHRowGroup {
            LHRow.Action(title: fx("Plumber at Pine Cabin"), sourceSymbol: "calendar", meta: fx("12–2"),
                         tag: LHTag(fx("Repairs"), tone: .action), hours: 2, controlLabel: fx("Confirm 2 hours"),
                         onControl: {})
            LHDivider(leadingInset: LHRow.actionDividerInset)
            LHRow.Action(title: fx("Tenant call about the lease renewal"), sourceSymbol: "checklist", meta: fx("9–10:30"),
                         tag: LHTag(fx("Needs hours"), tone: .caution), hours: nil, controlLabel: fx("Review and confirm"),
                         onControl: {})
            LHDivider(leadingInset: LHRow.actionDividerInset)
            LHRow.Action(title: fx("Showing at Oak Street Duplex"), sourceSymbol: "calendar", meta: fx("4–5:30"),
                         hours: 1.5, control: .confirmed, controlLabel: fx("Confirmed"), onControl: {})
        }
        LHSectionHeader(fx("Your rentals"), count: 3)
        LHRowGroup {
            LHRow.Browse(title: fx("Santa Ray Ave"), meta: fx("Frame going up"), value: fx("46h"), action: {}) {
                LHThumb.row(.frame70, lit: true)
            }
            LHDivider(leadingInset: LHRow.browseDividerInset + 8)
            LHRow.Browse(title: fx("Pine Cabin"), meta: fx("Roof on, siding going up"), value: fx("262h"), action: {}) {
                LHThumb.row(.half, lit: false)
            }
            LHDivider(leadingInset: LHRow.browseDividerInset)
            LHRow.Browse(title: fx("Learn how the 750 works"), meta: fx("3 min read"), systemImage: "book", action: {})
        }
        LHSectionHeader(fx("Values and toggles"))
        VStack(spacing: 8) {
            LHRow.Value(fx("Rental"), value: fx("Pine Cabin"), action: {})
            LHRow.Value(fx("Category"), value: fx("Repairs"), accessory: .menu, action: {})
            LHRowGroup {
                LHRow.Toggle(fx("Calendar suggestions"), subtitle: fx("At most two a day, never at night."), isOn: $toggle)
                    .padding(.horizontal, 16).padding(.vertical, 6)
            }
        }
    }

    // MARK: Page 3

    @ViewBuilder private var controlsPage: some View {
        LHSectionHeader(fx("Fields"))
        LHField(fx("What did you do?"), text: $note, multiline: true)
        LHField(fx("Rental name"), text: $name)
        LHField(fx("Other name"), text: .constant("ca"), error: fx("Use at least 3 letters."))
        LHSectionHeader(fx("Who and how long"))
        LHSegmented([.init("me", fx("Me")), .init("spouse", fx("Spouse"))], selection: $who, accessibilityLabel: fx("Who"))
        HStack { Spacer(); LHStepper(hours: $hours, label: fx("Hours")); Spacer() }
        LHSectionHeader(fx("Cards and tiles"))
        LHCard.Summary(value: fx("206"), label: fx("of 750 hours"), footnote: fx("Updated just now"),
                       actionTitle: fx("Export"), action: {})
        LHTile.StatGrid {
            LHTile.Stat(value: fx("9h"), label: fx("This week"), trend: .up)
            LHTile.Stat(value: fx("14h"), label: fx("Behind pace"))
        }
        HStack {
            Spacer()
            LHRing(progress: 206.0 / 750, diameter: 160, lineWidth: 14, accessibilityValue: fx("206 of 750 hours")) {
                Text(verbatim: "206").font(.title.weight(.bold)).fontDesign(.rounded).monospacedDigit()
            }
            Spacer()
        }
        LHBarRow(label: fx("Pine Cabin"), value: fx("262h"), fraction: 0.8)
    }

    // MARK: Page 4: the hero on the page

    private var heroPage: some View {
        GeometryReader { proxy in
            let window = proxy.size
            let side = CraftHeroSide.resolve(previous: nil, kind: .hero, window: CGSize(width: window.width, height: window.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom),
                                             band: .a, accessibility: typeSize.isAccessibilitySize).side
            ScrollView {
                VStack(spacing: 0) {
                    LHHeroChip(fx("Pine Cabin"))
                    CraftHouseView(stage: LHComponentSheetLaunch.stage, windowsLit: LHComponentSheetLaunch.lit, side: side)
                    LHPageDots(count: 3, current: 1).padding(.top, -48)
                    Text(verbatim: "262")
                        .font(LHFont.heroNumeral(size: typeSize.isAccessibilitySize ? 54 : 84))
                        .tracking(-2)
                        .foregroundStyle(AdaptiveColors(colorScheme: colorScheme).textPrimary)
                        .padding(.top, typeSize.isAccessibilitySize ? 0 : -24)
                    Text(fx("of 500 hours")).font(.body)
                        .foregroundStyle(AdaptiveColors(colorScheme: colorScheme).textSecondary)
                    HStack(spacing: 12) {
                        ForEach(CraftStage.allCases, id: \.self) { stage in
                            LHThumb.row(stage, lit: true)
                        }
                    }
                    .padding(.top, 16)
                    HStack(spacing: 12) {
                        LHThumb.header(.complete, lit: false)
                        LHThumb.large(.complete, lit: true)
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
            }
            .background { LHPage() }
        }
    }

    // MARK: Page 6

    /// One full-height sheet: a title long enough to wrap, a body taller than the screen at AX, a
    /// primary, and a secondary and tertiary choice. Below AX all three sit in the pinned bar; at AX
    /// only the primary does and the other two scroll with the body (§1.20).
    private var policySheet: some View {
        LHSheet(fx("Log time for the cabin you rent out to guests"), subtitle: fx("Today, Thu Oct 22"), onClose: {}) {
            VStack(alignment: .leading, spacing: 12) {
                LHField(fx("What did you do?"), text: $note, multiline: true)
                LHRow.Value(fx("Rental"), value: fx("Pine Cabin"), action: {})
                LHRow.Value(fx("Category"), value: fx("Repairs and maintenance"), action: {})
                LHRow.Value(fx("Who did the work"), value: fx("Me"), action: {})
                LHRow.Toggle(fx("Count it toward your yearly goal"), subtitle: fx("Only hours you confirm are counted."), isOn: $toggle)
            }
        } primary: {
            Button(fx("Log 1h 30m")) {}.buttonStyle(LHButton.primary)
        } secondary: {
            Button(fx("Save as a draft")) {}.buttonStyle(LHButton.secondary).frame(maxWidth: .infinity)
            Button(fx("Discard this entry")) {}.buttonStyle(LHButton.tertiary).frame(maxWidth: .infinity)
        }
        .background(AdaptiveColors(colorScheme: colorScheme).backgroundSecondary)
    }

    // MARK: Page 5

    @ViewBuilder private var emptyPage: some View {
        LHSectionHeader(fx("Empty in a container"))
        LHRowGroup {
            LHEmptyState(systemImage: "checkmark.circle", headline: fx("All caught up"),
                         message: fx("New suggestions show up here."), actionTitle: fx("Look again"), action: {})
        }
        LHSectionHeader(fx("Sheet scaffold"))
        LHSheet(fx("Log time"), subtitle: fx("Today, Thu Oct 22"), onClose: {}) {
            VStack(alignment: .leading, spacing: 12) {
                LHField(fx("What did you do?"), text: $note, multiline: true)
                LHRow.Value(fx("Rental"), value: fx("Pine Cabin"), action: {})
            }
        } footer: {
            Button(fx("Log 1h 30m")) {}.buttonStyle(LHButton.primary)
        }
        .frame(height: 420)
        .background(AdaptiveColors(colorScheme: colorScheme).backgroundSecondary,
                    in: RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
    }
}
#endif
