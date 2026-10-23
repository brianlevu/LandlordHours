import SwiftUI
import LucideIcons

// MARK: - Before anything is read: recents, the details line, and the manual door

extension LogTimeSheet {
    /// "RECENT" + up to three one-tap fills. Hidden until there are two past entries.
    var recentsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT")
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .tracking(1.3)
                .foregroundStyle(colors.draftingInk)
            LogChipFlow(spacing: 8) {
                ForEach(recents) { recent in
                    LogChip(title: LogRecents.title(recent, properties: properties, includeHours: !isAX),
                            identifier: "log.recent") { useRecent(recent) }
                        .accessibilityLabel(LogRecents.title(recent, properties: properties))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.recents")
    }

    /// The defaults in words: what Log would record right now. One quiet line.
    var detailsPieces: [String] {
        let who: String
        if isFirstRun {
            let name = FirstPropertyDraft(name: firstRunName).trimmedName
            who = name.isEmpty ? String(localized: "Name your rental") : name
        } else {
            who = properties.first { $0.id == form.propertyId }?.name ?? String(localized: "Choose rental")
        }
        let kind: String
        if let category = form.category {
            kind = form.categoryIsRemembered ? String(localized: "\(category.inboxLabel) (last used)") : category.inboxLabel
        } else {
            kind = String(localized: "Choose kind of work")
        }
        return [who, kind, LogTimeFormat.hours(form.hours), LogTimeFormat.dayWord(form.date)]
    }

    var detailsLine: some View {
        let pieces = detailsPieces
        return LogChipFlow(spacing: 4) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { index, piece in
                HStack(spacing: 4) {
                    Text(verbatim: piece).font(.footnote).foregroundStyle(colors.textSecondary)
                    if index < pieces.count - 1 { Text(verbatim: "\u{00B7}").font(.footnote).foregroundStyle(colors.textSecondary) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Log will record: \(pieces.joined(separator: ", "))"))
        .accessibilityIdentifier("log.details")
    }

    /// The manual door: every field, no reading, for the user who would rather not use the note.
    var enterDetailsButton: some View {
        Button(action: enterManual) {
            HStack(spacing: 8) {
                LucideIcon(image: Lucide.slidersHorizontal, size: 16)
                Text("Enter details yourself").font(.body.weight(.medium))
            }
            .foregroundStyle(colors.actionText)
            .frame(minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.lhPressable)
        .accessibilityHint("Shows every field and turns off auto-fill for this entry.")
        .accessibilityIdentifier("log.enterDetails")
    }

    var autoFillOff: some View {
        HStack {
            Text("Auto-fill is off for this entry.")
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
            Button(action: turnAutoFillOn) {
                Text("Turn on").font(.footnote.weight(.semibold)).foregroundStyle(colors.actionText).frame(minHeight: 44)
            }
            .buttonStyle(.lhPressable)
            .accessibilityIdentifier("log.autoFill.on")
            Spacer(minLength: 0)
        }
    }
}
