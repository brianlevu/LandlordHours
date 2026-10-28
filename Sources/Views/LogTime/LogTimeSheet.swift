import SwiftUI
import PhotosUI

// MARK: - "+" Log time and the timer (note-first, v2)
//
// Say it. Check it. Log it. One opaque `.large` sheet (Today dims behind it): the note on top, typed
// or spoken, one quiet details line under it, and a Log button that names what it will do. At the
// first pause in the note the details line unfolds into rows (rental, kind of work, how long, date);
// tapping a row edits it in place. Nothing is saved until Log.
//
// The note is read by NoteReaderChain (rules at the pause → Apple's on-device model → Private Cloud
// Compute; Services/NoteReading). The rules always run; "Read my notes with Apple's model"
// (Settings) only closes the model tiers. Wiring kept from 2.0 and 2.1: VoiceEntryService dictation
// (permission + denied path), the AppViewModel timer + Live Activity, the stopped-timer draft,
// Self/Spouse honouring spouse tracking, the property limit (ProGate), analytics and the iCloud
// push (inside AppViewModel.logTimeEntry).
//
// v2 look (standard §1.20, §1.5, §1.9, §1.13): `LHSheet` chrome on an opaque `backgroundSecondary`
// surface, the note in an `LHField`-spec field, rows are `LHRow.Value`, the stepper is `LHStepper`,
// Me / Spouse is `LHSegmented`, every button is an `LHButton`, and the Log button is the one
// `.primary`, pinned, with Liquid Glass on iOS 26+. Nothing else on the sheet is glass.
//
// This file is the shell: state, set-up, the footer, reading, saving, the timer. The pieces live in
// LogNoteCard, LogDetailsLine, LogDetailRows, LogInlineEditors, LogZeroPropertyView.
//
// Hosting (package J): `placement` is `.sheet` in the compact shell and `.pane` in the right pane
// of the two-pane layout; `rentalShown` is the rental the shelf or the chip is showing (nil on
// "All rentals"), which Log time starts on and names in the pane's header. See `LogTimePlacement`.

struct LogTimeSheet: View {
    let route: LogSheetRoute
    var placement: LogTimePlacement = .sheet
    /// The rental the shell is showing. Log time starts on it (as a default, not a user choice).
    var rentalShown: UUID? = nil
    var onClose: () -> Void

    init(route: LogSheetRoute, placement: LogTimePlacement = .sheet, rentalShown: UUID? = nil,
         onClose: @escaping () -> Void) {
        self.route = route
        self.placement = LogSheetDebug.placementOverride ?? placement
        self.rentalShown = rentalShown
        self.onClose = onClose
    }

    enum Mode: Equatable {
        case log
        case timerIdle
        case timerRunning
        case review(StoppedTimerDraft)
        case recovery(StaleTimerRecovery)

        static func == (a: Mode, b: Mode) -> Bool {
            switch (a, b) {
            case (.log, .log), (.timerIdle, .timerIdle), (.timerRunning, .timerRunning): return true
            case (.review(let x), .review(let y)): return x == y
            case (.recovery(let x), .recovery(let y)): return x.id == y.id
            default: return false
            }
        }
    }

    /// The timer card still picks its rental and kind in a sheet; the Log form edits them in place.
    enum Picker: String, Identifiable { case category, property; var id: String { rawValue } }

    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @ObservedObject var voice = VoiceEntryService.shared
    @ObservedObject var taxProfile = TaxProfileManager.shared

    @State var mode: Mode = .log
    @State var form = LogForm()
    @State var didSetUp = false
    @State var picker: Picker?
    /// The rows are on screen (the details line has unfolded).
    @State var unfolded = false
    /// The row whose editor is open (one at a time).
    @State var expanded: LogField?
    /// "Enter details yourself": no reading for this entry.
    @State var manual = false
    /// Leaving: the old content fades out before the new arrives (never two layouts at once).
    @State var exiting = false
    @State var isReading = false
    @State var readTask: Task<Void, Never>?
    /// Rows lit by the last fill (timber wash).
    @State var flashing: Set<LogField> = []
    @State var noteDirty = false
    @State var noneFound = false
    @State var mentioned: [RentalProperty] = []
    @State var rulesFilledAt = Date()
    @State var usedVoice = false
    @State var showVoiceIntro = false
    @State var showsMissing = false
    @State var photoItems: [PhotosPickerItem] = []
    @State var attachments: [TimeAttachment] = []
    @State var saveError: String?
    @State var isSaving = false
    @State var stepTick = 0
    @State var recents: [LogRecent] = []
    @State var firstRunName = ""
    @State var propertySearch = ""
    @State var paywall: ProPaywallRequest?
    @State var announcement: String?
    @State var openedAt = Date()
    /// Smart-layer slots: empty today, so nothing renders.
    @State var prefills: [LogPrefill] = []
    /// Rules, then Apple's models (one chain per sheet).
    @State var noteReader = NoteReaderChain.live()
    @FocusState var noteFocused: Bool
    @FocusState var nameFocused: Bool
    /// DEBUG capture of the listening state (the simulator has no microphone input).
    @State var debugListening = false
    var isListening: Bool { voice.isRecording || debugListening }

    var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    var spouseTracking: Bool { taxProfile.spouseTracking }
    var properties: [RentalProperty] { viewModel.properties }
    var isAX: Bool { dynamicTypeSize.isAccessibilitySize }
    var isReviewing: Bool {
        switch mode { case .review, .recovery: return true; default: return false }
    }
    var isRecovery: Bool { if case .recovery = mode { return true } else { return false } }
    var isTimer: Bool { mode == .timerIdle || mode == .timerRunning }
    /// No rentals yet: the sheet asks which rental, then creates it with the first entry.
    var isFirstRun: Bool { properties.isEmpty && mode == .log }
    var firstRunNameArg: String? { properties.isEmpty ? firstRunName : nil }

    var body: some View {
        ScrollViewReader { proxy in
            LogSheetChrome(title: title, subtitle: subtitle, onClose: onClose) {
                VStack(alignment: .leading, spacing: 16) {
                    switch mode {
                    case .timerIdle: timerIdle
                    case .timerRunning: timerRunning
                    default: logContent
                    }
                }
            } footer: {
                footerContent
            }
            .onChange(of: expanded) { _, field in
                guard let field else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(AppAnimation.reveal) { proxy.scrollTo(field.rowID, anchor: .center) }
                }
            }
        }
        .background { if placement == .sheet { colors.backgroundSecondary.ignoresSafeArea() } }
        .modifier(LogSheetPresentation(placement: placement))
        .sheet(item: $picker) { kind in
            Group {
                switch kind {
                case .category:
                    LogCategoryPicker(selected: form.category) { picked in
                        withMotion { form.setCategory(picked) }
                        persistReviewDraft()
                    }
                    .presentationDetents([.large])
                case .property:
                    LogPropertyPicker(properties: properties, selected: form.propertyId, onPick: { id in
                        withMotion { form.setProperty(id) }
                        saveError = nil
                    }, onAddProperty: {
                        onClose()
                        NotificationCenter.default.post(name: .switchToPropertiesAndOpenAddProperty, object: nil)
                    })
                    // At AX sizes the rows need the full height (medium otherwise).
                    .presentationDetents(isAX ? [.large] : [.medium, .large])
                }
            }
            .environmentObject(viewModel)
            .presentationBackground(colors.backgroundSecondary)
            .presentationDragIndicator(.visible)
        }
        .proPaywall($paywall)
        .sensoryFeedback(.selection, trigger: stepTick)
        .onAppear(perform: setUp)
        .onDisappear {
            readTask?.cancel()
            if voice.isRecording { voice.finishRecording() }
        }
        .onChange(of: form.note) { _, text in
            noteChanged(text)
            persistReviewDraft()
        }
        .onChange(of: voice.transcript) { _, transcript in
            let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            usedVoice = true
            form.note = cleaned
        }
        .onChange(of: voice.isRecording) { wasRecording, isRecording in
            // On stop, read the note right away (no 600ms wait): rules, then the model.
            if wasRecording, !isRecording { readNote(delay: 0, source: .voice) }
        }
        .onChange(of: viewModel.isTimerRunning) { _, running in
            if !running, mode == .timerRunning { withMotion { mode = .timerIdle } }
        }
        .onChange(of: photoItems) { _, items in
            Task { await loadPhotos(items) }
        }
        .onChange(of: form.propertyId) { _, _ in
            // A rental now chosen ends the "couldn't tell" and "mentions 2 rentals" prompts.
            if form.propertyId != nil { noneFound = false; mentioned = [] }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.sheet")
    }

    // MARK: Set-up

    func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        openedAt = Date()
        voice.refreshPermissionState()
        // The rental the shell is showing is the starting point, not the user's choice: a note can
        // still name another rental.
        form = LogForm.starting(properties: properties, entries: viewModel.timeEntries, rentalShown: rentalShown)
        recents = LogRecents.derive(entries: viewModel.timeEntries, properties: properties)
        switch route {
        case .log:
            mode = .log
        case .timer:
            mode = viewModel.isTimerRunning ? .timerRunning : .timerIdle
        case .timerReview:
            if let draft = StoppedTimerDraftStore.load(), properties.contains(where: { $0.id == draft.propertyId }) {
                beginReview(draft)
            } else {
                mode = viewModel.isTimerRunning ? .timerRunning : .log
            }
        case .recovery(let id):
            if let recovery = viewModel.staleTimerRecoveries.first(where: { $0.id == id }) {
                mode = .recovery(recovery)
                unfolded = true
                form.propertyId = viewModel.staleTimerRecoveryNeedsProperty(recovery) ? (properties.count == 1 ? properties[0].id : nil) : recovery.propertyId
                form.category = recovery.category
                form.hours = LogForm.clampHours(recovery.suggestedHours)
                form.date = recovery.startTime
                form.participant = .selfParticipant
            }
        }
        Analytics.logOpened(mode: analyticsMode, hasRentals: !properties.isEmpty, recentsShown: !recents.isEmpty)
        #if DEBUG
        var preset = LogSheetDebug.Preset()
        LogSheetDebug.apply(to: &form, mode: &mode, picker: &picker, voiceIntro: &showVoiceIntro,
                            saveError: &saveError, preset: &preset, properties: properties, spouseTracking: spouseTracking,
                            viewModel: viewModel, focus: { noteFocused = true })
        unfolded = unfolded || preset.unfolded
        expanded = preset.expanded ?? expanded
        manual = manual || preset.manual
        isReading = preset.isReading
        noneFound = preset.noneFound
        mentioned = preset.mentioned
        if let name = preset.firstRunName { firstRunName = name }
        if ["aiNote", "aiPartial", "aiTwoRentals"].contains(LogSheetDebug.state ?? "") {
            readNote(delay: 0.6, source: .note)
        }
        if preset.script { runDebugScript() }
        if LogSheetDebug.state == "listening" {
            debugListening = true
            form.note = "Fixed the sink at Pine"
        }
        if preset.listening { debugListening = true }
        if let delayed = picker {
            // A sheet can't present on the frame its parent appears.
            picker = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { picker = delayed }
        }
        if LogSheetDebug.state != nil && !preset.focusNote { return }
        #endif
        // Keyboard up, note focused: the note is the one thing the user has in their head.
        guard mode == .log else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if isFirstRun { nameFocused = true } else { noteFocused = true }
        }
    }

    func beginReview(_ draft: StoppedTimerDraft) {
        mode = .review(draft)
        unfolded = true
        form.propertyId = draft.propertyId
        form.category = draft.category
        form.hours = draft.reviewHours
        form.participant = LogParticipantRule.resolve(draft.participant, spouseTracking: spouseTracking)
        form.note = draft.notes
        form.date = draft.startDate
    }

    var analyticsMode: String {
        switch mode {
        case .log: return "log"
        case .timerIdle, .timerRunning: return "timer"
        case .review: return "timer_review"
        case .recovery: return "recovery"
        }
    }

    // MARK: Header (the title and the day; the close button is `LHSheet`'s)

    var title: String {
        switch mode {
        case .log: return isFirstRun ? lt("Log your first hour") : lt("Log time")
        case .timerIdle, .timerRunning: return lt("Timer")
        case .review, .recovery: return lt("Log the timer")
        }
    }

    /// The day the entry is for. In the pane it follows the rental shown, so the pane says where it is.
    var subtitle: String {
        let day = eyebrow
        guard placement == .pane, mode == .log,
              let name = properties.first(where: { $0.id == (rentalShown ?? form.propertyId) })?.name else { return day }
        return lt("\(name) \u{00B7}\u{00A0}\(day)")
    }

    var eyebrow: String {
        switch mode {
        case .review(let draft): return lt("Timer \u{00B7}\u{00A0}\(LogTimeFormat.longDay(draft.startDate))")
        case .recovery(let r): return lt("Timer \u{00B7}\u{00A0}\(LogTimeFormat.longDay(r.startTime))")
        case .log: return LogTimeFormat.eyebrow(form.date)
        default: return LogTimeFormat.eyebrow(Date())
        }
    }

    /// The timer is a different moment (starting work, not recording it): one quiet link at the
    /// foot, only before anything is filled.
    var showsTimerButton: Bool { mode == .log && !unfolded && !isFirstRun && !showVoiceIntro && !isListening }

    // MARK: Log content

    @ViewBuilder var logContent: some View {
        if !prefills.isEmpty && !noteFocused { prefillStrip }
        if isFirstRun { rentalNameField }
        VStack(alignment: .leading, spacing: 4) {
            noteField
            toolsRow
        }
        if showVoiceIntro { voiceIntro.transition(arrive) }
        if voice.permissionDenied && !isReviewing { deniedLine }
        if unfolded {
            rows.id("rows").opacity(exiting ? 0 : 1).transition(arrive)
            if manual { autoFillOff.opacity(exiting ? 0 : 1).transition(arrive) }
            if !isRecovery { receiptRow.opacity(exiting ? 0 : 1).transition(arrive) }
        } else if !showVoiceIntro {
            // The details line and the manual door sit right under the note: the note is focused on
            // open, and with the keyboard up the pinned footer covers everything below the recents.
            // The recents come first: with the keyboard up they are the fastest way to log, and they
            // must stay above the pinned primary (owner's pick 2026-10-27).
            if !recents.isEmpty && !isFirstRun && !isListening { recentsView.opacity(exiting ? 0 : 1).transition(.identity) }
            VStack(alignment: .leading, spacing: 0) {
                detailsLine
                if !doorInToolsRow { enterDetailsButton }
            }
            .opacity(exiting ? 0 : 1)
            .transition(.identity)
        }
        // Only the primary is pinned (§1.20, owner's pick 2026-10-27): the timer link scrolls with the
        // body, after the recents, so the keyboard never pushes the recents under a pinned link.
        if showsTimerButton {
            Button(action: openTimer) { Label(lt("Start a timer instead"), systemImage: "timer") }
                .buttonStyle(LHButton.tertiary)
                .frame(maxWidth: .infinity)
                .accessibilityHint(lt("Starts a timer instead of logging time you already did."))
                .accessibilityIdentifier("log.startTimer")
        }
    }

    /// New content slides in out of the line above it; old content leaves at once.
    var arrive: AnyTransition {
        .asymmetric(insertion: reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -14)), removal: .identity)
    }

    var prefillStrip: some View {
        LogChipFlow(spacing: 8) {
            ForEach(prefills) { item in
                LHChip(item.title, isSelected: false) {}
            }
        }
        .accessibilityIdentifier("log.prefills")
    }

    // MARK: Footer: what's missing, the one quiet link, and the one primary

    @ViewBuilder var footerContent: some View {
        switch mode {
        case .timerIdle: timerIdleFooter
        case .timerRunning: timerRunningFooter
        default: logFooter
        }
    }

    var buttonTitle: String {
        LogTimeFormat.buttonTitle(form: form, properties: properties, firstRunName: firstRunNameArg, ax: isAX)
    }

    var logFooter: some View {
        let label = buttonTitle
        let gap = form.gap(properties: properties, firstRunName: firstRunNameArg)
        return VStack(spacing: 0) {
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(colors.destructive)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("log.saveError")
            } else if showsMissing, gap != nil, let message = form.missingMessage(properties: properties, firstRunName: firstRunNameArg) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(colors.cautionText)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("log.missing")
            }
            if isReviewing {
                Button(lt("Discard"), action: discardReview)
                    .buttonStyle(LHButton.destructiveTertiary)
                    .accessibilityIdentifier("log.discard")
            }
            Button(action: primaryTapped) {
                ZStack {
                    // Only the words change: the old label leaves up, the new one arrives from below.
                    Text(label)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .id(label)
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)),
                                                                           removal: .opacity.combined(with: .offset(y: -8))))
                }
            }
            .buttonStyle(LHButton.primaryGlass)
            .animation(reduceMotion ? AppAnimation.reduced : AppAnimation.feedback, value: label)
            .disabled(isSaving)
            .accessibilityLabel(label.replacingOccurrences(of: "\u{00A0}", with: " "))
            .accessibilityHint(gap == nil ? "" : lt("Opens the missing detail."))
            .accessibilityIdentifier("log.save")
        }
    }

    func openTimer() {
        Analytics.logTimerOpened()
        withMotion { mode = viewModel.isTimerRunning ? .timerRunning : .timerIdle }
    }

    /// The button is never dead: with a gap it opens that editor; otherwise it logs.
    func primaryTapped() {
        if let gap = form.gap(properties: properties, firstRunName: firstRunNameArg) {
            showsMissing = true
            openEditor(for: gap)
            return
        }
        if isReading { Analytics.logTappedWhileReading() }
        cancelReading()
        save()
    }

    func openEditor(for gap: LogGap) {
        func open(_ field: LogField) {
            Task { @MainActor in
                await arriveRows { expanded = field }
                if !unfolded { unfolded = true }
            }
        }
        switch gap {
        case .name: nameFocused = true
        case .rental: open(.property)
        case .kind: open(.category)
        case .hours: open(.hours)
        }
    }

    // MARK: Timer

    var timerIdle: some View {
        VStack(alignment: .leading, spacing: 8) {
            LHRow.Value(lt("Rental"), value: properties.first(where: { $0.id == form.propertyId })?.name ?? lt("Choose")) { picker = .property }
                .accessibilityIdentifier("timer.property")
            LHRow.Value(lt("Kind of work"), value: timerCategory.inboxLabel) { picker = .category }
                .accessibilityIdentifier("timer.category")
            Text("0:00")
                .lhHeroNumberFont()
                .foregroundStyle(colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
                .accessibilityLabel(lt("Timer at zero"))
        }
    }

    var timerIdleFooter: some View {
        VStack(spacing: 0) {
            if form.propertyId == nil {
                Text(lt("Pick a rental to start the timer."))
                    .font(.footnote)
                    .foregroundStyle(colors.cautionText)
                    .padding(.bottom, 4)
            }
            Button(lt("Log time instead")) { withMotion { mode = .log } }
                .buttonStyle(LHButton.tertiary)
                .accessibilityIdentifier("timer.logInstead")
            Button(lt("Start timer"), action: startTimer)
                .buttonStyle(LHButton.primary)
                .disabled(form.propertyId == nil || viewModel.isTimerRunning)
                .accessibilityIdentifier("timer.start")
        }
    }

    var timerCategory: ActivityCategory { form.category ?? .management }

    var timerRunning: some View {
        VStack(alignment: .leading, spacing: 16) {
            LiveTimerCard(
                property: properties.first { $0.id == viewModel.timerPropertyId },
                category: viewModel.timerCategory,
                start: viewModel.timerStartTime ?? Date()
            )
            Text(lt("Keeps running if you close this. You\u{2019}ll see it on your Lock Screen."))
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
        }
    }

    var timerRunningFooter: some View {
        VStack(spacing: 0) {
            Button(lt("Discard"), action: discardRunning)
                .buttonStyle(LHButton.destructiveTertiary)
                .accessibilityIdentifier("timer.discard")
            Button(lt("Stop"), action: stopTimer)
                .buttonStyle(LHButton.primary)
                .accessibilityIdentifier("timer.stop")
        }
    }

    func startTimer() {
        guard let propertyId = form.propertyId else { return }
        viewModel.startTimer(propertyId: propertyId, category: timerCategory)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withMotion { mode = .timerRunning }
    }

    func stopTimer() {
        guard let draft = viewModel.stopTimerIntoDraft() else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withMotion { beginReview(draft) }
    }

    func discardRunning() {
        guard let propertyId = viewModel.timerPropertyId, let start = viewModel.timerStartTime else { return }
        let category = viewModel.timerCategory
        viewModel.cancelTimer()
        onClose()
        AppToastCenter.shared.show(lt("Timer discarded"), kind: .neutral) { [weak viewModel = viewModel] in
            viewModel?.restoreTimer(propertyId: propertyId, category: category, startTime: start)
        }
    }

    func discardReview() {
        switch mode {
        case .review(var draft):
            draft.notes = form.note
            StoppedTimerDraftStore.clear()
            onClose()
            AppToastCenter.shared.show(lt("Timer discarded"), kind: .neutral) { StoppedTimerDraftStore.save(draft) }
        case .recovery(let recovery):
            viewModel.discardRecoveredStaleTimer(id: recovery.id)
            onClose()
            AppToastCenter.shared.show(lt("Timer discarded"), kind: .neutral)
        default: break
        }
    }

    /// The note the user is writing for a stopped timer survives closing the sheet.
    func persistReviewDraft() {
        guard case .review(var draft) = mode else { return }
        draft.notes = form.note
        draft.participant = form.participant
        StoppedTimerDraftStore.save(draft)
    }

    var reviewCaption: String? {
        switch mode {
        case .review(let draft):
            if TimerReviewMath.wasCapped(elapsed: draft.elapsed) {
                return lt("Timer ran over 24h. We stopped counting at 24h, so check the hours.")
            }
            return TimerReviewMath.ranCaption(elapsed: draft.elapsed)
        case .recovery(let r):
            return r.wasCapped ? lt("\(r.ranLabel). We stopped counting at 24h, so check the hours.") : lt("Timer \(r.ranLabel.lowercased())")
        default: return nil
        }
    }

    // MARK: Note reading

    func noteChanged(_ text: String) {
        guard mode == .log, !manual else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { usedVoice = false }
        // Editing the note after a fill starts a new fill; the old caption goes away until it lands.
        if form.canUndoFill || isReading || noneFound {
            withAnimation(AppAnimation.quick) { noteDirty = true; noneFound = false }
        }
        // While talking, the rules read on every pause; the model reads when the talking stops.
        readNote(delay: 0.6, source: usedVoice ? .voice : .note, rulesOnly: isListening)
    }

    func cancelReading() {
        readTask?.cancel()
        withAnimation(AppAnimation.quick) { isReading = false }
    }

    /// After a 600ms pause the note is read: the rules fill at once (the details line unfolds into
    /// rows), then Apple's on-device model (and Private Cloud Compute when the phone's model can't
    /// answer) refine the fields while "Reading your note" shows. Never a field the user set;
    /// nothing is saved until Log.
    func readNote(delay: Double, source: LogFillSource, rulesOnly: Bool = false) {
        readTask?.cancel()
        let text = form.trimmedNote
        guard text.count >= 6, mode == .log, !manual, !LogSheetDebug.holdsReading else {
            if !LogSheetDebug.holdsReading { isReading = false }
            noteDirty = false
            return
        }
        let request = NoteReadRequest(text: text, properties: properties, spouseTracking: spouseTracking)
        let chain = noteReader
        readTask = Task { @MainActor in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, form.trimmedNote == text else { return }
            let rules = chain.rules(request)
            await fill(rules, source: source, tier: .rules, rulesBaseline: nil)
            guard !Task.isCancelled, form.trimmedNote == text else { return }
            guard !rulesOnly, chain.hasModel else {
                finishRead(rules)
                return
            }
            withAnimation(AppAnimation.reveal) { isReading = true }
            let outcome = await chain.read(request, rules: rules) { refined in
                guard !Task.isCancelled, form.trimmedNote == text else { return }
                Task { @MainActor in await fill(refined, source: source, tier: .model, rulesBaseline: rules) }
            }
            guard !Task.isCancelled, form.trimmedNote == text else { return }
            withMotion { isReading = false }
            await fill(outcome.reading, source: source, tier: .model, rulesBaseline: rules)
            if outcome.onDevice == .failed || outcome.onDevice == .timedOut || outcome.pcc == .failed || outcome.pcc == .timedOut {
                Analytics.readFailed(reason: outcome.pcc == .notNeeded ? outcome.onDevice : outcome.pcc)
            }
            finishRead(outcome.reading)
        }
    }

    /// The read is over: settle the caption, and if nothing told which rental on an account with
    /// several, say so.
    func finishRead(_ reading: NoteReading) {
        withAnimation(AppAnimation.reveal) {
            noteDirty = false
            isReading = false
            noneFound = properties.count > 1 && form.propertyId == nil && reading.category == nil
                && reading.mentionedPropertyCount == 0 && !form.isUserSet(.property)
            if reading.mentionedPropertyCount >= 2 { mentioned = mentionedProperties(for: form.trimmedNote) }
        }
    }

    func mentionedProperties(for text: String) -> [RentalProperty] {
        NoteRules.mentionedProperties(normalized: RulesEngine.normalize(text), properties: properties)
    }

    /// Writes one reading into the form. The first fill unfolds the details line into rows.
    func fill(_ reading: NoteReading, source: LogFillSource, tier: LogFillTier, rulesBaseline: NoteReading?) async {
        let late = tier == .model && Date().timeIntervalSince(rulesFilledAt) > 1.5
        var wrote = Set<LogField>()
        await arriveRows {
            noteDirty = false
            expanded = nil
            wrote = form.apply(reading, source: source, spouseTracking: spouseTracking, tier: tier, late: late,
                               rulesBaseline: rulesBaseline)
            if tier == .rules { rulesFilledAt = Date() }
        }
        if !unfolded { return }
        if !wrote.isEmpty {
            pulse(wrote)
            announce(wrote, tier: tier)
            Analytics.noteFilled(tier: tier, fields: wrote.count, voice: source == .voice)
        }
        if !form.updatedAfterSeen.isEmpty { scheduleUpdateExpiry() }
        if !form.updatedAfterSeen.isEmpty, tier == .model { Analytics.fillUpdatedAfterSeen(fields: form.updatedAfterSeen.count) }
    }

    func scheduleUpdateExpiry() {
        let fields = Array(form.updatedAfterSeen.keys)
        guard !LogSheetDebug.holdsReading, LogSheetDebug.state == nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            withMotion { for field in fields { form.dismissUpdate(field) } }
        }
    }

    /// The timber wash on each filled row: 0 → 16% → 0 over 300 + 300 ms, one light haptic per batch.
    func pulse(_ fields: Set<LogField>) {
        guard !fields.isEmpty, LogSheetDebug.state == nil || LogSheetDebug.animatesFills else { return }
        if !reduceMotion { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        withAnimation(AppAnimation.standard) { flashing.formUnion(fields) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(AppAnimation.standard) { flashing.subtract(fields) }
        }
    }

    /// One batched VoiceOver announcement per fill; a model refinement says "Updated" on its own.
    func announce(_ fields: Set<LogField>, tier: LogFillTier) {
        let names = fields.sorted { $0.order < $1.order }.map(\.spokenName)
        guard !names.isEmpty else { return }
        let list = ListFormatter.localizedString(byJoining: names)
        let message = (tier == .model && form.updatedAfterSeen.keys.contains(where: fields.contains))
            ? lt("Updated \(list) from your note.")
            : (form.fillSource == .voice ? lt("Filled \(list) from what you said.") : lt("Filled \(list) from your note."))
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    /// Leave, then arrive: what is on screen fades out (130 ms ease-in), then the new state comes in
    /// (ease-out, one transaction). Old and new content are never on screen together. After the
    /// rows exist, a change is just a spring. Reduce Motion: a 200 ms crossfade.
    func arriveRows(_ body: @escaping () -> Void) async {
        if unfolded || LogSheetDebug.instantUnfold {
            withMotion { body(); unfolded = true }
            return
        }
        if reduceMotion {
            withAnimation(AppAnimation.reduced) { unfolded = true; body() }
            return
        }
        withAnimation(AppAnimation.quick) { exiting = true }
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard !Task.isCancelled else { withAnimation(AppAnimation.quick) { exiting = false }; return }
        withAnimation(AppAnimation.flow) { exiting = false; unfolded = true; body() }
    }

    // MARK: Actions on the form

    func undoFill() {
        readTask?.cancel()
        Analytics.fillUndone()
        withMotion {
            form.undoFill()
            isReading = false
            noneFound = false
            mentioned = []
            noteDirty = false
        }
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
        noteFocused = true
    }

    func undoUpdate(_ field: LogField) {
        withMotion { form.undoUpdate(field) }
    }

    func edited(_ field: LogField) {
        Analytics.fieldEdited(field: field)
        persistReviewDraft()
        saveError = nil
    }

    func pick(property id: UUID) {
        withMotion { form.setProperty(id); expanded = nil; mentioned = []; noneFound = false }
        edited(.property)
    }

    func pick(category: ActivityCategory) {
        withMotion { form.setCategory(category); expanded = nil }
        edited(.category)
    }

    func set(hours: Double, collapse: Bool) {
        withMotion { form.setHours(hours); if collapse { expanded = nil } }
        stepTick += 1
        edited(.hours)
    }

    func set(date: Date) {
        withMotion { form.setDate(date); expanded = nil }
        edited(.date)
    }

    func useRecent(_ recent: LogRecent) {
        Analytics.recentUsed()
        Task { @MainActor in
            await arriveRows {
                form.applyRecent(recent)
                expanded = nil
            }
        }
    }

    func enterManual() {
        readTask?.cancel()
        Analytics.manualPathOpened()
        noteFocused = false   // manual entry is the rows, not the note: the keyboard would cover their editors
        Task { @MainActor in
            await arriveRows {
                manual = true
                isReading = false
                noneFound = false
            }
        }
    }

    func turnAutoFillOn() {
        withMotion { manual = false }
        if form.trimmedNote.count >= 6 { readNote(delay: 0, source: usedVoice ? .voice : .note) }
    }

    func toggle(_ field: LogField) {
        withMotion { expanded = expanded == field ? nil : field }
    }

    // MARK: Voice

    func micTapped() {
        if voice.isRecording {
            voice.finishRecording()
            return
        }
        if debugListening {
            debugListening = false
            return
        }
        if voice.permissionDenied {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            noteFocused = false   // the keyboard would sit over the "Open Settings" line
            return
        }
        if voice.needsPermissionPrompt && !LogVoiceIntro.seen {
            withMotion { showVoiceIntro = true }
            return
        }
        startListening()
    }

    func startListening() {
        noteFocused = false
        Task { await voice.startRecording(contextualStrings: voiceContextualStrings) }
    }

    var voiceContextualStrings: [String] {
        var phrases = properties.flatMap { [$0.name, $0.address] + $0.aliases }
        phrases += ActivityCategory.allCases.flatMap { [$0.rawValue, $0.inboxLabel] }
        phrases += ["spouse", "tenant", "receipt", "plumber", "showing"]
        let unique = Array(Set(phrases.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }))
        return Array(unique.prefix(80))
    }

    // MARK: Save

    func save() {
        guard form.canLog(properties: properties, firstRunName: firstRunNameArg), let category = form.category, !isSaving else { return }
        isSaving = true
        saveError = nil
        showsMissing = false
        defer { isSaving = false }
        noteFocused = false
        nameFocused = false
        let participant = form.participantToSave(spouseTracking: spouseTracking)
        let hours = form.hours

        // The first log creates the rental with the entry, in one save.
        if isFirstRun {
            let name = FirstPropertyDraft(name: firstRunName).trimmedName
            let result = viewModel.logFirstEntry(propertyName: name, participant: participant, category: category, hours: hours,
                                                 date: form.date, notes: form.trimmedNote, attachments: attachments,
                                                 source: usedVoice ? .voice : .manual, recordDescription: form.descriptionToSave)
            switch result {
            case .failed(let message): fail(message)
            case .saved(let id):
                Analytics.propertyCreatedInline()
                succeed(LogTimeFormat.addedAndLoggedToast(hours: hours, propertyName: name)) { [weak viewModel = viewModel] in
                    guard let viewModel else { return }
                    if let entry = viewModel.timeEntries.first(where: { $0.id == id }) {
                        let propertyId = entry.propertyId
                        viewModel.deleteTimeEntry(entry)
                        if let property = viewModel.properties.first(where: { $0.id == propertyId }) { viewModel.deleteProperty(property) }
                    }
                }
            }
            return
        }

        guard let propertyId = form.propertyId else { return }
        let propertyName = properties.first { $0.id == propertyId }?.name

        switch mode {
        case .recovery(let recovery):
            let saved = viewModel.saveRecoveredStaleTimer(id: recovery.id, hours: hours, propertyId: propertyId,
                                                          notes: form.trimmedNote.isEmpty ? nil : form.trimmedNote)
            guard saved else { return fail(viewModel.persistenceError ?? LogSaveResult.writeFailedMessage) }
            succeed(LogTimeFormat.loggedToast(hours: hours, propertyName: propertyName), undo: nil)
        case .review(let draft):
            let result = viewModel.logTimeEntry(propertyId: propertyId, participant: participant, category: category,
                                                hours: hours, date: draft.startDate, notes: form.trimmedNote,
                                                attachments: attachments, source: .timer)
            switch result {
            case .failed(let message): fail(message)
            case .saved(let id):
                StoppedTimerDraftStore.clear()
                var kept = draft
                kept.notes = form.note
                succeed(LogTimeFormat.loggedToast(hours: hours, propertyName: propertyName)) { [weak viewModel = viewModel] in
                    if let entry = viewModel?.timeEntries.first(where: { $0.id == id }) { viewModel?.deleteTimeEntry(entry) }
                    StoppedTimerDraftStore.save(kept)
                }
            }
        default:
            let result = viewModel.logTimeEntry(propertyId: propertyId, participant: participant, category: category,
                                                hours: hours, date: form.date, notes: form.trimmedNote,
                                                attachments: attachments, source: usedVoice ? .voice : .manual,
                                                recordDescription: form.descriptionToSave)
            switch result {
            case .failed(let message): fail(message)
            case .saved(let id):
                succeed(LogTimeFormat.loggedToast(hours: hours, propertyName: propertyName)) { [weak viewModel = viewModel] in
                    if let entry = viewModel?.timeEntries.first(where: { $0.id == id }) { viewModel?.deleteTimeEntry(entry) }
                }
            }
        }
    }

    func fail(_ message: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        withMotion { saveError = message }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    func succeed(_ message: String, undo: (() -> Void)?) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onClose()
        AppToastCenter.shared.show(message, kind: .success, undo: undo)
    }

    func loadPhotos(_ items: [PhotosPickerItem]) async {
        var loaded: [TimeAttachment] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loaded.append(TimeAttachment(filename: "photo_\(UUID().uuidString).jpg", data: data, mimeType: "image/jpeg"))
            }
        }
        attachments = loaded
    }

    func withMotion(_ body: () -> Void) {
        withAnimation(reduceMotion ? AppAnimation.reduced : AppAnimation.flow, body)
    }
}

// MARK: - Field helpers

extension LogField {
    /// The scroll anchor of the field's row.
    var rowID: String { "log.row.\(self)" }

    /// Row order on the sheet.
    var order: Int {
        switch self {
        case .property: return 0
        case .category: return 1
        case .hours: return 2
        case .date: return 3
        case .participant: return 4
        case .description: return 5
        }
    }

    /// For the VoiceOver announcement ("Filled rental, kind of work and how long from your note.").
    var spokenName: String {
        switch self {
        case .property: return lt("rental")
        case .category: return lt("kind of work")
        case .hours: return lt("how long")
        case .date: return lt("date")
        case .participant: return lt("who")
        case .description: return lt("the record")
        }
    }
}

// MARK: - Presentation

/// The compact shell presents Log time as an opaque `.large` sheet (§1.20 "focused-entry sheets"):
/// the system pushes Today back and dims it, the surface is `backgroundSecondary`, never glass or
/// material. In the pane the host owns the surface, so nothing is applied.
private struct LogSheetPresentation: ViewModifier {
    let placement: LogTimePlacement

    func body(content: Content) -> some View {
        if placement == .sheet {
            content.lhSheetPresentation(.focused)
        } else {
            content
        }
    }
}
