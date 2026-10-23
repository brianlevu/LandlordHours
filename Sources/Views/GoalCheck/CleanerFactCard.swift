import SwiftUI
import LucideIcons

// MARK: - Inbox: "A cleaner seems to work at <name>" (2.1, stub-backed)
//
// A fact the calendar suggests, shown as a question. Nothing changes until the owner taps one
// of three equal-weight answers (none filled). The shipped source returns no facts, so this card
// never appears in a real build until the calendar detector lands; DEBUG `-LHCleanerFact`
// injects one for captures and UI tests.

struct CleanerFactCard: View {
    let fact: CleanerFact
    var onAnswered: () -> Void

    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                LucideIcon(image: Lucide.calendar, size: 16)
                    .foregroundStyle(colors.draftingInk)
                    .accessibilityHidden(true)
                Text("From your calendar", tableName: "Home")
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .textCase(.uppercase)
                    .tracking(1.3)
                    .foregroundStyle(colors.draftingInk)
            }
            Text("A cleaner seems to work at \(fact.propertyName)", tableName: "Home")
                .font(.title3.weight(.semibold))
                .foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("cleanerFact.title")
            Text("“\(fact.eventTitle)” is on your calendar there. Do they do more hours at \(fact.propertyName) than you?", tableName: "Home")
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                choice(String(localized: "They do more", table: "Home"), .theyDoMore, id: "cleanerFact.theyDoMore")
                choice(String(localized: "I do more", table: "Home"), .iDoMore, id: "cleanerFact.iDoMore")
                choice(String(localized: "Not sure", table: "Home"), .notSure, id: "cleanerFact.notSure")
            }
            .padding(.top, 4)
            Text("Nothing changes until you tap.", tableName: "Home")
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
            Text(RentalPlanWords.cpaLine)
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cleanerFact.card")
    }

    /// Equal weight: none is filled, so nothing leans toward an answer.
    private func choice(_ title: String, _ answer: CleanerFactInbox.Answer, id: String) -> some View {
        Button {
            let store = RentalPlanStore.shared
            store.setWhoDoesMost(CleanerFactInbox.who(for: answer), for: fact.propertyId)
            CleanerFactInbox.markAnswered(fact)
            RentalPlanAnnouncer.announce(viewModel.rentalPlanContext, store: store)
            onAnswered()
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.action)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(colors.actionSurface))
                .contentShape(Capsule())
        }
        .buttonStyle(.lhPressable)
        .accessibilityIdentifier(id)
    }
}
