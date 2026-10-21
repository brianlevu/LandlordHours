import SwiftUI
import PhotosUI

// MARK: - "+" Log time and the timer (redesign-specs.md §3; approved sandbox S2Log.swift r4)
//
// One `.large` sheet covers the tab bar, so the tab bar can never hide the field or the keyboard.
// It moves between Log, the timer (idle / running) and the timer's review in place.
// The note is read by NoteReaderChain (rules → Apple's on-device model → Private Cloud Compute;
// Services/NoteReading). Wiring kept from 1.x TimeLogView: VoiceEntryService dictation
// (permission + denied path), the AppViewModel timer + Live Activity, the stopped-timer draft,
// Self/Spouse honouring spouse tracking, the property limit (ProGate), analytics (inside
// AppViewModel.logTimeEntry) and the iCloud push (saveData path).

struct LogTimeSheet: View {
    let route: LogSheetRoute
    var onClose: () -> Void

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

    enum Picker: String, Identifiable { case category, property; var id: String { rawValue } }

    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var voice = VoiceEntryService.shared
    @ObservedObject private var taxProfile = TaxProfileManager.shared

    @State private var mode: Mode = .log
    @State private var form = LogForm()
    @State private var didSetUp = false
    @State private var picker: Picker?
    @State private var isReading = false
    @State private var readTask: Task<Void, Never>?
    @State private var flash = 0.0
    @State private var usedVoice = false
    @State private var showVoiceIntro = false
    @State private var showDatePicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var attachments: [TimeAttachment] = []
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var stepTick = 0
    /// Smart-layer slots: empty today, so nothing renders.
    @State private var prefills: [LogPrefill] = []
    /// Rules, then Apple's models (one chain per sheet).
    @State private var noteReader = NoteReaderChain.live()
    @FocusState private var noteFocused: Bool
    /// DEBUG capture of the listening state (the simulator has no microphone input).
    @State private var debugListening = false
    private var isListening: Bool { voice.isRecording || debugListening }
    /// Room under the live words for the "Listening… tap to stop" line.
    @ScaledMetric(relativeTo: .footnote) private var listeningInset: CGFloat = 24

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var spouseTracking: Bool { taxProfile.spouseTracking }
    private var properties: [RentalProperty] { viewModel.properties }
    private var isAX: Bool { dynamicTypeSize.isAccessibilitySize }
    private var isReviewing: Bool {
        switch mode { case .review, .recovery: return true; default: return false }
    }
    private var isTimer: Bool { mode == .timerIdle || mode == .timerRunning }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                switch mode {
                case .timerIdle: timerIdle
                case .timerRunning: timerRunning
                default: logContent
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background(colors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isTimer && footerIsPinned { footer.transition(.opacity) }
        }
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
                    // At AX sizes the rows need the full height (medium otherwise, as approved).
                    .presentationDetents(isAX ? [.large] : [.medium, .large])
                }
            }
            .environmentObject(viewModel)
            .presentationBackground(colors.background)
            .presentationDragIndicator(.hidden)
        }
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
            // On stop, read the note right away (no 600ms wait).
            if wasRecording, !isRecording { readNote(delay: 0, source: .voice) }
        }
        .onChange(of: viewModel.isTimerRunning) { _, running in
            if !running, mode == .timerRunning { withMotion { mode = .timerIdle } }
        }
        .onChange(of: photoItems) { _, items in
            Task { await loadPhotos(items) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.sheet")
    }

    // MARK: Set-up

    private func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        voice.refreshPermissionState()
        form = LogForm.starting(properties: properties, entries: viewModel.timeEntries)
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
                form.propertyId = viewModel.staleTimerRecoveryNeedsProperty(recovery) ? (properties.count == 1 ? properties[0].id : nil) : recovery.propertyId
                form.category = recovery.category
                form.hours = LogForm.clampHours(recovery.suggestedHours)
                form.date = recovery.startTime
                form.participant = .selfParticipant
            }
        }
        #if DEBUG
        LogSheetDebug.apply(to: &form, mode: &mode, picker: &picker, voiceIntro: &showVoiceIntro,
                            saveError: &saveError, properties: properties, viewModel: viewModel, focus: { noteFocused = true })
        if ["aiNote", "aiPartial", "aiTwoRentals"].contains(LogSheetDebug.state ?? "") {
            readNote(delay: 0.6, source: .note)
        }
        if LogSheetDebug.state == "listening" {
            debugListening = true
            form.note = "Fixed the sink at Pine"
        }
        if let delayed = picker {
            // A sheet can't present on the frame its parent appears.
            picker = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { picker = delayed }
        }
        #endif
    }

    private func beginReview(_ draft: StoppedTimerDraft) {
        mode = .review(draft)
        form.propertyId = draft.propertyId
        form.category = draft.category
        form.hours = draft.reviewHours
        form.participant = LogParticipantRule.resolve(draft.participant, spouseTracking: spouseTracking)
        form.note = draft.notes
        form.date = draft.startDate
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.3)
                    .foregroundStyle(colors.textSecondary)
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("log.title")
            }
            Spacer(minLength: 8)
            LogSheetCloseButton { onClose() }
        }
    }

    private var eyebrow: String {
        switch mode {
        case .review(let draft): return "Timer\(LogTimeFormat.dot)\(InboxFormat.longDay(draft.startDate))"
        case .recovery(let r): return "Timer\(LogTimeFormat.dot)\(InboxFormat.longDay(r.startTime))"
        default: return LogTimeFormat.eyebrow(Date())
        }
    }

    private var title: String {
        switch mode {
        case .log: return "Log time"
        case .timerIdle, .timerRunning: return "Timer"
        case .review, .recovery: return "Log the timer"
        }
    }

    // MARK: Log

    @ViewBuilder private var logContent: some View {
        if !prefills.isEmpty && !noteFocused { prefillStrip }
        noteField
        if showVoiceIntro { voiceIntro }
        if voice.permissionDenied && !isReviewing { deniedLine }
        captionSlot
        LogHoursStepper(hours: Binding(get: { form.hours }, set: { form.setHours($0); persistReviewDraft() }),
                        flash: form.filled.contains(.hours) ? flash : 0,
                        stepTick: $stepTick)
        rows
        if !footerIsPinned { footer.padding(.horizontal, -20) }
    }

    private var prefillStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(prefills) { item in
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(colors.backgroundSecondary))
                        .overlay(Capsule().strokeBorder(colors.border, lineWidth: 0.5))
                }
            }
        }
        .accessibilityIdentifier("log.prefills")
    }

    private var notePlaceholder: String {
        isReviewing ? "What did you work on?" : "What did you do? Try \u{201C}fixed the sink at Pine Cabin, 1 hour\u{201D}"
    }

    private var noteField: some View {
        ZStack(alignment: .topLeading) {
            if form.note.isEmpty {
                Text(notePlaceholder)
                    .font(.body)
                    .foregroundStyle(colors.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .padding(.trailing, 40)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextField("", text: $form.note, axis: .vertical)
                .lineLimit(3...6)
                .font(.body)
                .foregroundStyle(colors.textPrimary)
                .tint(colors.action)
                .focused($noteFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .padding(.trailing, 44)
                .padding(.bottom, isListening ? listeningInset : 0)
                .accessibilityLabel("Note")
                .accessibilityHint(notePlaceholder)
                .accessibilityIdentifier("log.note")
        }
        .frame(minHeight: 104, alignment: .topLeading)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(noteFocused || isListening ? colors.action.opacity(0.5) : colors.border, lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) { micButton.padding(6) }
        .overlay(alignment: .bottomLeading) {
            if isListening {
                Text("Listening\u{2026} tap to stop")
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 16)
                    .padding(.trailing, 56)
                    .padding(.bottom, 14)
                    .accessibilityIdentifier("log.listening")
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { noteFocused = true }
    }

    private var micButton: some View {
        let denied = voice.permissionDenied
        return Button(action: micTapped) {
            ZStack {
                if isListening {
                    LogMicLevelRing(level: voice.inputLevel).frame(width: 46, height: 46)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(colors.onAction)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.onAction)
                }
            }
            .frame(width: 36, height: 36)
            .background(Circle().fill(colors.action))
            .opacity(denied ? 0.4 : 1)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(isListening ? "Stop listening" : "Talk instead of type")
        .accessibilityHint(denied ? "Microphone is off in Settings" : "")
        .accessibilityIdentifier("log.mic")
    }

    private var voiceIntro: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(colors.action)
                .frame(width: 36, height: 36)
                .background(Circle().fill(colors.actionSurface))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text("Talk like you\u{2019}d tell a friend. We\u{2019}ll fill the rest.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Start talking") {
                    LogVoiceIntro.markSeen()
                    withMotion { showVoiceIntro = false }
                    startListening()
                }
                .buttonStyle(PropertyTintedButtonStyle())
                .accessibilityIdentifier("log.voice.start")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.voice.intro")
    }

    private var deniedLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Turn on the microphone in Settings to talk instead of type.")
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.action)
            .frame(minHeight: 44)
            .accessibilityIdentifier("log.voice.openSettings")
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.voice.denied")
    }

    /// The line under the note: "Reading your note", "Filled from your note  Undo", or the
    /// timer's run time. Reserved by content, never by blank space.
    @ViewBuilder private var captionSlot: some View {
        if isReading {
            HStack(spacing: 8) {
                DraftingLoader(sketch: .document, subject: "your note", lineWidth: 1.5)
                    .frame(height: 18)
                Text("Reading your note")
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                PlaceholderBar(width: 64, height: 10)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("log.reading")
        } else if let source = form.fillSource, form.canUndoFill {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(colors.timberInk)
                    .accessibilityHidden(true)
                Text(source.caption)
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Undo") {
                    withMotion { form.undoFill() }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(colors.action)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Undo the fill")
                .accessibilityIdentifier("log.fill.undo")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .transition(.opacity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("log.fill.caption")
        } else if let reviewCaption {
            Text(reviewCaption)
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .accessibilityIdentifier("log.timer.ran")
        }
    }

    private var reviewCaption: String? {
        switch mode {
        case .review(let draft):
            if TimerReviewMath.wasCapped(elapsed: draft.elapsed) {
                return "Timer ran over 24h. We stopped counting at 24h, so check the hours."
            }
            return TimerReviewMath.ranCaption(elapsed: draft.elapsed)
        case .recovery(let r):
            return r.wasCapped ? "\(r.ranLabel). We stopped counting at 24h, so check the hours." : "Timer \(r.ranLabel.lowercased())"
        default: return nil
        }
    }

    // MARK: Rows

    private var rows: some View {
        VStack(spacing: 0) {
            valueRow("Property", flashing: form.filled.contains(.property), identifier: "log.property") {
                picker = .property
            } value: {
                if let property = properties.first(where: { $0.id == form.propertyId }) {
                    HStack(spacing: 8) {
                        PropertySeal(property, in: properties, size: 24)
                        Text(property.name)
                            .foregroundStyle(colors.textPrimary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                    }
                } else if isReading {
                    PlaceholderBar(width: 96, height: 14)
                } else {
                    Text("Choose").foregroundStyle(saveError != nil || showsMissing ? colors.caution : colors.action)
                }
            }
            if let hint = form.propertyHint, form.propertyId == nil {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "info.circle").accessibilityHidden(true)
                    Text(hint).fixedSize(horizontal: false, vertical: true)
                }
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("log.propertyHint")
            }
            if LogParticipantRule.showsPicker(spouseTracking: spouseTracking), !isRecovery {
                divider
                staticRow("Who", flashing: form.filled.contains(.participant)) {
                    LogWhoPicker(participant: Binding(get: { form.participant }, set: { form.setParticipant($0); persistReviewDraft() }))
                }
            }
            divider
            valueRow("Category", flashing: form.filled.contains(.category), identifier: "log.category") {
                picker = .category
            } value: {
                if let category = form.category {
                    HStack(spacing: 8) {
                        CategoryToolTile(category: category, size: 24)
                        VStack(alignment: isAX ? .leading : .trailing, spacing: 0) {
                            Text(category.inboxLabel).foregroundStyle(colors.textPrimary)
                            if form.categoryIsRemembered && !isReviewing {
                                Text("Last used").font(.caption).foregroundStyle(colors.textSecondary)
                            }
                        }
                    }
                } else if isReading {
                    PlaceholderBar(width: 80, height: 14)
                } else {
                    Text("Choose").foregroundStyle(colors.action)
                }
            }
            if !form.countsTowardHours, let category = form.category {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "info.circle").accessibilityHidden(true)
                    Text("\(category.inboxLabel) doesn\u{2019}t count toward your hours.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("log.notCounted")
            }
            if form.recordDescription != nil {
                // Smart-layer slot: the fact-checked sentence for the record from Apple's model
                // (hidden until it exists). Editable in place; the note stays the user's words.
                divider
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description for your record").font(.subheadline).foregroundStyle(colors.textSecondary)
                    TextField("", text: Binding(get: { form.recordDescription ?? "" }, set: { form.setDescription($0) }), axis: .vertical)
                        .lineLimit(1...3)
                        .foregroundStyle(colors.textPrimary)
                        .tint(colors.action)
                        .accessibilityLabel("Description for your record")
                        .accessibilityIdentifier("log.description.field")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(colors.timber.opacity(form.filled.contains(.description) ? flash : 0))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("log.description")
            }
            divider
            valueRow("Date", flashing: form.filled.contains(.date), identifier: "log.date") {
                withMotion { showDatePicker.toggle() }
            } value: {
                Text(LogTimeFormat.dateRow(form.date)).foregroundStyle(colors.textPrimary)
            }
            if showDatePicker {
                DatePicker("Date", selection: Binding(get: { form.date }, set: { form.setDate($0) }), in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(colors.action)
                    .labelsHidden()
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("log.datePicker")
            }
            if !isRecovery {
                divider
                PhotosPicker(selection: $photoItems, maxSelectionCount: 3, matching: .images) {
                    HStack(spacing: 10) {
                        Image(systemName: attachments.isEmpty ? "camera" : "checkmark.circle.fill")
                            .foregroundStyle(attachments.isEmpty ? colors.action : colors.positive)
                            .accessibilityHidden(true)
                        Text(attachments.isEmpty ? "Add a receipt photo" : (attachments.count == 1 ? "1 photo added" : "\(attachments.count) photos added"))
                            .foregroundStyle(attachments.isEmpty ? colors.action : colors.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("log.receipt")
            }
        }
        .font(.body)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var isRecovery: Bool { if case .recovery = mode { return true } else { return false } }

    private var divider: some View {
        Rectangle().fill(colors.border.opacity(0.7)).frame(height: 0.5).padding(.leading, 16)
    }

    private var rowStack: AnyLayout {
        isAX ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))
    }

    private func valueRow<V: View>(_ label: String, flashing: Bool, identifier: String, action: @escaping () -> Void,
                                   @ViewBuilder value: () -> V) -> some View {
        Button(action: action) {
            rowStack {
                Text(label).foregroundStyle(isAX ? colors.textSecondary : colors.textPrimary)
                if !isAX { Spacer(minLength: 12) }
                HStack(spacing: 6) {
                    value()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, isAX ? 10 : 6)
            .frame(minHeight: 52)
            .background(colors.timber.opacity(flashing ? flash : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.lhPressable)
        .accessibilityIdentifier(identifier)
    }

    private func staticRow<V: View>(_ label: String, flashing: Bool, @ViewBuilder value: () -> V) -> some View {
        rowStack {
            Text(label).foregroundStyle(isAX ? colors.textSecondary : colors.textPrimary)
            if !isAX { Spacer(minLength: 12) }
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, isAX ? 10 : 6)
        .frame(minHeight: 52)
        .background(colors.timber.opacity(flashing ? flash : 0))
    }

    // MARK: Footer

    /// Pinned above the keyboard / home indicator; at AX sizes it scrolls with the form unless
    /// the keyboard is up (then the Log button still rides on the keyboard).
    private var footerIsPinned: Bool { !isAX || noteFocused }

    private var missingMessage: String? { form.missingMessage(properties: properties) }
    /// The caution line shows once something is typed or picked (an untouched sheet isn't scolded).
    private var showsMissing: Bool {
        missingMessage != nil && (!form.note.isEmpty || isReviewing || properties.isEmpty || LogSheetDebug.forcesInvalid)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(colors.caution)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("log.saveError")
            } else if showsMissing, let missingMessage {
                Text(missingMessage)
                    .font(.footnote)
                    .foregroundStyle(colors.caution)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("log.missing")
            }
            HStack(spacing: 12) {
                Button(action: save) {
                    Text(LogTimeFormat.logButton(form.hours))
                        .contentTransition(.numericText(value: form.hours))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(InboxPrimaryButtonStyle())
                .disabled(!form.canLog(properties: properties) || isSaving)
                .accessibilityIdentifier("log.save")
                if noteFocused {
                    Button("Done") { noteFocused = false }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colors.action)
                        .frame(minWidth: 44, minHeight: 44)
                        .fixedSize()
                        .accessibilityIdentifier("log.done")
                }
            }
            if isReviewing {
                Button("Discard", action: discardReview)
                    .font(.body)
                    .foregroundStyle(colors.destructive)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("log.discard")
            } else if !noteFocused {
                Button("Start a timer instead") {
                    withMotion { mode = viewModel.isTimerRunning ? .timerRunning : .timerIdle }
                }
                .font(.body)
                .foregroundStyle(colors.action)
                .frame(minHeight: 44)
                .accessibilityIdentifier("log.startTimer")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(colors.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            LinearGradient(colors: [colors.background.opacity(0), colors.background], startPoint: .top, endPoint: .bottom)
                .frame(height: 20)
                .offset(y: -20)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: Timer

    private var timerIdle: some View {
        VStack(spacing: 24) {
            VStack(spacing: 0) {
                valueRow("Property", flashing: false, identifier: "timer.property") { picker = .property } value: {
                    if let property = properties.first(where: { $0.id == form.propertyId }) {
                        HStack(spacing: 8) {
                            PropertySeal(property, in: properties, size: 24)
                            Text(property.name).foregroundStyle(colors.textPrimary).lineLimit(2)
                        }
                    } else {
                        Text("Choose").foregroundStyle(colors.action)
                    }
                }
                divider
                valueRow("Category", flashing: false, identifier: "timer.category") { picker = .category } value: {
                    HStack(spacing: 8) {
                        CategoryToolTile(category: timerCategory, size: 24)
                        Text(timerCategory.inboxLabel).foregroundStyle(colors.textPrimary)
                    }
                }
            }
            .font(.body)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("0:00")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(colors.textTertiary)
                .padding(.vertical, 16)
                .accessibilityLabel("Timer at zero")

            VStack(spacing: 8) {
                Button("Start timer", action: startTimer)
                    .buttonStyle(InboxPrimaryButtonStyle())
                    .disabled(form.propertyId == nil || viewModel.isTimerRunning)
                    .accessibilityIdentifier("timer.start")
                if form.propertyId == nil {
                    Text("Pick a property to start the timer.")
                        .font(.footnote)
                        .foregroundStyle(colors.caution)
                }
                Button("Log time instead") { withMotion { mode = .log } }
                    .font(.body)
                    .foregroundStyle(colors.action)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("timer.logInstead")
            }
        }
    }

    private var timerCategory: ActivityCategory { form.category ?? .management }

    private var timerRunning: some View {
        VStack(spacing: 16) {
            LiveTimerCard(
                property: properties.first { $0.id == viewModel.timerPropertyId },
                properties: properties,
                category: viewModel.timerCategory,
                start: viewModel.timerStartTime ?? Date(),
                onStop: stopTimer
            )
            Button("Discard", action: discardRunning)
                .font(.body)
                .foregroundStyle(colors.destructive)
                .frame(minHeight: 44)
                .accessibilityIdentifier("timer.discard")
            Text("Keeps running if you close this. You\u{2019}ll see it on your Lock Screen.")
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func startTimer() {
        guard let propertyId = form.propertyId else { return }
        viewModel.startTimer(propertyId: propertyId, category: timerCategory)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withMotion { mode = .timerRunning }
    }

    private func stopTimer() {
        guard let draft = viewModel.stopTimerIntoDraft() else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withMotion { beginReview(draft) }
    }

    private func discardRunning() {
        guard let propertyId = viewModel.timerPropertyId, let start = viewModel.timerStartTime else { return }
        let category = viewModel.timerCategory
        viewModel.cancelTimer()
        onClose()
        AppToastCenter.shared.show("Timer discarded", kind: .neutral) { [weak viewModel = viewModel] in
            viewModel?.restoreTimer(propertyId: propertyId, category: category, startTime: start)
        }
    }

    private func discardReview() {
        switch mode {
        case .review(var draft):
            draft.notes = form.note
            StoppedTimerDraftStore.clear()
            onClose()
            AppToastCenter.shared.show("Timer discarded", kind: .neutral) { StoppedTimerDraftStore.save(draft) }
        case .recovery(let recovery):
            viewModel.discardRecoveredStaleTimer(id: recovery.id)
            onClose()
            AppToastCenter.shared.show("Timer discarded", kind: .neutral)
        default: break
        }
    }

    /// The note the user is writing for a stopped timer survives closing the sheet.
    private func persistReviewDraft() {
        guard case .review(var draft) = mode else { return }
        draft.notes = form.note
        draft.participant = form.participant
        StoppedTimerDraftStore.save(draft)
    }

    // MARK: Note reading

    private func noteChanged(_ text: String) {
        guard mode == .log else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { usedVoice = false }
        guard !isListening else { return }
        readNote(delay: 0.6, source: usedVoice ? .voice : .note)
    }

    /// After a 600ms pause the note is read: the rules fill at once, then Apple's on-device
    /// model (and Private Cloud Compute when the phone's model can't answer) refine the fields
    /// while the drafting line shows. Never a field the user set; nothing is saved until Log.
    private func readNote(delay: Double, source: LogFillSource) {
        readTask?.cancel()
        let text = form.trimmedNote
        guard text.count >= 6, mode == .log, !LogSheetDebug.holdsReading else {
            isReading = false
            return
        }
        let request = NoteReadRequest(text: text, properties: properties, spouseTracking: spouseTracking)
        let chain = noteReader
        readTask = Task { @MainActor in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, form.trimmedNote == text else { return }
            let rules = chain.rules(request)
            fill(rules, source: source)
            guard chain.hasModel else {
                isReading = false
                return
            }
            withAnimation(.easeOut(duration: 0.2)) { isReading = true }
            let outcome = await chain.read(request, rules: rules) { refined in
                guard !Task.isCancelled, form.trimmedNote == text else { return }
                fill(refined, source: source)
            }
            guard !Task.isCancelled, form.trimmedNote == text else { return }
            withMotion { isReading = false }
            fill(outcome.reading, source: source)
        }
    }

    private func fill(_ reading: NoteReading, source: LogFillSource) {
        var wrote = Set<LogField>()
        withMotion { wrote = form.apply(reading, source: source, spouseTracking: spouseTracking) }
        if !wrote.isEmpty { playFlash() }
    }

    /// The timber wash on each filled value: 0 → 16% → 0 over 600ms.
    private func playFlash() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.3)) { flash = 0.16 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeIn(duration: 0.3)) { flash = 0 }
        }
    }

    // MARK: Voice

    private func micTapped() {
        if voice.isRecording {
            voice.finishRecording()
            return
        }
        if voice.permissionDenied {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        if voice.needsPermissionPrompt && !LogVoiceIntro.seen {
            withMotion { showVoiceIntro = true }
            return
        }
        startListening()
    }

    private func startListening() {
        noteFocused = false
        Task { await voice.startRecording(contextualStrings: voiceContextualStrings) }
    }

    private var voiceContextualStrings: [String] {
        var phrases = properties.flatMap { [$0.name, $0.address] + $0.aliases }
        phrases += ActivityCategory.allCases.flatMap { [$0.rawValue, $0.inboxLabel] }
        phrases += ["spouse", "tenant", "receipt", "plumber", "showing"]
        let unique = Array(Set(phrases.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }))
        return Array(unique.prefix(80))
    }

    // MARK: Save

    private func save() {
        guard form.canLog(properties: properties), let propertyId = form.propertyId, let category = form.category, !isSaving else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        noteFocused = false
        let participant = form.participantToSave(spouseTracking: spouseTracking)
        let propertyName = properties.first { $0.id == propertyId }?.name
        let hours = form.hours

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

    private func fail(_ message: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        withMotion { saveError = message }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func succeed(_ message: String, undo: (() -> Void)?) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onClose()
        AppToastCenter.shared.show(message, kind: .success, undo: undo)
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var loaded: [TimeAttachment] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loaded.append(TimeAttachment(filename: "photo_\(UUID().uuidString).jpg", data: data, mimeType: "image/jpeg"))
            }
        }
        attachments = loaded
    }

    private func withMotion(_ body: () -> Void) {
        if reduceMotion { withAnimation(.easeOut(duration: 0.2), body) } else { withAnimation(.spring(response: 0.3, dampingFraction: 1), body) }
    }
}

// MARK: - Parts

/// The confirm sheet's stepper ("How long?", 15-minute steps) with 30m / 1h / 2h / 4h presets.
struct LogHoursStepper: View {
    @Binding var hours: Double
    var flash: Double = 0
    @Binding var stepTick: Int
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let presets: [(String, Double)] = [("30m", 0.5), ("1h", 1), ("2h", 2), ("4h", 4)]

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let minutes = Int((hours * 60).rounded())
        VStack(alignment: .leading, spacing: 10) {
            Text("How long?")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, 4)
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    step("minus", enabled: hours > 0, colors: colors) { hours = max(0, hours - LogForm.step) }
                        .accessibilityLabel("Less time")
                        .accessibilityIdentifier("log.hours.minus")
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(minutes / 60)")
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText(value: Double(minutes / 60)))
                        Text("h").font(.title3).foregroundStyle(colors.textSecondary)
                        Text(String(format: "%02d", minutes % 60))
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText(value: Double(minutes % 60)))
                            .padding(.leading, 6)
                        Text("m").font(.title3).foregroundStyle(colors.textSecondary)
                    }
                    .monospacedDigit()
                    .foregroundStyle(hours > 0 ? colors.textPrimary : colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("How long")
                    .accessibilityValue(InboxFormat.spokenHours(hours))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: hours = min(LogForm.maxHours, hours + LogForm.step)
                        case .decrement: hours = max(0, hours - LogForm.step)
                        @unknown default: break
                        }
                    }
                    .accessibilityIdentifier("log.hours.value")
                    Spacer(minLength: 0)
                    step("plus", enabled: hours < LogForm.maxHours, colors: colors) { hours = min(LogForm.maxHours, hours + LogForm.step) }
                        .accessibilityLabel("More time")
                        .accessibilityIdentifier("log.hours.plus")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
                    ForEach(presets, id: \.0) { preset in
                        let on = abs(hours - preset.1) < 0.01
                        Button {
                            animate { hours = preset.1 }
                            stepTick += 1
                        } label: {
                            Text(preset.0)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundStyle(on ? colors.onAction : colors.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Capsule().fill(on ? colors.action : colors.backgroundTertiary))
                                .overlay(Capsule().strokeBorder(on ? Color.clear : colors.border, lineWidth: 0.5))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.lhPressable)
                        .accessibilityLabel(InboxFormat.spokenHours(preset.1))
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                        .accessibilityIdentifier("log.chip.\(preset.0)")
                    }
                }
            }
            .padding(16)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.timber.opacity(flash)).allowsHitTesting(false))
        }
    }

    private func animate(_ body: () -> Void) {
        if reduceMotion { body() } else { withAnimation(.spring(response: 0.28, dampingFraction: 0.9), body) }
    }

    private func step(_ symbol: String, enabled: Bool, colors: AdaptiveColors, _ action: @escaping () -> Void) -> some View {
        Button {
            animate(action)
            stepTick += 1
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(enabled ? colors.textPrimary : colors.textTertiary)
                .frame(width: 44, height: 44)
                .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(colors.border, lineWidth: 0.5))
        }
        .buttonStyle(.lhPressable)
        .disabled(!enabled)
    }
}

/// Me / Spouse on brand tokens (the system segmented control renders grey on iOS 27).
struct LogWhoPicker: View {
    @Binding var participant: Participant
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        HStack(spacing: 2) {
            ForEach([Participant.selfParticipant, .spouse], id: \.self) { option in
                let selected = participant == option
                Button {
                    if reduceMotion { participant = option } else { withAnimation(AppAnimation.quick) { participant = option } }
                } label: {
                    Text(option == .spouse ? "Spouse" : "Me")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(selected ? colors.onAction : colors.textPrimary)
                        .padding(.horizontal, 16)
                        .frame(minWidth: 64, minHeight: 36)
                        .background(Capsule().fill(selected ? colors.action : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option == .spouse ? "Spouse" : "Me")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier(option == .spouse ? "log.who.spouse" : "log.who.me")
            }
        }
        .padding(3)
        .background(Capsule().fill(colors.backgroundTertiary))
        .overlay(Capsule().strokeBorder(colors.border, lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .contain)
    }
}

/// A 2pt drafting ring that follows the input level; still in silence and under Reduce Motion.
struct LogMicLevelRing: View {
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Circle()
            .strokeBorder(AdaptiveColors(colorScheme: colorScheme).drafting, lineWidth: 2)
            .scaleEffect(1 + (reduceMotion ? 0 : min(max(level, 0), 1)) * 0.18)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: level)
            .accessibilityHidden(true)
    }
}

/// The Live Activity layout at full size, on theme-fixed blueprint. No dial, ring or pulse.
struct LiveTimerCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let property: RentalProperty?
    let properties: [RentalProperty]
    let category: ActivityCategory
    let start: Date
    var onStop: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = min(context.date.timeIntervalSince(start), TimerReviewMath.cap)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    if let property {
                        PropertySeal(property, in: properties, size: 24)
                            .environment(\.colorScheme, .dark)
                    }
                    Text(property?.name ?? "Timer")
                        .font(.headline)
                        .foregroundStyle(OnBlueprint.primary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if !dynamicTypeSize.isAccessibilitySize {
                    Text("LandlordHours")
                        .font(.caption2.monospaced().weight(.medium))
                        .textCase(.uppercase)
                        .tracking(1.5)
                        .foregroundStyle(HouseTokens.drafting)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityHidden(true)
                    }
                }
                Text(LogTimeFormat.clock(elapsed))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(OnBlueprint.primary)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.easeOut(duration: 0.2), value: Int(elapsed))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel("Running for \(InboxFormat.spokenHours(elapsed / 3600))")
                    .accessibilityIdentifier("timer.clock")
                Text("\(category.inboxLabel)\(LogTimeFormat.dot)started \(InboxFormat.clockTime(start))")
                    .font(.subheadline)
                    .foregroundStyle(HouseTokens.onHeroSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Stop", action: onStop)
                    .buttonStyle(OnBlueprintButtonStyle())
                    .accessibilityIdentifier("timer.stop")
            }
            .padding(20)
            .background(InboxBlueprintPaper(cornerRadius: 24))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timer.card")
    }
}

/// "Talk like you'd tell a friend" shows once, before the system asks.
enum LogVoiceIntro {
    private static var key: String { UserScope.key("LandlordHours.voiceIntroSeen") }
    static var seen: Bool { UserDefaults.standard.bool(forKey: key) }
    static func markSeen() { UserDefaults.standard.set(true, forKey: key) }
}

extension AppViewModel {
    /// Stops the running timer into a draft the review (and Today's draft card) can log.
    /// The draft is stored before the timer ends, so nothing is lost if the app dies here.
    @discardableResult
    func stopTimerIntoDraft(now: Date = Date()) -> StoppedTimerDraft? {
        guard isTimerRunning, let start = timerStartTime, let propertyId = timerPropertyId else { return nil }
        let draft = StoppedTimerDraft(elapsed: now.timeIntervalSince(start), propertyId: propertyId, category: timerCategory,
                                      startDate: start, participant: .selfParticipant, notes: "")
        StoppedTimerDraftStore.save(draft)
        cancelTimer()
        return draft
    }
}
