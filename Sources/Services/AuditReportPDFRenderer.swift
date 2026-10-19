import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Renders an `AuditReport` as a printable, black-on-white PDF (US Letter, landscape).
///
/// Layout runs twice: a measuring pass that counts pages, then the drawing pass, so every
/// page footer can say "Page n of N".
struct AuditReportPDFRenderer {
    /// Loads attachment bytes. Defaults to the on-disk attachment store.
    var attachmentData: (TimeAttachment) -> Data? = { $0.data }

    static let pageSize = CGSize(width: 792, height: 612)

    /// Largest box an appendix photo is drawn into: two per row on the 720 pt content width,
    /// tall enough for a portrait receipt while leaving room for its caption on one page.
    static let appendixBox = CGSize(width: 340, height: 420)
    static let minimumPPI: CGFloat = 200

    /// Drawn size of an appendix photo: aspect-fit into `box`, never larger than the
    /// source's pixel size (1 px = 1 pt) so small images are not upscaled.
    static func appendixImageSize(pixelSize: CGSize, box: CGSize = appendixBox) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return .zero }
        let maxWidth = min(box.width, pixelSize.width)
        let maxHeight = min(box.height, pixelSize.height)
        let scale = min(maxWidth / pixelSize.width, maxHeight / pixelSize.height)
        return CGSize(width: floor(pixelSize.width * scale), height: floor(pixelSize.height * scale))
    }

    /// Orientation-corrected pixel size of an image, or nil if it can't be decoded.
    static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let widthNumber = props[kCGImagePropertyPixelWidth] as? NSNumber,
              let heightNumber = props[kCGImagePropertyPixelHeight] as? NSNumber
        else { return nil }
        let width = CGFloat(widthNumber.doubleValue)
        let height = CGFloat(heightNumber.doubleValue)
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    func render(_ report: AuditReport) -> Data {
        let measuring = Composer(report: report, context: nil, totalPages: 0, attachmentData: attachmentData)
        measuring.layout()
        let totalPages = measuring.pageNumber

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "LandlordHours",
            kCGPDFContextAuthor as String: "LandlordHours",
            kCGPDFContextTitle as String: "Rental Activity Time Log \(report.taxYear)",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: Self.pageSize), format: format)
        return renderer.pdfData { context in
            let composer = Composer(report: report, context: context, totalPages: totalPages, attachmentData: attachmentData)
            composer.layout()
        }
    }
}

// MARK: - Composer

private final class Composer {
    struct Column {
        let title: String
        let width: CGFloat
        var alignment: NSTextAlignment = .left
    }

    let report: AuditReport
    let context: UIGraphicsPDFRendererContext?
    let totalPages: Int
    let attachmentData: (TimeAttachment) -> Data?

    let pageSize = AuditReportPDFRenderer.pageSize
    let margin: CGFloat = 36
    let footerHeight: CGFloat = 34
    var contentWidth: CGFloat { pageSize.width - 2 * margin }
    var contentBottom: CGFloat { pageSize.height - margin - footerHeight }

    private(set) var pageNumber = 0
    private var y: CGFloat = 0

    // Typography (Helvetica: available everywhere, prints cleanly)
    let titleFont = UIFont(name: "Helvetica-Bold", size: 20) ?? .boldSystemFont(ofSize: 20)
    let sectionFont = UIFont(name: "Helvetica-Bold", size: 13) ?? .boldSystemFont(ofSize: 13)
    let bodyFont = UIFont(name: "Helvetica", size: 10) ?? .systemFont(ofSize: 10)
    let bodyBoldFont = UIFont(name: "Helvetica-Bold", size: 10) ?? .boldSystemFont(ofSize: 10)
    let tableFont = UIFont(name: "Helvetica", size: 8) ?? .systemFont(ofSize: 8)
    let tableHeaderFont = UIFont(name: "Helvetica-Bold", size: 8) ?? .boldSystemFont(ofSize: 8)
    let footerFont = UIFont(name: "Helvetica", size: 8) ?? .systemFont(ofSize: 8)

    let ink = UIColor.black
    let secondaryInk = UIColor(white: 0.25, alpha: 1)
    let rule = UIColor(white: 0.7, alpha: 1)
    let headerFill = UIColor(white: 0.9, alpha: 1)

    let dateFormatter: DateFormatter
    let timestampFormatter: DateFormatter
    let generatedFormatter: DateFormatter

    init(report: AuditReport, context: UIGraphicsPDFRendererContext?, totalPages: Int, attachmentData: @escaping (TimeAttachment) -> Data?) {
        self.report = report
        self.context = context
        self.totalPages = totalPages
        self.attachmentData = attachmentData
        dateFormatter = AuditReportFormat.dateFormatter("yyyy-MM-dd", timeZone: report.timeZone)
        timestampFormatter = AuditReportFormat.dateFormatter("yyyy-MM-dd HH:mm", timeZone: report.timeZone)
        generatedFormatter = AuditReportFormat.dateFormatter("MMMM d, yyyy 'at' HH:mm zzz", timeZone: report.timeZone)
    }

    // MARK: Document

    func layout() {
        newPage()
        drawCover()
        drawQualification()
        drawBreakdowns()
        drawEntryTable()
        drawSourceAppendix()
        drawAttachmentAppendix()
        finishPage()
    }

    private func drawCover() {
        drawText("Rental Activity Time Log: Tax Year \(report.taxYear)", font: titleFont)
        y += 4
        drawText("Prepared with LandlordHours. Generated \(generatedFormatter.string(from: report.generatedAt)).", font: bodyFont, color: secondaryInk)
        y += 10
        for qualification in report.qualifications {
            drawText(qualification.coverLine, font: bodyBoldFont)
            y += 2
        }
        y += 10

        sectionTitle("Summary")
        let s = report.summary
        var range = "No entries"
        if let first = s.firstEntryDate, let last = s.lastEntryDate {
            range = "\(dateFormatter.string(from: first)) to \(dateFormatter.string(from: last))"
        }
        let rows: [[String]] = [
            ["Total hours logged", AuditReportFormat.hours(s.totalHours)],
            ["Hours in REPS-countable activities", AuditReportFormat.hours(s.repsCountableHours)],
            ["Hours in investor-level activities (not countable)", AuditReportFormat.hours(s.nonCountableHours)],
            ["Time entries", "\(s.entryCount)"],
            ["Properties with logged time", "\(s.propertyCount)"],
            ["Photos and receipts attached", "\(s.attachmentCount)"],
            ["Entry dates", range],
            ["Times shown in", "\(report.timeZone.identifier) (\(report.timeZone.abbreviation(for: report.generatedAt) ?? ""))"],
        ]
        table(columns: [Column(title: "Item", width: 520), Column(title: "Value", width: 200, alignment: .right)], rows: rows, font: bodyFont, headerFont: bodyBoldFont)

        if report.isEmpty {
            y += 6
            drawText("No time entries were logged for \(report.taxYear).", font: bodyBoldFont)
        }

        y += 10
        drawText(AuditReportFormat.disclaimer, font: bodyBoldFont)
        y += 16
    }

    private func drawQualification() {
        sectionTitle("Qualification by participant (REPS)")
        let rows = report.qualifications.map { q -> [String] in
            [
                q.participant.rawValue,
                AuditReportFormat.hours(q.realEstateHours),
                q.meets750HourTest ? "Met" : "Not met",
                q.nonRealEstateHours.map(AuditReportFormat.hours) ?? "Not entered",
                q.moreThanHalfText,
                q.statusText,
            ]
        }
        table(
            columns: [
                Column(title: "Participant", width: 80),
                Column(title: "Real estate hours", width: 90, alignment: .right),
                Column(title: "More than 750 hours", width: 95),
                Column(title: "Non-real-estate work hours", width: 120, alignment: .right),
                Column(title: "More than half of work time", width: 125),
                Column(title: "Result", width: 210),
            ],
            rows: rows,
            trailingNote: "REPS is tested for each spouse separately; spouse hours are not combined for the 750-hour test. Investor-level tasks (investing, financing, purchase negotiation) are excluded. Non-real-estate work hours come from the Tax Profile in the app; spouse work hours aren't tracked in the app yet, so the spouse's more-than-half test is not evaluated."
        )

        if !report.materialParticipation.isEmpty {
            y += 8
            let mpRows = report.materialParticipation.map { line -> [String] in
                [
                    line.label,
                    AuditReportFormat.hours(line.ownerAndSpouseHours),
                    line.meets500HourTest ? "Met" : "Not met",
                    line.meets100HourTest ? "Met" : (line.pendingConfirmation ? "Needs confirmation" : "Not met"),
                    line.statusText,
                ]
            }
            table(
                title: report.groupingElection ? "Material participation (grouped activity)" : "Material participation by property",
                columns: [
                    Column(title: "Activity", width: 200),
                    Column(title: "Countable hours (excl. investor)", width: 100, alignment: .right),
                    Column(title: "500-hour test", width: 90),
                    Column(title: "100-hour test", width: 100),
                    Column(title: "Result", width: 230),
                ],
                rows: mpRows,
                trailingNote: "Countable hours leave out investor-level tasks, so they can be lower than the totals in the Hours by property table. The 100-hour test also requires that no other individual participated more. LandlordHours only marks it met after you confirm that in the app."
            )
        }
        y += 10
    }

    private func drawBreakdowns() {
        guard !report.isEmpty else { return }

        sectionTitle("Hours by property")
        table(
            columns: [
                Column(title: "Property", width: 150),
                Column(title: "Type", width: 95),
                Column(title: "Address", width: 195),
                Column(title: "Entries", width: 50, alignment: .right),
                Column(title: "Self hours", width: 60, alignment: .right),
                Column(title: "Spouse hours", width: 60, alignment: .right),
                Column(title: "Total hours", width: 55, alignment: .right),
                Column(title: "REPS-countable", width: 55, alignment: .right),
            ],
            rows: report.propertyTotals.map {
                [$0.name, $0.propertyType, $0.address, "\($0.entryCount)",
                 AuditReportFormat.hours($0.selfHours), AuditReportFormat.hours($0.spouseHours),
                 AuditReportFormat.hours($0.totalHours), AuditReportFormat.hours($0.repsCountableHours)]
            }
        )
        y += 12

        sectionTitle("Hours by category")
        table(
            columns: [
                Column(title: "Category", width: 220),
                Column(title: "Counts toward REPS", width: 110),
                Column(title: "Entries", width: 70, alignment: .right),
                Column(title: "Hours", width: 80, alignment: .right),
            ],
            rows: report.categoryTotals.map {
                [$0.category.rawValue, $0.countsForREPS ? "Yes" : "No (investor-level)", "\($0.entryCount)", AuditReportFormat.hours($0.hours)]
            }
        )
        y += 12

        sectionTitle("Hours by participant")
        table(
            columns: [
                Column(title: "Participant", width: 120),
                Column(title: "Entries", width: 70, alignment: .right),
                Column(title: "Total hours", width: 90, alignment: .right),
                Column(title: "REPS-countable hours", width: 120, alignment: .right),
            ],
            rows: report.participantTotals.map {
                [$0.participant.rawValue, "\($0.entryCount)", AuditReportFormat.hours($0.totalHours), AuditReportFormat.hours($0.repsCountableHours)]
            }
        )
    }

    private func drawEntryTable() {
        guard !report.isEmpty else { return }
        newPage()
        sectionTitle("Time entries (chronological)")
        note("Logged = when the entry was saved in the app. Last edited appears only when the entry was changed after it was logged. Detected and Confirmed appear only for entries the app suggested; other entries show Logged only. Attachments refer to the photo appendix.")
        y += 4

        let maxDescription = 900
        let rows = report.entries.map { row -> [String] in
            var description = row.description
            if description.count > maxDescription {
                description = String(description.prefix(maxDescription)) + "… [truncated; full text in the CSV export]"
            }
            return [
                row.reference,
                dateFormatter.string(from: row.date),
                row.propertyName,
                row.category.rawValue + (row.category.countsForREPS ? "" : " (not countable)"),
                row.participant.rawValue,
                AuditReportFormat.hours(row.hours),
                description,
                timestampFormatter.string(from: row.loggedAt),
                row.lastEditedAt.map { timestampFormatter.string(from: $0) } ?? "",
                row.sourceLabel,
                row.detectedAt.map { timestampFormatter.string(from: $0) } ?? "",
                confirmedCell(row),
                row.attachmentRefs.joined(separator: ", "),
            ]
        }
        table(
            columns: [
                Column(title: "Ref", width: 26),
                Column(title: "Date", width: 48),
                Column(title: "Property", width: 60),
                Column(title: "Category", width: 70),
                Column(title: "Who", width: 38),
                Column(title: "Hours", width: 32, alignment: .right),
                Column(title: "Description", width: 124),
                Column(title: "Logged", width: 56),
                Column(title: "Last edited", width: 56),
                Column(title: "Source", width: 56),
                Column(title: "Detected", width: 56),
                Column(title: "Confirmed", width: 62),
                Column(title: "Attach.", width: 36),
            ],
            rows: rows
        )
        y += 6
        drawText("Total: \(report.summary.entryCount) entries, \(AuditReportFormat.hours(report.summary.totalHours)) hours.", font: bodyBoldFont)
    }

    private func confirmedCell(_ row: AuditReport.EntryRow) -> String {
        guard let confirmed = row.confirmedAt else { return "" }
        var cell = timestampFormatter.string(from: confirmed)
        if let lag = row.confirmationLagText { cell += "\n" + lag }
        return cell
    }

    private func drawSourceAppendix() {
        guard !report.isEmpty else { return }
        ensureSpace(150)
        y += 14
        sectionTitle("Appendix: where entries came from")
        table(
            columns: [Column(title: "Source", width: 220), Column(title: "Entries", width: 80, alignment: .right)],
            rows: report.sourceTotals.map { [$0.label, "\($0.entryCount)"] },
            trailingNote: AuditReportFormat.suggestionExplanation
        )
    }

    private func drawAttachmentAppendix() {
        guard !report.attachments.isEmpty else { return }
        newPage()
        sectionTitle("Appendix: photos and receipts")
        note("Each item lists its reference, the entry it belongs to, and the original file name. Photos are printed large enough to read.")
        y += 6

        let perRow = 2
        let gap: CGFloat = 12
        let cellWidth = (contentWidth - gap) / CGFloat(perRow)
        let captionHeight: CGFloat = 30
        let placeholder = CGSize(width: AuditReportPDFRenderer.appendixBox.width, height: 90)

        for chunkStart in stride(from: 0, to: report.attachments.count, by: perRow) {
            let chunk = Array(report.attachments[chunkStart..<min(chunkStart + perRow, report.attachments.count)])
            let items = chunk.map { ref -> (ref: AuditReport.AttachmentRef, data: Data?, size: CGSize) in
                let data = attachmentData(ref.attachment)
                let pixels = data.flatMap(AuditReportPDFRenderer.pixelSize(of:))
                let size = pixels.map { AuditReportPDFRenderer.appendixImageSize(pixelSize: $0) } ?? placeholder
                return (ref, data, size)
            }
            let imageRowHeight = items.map(\.size.height).max() ?? placeholder.height
            // Keep each image with its caption: move the whole row to a new page if needed.
            ensureSpace(imageRowHeight + captionHeight + gap)

            for (offset, item) in items.enumerated() {
                let cellX = margin + CGFloat(offset) * (cellWidth + gap)
                let rect = CGRect(x: cellX + (cellWidth - item.size.width) / 2, y: y, width: item.size.width, height: item.size.height)
                drawAttachment(item.ref.attachment, data: item.data, in: rect)
                let caption = "\(item.ref.reference) · entry \(item.ref.entryReference) · \(dateFormatter.string(from: item.ref.entryDate))\n\(item.ref.attachment.filename)"
                drawText(caption, font: tableFont, color: ink,
                         in: CGRect(x: cellX, y: y + imageRowHeight + 4, width: cellWidth, height: captionHeight - 4),
                         alignment: .center)
            }
            y += imageRowHeight + captionHeight + gap
        }
    }

    // MARK: Pages

    private func newPage() {
        if pageNumber > 0 { finishPage() }
        pageNumber += 1
        context?.beginPage()
        y = margin
    }

    private func finishPage() {
        guard context != nil else { return }
        let footerTop = pageSize.height - margin - footerHeight + 10
        strokeLine(from: CGPoint(x: margin, y: footerTop), to: CGPoint(x: pageSize.width - margin, y: footerTop))
        let generated = "Generated by LandlordHours on \(generatedFormatter.string(from: report.generatedAt))"
        let pageLabel = "Page \(pageNumber) of \(totalPages)"
        drawText(generated, font: footerFont, color: secondaryInk, in: CGRect(x: margin, y: footerTop + 4, width: contentWidth - 100, height: 10))
        drawText(pageLabel, font: footerFont, color: secondaryInk, in: CGRect(x: pageSize.width - margin - 100, y: footerTop + 4, width: 100, height: 10), alignment: .right)
        drawText(AuditReportFormat.disclaimer, font: footerFont, color: secondaryInk, in: CGRect(x: margin, y: footerTop + 14, width: contentWidth, height: 10))
    }

    private func ensureSpace(_ height: CGFloat) {
        if y + height > contentBottom { newPage() }
    }

    // MARK: Primitives

    private func attributes(_ font: UIFont, _ color: UIColor, _ alignment: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        // Ligatures off: fonts embed without ToUnicode for ligature glyphs, so "fi" would
        // extract as missing text and break copy/search for "financing" or "Tax Profile".
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph, .ligature: 0]
    }

    private func measure(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return font.lineHeight }
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes(font, ink),
            context: nil
        )
        return ceil(rect.height)
    }

    private func drawText(_ text: String, font: UIFont, color: UIColor? = nil, in rect: CGRect, alignment: NSTextAlignment = .left) {
        guard context != nil else { return }
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
            attributes: attributes(font, color ?? ink, alignment),
            context: nil
        )
    }

    /// Flowing paragraph at the current position.
    private func drawText(_ text: String, font: UIFont, color: UIColor? = nil) {
        let height = measure(text, font: font, width: contentWidth)
        ensureSpace(height)
        drawText(text, font: font, color: color, in: CGRect(x: margin, y: y, width: contentWidth, height: height + 1))
        y += height
    }

    private func sectionTitle(_ title: String) {
        // Keep a title with at least a few lines of what follows.
        ensureSpace(measure(title, font: sectionFont, width: contentWidth) + 60)
        drawText(title, font: sectionFont)
        y += 6
    }

    private func note(_ text: String) {
        y += 4
        drawText(text, font: tableFont, color: secondaryInk)
    }

    private func strokeLine(from: CGPoint, to: CGPoint) {
        guard let cg = context?.cgContext else { return }
        cg.saveGState()
        cg.setStrokeColor(rule.cgColor)
        cg.setLineWidth(0.5)
        cg.move(to: from)
        cg.addLine(to: to)
        cg.strokePath()
        cg.restoreGState()
    }

    private func fill(_ rect: CGRect, _ color: UIColor) {
        guard let cg = context?.cgContext else { return }
        cg.saveGState()
        cg.setFillColor(color.cgColor)
        cg.fill(rect)
        cg.restoreGState()
    }

    /// Draws a table. A `trailingNote` is kept on the same page as the table's last row.
    /// With a `title`, a table that fits on one page is moved whole to a new page rather than split.
    private func table(title: String? = nil, columns: [Column], rows: [[String]], font: UIFont? = nil, headerFont: UIFont? = nil, trailingNote: String? = nil) {
        let cellFont = font ?? tableFont
        let headFont = headerFont ?? tableHeaderFont
        let padX: CGFloat = 3
        let padY: CGFloat = 3
        let tableWidth = columns.reduce(0) { $0 + $1.width }

        func rowHeight(_ cells: [String], _ font: UIFont) -> CGFloat {
            zip(cells, columns).map { measure($0, font: font, width: $1.width - 2 * padX) }.max().map { $0 + 2 * padY } ?? 0
        }

        func drawRow(_ cells: [String], _ font: UIFont, height: CGFloat, header: Bool) {
            if header { fill(CGRect(x: margin, y: y, width: tableWidth, height: height), headerFill) }
            var x = margin
            for (cell, column) in zip(cells, columns) {
                drawText(cell, font: font, color: ink,
                         in: CGRect(x: x + padX, y: y + padY, width: column.width - 2 * padX, height: height - 2 * padY + 1),
                         alignment: column.alignment)
                x += column.width
            }
            y += height
            strokeLine(from: CGPoint(x: margin, y: y), to: CGPoint(x: margin + tableWidth, y: y))
        }

        let headerCells = columns.map(\.title)
        let headerHeight = rowHeight(headerCells, headFont)

        func drawHeader() {
            strokeLine(from: CGPoint(x: margin, y: y), to: CGPoint(x: margin + tableWidth, y: y))
            drawRow(headerCells, headFont, height: headerHeight, header: true)
        }

        let noteHeight = trailingNote.map { 4 + measure($0, font: tableFont, width: contentWidth) } ?? 0
        if let title {
            let titleHeight = measure(title, font: sectionFont, width: contentWidth) + 6
            let total = titleHeight + headerHeight + rows.reduce(0) { $0 + rowHeight($1, cellFont) } + noteHeight
            if y + total > contentBottom && total <= contentBottom - margin { newPage() }
            sectionTitle(title)
        }
        ensureSpace(headerHeight + (rows.first.map { rowHeight($0, cellFont) } ?? 0))
        drawHeader()
        for (index, row) in rows.enumerated() {
            let height = rowHeight(row, cellFont)
            let keep = index == rows.count - 1 ? noteHeight : 0
            if y + height + keep > contentBottom {
                newPage()
                drawHeader() // repeat the header on continuation pages
            }
            drawRow(row, cellFont, height: height, header: false)
        }
        if let trailingNote { note(trailingNote) }
    }

    private func drawAttachment(_ attachment: TimeAttachment, data: Data?, in rect: CGRect) {
        guard context != nil else { return }
        guard let data else {
            strokeRect(rect)
            drawText("File not available on this device", font: tableFont, color: secondaryInk, in: rect.insetBy(dx: 8, dy: rect.height / 2 - 10), alignment: .center)
            return
        }
        // Resolution for the drawn size: at least 200 ppi, never more pixels than the source has.
        let maxPixel = Int(ceil(max(rect.width, rect.height) * AuditReportPDFRenderer.minimumPPI / 72))
        guard let image = Self.thumbnail(from: data, maxPixel: maxPixel) else {
            strokeRect(rect)
            let kind = attachment.mimeType == "application/pdf" ? "PDF document" : "File"
            drawText("\(kind) (no preview)", font: tableFont, color: secondaryInk, in: rect.insetBy(dx: 8, dy: rect.height / 2 - 10), alignment: .center)
            return
        }
        UIImage(cgImage: image).draw(in: rect)
        strokeRect(rect)
    }

    private func strokeRect(_ rect: CGRect) {
        guard let cg = context?.cgContext else { return }
        cg.saveGState()
        cg.setStrokeColor(rule.cgColor)
        cg.setLineWidth(0.5)
        cg.stroke(rect)
        cg.restoreGState()
    }

    /// Downsampled, orientation-corrected thumbnail, re-encoded as JPEG so the PDF stays small.
    static func thumbnail(from data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let jpeg = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil) else { return thumb }
        CGImageDestinationAddImage(destination, thumb, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let provider = CGDataProvider(data: jpeg as CFData),
              let encoded = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return thumb }
        return encoded
    }
}
