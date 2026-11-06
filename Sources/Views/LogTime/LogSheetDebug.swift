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
//   note-first states (2.1), each a settled frame (no timers; the reading pipeline is not run):
//       nfInitial | nfTyping | nfRules | nfModel | nfPartialHours | nfPartialKind | nfTwoRentals
//       nfZero | nfZeroNamed (seed "empty") | nfEditHours | nfUndone | nfListening | nfMicIntro
//       nfSwap | nfManual | nfToast (the toast over Today)   (timer review: timerReview)
//   -LHLogScript full|partial|two|swap   types that note into the real sheet, pauses, waits for the
//                            model, then taps Log (the unfold / post-log videos); -LHLogNoLog 1 stops short
//   -LHLogPlacement pane  builds the content for the two-pane right pane (no sheet surface, the header
//                            names the rental shown); the shell still presents it in a sheet
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

    /// `-LHLogPlacement pane`: DEBUG probe of the pane build of the content (package J hosts the real one).
    static var placementOverride: LogTimePlacement? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LHLogPlacement"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1] == "pane" ? .pane : nil
        #else
        return nil
        #endif
    }

    /// The typed capture is the moment before the 600ms read: nothing fills. The note-first
    /// presets are settled frames, so the live reading must not run over them.
    static var holdsReading: Bool { state == "typed" || (state?.hasPrefix("nf") ?? false) }

    /// Presets show the settled state at once: no leave-then-arrive wait.
    static var instantUnfold: Bool { state?.hasPrefix("nf") ?? false }

    /// A scripted run (`-LHLogScript`) plays the real fill motion; presets stay still.
    static var animatesFills: Bool { scriptNote != nil }

    /// The note the scripted run types, by scenario name.
    static var scriptNote: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LHLogScript"), args.indices.contains(i + 1) else { return nil }
        switch args[i + 1] {
        case "full": return "fixed the sink at Pine Cabin, about 2 hours yesterday"
        case "partial": return "met the plumber at Oak St"
        case "two": return "turnover clean at Pine Cabin and Oak St"
        case "swap": return "replaced the water heater at Oak St, 3 hours"
        default: return nil
        }
        #else
        return nil
        #endif
    }

    /// The invalid capture shows the caution line before any typing.
    static var forcesInvalid: Bool { state == "invalid" }

    /// The route the shell opens on launch for `-LHOpenLog`.
    static var launchRoute: LogSheetRoute? {
        if state == nil { return scriptNote == nil ? nil : .log }
        switch state {
        case "timerIdle", "timerRunning": return .timer
        case "timerReview": return .timerReview
        case "nfToast": return nil
        default: return .log
        }
    }

    #if DEBUG
    static let sample = "Fixed the sink at Pine Cabin, 1 hour"
    static let aiSample = "fixed the sink at Oak St with Mike, about 2 hours yesterday"
    static let aiPartialSample = "Fixed the sink, about an hour"
    static let aiTwoRentalsSample = "Fixed the sink at Pine Cabin and mowed at Maple Court, 2 hours"

    /// What a note-first preset sets on the sheet besides the form.
    struct Preset {
        var unfolded = false
        var expanded: LogField?
        var manual = false
        var isReading = false
        var noneFound = false
        var mentioned: [RentalProperty] = []
        var firstRunName: String?
        var listening = false
        var script = false
        var focusNote = false
    }

    enum ModelStep { case confirm, swap }

    @MainActor
    static func apply(to form: inout LogForm, mode: inout LogTimeSheet.Mode, picker: inout LogTimeSheet.Picker?,
                      voiceIntro: inout Bool, saveError: inout String?, preset: inout Preset,
                      properties: [RentalProperty], spouseTracking: Bool,
                      viewModel: AppViewModel, focus: @escaping () -> Void) {
        if scriptNote != nil { preset.script = true }
        guard let state else { return }
        let pine = properties.first { $0.name == "Pine Cabin" } ?? properties.first
        let oak = properties.first { $0.name.hasPrefix("Oak") } ?? properties.dropFirst().first
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-LHFailNextSave") { AppViewModel.debugFailNextWrite = true }
        // The 2.0 states show their rows (the note-first sheet folds them into the details line until a fill).
        if ["filled", "voiceFilled", "saveFailed", "invalid", "keyboard", "notCounted", "quick", "listening"].contains(state) {
            preset.unfolded = true
        }

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

        /// Reads `note` through the real rules, then (optionally) a scripted model answer, as one settled frame.
        func read(_ note: String, model step: ModelStep? = nil) {
            form.note = note
            let request = NoteReadRequest(text: note, properties: properties, spouseTracking: spouseTracking)
            let rules = NoteRules.read(request)
            form.apply(rules, source: .note, spouseTracking: spouseTracking, tier: .rules)
            preset.unfolded = true
            if rules.mentionedPropertyCount >= 2 {
                preset.mentioned = NoteRules.mentionedProperties(normalized: RulesEngine.normalize(note), properties: properties)
            }
            var finalReading = rules
            if let step {
                var answer = rules
                answer.tier = .onDevice
                let first = note.split(separator: ",").first.map(String.init) ?? note
                answer.description = first.prefix(1).uppercased() + first.dropFirst()
                switch step {
                case .confirm: answer.category = rules.category ?? .repairs
                case .swap: answer.category = rules.category == .renovations ? .repairs : .renovations
                }
                form.apply(answer, source: .note, spouseTracking: spouseTracking, tier: .model, late: step == .swap, rulesBaseline: rules)
                finalReading = answer
            }
            preset.noneFound = properties.count > 1 && form.propertyId == nil && finalReading.category == nil && rules.mentionedPropertyCount == 0
        }

        switch state {
        case "nfInitial":
            preset.focusNote = true
        case "nfTyping":
            form.note = "fixed the sink at Pine Cabin, about 2 hours yesterday"
            preset.focusNote = true
        case "nfRules":
            read("fixed the sink at Pine Cabin, about 2 hours yesterday")
            preset.isReading = true
        case "nfModel":
            read("fixed the sink at Pine Cabin, about 2 hours yesterday", model: .confirm)
        case "nfPartialHours":
            read("met the plumber at Oak St", model: .confirm)
        case "nfPartialKind":
            read("walked Oak St with Mike")
        case "nfTwoRentals":
            read("turnover clean at Pine Cabin and Oak St", model: .confirm)
        case "nfZero":
            preset.firstRunName = ""
        case "nfZeroNamed":
            preset.firstRunName = "Pine Cabin"
            read("fixed the sink, 1 hour")
        case "nfEditHours":
            read("fixed the sink at Pine Cabin, about 2 hours yesterday", model: .confirm)
            preset.expanded = .hours
        case "nfUndone":
            read("fixed the sink at Pine Cabin, about 2 hours yesterday", model: .confirm)
            form.undoFill()
        case "nfListening":
            read("Fixed the sink at Pine Cabin, took about an hour")
            preset.listening = true
        case "nfMicIntro":
            voiceIntro = true
        case "nfSwap":
            read("replaced the water heater at Oak St, 3 hours", model: .swap)
        case "nfManual":
            preset.unfolded = true
            preset.manual = true
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
                // After the launch's own profile set-up, so the draft lands under the profile's key.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    LogSheetDebug.seedStoppedDraft(properties: app.properties, elapsed: 3600 + 12 * 60)
                }
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
        if LogSheetDebug.state == "nfToast" {
            AppToastCenter.shared.undoWindow = 600
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                AppToastCenter.shared.show(LogTimeFormat.loggedToast(hours: 2, propertyName: "Pine Cabin"), kind: .success, undo: {})
            }
            return
        }
        guard let route = LogSheetDebug.launchRoute else { return }
        if route == .timerReview { LogSheetDebug.seedStoppedDraft(properties: app.properties) }
        open(route)
    }
}
#endif

#if DEBUG
extension LogTimeSheet {
    /// `-LHLogScript`: types a note into the real sheet (so the real reading pipeline runs), waits
    /// through the pause and the model, then taps Log. For the unfold and post-log videos.
    func runDebugScript() {
        guard let note = LogSheetDebug.scriptNote else { return }
        let taps = !ProcessInfo.processInfo.arguments.contains("-LHLogNoLog")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            noteFocused = true
            try? await Task.sleep(for: .seconds(0.7))
            for character in note {
                form.note += String(character)
                try? await Task.sleep(for: .milliseconds(42))
            }
            try? await Task.sleep(for: .seconds(0.7))
            noteFocused = false
            try? await Task.sleep(for: .seconds(4.2))
            if taps { primaryTapped() }
        }
    }
}
#endif
