import SwiftUI

// MARK: - Blueprint list language (2.0), now thin wrappers over the v2 LH* components
//
// Package 0b: every type here keeps its old signature so callers compile, and renders through
// the LH* component that replaces it (docs/design/v2-revamp-plan.md §4). Each lane removes its own
// uses; the whole file is deleted in cleanup. New code uses LH* directly.

/// Tab-root title. Wraps `LHScreenTitle` (collection style).
struct BPScreenTitle: View {
    let text: String

    var body: some View {
        LHScreenTitle(text)
    }
}

/// Reports and Settings open from Today's header, so the shell keeps Today highlighted (WP-D's
/// tab rule). This back control makes that relationship explicit: the screen belongs to Today,
/// and "‹ Today" is the way back, the same as tapping the highlighted tab.
struct BPBackToTodayButton: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        Button {
            NotificationCenter.default.post(name: .switchToTab, object: ShellTab.todayIndex)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                Text("Today")
                    .font(.body)
            }
            .foregroundStyle(colors.action)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel("Back to Today")
        .accessibilityIdentifier("shell.backToToday")
    }
}

enum AppVersionInfo {
    /// "Version 1.0.6 (202608260402)", read from the bundle at runtime.
    static func display(bundle: Bundle = .main) -> String {
        let marketing = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let build, !build.isEmpty, build != marketing else { return "Version \(marketing)" }
        return "Version \(marketing) (\(build))"
    }
}

/// Section label with an optional trailing value ("October 2026 ... 41h"). Wraps `LHSectionHeader`.
struct BPSectionHeader: View {
    let title: String
    var trailing: String? = nil
    var trailingAccessibility: String? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        layout {
            LHSectionHeader(title)
            if let trailing {
                Text(trailing)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(colors.textSecondary)
                    .accessibilityLabel(trailingAccessibility ?? trailing)
            }
        }
    }
}

/// One settings row. Wraps `LHRow.Browse` (36pt glyph tile, title, meta, value, chevron).
/// A destructive row or a coloured value has no LH equivalent yet, so those two draw the legacy
/// face until their lane moves them to `LHRow.Browse` plus a tag.
struct SettingRow: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var valueColor: Color? = nil
    var showsChevron: Bool = false
    var isDestructive: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if isDestructive || valueColor != nil {
            legacyFace
        } else {
            LHRow.Browse(title: title, meta: subtitle, value: value, systemImage: symbol, tint: .neutral,
                         showsChevron: showsChevron)
        }
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    private var ax: Bool { typeSize.isAccessibilitySize }

    /// Below AX: label and subtitle left, value and chevron right. At AX the glyph stays inline, the
    /// label wraps beside it, the value drops under the subtitle and the chevron is dropped, so nothing
    /// narrows the label (owner ruling 2026-10-27; Apple's Settings does the same).
    private var legacyFace: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        return HStack(alignment: (subtitle == nil && !ax) ? .center : .top, spacing: 12) {
            LHRowGlyph(systemImage: symbol, tint: isDestructive ? .destructive : .neutral)
            VStack(alignment: .leading, spacing: ax ? 4 : 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(isDestructive ? colors.destructive : colors.textPrimary)
                    .lineLimit(ax ? nil : 2)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(ax ? nil : (typeSize >= .xxLarge ? 2 : 1))
                }
                if ax, let value { valueText(value, colors) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !ax, let value { valueText(value, colors).layoutPriority(1) }
            if showsChevron && !ax { LHChevron() }
        }
        .padding(LHRow.insets)
        .frame(minHeight: LHMetrics.rowMinHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func valueText(_ value: String, _ colors: AdaptiveColors) -> some View {
        Text(value)
            .font(.subheadline)
            .fontDesign(.rounded)
            .monospacedDigit()
            .foregroundStyle(valueColor ?? colors.textSecondary)
            .multilineTextAlignment(ax ? .leading : .trailing)
    }
}

/// Toggle row. Wraps `LHRow.Toggle`; the leading symbol and badge are dropped (v2 toggle rows
/// carry a label and one subtitle only), the badge folds into the subtitle.
struct SettingToggleRow: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var badge: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        LHRow.Toggle(badge.map { "\(title) (\($0))" } ?? title, subtitle: subtitle, isOn: $isOn)
    }
}

/// Filter chip face (a label; callers supply the Button or Menu). Matches `LHChip`: 34pt capsule,
/// selected fills with the action colour.
struct BPFilterChip: View {
    let title: String
    var isActive: Bool = false
    var showsChevron: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        HStack(spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(isActive ? colors.onAction : colors.textPrimary)
        .padding(.horizontal, 12)
        .frame(minHeight: LHChip.height)
        .background(isActive ? colors.action : colors.backgroundTertiary, in: Capsule())
        .overlay(Capsule().strokeBorder(isActive ? Color.clear : colors.border, lineWidth: 0.5))
        .contentShape(Capsule())
    }
}

/// Segmented control. Two or three options wrap `LHSegmented`; four or more keep the stacked
/// capsule fallback (the standard sends those to `LHRow.Value`).
struct BPSegmentedPicker<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    /// Kept for source compatibility; `LHSegmented` never stacks.
    var layout: Layout = .automatic

    enum Layout { case automatic, horizontalOnly }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var minHeight: CGFloat = 40

    var body: some View {
        if (2...3).contains(options.count) {
            LHSegmented(options.map { LHSegmented<Option>.Option($0, title($0)) }, selection: $selection)
        } else {
            fallback
        }
    }

    private var fallback: some View {
        Group {
            if layout == .horizontalOnly {
                HStack(spacing: 8) { segments }
            } else if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) { segments }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { segments }
                    VStack(spacing: 8) { segments }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    @ViewBuilder private var segments: some View {
        ForEach(options, id: \.self) { option in
            segment(option)
        }
    }

    private func segment(_ option: Option) -> some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let isSelected = selection == option
        return Button {
            guard selection != option else { return }
            if reduceMotion { selection = option } else {
                withAnimation(AppAnimation.quick) { selection = option }
            }
        } label: {
            Text(title(option))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isSelected ? colors.onAction : colors.textPrimary)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(Capsule().fill(isSelected ? colors.action : colors.backgroundTertiary))
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : colors.border, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(title(option))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Small capsule action label ("Export", "Share") for title rows. Draws the `LHButton.secondary`
/// face (callers still wrap it in their own Button until each lane moves to `LHButton.secondary`).
struct BPCapsuleButtonLabel: View {
    let title: String
    var symbol: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(colors.action)
        .padding(.horizontal, LHButton.Metrics.secondaryPadding)
        .padding(.vertical, 10)
        .frame(minHeight: LHButton.Metrics.controlHeight)
        .background(colors.actionSurface, in: Capsule())
        .contentShape(Capsule())
    }
}

/// Centered empty state. Wraps `LHEmptyState` (no action).
struct BPEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        LHEmptyState(systemImage: symbol, tone: .action, headline: title, message: message)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
    }
}

/// Labelled horizontal bar (Flighty's report bars): label, capsule track, tabular value.
/// Stacks the bar under the label at accessibility text sizes.
struct BPBarRow: View {
    let label: String
    let value: Double
    let maxValue: Double
    let valueText: String
    var tint: Color? = nil
    var accessibilityValueText: String? = nil
    var animate: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    /// One fixed value column, so every track in a card starts and ends on the same lines
    /// ("2h" and "120h 30m" no longer give their bars different widths).
    @ScaledMetric(relativeTo: .subheadline) private var valueColumnWidth: CGFloat = 70
    /// Label column grows with the text so a one-word label ("Bookkeeping") never hyphenates.
    @ScaledMetric(relativeTo: .subheadline) private var labelColumnWidth: CGFloat = 112

    private var fraction: Double {
        guard maxValue > 0 else { return 0 }
        return min(max(value / maxValue, 0), 1)
    }

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        labelText(colors)
                        Spacer(minLength: 8)
                        valueLabel(colors)
                    }
                    bar(colors)
                }
            } else {
                HStack(spacing: 12) {
                    labelText(colors)
                        .frame(width: labelColumnWidth, alignment: .leading)
                    bar(colors)
                    valueLabel(colors)
                        .minimumScaleFactor(0.8)
                        .frame(width: valueColumnWidth, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValueText ?? valueText)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion || !animate {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 1).delay(0.05)) { appeared = true }
            }
        }
    }

    private func labelText(_ colors: AdaptiveColors) -> some View {
        Text(label)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.textPrimary)
            .lineLimit(2)
            .truncationMode(.tail)
    }

    private func valueLabel(_ colors: AdaptiveColors) -> some View {
        Text(valueText)
            .font(.system(.subheadline, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(colors.textSecondary)
            .lineLimit(1)
    }

    private func bar(_ colors: AdaptiveColors) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(colors.backgroundTertiary)
                    .overlay(Capsule().strokeBorder(colors.border.opacity(0.6), lineWidth: 0.5))
                Capsule()
                    .fill(tint ?? colors.action)
                    .frame(width: max(fraction > 0 ? 10 : 0, proxy.size.width * (appeared ? fraction : 0)))
            }
        }
        .frame(height: 10)
    }
}

// MARK: - Loading placeholder (integration hook)

/// Stand-in for a value that is still loading: a soft rounded bar, never a spinner, and only
/// where the number or chart will appear. The rest of the screen stays interactive.
/// INTEGRATION: wp-l-loading ships `PlaceholderBar` (numbers) and `DraftingLoader` (charts);
/// swap them in here so every `isLoading` hook in Records/Reports/Export picks them up.
struct BPLoadingPlaceholder: View {
    enum Kind { case number, chart }
    var kind: Kind = .number
    var width: CGFloat? = 96
    var height: CGFloat = 28
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        RoundedRectangle(cornerRadius: kind == .number ? height / 2 : 8, style: .continuous)
            .fill(colors.backgroundTertiary)
            .overlay(
                RoundedRectangle(cornerRadius: kind == .number ? height / 2 : 8, style: .continuous)
                    .strokeBorder(colors.border.opacity(0.6), lineWidth: 0.5)
            )
            .frame(width: width, height: height)
            .accessibilityElement()
            .accessibilityLabel("Loading")
    }
}

// MARK: - Hours formatting

/// Forwards to `LHFormat`. The one difference kept for the existing tests: zero reads "0h".
enum BPHours {
    /// "2h", "1h 30m", "45m", "0h".
    static func short(_ hours: Double) -> String {
        guard let minutes = LHFormat.minutes(hours), minutes > 0 else { return "0h" }
        return LHFormat.hours(hours)
    }

    /// Spoken: "2 hours 30 minutes" (no comma; the existing tests and Reports labels read this way).
    static func spoken(_ hours: Double) -> String {
        guard let totalMinutes = LHFormat.minutes(hours) else { return "0 hours" }
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        var parts: [String] = []
        if h > 0 { parts.append(h == 1 ? "1 hour" : "\(h) hours") }
        if m > 0 { parts.append(m == 1 ? "1 minute" : "\(m) minutes") }
        return parts.isEmpty ? "0 hours" : parts.joined(separator: " ")
    }
}
