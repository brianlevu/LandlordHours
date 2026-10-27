import SwiftUI

// MARK: - LHRow (standard §1.3–§1.6) and LHRowGroup
//
// One grid for every row, in every band (§1.27 "Row grammar"):
//   insets 16 / 10, minHeight 56, leading slot 22 (control) or 36 / 44 (ornament), 12 gap,
//   title `.body` (semibold in decision rows), one meta line `.subheadline` `textSecondary`,
//   trailing value `.subheadline.semibold` rounded tabular. Heights 56–88 at default (D1).
//
//   LHRow.Action  the confirm item (Today To confirm, Inbox). Leading 22pt circle in a 44 frame;
//                 the row tap opens the sheet; system `.swipeActions` only, applied by the caller in
//                 its `List` (§1.3a). No button inside the row other than the control.
//   LHRow.Browse  Records, Rentals, Learn, picker lists: one ornament (36 tile, 44 house thumbnail
//                 or an SF glyph in a 36 wash tile), title + meta, trailing value + chevron.
//   LHRow.Value   pickers inside sheets and forms: label left, value + chevron right, on an inner
//                 surface (radius 12, backgroundTertiary), minHeight 56.
//   LHRow.Toggle  min 44, label + optional one-line subtitle, system Toggle tinted `action`.
//
// Rows live in one grouped container: an inset-grouped `List` section (the system draws the card
// and clips swipe backgrounds), or `LHRowGroup` where a List cannot be used (a fixed number of rows
// inside a page). Never a card per row (§1.1).

enum LHRow {
    /// The divider inset for rows with the 22pt control: 16 + 22 + 12.
    static let actionDividerInset: CGFloat = 50
    /// The divider inset for rows with a 36pt ornament: 16 + 36 + 12.
    static let browseDividerInset: CGFloat = 64
    /// Row content insets.
    static let insets = EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
}

// MARK: - Action

extension LHRow {
    struct Action: View {
        /// What the leading control shows.
        enum Control: Equatable {
            /// Empty circle: tap confirms (`canQuickLog`) or opens the sheet.
            case open
            /// Filled `positive` with a checkmark (motion `rowConfirm`).
            case confirmed
        }

        let title: String
        /// SF Symbol for the source (`calendar`, `checklist`), drawn in the meta line.
        var sourceSymbol: String? = nil
        /// Time range and other meta text ("12–2"). The date belongs to the day header, never here.
        var meta: String? = nil
        /// At most one tag (category or a status tag that replaces it).
        var tag: LHTag? = nil
        /// Hours, nil when unknown (shows "—").
        var hours: Double?
        var control: Control = .open
        /// "Confirm 2 hours" / "Review and confirm".
        var controlLabel: String
        var onControl: () -> Void
        var onOpen: (() -> Void)? = nil
        var identifier: String? = nil

        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.dynamicTypeSize) private var typeSize
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 22
        @ScaledMetric(relativeTo: .body) private var titleLine: CGFloat = 22
        private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
        private var ax: Bool { typeSize.isAccessibilitySize }
        private var tapPad: CGFloat { max(0, (LHMetrics.minTap - circle) / 2) }

        init(title: String, sourceSymbol: String? = nil, meta: String? = nil, tag: LHTag? = nil, hours: Double?,
             control: Control = .open, controlLabel: String, onControl: @escaping () -> Void,
             onOpen: (() -> Void)? = nil, identifier: String? = nil) {
            self.title = title
            self.sourceSymbol = sourceSymbol
            self.meta = meta
            self.tag = tag
            self.hours = hours
            self.control = control
            self.controlLabel = controlLabel
            self.onControl = onControl
            self.onOpen = onOpen
            self.identifier = identifier
        }

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                controlButton
                VStack(alignment: .leading, spacing: ax ? 4 : 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(ax ? nil : 2)
                    metaLine
                    if ax { hoursText }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !ax { hoursText.padding(.top, 2) }
            }
            .padding(LHRow.insets)
            .frame(minHeight: LHMetrics.rowMinHeight)
            .contentShape(Rectangle())
            .onTapGesture { onOpen?() }
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: controlLabel, onControl)
            .modifier(OptionalIdentifier(identifier: identifier))
        }

        private var controlButton: some View {
            Button(action: onControl) {
                ZStack {
                    Circle().strokeBorder(control == .confirmed ? colors.positive : colors.textTertiary, lineWidth: 1.5)
                    Circle().fill(colors.positive).opacity(control == .confirmed ? 1 : 0)
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(colors.onAction)
                        .opacity(control == .confirmed ? 1 : 0)
                }
                .frame(width: circle, height: circle)
                .frame(height: max(circle, titleLine))
                // A 44pt tap frame around the 22pt glyph without widening the row's grid.
                .padding(tapPad)
                .contentShape(Rectangle())
                .padding(-tapPad)
                .animation(reduceMotion ? AppAnimation.reduced : AppAnimation.feedback, value: control)
            }
            .buttonStyle(.borderless)
            .sensoryFeedback(.success, trigger: control) { _, new in new == .confirmed }
            .accessibilityLabel(controlLabel)
        }

        @ViewBuilder private var metaLine: some View {
            if sourceSymbol != nil || meta != nil || tag != nil {
                let layout = ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                : AnyLayout(HStackLayout(spacing: 6))
                layout {
                    if sourceSymbol != nil || meta != nil {
                        HStack(spacing: 4) {
                            if let sourceSymbol { Image(systemName: sourceSymbol) }
                            if let meta { Text(meta) }
                        }
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(ax ? nil : 1)
                    }
                    if let tag { tag }
                }
            }
        }

        private var hoursText: some View {
            Text(LHFormat.hours(hours))
                .font(.subheadline.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(hours == nil ? colors.textTertiary : colors.textPrimary)
                .lineLimit(1)
                .layoutPriority(2)
                .contentTransition(.numericText())
        }
    }
}

// MARK: - Browse

extension LHRow {
    struct Browse<Leading: View>: View {
        let title: String
        var meta: String? = nil
        var value: String? = nil
        var showsChevron = true
        var action: (() -> Void)? = nil
        @ViewBuilder var leading: Leading

        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.dynamicTypeSize) private var typeSize
        private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

        init(title: String, meta: String? = nil, value: String? = nil, showsChevron: Bool = true,
             action: (() -> Void)? = nil, @ViewBuilder leading: () -> Leading) {
            self.title = title
            self.meta = meta
            self.value = value
            self.showsChevron = showsChevron
            self.action = action
            self.leading = leading()
        }

        var body: some View {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(LHButton.press)
            } else {
                content
            }
        }

        private var ax: Bool { typeSize.isAccessibilitySize }

        /// Owner ruling 2026-10-27: below AX the title wraps to 2 lines (D7); at AX it never truncates.
        /// The meta takes a second line from XXL so a date is never cut; at AX it is unlimited.
        private var content: some View {
            HStack(alignment: ax ? .top : .center, spacing: 12) {
                leading
                VStack(alignment: .leading, spacing: ax ? 4 : 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(ax ? nil : 2)
                    if let meta {
                        Text(meta)
                            .font(.subheadline)
                            .foregroundStyle(colors.textSecondary)
                            .lineLimit(ax ? nil : (typeSize >= .xxLarge ? 2 : 1))
                    }
                    // At AX the value drops under the label so it never narrows it ("sug-/gesting").
                    if ax, let value { valueText(value) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !ax, let value { valueText(value).layoutPriority(1) }
                // At AX the chevron is dropped: it frees about 23pt (chevron + 12 gap) for the label,
                // which is what made "Notifica-/tions" break mid-word (Brian, 2026-10-27).
                if showsChevron && !ax {
                    LHChevron()
                }
            }
            .padding(LHRow.insets)
            .frame(minHeight: LHMetrics.rowMinHeight)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }

        private func valueText(_ value: String) -> some View {
            Text(value)
                .font(.subheadline)
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(colors.textSecondary)
                .lineLimit(ax ? nil : 1)
        }
    }
}

extension LHRow.Browse where Leading == LHRowGlyph {
    /// A browse row with an SF glyph in a 36 wash tile.
    init(title: String, meta: String? = nil, value: String? = nil, systemImage: String, tint: LHRowGlyph.Tint = .action,
         showsChevron: Bool = true, action: (() -> Void)? = nil) {
        self.init(title: title, meta: meta, value: value, showsChevron: showsChevron, action: action) {
            LHRowGlyph(systemImage: systemImage, tint: tint)
        }
    }
}

/// The one disclosure chevron (standard §1.4): `chevron.right`, `.footnote.semibold`, the `chevron`
/// token (`textSecondary`, 7.5:1 light / 8.9:1 dark; a UI glyph needs 3:1). Never `textTertiary`, never a
/// system grey: the stock List disclosure measured 1.72:1 (#C5C5C7 on white). Hidden from VoiceOver.
struct LHChevron: View {
    var systemName = "chevron.right"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: systemName)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AdaptiveColors(colorScheme: colorScheme).chevron)
            .accessibilityHidden(true)
    }
}

/// An SF glyph in a 36pt wash tile (radius 12): the browse row's leading slot outside Records and
/// Rentals.
struct LHRowGlyph: View {
    enum Tint: Equatable { case action, positive, caution, informational, neutral, destructive }
    let systemImage: String
    var tint: Tint = .action

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 36
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var pair: (Color, Color) {
        switch tint {
        case .action: return (colors.action, colors.actionSurface)
        case .positive: return (colors.positive, colors.positiveSurface)
        case .caution: return (colors.caution, colors.cautionSurface)
        case .informational: return (colors.informational, colors.informationalSurface)
        case .neutral: return (colors.textSecondary, colors.backgroundTertiary)
        case .destructive: return (colors.destructive, colors.destructiveSurface)
        }
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.body)
            .foregroundStyle(pair.0)
            .frame(width: side, height: side)
            .background(pair.1, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Value

extension LHRow {
    struct Value: View {
        enum Accessory: Equatable {
            /// Opens a sheet (≥ 6 options): `chevron.right`.
            case disclosure
            /// A `Menu` (≤ 5 options): `chevron.up.chevron.down`.
            case menu
            case none
        }

        let label: String
        let value: String
        var accessory: Accessory = .disclosure
        var action: (() -> Void)? = nil

        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.dynamicTypeSize) private var typeSize
        private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

        init(_ label: String, value: String, accessory: Accessory = .disclosure, action: (() -> Void)? = nil) {
            self.label = label
            self.value = value
            self.accessory = accessory
            self.action = action
        }

        var body: some View {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(LHButton.press)
            } else {
                content
            }
        }

        /// The row's face, for use as a `Menu` label.
        var content: some View {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                      : AnyLayout(HStackLayout(spacing: 12))
            return layout {
                Text(label)
                    .font(.body)
                    .foregroundStyle(colors.textPrimary)
                    .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                HStack(spacing: 6) {
                    Text(value)
                        .font(.body)
                        .foregroundStyle(colors.textSecondary)
                        .multilineTextAlignment(.trailing)
                    switch accessory {
                    case .disclosure:
                        LHChevron()
                    case .menu:
                        LHChevron(systemName: "chevron.up.chevron.down")
                    case .none:
                        EmptyView()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: LHMetrics.rowMinHeight, alignment: .leading)
            .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Toggle

extension LHRow {
    struct Toggle: View {
        let label: String
        var subtitle: String? = nil
        @Binding var isOn: Bool

        @Environment(\.colorScheme) private var colorScheme
        private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

        init(_ label: String, subtitle: String? = nil, isOn: Binding<Bool>) {
            self.label = label
            self.subtitle = subtitle
            self._isOn = isOn
        }

        var body: some View {
            SwiftUI.Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.body).foregroundStyle(colors.textPrimary)
                    if let subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(colors.textSecondary)
                    }
                }
            }
            .tint(colors.action)
            .frame(minHeight: LHMetrics.minTap)
        }
    }
}

// MARK: - Grouped container

/// One grouped container for a fixed set of rows outside a `List`: `backgroundSecondary`, radius
/// 20 continuous; on the dusk/night page a 1pt `pageCardEdge`, elsewhere a hairline in dark only.
/// Put `LHDivider(leadingInset:)` between rows.
struct LHRowGroup<Content: View>: View {
    var onPage = false
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    init(onPage: Bool = false, @ViewBuilder content: () -> Content) {
        self.onPage = onPage
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
        VStack(spacing: 0) { content }
            .background(colors.backgroundSecondary, in: shape)
            .overlay {
                if onPage {
                    shape.strokeBorder(colors.pageCardEdge, lineWidth: 1)
                } else if colorScheme == .dark {
                    shape.strokeBorder(colors.border, lineWidth: LHMetrics.hairline)
                }
            }
    }
}

// MARK: - Helpers

struct OptionalIdentifier: ViewModifier {
    let identifier: String?
    func body(content: Content) -> some View {
        if let identifier { content.accessibilityIdentifier(identifier) } else { content }
    }
}
