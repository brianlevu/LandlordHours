import SwiftUI
import Charts

// MARK: - Reports
//
// The ring's screen (standard §1.12, §H.5): where each person honestly stands first (the same
// engine values as Today), the two pace tiles that left Today, then where the hours went (rental,
// kind of work, month, who, source), then the PDF. Plain canvas: the house sits on Today and the
// rental page, so two heroes never compete here. The one thing on a screen set in the drafting
// mono is the ring card's eyebrow (§C, mono labels).

/// The goal Reports measures against. Labels double as the segmented control's titles.
enum GoalMode: String, CaseIterable, Identifiable {
    case reps750 = "750h"
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
    /// main actor today, so this stays false; when totals or charts move off-thread, set it and the
    /// numbers and the month chart show as placeholders.
    var isLoading: Bool = false

    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @ObservedObject private var goalManager = GoalManager.shared
    @ObservedObject private var taxProfile = TaxProfileManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedGoal: GoalMode = .reps750
    @State private var showingExportSheet = false
    @State private var paywall: ProPaywallRequest?
    @State private var showingParticipationSheet = false

    private var ax: Bool { dynamicTypeSize.isAccessibilitySize }

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

    private var rentalRows: [ReportsRentalRow] {
        let calendar = Calendar.current
        let today = viewModel.timeEntries.filter { calendar.isDateInToday($0.date) }
        let loggedToday = Set(today.map(\.propertyId))
        return ReportsLogic.rentalRows(
            rentals: viewModel.properties.map { ($0.id, $0.name, viewModel.hoursForProperty($0, year: selectedYear), loggedToday.contains($0.id)) },
            goalHours: selectedGoal.targetHours
        )
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
        return [(RR.t("reports.who.me", "Me"), me), (RR.t("reports.who.spouse", "Spouse"), spouse)]
    }

    private var sourceBars: [(label: String, hours: Double)] {
        let bySource = Dictionary(grouping: yearEntries, by: { RecordSourceBadge(entry: $0) })
            .map { ($0.key.title, $0.value.reduce(0) { $0 + $1.hours }) }
        return ReportsLogic.ranked(bySource)
    }

    private var monthly: [Double] { ReportsLogic.monthlyHours(yearEntries, year: selectedYear) }

    /// "Through Oct 19 · 73 days left in the year", or what a closed or future year is.
    private var throughLine: String {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        if selectedYear < currentYear { return RR.t("reports.through.closed", "The \(String(selectedYear)) tax year is closed.") }
        if selectedYear > currentYear { return RR.t("reports.through.future", "\(String(selectedYear)) hasn\u{2019}t started yet.") }
        let day = now.formatted(.dateTime.month(.abbreviated).day())
        let days = ReportsLogic.daysLeft(now: now, calendar: calendar)
        return RR.t("reports.through.open", "Through \(day) \u{00B7} \(days) days left in the year")
    }

    /// Days since the first record of the year, so a pace waits for enough hours (Today's rule).
    private var daysOfData: Int {
        let calendar = Calendar.current
        guard let first = yearEntries.map(\.date).min() else { return 0 }
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: Date())).day ?? 0)
    }

    private var paceTiles: [ReportsTile] {
        guard let lead = standings.first else { return [] }
        let rep = selectedGoal == .reps750 ? viewModel.repsStatus(participant: .selfParticipant, year: selectedYear) : nil
        return ReportsLogic.paceTiles(
            standing: lead, rep: rep, year: selectedYear,
            paceReady: TodayHeroCopy.paceIsReady(hours: lead.hours, daysOfData: daysOfData)
        )
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                    header
                    controls
                    standingSection
                    if yearEntries.isEmpty {
                        LHEmptyState(
                            systemImage: "chart.bar",
                            tone: .action,
                            headline: RR.t("reports.empty.title", "No hours in \(String(selectedYear)) yet"),
                            message: RR.t("reports.empty.message", "Log or confirm work and the breakdown fills in here.")
                        )
                        .accessibilityIdentifier("reports.empty")
                    } else {
                        rentalSection
                        barSection(title: RR.t("reports.section.kind", "By kind of work"), bars: categoryBars)
                        monthSection
                        if !whoBars.isEmpty {
                            barSection(title: RR.t("reports.section.who", "Who did it"), bars: whoBars)
                        }
                        barSection(title: RR.t("reports.section.source", "Where the hours came from"), bars: sourceBars)
                    }
                    exportCard
                }
                .padding(.horizontal, LHMetrics.gutter)
                .padding(.top, 8)
                .padding(.bottom, LHMetrics.sectionGap)
            }
            .scrollIndicators(.hidden)
            .background { LHCanvas() }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingExportSheet) {
                ExportPDFView(year: selectedYear)
            }
            .proPaywall($paywall)
            .sheet(isPresented: $showingParticipationSheet) {
                ParticipationConfirmationSheet(
                    year: selectedYear,
                    currentAnswer: materialParticipation.noOneParticipatedMore
                ) { answer in
                    taxProfile.setNoOneParticipatedMore(answer, forYear: selectedYear)
                }
            }
            .onAppear {
                selectedGoal = GoalMode(goalManager.houseGoal)
                Analytics.reportViewed()
            }
        }
        .accessibilityIdentifier("reports.screen")
    }

    // MARK: Header and controls

    private var header: some View {
        ScreenHeader(
            title: RR.t("reports.title", "Reports"),
            subtitle: throughLine,
            back: (label: RR.t("reports.back", "Back to Today"), identifier: "shell.backToToday", action: {
                NotificationCenter.default.post(name: .switchToTab, object: ShellTab.todayIndex)
            }),
            trailing: (symbol: "square.and.arrow.up", label: RR.t("reports.export.label", "Export report"),
                       identifier: "reports.export", action: exportAction)
        )
    }

    /// The year chip and the goal switcher share a row while they fit; otherwise the switcher takes
    /// its own row.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                yearMenu
                goalPicker
            }
            VStack(alignment: .leading, spacing: 8) {
                yearMenu
                goalPicker
            }
        }
        .padding(.top, -8)
    }

    private var yearMenu: some View {
        Menu {
            Picker(RR.t("reports.year", "Year"), selection: $selectedYear) {
                ForEach(RecordsLogic.availableYears(viewModel.timeEntries), id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
        } label: {
            LHChip(String(selectedYear), systemImage: "calendar", isSelected: false) {}
                .allowsHitTesting(false)
        }
        .fixedSize()
        .accessibilityLabel(RR.t("reports.year.spoken", "Tax year, \(String(selectedYear))"))
        .accessibilityIdentifier("reports.year")
    }

    private var goalPicker: some View {
        LHSegmented(
            GoalMode.allCases.map { LHSegmented<GoalMode>.Option($0, $0.pillLabel) },
            selection: $selectedGoal,
            accessibilityLabel: RR.t("reports.goal", "Goal")
        )
        .accessibilityIdentifier("reports.goal")
    }

    // MARK: Standing

    private var standingSection: some View {
        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            LHSectionHeader(RR.t("reports.section.stand", "Where you stand"))
            VStack(spacing: 12) {
                ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
                    if index == 0 {
                        RingStandingCard(standing: standing, year: selectedYear, isLoading: isLoading)
                    } else {
                        CompactStandingCard(standing: standing, year: selectedYear, isLoading: isLoading)
                    }
                }
                if showsParticipationRow { participationRow }
                if !paceTiles.isEmpty {
                    LHTile.StatGrid {
                        ForEach(paceTiles, id: \.label) { tile in
                            LHTile.Stat(value: tile.value, label: tile.label)
                        }
                    }
                    .accessibilityIdentifier("reports.paceTiles")
                }
            }
        }
        .lhMotion(AppAnimation.standard, value: selectedGoal)
    }

    private var participationRow: some View {
        let answer = materialParticipation.noOneParticipatedMore
        let title: String
        let symbol: String
        let tint: LHRowGlyph.Tint
        switch answer {
        case .none:
            title = RR.t("reports.participation.ask", "Did anyone else do more?")
            symbol = "questionmark.circle.fill"
            tint = .caution
        case .some(true):
            title = RR.t("reports.participation.nobody", "No one did more")
            symbol = "checkmark.circle.fill"
            tint = .positive
        case .some(false):
            title = RR.t("reports.participation.someone", "Someone did more")
            symbol = "exclamationmark.circle.fill"
            tint = .caution
        }
        let meta = answer == nil
            ? RR.t("reports.participation.meta.ask", "Answer for \(String(selectedYear)) to settle the 100-hour test.")
            : RR.t("reports.participation.meta.change", "Tap to change your answer for \(String(selectedYear)).")
        return LHRowGroup {
            LHRow.Browse(
                title: title,
                meta: meta,
                value: answer == nil ? RR.t("reports.participation.answer", "Answer") : RR.t("reports.participation.change", "Change"),
                systemImage: symbol,
                tint: tint,
                action: { showingParticipationSheet = true }
            )
        }
        .accessibilityIdentifier("reports.mp100.confirmRow")
        .accessibilityHint(RR.t("reports.participation.hint", "Opens the 100-hour test question"))
    }

    // MARK: Breakdowns

    private func sectionTitle(_ title: String, total: Double) -> String {
        RR.t("reports.header.total", "\(title) \u{00B7} \(LHFormat.hours(total))")
    }

    private var rentalSection: some View {
        let rows = rentalRows
        let total = rows.reduce(0) { $0 + $1.hours }
        let title = RR.t("reports.section.rental", "By rental")
        return VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            LHSectionHeader(sectionTitle(title, total: total))
            LHRowGroup {
                if rows.isEmpty {
                    emptyBar
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { LHDivider(leadingInset: LHRow.insets.leading + 44 + 12) }
                        LHRow.Browse(
                            title: row.name,
                            meta: ReportsLogic.shareLine(row.share),
                            value: LHFormat.hours(row.hours),
                            showsChevron: false
                        ) {
                            LHThumb.row(row.stage, lit: row.loggedToday)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(row.name)
                        .accessibilityValue(RR.t("reports.rental.spoken", "\(LHFormat.spokenHours(row.hours)), \(Int((row.share * 100).rounded())) percent"))
                    }
                }
            }
            Text(RR.t("reports.rental.footnote", "Every hour that counts as rental work, yours and your spouse\u{2019}s."))
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports.section.rental")
    }

    private var emptyBar: some View {
        Text(RR.t("reports.nothingYet", "Nothing logged here yet."))
            .font(.subheadline)
            .foregroundStyle(colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LHRow.insets)
    }

    private func barSection(title: String, bars: [(label: String, hours: Double)]) -> some View {
        let total = bars.reduce(0) { $0 + $1.hours }
        let maxValue = bars.map(\.hours).max() ?? 0
        return VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            LHSectionHeader(sectionTitle(title, total: total))
            VStack(spacing: 14) {
                if bars.isEmpty {
                    emptyBar.padding(-16)
                } else {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                        LHBarRow(label: bar.label, value: LHFormat.hours(bar.hours), fraction: maxValue > 0 ? bar.hours / maxValue : 0)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(bar.label)
                            .accessibilityValue(RR.t("reports.bar.spoken", "\(LHFormat.spokenHours(bar.hours)), \(total > 0 ? Int((bar.hours / total * 100).rounded()) : 0) percent"))
                    }
                }
            }
            .padding(LHMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
            .overlay { cardEdge }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports.section.\(title)")
    }

    @ViewBuilder private var cardEdge: some View {
        if colorScheme == .dark {
            RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
                .strokeBorder(colors.border, lineWidth: LHMetrics.hairline)
        }
    }

    private var monthSection: some View {
        let values = monthly
        let total = values.reduce(0, +)
        let symbols = Calendar.current.shortMonthSymbols
        let currentMonth = Calendar.current.component(.month, from: Date())
        let isCurrentYear = Calendar.current.component(.year, from: Date()) == selectedYear
        return VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            LHSectionHeader(sectionTitle(RR.t("reports.section.month", "By month"), total: total))
            Chart {
                ForEach(0..<12, id: \.self) { index in
                    BarMark(
                        x: .value("Month", symbols[index]),
                        y: .value("Hours", values[index])
                    )
                    .foregroundStyle(isCurrentYear && index + 1 > currentMonth ? colors.border : colors.action)
                    .cornerRadius(4)
                    .accessibilityLabel(Calendar.current.monthSymbols[index])
                    .accessibilityValue(LHFormat.spokenHours(values[index]))
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
                            Text(LHFormat.hours(hours))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(colors.textSecondary)
                        }
                    }
                }
            }
            .frame(height: ax ? 200 : 150)
            .opacity(isLoading ? 0 : 1)
            .overlay {
                if isLoading {
                    RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous)
                        .fill(colors.backgroundTertiary)
                }
            }
            .padding(LHMetrics.cardPadding)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
            .overlay { cardEdge }
            .accessibilityLabel(RR.t("reports.month.spoken", "Hours by month, \(String(selectedYear))"))
            .accessibilityIdentifier("reports.monthChart")
        }
    }

    // MARK: Export

    private var pdfTitle: String {
        String(format: String(localized: "pdf.title", defaultValue: "Rental hours record %lld"), selectedYear)
    }

    private var exportRow: some View {
        LHRow.Browse(
            title: pdfTitle,
            meta: RR.t("reports.export.meta", "The PDF and the spreadsheet, with where each hour came from."),
            systemImage: "doc.richtext",
            action: ProGate.isExportLocked(isPro: subscriptionManager.isPro) ? nil : exportAction
        )
    }

    /// Free: the card is a `.row` locked preview (the Reports free preview); every report above
    /// stays free. Pro: a plain link to the PDF.
    @ViewBuilder
    private var exportCard: some View {
        if ProGate.isExportLocked(isPro: subscriptionManager.isPro) {
            LHRowGroup {
                LockedPreview(
                    size: .row,
                    entry: .reportsExport,
                    line: ProGate.lockLine(.reportsExport),
                    keeps: ProGate.keepsLine(.reportsExport),
                    onUnlock: openExportPaywall
                ) {
                    exportRow
                }
            }
        } else {
            LHRowGroup { exportRow }
                .accessibilityIdentifier("reports.exportCard")
        }
    }

    /// Export always opens the PDF page; a free user sees it as a locked preview there.
    private func exportAction() {
        showingExportSheet = true
    }

    private func openExportPaywall() {
        paywall = ProPaywallRequest(context: .export, entry: .reportsExport, year: selectedYear,
                                    onUnlocked: { showingExportSheet = true })
    }
}

// MARK: - Standing cards

private extension ReportStanding {
    var spokenValue: String {
        RR.t("reports.standing.spoken", "\(LHFormat.spokenHours(hours)) of \(Int(target)) hours. \(status). \(detail ?? "")")
    }
}

/// The lead standing: the ring at 260 with the hours in its centre, the status in words with a
/// glyph (colour is never the only cue), and the one rule that matters next.
private struct RingStandingCard: View {
    let standing: ReportStanding
    let year: Int
    var isLoading = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
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
        RR.t("reports.standing.eyebrow", "\(String(year)) \u{00B7} \(standing.name)")
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(eyebrow)
                .font(AppTypography.drafting)
                .textCase(.uppercase)
                .tracking(1.3)
                .foregroundStyle(colors.draftingInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            LHRing(progress: standing.progress, tone: standing.tone == .positive ? .positive : (standing.tone == .caution ? .caution : .action), accessibilityValue: standing.spokenValue) {
                VStack(spacing: 2) {
                    Text(String(Int(standing.hours.rounded(.down))))
                        .font(.largeTitle.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(colors.textPrimary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .redacted(reason: isLoading ? .placeholder : [])
                    Text(RR.t("reports.standing.of", "of \(Int(standing.target)) hours"))
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 36)
            }
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: toneSymbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(toneColor)
                        .accessibilityHidden(true)
                    Text(standing.status)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(standing.tone == .neutral ? colors.textPrimary : toneColor)
                        .multilineTextAlignment(.center)
                }
                if let detail = standing.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(LHMetrics.cardPadding)
        .frame(maxWidth: .infinity)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
        .overlay {
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
                    .strokeBorder(colors.border, lineWidth: LHMetrics.hairline)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RR.t("reports.standing.label", "\(standing.name), \(standing.goal.spokenName)"))
        .accessibilityValue(standing.spokenValue)
        .accessibilityIdentifier("reports.standing.\(standing.person.rawValue)")
    }
}

/// Any further standing (a spouse's own count): a small ring beside the words.
private struct CompactStandingCard: View {
    let standing: ReportStanding
    let year: Int
    var isLoading = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var eyebrow: String {
        RR.t("reports.standing.eyebrow", "\(String(year)) \u{00B7} \(standing.name)")
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        layout {
            LHRing(progress: standing.progress, tone: standing.tone == .positive ? .positive : (standing.tone == .caution ? .caution : .action), diameter: 72, lineWidth: 9,
                   accessibilityValue: standing.spokenValue) {
                EmptyView()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(AppTypography.drafting)
                    .textCase(.uppercase)
                    .tracking(1.3)
                    .foregroundStyle(colors.draftingInk)
                Text(RR.t("reports.standing.ofHours", "\(LHFormat.hours(standing.hours)) of \(Int(standing.target))h"))
                    .font(.title3.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(colors.textPrimary)
                    .redacted(reason: isLoading ? .placeholder : [])
                Text(standing.status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                if let detail = standing.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(LHMetrics.cardPadding)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
        .overlay {
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
                    .strokeBorder(colors.border, lineWidth: LHMetrics.hairline)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RR.t("reports.standing.label", "\(standing.name), \(standing.goal.spokenName)"))
        .accessibilityValue(standing.spokenValue)
        .accessibilityIdentifier("reports.standing.\(standing.person.rawValue)")
    }
}

// MARK: - 100-hour test question sheet
//
// Shared by Reports, Today and Settings. Records the per-tax-year answer to the "did anyone else
// do more?" part of the 100-hour test. Answers are glyph + text so the choice never depends on
// colour alone.
struct ParticipationConfirmationSheet: View {
    let year: Int
    let currentAnswer: Bool?
    let onAnswer: (Bool?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        LHSheet(
            RR.t("reports.sheet.title", "100-hour test"),
            subtitle: String(year),
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                Text(RR.t("reports.sheet.question", "Did a manager or contractor put in more hours than you and your spouse this year, at any rental?"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                LHRowGroup {
                    answerRow(
                        title: RR.t("reports.sheet.no", "No one did more"),
                        subtitle: RR.t("reports.sheet.no.detail", "You and your spouse put in the most time."),
                        symbol: "checkmark.circle.fill",
                        tint: .positive,
                        isSelected: currentAnswer == true,
                        identifier: "participation.answer.yes"
                    ) {
                        onAnswer(true)
                        dismiss()
                    }
                    LHDivider(leadingInset: LHRow.browseDividerInset)
                    answerRow(
                        title: RR.t("reports.sheet.yes", "Someone did more"),
                        subtitle: RR.t("reports.sheet.yes.detail", "A manager, contractor or co-owner put in more."),
                        symbol: "exclamationmark.circle.fill",
                        tint: .caution,
                        isSelected: currentAnswer == false,
                        identifier: "participation.answer.no"
                    ) {
                        onAnswer(false)
                        dismiss()
                    }
                }
            }
            .padding(.top, 8)
        }
        .lhSheetPresentation(.standard)
        .accessibilityIdentifier("participation.sheet")
    }

    private func answerRow(
        title: String,
        subtitle: String,
        symbol: String,
        tint: LHRowGlyph.Tint,
        isSelected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        LHRow.Browse(
            title: title,
            meta: subtitle,
            value: isSelected ? RR.t("reports.sheet.selected", "Chosen") : nil,
            showsChevron: false,
            action: action
        ) {
            LHRowGlyph(systemImage: symbol, tint: tint)
        }
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    ReportsView()
        .environmentObject(AppViewModel())
}
