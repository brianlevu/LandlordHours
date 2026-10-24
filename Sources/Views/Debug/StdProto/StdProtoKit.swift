import SwiftUI

#if DEBUG
// MARK: - Design-standard mockups (DEBUG only, throwaway)
//
//   -LHStdProto today|inbox|logtime|seeall|goalcheck   which screen
//   -LHHomeSeed brian|reps750|eight                    which owner
//   -LHStdState <state>                                logtime: empty|filled|gap · goalcheck: question|result|summary
//   -LHStdScroll bottom                                Today: start scrolled to the end
//   -LHStdDemo confirm|tiles|logtime|goalcheck         scripted run for the videos
//
// Law: docs/design/DESIGN-STANDARD.md (components §1, density §2, motion §B, voice §C).
// Every visible string goes through `L(...)` into StdProto.xcstrings.

/// Every string on these screens: the StdProto string catalog.
func L(_ key: String.LocalizationValue) -> String { String(localized: key, table: "StdProto") }

/// Canonical lines (standard §C.5): one key per idea, never a variant.
enum StdCanon {
    static var nothingCounts: String { String(localized: "common.nothingCountsUntilConfirm", defaultValue: "Nothing counts until you confirm it.", table: "StdProto") }
    static var cpa: String { String(localized: "common.cpaFootnote", defaultValue: "Your CPA decides what the numbers mean.", table: "StdProto") }
    static var confirm: String { String(localized: "row.action.confirm", defaultValue: "Confirm", table: "StdProto") }
    static var notRentalWork: String { String(localized: "row.action.notRentalWork", defaultValue: "Not rental work", table: "StdProto") }
    static func confirmLikely(_ n: Int) -> String { String(localized: "row.batch.confirmLikely", defaultValue: "Confirm \(n) likely", table: "StdProto") }
}

struct StdProtoLaunch {
    enum Screen: String { case today, inbox, logtime, seeall, goalcheck }

    let screen: Screen
    let seedID: String
    let state: String
    let scroll: String?
    let demo: String?

    static let current: StdProtoLaunch? = {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let j = args.firstIndex(of: flag), args.indices.contains(j + 1) else { return nil }
            return args[j + 1]
        }
        guard let raw = value("-LHStdProto"), let screen = Screen(rawValue: raw) else { return nil }
        return StdProtoLaunch(screen: screen, seedID: value("-LHHomeSeed") ?? "brian",
                              state: value("-LHStdState") ?? "", scroll: value("-LHStdScroll"), demo: value("-LHStdDemo"))
    }()
}

// MARK: - Motion tokens (§B.2) and the hours format (§1.2)

enum StdMotion {
    static let feedback = Animation.easeOut(duration: 0.12)
    static let quick = Animation.easeInOut(duration: 0.15)
    static let reveal = Animation.easeOut(duration: 0.22)
    static let standard = Animation.easeInOut(duration: 0.24)
    static let flow = Animation.spring(duration: 0.30, bounce: 0)
    static let collapse = Animation.spring(duration: 0.25, bounce: 0)
    static let segment = Animation.spring(duration: 0.25, bounce: 0)
    static let pop = Animation.spring(duration: 0.26, bounce: 0.30)
    static let count = Animation.easeOut(duration: 0.60)
    static let ringProgress = Animation.spring(duration: 0.60, bounce: 0)
}

enum StdFormat {
    /// "2h", "30m", "1h 30m", "—" for unknown.
    static func hours(_ value: Double?) -> String {
        guard let value else { return "—" }
        let minutes = Int((value * 60).rounded())
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return L("\(m)m") }
        if m == 0 { return L("\(h)h") }
        return L("\(h)h \(m)m")
    }
}

/// Short category names, from the catalog.
extension ActivityCategory {
    var stdLabel: String {
        switch self {
        case .repairs: return L("Repairs")
        case .management: return L("Management")
        case .leasing: return L("Leasing")
        case .bookkeeping: return L("Bookkeeping")
        case .legal: return L("Legal")
        case .insurance: return L("Insurance")
        case .travel: return L("Travel")
        case .renovations: return L("Renovation")
        case .investing: return L("Investing")
        case .financing: return L("Financing")
        case .contractNegotiation: return L("Negotiation")
        }
    }
}

/// Reads the scheme once per view.
struct StdColors: DynamicProperty {
    @Environment(\.colorScheme) private var scheme
    var c: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }
}

// MARK: - Type helpers

enum StdFont {
    /// Drafting label: SF Mono 11 medium (caption2), caps, +12% tracking.
    static let drafting = Font.system(.caption2, design: .monospaced, weight: .medium)
    static let draftingTracking: CGFloat = 1.32
}

// MARK: - LHScreenTitle (§1.14)

struct StdScreenTitle: View {
    let title: String
    var subtitle: String? = nil
    @Environment(\.colorScheme) private var scheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(LHFont.fraunces(.largeTitle))
                .foregroundStyle(colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Sheet title (§1.14 sheet style): drafting eyebrow + SF title2 semibold, close .icon on the right.
struct StdSheetHeader: View {
    var eyebrow: String? = nil
    let title: String
    var leading: (() -> Void)? = nil
    var onClose: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let leading {
                Button(action: leading) { Image(systemName: "chevron.left") }
                    .buttonStyle(StdButtonStyle(.icon))
                    .accessibilityLabel(L("Back"))
            }
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Text(eyebrow).font(StdFont.drafting).textCase(.uppercase).tracking(StdFont.draftingTracking)
                        .foregroundStyle(colors.draftingInk)
                }
                Text(title).font(.title2.weight(.semibold)).foregroundStyle(colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(StdButtonStyle(.icon))
                .accessibilityLabel(L("Close"))
        }
        .frame(minHeight: 56)
    }
}

// MARK: - LHSectionHeader (§1.15)

struct StdSectionHeader: View {
    let title: String
    var count: Int? = nil
    var ink: Color? = nil
    var trailing: String? = nil
    var onTrailing: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    @Environment(\.dynamicTypeSize) private var typeSize

    private var label: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title).font(StdFont.drafting).textCase(.uppercase).tracking(StdFont.draftingTracking)
                .foregroundStyle(ink ?? colors.draftingInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let count {
                Text(verbatim: "\(count)")
                    .font(.caption2.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(colors.action)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Capsule().fill(colors.actionSurface))
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(StdMotion.standard, value: count)
                    .fixedSize()
            }
        }
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    label
                    if let trailing { Button(trailing, action: onTrailing).buttonStyle(StdButtonStyle(.tertiary)).padding(.vertical, -8) }
                }
            } else {
                HStack(alignment: .center, spacing: 8) {
                    label
                    Spacer(minLength: 8)
                    if let trailing { Button(trailing, action: onTrailing).buttonStyle(StdButtonStyle(.tertiary)).padding(.vertical, -8) }
                }
            }
        }
        .textCase(nil)
        .frame(minHeight: 28)
    }
}

// MARK: - Day header (§1.15a): sentence case, subheadline semibold, textSecondary, 28pt

struct StdDayHeader: View {
    let title: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AdaptiveColors(colorScheme: scheme).textSecondary)
            .textCase(nil)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .bottomLeading)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// A day header drawn as a row inside the card: no separators, tight insets.
    func stdDayRow(first: Bool, colors: AdaptiveColors) -> some View {
        listRowInsets(EdgeInsets(top: first ? 4 : 6, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(colors.backgroundSecondary)
            // Hairline above a new day (between groups), none between a header and its first row.
            .listRowSeparator(first ? .hidden : .visible, edges: .top)
            .listRowSeparator(.hidden, edges: .bottom)
    }
}

/// Rows grouped by day, newest first (§1.15a); Upcoming last.
func stdDayGroups(_ items: [StdSuggestion]) -> [(name: String, items: [StdSuggestion])] {
    var order: [String] = []
    var byGroup: [String: [StdSuggestion]] = [:]
    let sorted = items.enumerated().sorted { ($0.element.groupRank, $0.offset) < ($1.element.groupRank, $1.offset) }.map(\.element)
    for item in sorted {
        if byGroup[item.group] == nil { order.append(item.group) }
        byGroup[item.group, default: []].append(item)
    }
    return order.map { ($0, byGroup[$0] ?? []) }
}

// MARK: - LHTag (§1.16)

struct StdTag: View {
    let text: String
    let ink: Color
    var wash: Color? = nil
    var wraps = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(ink)
            .lineLimit(wraps ? nil : 1)
            .fixedSize(horizontal: false, vertical: wraps)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .frame(minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(wash ?? ink.opacity(0.12)))
    }
}

// MARK: - LHChip (§1.16)

struct StdChip: View {
    let text: String
    var selected = false
    /// Equal-width chips in a row (the Inbox question).
    var fill = false
    var action: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(selected ? colors.onAction : colors.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(maxWidth: fill ? .infinity : nil, minHeight: 34)
                .background(Capsule().fill(selected ? colors.action : colors.backgroundTertiary))
                .overlay(Capsule().strokeBorder(colors.border, lineWidth: selected ? 0 : 0.5))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(StdPressStyle())
    }
}

// MARK: - LHButton (§1.13) and press (§B.3)

struct StdPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(configuration.isPressed ? StdMotion.feedback : StdMotion.quick, value: configuration.isPressed)
    }
}

struct StdButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, tertiary, icon, iconOnBlueprint }
    let kind: Kind
    var destructive = false
    init(_ kind: Kind, destructive: Bool = false) { self.kind = kind; self.destructive = destructive }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// .icon circles grow with Dynamic Type (44 at default, at most 60); the glyph is capped at
    /// xxxLarge so it always sits inside its circle.
    @ScaledMetric(relativeTo: .body) private var iconCircle: CGFloat = 44
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }
    private var circle: CGFloat { min(iconCircle, 60) }

    func makeBody(configuration: Configuration) -> some View {
        styled(configuration.label)
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(configuration.isPressed ? StdMotion.feedback : StdMotion.quick, value: configuration.isPressed)
    }

    @ViewBuilder private func styled(_ label: Configuration.Label) -> some View {
        switch kind {
        case .primary:
            label.font(.body.weight(.semibold))
                .foregroundStyle(colors.onAction)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Capsule().fill(colors.action))
                .contentShape(Capsule())
        case .secondary:
            label.font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.action)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(Capsule().fill(colors.actionSurface))
                .contentShape(Capsule())
        case .tertiary:
            label.font(.subheadline.weight(.semibold))
                .foregroundStyle(destructive ? colors.destructive : colors.action)
                .padding(.horizontal, 4)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        case .icon:
            label.font(.body.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(colors.textSecondary)
                .frame(width: circle, height: circle)
                .background(Circle().fill(colors.backgroundTertiary))
                .contentShape(Circle())
        case .iconOnBlueprint:
            label.font(.body.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(Color.white)
                .frame(width: circle, height: circle)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .contentShape(Circle())
        }
    }
}

// MARK: - LHRow.Action (§1.3): the confirm item

struct StdSuggestion: Identifiable, Equatable {
    enum Source { case calendar, reminder }
    enum Status { case none, notSure, needsHours, mightBeLogged }
    let id: String
    let title: String
    let source: Source
    let when: String
    let category: ActivityCategory?
    let status: Status
    let hours: Double?
    /// The rental it counts toward, when the item names one (moves the hero on confirm).
    var rental: String? = nil
    var canQuickLog: Bool { hours != nil && status != .needsHours }
    var isLikely: Bool { canQuickLog && status == .none }
}

struct StdActionRow: View {
    let item: StdSuggestion
    let confirmed: Bool
    let onConfirm: () -> Void
    /// False under a day header (Inbox): the meta line carries the time only (critique #1).
    var showDay = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    /// One title line at the current text size, so the circle sits on the first line.
    @ScaledMetric(relativeTo: .body) private var titleLine: CGFloat = 22
    /// The circle grows with the text (22pt at default) so it never looks undersized at AX sizes.
    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 22
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    private var isStatus: Bool { item.status != .none }

    private var tag: (String, Color, Color)? {
        switch item.status {
        case .notSure: return (L("Not sure"), colors.caution, colors.cautionSurface)
        case .needsHours: return (L("Needs hours"), colors.caution, colors.cautionSurface)
        case .mightBeLogged: return (L("Might be logged"), colors.informational, colors.informationalSurface)
        case .none:
            guard let c = item.category else { return nil }
            return (c.stdLabel, colors.categoryTagInk(c), colors.categoryTagWash(c))
        }
    }

    /// "Oct 19 9–10:30" → ("Oct 19", "9–10:30"); "Nov 1" → ("Nov 1", nil).
    private var dayTime: (day: String, time: String?) {
        let parts = item.when.split(separator: " ")
        guard let last = parts.last, last.contains("–"), parts.count > 1 else { return (item.when, nil) }
        return (parts.dropLast().joined(separator: " "), String(last))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            control
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    title
                    meta
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 8) {
                            hours
                            if let tag { StdTag(text: tag.0, ink: tag.1, wash: tag.2).fixedSize() }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            hours
                            // Wraps instead of pushing the row past the card edge (AX3).
                            if let tag { StdTag(text: tag.0, ink: tag.1, wash: tag.2, wraps: true) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    meta
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                hours.padding(.top, 2)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(StdCanon.notRentalWork)) {}
    }

    /// 22pt circle on the first title line, 16pt from the card edge; the tap area is 44 x 44.
    private var control: some View {
        Button(action: onConfirm) {
            ZStack {
                Circle().strokeBorder(confirmed ? colors.positive : colors.textTertiary, lineWidth: 1.5)
                Circle().fill(colors.positive).opacity(confirmed ? 1 : 0)
                Image(systemName: "checkmark").resizable().scaledToFit().frame(width: circle * 0.45, height: circle * 0.45)
                    .foregroundStyle(Color.white)
                    .opacity(confirmed ? 1 : 0)
            }
            .frame(width: circle, height: circle)
            .frame(width: circle, height: max(circle, titleLine))
            .padding(11)
            .contentShape(Rectangle())
            .padding(-11)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(item.canQuickLog ? L("Confirm \(StdFormat.hours(item.hours))") : L("Review and confirm"))
        .accessibilityIdentifier("row.confirm.\(item.id)")
    }

    private var title: some View {
        Text(item.title)
            .font(.body.weight(.semibold))
            .foregroundStyle(colors.textPrimary)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sourceIcon: String { item.source == .calendar ? "calendar" : "checklist" }
    private var sourceWord: String { item.source == .calendar ? L("Calendar") : L("Reminder") }

    private func metaText(word: Bool, time: Bool) -> Text {
        let glyph = Text(Image(systemName: sourceIcon))
        // Word joiners keep "10–11:30" together when the meta wraps at large sizes.
        if !showDay {
            // Under a day header: "Calendar · 12–2", or just the source when there is no time.
            guard let range = item.timeRange?.replacingOccurrences(of: "–", with: "\u{2060}–\u{2060}") else {
                return glyph + Text(verbatim: " ") + Text(sourceWord)
            }
            return word ? glyph + Text(verbatim: " ") + Text(L("\(sourceWord) · \(range)")) : glyph + Text(verbatim: " ") + Text(range)
        }
        let when = (time ? item.when : dayTime.day).replacingOccurrences(of: "–", with: "\u{2060}–\u{2060}")
        return word ? glyph + Text(verbatim: " ") + Text(L("\(sourceWord) · \(when)"))
                    : glyph + Text(verbatim: " ") + Text(when)
    }

    /// Fit order: the word "Calendar" goes first, then the tag yields (a status tag keeps its place
    /// and the time range yields instead). Nothing is cut mid-word. At AX the meta wraps.
    @ViewBuilder private var meta: some View {
        if typeSize.isAccessibilitySize {
            metaText(word: false, time: true)
                .font(.subheadline).foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(L("\(sourceWord), \(item.when)"))
        } else {
            ViewThatFits(in: .horizontal) {
                metaLine(word: true, time: true, tag: true)
                metaLine(word: false, time: true, tag: true)
                if isStatus {
                    metaLine(word: false, time: false, tag: true)
                    metaLine(word: false, time: true, tag: false)
                } else {
                    metaLine(word: false, time: true, tag: false)
                    metaLine(word: false, time: false, tag: false)
                }
            }
            .font(.subheadline).foregroundStyle(colors.textSecondary)
        }
    }

    private func metaLine(word: Bool, time: Bool, tag showTag: Bool) -> some View {
        HStack(spacing: 6) {
            metaText(word: word, time: time).lineLimit(1).fixedSize()
            if showTag, let tag { StdTag(text: tag.0, ink: tag.1, wash: tag.2).fixedSize().stdMeasure("tag.\(item.id).\(tag.0)") }
        }
    }

    private var hours: some View {
        Text(StdFormat.hours(item.hours))
            .font(.subheadline.weight(.semibold)).fontDesign(.rounded).monospacedDigit()
            .foregroundStyle(item.hours == nil ? colors.textTertiary : colors.textPrimary)
            .lineLimit(1)
            .fixedSize()
    }
}

struct StdMetaLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon; configuration.title }
    }
}

// MARK: - LHRow.Browse (§1.4)

struct StdBrowseRow<Leading: View>: View {
    let title: String
    let meta: String
    var value: String? = nil
    var valueInk: Color? = nil
    var chevron = true
    var metaLines = 1
    /// A 3pt progress bar under the text (critique #7): fraction and intent ink.
    var progress: (Double, Color)? = nil
    /// Put the value under the text (as at AX sizes) so the meta line gets the full width.
    var stackValue = false
    @ViewBuilder var leading: Leading
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    var body: some View {
        HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
            if !typeSize.isAccessibilitySize { leading.frame(width: 36, height: 36) }
            VStack(alignment: .leading, spacing: typeSize.isAccessibilitySize ? 0 : 2) {
HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(colors.textPrimary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
                    // Stacked value at large text: it rides the title line so the meta keeps full width.
                    if stackValue && !typeSize.isAccessibilitySize, let value {
                        Spacer(minLength: 4)
                        valueText(value)
                    }
                }
                Text(meta).font(.subheadline).foregroundStyle(colors.textSecondary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : metaLines)
                    .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
                if typeSize.isAccessibilitySize, let value { valueText(value) }
                if let progress {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(colors.backgroundTertiary)
                            Capsule().fill(progress.1).frame(width: max(3, g.size.width * min(1, progress.0)))
                        }
                    }
                    .frame(height: 3)
                    .padding(.top, typeSize.isAccessibilitySize ? 2 : 5)
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !typeSize.isAccessibilitySize && !stackValue, let value { valueText(value) }
            if chevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(colors.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func valueText(_ v: String) -> some View {
        Text(v).font(.subheadline.weight(.semibold)).fontDesign(.rounded).monospacedDigit()
            .foregroundStyle(valueInk ?? colors.textPrimary).lineLimit(1).fixedSize()
    }
}

// MARK: - LHTile.Stat (§1.11)

struct StdStatTile: View {
    let value: String
    let label: String
    var ink: Color? = nil
    var glyph: String? = nil
    @Environment(\.colorScheme) private var scheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let glyph {
                    Image(systemName: glyph).font(.headline).foregroundStyle(ink ?? colors.textPrimary)
                        .accessibilityHidden(true)
                }
                Text(value).font(.title2.weight(.bold)).fontDesign(.rounded).monospacedDigit()
                    .foregroundStyle(colors.textPrimary)
                    .contentTransition(.numericText())
            }
            Text(label).font(.caption).foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.backgroundSecondary))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - LHFootnote.cpa (§1.22)

struct StdCPAFootnote: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(StdCanon.cpa)
            .font(.footnote)
            .foregroundStyle(AdaptiveColors(colorScheme: scheme).textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - LHSegmented (§1.8)

struct StdSegmented: View {
    let options: [String]
    @Binding var selection: Int
    @Namespace private var thumb
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                Button {
                    withAnimation(reduceMotion ? StdMotion.quick : StdMotion.segment) { selection = i }
                } label: {
                    Text(options[i])
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(i == selection ? colors.textPrimary : colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .frame(minWidth: 64)
                        .background {
                            if i == selection {
                                Capsule().fill(colors.backgroundSecondary)
                                    .overlay(Capsule().strokeBorder(colors.border, lineWidth: 0.5))
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(i == selection ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(minHeight: 36)
        .background(Capsule().fill(colors.backgroundTertiary))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - LHStepper (§1.9)

struct StdStepper: View {
    @Binding var hours: Double
    /// "Not said": the missing-value treatment (caution ink, critique #6) until a step is taken.
    var missing = false
    var onStep: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: scheme) }

    /// One right rail (critique #6): − and + lead, the value ends on the same trailing line as the
    /// other rows' values (a chevron's width in from the edge).
    var body: some View {
        let layout = typeSize >= .accessibility3 ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            HStack(spacing: 8) {
                Button { hours = max(0, hours - 0.25); onStep() } label: { Image(systemName: "minus") }
                    .buttonStyle(StdButtonStyle(.icon)).accessibilityLabel(L("Less"))
                Button { hours = min(24, hours + 0.25); onStep() } label: { Image(systemName: "plus") }
                    .buttonStyle(StdButtonStyle(.icon)).accessibilityLabel(L("More"))
            }
            Text(missing ? L("Not said") : StdFormat.hours(hours))
                .font(missing ? .body : .title2.weight(.semibold)).fontDesign(missing ? .default : .rounded).monospacedDigit()
                .foregroundStyle(missing ? colors.caution : colors.textPrimary)
                .contentTransition(.numericText(value: hours))
                .animation(StdMotion.standard, value: hours)
                .frame(minWidth: 100, alignment: .trailing)
                .padding(.trailing, 17)
        }
        .sensoryFeedback(.selection, trigger: hours)
    }
}

// MARK: - Counting number for heroCountUp

/// Digits count from the previous value to the new one; the animation is whatever the caller's
/// transaction carries (`StdMotion.count` = easeOut 0.60).
struct StdCountingText: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { Text(verbatim: "\(Int(value.rounded()))") }
}

/// Motion log for the hand-off: prints each named motion with its start time when -LHStdMotionLog is set.
enum StdMotionLog {
    static let on = ProcessInfo.processInfo.arguments.contains("-LHStdMotionLog")
    static func mark(_ name: String) {
        guard on else { return }
        FileHandle.standardError.write("STDMOTION \(name) \(CACurrentMediaTime())\n".data(using: .utf8) ?? Data())
    }
}
#endif

#if DEBUG
// MARK: - Geometry log for the density hand-off (-LHStdGeom): "STDGEOM name minY height minX width" in points.

enum StdGeom {
    static let on = ProcessInfo.processInfo.arguments.contains("-LHStdGeom")
    static func log(_ line: String) {
        guard on else { return }
        FileHandle.standardError.write((line + "\n").data(using: .utf8) ?? Data())
    }
}

extension View {
    @ViewBuilder func stdMeasure(_ name: String) -> some View {
        if StdGeom.on {
            onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in
                StdGeom.log(String(format: "STDGEOM %@ %.1f %.1f %.1f %.1f", name, r.minY, r.height, r.minX, r.width))
            }
        } else {
            self
        }
    }
}
#endif

#if DEBUG
/// rowConfirm's second half: the row fades (0.08) before its height springs to zero (collapse 0.25),
/// clipped, so nothing overlaps or ghosts while the rows below move up.
struct StdCollapse: ViewModifier {
    let fading: Bool
    let collapsed: Bool
    func body(content: Content) -> some View {
        content
            .opacity(fading ? 0 : 1)
            .frame(height: collapsed ? 0 : nil, alignment: .top)
            .clipShape(Rectangle().inset(by: collapsed ? 0 : -60))
    }
}

/// rowConfirm, Reminders-style: the circle fills and ticks (feedback 0.12), the row is held 0.5s so
/// the tick reads, then the removal runs inside withAnimation(.collapse) and the List closes the gap.
@MainActor
enum StdRowConfirm {
    static let hold: UInt64 = 500_000_000
    static func run(id: String, reduceMotion: Bool,
                    fill: @escaping () -> Void,
                    fade: @escaping () -> Void,
                    collapse: @escaping () -> Void,
                    remove: @escaping () -> Void) {
        withAnimation(reduceMotion ? StdMotion.quick : StdMotion.feedback) { fill() }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000 + hold)
            StdMotionLog.mark("rowConfirm.collapse")
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : StdMotion.collapse) { remove() }
        }
    }
}
#endif
