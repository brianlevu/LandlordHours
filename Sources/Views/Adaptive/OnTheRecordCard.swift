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
struct OnTheRecordCard: View {
    /// nil = every rental.
    let rentalID: UUID?
    /// Stretch to the height it is given (the work pane fills to the bar).
    var fills = false

    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    /// Today's entries for the rental, newest first.
    static func entries(_ all: [TimeEntry], rentalID: UUID?, now: Date, calendar: Calendar = .current) -> [TimeEntry] {
        all.filter { calendar.isDate($0.date, inSameDayAs: now) && (rentalID == nil || $0.propertyId == rentalID) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        let today = Self.entries(viewModel.timeEntries, rentalID: rentalID, now: InboxClock.now())
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
                row(entry)
            }
            if fills { Spacer(minLength: 0) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane.record")
    }

    private func row(_ entry: TimeEntry) -> some View {
        let note = entry.notes.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        let title = note.isEmpty ? entry.category.inboxLabel : note
        let rental = rentalID == nil ? viewModel.properties.first { $0.id == entry.propertyId }?.name : nil
        let meta = [rental, note.isEmpty ? nil : entry.category.inboxLabel].compactMap { $0 }.joined(separator: " · ")
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
