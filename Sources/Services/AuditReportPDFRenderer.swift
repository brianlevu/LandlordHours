import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Renders an `AuditReport` as a printable, black-on-white PDF (US Letter, landscape).
///
/// Layout runs twice: a measuring pass that counts pages, then the drawing pass, so every
/// page footer can say "Page n of N".
/// One string from the package catalog (`Settings.xcstrings`, keys `pdf.*`).
private func L(_ key: StaticString, _ value: String.LocalizationValue) -> String { HS.t(key, value) }

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
            kCGPDFContextCreator as String: "Dormer",
            kCGPDFContextAuthor as String: "Dormer",
            kCGPDFContextTitle as String: HS.recordTitle(year: report.taxYear),
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

    /// Whether the report covers a spouse's hours (then each person's 750 is shown on its own line or column).
    private var hasSpouse: Bool { report.participantTotals.contains { $0.participant == .spouse } }

    private func drawCover() {
        drawText(HS.recordTitle(year: report.taxYear), font: titleFont)
        y += 4
        drawText(HS.f("pdf.prepared", "Prepared in Dormer on %@.", generatedFormatter.string(from: report.generatedAt)), font: bodyFont, color: secondaryInk)
        y += 10
        for qualification in report.qualifications {
            drawText(qualification.coverLine, font: bodyBoldFont)
            y += 2
        }
        y += 10

        sectionTitle(L("pdf.summary", "Summary"))
        let s = report.summary
        var range = L("pdf.no.entries", "No entries")
        if let first = s.firstEntryDate, let last = s.lastEntryDate {
            range = "\(dateFormatter.string(from: first)) to \(dateFormatter.string(from: last))"
        }
        // The 750 is each person's own: one line per person, never the two added together.
        var repsRows: [[String]] = [[L("pdf.hours.toward.750.you", "Your hours toward 750"), AuditReportFormat.hours(s.selfRepsHours)]]
        if hasSpouse { repsRows.append([L("pdf.hours.toward.750.spouse", "Spouse hours toward 750"), AuditReportFormat.hours(s.spouseRepsHours)]) }
        let rows: [[String]] = [
            [L("pdf.total.hours.logged", "Total hours logged"), AuditReportFormat.hours(s.totalHours)],
        ] + repsRows + [
            [L("pdf.hours.in.investor.level.activities.not", "Investor hours (don’t count)"), AuditReportFormat.hours(s.nonCountableHours)],
            [L("pdf.time.entries", "Records"), "\(s.entryCount)"],
            [L("pdf.properties.with.logged.time", "Rentals with hours"), "\(s.propertyCount)"],
            [L("pdf.photos.and.receipts.attached", "Photos and receipts attached"), "\(s.attachmentCount)"],
            [L("pdf.entry.dates", "Record dates"), range],
            [L("pdf.times.shown.in", "Times shown in"), "\(report.timeZone.identifier) (\(report.timeZone.abbreviation(for: report.generatedAt) ?? ""))"],
        ]
        table(columns: [Column(title: L("pdf.item", "Item"), width: 520), Column(title: L("pdf.value", "Value"), width: 200, alignment: .right)], rows: rows, font: bodyFont, headerFont: bodyBoldFont)

        if report.isEmpty {
            y += 6
            drawText(HS.f("pdf.empty", "No hours were logged for %lld.", report.taxYear), font: bodyBoldFont)
        }

        y += 10
        drawText(AuditReportFormat.disclaimer, font: bodyBoldFont)
        y += 16
    }

    private func drawQualification() {
        sectionTitle(L("pdf.h750.hours.by.person", "Hours toward 750, by person"))
        let rows = report.qualifications.map { q -> [String] in
            [
                q.participant.rawValue,
                AuditReportFormat.hours(q.realEstateHours),
                q.meets750HourTest ? L("pdf.met", "Met") : L("pdf.not.met", "Not met"),
                q.nonRealEstateHours.map(AuditReportFormat.hours) ?? L("pdf.not.entered", "Not entered"),
                q.moreThanHalfText,
                q.statusText,
            ]
        }
        table(
            columns: [
                Column(title: L("pdf.person", "Who"), width: 80),
                Column(title: L("pdf.real.estate.hours", "Real estate hours"), width: 90, alignment: .right),
                Column(title: L("pdf.more.than.750.hours", "More than 750 hours"), width: 95),
                Column(title: L("pdf.non.real.estate.work.hours", "Non-real-estate work hours"), width: 120, alignment: .right),
                Column(title: L("pdf.more.than.half.of.work.time", "More than half of work time"), width: 125),
                Column(title: L("pdf.result", "Result"), width: 210),
            ],
            rows: rows,
            trailingNote: L("pdf.h750.is.tested.for.each.spouse", "The 750-hour test is checked for each spouse separately; spouse hours are not combined for the 750-hour test. Investor-level tasks (investing, financing, purchase negotiation) are excluded. Non-real-estate work hours come from Filing and goal in the app; spouse work hours aren’t tracked in the app yet, so the spouse’s more-than-half test is not evaluated.")
        )

        if !report.materialParticipation.isEmpty {
            y += 8
            let mpRows = report.materialParticipation.map { line -> [String] in
                [
                    line.label,
                    AuditReportFormat.hours(line.ownerAndSpouseHours),
                    line.meets500HourTest ? L("pdf.met", "Met") : L("pdf.not.met", "Not met"),
                    line.meets100HourTest ? L("pdf.met", "Met") : (line.pendingConfirmation ? L("pdf.needs.confirmation", "Needs confirmation") : L("pdf.not.met", "Not met")),
                    line.statusText,
                ]
            }
            table(
                title: report.groupingElection ? L("pdf.material.part.grouped.activity", "500-hour and 100-hour tests (grouped activity)") : L("pdf.material.part.by.property", "500-hour and 100-hour tests by property"),
                columns: [
                    Column(title: L("pdf.activity", "Activity"), width: 200),
                    Column(title: L("pdf.counts.hours.excl.investor", "Hours that count (no investor hours)"), width: 100, alignment: .right),
                    Column(title: L("pdf.500.hour.test", "500-hour test"), width: 90),
                    Column(title: L("pdf.100.hour.test", "100-hour test"), width: 100),
                    Column(title: L("pdf.result", "Result"), width: 230),
                ],
                rows: mpRows,
                trailingNote: L("pdf.counts.hours.leave.out.investor.level", "Hours that count leave out investor-level tasks, so they can be lower than the totals in the Hours by rental table. The 100-hour test also requires that no other individual participated more. It counts as met only after you confirm it in the app.")
            )
        }
        y += 10
    }

    private func drawBreakdowns() {
        guard !report.isEmpty else { return }

        sectionTitle(L("pdf.hours.by.property", "Hours by rental"))
        var columns = [
            Column(title: L("pdf.property", "Rental"), width: hasSpouse ? 140 : 150),
            Column(title: L("pdf.type", "Type"), width: hasSpouse ? 85 : 95),
            Column(title: L("pdf.address", "Address"), width: hasSpouse ? 150 : 195),
            Column(title: L("pdf.entries", "Records"), width: hasSpouse ? 45 : 50, alignment: .right),
            Column(title: L("pdf.self.hours", "Your hours"), width: hasSpouse ? 55 : 60, alignment: .right),
            Column(title: L("pdf.spouse.hours", "Spouse hours"), width: hasSpouse ? 55 : 60, alignment: .right),
            Column(title: L("pdf.total.hours", "Total hours"), width: hasSpouse ? 55 : 55, alignment: .right),
            Column(title: L("pdf.h750.counts.you", "Your 750 hours"), width: hasSpouse ? 65 : 55, alignment: .right),
        ]
        if hasSpouse { columns.append(Column(title: L("pdf.h750.counts.spouse", "Spouse 750 hours"), width: 70, alignment: .right)) }
        func rentalRow(_ name: String, _ type: String, _ address: String, _ records: Int, _ p: (me: Double, spouse: Double, total: Double, repsMe: Double, repsSpouse: Double)) -> [String] {
            var cells = [name, type, address, "\(records)", AuditReportFormat.hours(p.me), AuditReportFormat.hours(p.spouse),
                         AuditReportFormat.hours(p.total), AuditReportFormat.hours(p.repsMe)]
            if hasSpouse { cells.append(AuditReportFormat.hours(p.repsSpouse)) }
            return cells
        }
        let lines = report.propertyTotals.map {
            rentalRow($0.name, $0.propertyType, $0.address, $0.entryCount, ($0.selfHours, $0.spouseHours, $0.totalHours, $0.selfRepsHours, $0.spouseRepsHours))
        }
        // Totals row: every column is its own column's sum, so each person's 750 stays that person's.
        let all = report.propertyTotals
        let totals = rentalRow(L("pdf.total.all.rentals", "Total, all rentals"), "", "", all.reduce(0) { $0 + $1.entryCount },
                               (all.reduce(0) { $0 + $1.selfHours }, all.reduce(0) { $0 + $1.spouseHours }, all.reduce(0) { $0 + $1.totalHours },
                                all.reduce(0) { $0 + $1.selfRepsHours }, all.reduce(0) { $0 + $1.spouseRepsHours }))
        table(columns: columns, rows: lines + [totals])
        y += 12

        sectionTitle(L("pdf.hours.by.category", "Hours by category"))
        // With a spouse, hours are shown per person beside the Yes/No flag, never as one combined figure that
        // could be read as hours toward the 750.
        let flag = { (c: AuditReport.CategoryTotal) in c.countsForREPS ? L("pdf.yes", "Yes") : L("pdf.no.investor.level", "No (investor hours)") }
        if hasSpouse {
            table(
                columns: [
                    Column(title: L("pdf.category", "Category"), width: 200),
                    Column(title: L("pdf.counts.for.h750.test", "Counts for the 750 test"), width: 150),
                    Column(title: L("pdf.entries", "Records"), width: 70, alignment: .right),
                    Column(title: L("pdf.hours.you", "Your hours"), width: 90, alignment: .right),
                    Column(title: L("pdf.hours.spouse", "Spouse hours"), width: 90, alignment: .right),
                ],
                rows: report.categoryTotals.map {
                    [$0.category.rawValue, flag($0), "\($0.entryCount)", AuditReportFormat.hours($0.selfHours), AuditReportFormat.hours($0.spouseHours)]
                }
            )
        } else {
            table(
                columns: [
                    Column(title: L("pdf.category", "Category"), width: 220),
                    Column(title: L("pdf.counts.for.h750.test", "Counts for the 750 test"), width: 150),
                    Column(title: L("pdf.entries", "Records"), width: 70, alignment: .right),
                    Column(title: L("pdf.hours", "Hours"), width: 80, alignment: .right),
                ],
                rows: report.categoryTotals.map { [$0.category.rawValue, flag($0), "\($0.entryCount)", AuditReportFormat.hours($0.hours)] }
            )
        }
        y += 12

        sectionTitle(L("pdf.hours.by.person", "Hours by person"))
        table(
            columns: [
                Column(title: L("pdf.person", "Who"), width: 120),
                Column(title: L("pdf.entries", "Records"), width: 70, alignment: .right),
                Column(title: L("pdf.total.hours", "Total hours"), width: 90, alignment: .right),
                Column(title: L("pdf.h750.counts.hours", "Hours toward 750"), width: 120, alignment: .right),
            ],
            rows: report.participantTotals.map {
                [$0.participant.rawValue, "\($0.entryCount)", AuditReportFormat.hours($0.totalHours), AuditReportFormat.hours($0.repsCountableHours)]
            }
        )
    }

    private func drawEntryTable() {
        guard !report.isEmpty else { return }
        newPage()
        sectionTitle(L("pdf.time.entries.chronological", "Records, by date"))
        note(L("pdf.logged.when.the.entry.was.saved", "Logged = when the entry was saved in the app. Last edited appears only when the entry was changed after it was logged. Suggested and Confirmed appear only for entries the app suggested; other entries show Logged only. Attachments refer to the photo appendix."))
        y += 4

        let maxDescription = 900
        let rows = report.entries.map { row -> [String] in
            var description = row.description
            if description.count > maxDescription {
                description = String(description.prefix(maxDescription)) + L("pdf.truncated", "… [truncated; full text in the CSV export]")
            }
            return [
                row.reference,
                dateFormatter.string(from: row.date),
                row.propertyName,
                row.category.rawValue + (row.category.countsForREPS ? "" : L("pdf.notcounts", " (doesn’t count)")),
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
                Column(title: L("pdf.ref", "Ref"), width: 26),
                Column(title: L("pdf.date", "Date"), width: 48),
                Column(title: L("pdf.property", "Rental"), width: 60),
                Column(title: L("pdf.category", "Category"), width: 70),
                Column(title: L("pdf.who", "Who"), width: 38),
                Column(title: L("pdf.hours", "Hours"), width: 32, alignment: .right),
                Column(title: L("pdf.description", "Description"), width: 124),
                Column(title: L("pdf.logged", "Logged"), width: 56),
                Column(title: L("pdf.last.edited", "Last edited"), width: 56),
                Column(title: L("pdf.source", "Source"), width: 56),
                Column(title: L("pdf.suggested", "Suggested"), width: 56),
                Column(title: L("pdf.confirmed", "Confirmed"), width: 62),
                Column(title: L("pdf.attach", "Attach."), width: 36),
            ],
            rows: rows
        )
        y += 6
        drawText(HS.f("pdf.total", "Total: %lld records, %@ hours.", report.summary.entryCount, AuditReportFormat.hours(report.summary.totalHours)), font: bodyBoldFont)
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
        sectionTitle(L("pdf.appendix.where.entries.came.from", "Appendix: where records came from"))
        table(
            columns: [Column(title: L("pdf.source", "Source"), width: 220), Column(title: L("pdf.entries", "Records"), width: 80, alignment: .right)],
            rows: report.sourceTotals.map { [$0.label, "\($0.entryCount)"] },
            trailingNote: AuditReportFormat.suggestionExplanation
        )
    }

    private func drawAttachmentAppendix() {
        guard !report.attachments.isEmpty else { return }
        newPage()
        sectionTitle(L("pdf.appendix.photos.and.receipts", "Appendix: photos and receipts"))
        note(L("pdf.each.item.lists.its.reference.the", "Each item lists its reference, the entry it belongs to, and the original file name. Photos are printed large enough to read."))
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
        let generated = HS.f("pdf.generated", "Made with Dormer on %@", generatedFormatter.string(from: report.generatedAt))
        let pageLabel = HS.f("pdf.page", "Page %lld of %lld", pageNumber, totalPages)
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
            drawText(L("pdf.file.not.available.on.this.device", "File not available on this device"), font: tableFont, color: secondaryInk, in: rect.insetBy(dx: 8, dy: rect.height / 2 - 10), alignment: .center)
            return
        }
        // Resolution for the drawn size: at least 200 ppi, never more pixels than the source has.
        let maxPixel = Int(ceil(max(rect.width, rect.height) * AuditReportPDFRenderer.minimumPPI / 72))
        guard let image = Self.thumbnail(from: data, maxPixel: maxPixel) else {
            strokeRect(rect)
            let kind = attachment.mimeType == "application/pdf" ? L("pdf.kind.pdf", "PDF document") : L("pdf.kind.file", "File")
            drawText(HS.f("pdf.nopreview", "%@ (no preview)", kind), font: tableFont, color: secondaryInk, in: rect.insetBy(dx: 8, dy: rect.height / 2 - 10), alignment: .center)
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
