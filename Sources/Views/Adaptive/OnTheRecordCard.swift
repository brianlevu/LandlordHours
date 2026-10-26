import SwiftUI

// MARK: - The work pane's card and "On the record today" (§1.27 two-pane; DU4, DU5, DU11)

/// The work pane's grouped container: opaque `backgroundSecondary`, radius 20 continuous, over the
/// interior wall. The edge is `pageCardEdge` by day and the locked `duoNightCardEdge` (#3C4675) at
/// night, in every two-pane and stacked window (DU11).
struct PaneCard<Content: View>: View {
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .background(colors.backgroundSecondary, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(colorScheme == .dark ? AppColors.duoNightCardEdge : colors.pageCardEdge, lineWidth: 1))
    }
}

/// What is already on the record today at the selected rental (or at every rental on "All
/// rentals"): the honest fill under To confirm. Zero logged keeps the card in place with one line
/// and no figure or button (DU5).
///
/// "Fills the pane to the bar" (§1.27) with content, never with an empty card (D4, D6): when the
/// pane has room left, the card goes on with "Earlier", the rental's own most recent entries, as many
/// whole rows as fit above the bar. The rows that fit are measured, not estimated: every candidate
/// row is laid out once off-screen at the card's width, and the section shows the rows whose bottoms
/// land inside the room the column has left (`fitHeight` less where the section starts). The start
/// does not depend on how many rows show, so the count never feeds back into itself.
struct OnTheRecordCard: View {
    /// nil = every rental.
    let rentalID: UUID?
    /// The height the pane's content column may reach before it would scroll (the scroll view's
    /// visible height less its bottom margin), measured in `OnTheRecordCard.space`. nil = no
    /// "Earlier" section.
    var fitHeight: CGFloat? = nil

    /// The work pane's content column (its top is the scroll content's top).
    static let space = "pane.content"
    /// The most recent entries the section may show.
    static let earlierCap = 24

    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Where the "Earlier" section starts in the column.
    @State private var earlierTop: CGFloat = 0
    /// The bottom of the section's header (index 0) and of each candidate row (1...n), laid out
    /// off-screen at the card's width, tagged with the candidates and type size they were measured
    /// for. A stale measure is ignored, never reset after the fact: a reset in `onChange` could land
    /// after the fresh measure had reported and leave the section empty for good.
    @State private var earlierMeasure = EarlierMeasure()
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    /// Today's entries for the rental, newest first.
    static func entries(_ all: [TimeEntry], rentalID: UUID?, now: Date, calendar: Calendar = .current) -> [TimeEntry] {
        all.filter { calendar.isDate($0.date, inSameDayAs: now) && (rentalID == nil || $0.propertyId == rentalID) }
            .sorted { $0.date > $1.date }
    }

    /// The rental's entries before today, newest first (at most `earlierCap`).
    static func earlier(_ all: [TimeEntry], rentalID: UUID?, now: Date, calendar: Calendar = .current) -> [TimeEntry] {
        let start = calendar.startOfDay(for: now)
        return Array(all.filter { $0.date < start && (rentalID == nil || $0.propertyId == rentalID) }
            .sorted { $0.date > $1.date }
            .prefix(earlierCap))
    }

    /// When one rental is shown and its own history runs out before the bar: the other rentals'
    /// entries before today, newest first (at most `earlierCap`), under "Earlier at other rentals".
    /// Real recent work, not an empty card or bare wall (D4, DU4); none on "All rentals".
    static func earlierElsewhere(_ all: [TimeEntry], rentalID: UUID?, now: Date, calendar: Calendar = .current) -> [TimeEntry] {
        guard let rentalID else { return [] }
        let start = calendar.startOfDay(for: now)
        return Array(all.filter { $0.date < start && $0.propertyId != rentalID }
            .sorted { $0.date > $1.date }
            .prefix(earlierCap))
    }

    /// How many earlier rows fit (pure): the rows whose measured bottom, added to where the section
    /// starts, stays inside the room. 0 when not even the header and one row fit.
    static func fitCount(ends: [Int: CGFloat], candidates: Int, top: CGFloat, room: CGFloat?) -> Int {
        guard let room, candidates > 0, ends[0] != nil else { return 0 }
        var count = 0
        for i in 1...candidates {
            guard let end = ends[i], top + end <= room else { break }
            count = i
        }
        return count
    }

    var body: some View {
        let now = InboxClock.now()
        let today = Self.entries(viewModel.timeEntries, rentalID: rentalID, now: now)
        let own = fitHeight == nil ? [] : Self.earlier(viewModel.timeEntries, rentalID: rentalID, now: now)
        let elsewhere = fitHeight == nil ? [] : Self.earlierElsewhere(viewModel.timeEntries, rentalID: rentalID, now: now)
        let earlier = own + elsewhere
        let ownCount = own.count
        let key = EarlierMeasure.key(earlier.map(\.id), typeSize: typeSize)
        let ends = earlierMeasure.key == key ? earlierMeasure.ends : [:]
        let shown = Self.fitCount(ends: ends, candidates: earlier.count, top: earlierTop, room: fitHeight)
        PaneCard {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "twoPane.record.title", defaultValue: "On the record today", table: "Adaptive"))
                    .font(.headline)
                    .foregroundStyle(colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if !today.isEmpty {
                    Text(LHFormat.hours(today.map(\.hours).reduce(0, +)))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(colors.textPrimary)
                }
            }
            .padding(.horizontal, LHMetrics.cardPadding)
            .padding(.top, 12)
            .padding(.bottom, 8)
            if today.isEmpty {
                LHDivider(leadingInset: LHMetrics.cardPadding)
                Text(String(localized: "twoPane.record.empty", defaultValue: "Nothing logged yet today.", table: "Adaptive"))
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, LHMetrics.cardPadding)
                    .padding(.vertical, 14)
                    .accessibilityIdentifier("pane.record.empty")
            }
            ForEach(today) { entry in
                LHDivider(leadingInset: LHMetrics.cardPadding)
                row(entry, dated: false)
            }
            // Where "Earlier" starts: the same with or without the section, so the fit is stable.
            Color.clear
                .frame(height: 0)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).minY } action: { earlierTop = $0 }
                .accessibilityHidden(true)
            if shown > 0 {
                earlierSection(Array(earlier.prefix(shown)), ownCount: ownCount)
            }
        }
        .background(alignment: .topLeading) {
            // The off-screen measure: every candidate laid out once at the card's width.
            if !earlier.isEmpty {
                earlierSection(earlier, ownCount: ownCount, measuring: true, key: key)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(key)
                    .coordinateSpace(.named("record.measure"))
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane.record")
    }

    /// "Earlier" and its rows, each with its day. `measuring` reports each part's bottom.
    /// `entries` are the rental's own (the first `ownCount`) and then the other rentals'; the
    /// "Earlier at other rentals" heading travels with the first other row, so a fit never ends on it.
    @ViewBuilder private func earlierSection(_ entries: [TimeEntry], ownCount: Int, measuring: Bool = false, key: Int = 0) -> some View {
        VStack(spacing: 0) {
            LHDivider(leadingInset: LHMetrics.cardPadding)
            subheading(ownCount > 0 ? Self.earlierTitle : Self.earlierElsewhereTitle)
                .modifier(MeasureEnd(index: 0, measuring: measuring) { earlierMeasure.record(key: key, index: $0, end: $1) })
            ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                VStack(spacing: 0) {
                    if ownCount > 0, i == ownCount {
                        LHDivider(leadingInset: LHMetrics.cardPadding)
                        subheading(Self.earlierElsewhereTitle)
                    }
                    LHDivider(leadingInset: LHMetrics.cardPadding)
                    row(entry, dated: true, withRental: i >= ownCount)
                }
                .modifier(MeasureEnd(index: i + 1, measuring: measuring) { earlierMeasure.record(key: key, index: $0, end: $1) })
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(measuring ? "" : "pane.record.earlier")
    }

    static var earlierTitle: String {
        String(localized: "twoPane.record.earlier", defaultValue: "Earlier", table: "Adaptive")
    }

    static var earlierElsewhereTitle: String {
        String(localized: "twoPane.record.earlierElsewhere", defaultValue: "Earlier at other rentals", table: "Adaptive")
    }

    private func subheading(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LHMetrics.cardPadding)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ entry: TimeEntry, dated: Bool, withRental: Bool = false) -> some View {
        let note = entry.notes.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        let title = note.isEmpty ? entry.category.inboxLabel : note
        let rental = (rentalID == nil || withRental) ? viewModel.properties.first { $0.id == entry.propertyId }?.name : nil
        let day = dated ? entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) : nil
        let meta = [day, rental, note.isEmpty ? nil : entry.category.inboxLabel].compactMap { $0 }.joined(separator: " · ")
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(LHFormat.hours(entry.hours))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(colors.textPrimary)
        }
        .padding(.horizontal, LHMetrics.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: LHMetrics.rowMinHeight)
        .accessibilityElement(children: .combine)
    }
}

/// The off-screen measure of the "Earlier" rows and what it was measured for (pure).
struct EarlierMeasure: Equatable {
    var key: Int = 0
    var ends: [Int: CGFloat] = [:]

    static func key(_ ids: [UUID], typeSize: DynamicTypeSize) -> Int {
        var hasher = Hasher()
        hasher.combine(ids)
        hasher.combine(typeSize)
        return hasher.finalize()
    }

    /// A report for a newer key replaces the old measure; one for the current key adds to it.
    mutating func record(key: Int, index: Int, end: CGFloat) {
        if key != self.key { self = EarlierMeasure(key: key) }
        ends[index] = end
    }
}

/// Reports a part's bottom in an off-screen measure's space (no-op on the shown copy).
struct MeasureEnd: ViewModifier {
    let index: Int
    let measuring: Bool
    var space: String = "record.measure"
    let report: (Int, CGFloat) -> Void

    func body(content: Content) -> some View {
        if measuring {
            content.onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(space)).maxY } action: { report(index, $0) }
        } else {
            content
        }
    }
}
