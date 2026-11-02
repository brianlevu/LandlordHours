import SwiftUI

#if DEBUG
// MARK: - The two next-worst screens, same idea (2.3.1 quiet sandbox)
//
// Pace reminders: each row says when, in five words or fewer; the sample note folds behind one row;
// the footnote goes (the Care row already says what it is about).
// Filing and goal: rows carry no sentences and sections no footers. A sentence moves into the sheet
// its row opens (the 50% rule into "Other work hours", the 100-hour rule into its question), and one
// "How these work" row leads to the lessons that already explain the spouse and grouping rules.

struct QuietRemindersView: View {
    var sampleOpen = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var weekly = true
    @State private var behind = false
    @State private var yearEnd = true
    @State private var care = true
    @State private var showsSample = false

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                section("Your pace") {
                    LHRowGroup {
                        toggle("Weekly pace", "Sundays, 6 PM", $weekly)
                        LHDivider(leadingInset: 16)
                        toggle("Behind pace", "If you fall 2 weeks behind", $behind)
                        LHDivider(leadingInset: 16)
                        toggle("Year end", "Dec 1 and Dec 20", $yearEnd)
                    }
                }
                section("Your rentals") {
                    LHRowGroup { toggle("Care plan", "When upkeep comes due", $care) }
                }
                section("Quiet hours") {
                    LHRowGroup {
                        LHRow.Browse(title: "Never between", value: "8 PM \u{2013} 8 AM", systemImage: "moon", tint: .neutral, action: {})
                    }
                }
                LHRowGroup {
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0)) { showsSample.toggle() }
                    } label: {
                        HStack(spacing: 12) {
                            LHRowGlyph(systemImage: "bell.badge", tint: .neutral)
                            Text("See a sample").font(.body).foregroundStyle(colors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            LHChevron(systemName: "chevron.down").rotationEffect(.degrees(showsSample ? 180 : 0))
                        }
                        .padding(LHRow.insets)
                        .frame(minHeight: LHMetrics.rowMinHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(LHButton.press)
                    .accessibilityHint(showsSample ? "Hides the sample" : "Shows a sample weekly note")
                }
                if showsSample {
                    NudgePreviewCard(title: "Your week",
                                     message: "420 of 750 this year. About 38h a week gets you to 750 by Dec 31.",
                                     when: "Sun 6 PM")
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .background { LHCanvas() }
        .lhDetailScreen("Pace reminders", subtitle: "A few a month at most.",
                        back: LHBackAction(label: "Back", identifier: "quiet.reminders.back") { dismiss() })
        .hidesAppTabBar()
        .onAppear { showsSample = sampleOpen }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            LHSectionHeader(title).padding(.horizontal, 4)
            content()
        }
    }

    private func toggle(_ title: String, _ when: String, _ isOn: Binding<Bool>) -> some View {
        LHRow.Toggle(title, subtitle: when, isOn: isOn)
            .padding(LHRow.insets)
            .frame(minHeight: LHMetrics.rowMinHeight)
    }
}

struct QuietFilingView: View {
    var showsHalfSheet = false
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var taxProfile = TaxProfileManager.shared
    @ObservedObject private var goalManager = GoalManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var halfSheet = false
    @State private var hoursText = ""

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        List {
            Section {
                LongTailValueRow(label: "Filing status", value: taxProfile.filingStatus.rawValue, accessory: .menu)
                    .longTailRow(separatorInset: LHRow.insets.leading)
                LHRow.Toggle("Spouse hours", isOn: $taxProfile.spouseTracking)
                    .longTailRow(separatorInset: LHRow.insets.leading, toggle: true)
            } header: { LHSectionHeader("You", leadsList: true).textCase(nil) }

            Section {
                LongTailValueRow(label: "Goal", value: goalManager.goalChoice.title, accessory: .menu)
                    .longTailRow(separatorInset: LHRow.insets.leading)
                LongTailValueRow(label: "Tax year", value: String(taxProfile.taxYear), accessory: .menu)
                    .longTailRow(separatorInset: LHRow.insets.leading)
                LHRow.Toggle("Group your rentals", isOn: $taxProfile.groupingElection)
                    .longTailRow(separatorInset: LHRow.insets.leading, toggle: true)
            } header: { LHSectionHeader("Goal").textCase(nil) }

            Section {
                Button { halfSheet = true } label: {
                    LongTailValueRow(label: "Other work hours", value: "Not set", accessory: .disclosure)
                }
                .buttonStyle(LHButton.press)
                .longTailRow(separatorInset: LHRow.insets.leading)
                LongTailValueRow(label: "Did anyone else do more?", value: "Not answered", accessory: .disclosure)
                    .longTailRow(separatorInset: LHRow.insets.leading)
            } header: { LHSectionHeader("Your other work").textCase(nil) }

            Section {
                ForEach(viewModel.properties) { property in
                    LHRow.Browse(title: property.name, value: property.propertyType.rawValue,
                                 systemImage: "house", tint: .neutral, showsChevron: false)
                        .longTailRow()
                }
            } header: { LHSectionHeader("Your rentals", count: viewModel.properties.count).textCase(nil) }

            Section {
                LHRow.Browse(title: "How these work", systemImage: "book", tint: .neutral, action: {})
                    .longTailRow()
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(LHMetrics.sectionGap)
        .lhListGutter()
        .scrollContentBackground(.hidden)
        .background { LHCanvas() }
        .lhTabScreen("Filing and goal", subtitle: "What decides which hours count.",
                     back: LHBackAction(label: "Back", identifier: "quiet.filing.back") { dismiss() })
        .hidesAppTabBar()
        .sheet(isPresented: $halfSheet) {
            LHSheet("Other work hours", onClose: { halfSheet = false }) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("For the 750, your rental hours have to be more than half of all your work hours. Add your W-2 or other job hours.")
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                    LHField("Hours", text: $hoursText, accessibilityLabel: "Other work hours", identifier: "quiet.filing.hours")
                        .keyboardType(.numberPad)
                }
            } footer: {
                Button("Save") { halfSheet = false }.buttonStyle(LHButton.primary)
            }
            .lhSheetPresentation()
        }
        .onAppear { halfSheet = showsHalfSheet }
    }
}
#endif
