import SwiftUI
import PhotosUI
import LucideIcons

struct TimeLogView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var categoryManager: CategoryManager
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

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
    @FocusState private var isTimerNotesFocused: Bool
    private let timerTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Inline AI state
    @State private var isProcessingAI: Bool = false
    @State private var aiParsedEntry: ParsedTimeEntry?
    @State private var aiAutoFilled: Bool = false
    @State private var aiDebounceTask: Task<Void, Never>?

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
        .alert("Timer Capped", isPresented: $showTimerCappedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your timer was running for over 24 hours. The entry has been capped at 24 hours.")
        }
    }

    // MARK: - Main Scroll Content
    private var mainScrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                headerSection
                if trackMode == .log {
                    mainEntryCard
                } else {
                    timerCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(colors.background)
        .onTapGesture {
            isNotesFocused = false
            isTimerNotesFocused = false
        }
        .overlay(alignment: .bottom) {
            if showingSaved {
                savedBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(AppAnimation.smooth, value: showingSaved)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Track Time")
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundStyle(colors.textPrimary)
                    Text(Date(), style: .date)
                        .font(AppTypography.caption)
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
            }
            modeToggle
        }
        .padding(.top, 4)
    }

    // MARK: - Main Entry Card
    private var mainEntryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Notes textarea
            notesSection

            // AI state: hint, suggestion bar, or auto-filled confirmation
            aiStateSection

            // Category
            fieldLabel("Category")
                .padding(.horizontal, 20)
            categoryChipsSection
                .padding(.bottom, 20)

            // Property
            if viewModel.properties.count > 1 {
                fieldLabel("Property")
                    .padding(.horizontal, 20)
                propertyPickerRow
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }

            // Hours
            fieldLabel("Hours")
                .padding(.horizontal, 20)
            hoursStepperRow
                .padding(.bottom, 20)

            // Date
            fieldLabel("Date")
                .padding(.horizontal, 20)
            datePickerRow
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            // Participant
            fieldLabel("Participant")
                .padding(.horizontal, 20)
            participantSegment
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            // Attach
            attachButton
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            // Log Time
            logTimeButton
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 16, x: 0, y: 4)
    }

    // MARK: - Field Label
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(colors.textSecondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.bottom, 10)
    }

    // MARK: - Notes Section
    private var notesSection: some View {
        ZStack(alignment: .topLeading) {
            if entryNotes.isEmpty {
                Text("What did you work on?")
                    .foregroundStyle(colors.textTertiary)
                    .font(.system(size: 15))
                    .padding(.top, 34)
                    .padding(.leading, 32)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $entryNotes)
                .focused($isNotesFocused)
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
                            isNotesFocused = false
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.primary)
                    }
                }
        }
        .padding(4)
        .background(colors.background.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    notesBorderColor,
                    lineWidth: 1.5
                )
        )
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .onChange(of: entryNotes) { _, newValue in
            handleNotesChange(newValue)
        }
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
            } else {
                // State 1: AI hint — show until notes are long enough to trigger AI
                let trimmed = entryNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count < 10 {
                    aiHint(hasStartedTyping: !entryNotes.isEmpty)
                }
            }
        }
    }

    // State 1: AI Hint
    private func aiHint(hasStartedTyping: Bool) -> some View {
        HStack(spacing: 8) {
            // AI sparkle badge
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.primary.opacity(0.12))
                .frame(width: 24, height: 24)
                .overlay(
                    LucideIcon(image: Lucide.sparkles, size: 12)
                        .foregroundStyle(AppColors.primary)
                )
            Text(hasStartedTyping
                 ? "Keep typing — AI will auto-detect category, property & hours"
                 : "Describe your work and AI will fill in the details")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.mist)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .animation(.easeInOut(duration: 0.2), value: hasStartedTyping)
    }

    // AI Processing
    private var aiProcessingIndicator: some View {
        HStack(spacing: 10) {
            // AI sparkle badge
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.primary)
                .frame(width: 24, height: 24)
                .overlay(
                    LucideIcon(image: Lucide.sparkles, size: 12)
                        .foregroundStyle(.white)
                )
            Text("Analyzing your description...")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.primary)
            Spacer()
            ProgressView()
                .scaleEffect(0.7)
                .tint(AppColors.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(colors.primarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // State 2: AI Suggestion Bar
    private func aiSuggestionBar(parsed: ParsedTimeEntry) -> some View {
        HStack(spacing: 10) {
            // Sparkle badge
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.primary)
                .frame(width: 28, height: 28)
                .overlay(
                    LucideIcon(image: Lucide.sparkles, size: 14)
                        .foregroundStyle(.white)
                )

            // Body: "We detected:" + chips
            VStack(alignment: .leading, spacing: 6) {
                Text("We detected:")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.textSecondary)

                // Detected chips
                HStack(spacing: 6) {
                    // Category chip
                    aiDetectedChip(
                        dotColor: categoryDotColor(for: parsed.category),
                        text: categoryChipLabel(for: parsed.category)
                    )

                    // Property chip
                    if let property = parsed.property {
                        aiDetectedChip(dotColor: nil, text: property.name, icon: "🏠")
                    }

                    // Hours chip
                    aiDetectedChip(
                        dotColor: nil,
                        text: "\(parsed.hours.formatted(.number.precision(.fractionLength(0...1))))h"
                    )
                }
            }

            Spacer(minLength: 0)

            // Auto-fill button
            Button {
                applyAutoFill(parsed)
            } label: {
                Text("Auto-fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(colors.primarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppColors.primaryLight, lineWidth: 1.5)
        )
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .transition(.opacity.combined(with: .move(edge: .top)))
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
            Text("Auto-filled from your description")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.sage)
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
                        withAnimation(AppAnimation.quick) {
                            entryCategory = cat
                        }
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
                        .foregroundStyle(entryCategory == cat ? .white : AppColors.slate)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(entryCategory == cat ? AppColors.primary : AppColors.snow)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    entryCategory == cat ? AppColors.primary : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(
                            color: entryCategory == cat ? AppColors.primary.opacity(0.3) : .clear,
                            radius: 6,
                            y: 3
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(AppAnimation.pillPop, value: entryCategory == cat)
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
                    entryPropertyId = property.id
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
                RoundedRectangle(cornerRadius: 8)
                    .fill(entryPropertyId != nil ? colors.primarySurface : AppColors.snow)
                    .frame(width: 28, height: 28)
                    .overlay(
                        LucideIcon(image: Lucide.house, size: 14)
                            .foregroundStyle(entryPropertyId != nil ? AppColors.primary : AppColors.mist)
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
        HStack(spacing: 24) {
            Spacer()

            Button {
                if entryHours > 0.25 {
                    withAnimation(AppAnimation.quick) { entryHours -= 0.25 }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } label: {
                LucideIcon(image: Lucide.minus, size: 16)
                    .foregroundStyle(colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(colors.backgroundSecondary)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(AppColors.snow, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
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
                    withAnimation(AppAnimation.quick) { entryHours += 0.25 }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } label: {
                LucideIcon(image: Lucide.plus, size: 16)
                    .foregroundStyle(colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(colors.backgroundSecondary)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(AppColors.snow, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase hours")
            .accessibilityHint("Increases by 15 minutes")

            Spacer()
        }
    }

    // MARK: - Date Picker Row
    private var datePickerRow: some View {
        HStack(spacing: 10) {
            // Calendar icon badge
            RoundedRectangle(cornerRadius: 8)
                .fill(colors.primarySurface)
                .frame(width: 28, height: 28)
                .overlay(
                    LucideIcon(image: Lucide.calendar, size: 14)
                        .foregroundStyle(AppColors.primary)
                )

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
                .strokeBorder(AppColors.snow, lineWidth: 1.5)
        )
    }

    // MARK: - Participant Segment
    private var participantSegment: some View {
        HStack(spacing: 0) {
            segmentButton("Self", isSelected: entryParticipant == .selfParticipant) {
                withAnimation(AppAnimation.quick) { entryParticipant = .selfParticipant }
            }
            segmentButton("Spouse", isSelected: entryParticipant == .spouse) {
                withAnimation(AppAnimation.quick) { entryParticipant = .spouse }
            }
        }
        .padding(3)
        .background(AppColors.snow)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func segmentButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? colors.textPrimary : AppColors.slate)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? colors.backgroundSecondary : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: isSelected ? .black.opacity(0.06) : .clear, radius: 4, y: 1)
        }
        .buttonStyle(.plain)
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
            .background(AppColors.snow)
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
            if effectivePropertyId != nil && entryNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Add a description for IRS records")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.mist)
            }
            Button {
                saveMainEntry()
            } label: {
                Text("Log Time")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(canSave ? AppColors.primary : AppColors.mist)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
    }

    // MARK: - Saved Banner
    private var savedBanner: some View {
        HStack(spacing: 10) {
            LucideIcon(image: Lucide.circleCheck, size: 18)
                .foregroundStyle(.white)
            Text("Time logged!")
                .font(AppTypography.button)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppColors.sage)
        .clipShape(Capsule())
        .shadow(color: AppColors.sage.opacity(0.3), radius: 12, y: 4)
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
            return AppColors.primaryLight // AI has suggestion ready
        }
        if isProcessingAI {
            return AppColors.primaryLight.opacity(0.6) // AI analyzing
        }
        if isNotesFocused && !entryNotes.isEmpty {
            return AppColors.primary.opacity(0.3) // Typing, AI will activate
        }
        return AppColors.snow // Default
    }

    private var effectivePropertyId: UUID? {
        if viewModel.properties.count == 1 { return viewModel.properties[0].id }
        return entryPropertyId
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
        entryAttachments = []
        entryPhotoItems = []
        aiParsedEntry = nil
        aiAutoFilled = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.4)) { showingSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showingSaved = false }
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
        aiAutoFilled = false
        aiParsedEntry = nil

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    withAnimation(AppAnimation.smooth) {
                        aiParsedEntry = result
                    }
                }
            }
        }
    }

    private func applyAutoFill(_ parsed: ParsedTimeEntry) {
        withAnimation(AppAnimation.smooth) {
            entryCategory = parsed.category
            entryHours = parsed.hours
            entryParticipant = parsed.participant
            if let property = parsed.property {
                entryPropertyId = property.id
            }
            aiAutoFilled = true
            aiParsedEntry = nil
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            JellyBadge(
                systemName: "house",
                color: AppColors.primary,
                wash: colors.primarySurface,
                size: 72
            )
            Text("Add a Property First")
                .font(AppTypography.subheadline)
                .foregroundStyle(colors.textPrimary)
            Text("You need at least one property\nbefore logging time")
                .font(AppTypography.body)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            AuroraBackground()
        }
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            modeButton(.log)
            modeButton(.timer)
        }
        .padding(3)
        .background(AppColors.snow)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(AppAnimation.quick, value: trackMode) // animate the pill highlight only
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
            .padding(.vertical, 10)
            .background(trackMode == mode ? colors.backgroundSecondary : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: trackMode == mode ? .black.opacity(0.06) : .clear, radius: 4, y: 1)
        }
        .buttonStyle(.plain)
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
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 16, x: 0, y: 4)
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
                        .font(.system(size: 17, weight: .semibold))
                    LucideIcon(image: Lucide.play, size: 16)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 36)
                .padding(.vertical, 14)
                .background(timerCanStart ? AppColors.charcoal : AppColors.mist)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
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
                    viewModel.cancelTimer()
                    timerPhase = .idle
                    timerElapsed = 0
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.slate)
                }
                .buttonStyle(.plain)

                Button {
                    stopTimerAction()
                } label: {
                    HStack(spacing: 10) {
                        Text("Stop")
                            .font(.system(size: 17, weight: .semibold))
                        LucideIcon(image: Lucide.square, size: 14)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 14)
                    .background(AppColors.coral)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
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
                    .strokeBorder(AppColors.snow, lineWidth: 1.5)
            )
            .padding(.horizontal, 20)

            // Participant
            fieldLabel("Participant")
                .padding(.horizontal, 20)
            HStack(spacing: 0) {
                segmentButton("Self", isSelected: timerParticipant == .selfParticipant) {
                    withAnimation(AppAnimation.quick) { timerParticipant = .selfParticipant }
                }
                segmentButton("Spouse", isSelected: timerParticipant == .spouse) {
                    withAnimation(AppAnimation.quick) { timerParticipant = .spouse }
                }
            }
            .padding(3)
            .background(AppColors.snow)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)

            // Save / Discard
            VStack(spacing: 10) {
                if timerNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Add a description for IRS records")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.mist)
                }
                Button {
                    saveTimerEntry()
                } label: {
                    Text("Save Entry")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canSaveTimer ? AppColors.primary : AppColors.mist)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSaveTimer)

                Button {
                    discardTimerEntry()
                } label: {
                    Text("Discard")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.slate)
                }
                .buttonStyle(.plain)
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
                    .animation(.spring(response: 0.8, dampingFraction: 0.75), value: progress)
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
                Text("MINS")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(2)
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
                        withAnimation(AppAnimation.quick) {
                            timerSelectedCategory = cat
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(timerSelectedCategory == cat
                                      ? Color.white.opacity(0.5)
                                      : cat.color)
                                .frame(width: 8, height: 8)
                            Text(cat.chipLabel)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(timerSelectedCategory == cat ? .white : AppColors.slate)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(timerSelectedCategory == cat ? AppColors.primary : AppColors.snow)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    timerSelectedCategory == cat ? AppColors.primary : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(
                            color: timerSelectedCategory == cat ? AppColors.primary.opacity(0.3) : .clear,
                            radius: 6,
                            y: 3
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(AppAnimation.pillPop, value: timerSelectedCategory == cat)
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
        withAnimation(.spring(response: 0.4)) { showingSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showingSaved = false }
        }
    }

    private func discardTimerEntry() {
        resetTimerState()
    }

    private func resetTimerState() {
        timerNotes = ""
        timerParticipant = .selfParticipant
        timerPhase = .idle
        timerElapsed = 0
        stoppedElapsed = 0
        stoppedPropertyId = nil
        stoppedCategory = .management
        stoppedStartDate = Date()
    }
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
            Form {
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(ActivityCategory.allCases, id: \.self) { cat in
                            HStack {
                                Text(cat.rawValue)
                                if !cat.countsForREPS {
                                    Spacer()
                                    Text("Non-REPS")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .tag(cat)
                        }
                    }
                }

                Section("Property") {
                    if viewModel.properties.isEmpty {
                        Text("No properties added")
                            .foregroundStyle(.secondary)
                    } else if viewModel.properties.count == 1 {
                        HStack {
                            LucideIcon(image: Lucide.house, size: 16)
                                .foregroundStyle(AppColors.primary)
                            Text(viewModel.properties[0].name)
                        }
                    } else {
                        Picker("Select Property", selection: $selectedPropertyId) {
                            Text("Select a property").tag(nil as UUID?)
                            ForEach(viewModel.properties) { property in
                                Text(property.name).tag(property.id as UUID?)
                            }
                        }
                    }
                }

                Section("Participant") {
                    Picker("Participant", selection: $selectedParticipant) {
                        Text("Self").tag(Participant.selfParticipant)
                        Text("Spouse").tag(Participant.spouse)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Hours") {
                    Stepper(value: $hours, in: 0.25...24, step: 0.25) {
                        Text(String(format: "%.1f hours", hours))
                    }
                }

                Section("Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Notes (Optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
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
