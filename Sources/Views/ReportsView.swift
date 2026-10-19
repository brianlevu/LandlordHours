import SwiftUI
import Charts

// MARK: - Reports
//
// Flighty's report, on the Blueprint brand: where each person honestly stands first (the same
// engine values as Today), then where the hours went (property, kind of work, month, who,
// source), then the export. docs/design/2.0-hifi-reference-spec.md §h.

/// The goal Reports measures against. Labels double as the segmented control's titles.
enum GoalMode: String, CaseIterable, Identifiable {
    case reps750 = "REPS 750h"
    case mp500 = "500h"
    case mp100 = "100h"

    var id: String { rawValue }
    var pillLabel: String { rawValue }

    var houseGoal: HouseGoal {
        switch self {
        case .reps750: return .reps750
        case .mp500: return .mp500
        case .mp100: return .mp100
        }
    }

    var targetHours: Double { houseGoal.targetHours }

    init(_ goal: HouseGoal) {
        switch goal {
        case .reps750: self = .reps750
        case .mp500: self = .mp500
        case .mp100: self = .mp100
        }
    }
}

struct ReportsView: View {
    /// Loading hook (owner direction: loading never blocks). Reports' numbers are computed on the
    /// main actor today, so this stays false; when totals or charts move off-thread, set it and
    /// only the numbers and the month chart show `BPLoadingPlaceholder` (DraftingLoader later).
    var isLoading: Bool = false

    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @ObservedObject private var goalManager = GoalManager.shared
    @ObservedObject private var taxProfile = TaxProfileManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedGoal: GoalMode = .reps750
    @State private var showingExportSheet = false
    @State private var showingPaywall = false
    @State private var showingParticipationSheet = false

    // MARK: Data

    private var yearEntries: [TimeEntry] { viewModel.entriesForYear(selectedYear) }
    private var standings: [ReportStanding] { viewModel.reportStandings(goal: selectedGoal.houseGoal, year: selectedYear) }

    private var materialParticipation: TaxQualificationEngine.MaterialParticipationResult {
        viewModel.materialParticipationOverview(year: selectedYear, includeSpouse: viewModel.tracksSpouseJointly)
    }

    private var showsParticipationRow: Bool {
        selectedGoal == .mp100
            && materialParticipation.ownerAndSpouseHours > 100
            && !materialParticipation.meets500HourTest
    }

    private var propertyBars: [(label: String, hours: Double)] {
        ReportsLogic.ranked(viewModel.properties.map { ($0.name, viewModel.hoursForProperty($0, year: selectedYear)) })
    }

    private var categoryBars: [(label: String, hours: Double)] {
        let byCategory = Dictionary(grouping: yearEntries.filter(\.countsForREPS), by: \.category)
            .map { ($0.key.inboxLabel, $0.value.reduce(0) { $0 + $1.hours }) }
        return ReportsLogic.ranked(byCategory)
    }

    private var whoBars: [(label: String, hours: Double)] {
        let me = yearEntries.filter { $0.participant == .selfParticipant }.reduce(0) { $0 + $1.hours }
        let spouse = yearEntries.filter { $0.participant == .spouse }.reduce(0) { $0 + $1.hours }
        guard spouse > 0 || taxProfile.spouseTracking else { return [] }
        return [("Me", me), ("Spouse", spouse)]
    }

    private var sourceBars: [(label: String, hours: Double)] {
        let bySource = Dictionary(grouping: yearEntries, by: { RecordSourceBadge(entry: $0) })
            .map { ($0.key.title, $0.value.reduce(0) { $0 + $1.hours }) }
        return ReportsLogic.ranked(bySource)
    }

    private var monthly: [Double] { ReportsLogic.monthlyHours(yearEntries, year: selectedYear) }

    private var throughLine: String {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        if selectedYear < currentYear { return "The \(String(selectedYear)) tax year is closed." }
        if selectedYear > currentYear { return "\(String(selectedYear)) hasn't started yet." }
        let end = calendar.date(from: DateComponents(year: currentYear, month: 12, day: 31)) ?? now
        let days = max(calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: end).day ?? 0, 0)
        return "Through \(now.formatted(.dateTime.month(.abbreviated).day())) · \(days) days left in the year"
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    standingSection
                    if yearEntries.isEmpty {
                        BPEmptyState(
                            symbol: "chart.bar",
                            title: "No hours in \(String(selectedYear)) yet",
                            message: "Log or confirm work and the breakdown fills in here."
                        )
                        .padding(.vertical, 12)
                        .accessibilityIdentifier("reports.empty")
                    } else {
                        breakdown(title: "By property", bars: propertyBars, footnote: "All logged hours that count as real estate work, both of you.")
                        breakdown(title: "By kind of work", bars: categoryBars, footnote: nil)
                        monthSection
                        if !whoBars.isEmpty {
                            breakdown(title: "Who did it", bars: whoBars, footnote: nil)
                        }
                        breakdown(title: "Where the hours came from", bars: sourceBars, footnote: nil)
                    }
                    exportCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, AppSpacing.tabContentBottomInset)
            }
            .scrollIndicators(.hidden)
            .background { LHMobileCanvas() }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingExportSheet) {
                ExportPDFView(year: selectedYear)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(
                    context: .export,
                    year: selectedYear,
                    onUnlocked: { showingExportSheet = true },
                    onClose: { showingPaywall = false }
                )
            }
            .sheet(isPresented: $showingParticipationSheet) {
                ParticipationConfirmationSheet(
                    year: selectedYear,
                    currentAnswer: materialParticipation.noOneParticipatedMore
                ) { answer in
                    taxProfile.setNoOneParticipatedMore(answer, forYear: selectedYear)
                }
            }
            .onAppear {
                selectedGoal = GoalMode(HouseGoal(goalManager.globalGoalType))
                Analytics.reportViewed()
            }
        }
        .accessibilityIdentifier("reports.screen")
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline))) {
                BPScreenTitle(text: "Reports")
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 12) }
                Button(action: exportAction) {
                    BPCapsuleButtonLabel(
                        title: "Export",
                        symbol: subscriptionManager.isPro ? "square.and.arrow.up" : "lock.fill"
                    )
                }
                .buttonStyle(.lhPressable)
                .accessibilityLabel(subscriptionManager.isPro ? "Export report" : "Unlock export")
                .accessibilityIdentifier("reports.export")
            }

            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))) {
                Menu {
                    Picker("Year", selection: $selectedYear) {
                        ForEach(RecordsLogic.availableYears(viewModel.timeEntries), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                } label: {
                    BPFilterChip(title: String(selectedYear), isActive: true)
                }
                .accessibilityLabel("Tax year, \(String(selectedYear))")
                .accessibilityIdentifier("reports.year")

                Picker("Goal", selection: $selectedGoal) {
                    ForEach(GoalMode.allCases) { goal in
                        Text(goal.pillLabel).tag(goal)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("reports.goal")
            }
        }
    }

    // MARK: Standing

    private var standingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            BPSectionHeader(title: "Where you stand")
                .padding(.horizontal, 4)
            ForEach(standings) { standing in
                StandingCard(standing: standing, year: selectedYear, isLoading: isLoading)
            }
            if showsParticipationRow {
                participationRow
            }
            Text(throughLine)
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, 4)
        }
        .lhMotion(AppAnimation.standard, value: selectedGoal)
    }

    private var participationRow: some View {
        let answer = materialParticipation.noOneParticipatedMore
        let title: String
        let symbol: String
        let tint: Color
        switch answer {
        case .none:
            title = "Did anyone else do more?"
            symbol = "questionmark.circle.fill"
            tint = colors.caution
        case .some(true):
            title = "No one participated more"
            symbol = "checkmark.circle.fill"
            tint = colors.positive
        case .some(false):
            title = "Someone participated more"
            symbol = "exclamationmark.circle.fill"
            tint = colors.caution
        }
        return Button {
            showingParticipationSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(answer == nil ? "Answer for \(String(selectedYear)) to settle the 100-hour test." : "Tap to change your answer for \(String(selectedYear)).")
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(answer == nil ? "Answer" : "Change")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(answer == nil ? colors.onAction : colors.action)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(answer == nil ? colors.action : colors.actionSurface))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.backgroundSecondary))
        }
        .buttonStyle(.lhPressable)
        .accessibilityIdentifier("reports.mp100.confirmRow")
        .accessibilityHint("Opens the 100-hour test question")
    }

    // MARK: Breakdown

    private func breakdown(title: String, bars: [(label: String, hours: Double)], footnote: String?) -> some View {
        let total = bars.reduce(0) { $0 + $1.hours }
        let maxValue = bars.map(\.hours).max() ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            BPSectionHeader(title: title, trailing: BPHours.short(total), trailingAccessibility: "\(BPHours.spoken(total)) total")
                .padding(.horizontal, 4)
            VStack(spacing: 2) {
                if bars.isEmpty {
                    Text("Nothing logged here yet.")
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                        BPBarRow(
                            label: bar.label,
                            value: bar.hours,
                            maxValue: maxValue,
                            valueText: BPHours.short(bar.hours),
                            accessibilityValueText: "\(BPHours.spoken(bar.hours)), \(total > 0 ? Int((bar.hours / total * 100).rounded()) : 0) percent"
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.backgroundSecondary))
            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports.section.\(title)")
    }

    private var monthSection: some View {
        let values = monthly
        let total = values.reduce(0, +)
        let symbols = Calendar.current.shortMonthSymbols
        let currentMonth = Calendar.current.component(.month, from: Date())
        let isCurrentYear = Calendar.current.component(.year, from: Date()) == selectedYear
        return VStack(alignment: .leading, spacing: 8) {
            BPSectionHeader(title: "By month", trailing: BPHours.short(total), trailingAccessibility: "\(BPHours.spoken(total)) total")
                .padding(.horizontal, 4)
            Chart {
                ForEach(0..<12, id: \.self) { index in
                    BarMark(
                        x: .value("Month", symbols[index]),
                        y: .value("Hours", values[index])
                    )
                    .foregroundStyle(isCurrentYear && index + 1 > currentMonth ? colors.border : colors.action)
                    .cornerRadius(3)
                    .accessibilityLabel(Calendar.current.monthSymbols[index])
                    .accessibilityValue(BPHours.spoken(values[index]))
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(String(label.prefix(1)))
                                .font(.caption2)
                                .foregroundStyle(colors.textSecondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(colors.border.opacity(0.7))
                    AxisValueLabel {
                        if let hours = value.as(Double.self) {
                            Text("\(Int(hours))h")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(colors.textSecondary)
                        }
                    }
                }
            }
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 200 : 150)
            .opacity(isLoading ? 0 : 1)
            .overlay {
                if isLoading { BPLoadingPlaceholder(kind: .chart, width: nil, height: 150) }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.backgroundSecondary))
            .accessibilityLabel("Hours by month, \(String(selectedYear))")
            .accessibilityIdentifier("reports.monthChart")
        }
    }

    // MARK: Export

    private var exportCard: some View {
        Button(action: exportAction) {
            HStack(spacing: 14) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 22))
                    .foregroundStyle(colors.action)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(colors.actionSurface))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("The record your accountant gets")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subscriptionManager.isPro
                         ? "PDF and CSV of every \(String(selectedYear)) entry, with where it came from."
                         : "PDF and CSV export comes with Pro. Pay once.")
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: subscriptionManager.isPro ? "chevron.right" : "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.backgroundSecondary))
        }
        .buttonStyle(.lhPressable)
        .accessibilityIdentifier("reports.exportCard")
    }

    private func exportAction() {
        if viewModel.canExportPDF() {
            showingExportSheet = true
        } else {
            showingPaywall = true
        }
    }
}

// MARK: - Standing card

/// One person's honest status: hours against the goal, a plain bar, the status in words with a
/// glyph (colour is never the only cue), and the one rule that matters next.
private struct StandingCard: View {
    let standing: ReportStanding
    let year: Int
    var isLoading: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var toneColor: Color {
        switch standing.tone {
        case .positive: return colors.positive
        case .caution: return colors.caution
        case .neutral: return colors.textSecondary
        }
    }

    private var toneSymbol: String {
        switch standing.tone {
        case .positive: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.circle.fill"
        case .neutral: return "circle.dashed"
        }
    }

    private var eyebrow: String {
        "\(String(year)) · \(standing.name)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow)
                .font(AppTypography.drafting)
                .textCase(.uppercase)
                .tracking(1.3)
                .foregroundStyle(colors.draftingInk)
            if isLoading {
                BPLoadingPlaceholder(kind: .number, width: 120, height: 34)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) { number; ofTarget }
                    VStack(alignment: .leading, spacing: 0) { number; ofTarget }
                }
            }
            progressBar
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: toneSymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(toneColor)
                    .accessibilityHidden(true)
                Text(standing.status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(standing.tone == .neutral ? colors.textPrimary : toneColor)
            }
            if let detail = standing.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colors.backgroundSecondary))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(colors.border.opacity(0.6), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(standing.name), \(standing.goal.spokenName)")
        .accessibilityValue("\(BPHours.spoken(standing.hours)) of \(Int(standing.target)) hours. \(standing.status). \(standing.detail ?? "")")
        .accessibilityIdentifier("reports.standing.\(standing.person.rawValue)")
        .onAppear {
            if reduceMotion { appeared = true } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 1).delay(0.05)) { appeared = true }
            }
        }
    }

    private var number: some View {
        Text(BPHours.short(standing.hours))
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(colors.textPrimary)
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var ofTarget: some View {
        Text("of \(Int(standing.target))h")
            .font(.title3)
            .foregroundStyle(colors.textSecondary)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(colors.backgroundTertiary)
                    .overlay(Capsule().strokeBorder(colors.border.opacity(0.7), lineWidth: 0.5))
                Capsule()
                    .fill(standing.tone == .positive ? colors.positive : colors.action)
                    .frame(width: max(standing.progress > 0 ? 8 : 0, proxy.size.width * (appeared ? standing.progress : 0)))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

// MARK: - 100-Hour Test Confirmation Sheet
//
// Shared by Reports and the Settings tax profile. Records the per-tax-year answer to
// IRS Test 3's "did anyone else participate more?" prong. Answers are glyph + text so
// the choice never depends on colour alone.
struct ParticipationConfirmationSheet: View {
    let year: Int
    let currentAnswer: Bool?
    let onAnswer: (Bool?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("\(String(year)) · 100-hour test")
                            .font(AppTypography.drafting)
                            .textCase(.uppercase)
                            .tracking(1.3)
                            .foregroundStyle(colors.draftingInk)

                        Text("Did anyone else, like a property manager or contractor, spend more time on this property than you and your spouse this year?")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("\u{201C}Anyone else\u{201D} means a manager, contractor or co-owner who isn\u{2019}t your spouse.")
                            .font(.subheadline)
                            .foregroundStyle(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: AppSpacing.sm) {
                        answerButton(
                            title: "No one did more",
                            subtitle: "You and your spouse put in the most time",
                            symbol: "checkmark.circle.fill",
                            tint: colors.positive,
                            isSelected: currentAnswer == true,
                            identifier: "participation.answer.yes"
                        ) {
                            onAnswer(true)
                            dismiss()
                        }

                        answerButton(
                            title: "Someone did more",
                            subtitle: "A manager, contractor or co-owner outpaced you",
                            symbol: "exclamationmark.circle.fill",
                            tint: colors.caution,
                            isSelected: currentAnswer == false,
                            identifier: "participation.answer.no"
                        ) {
                            onAnswer(false)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(colors.action)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func answerButton(
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        isSelected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colors.action)
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.backgroundSecondary))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? colors.action : colors.border, lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.lhPressable)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    ReportsView()
        .environmentObject(AppViewModel())
}
