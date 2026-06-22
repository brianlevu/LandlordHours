import SwiftUI
import PDFKit
import LucideIcons

struct ExportPDFView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    let year: Int
    @State private var shareItem: PDFShareItem?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Export report")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                            .minimumScaleFactor(0.82)
                        Text("Create a \(String(year)) PDF for your records or accountant.")
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
                                        .foregroundStyle(AppColors.sage)
                                    Text("PDF ready")
                                        .font(AppTypography.button)
                                        .foregroundStyle(colors.textPrimary)
                                }

                                ShareLink(item: shareItem.url) {
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
                            }
                        } else {
                            Button {
                                generateAndSharePDF()
                            } label: {
                                HStack(spacing: 8) {
                                    LucideIcon(image: Lucide.fileDown, size: 16)
                                    Text(canExport ? "Generate PDF" : "No entries to export")
                                }
                                .font(AppTypography.button)
                                .foregroundStyle(canExport ? AppColors.charcoal : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(canExport ? AppColors.sage : AppColors.mist)
                                .clipShape(Capsule())
                            }
                            .disabled(!canExport)
                            .accessibilityIdentifier("export.generatePDF")
                        }

                        if let exportError {
                            Text(exportError)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.error)
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
                            reportRow(label: "Properties", value: "\(viewModel.properties.count) properties", icon: "building-2", color: AppColors.sky)
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

    var canExport: Bool {
        !yearEntries.isEmpty
    }

    var exportSummaryText: String {
        if canExport {
            return "Create a PDF with properties, entries, notes, participants, and total hours."
        }
        return "Log time entries for \(year), then export a PDF for your CPA or records."
    }

    var repsQualifiedHours: Double {
        yearEntries.filter { $0.countsForREPS }.reduce(0) { $0 + $1.hours }
    }

    private func generateAndSharePDF() {
        let pdfData = generatePDF()

        // Save to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("LandlordHours_\(year).pdf")
        do {
            try pdfData.write(to: tempURL, options: .atomic)
            shareItem = PDFShareItem(url: tempURL)
            exportError = nil
        } catch {
            exportError = "Could not generate the PDF. Please try again."
        }
    }

    func generatePDF() -> Data {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50

        let pdfMetaData = [
            kCGPDFContextCreator: "LandlordHours",
            kCGPDFContextAuthor: "LandlordHours App",
            kCGPDFContextTitle: "REPS Time Report \(year)"
        ]

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { context in
            context.beginPage()

            // Title
            let titleFont = UIFont.boldSystemFont(ofSize: 24)
            let title = "LandlordHours REPS Report"
            title.draw(at: CGPoint(x: margin, y: margin), withAttributes: [.font: titleFont])

            // Year
            let yearFont = UIFont.systemFont(ofSize: 18)
            "Year \(year)".draw(at: CGPoint(x: margin, y: margin + 35), withAttributes: [.font: yearFont])

            // Summary
            let headerFont = UIFont.boldSystemFont(ofSize: 14)
            let bodyFont = UIFont.systemFont(ofSize: 12)

            var yPosition: CGFloat = margin + 80

            "Summary".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: [.font: headerFont])
            yPosition += 25

            "Total Hours Logged: \(String(format: "%.1f", totalHours)) hours".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: [.font: bodyFont])
            yPosition += 20

            "REPS-counted Hours: \(String(format: "%.1f", repsQualifiedHours)) hours".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: [.font: bodyFont])
            yPosition += 20

            "Total Entries: \(yearEntries.count)".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: [.font: bodyFont])
            yPosition += 35

            // Properties
            "Properties".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: [.font: headerFont])
            yPosition += 25

            for property in viewModel.properties {
                property.name.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: [.font: bodyFont])
                yPosition += 18
                property.address.draw(at: CGPoint(x: margin + 20, y: yPosition), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.gray])
                yPosition += 25

                if yPosition > pageHeight - 100 {
                    context.beginPage()
                    yPosition = margin
                }
            }

            yPosition += 15

            // Time Entries
            "Time Entries".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: [.font: headerFont])
            yPosition += 25

            // Table header
            let entries = yearEntries.sorted { $0.date > $1.date }

            let maxTextWidth = pageWidth - 2 * margin

            for entry in entries {
                let property = viewModel.properties.first { $0.id == entry.propertyId }
                let propertyName = property?.name ?? "Unknown"

                let entryText = "\(entry.formattedDate) | \(propertyName) | \(entry.category.rawValue) | \(String(format: "%.1f", entry.hours))h | \(entry.participant.rawValue)" as NSString
                let entryAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont]
                let entrySize = entryText.boundingRect(with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: entryAttrs, context: nil)
                entryText.draw(in: CGRect(x: margin, y: yPosition, width: maxTextWidth, height: entrySize.height), withAttributes: entryAttrs)
                yPosition += entrySize.height + 4

                if !entry.notes.isEmpty {
                    let notesText = "  Notes: \(entry.notes)" as NSString
                    let notesAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: UIColor.gray]
                    let notesWidth = maxTextWidth - 20
                    let notesSize = notesText.boundingRect(with: CGSize(width: notesWidth, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: notesAttrs, context: nil)
                    notesText.draw(in: CGRect(x: margin + 20, y: yPosition, width: notesWidth, height: notesSize.height), withAttributes: notesAttrs)
                    yPosition += notesSize.height + 4
                }

                if yPosition > pageHeight - 50 {
                    context.beginPage()
                    yPosition = margin
                }
            }

            // Footer
            let footerFont = UIFont.systemFont(ofSize: 10)
            let footer = "Generated by LandlordHours on \(Date().formatted(date: .long, time: .omitted))"
            let footerRect = CGRect(x: margin, y: pageHeight - 30, width: pageWidth - 2 * margin, height: 20)
            footer.draw(in: footerRect, withAttributes: [.font: footerFont, .foregroundColor: UIColor.gray])
        }

        return data
    }
}

private struct PDFShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
