import Foundation

// MARK: - DEBUG states for Log time captures and UI tests (compiled out of Release)
//
//   -LHOpenLog <state>   opens the "+" sheet on launch in one state:
//       empty | typed | filled | quick | invalid | keyboard | notCounted | saveFailed
//       voiceFirst | listening | voiceFilled | voiceDenied (pair with -LHVoiceDenied)
//       pickerCategory | pickerProperty | pickerPropertyLimit (seed "limit")
//       timerIdle | timerRunning | timerReview
//       aiNote | aiPartial | aiTwoRentals   types a note that goes through the real note reader; pair with
//                            -LHNoteModel fake|thinking|unavailable (NoteReaderChain)
//   -LHLogSpouse          spouse tracking on (the Who row)
//   -LHTodayTimer running|draft|recovery   Today's timer card states
//   -LHFailNextSave       the next save fails (the surfaced save error)

enum LogSheetDebug {
    static var state: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LHOpenLog"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
        #else
        return nil
        #endif
    }

    /// The typed capture is the moment before the 600ms read: nothing fills.
    static var holdsReading: Bool { state == "typed" }

    /// The invalid capture shows the caution line before any typing.
    static var forcesInvalid: Bool { state == "invalid" }

    /// The route the shell opens on launch for `-LHOpenLog`.
    static var launchRoute: LogSheetRoute? {
        guard let state else { return nil }
        switch state {
        case "timerIdle", "timerRunning": return .timer
        case "timerReview": return .timerReview
        default: return .log
        }
    }

    #if DEBUG
    static let sample = "Fixed the sink at Pine Cabin, 1 hour"
    /// Screenshot hook: `-LHLogNote "<text>"` replaces the sample note (default: the Oak St sink).
    static var aiSample: String {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-LHLogNote"), a.indices.contains(i + 1) { return a[i + 1] }
        return "fixed the sink at Oak St with Mike, about 2 hours yesterday"
    }
    static let aiPartialSample = "Fixed the sink, about an hour"
    static let aiTwoRentalsSample = "Fixed the sink at Pine Cabin and mowed at Maple Court, 2 hours"

    @MainActor
    static func apply(to form: inout LogForm, mode: inout LogTimeSheet.Mode, picker: inout LogTimeSheet.Picker?,
                      voiceIntro: inout Bool, saveError: inout String?, properties: [RentalProperty],
                      viewModel: AppViewModel, focus: @escaping () -> Void) {
        guard let state else { return }
        let pine = properties.first { $0.name == "Pine Cabin" } ?? properties.first
        let oak = properties.first { $0.name.hasPrefix("Oak") } ?? properties.dropFirst().first
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-LHFailNextSave") { AppViewModel.debugFailNextWrite = true }

        func filled() {
            form.note = sample
            form.propertyId = pine?.id
            form.category = .repairs
            form.hours = 1
            if let pine {
                form.apply(ParsedTimeEntry(property: pine, category: .repairs, hours: 1, participant: .selfParticipant,
                                           notes: sample, hoursAreExplicit: true, categoryMatched: true),
                           source: state == "voiceFilled" ? .voice : .note, spouseTracking: false)
            }
        }

        switch state {
        case "typed":
            form.note = sample
        case "aiNote":
            // Not user-set: the read fills over the defaults, as when typed.
            form.note = aiSample
        case "aiPartial":
            form.note = aiPartialSample
        case "aiTwoRentals":
            form.note = aiTwoRentalsSample
        case "filled", "voiceFilled":
            // Defaults first (the remembered category), then the fill, so the caption shows.
            form.propertyId = nil
            form.category = .bookkeeping
            filled()
        case "quick":
            form.setHours(2)
        case "invalid":
            form.note = "Tenant call about the lease renewal"
            form.propertyId = nil
            form.setCategory(.management)
            form.setHours(0.5)
        case "keyboard":
            form.note = "Met the HVAC tech at Oak Street, walked through the duplex and"
            form.setProperty(oak?.id)
            form.setHours(1.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: focus)
        case "notCounted":
            form.note = "Call with the lender about refinancing Pine Cabin"
            form.setProperty(pine?.id)
            form.setCategory(.financing)
        case "saveFailed":
            filled()
            saveError = LogSaveResult.writeFailedMessage
        case "voiceFirst":
            voiceIntro = true
        case "pickerCategory":
            form.setCategory(.repairs)
            picker = .category
        case "pickerProperty", "pickerPropertyLimit":
            form.setProperty(pine?.id)
            picker = .property
        case "timerIdle":
            if viewModel.isTimerRunning { viewModel.cancelTimer() }
            mode = .timerIdle
            form.propertyId = pine?.id
            form.category = .repairs
        case "timerRunning":
            if viewModel.isTimerRunning { viewModel.cancelTimer() }
            if let pine {
                viewModel.restoreTimer(propertyId: pine.id, category: .repairs, startTime: Date().addingTimeInterval(-(3600 + 14 * 60 + 7)))
            }
            mode = .timerRunning
        default:
            break
        }
    }

    /// Seeds a stopped timer (1:14:07 at Pine Cabin) for the review and the Today draft card.
    @MainActor
    static func seedStoppedDraft(properties: [RentalProperty], elapsed: TimeInterval = 4447) {
        guard let pine = properties.first(where: { $0.name == "Pine Cabin" }) ?? properties.first else { return }
        let start = Calendar.current.date(bySettingHour: 10, minute: 25, second: 0, of: Date()) ?? Date()
        StoppedTimerDraftStore.save(StoppedTimerDraft(elapsed: elapsed, propertyId: pine.id, category: .repairs,
                                                      startDate: start, participant: .selfParticipant, notes: ""))
    }
    #endif
}

#if DEBUG
/// Shell-level DEBUG set-up for Log time captures: runs after the launch seeds.
enum LogShellDebug {
    @MainActor
    static func applyIfNeeded(app: AppViewModel, open: @escaping (LogSheetRoute) -> Void) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-LHLogSpouse") { TaxProfileManager.shared.spouseTracking = true }
        if let i = args.firstIndex(of: "-LHTodayTimer"), args.indices.contains(i + 1) {
            StoppedTimerDraftStore.clear()
            if app.isTimerRunning { app.cancelTimer() }
            let pine = app.properties.first { $0.name == "Pine Cabin" } ?? app.properties.first
            switch args[i + 1] {
            case "running":
                if let pine { app.restoreTimer(propertyId: pine.id, category: .repairs, startTime: Date().addingTimeInterval(-42)) }
            case "draft":
                LogSheetDebug.seedStoppedDraft(properties: app.properties, elapsed: 3600 + 12 * 60)
            case "discarded":
                if let pine { app.restoreTimer(propertyId: pine.id, category: .repairs, startTime: Date().addingTimeInterval(-42)) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    guard let start = app.timerStartTime, let id = app.timerPropertyId else { return }
                    app.cancelTimer()
                    AppToastCenter.shared.undoWindow = 60
                    AppToastCenter.shared.show("Timer discarded", kind: .neutral) {
                        app.restoreTimer(propertyId: id, category: .repairs, startTime: start)
                    }
                }
            default: break
            }
        }
        guard let route = LogSheetDebug.launchRoute else { return }
        if route == .timerReview { LogSheetDebug.seedStoppedDraft(properties: app.properties) }
        open(route)
    }
}
#endif
