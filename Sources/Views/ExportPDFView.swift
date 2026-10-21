import SwiftUI
import PDFKit

/// Export: the real first page of the PDF on top (Crouton), the year, what's inside, then one
/// action. docs/design/2.0-hifi-reference-spec.md §h.
struct ExportPDFView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        NavigationStack {
            ScrollView {
                LockedPreview(
                    size: .page,
                    entry: .exportPage,
                    line: ProGate.lockLine(.exportPage),
                    keeps: ProGate.keepsLine(.exportPage),
                    unlocked: !ProGate.isExportLocked(isPro: subscriptionManager.isPro),
                    stamp: "PREVIEW",
                    onUnlock: openPaywall
                ) {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Export report")
                                .lhDisplayFont(.largeTitle)
                                .foregroundStyle(colors.textPrimary)
                                .accessibilityAddTraits(.isHeader)
                            Text("A PDF for your accountant and a CSV spreadsheet of every entry.")
                                .font(.subheadline)
                                .foregroundStyle(colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        yearChips

                        // Free: the summary stays sharp; the page itself is what Pro unlocks,
                        // so it sits under the lock (sandbox lock-export).
                        if ProGate.isExportLocked(isPro: subscriptionManager.isPro) { summary }
                    }
                    .padding(.bottom, 24)
                } locked: {
                    VStack(alignment: .leading, spacing: 24) {
                        pagePreview

                        if !ProGate.isExportLocked(isPro: subscriptionManager.isPro) { summary }

                        actions
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            // Content scrolling up never shows through under the Close chip.
            .modifier(HardTopScrollEdge())
            .toolbarBackground(colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(colors.action)
                        .accessibilityIdentifier("export.close")
                }
            }
        }
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

    // MARK: Year

    private var yearChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(yearChoices, id: \.self) { choice in
                    Button {
                        year = choice
                    } label: {
                        BPFilterChip(title: yearLabel(choice), isActive: choice == year, showsChevron: false)
                    }
                    .buttonStyle(.lhPressable)
                    .accessibilityAddTraits(choice == year ? .isSelected : [])
                    .accessibilityIdentifier("export.year.\(choice)")
                }
            }
        }
    }

    private func yearLabel(_ value: Int) -> String {
        if value == currentYear { return "This year" }
        if value == currentYear - 1 { return "Last year" }
        return String(value)
    }

    // MARK: Preview

    private var pagePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.08), radius: 16, y: 4)
            if let preview, previewYear == year {
                Image(uiImage: preview)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
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
        .aspectRatio(11 / 8.5, contentMode: .fit)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : AppAnimation.reveal, value: previewYear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the first page of the \(String(year)) report")
        .accessibilityIdentifier("export.preview")
    }

    // MARK: Summary

    private var summary: some View {
        VStack(spacing: 0) {
            summaryRow("Entries", value: "\(yearEntries.count)")
            Divider().padding(.leading, 16)
            summaryRow("Properties", value: "\(activePropertyCount)")
            Divider().padding(.leading, 16)
            summaryRow("All logged hours", value: BPHours.short(totalHours))
            Divider().padding(.leading, 16)
            summaryRow("Real estate hours", value: BPHours.short(repsQualifiedHours))
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.backgroundSecondary))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("export.summary")
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(colors.textPrimary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.body, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(colors.textSecondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            if let shareItem {
                Label("Report ready", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.positive)
                    .frame(maxWidth: .infinity)

                Button {
                    sharing = ShareRequest(url: shareItem.pdfURL, format: .pdf)
                } label: {
                    Label("Share PDF", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(InboxPrimaryButtonStyle())
                .accessibilityIdentifier("export.sharePDF")

                Button {
                    sharing = ShareRequest(url: shareItem.csvURL, format: .csv)
                } label: {
                    Label("Share CSV spreadsheet", systemImage: "tablecells")
                        .font(AppTypography.buttonLarge)
                        .foregroundStyle(colors.action)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(Capsule().fill(colors.actionSurface))
                }
                .buttonStyle(.lhPressable)
                .accessibilityIdentifier("export.shareCSV")

                Button("Create again") { generateExports() }
                    .font(AppTypography.button)
                    .foregroundStyle(colors.action)
                    .frame(minHeight: 44)
                    .disabled(!gate.allowsCreate)
                    .accessibilityHint("Makes a new report from your current records")
                    .accessibilityIdentifier("export.createAgain")
                if gate == .stillSyncing {
                    createWithLocalButton
                }
            } else {
                if reportIsStale && !isGenerating {
                    Text("Your records changed since your last report. Create it again to include them.")
                        .font(.footnote)
                        .foregroundStyle(colors.caution)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("export.stale")
                }
                if isGenerating {
                    // Busy: the drafting line runs inside a muted, non-tappable button.
                    HStack(spacing: 10) {
                        DraftingLoader(sketch: .chart, surface: .adaptive, lineWidth: 1.6)
                            .frame(width: 34, height: 14)
                            .accessibilityHidden(true)
                        Text(generateButtonTitle)
                    }
                    .font(AppTypography.buttonLarge)
                    .foregroundStyle(colors.action)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(Capsule().fill(colors.actionSurface))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("export.generatePDF")

                    Text("You can close this. We’ll let you know when it’s ready.")
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("export.backgroundHint")
                } else {
                    Button {
                        generateExports()
                    } label: {
                        Text(generateButtonTitle)
                    }
                    .buttonStyle(InboxPrimaryButtonStyle())
                    .disabled(!gate.allowsCreate)
                    .accessibilityIdentifier("export.generatePDF")

                    if gate == .stillSyncing && canExport {
                        createWithLocalButton
                    }

                    if !canExport && gate == .noEntries {
                        Text("Log time in \(String(year)), then export it here.")
                            .font(.footnote)
                            .foregroundStyle(colors.textSecondary)
                    }
                }
            }

            if viewModel.initialPullFailed && gate.allowsCreate {
                Label("Couldn’t reach iCloud. This report may be missing hours from your other devices.",
                      systemImage: "icloud.slash")
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("export.pullFailedNote")
            }

            if let exportError {
                Label(exportError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(colors.destructive)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// The pull is slow, not failed: the report may miss hours from other devices. The user
    /// chooses to go ahead anyway (the only way to create while syncing).
    private var createWithLocalButton: some View {
        Button("Create with what’s on this device") { generateExports(force: true) }
            .font(AppTypography.button)
            .foregroundStyle(colors.action)
            .frame(maxWidth: .infinity, minHeight: 44)
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

    var repsQualifiedHours: Double {
        yearEntries.filter { $0.countsForREPS }.reduce(0) { $0 + $1.hours }
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
            noOneParticipatedMore: taxProfile.noOneParticipatedMore(forYear: year)
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
            let pdfURL = folder.appendingPathComponent("LandlordHours_\(year)_Activity_Log.pdf")
            let csvURL = folder.appendingPathComponent("LandlordHours_\(year)_Activity_Log.csv")
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
        case .generating: return "Creating report…"
        case .waitingForHours: return "Getting your latest hours…"
        case .stillSyncing: return "Still syncing from iCloud"
        case .noEntries: return "No entries to export"
        case .ready: return isStale ? "Create again" : "Create PDF and CSV"
        }
    }
}
