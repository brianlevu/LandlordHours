import SwiftUI
import PDFKit
import LucideIcons

struct ExportPDFView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    let year: Int
    @State private var shareItem: ExportShareItem?
    @State private var exportError: String?
    @State private var isGenerating = false
    @State private var sharing: ShareRequest?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Export report")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                            .minimumScaleFactor(0.82)
                        Text("Create a \(String(year)) report for your records or your CPA.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Export action card
                    VStack(spacing: 16) {
                        Circle()
                            .fill(colors.backgroundTertiary)
                            .frame(width: 64, height: 64)
                            .overlay {
                                LucideIcon(image: Lucide.fileText, size: 28)
                                    .foregroundStyle(AppColors.charcoal)
                            }

                        Text("Export \(String(year)) report")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(colors.textPrimary)

                        Text(exportSummaryText)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)

                        if let shareItem {
                            VStack(spacing: 10) {
                                HStack(spacing: 8) {
                                    LucideIcon(image: Lucide.check, size: 16)
                                        .foregroundStyle(colors.positive)
                                    Text("Report ready")
                                        .font(AppTypography.button)
                                        .foregroundStyle(colors.textPrimary)
                                }

                                Button {
                                    sharing = ShareRequest(url: shareItem.pdfURL, format: .pdf)
                                } label: {
                                    HStack(spacing: 8) {
                                        LucideIcon(image: Lucide.share2, size: 16)
                                        Text("Share PDF")
                                    }
                                    .font(AppTypography.button)
                                    .foregroundStyle(AppColors.onAction)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(colors.action)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.lhPressable)
                                .accessibilityIdentifier("export.sharePDF")

                                Button {
                                    sharing = ShareRequest(url: shareItem.csvURL, format: .csv)
                                } label: {
                                    HStack(spacing: 8) {
                                        LucideIcon(image: Lucide.fileText, size: 16)
                                        Text("Share CSV spreadsheet")
                                    }
                                    .font(AppTypography.button)
                                    .foregroundStyle(colors.action)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(colors.actionSurface)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.lhPressable)
                                .accessibilityIdentifier("export.shareCSV")
                            }
                        } else {
                            Button {
                                generateExports()
                            } label: {
                                HStack(spacing: 8) {
                                    if isGenerating {
                                        ProgressView()
                                            .tint(AppColors.onAction)
                                    } else {
                                        LucideIcon(image: Lucide.fileDown, size: 16)
                                    }
                                    Text(generateButtonTitle)
                                }
                                .font(AppTypography.button)
                                .foregroundStyle(canExport ? AppColors.onAction : colors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(canExport ? colors.action : colors.backgroundTertiary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.lhPressable)
                            .disabled(!canExport || isGenerating)
                            .accessibilityIdentifier("export.generatePDF")
                        }

                        if let exportError {
                            Text(exportError)
                                .font(AppTypography.caption)
                                .foregroundStyle(colors.destructive)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(20)
                    .background(colors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(colors.border.opacity(0.28), lineWidth: 1)
                    }

                    // Report summary card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            LucideIcon(image: Lucide.list, size: 14)
                                .foregroundStyle(AppColors.charcoal)
                            Text("Report includes")
                                .font(.system(size: 19, weight: .black, design: .rounded))
                                .foregroundStyle(colors.textPrimary)
                        }

                        VStack(spacing: 0) {
                            reportRow(label: "Properties", value: "\(activePropertyCount) with time logged", icon: "building-2", color: AppColors.sky)
                            Divider().padding(.leading, 48)
                            reportRow(label: "Time Entries", value: "\(yearEntries.count) entries", icon: "clock", color: AppColors.primary)
                            Divider().padding(.leading, 48)
                            reportRow(label: "Total Hours", value: String(format: "%.1f hours", totalHours), icon: "hourglass", color: AppColors.honey)
                            Divider().padding(.leading, 48)
                            reportRow(label: "REPS hours", value: String(format: "%.1f hours", repsQualifiedHours), icon: "badge-check", color: AppColors.sage)
                        }
                    }
                    .padding(20)
                    .background(colors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(colors.border.opacity(0.28), lineWidth: 1)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .background { LHMobileCanvas() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .hidesAppTabBar()
        .sheet(item: $sharing) { request in
            ActivityShareSheet(items: [request.url]) { completed in
                sharing = nil
                if completed { viewModel.exportShared(format: request.format) }
            }
            .presentationDetents([.medium, .large])
            .ignoresSafeArea()
        }
    }

    private func reportRow(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            JellyBadge(systemName: icon, color: color, wash: colors.backgroundTertiary, size: 36)
            Text(label)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)
            Spacer()
            Text(value)
                .font(AppTypography.bodySmall)
                .fontWeight(.medium)
                .foregroundStyle(colors.textSecondary)
        }
        .padding(.vertical, 8)
    }

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
        if !canExport { return "No entries to export" }
        return isGenerating ? "Creating report…" : "Create PDF and CSV"
    }

    var exportSummaryText: String {
        if canExport {
            return "A PDF for your CPA, plus a spreadsheet. It shows hours by property, category, and person, every entry, and your photos."
        }
        return "Log time entries for \(String(year)), then export a report for your CPA or records."
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

    private func generateExports() {
        guard !isGenerating else { return }
        isGenerating = true
        exportError = nil
        let report = makeReport()
        let year = year
        Task.detached(priority: .userInitiated) {
            let result = AuditExportFiles.write(report: report, year: year)
            await MainActor.run {
                isGenerating = false
                switch result {
                case .success(let files):
                    shareItem = files
                case .failure:
                    exportError = "Could not create the report. Please try again."
                }
            }
        }
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

struct ExportShareItem: Identifiable {
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
