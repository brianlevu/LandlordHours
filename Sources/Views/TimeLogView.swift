import SwiftUI
import Combine
import PhotosUI
import LucideIcons

struct TimeLogView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var categoryManager: CategoryManager
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @StateObject private var voiceEntryService = VoiceEntryService.shared

    // Main inline entry form state
    @State private var entryNotes: String = ""
    @State private var entryCategory: ActivityCategory = .management
    @State private var entryPropertyId: UUID?
    @State private var entryHours: Double = 1.0
    @State private var entryDate: Date = Date()
    @State private var entryParticipant: Participant = .selfParticipant
    @State private var entryPhotoItems: [PhotosPickerItem] = []
    @State private var entryAttachments: [TimeAttachment] = []
    @State private var showingSaved: Bool = false
    @State private var isSaving: Bool = false
    @State private var isLogDetailsExpanded: Bool = false

    // Timer mode
    enum TrackMode: String, CaseIterable {
        case log = "Log"
        case timer = "Timer"
    }
    enum TimerPhase {
        case idle, running, finishing
    }
    @State private var trackMode: TrackMode = .log
    @State private var timerPhase: TimerPhase = .idle
    @State private var timerSelectedPropertyId: UUID?
    @State private var timerSelectedCategory: ActivityCategory = .management
    @State private var timerNotes: String = ""
    @State private var timerParticipant: Participant = .selfParticipant
    @State private var timerElapsed: TimeInterval = 0
    @State private var stoppedElapsed: TimeInterval = 0
    @State private var stoppedPropertyId: UUID?
    @State private var stoppedCategory: ActivityCategory = .management
    @State private var stoppedStartDate: Date = Date()
    @State private var showTimerCappedAlert = false
    @State private var showDiscardTimerAlert = false
    @FocusState private var isTimerNotesFocused: Bool
    private let timerTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var stoppedTimerDraftKey: String { UserScope.key("LandlordHours.stoppedTimerDraft") }
    private let minimumSavableTimerElapsed: TimeInterval = 60

    // Inline AI state
    @State private var isProcessingAI: Bool = false
    @State private var aiParsedEntry: ParsedTimeEntry?
    @State private var aiAutoFilled: Bool = false
    @State private var aiDebounceTask: Task<Void, Never>?
    @State private var userAdjustedLogDetails: Bool = false

    // Property picker sheet
    @State private var showingPropertyPicker = false

    // Keyboard focus
    @FocusState private var isNotesFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.properties.isEmpty {
                    emptyState
                } else {
                    mainScrollContent
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            if viewModel.properties.count == 1 {
                entryPropertyId = viewModel.properties.first?.id
                timerSelectedPropertyId = viewModel.properties.first?.id
            }
            if loadStoppedTimerDraft() {
                trackMode = .timer
                timerPhase = .finishing
                return
            }
            // Auto-switch to timer mode if a timer is running and we're not already in a timer flow
            if viewModel.isTimerRunning && timerPhase == .idle {
                trackMode = .timer
                timerPhase = .running
                timerElapsed = viewModel.timerElapsedTime
            }
        }
        .onChange(of: viewModel.isTimerRunning) { _, isRunning in
            if !isRunning && timerPhase == .running {
                timerPhase = .idle
                timerElapsed = 0
            }
        }
        .onChange(of: voiceEntryService.transcript) { _, transcript in
            applyVoiceTranscript(transcript)
        }
        .onChange(of: timerNotes) { _, _ in
            if timerPhase == .finishing { saveStoppedTimerDraft() }
        }
        .onChange(of: timerParticipant) { _, _ in
            if timerPhase == .finishing { saveStoppedTimerDraft() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .prefillFirstActivity)) { _ in
            guard viewModel.timeEntries.isEmpty, !viewModel.properties.isEmpty else { return }
            trackMode = .log
            entryPropertyId = viewModel.properties.first?.id
            entryCategory = .management
            entryHours = 1.0
            entryDate = Date()
            entryParticipant = .selfParticipant
            entryNotes = "Reviewed tenant message and coordinated maintenance for the property."
            aiParsedEntry = nil
            aiAutoFilled = false
            isLogDetailsExpanded = false
            isNotesFocused = false
            userAdjustedLogDetails = false
        }
        .alert("Timer Capped", isPresented: $showTimerCappedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your timer was running for over 24 hours. The entry has been capped at 24 hours.")
        }
        .alert("Discard this timer?", isPresented: $showDiscardTimerAlert) {
            Button("Keep Timer", role: .cancel) {}
            Button("Discard timer", role: .destructive) {
                viewModel.cancelTimer()
                timerPhase = .idle
                timerElapsed = 0
            }
        } message: {
            Text("The running timer will stop without saving a time entry.")
        }
        .onDisappear {
            voiceEntryService.finishRecording()
        }
    }

    // MARK: - Main Scroll Content
    private var mainScrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection
                        .id("trackHeader")
                    if let recovery = viewModel.staleTimerRecovery {
                        staleTimerRecoveryCard(recovery)
                    }
                    if trackMode == .log {
                        mainEntryCard
                    } else {
                        timerCard
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, AppSpacing.tabContentBottomInset)
            }
            .background {
                LHMobileCanvas()
            }
            .onTapGesture {
                isNotesFocused = false
                isTimerNotesFocused = false
            }
            .onChange(of: isLogDetailsExpanded) { _, expanded in
                guard expanded else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    animate(AppAnimation.smooth) {
                        proxy.scrollTo("trackHeader", anchor: .top)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    if showingSaved {
                        savedBanner
                            .transition(toastTransition)
                            .lhMotion(AppAnimation.reveal, value: showingSaved)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 94)
            }
        }
    }

    private var contentTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

    private var toastTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private func animate(_ animation: Animation = AppAnimation.smooth, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Log your time")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .lineSpacing(-2)
                        .minimumScaleFactor(0.82)
                    Text(trackMode == .log ? "Describe the work. We’ll fill the details." : "Start a timer for work in progress.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()

                LucideIcon(image: trackMode == .log ? Lucide.penLine : Lucide.timer, size: 22)
                    .foregroundStyle(colors.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            modeToggle
        }
    }

    // MARK: - Stale Timer Recovery
    private func staleTimerRecoveryCard(_ recovery: StaleTimerRecovery) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                LHIconTile(icon: Lucide.timerReset, color: AppColors.honey, wash: colors.honeyWash, size: 42, isActive: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Finish your saved timer")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text(staleTimerRecoveryMessage(recovery))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.saveRecoveredStaleTimer()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Text("Save \(AppFormat.hours(recovery.suggestedHours))")
                        .font(AppTypography.buttonSmall)
                        .foregroundStyle(AppColors.onAction)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.action)
                        .clipShape(Capsule())
                }
                .buttonStyle(.lhPressable)

                Button {
                    viewModel.discardRecoveredStaleTimer()
                } label: {
                    Text("Discard")
                        .font(AppTypography.buttonSmall)
                        .foregroundStyle(colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(colors.backgroundTertiary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.lhPressable)
            }
        }
        .padding(16)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.xl, style: .continuous)
                .strokeBorder(colors.border.opacity(0.45), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Forgotten timer recovery. \(staleTimerRecoveryMessage(recovery))")
    }

    private func staleTimerRecoveryMessage(_ recovery: StaleTimerRecovery) -> String {
        let propertyName = viewModel.properties.first { $0.id == recovery.propertyId }?.name ?? "this property"
        let start = recovery.startTime.formatted(date: .abbreviated, time: .shortened)
        return "Started \(start) for \(propertyName). We capped the suggested entry at 24 hours so you can review it instead of losing the record."
    }

    // MARK: - Main Entry Card
    private var mainEntryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            entryComposerHeader

            notesSection

            aiStateSection

            if isLogDetailsExpanded {
                logDetailsSection
                    .transition(contentTransition)
            } else {
                composerNextStep
                .transition(.opacity)
            }
        }
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(colors.border.opacity(0.28), lineWidth: 1)
        }
        .lhMotion(AppAnimation.flow, value: isLogDetailsExpanded)
    }

    private var entryComposerHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            LHIconTile(icon: Lucide.sparkles, color: colors.action, wash: colors.actionSurface, size: 40, isActive: true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Today’s entry")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Text("Write it naturally. Review the evidence before saving.")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: - Field Label
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .black, design: .rounded))
            .foregroundStyle(colors.textPrimary)
            .padding(.bottom, 10)
    }

    // MARK: - Notes Section
    private var notesSection: some View {
        ZStack(alignment: .topLeading) {
            if entryNotes.isEmpty {
                Text("Called plumber about the Oak Street leak for 1 hour")
                    .foregroundStyle(colors.textSecondary.opacity(0.72))
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .padding(.top, 20)
                    .padding(.leading, 20)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $entryNotes)
                .focused($isNotesFocused)
                .frame(minHeight: isLogDetailsExpanded ? 74 : 122, maxHeight: isLogDetailsExpanded ? 116 : 156)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(colors.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            isNotesFocused = false
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.primary)
                    }
                }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    voiceEntryButton
                        .padding(.trailing, 10)
                        .padding(.bottom, 10)
                }
            }
        }
        .padding(4)
        .background(colors.backgroundTertiary.opacity(colorScheme == .dark ? 0.72 : 0.9))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    notesBorderColor,
                    lineWidth: aiParsedEntry != nil || isProcessingAI ? 1.5 : 1
                )
        )
        .padding(.horizontal, 20)
        .guidedSpotlightTarget(.firstActivity)
        .onChange(of: entryNotes) { _, newValue in
            handleNotesChange(newValue)
        }
    }

    private var voiceEntryButton: some View {
        Button {
            toggleVoiceEntry()
        } label: {
            HStack(spacing: 7) {
                LucideIcon(image: voiceEntryService.isRecording ? Lucide.audioWaveform : Lucide.mic, size: 15)
                Text(voiceEntryService.isRecording ? "Listening" : "Speak")
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(voiceEntryService.isRecording ? AppColors.onAction : colors.action)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(voiceEntryService.isRecording ? colors.action : colors.actionSurface)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(colors.action.opacity(voiceEntryService.isRecording ? 0 : 0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(voiceEntryService.isRecording ? "Stop voice entry" : "Start voice entry")
        .accessibilityHint("Dictates the time entry description using Apple speech recognition.")
    }

    private var composerNextStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            if entryNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entryEvidencePreview

                Button {
                    revealLogDetails()
                } label: {
                    HStack(spacing: 12) {
                        LHIconTile(icon: Lucide.slidersHorizontal, color: colors.textPrimary, wash: colors.backgroundTertiary, size: 34, isActive: true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Set details manually")
                                .font(AppTypography.button)
                                .foregroundStyle(colors.textPrimary)
                            Text("Property, category, hours")
                                .font(AppTypography.caption)
                                .foregroundStyle(colors.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        Spacer(minLength: 8)
                        LucideIcon(image: Lucide.chevronDown, size: 18)
                            .foregroundStyle(colors.textPrimary)
                    }
                    .padding(15)
                    .background(colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.lhPressable)
            } else {
                entryEvidencePreview

                Button {
                    revealLogDetails()
                } label: {
                    HStack(spacing: 8) {
                        Text("Review evidence")
                        LucideIcon(image: Lucide.arrowRight, size: 16)
                    }
                    .font(AppTypography.button)
                    .foregroundStyle(AppColors.onAction)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(colors.action)
                    .clipShape(Capsule())
                }
                .buttonStyle(.lhPressable)

                Text("Property, category, hours, date, person, and attachments stay editable before saving.")
                    .font(AppTypography.caption)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var entryEvidencePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                LucideIcon(image: Lucide.clipboardCheck, size: 15)
                    .foregroundStyle(colors.action)
                Text("Evidence draft")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                Text(evidenceDraftStatus)
                    .font(AppTypography.caption)
                    .foregroundStyle(evidenceDraftStatusColor)
            }

            VStack(spacing: 8) {
                evidencePreviewChip(icon: Lucide.house, text: selectedPropertyName, isResolved: effectivePropertyId != nil)

                HStack(spacing: 8) {
                    evidencePreviewChip(icon: Lucide.tag, text: categoryChipLabel(for: entryCategory), isResolved: true)
                    evidencePreviewChip(icon: Lucide.clock, text: AppFormat.hours(entryHours), isResolved: true)
                }
            }
        }
        .padding(14)
        .background(colors.background.opacity(colorScheme == .dark ? 0.45 : 0.72))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(colors.border.opacity(0.2), lineWidth: 1)
        )
    }

    private var evidenceDraftStatus: String {
        if aiAutoFilled { return "AI filled" }
        if aiParsedEntry != nil { return "Detected" }
        if entryNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Ready" }
        return "Review"
    }

    private var evidenceDraftStatusColor: Color {
        if aiAutoFilled { return colors.positive }
        if aiParsedEntry != nil { return colors.action }
        return colors.textSecondary
    }

    private func evidencePreviewChip(icon: UIImage, text: String, isResolved: Bool) -> some View {
        HStack(spacing: 6) {
            LucideIcon(image: icon, size: 13)
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .font(AppTypography.caption)
        .foregroundStyle(isResolved ? colors.textPrimary : colors.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(isResolved ? colors.backgroundSecondary : colors.backgroundTertiary.opacity(0.75))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(colors.border.opacity(isResolved ? 0.24 : 0.12), lineWidth: 1)
        )
    }

    private var logDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                LHIconTile(icon: Lucide.listChecks, color: colors.action, wash: colors.actionSurface, size: 32, isActive: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entryNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Set details" : "Review details")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text(entryNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Fill the fields now, then add a note before saving." : "Adjust only what needs changing.")
                        .font(AppTypography.caption)
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)

            quickDetailSummary

            logTimeButton
                .padding(.horizontal, 20)

            fieldLabel("Category")
                .padding(.horizontal, 20)
            categoryChipsSection

            if viewModel.properties.count > 1 {
                fieldLabel("Property")
                    .padding(.horizontal, 20)
                propertyPickerRow
                    .padding(.horizontal, 20)
            }

            fieldLabel("Hours")
                .padding(.horizontal, 20)
            hoursStepperRow

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("Date")
                datePickerRow
            }
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("Person")
                participantSegment
            }
            .padding(.horizontal, 20)

            attachButton
                .padding(.horizontal, 20)
        }
        .padding(.top, 4)
        .padding(.bottom, 20)
    }

    private var quickDetailSummary: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                compactDetailChip(icon: Lucide.clock, text: AppFormat.hours(entryHours))
                compactDetailChip(icon: Lucide.tag, text: categoryChipLabel(for: entryCategory))
                compactDetailChip(icon: Lucide.house, text: selectedPropertyName)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactDetailChip(icon: UIImage, text: String) -> some View {
        HStack(spacing: 6) {
            LucideIcon(image: icon, size: 13)
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .font(AppTypography.caption)
        .foregroundStyle(colors.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(colors.background.opacity(0.56))
        .clipShape(Capsule())
    }

    // MARK: - AI State Section
    private var aiStateSection: some View {
        Group {
            if aiAutoFilled {
                // State 3: Auto-filled confirmation
                autoFilledConfirmation
            } else if let parsed = aiParsedEntry {
                // State 2: AI suggestion bar
                aiSuggestionBar(parsed: parsed)
            } else if isProcessingAI {
                // Loading state
                aiProcessingIndicator
            } else if let voiceError = voiceEntryService.errorMessage {
                voiceEntryError(voiceError)
            } else if voiceEntryService.isRecording {
                voiceEntryListeningIndicator
            } else {
                // State 1: AI hint — show until notes are long enough to trigger AI
                let trimmed = entryNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed.count < 10 {
                    aiHint(hasStartedTyping: !entryNotes.isEmpty)
                }
            }
        }
    }

    // State 1: AI Hint
    private func aiHint(hasStartedTyping: Bool) -> some View {
        HStack(spacing: 8) {
            // AI sparkle badge
            LHIconTile(icon: Lucide.sparkles, color: colors.action, wash: colors.actionSurface, size: 26, isActive: true)
            Text(hasStartedTyping
                 ? "Keep typing. AI will detect category, property, and hours."
                 : "Describe your work and AI will fill in the details")
                .font(.system(size: 12))
                .foregroundStyle(colors.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .lhMotion(AppAnimation.standard, value: hasStartedTyping)
    }

    private var voiceEntryListeningIndicator: some View {
        HStack(spacing: 10) {
            LHIconTile(icon: Lucide.audioWaveform, color: colors.action, wash: colors.actionSurface, size: 28, isActive: true)
            Text("Listening. Speak naturally, then review the draft.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(colors.textPrimary)
            Spacer()
            Button("Done") {
                voiceEntryService.finishRecording()
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(colors.action)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(colors.actionSurface.opacity(colorScheme == .dark ? 0.45 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    private func voiceEntryError(_ message: String) -> some View {
        HStack(spacing: 10) {
            LHIconTile(icon: Lucide.micOff, color: AppColors.caution, wash: colors.cautionSurface, size: 28, isActive: true)
            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(colors.cautionSurface.opacity(colorScheme == .dark ? 0.48 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // AI Processing
    private var aiProcessingIndicator: some View {
        HStack(spacing: 10) {
            // AI sparkle badge
            LHIconTile(icon: Lucide.sparkles, color: colors.action, wash: colors.actionSurface, size: 28, isActive: true)
            Text("Analyzing your description...")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colors.textPrimary)
            Spacer()
            ProgressView()
                .scaleEffect(0.7)
                .tint(colors.action)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(colors.actionSurface.opacity(colorScheme == .dark ? 0.45 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // State 2: AI Suggestion Bar
    private func aiSuggestionBar(parsed: ParsedTimeEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LHIconTile(icon: Lucide.sparkles, color: colors.action, wash: colors.actionSurface, size: 32, isActive: true)
                Text("Detected details")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)

                Spacer(minLength: 8)

                Button {
                    applyAutoFill(parsed)
                } label: {
                    Text("Auto-fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.onAction)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(colors.action)
                        .clipShape(Capsule())
                }
                .buttonStyle(.lhPressable)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    aiDetectedChip(
                        dotColor: categoryDotColor(for: parsed.category),
                        text: categoryChipLabel(for: parsed.category)
                    )

                    if let property = parsed.property {
                        aiDetectedChip(dotColor: nil, text: property.name, icon: "🏠")
                    }

                    aiDetectedChip(
                        dotColor: nil,
                        text: "\(parsed.hours.formatted(.number.precision(.fractionLength(0...1))))h"
                    )
                }
            }
        }
        .padding(14)
        .background(colors.actionSurface.opacity(colorScheme == .dark ? 0.45 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(colors.action.opacity(0.32), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .transition(contentTransition)
    }

    private func aiDetectedChip(dotColor: Color?, text: String, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
            }
            if let icon {
                Text(icon)
                    .font(.system(size: 10))
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(colors.backgroundSecondary)
        .clipShape(Capsule())
    }

    // State 3: Auto-filled confirmation
    private var autoFilledConfirmation: some View {
        HStack(spacing: 6) {
            LucideIcon(image: Lucide.check, size: 14)
                .foregroundStyle(AppColors.sage)
            Text("Draft ready from your description")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .transition(.opacity)
    }

    // MARK: - Category Chips
    private var categoryChipsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityCategory.allCases, id: \.self) { cat in
                    Button {
                        updateEntryCategory(cat)
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(entryCategory == cat
                                      ? Color.white.opacity(0.5)
                                      : categoryDotColor(for: cat))
                                .frame(width: 8, height: 8)
                            Text(categoryChipLabel(for: cat))
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(entryCategory == cat ? AppColors.onAction : colors.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(entryCategory == cat ? colors.action : colors.backgroundTertiary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    entryCategory == cat ? colors.action.opacity(0.55) : colors.border.opacity(0.2),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.lhPressable)
                    .lhMotion(AppAnimation.pillPop, value: entryCategory == cat)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Property Picker Row
    private var propertyPickerRow: some View {
        Menu {
            ForEach(viewModel.properties) { property in
                Button {
                    updateEntryPropertyId(property.id)
                } label: {
                    HStack {
                        Text(property.name)
                        if entryPropertyId == property.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                // House icon badge
                LHIconTile(
                    icon: Lucide.house,
                    color: entryPropertyId != nil ? AppColors.primary : AppColors.mist,
                    wash: entryPropertyId != nil ? colors.primarySurface : AppColors.snow,
                    size: 30,
                    isActive: entryPropertyId != nil
                )

                Text(selectedPropertyName)
                    .font(.system(size: 15))
                    .foregroundStyle(entryPropertyId != nil ? colors.textPrimary : AppColors.mist)

                Spacer()

                LucideIcon(image: Lucide.chevronRight, size: 18)
                    .foregroundStyle(AppColors.cloud)
            }
            .padding(14)
            .padding(.horizontal, 2)
            .background(colors.background.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(AppColors.snow, lineWidth: 1.5)
            )
        }
    }

    private var selectedPropertyName: String {
        if let id = entryPropertyId, let property = viewModel.properties.first(where: { $0.id == id }) {
            return property.name
        }
        return "Select property"
    }

    // MARK: - Hours Stepper
    private var hoursStepperRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                Spacer()

                Button {
                    if entryHours > 0.25 {
                        updateEntryHours(entryHours - 0.25)
                    }
                } label: {
                    LucideIcon(image: Lucide.minus, size: 16)
                        .foregroundStyle(colors.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(colors.backgroundTertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.lhPressable)
                .accessibilityLabel("Decrease hours")
                .accessibilityHint("Decreases by 15 minutes")

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(entryHours.formatted(.number.precision(.fractionLength(0...2))))
                        .font(.system(size: 40, weight: .regular, design: .serif))
                        .foregroundStyle(colors.textPrimary)
                        .contentTransition(.numericText())
                    Text("h")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.mist)
                }
                .frame(minWidth: 80, alignment: .center)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(entryHours.formatted(.number.precision(.fractionLength(0...2)))) hours")

                Button {
                    if entryHours < 24 {
                        updateEntryHours(entryHours + 0.25)
                    }
                } label: {
                    LucideIcon(image: Lucide.plus, size: 16)
                        .foregroundStyle(colors.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(colors.backgroundTertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.lhPressable)
                .accessibilityLabel("Increase hours")
                .accessibilityHint("Increases by 15 minutes")

                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([0.5, 1.0, 1.5, 2.0, 3.0, 4.0], id: \.self) { preset in
                        Button {
                            updateEntryHours(preset)
                        } label: {
                            Text(AppFormat.hours(preset))
                                .font(AppTypography.buttonSmall)
                                .foregroundStyle(abs(entryHours - preset) < 0.001 ? AppColors.onAction : colors.textSecondary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(abs(entryHours - preset) < 0.001 ? colors.action : colors.backgroundTertiary)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(abs(entryHours - preset) < 0.001 ? colors.action.opacity(0.55) : colors.border.opacity(0.24), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.lhPressable)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Date Picker Row
    private var datePickerRow: some View {
        HStack(spacing: 10) {
            // Calendar icon badge
            LHIconTile(icon: Lucide.calendar, color: AppColors.primary, wash: colors.primarySurface, size: 30, isActive: true)

            // Overlay DatePicker for native date picking
            DatePicker("", selection: $entryDate, displayedComponents: .date)
                .labelsHidden()
                .tint(AppColors.primary)

            Spacer()
        }
        .padding(14)
        .padding(.horizontal, 2)
        .background(colors.background.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(colors.border.opacity(0.35), lineWidth: 1.5)
        )
    }

    // MARK: - Participant Segment
    private var participantSegment: some View {
        HStack(spacing: 6) {
            segmentButton("Self", isSelected: entryParticipant == .selfParticipant) {
                updateEntryParticipant(.selfParticipant)
            }
            segmentButton("Spouse", isSelected: entryParticipant == .spouse) {
                updateEntryParticipant(.spouse)
            }
        }
        .padding(5)
        .frame(maxWidth: .infinity)
        .background(colors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func segmentButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                LucideIcon(image: title == "Self" ? Lucide.user : Lucide.users, size: 15)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
                .font(.system(size: 15, weight: isSelected ? .bold : .semibold, design: .rounded))
                .foregroundStyle(isSelected ? colors.textPrimary : colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(isSelected ? colors.backgroundSecondary : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? colors.border.opacity(0.35) : Color.clear, lineWidth: 1)
                }
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(title == "Self" ? "Self participant" : "Spouse participant")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Attach Button
    private var attachButton: some View {
        PhotosPicker(
            selection: $entryPhotoItems,
            maxSelectionCount: 5,
            matching: .images
        ) {
            HStack(spacing: 8) {
                LucideIcon(image: Lucide.paperclip, size: 16)
                Text(entryAttachments.isEmpty ? "Attach receipt or document" : "Attached (\(entryAttachments.count))")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(entryAttachments.isEmpty ? AppColors.slate : AppColors.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .onChange(of: entryPhotoItems) { _, newItems in
            Task { await loadPhotos(from: newItems) }
        }
    }

    private var canSave: Bool {
        effectivePropertyId != nil && !isSaving && !entryNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Log Time Button
    private var logTimeButton: some View {
        VStack(spacing: 6) {
            if let helperText = logTimeHelperText {
                Text(helperText)
                    .font(.system(size: 12))
                    .foregroundStyle(colors.textSecondary)
            }
            Button {
                saveMainEntry()
            } label: {
                Text("Log Time")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(canSave ? AppColors.onAction : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(canSave ? colors.action : AppColors.mist)
                    .clipShape(Capsule())
            }
            .buttonStyle(.lhPressable)
            .disabled(!canSave)
        }
    }

    // MARK: - Saved Banner
    private var savedBanner: some View {
        LHSuccessToast(title: "Time logged", detail: "Evidence saved for \(Calendar.current.component(.year, from: entryDate))")
    }

    // MARK: - Category Helpers
    private func categoryChipLabel(for cat: ActivityCategory) -> String {
        cat.chipLabel
    }

    private func categoryDotColor(for cat: ActivityCategory) -> Color {
        cat.color
    }

    // MARK: - Helpers
    private var notesBorderColor: Color {
        if aiParsedEntry != nil && !aiAutoFilled {
            return colors.action // AI has suggestion ready
        }
        if isProcessingAI {
            return colors.action.opacity(0.7) // AI analyzing
        }
        if isNotesFocused && !entryNotes.isEmpty {
            return colors.action.opacity(0.5) // Typing, AI will activate
        }
        return colors.border.opacity(0.18) // Default
    }

    private var effectivePropertyId: UUID? {
        if viewModel.properties.count == 1 { return viewModel.properties[0].id }
        return entryPropertyId
    }

    private var logTimeHelperText: String? {
        if effectivePropertyId == nil {
            return "Select a property to log this entry."
        }
        if entryNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add a short description for your records."
        }
        return nil
    }

    private func saveMainEntry() {
        guard let propId = effectivePropertyId, !isSaving else { return }
        isSaving = true
        isNotesFocused = false
        viewModel.addTimeEntry(
            propertyId: propId,
            participant: entryParticipant,
            category: entryCategory,
            hours: entryHours,
            date: entryDate,
            notes: entryNotes,
            attachments: entryAttachments
        )
        // Reset form
        entryNotes = ""
        entryHours = 1.0
        entryDate = Date()
        entryParticipant = .selfParticipant
        entryCategory = .management
        isLogDetailsExpanded = false
        userAdjustedLogDetails = false
        entryAttachments = []
        entryPhotoItems = []
        aiParsedEntry = nil
        aiAutoFilled = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        animate(AppAnimation.reveal) { showingSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            animate(AppAnimation.reveal) { showingSaved = false }
            isSaving = false
        }
    }

    private func loadPhotos(from items: [PhotosPickerItem]) async {
        var attachments: [TimeAttachment] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let attachment = TimeAttachment(
                    filename: "photo_\(UUID().uuidString).jpg",
                    data: data,
                    mimeType: "image/jpeg"
                )
                attachments.append(attachment)
            }
        }
        await MainActor.run { entryAttachments = attachments }
    }

    // MARK: - AI Logic
    private func handleNotesChange(_ text: String) {
        // Cancel previous debounce
        aiDebounceTask?.cancel()
        isProcessingAI = false
        aiAutoFilled = false
        aiParsedEntry = nil

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            animate(AppAnimation.quick) {
                isLogDetailsExpanded = false
            }
            userAdjustedLogDetails = false
        }
        guard trimmed.count >= 10 else { return }

        // Debounce 1 second before calling AI
        aiDebounceTask = Task {
            try? await Task.sleep(for: .seconds(1.0))
            guard !Task.isCancelled else { return }
            await MainActor.run { isProcessingAI = true }

            let result = await AITimeEntryService.shared.parseTimeEntry(
                from: trimmed,
                properties: viewModel.properties
            )

            // Brief pause so the user sees "Analyzing..." before the result appears
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isProcessingAI = false
                if let result {
                    animate(AppAnimation.smooth) {
                        if userAdjustedLogDetails {
                            aiParsedEntry = result
                        } else {
                            applyAutoFill(result)
                        }
                    }
                }
            }
        }
    }

    private func toggleVoiceEntry() {
        isNotesFocused = false

        if voiceEntryService.isRecording {
            voiceEntryService.finishRecording()
            return
        }

        Task {
            await voiceEntryService.startRecording(contextualStrings: voiceContextualStrings)
        }
    }

    private func applyVoiceTranscript(_ transcript: String) {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        entryNotes = cleaned
    }

    private var voiceContextualStrings: [String] {
        var phrases = viewModel.properties.flatMap { property in
            [property.name, property.address]
        }
        phrases += ActivityCategory.allCases.flatMap { category in
            [category.rawValue, category.chipLabel]
        }
        phrases += ["REPS", "real estate professional", "material participation", "spouse", "tenant", "receipt"]
        let uniquePhrases = Array(Set(phrases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
        return Array(uniquePhrases.prefix(80))
    }

    private func applyAutoFill(_ parsed: ParsedTimeEntry) {
        isNotesFocused = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        animate(AppAnimation.smooth) {
            entryCategory = parsed.category
            entryHours = parsed.hours
            entryParticipant = parsed.participant
            if let property = parsed.property {
                entryPropertyId = property.id
            }
            aiAutoFilled = true
            aiParsedEntry = nil
            isLogDetailsExpanded = true
        }
    }

    private func updateEntryCategory(_ category: ActivityCategory) {
        userAdjustedLogDetails = true
        animate(AppAnimation.quick) {
            entryCategory = category
        }
    }

    private func updateEntryPropertyId(_ propertyId: UUID?) {
        userAdjustedLogDetails = true
        entryPropertyId = propertyId
    }

    private func updateEntryHours(_ hours: Double) {
        userAdjustedLogDetails = true
        animate(AppAnimation.quick) {
            entryHours = min(max(hours, 0.25), 24)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func updateEntryParticipant(_ participant: Participant) {
        userAdjustedLogDetails = true
        animate(AppAnimation.quick) {
            entryParticipant = participant
        }
    }

    private func revealLogDetails() {
        isNotesFocused = false
        animate(AppAnimation.smooth) {
            isLogDetailsExpanded = true
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Circle()
                .fill(colors.backgroundTertiary)
                .frame(width: 76, height: 76)
                .overlay {
                    LucideIcon(image: Lucide.housePlus, size: 32)
                        .foregroundStyle(AppColors.charcoal)
                }
            Text("Add a property first")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)
                .multilineTextAlignment(.center)
            Text("Create one rental property, then log time against it for cleaner records.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 32)

            Button {
                NotificationCenter.default.post(name: .switchToTab, object: 1)
            } label: {
                HStack(spacing: 8) {
                    LucideIcon(image: Lucide.plus, size: 16)
                    Text("Add property")
                }
                .font(AppTypography.button)
                .foregroundStyle(AppColors.onAction)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(colors.action)
                .clipShape(Capsule())
            }
            .buttonStyle(.lhPressable)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LHMobileCanvas()
        }
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            modeButton(.log)
            modeButton(.timer)
        }
        .padding(3)
        .background(colors.backgroundTertiary)
        .clipShape(Capsule())
        .lhMotion(AppAnimation.quick, value: trackMode)
    }

    private func modeButton(_ mode: TrackMode) -> some View {
        Button {
            trackMode = mode
            if mode == .timer && viewModel.isTimerRunning {
                timerPhase = .running
                timerElapsed = viewModel.timerElapsedTime
            }
        } label: {
            HStack(spacing: 6) {
                LucideIcon(image: mode == .log ? Lucide.penLine : Lucide.timer, size: 14)
                Text(mode.rawValue)
                    .font(.system(size: 14, weight: trackMode == mode ? .semibold : .medium))
                if mode == .timer && viewModel.isTimerRunning && trackMode != .timer {
                    Circle()
                        .fill(AppColors.coral)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundStyle(trackMode == mode ? colors.textPrimary : AppColors.slate)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(trackMode == mode ? colors.backgroundSecondary : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.lhPressable)
    }

    // MARK: - Timer Card

    private var timerCard: some View {
        VStack(spacing: 0) {
            switch timerPhase {
            case .idle:
                timerIdleContent
            case .running:
                timerRunningContent
            case .finishing:
                timerFinishingContent
            }
        }
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(colors.border.opacity(0.28), lineWidth: 1)
        }
        .onReceive(timerTick) { _ in
            if viewModel.isTimerRunning && timerPhase == .running {
                timerElapsed = viewModel.timerElapsedTime
            }
        }
    }

    // MARK: - Timer Idle

    private var timerIdleContent: some View {
        VStack(spacing: 0) {
            // Category
            fieldLabel("Category")
                .padding(.horizontal, 20)
                .padding(.top, 20)
            timerCategoryChips
                .padding(.bottom, 20)

            // Property
            if viewModel.properties.count > 1 {
                fieldLabel("Property")
                    .padding(.horizontal, 20)
                timerPropertyPicker
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }

            // Clock ring (idle)
            clockRingView(progress: 0, isActive: false)
                .padding(.vertical, 12)

            // Start button — Tiimo style
            Button {
                startTimerAction()
            } label: {
                HStack(spacing: 10) {
                    Text("Start")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                    LucideIcon(image: Lucide.play, size: 16)
                }
                .foregroundStyle(timerCanStart ? AppColors.onAction : .white)
                .padding(.horizontal, 36)
                .padding(.vertical, 14)
                .background(timerCanStart ? colors.action : AppColors.mist)
                .clipShape(Capsule())
            }
            .buttonStyle(.lhPressable)
            .disabled(!timerCanStart)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Timer Running

    private var timerRunningContent: some View {
        VStack(spacing: 16) {
            // Context chips
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    LucideIcon(image: Lucide.house, size: 12)
                        .foregroundStyle(AppColors.primary)
                    Text(timerPropertyName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(colors.primarySurface)
                .clipShape(Capsule())

                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.timerCategory.color)
                        .frame(width: 6, height: 6)
                    Text(viewModel.timerCategory.chipLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(colors.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(colors.primarySurface)
                .clipShape(Capsule())
            }
            .padding(.top, 20)

            // Clock ring
            clockRingView(progress: ringProgress, isActive: true)

            // Controls — Tiimo style
            HStack(spacing: 20) {
                Button {
                    showDiscardTimerAlert = true
                } label: {
                    Text("Discard timer")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.slate)
                }
                .buttonStyle(.lhPressable)

                Button {
                    stopTimerAction()
                } label: {
                    HStack(spacing: 10) {
                        Text("Stop")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                        LucideIcon(image: Lucide.square, size: 14)
                    }
                    .foregroundStyle(AppColors.onAction)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 14)
                    .background(AppColors.coral)
                    .clipShape(Capsule())
                }
                .buttonStyle(.lhPressable)
            }
            .padding(.bottom, 28)
        }
    }

    // MARK: - Timer Finishing

    private var timerFinishingContent: some View {
        VStack(spacing: 20) {
            // Summary
            VStack(spacing: 8) {
                JellyBadge(systemName: "circle-check", color: AppColors.sage, wash: AppColors.sageWash, size: 48)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.2f", stoppedElapsed / 3600.0))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text("hours")
                        .font(.system(size: 14))
                        .foregroundStyle(colors.textSecondary)
                }

                HStack(spacing: 6) {
                    Text(stoppedPropertyDisplayName)
                    Text("·")
                    Text(stoppedCategory.chipLabel)
                }
                .font(AppTypography.bodySmall)
                .foregroundStyle(colors.textSecondary)
            }
            .padding(.top, 24)

            // Notes
            fieldLabel("Notes")
                .padding(.horizontal, 20)
            ZStack(alignment: .topLeading) {
                if timerNotes.isEmpty {
                    Text("What did you work on?")
                        .foregroundStyle(colors.textTertiary)
                        .font(.system(size: 15))
                        .padding(.top, 12)
                        .padding(.leading, 16)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $timerNotes)
                    .focused($isTimerNotesFocused)
                    .frame(minHeight: 60, maxHeight: 100)
                    .font(.system(size: 15))
                    .foregroundStyle(colors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                isTimerNotesFocused = false
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.primary)
                        }
                    }
            }
            .background(colors.background.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(colors.border.opacity(0.35), lineWidth: 1.5)
            )
            .padding(.horizontal, 20)

            // Participant
            fieldLabel("Participant")
                .padding(.horizontal, 20)
            HStack(spacing: 0) {
                segmentButton("Self", isSelected: timerParticipant == .selfParticipant) {
                    animate(AppAnimation.quick) { timerParticipant = .selfParticipant }
                }
                segmentButton("Spouse", isSelected: timerParticipant == .spouse) {
                    animate(AppAnimation.quick) { timerParticipant = .spouse }
                }
            }
            .padding(3)
            .background(colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)

            // Save / Discard
            VStack(spacing: 10) {
                if stoppedElapsed < minimumSavableTimerElapsed {
                    Text("Timer entries need at least 1 minute before saving.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.mist)
                } else if timerNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Add a short description for your records.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.mist)
                }
                Button {
                    saveTimerEntry()
                } label: {
                    Text("Save Entry")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(canSaveTimer ? AppColors.onAction : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canSaveTimer ? colors.action : AppColors.mist)
                        .clipShape(Capsule())
                }
                .buttonStyle(.lhPressable)
                .disabled(!canSaveTimer)

                Button {
                    discardTimerEntry()
                } label: {
                    Text("Discard")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.slate)
                }
                .buttonStyle(.lhPressable)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Tiimo-Style Clock Ring

    private func clockRingView(progress: Double, isActive: Bool) -> some View {
        let ringDiameter: CGFloat = 220
        let strokeWidth: CGFloat = 22
        let ringRadius: CGFloat = ringDiameter / 2
        let innerEdge: CGFloat = ringRadius - strokeWidth / 2
        let tickOuter: CGFloat = innerEdge - 2
        let labelOffset: CGFloat = ringRadius + 16

        return ZStack {
            // Track ring (lavender)
            Circle()
                .stroke(
                    colors.primarySurface,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .frame(width: ringDiameter, height: ringDiameter)

            // Tick marks — 60 minute markers drawn in a single Canvas pass
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<60 {
                    let isMajor = i % 15 == 0
                    let isFive = i % 5 == 0
                    let h: CGFloat = isMajor ? 12 : (isFive ? 7 : 3)
                    let w: CGFloat = isMajor ? 2 : (isFive ? 1.5 : 1)
                    let opacity: CGFloat = isMajor ? 0.4 : (isFive ? 0.25 : 0.15)
                    let angle = Double(i) * .pi / 30 // 6° in radians
                    let sinA = CGFloat(sin(angle))
                    let cosA = CGFloat(cos(angle))
                    let outerPt = CGPoint(x: center.x + tickOuter * sinA, y: center.y - tickOuter * cosA)
                    let innerPt = CGPoint(x: center.x + (tickOuter - h) * sinA, y: center.y - (tickOuter - h) * cosA)
                    var path = Path()
                    path.move(to: outerPt)
                    path.addLine(to: innerPt)
                    context.stroke(path, with: .color(AppColors.slate.opacity(opacity)), lineWidth: w)
                }
            }
            .frame(width: ringDiameter + 64, height: ringDiameter + 64)
            .allowsHitTesting(false)

            // Progress ring
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryLight],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: ringDiameter, height: ringDiameter)
                    .shadow(color: AppColors.primary.opacity(0.25), radius: 8)
                    .lhMotion(AppAnimation.ringProgress, value: progress)
            }

            // Clock face labels
            Text("60")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colors.textTertiary)
                .offset(y: -labelOffset)
            Text("15")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colors.textTertiary)
                .offset(x: labelOffset)
            Text("30")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colors.textTertiary)
                .offset(y: labelOffset)
            Text("45")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colors.textTertiary)
                .offset(x: -labelOffset)

            // Center content
            VStack(spacing: 2) {
                if isActive && timerHours > 0 {
                    Text("\(timerHours)h")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.primary)
                }
                Text("\(isActive ? timerMinutesInHour : 0)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(isActive ? colors.textPrimary : colors.textTertiary)
                    .contentTransition(.numericText())
                Text("mins")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(isActive ? colors.textSecondary : colors.textTertiary)
            }
        }
        .frame(width: ringDiameter + 64, height: ringDiameter + 64)
    }

    // MARK: - Timer Category Chips

    private var timerCategoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityCategory.allCases, id: \.self) { cat in
                    Button {
                        animate(AppAnimation.quick) {
                            timerSelectedCategory = cat
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(timerSelectedCategory == cat ? AppColors.onAction.opacity(0.62) : cat.color)
                                .frame(width: 8, height: 8)
                            Text(cat.chipLabel)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(timerSelectedCategory == cat ? AppColors.onAction : colors.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(timerSelectedCategory == cat ? colors.action : colors.backgroundTertiary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    timerSelectedCategory == cat ? colors.action.opacity(0.55) : colors.border.opacity(0.35),
                                    lineWidth: 1.5
                                )
                        )
                    }
                    .buttonStyle(.lhPressable)
                    .lhMotion(AppAnimation.pillPop, value: timerSelectedCategory == cat)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Timer Property Picker

    private var timerPropertyPicker: some View {
        Menu {
            ForEach(viewModel.properties) { property in
                Button {
                    timerSelectedPropertyId = property.id
                } label: {
                    HStack {
                        Text(property.name)
                        if timerSelectedPropertyId == property.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(timerSelectedPropertyId != nil ? colors.primarySurface : AppColors.snow)
                    .frame(width: 28, height: 28)
                    .overlay(
                        LucideIcon(image: Lucide.house, size: 14)
                            .foregroundStyle(timerSelectedPropertyId != nil ? AppColors.primary : AppColors.mist)
                    )

                Text(selectedTimerPropertyName)
                    .font(.system(size: 15))
                    .foregroundStyle(timerSelectedPropertyId != nil ? colors.textPrimary : AppColors.mist)

                Spacer()

                LucideIcon(image: Lucide.chevronRight, size: 18)
                    .foregroundStyle(AppColors.cloud)
            }
            .padding(14)
            .padding(.horizontal, 2)
            .background(colors.background.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(AppColors.snow, lineWidth: 1.5)
            )
        }
    }

    // MARK: - Timer Helpers

    private var timerCanStart: Bool {
        let propId = viewModel.properties.count == 1 ? viewModel.properties[0].id : timerSelectedPropertyId
        return propId != nil && !viewModel.isTimerRunning
    }

    private var canSaveTimer: Bool {
        stoppedElapsed >= minimumSavableTimerElapsed &&
        !timerNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedTimerPropertyName: String {
        if let id = timerSelectedPropertyId,
           let property = viewModel.properties.first(where: { $0.id == id }) {
            return property.name
        }
        return "Select property"
    }

    private var timerPropertyName: String {
        guard let id = viewModel.timerPropertyId,
              let property = viewModel.properties.first(where: { $0.id == id }) else {
            return "Unknown"
        }
        return property.name
    }

    private var stoppedPropertyDisplayName: String {
        guard let id = stoppedPropertyId,
              let property = viewModel.properties.first(where: { $0.id == id }) else {
            return "Unknown"
        }
        return property.name
    }

    private var timerHours: Int {
        Int(timerElapsed) / 3600
    }

    private var timerMinutesInHour: Int {
        (Int(timerElapsed) % 3600) / 60
    }

    private var ringProgress: Double {
        let totalSeconds = timerElapsed
        if totalSeconds <= 0 { return 0 }
        // Ring fills once per hour matching the clock face, then resets
        let secondsInHour = totalSeconds.truncatingRemainder(dividingBy: 3600)
        return secondsInHour == 0 && totalSeconds > 0 ? 1.0 : secondsInHour / 3600.0
    }

    private func startTimerAction() {
        let propId = viewModel.properties.count == 1 ? viewModel.properties[0].id : timerSelectedPropertyId
        guard let propId else { return }
        viewModel.startTimer(propertyId: propId, category: timerSelectedCategory)
        timerPhase = .running
        timerElapsed = 0
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Captures all timer data locally, then actually stops the ViewModel timer.
    /// This ensures the floating banner disappears and the timer is truly stopped.
    private func stopTimerAction() {
        // Check if the raw elapsed time exceeds 24 hours before capping
        let rawElapsed = viewModel.timerStartTime.map { Date().timeIntervalSince($0) } ?? 0
        stoppedElapsed = viewModel.timerElapsedTime // Already capped at 24h
        stoppedPropertyId = viewModel.timerPropertyId
        stoppedCategory = viewModel.timerCategory
        stoppedStartDate = viewModel.timerStartTime ?? Date()
        saveStoppedTimerDraft()

        if rawElapsed > 24 * 3600 {
            showTimerCappedAlert = true
        }

        // Actually stop the ViewModel timer (clears floating banner, persisted state, etc.)
        viewModel.cancelTimer()

        timerPhase = .finishing
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func saveTimerEntry() {
        guard let propertyId = stoppedPropertyId else { return }
        let hours = stoppedElapsed / 3600.0

        viewModel.addTimeEntry(
            propertyId: propertyId,
            participant: timerParticipant,
            category: stoppedCategory,
            hours: hours,
            date: stoppedStartDate,
            notes: timerNotes
        )

        resetTimerState()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        animate(AppAnimation.reveal) { showingSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            animate(AppAnimation.reveal) { showingSaved = false }
        }
    }

    private func discardTimerEntry() {
        resetTimerState()
    }

    private func resetTimerState() {
        clearStoppedTimerDraft()
        timerNotes = ""
        timerParticipant = .selfParticipant
        timerPhase = .idle
        timerElapsed = 0
        stoppedElapsed = 0
        stoppedPropertyId = nil
        stoppedCategory = .management
        stoppedStartDate = Date()
    }

    private func saveStoppedTimerDraft() {
        guard let propertyId = stoppedPropertyId else { return }
        let draft = StoppedTimerDraft(
            elapsed: stoppedElapsed,
            propertyId: propertyId,
            category: stoppedCategory,
            startDate: stoppedStartDate,
            participant: timerParticipant,
            notes: timerNotes
        )
        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: stoppedTimerDraftKey)
        }
    }

    @discardableResult
    private func loadStoppedTimerDraft() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: stoppedTimerDraftKey),
              let draft = try? JSONDecoder().decode(StoppedTimerDraft.self, from: data),
              viewModel.properties.contains(where: { $0.id == draft.propertyId }) else {
            clearStoppedTimerDraft()
            return false
        }

        stoppedElapsed = draft.elapsed
        stoppedPropertyId = draft.propertyId
        stoppedCategory = draft.category
        stoppedStartDate = draft.startDate
        timerParticipant = draft.participant
        timerNotes = draft.notes
        return true
    }

    private func clearStoppedTimerDraft() {
        UserDefaults.standard.removeObject(forKey: stoppedTimerDraftKey)
    }
}

private struct StoppedTimerDraft: Codable {
    let elapsed: TimeInterval
    let propertyId: UUID
    let category: ActivityCategory
    let startDate: Date
    let participant: Participant
    let notes: String
}

// MARK: - Quick Stat Badge (used by ReportsView)
struct QuickStatBadge: View {
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    let title: String
    let value: String
    let icon: UIImage
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            LucideIcon(image: icon, size: 16)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)
            Text(title)
                .font(AppTypography.label)
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
    }
}

// MARK: - Quick Log Entry View (Sheet — used by CategoryPickerSheet)
struct QuickLogEntryView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var customCategory: CustomCategory?

    @State private var selectedPropertyId: UUID?
    @State private var hours: Double = 1.0
    @State private var notes: String = ""
    @State private var date = Date()
    @State private var selectedCategory: ActivityCategory = .management
    @State private var selectedParticipant: Participant = .selfParticipant

    init(customCategory: CustomCategory? = nil) {
        self.customCategory = customCategory
        if let name = customCategory?.name,
           let matched = ActivityCategory.allCases.first(where: { $0.rawValue == name }) {
            _selectedCategory = State(initialValue: matched)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    inputCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background { LHMobileCanvas() }
            .navigationTitle(customCategory?.name ?? "Quick Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEntry() }
                        .disabled(effectivePropertyId == nil)
                }
            }
            .onAppear {
                if viewModel.properties.count == 1 {
                    selectedPropertyId = viewModel.properties[0].id
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(customCategory?.name ?? "Quick log")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)
            Text("Add a focused entry without leaving the category flow.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(colors.textSecondary)
        }
    }

    private var inputCard: some View {
        VStack(spacing: 14) {
            Picker("Category", selection: $selectedCategory) {
                ForEach(ActivityCategory.allCases, id: \.self) { cat in
                    Text(cat.rawValue).tag(cat)
                }
            }
            .pickerStyle(.menu)

            propertyPickerRow

            Picker("Participant", selection: $selectedParticipant) {
                Text("Self").tag(Participant.selfParticipant)
                Text("Spouse").tag(Participant.spouse)
            }
            .pickerStyle(.segmented)

            Stepper(value: $hours, in: 0.25...24, step: 0.25) {
                HStack {
                    Text("Hours")
                        .foregroundStyle(colors.textSecondary)
                    Spacer()
                    Text(String(format: "%.1f hours", hours))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                }
            }

            DatePicker("Date", selection: $date, displayedComponents: .date)
                .foregroundStyle(colors.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                TextEditor(text: $notes)
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
            }
        }
        .padding(18)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xxl))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.xxl)
                .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var propertyPickerRow: some View {
        if viewModel.properties.isEmpty {
            Text("No properties added")
                .font(AppTypography.body)
                .foregroundStyle(colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if viewModel.properties.count == 1 {
            HStack(spacing: 10) {
                LHIconTile(icon: Lucide.house, color: AppColors.sage, wash: colors.sageWash, size: 34, isActive: true)
                Text(viewModel.properties[0].name)
                    .font(AppTypography.body)
                    .foregroundStyle(colors.textPrimary)
                Spacer()
            }
        } else {
            Picker("Property", selection: $selectedPropertyId) {
                Text("Select a property").tag(nil as UUID?)
                ForEach(viewModel.properties) { property in
                    Text(property.name).tag(property.id as UUID?)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var effectivePropertyId: UUID? {
        if viewModel.properties.count == 1 { return viewModel.properties[0].id }
        return selectedPropertyId
    }

    func saveEntry() {
        guard let propertyId = effectivePropertyId else { return }
        viewModel.addTimeEntry(
            propertyId: propertyId,
            participant: selectedParticipant,
            category: selectedCategory,
            hours: hours,
            date: date,
            notes: notes
        )
        dismiss()
    }
}

#Preview {
    TimeLogView()
        .environmentObject(AppViewModel())
        .environmentObject(CategoryManager.shared)
}
