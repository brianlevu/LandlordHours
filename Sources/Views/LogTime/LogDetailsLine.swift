import SwiftUI

// MARK: - Before anything is read: quick picks, the details line, and the manual door

extension LogTimeSheet {
    /// Quick picks: up to three one-tap fills of rental, kind and hours ("Repairs · Pine Cabin · 1h"),
    /// from the user's own recent entries. Hidden until there are two past entries. At AX sizes
    /// each pick is a full-width secondary button so the whole phrase can wrap.
    var recentsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The day-header style without its 28pt row: with the keyboard up the strip, the details
            // line and "Enter details yourself" all sit above the pinned primary (S7).
            Text(lt("Recent"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.textSecondary)
                .accessibilityAddTraits(.isHeader)
            if isAX {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(recents) { recent in
                        Button(LogRecents.title(recent, properties: properties, includeHours: false)) { useRecent(recent) }
                            .buttonStyle(LHButton.secondary)
                            .accessibilityLabel(LogRecents.title(recent, properties: properties))
                            .accessibilityIdentifier("log.recent")
                    }
                }
            } else {
                // One strip (§1.16), edge to edge with its own 20pt inner gutter, so the recents keep one
                // row above the keyboard (owner's pick 2026-10-27: the fastest way to log stays visible).
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(recents) { recent in
                            LHChip(LogRecents.title(recent, properties: properties), isSelected: false) { useRecent(recent) }
                                .accessibilityLabel(LogRecents.title(recent, properties: properties))
                                .accessibilityIdentifier("log.recent")
                        }
                    }
                    .padding(.horizontal, LHMetrics.gutter)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -LHMetrics.gutter)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.recents")
    }

    /// The defaults in words: what Log would record right now.
    var detailsPieces: [String] {
        let who: String
        if isFirstRun {
            let name = FirstPropertyDraft(name: firstRunName).trimmedName
            who = name.isEmpty ? lt("Name your rental") : name
        } else {
            who = properties.first { $0.id == form.propertyId }?.name ?? lt("Choose rental")
        }
        let kind: String
        if let category = form.category {
            kind = form.categoryIsRemembered ? lt("\(category.inboxLabel) (last used)") : category.inboxLabel
        } else {
            kind = lt("Choose kind of work")
        }
        return [who, kind, LogTimeFormat.hours(form.hours), LogTimeFormat.dayWord(form.date)]
    }

    var detailsLine: some View {
        let pieces = detailsPieces
        return Text(pieces.joined(separator: LogTimeFormat.dot))
            .font(.footnote)
            .foregroundStyle(colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lt("Log will record: \(pieces.joined(separator: ", "))"))
            .accessibilityIdentifier("log.details")
    }

    /// The manual door: every field, no reading, for the user who would rather not use the note.
    var enterDetailsButton: some View {
        Button(action: enterManual) {
            Label(lt("Enter details yourself"), systemImage: "slider.horizontal.3")
        }
        .buttonStyle(LHButton.tertiary)
        .accessibilityHint(lt("Shows every field and turns off auto-fill for this entry."))
        .accessibilityIdentifier("log.enterDetails")
    }

    var autoFillOff: some View {
        let layout = isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            Text(lt("Auto-fill is off for this entry."))
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
            Button(lt("Turn on"), action: turnAutoFillOn)
                .buttonStyle(LHButton.tertiary)
                .accessibilityIdentifier("log.autoFill.on")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
