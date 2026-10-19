import SwiftUI

// MARK: - Blueprint list language (2.0)
//
// The shared pieces Records, Reports and Settings are built from, so the three screens read as
// one product with Today and the Inbox: Fraunces large titles, uppercase footnote section
// labels, native inset-grouped lists on the brand canvas, SF Symbols in secondary ink, SF Pro
// Rounded tabular numbers. docs/design/2.0-brand-system.md + 2.0-hifi-reference-spec.md §g–§j.

/// Tab-root title in Fraunces, the same face and size as "Inbox" and "Today".
struct BPScreenTitle: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .lhDisplayFont(.largeTitle)
            .foregroundStyle(AdaptiveColors(colorScheme: colorScheme).textPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .accessibilityAddTraits(.isHeader)
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

/// Uppercase footnote section label with an optional trailing value ("OCTOBER 2026 … 41h").
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
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        layout {
            Text(title)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.3)
                .foregroundStyle(colors.textSecondary)
                .accessibilityAddTraits(.isHeader)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
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

/// One settings row: monochrome SF Symbol, 17pt label, optional subtitle and trailing value.
/// The chevron is drawn by the List for NavigationLinks; buttons that open something pass
/// `showsChevron: true`.
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
        let colors = AdaptiveColors(colorScheme: colorScheme)
        HStack(alignment: subtitle == nil ? .center : .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isDestructive ? colors.destructive : colors.textSecondary)
                .frame(width: 28, alignment: .center)
                .padding(.top, subtitle == nil ? 0 : 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(isDestructive ? colors.destructive : colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(valueColor ?? colors.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Toggle row with a subtitle (Wispr Flow's privacy toggles), drawn with the visible-off switch.
struct SettingToggleRow: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var badge: String? = nil
    @Binding var isOn: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 28)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.body)
                            .foregroundStyle(colors.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(colors.textSecondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .overlay(Capsule().strokeBorder(colors.border, lineWidth: 1))
                        }
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .toggleStyle(InboxSwitchStyle())
        .padding(.vertical, 6)
    }
}

/// Filter chip (Mercury): 32pt capsule; the selected one fills with the action colour.
struct BPFilterChip: View {
    let title: String
    var isActive: Bool = false
    var showsChevron: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        HStack(spacing: 4) {
            Text(title)
                .font(.subheadline.weight(isActive ? .semibold : .regular))
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(isActive ? colors.onAction : colors.textPrimary)
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
        .background(Capsule().fill(isActive ? colors.action : colors.backgroundSecondary))
        .overlay(Capsule().strokeBorder(isActive ? Color.clear : colors.border, lineWidth: 1))
        .contentShape(Capsule())
    }
}

/// Small bordered capsule action ("Export", "Share") for title rows.
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
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(Capsule().fill(colors.backgroundSecondary))
        .overlay(Capsule().strokeBorder(colors.border, lineWidth: 1))
        .contentShape(Capsule())
    }
}

/// Centered empty state: 56pt circle + symbol, title, one line (spec §k).
struct BPEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        VStack(spacing: 10) {
            Circle()
                .fill(colors.backgroundSecondary)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(colors.textSecondary)
                )
                .overlay(Circle().strokeBorder(colors.border, lineWidth: 1))
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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
                        .frame(width: 112, alignment: .leading)
                    bar(colors)
                    valueLabel(colors)
                        .frame(minWidth: 52, alignment: .trailing)
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

enum BPHours {
    /// "2h", "1h 30m", "45m", "0h". Whole minutes, never rounded up.
    static func short(_ hours: Double) -> String {
        let totalMinutes = Int((max(hours, 0) * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h == 0 && m == 0 { return "0h" }
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    /// Spoken: "2 hours 30 minutes".
    static func spoken(_ hours: Double) -> String {
        let totalMinutes = Int((max(hours, 0) * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        var parts: [String] = []
        if h > 0 { parts.append(h == 1 ? "1 hour" : "\(h) hours") }
        if m > 0 { parts.append(m == 1 ? "1 minute" : "\(m) minutes") }
        return parts.isEmpty ? "0 hours" : parts.joined(separator: " ")
    }
}
