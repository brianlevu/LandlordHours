import SwiftUI
import PDFKit

/// Export: the real first page of the record on top, the year, what's inside, then one pinned
/// action. Standard v2 (package H): an `LHSheet` (title, `.icon` close, `.primary` pinned), year
/// choice on `LHChip`, the summary in one grouped container, and for a free user the one shared
/// `LockedPreview` whose unlock opens the paywall about the export.
struct ExportPDFView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var year: Int
    @State private var sharing: ShareRequest?
    /// WP-L: the report is made in the background; this sheet can close while it runs.
    @ObservedObject private var job = ExportJob.shared
    /// WP-P: a free user sees this page as a `.page` locked preview.
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var paywall: ProPaywallRequest?

    /// The records this sheet would export now; a ready report made from other records is stale.
    private var fingerprint: String { ExportFingerprint.current(app: viewModel, year: year) }
    private var shareItem: ExportShareItem? { job.readyFiles(for: year, fingerprint: fingerprint) }
    private var reportIsStale: Bool { job.isStale(year: year, fingerprint: fingerprint) }
    private var exportError: String? { job.failureMessage(for: year) }
    private var isGenerating: Bool { job.isGenerating }
    private var isLocked: Bool { ProGate.isExportLocked(isPro: subscriptionManager.isPro) }
    private var gate: ExportGate {
        ExportGate.resolve(
            hasEntries: canExport,
            isGenerating: isGenerating,
            hoursPlaceholderShowing: viewModel.isAwaitingInitialPull,
            initialPullRunning: viewModel.isInitialPullRunning
        )
    }
    @State private var preview: UIImage?
    @State private var previewYear: Int?

    init(year: Int) {
        _year = State(initialValue: year)
    }

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    private var yearChoices: [Int] {
        let years = Set(viewModel.timeEntries.map { Calendar.current.component(.year, from: $0.date) })
            .union([currentYear, year])
        return Array(years.sorted(by: >).prefix(4))
    }

    var body: some View {
        sheet
        .lhSheetPresentation(.focused)
        .hidesAppTabBar()
        .proPaywall($paywall)
        .task(id: year) { await renderPreview() }
        .onAppear { job.isSheetVisible = true }
        .onDisappear { job.isSheetVisible = false }
        .sheet(item: $sharing) { request in
            ActivityShareSheet(items: [ExportShareFile(url: request.url)]) { completed in
                sharing = nil
                if completed { viewModel.exportShared(format: request.format) }
            }
            .presentationDetents([.medium, .large])
            .ignoresSafeArea()
        }
    }

    private var sheetTitle: String { HS.t("export.title", "Export the record") }
    private var sheetSubtitle: String { HS.t("export.subtitle", "A PDF for your CPA and a CSV of every record.") }

    /// §1.20 with the AX footer policy (owner ruling 2026-10-27): the primary is pinned at every
    /// size; "Create again" / "Create with what's on this device" pins above it below AX and scrolls
    /// after the content at AX. Locked, the preview carries its own unlock, so nothing is pinned.
    @ViewBuilder private var sheet: some View {
        if isLocked {
            LHSheet(sheetTitle, subtitle: sheetSubtitle, onClose: { dismiss() }) { sheetContent }
        } else {
            LHSheet(sheetTitle, subtitle: sheetSubtitle, onClose: { dismiss() }) {
                sheetContent
            } primary: {
                primaryAction
            } secondary: {
                secondaryAction
            }
        }
    }

    private var sheetContent: some View {
        LockedPreview(
            size: .page,
            entry: .exportPage,
            line: ProGate.lockLine(.exportPage),
            keeps: ProGate.keepsLine(.exportPage),
            unlocked: !isLocked,
            stamp: HS.t("export.stamp", "PREVIEW"),
            onUnlock: openPaywall
        ) {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                yearChips

                // Free: the summary stays sharp; the page itself is what Pro unlocks,
                // so it sits under the lock (sandbox lock-export).
                if isLocked { summary }
            }
            .padding(.bottom, LHMetrics.sectionGap)
        } locked: {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                pagePreview

                if !isLocked { summary }

                status

            }
        }
        .padding(.top, 8)
    }

    // MARK: Year

    private var yearChips: some View {
        // The strip carries its own page gutter; the sheet already insets, so pull it back out.
        LHChipStrip {
            ForEach(yearChoices, id: \.self) { choice in
                LHChip(yearLabel(choice), isSelected: choice == year) { year = choice }
                    .accessibilityIdentifier("export.year.\(choice)")
            }
        }
        .padding(.horizontal, -LHMetrics.gutter)
    }

    private func yearLabel(_ value: Int) -> String {
        if value == currentYear { return HS.t("export.year.this", "This year") }
        if value == currentYear - 1 { return HS.t("export.year.last", "Last year") }
        return String(value)
    }

    // MARK: Preview

    /// From XXL up the page thumbnail shows the top of the page in a shorter frame, so the summary rows
    /// stay whole above the pinned action instead of sliding under it.
    private var shortPreview: Bool { !isLocked && typeSize >= .xxLarge }

    private var pagePreview: some View {
        let page = RoundedRectangle(cornerRadius: LHMetrics.tagRadius, style: .continuous)
        return ZStack {
            page
                .fill(Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.08), radius: 16, y: 4)
            if let preview, previewYear == year {
                // The clear base sets the size (the frame's aspect ratio); the image only fills it, so a
                // short frame crops the page's bottom instead of growing back to the page's height.
                Color.clear
                    .overlay(alignment: .top) {
                        Image(uiImage: preview)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: shortPreview ? .fill : .fit)
                    }
                    .overlay(alignment: .bottom) {
                        // A short frame cuts the page mid-line, so it fades out instead of ending on a sliced row.
                        if shortPreview {
                            LinearGradient(colors: [Color.white.opacity(0), Color.white], startPoint: .top, endPoint: .bottom)
                                .frame(height: 36)
                                .allowsHitTesting(false)
                        }
                    }
                    .clipShape(page)
                    .transition(.opacity)
            } else {
                // isLoading hook: the page renders off the main thread; only the page shows a
                // placeholder (title and table lines), the rest of the sheet stays usable.
                VStack(alignment: .leading, spacing: 10) {
                    BPLoadingPlaceholder(kind: .number, width: 140, height: 12)
                    BPLoadingPlaceholder(kind: .number, width: 90, height: 8)
                    BPLoadingPlaceholder(kind: .chart, width: nil, height: 36)
                    ForEach(0..<4, id: \.self) { _ in
                        BPLoadingPlaceholder(kind: .number, width: nil, height: 6)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .environment(\.colorScheme, .light)
            }
        }
        .aspectRatio(isLocked || shortPreview ? 11 / 6 : 11 / 8.5, contentMode: .fit)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : AppAnimation.reveal, value: previewYear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HS.f("export.preview.label", "Preview of the first page of the %@ record", String(year)))
        .accessibilityIdentifier("export.preview")
    }

    // MARK: Summary

    private var summary: some View {
        LHRowGroup {
            summaryRow(HS.t("export.summary.records", "Records"), value: "\(yearEntries.count)")
            LHDivider(leadingInset: LHRow.insets.leading)
            summaryRow(HS.t("export.summary.rentals", "Rentals"), value: "\(activePropertyCount)")
            LHDivider(leadingInset: LHRow.insets.leading)
            summaryRow(HS.t("export.summary.all", "All hours logged"), value: LHFormat.hours(totalHours))
            LHDivider(leadingInset: LHRow.insets.leading)
            summaryRow(repsQualifiedLabel, value: LHFormat.hours(repsQualifiedHours))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("export.summary")
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        LongTailValueRow(label: label, value: value, accessory: .none)
    }

    // MARK: Status (inside the content; the buttons are pinned in the sheet footer)

    @ViewBuilder
    private var status: some View {
        VStack(alignment: .leading, spacing: 12) {
            if shareItem != nil {
                Label(HS.t("export.ready", "Report ready"), systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.positive)

                if let shareItem {
                    Button {
                        sharing = ShareRequest(url: shareItem.csvURL, format: .csv)
                    } label: {
                        Label(HS.t("export.shareCSV", "Share CSV spreadsheet"), systemImage: "tablecells")
                    }
                    .buttonStyle(LHButton.secondary)
                    .accessibilityIdentifier("export.shareCSV")
                }
            } else {
                if reportIsStale && !isGenerating {
                    Text(HS.t("export.stale", "Your records changed since your last report. Create it again to include them."))
                        .font(.footnote)
                        .foregroundStyle(colors.caution)
                        .accessibilityIdentifier("export.stale")
                }
                if isGenerating {
                    // Busy: the drafting line runs while the button above is muted.
                    HStack(spacing: 10) {
                        DraftingLoader(sketch: .chart, surface: .adaptive, lineWidth: 1.6)
                            .frame(width: 34, height: 14)
                            .accessibilityHidden(true)
                        Text(HS.t("export.generating.hint", "You can close this. We’ll let you know when it’s ready."))
                            .font(.footnote)
                            .foregroundStyle(colors.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("export.backgroundHint")
                } else if !canExport && gate == .noEntries {
                    Text(HS.f("export.empty", "Log hours in %@, then export them here.", String(year)))
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                }
            }

            if viewModel.initialPullFailed && gate.allowsCreate {
                Label(HS.t("export.pullFailed", "Couldn’t reach iCloud. This report may be missing hours from your other devices."),
                      systemImage: "icloud.slash")
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .accessibilityIdentifier("export.pullFailedNote")
            }

            if let exportError {
                Label(exportError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(colors.destructive)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions (pinned: one primary, at most one tertiary above it)

    @ViewBuilder private var primaryAction: some View {
        if let shareItem {
            Button {
                sharing = ShareRequest(url: shareItem.pdfURL, format: .pdf)
            } label: {
                Label(HS.t("export.sharePDF", "Share PDF"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(LHButton.primary)
            .accessibilityIdentifier("export.sharePDF")
        } else {
            Button {
                generateExports()
            } label: {
                Text(generateButtonTitle)
            }
            .buttonStyle(LHButton.primary)
            .disabled(!gate.allowsCreate)
            .accessibilityIdentifier("export.generatePDF")
        }
    }

    @ViewBuilder private var secondaryAction: some View {
        if shareItem != nil {
            if gate == .stillSyncing {
                createWithLocalButton
            } else {
                Button(HS.t("export.createAgain", "Create again")) { generateExports() }
                    .buttonStyle(LHButton.tertiary)
                    .disabled(!gate.allowsCreate)
                    .accessibilityHint(HS.t("export.createAgain.hint", "Makes a new report from your current records"))
                    .accessibilityIdentifier("export.createAgain")
            }
        } else if gate == .stillSyncing && canExport {
            createWithLocalButton
        }
    }

    /// The pull is slow, not failed: the report may miss hours from other devices. The user
    /// chooses to go ahead anyway (the only way to create while syncing).
    private var createWithLocalButton: some View {
        Button(HS.t("export.createLocal", "Create with what’s on this device")) { generateExports(force: true) }
            .buttonStyle(LHButton.tertiary)
            .accessibilityIdentifier("export.createLocal")
    }

    // MARK: Pro

    /// Opens the export paywall; after a purchase the blur lifts and the report starts.
    private func openPaywall() {
        paywall = ProPaywallRequest(context: .export, entry: .exportPage, year: year, onUnlocked: {
            if gate.allowsCreate && shareItem == nil { generateExports() }
        })
    }

    // MARK: Data

    var yearEntries: [TimeEntry] {
        viewModel.timeEntries.filter { Calendar.current.component(.year, from: $0.date) == year }
    }

    var totalHours: Double {
        yearEntries.reduce(0) { $0 + $1.hours }
    }

    var activePropertyCount: Int {
        Set(yearEntries.map(\.propertyId)).count
    }

    var canExport: Bool {
        !yearEntries.isEmpty
    }

    private var generateButtonTitle: String {
        gate.title(isStale: reportIsStale)
    }

    /// The qualifying person's own hours toward the 750 (the spouse's when the spouse is the real estate
    /// professional); spouse hours are never added to yours.
    var repsQualifiedHours: Double {
        ExportPDFSummary.repsHours(entries: viewModel.timeEntries, year: year, participant: GoalManager.shared.repsParticipant)
    }

    private var repsQualifiedLabel: String {
        GoalManager.shared.repsParticipant == .spouse
            ? HS.t("export.summary.counted.spouse", "Spouse hours toward 750")
            : HS.t("export.summary.counted.you", "Your hours toward 750")
    }

    private func makeReport() -> AuditReport {
        let taxProfile = TaxProfileManager.shared
        return AuditReportBuilder.build(AuditReportBuilder.inputFromTaxProfile(
            entries: viewModel.timeEntries,
            properties: viewModel.properties,
            taxYear: year,
            spouseTracking: taxProfile.spouseTracking,
            nonREWorkHours: taxProfile.nonREWorkHours,
            groupingElection: taxProfile.groupingElection,
            noOneParticipatedMore: taxProfile.noOneParticipatedMore(forYear: year),
            repsParticipant: GoalManager.shared.repsParticipant
        ))
    }

    /// Renders the real report's first page as the preview (same renderer as the export).
    private func renderPreview() async {
        let report = makeReport()
        let year = year
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            // The first page never shows photos; skip loading them for the preview.
            let renderer = AuditReportPDFRenderer(attachmentData: { _ in nil })
            let data = renderer.render(report)
            guard let page = PDFDocument(data: data)?.page(at: 0) else { return nil }
            return page.thumbnail(of: CGSize(width: 1188, height: 918), for: .mediaBox)
        }.value
        guard !Task.isCancelled else { return }
        preview = image
        previewYear = year
    }

    /// `force`: the user chose to export what's on this device while the pull is still running.
    private func generateExports(force: Bool = false) {
        guard !ProGate.isExportLocked(isPro: subscriptionManager.isPro) else { return openPaywall() }
        guard gate.allowsCreate || (force && gate == .stillSyncing && canExport) else { return }
        job.start(report: makeReport(), year: year, fingerprint: fingerprint)
    }
}

/// Writes the PDF and CSV for a report into a fresh temporary folder.
enum AuditExportFiles {
    static func write(report: AuditReport, year: Int, directory: URL? = nil) -> Result<ExportShareItem, Error> {
        do {
            let folder = directory ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("LandlordHoursExport-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // `pdf.title` names both files ("Rental hours record 2026"), the same line as the PDF's title.
            let name = HS.recordTitle(year: year)
            let pdfURL = folder.appendingPathComponent("\(name).pdf")
            let csvURL = folder.appendingPathComponent("\(name).csv")
            try AuditReportPDFRenderer().render(report).write(to: pdfURL, options: .atomic)
            try Data(AuditReportCSV.make(report).utf8).write(to: csvURL, options: .atomic)
            return .success(ExportShareItem(pdfURL: pdfURL, csvURL: csvURL))
        } catch {
            return .failure(error)
        }
    }
}

struct ExportShareItem: Identifiable, Equatable {
    let id = UUID()
    let pdfURL: URL
    let csvURL: URL
}

/// The kind of file the user shared from the export screen.
enum ExportFormat: String {
    case pdf
    case csv
}

private struct ShareRequest: Identifiable {
    let id = UUID()
    let url: URL
    let format: ExportFormat
}

/// UIActivityViewController wrapper that reports whether the user actually shared
/// (`completed == true`), unlike SwiftUI's ShareLink.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onFinish: (_ completed: Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onFinish(completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// WP-L: when the export's Create button may run. Waiting states come before "no entries", so a
/// profile whose iCloud pull is still running never reads "No entries to export".
enum ExportGate: Equatable {
    case generating
    /// Today's hours placeholder is showing (first seconds of the pull).
    case waitingForHours
    /// The placeholder cap passed but the pull is still running: the report could miss hours.
    case stillSyncing
    case noEntries
    case ready

    static func resolve(hasEntries: Bool, isGenerating: Bool, hoursPlaceholderShowing: Bool, initialPullRunning: Bool) -> ExportGate {
        if isGenerating { return .generating }
        if hoursPlaceholderShowing { return .waitingForHours }
        if initialPullRunning { return .stillSyncing }
        if !hasEntries { return .noEntries }
        return .ready
    }

    var allowsCreate: Bool { self == .ready }

    func title(isStale: Bool) -> String {
        switch self {
        case .generating: return HS.t("export.gate.generating", "Creating report…")
        case .waitingForHours: return HS.t("export.gate.waiting", "Getting your latest hours…")
        case .stillSyncing: return HS.t("export.gate.syncing", "Still syncing from iCloud")
        case .noEntries: return HS.t("export.gate.empty", "No hours to export")
        case .ready: return isStale ? HS.t("export.createAgain", "Create again") : HS.t("export.gate.ready", "Create PDF and CSV")
        }
    }
}
