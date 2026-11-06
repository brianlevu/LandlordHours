import SwiftUI
import LinkPresentation
import UniformTypeIdentifiers

/// WP-L: the PDF + CSV export runs in the background, so the user can close the export sheet
/// and keep using the app. When it is ready and the sheet is closed, the shell shows a small
/// "Your report is ready" banner; tapping it opens the share sheet. A failure says so in the
/// sheet (and in the banner slot when the sheet is closed).
///
/// States: idle → generating(year) → ready(files, year) | failed(year, message).
@MainActor
final class ExportJob: ObservableObject {
    static let shared = ExportJob()

    enum State: Equatable {
        case idle
        case generating(year: Int)
        case ready(ExportShareItem, year: Int)
        case failed(year: Int, message: String)
    }

    typealias Writer = @Sendable (AuditReport, Int) async -> Result<ExportShareItem, Error>

    @Published private(set) var state: State = .idle
    /// The export sheet is on screen (it shows the result itself; no banner then).
    @Published var isSheetVisible = false
    /// The ready banner was closed or used.
    @Published private(set) var bannerDismissed = false

    static var failureMessage: String { HS.t("export.failure", "Couldn’t create the record. Try again.") }

    private let writer: Writer
    private var runID = UUID()
    /// Fingerprint of the records the ready (or running) report was made from.
    private(set) var reportFingerprint: String?
    private var task: Task<Void, Never>?

    /// Tests: wait for the current export to end.
    func waitUntilDone() async {
        await task?.value
    }

    init(writer: @escaping Writer = ExportJob.liveWriter) {
        self.writer = writer
    }

    /// Writes the files off the main actor. DEBUG `-LHSlowExport <seconds>` waits first, so a
    /// capture can show the generating state and leave the sheet.
    static let liveWriter: Writer = { report, year in
        #if DEBUG
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-LHSlowExport"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1),
           let seconds = Double(ProcessInfo.processInfo.arguments[index + 1]) {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
        #endif
        return await Task.detached(priority: .userInitiated) {
            AuditExportFiles.write(report: report, year: year)
        }.value
    }

    var isGenerating: Bool {
        if case .generating = state { return true }
        return false
    }

    /// The year of the ready or failed report, for the shell's staleness check.
    var resultYear: Int? {
        switch state {
        case .ready(_, let year), .failed(let year, _): return year
        case .idle, .generating: return nil
        }
    }

    /// The finished files for `year`, if any. With `fingerprint`, only while the records still
    /// match the ones the report was made from.
    func readyFiles(for year: Int, fingerprint: String? = nil) -> ExportShareItem? {
        guard case .ready(let item, let readyYear) = state, readyYear == year else { return nil }
        if let fingerprint, fingerprint != reportFingerprint { return nil }
        return item
    }

    /// A report for `year` is ready but the records changed since it was made.
    func isStale(year: Int, fingerprint: String) -> Bool {
        guard case .ready(_, let readyYear) = state, readyYear == year else { return false }
        return fingerprint != reportFingerprint
    }

    func failureMessage(for year: Int) -> String? {
        if case .failed(let failedYear, let message) = state, failedYear == year { return message }
        return nil
    }

    enum Banner: Equatable { case ready, failed }

    /// The banner shows once a report is ready (or failed) while the export sheet is closed.
    var banner: Banner? {
        guard !isSheetVisible, !bannerDismissed else { return nil }
        switch state {
        case .ready: return .ready
        case .failed: return .failed
        case .idle, .generating: return nil
        }
    }

    var showsReadyBanner: Bool { banner == .ready }

    /// The banner, unless the ready report no longer matches the records (then the export sheet
    /// offers "Create again" instead).
    func banner(currentFingerprint: String?) -> Banner? {
        guard let banner else { return nil }
        if banner == .ready, let currentFingerprint, currentFingerprint != reportFingerprint { return nil }
        return banner
    }

    /// Starts generating unless a report is already being made.
    func start(report: AuditReport, year: Int, fingerprint: String? = nil) {
        guard !isGenerating else { return }
        // A new report replaces the old one: don't leave its PDF and CSV in temp.
        if case .ready(let previous, _) = state { Self.deleteFiles(previous) }
        let id = UUID()
        runID = id
        reportFingerprint = fingerprint
        bannerDismissed = false
        state = .generating(year: year)
        task = Task { [weak self, writer] in
            let result = await writer(report, year)
            guard let self, self.runID == id else {
                // Reset (or a newer run) while writing: drop what this run produced.
                if case .success(let files) = result { ExportJob.deleteFiles(files) }
                return
            }
            // Seen in the open sheet already: no banner for it after the sheet closes.
            self.bannerDismissed = self.isSheetVisible
            switch result {
            case .success(let files):
                self.state = .ready(files, year: year)
                // WP-R's success haptic, when the user is watching the sheet.
                if self.isSheetVisible { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            case .failure:
                self.state = .failed(year: year, message: Self.failureMessage)
                RatingPromptCoordinator.shared.noteError()
            }
        }
    }

    /// The banner was tapped: hand over the files for the share sheet and retire the banner.
    func takeReadyForSharing() -> ExportShareItem? {
        guard case .ready(let item, _) = state else { return nil }
        bannerDismissed = true
        return item
    }

    func dismissBanner() {
        bannerDismissed = true
    }

    /// Deletes a report's PDF and CSV, and their folder when it is one of ours.
    nonisolated static func deleteFiles(_ files: ExportShareItem) {
        let fm = FileManager.default
        try? fm.removeItem(at: files.pdfURL)
        try? fm.removeItem(at: files.csvURL)
        let folder = files.pdfURL.deletingLastPathComponent()
        if folder.lastPathComponent.hasPrefix("LandlordHoursExport-") {
            try? fm.removeItem(at: folder)
        }
    }

    /// Sign-out / profile switch: the files belong to the outgoing profile.
    func reset() {
        task?.cancel()
        runID = UUID()
        reportFingerprint = nil
        // The outgoing profile's report must not linger in temp.
        if case .ready(let files, _) = state { Self.deleteFiles(files) }
        state = .idle
        bannerDismissed = false
        isSheetVisible = false
    }
}

/// "Your record is ready · Share". Floats above the tab bar; tap to open the share sheet. The
/// failed variant says the record couldn't be made and to try again from Export. Standard v2: SF
/// symbols, `LHButton.icon` for the close, strings from the package catalog.
struct ExportReadyBanner: View {
    /// The one subtitle for a ready report, on screen and for VoiceOver.
    static var readySubtitle: String { HS.t("export.banner.subtitle", "PDF and spreadsheet") }
    var kind: ExportJob.Banner = .ready
    var onOpen: () -> Void
    var onDismiss: () -> Void
    /// Seconds before the ready banner folds into a small pill, so it takes as little of the
    /// page as possible (it sits in its own row and never covers content).
    var collapseAfter: Double = 4
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var collapsed = false
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var readyLine: String { HS.t("export.banner.ready", "Your record is ready") }
    private var failedLine: String { HS.t("export.banner.failed", "Couldn’t create your record") }
    private var shareLine: String { HS.t("export.banner.share", "Share") }

    var body: some View {
        Group {
            if kind == .ready && collapsed {
                pill
                    .transition(.opacity)
            } else {
                full
                    .transition(.opacity)
            }
        }
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: kind == .ready ? readyLine : failedLine)
            guard kind == .ready else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + collapseAfter) {
                if reduceMotion { collapsed = true } else { withAnimation(AppAnimation.smooth) { collapsed = true } }
            }
        }
    }

    private var closeButton: some View {
        Button(action: onDismiss) { Image(systemName: "xmark") }
            .buttonStyle(LHButton.icon)
            .accessibilityLabel(HS.t("common.close", "Close"))
            .accessibilityIdentifier("export.readyBanner.close")
    }

    /// "Record ready · Share", a compact centred pill.
    private var pill: some View {
        HStack(spacing: 4) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(colors.positive)
                    Text(HS.t("export.banner.pill", "Record ready"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(shareLine)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.action)
                }
                .padding(.leading, 14)
                .frame(minHeight: LHMetrics.minTap)
                .contentShape(Rectangle())
            }
            .buttonStyle(LHButton.press)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(HS.f("export.banner.a11y", "%@. %@. %@", readyLine, Self.readySubtitle, shareLine))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("export.readyBanner")

            closeButton
        }
        .background(
            Capsule()
                .fill(colors.backgroundSecondary)
                .shadow(color: .black.opacity(LHToastMetrics.shadowOpacity(colorScheme)), radius: 10, y: 3)
        )
        .overlay(Capsule().strokeBorder(colors.border, lineWidth: LHMetrics.hairline))
        .frame(maxWidth: .infinity)
    }

    private var full: some View {
        HStack(spacing: 12) {
            if kind == .ready {
                Button(action: onOpen) {
                    HStack(spacing: 12) {
                        LHRowGlyph(systemImage: "doc.badge.checkmark", tint: .positive)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(readyLine)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(colors.textPrimary)
                            Text(Self.readySubtitle)
                                .font(.footnote)
                                .foregroundStyle(colors.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Text(shareLine)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(colors.action)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(LHButton.press)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(HS.f("export.banner.a11y", "%@. %@. %@", readyLine, Self.readySubtitle, shareLine))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("export.readyBanner")
            } else {
                HStack(spacing: 12) {
                    LHRowGlyph(systemImage: "exclamationmark.triangle.fill", tint: .caution)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(failedLine)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(colors.textPrimary)
                        Text(HS.t("export.banner.retry", "Try again from Export."))
                            .font(.footnote)
                            .foregroundStyle(colors.textSecondary)
                    }
                    Spacer(minLength: 8)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("export.failedBanner")
            }

            closeButton
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: 60)
        .background(
            RoundedRectangle(cornerRadius: LHToastMetrics.radius, style: .continuous)
                .fill(colors.backgroundSecondary)
                .shadow(color: .black.opacity(LHToastMetrics.shadowOpacity(colorScheme)), radius: 16, y: 4)
        )
        .overlay(RoundedRectangle(cornerRadius: LHToastMetrics.radius, style: .continuous)
            .strokeBorder(colors.border, lineWidth: LHMetrics.hairline))
    }
}

/// What a report was made from: the year's entries (and their edits), the properties, and the
/// tax profile values the report prints. Any change makes a ready report out of date.
enum ExportFingerprint {
    static func make(entries: [TimeEntry], properties: [RentalProperty], year: Int, profile: String) -> String {
        let calendar = Calendar.current
        var parts: [String] = ["y\(year)", profile]
        let yearEntries = entries
            .filter { calendar.component(.year, from: $0.date) == year }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for entry in yearEntries {
            let fields: [String] = [
                entry.id.uuidString, entry.propertyId.uuidString, "\(entry.participant)", "\(entry.category)",
                "\(entry.hours)", "\(entry.date.timeIntervalSince1970)", "\(entry.modifiedAt.timeIntervalSince1970)",
                entry.notes, entry.attachments.map(\.id.uuidString).joined(separator: ","),
            ]
            parts.append(fields.joined(separator: "|"))
        }
        for property in properties.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            parts.append("p|\(property.id.uuidString)|\(property.name)|\(property.address)|\(property.propertyType)")
        }
        return parts.joined(separator: "\n")
    }

    /// The live fingerprint for the active profile.
    @MainActor static func current(app: AppViewModel, year: Int) -> String {
        let tax = TaxProfileManager.shared
        let mostHours = String(describing: tax.noOneParticipatedMore(forYear: year))
        let profile = "\(tax.spouseTracking)|\(tax.nonREWorkHours)|\(tax.groupingElection)|\(mostHours)|\(tax.filingStatus)"
        return make(entries: app.timeEntries, properties: app.properties, year: year, profile: profile)
    }
}

/// A report file for the share sheet: always the FILE (PDF, or the spreadsheet as a .csv with
/// type public.comma-separated-values-text and its real filename), never pasted text, so it
/// arrives as an attachment in Mail and as a file in Files.
final class ExportShareFile: NSObject, UIActivityItemSource {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    var typeIdentifier: String {
        url.pathExtension.lowercased() == "csv" ? UTType.commaSeparatedText.identifier : UTType.pdf.identifier
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { url }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { url }

    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String { typeIdentifier }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = url.lastPathComponent
        metadata.originalURL = url
        metadata.url = url
        // A document icon, not the generic link compass.
        let symbol = typeIdentifier == UTType.pdf.identifier ? "doc.richtext" : "tablecells"
        if let icon = UIImage(systemName: symbol)?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal) {
            metadata.iconProvider = NSItemProvider(object: icon)
        }
        return metadata
    }
}

/// iOS 26+: a hard top scroll edge, so scrolled content never reads through the toolbar chip.
struct HardTopScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            content
        }
    }
}
