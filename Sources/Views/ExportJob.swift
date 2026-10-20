import SwiftUI
import LucideIcons

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

    static let failureMessage = "Could not create the report. Please try again."

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
        let id = UUID()
        runID = id
        reportFingerprint = fingerprint
        bannerDismissed = false
        state = .generating(year: year)
        task = Task { [weak self, writer] in
            let result = await writer(report, year)
            guard let self, self.runID == id else { return }
            // Seen in the open sheet already: no banner for it after the sheet closes.
            self.bannerDismissed = self.isSheetVisible
            switch result {
            case .success(let files):
                self.state = .ready(files, year: year)
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

    /// Sign-out / profile switch: the files belong to the outgoing profile.
    func reset() {
        task?.cancel()
        runID = UUID()
        reportFingerprint = nil
        state = .idle
        bannerDismissed = false
        isSheetVisible = false
    }
}

/// "Your report is ready · Share". Floats above the tab bar; tap to open the share sheet. The
/// failed variant says the report couldn't be made and to try again from Export.
struct ExportReadyBanner: View {
    var kind: ExportJob.Banner = .ready
    var onOpen: () -> Void
    var onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 12) {
            if kind == .ready {
                Button(action: onOpen) {
                    HStack(spacing: 12) {
                        LucideIcon(image: Lucide.fileCheck, size: 18)
                            .foregroundStyle(colors.positive)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(colors.positiveSurface))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Your report is ready")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(colors.textPrimary)
                            Text("PDF and spreadsheet")
                                .font(.footnote)
                                .foregroundStyle(colors.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Text("Share")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(colors.action)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.lhPressable)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your report is ready. Share the PDF and spreadsheet")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("export.readyBanner")
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.caution)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(colors.cautionSurface))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Couldn't create your report")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(colors.textPrimary)
                        Text("Try again from Export.")
                            .font(.footnote)
                            .foregroundStyle(colors.textSecondary)
                    }
                    Spacer(minLength: 8)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("export.failedBanner")
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.lhPressable)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("export.readyBanner.close")
        }
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .frame(minHeight: 60)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(colors.backgroundSecondary)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.12), radius: 16, y: 4)
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(colors.border.opacity(0.6), lineWidth: 1))
        .onAppear {
            UIAccessibility.post(notification: .announcement,
                                 argument: kind == .ready ? "Your report is ready" : "Couldn't create your report")
        }
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
