import SwiftUI
import PhotosUI

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

    // Quick log state
    @State private var selectedCustomCategory: CustomCategory?
    @State private var showingQuickLog = false

    // AI state
    @State private var showingAIEntry = false
    @State private var aiInput: String = ""
    @State private var isProcessingAI: Bool = false
    @State private var showingAIResult = false
    @State private var aiParsedEntry: ParsedTimeEntry?
    @State private var aiErrorMessage: String?

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
            .alert("Could not parse entry", isPresented: .init(
                get: { aiErrorMessage != nil },
                set: { if !$0 { aiErrorMessage = nil } }
            )) {
                Button("OK") { aiErrorMessage = nil }
            } message: {
                Text(aiErrorMessage ?? "")
            }
            .sheet(isPresented: $showingAIResult) {
                if let parsed = aiParsedEntry {
                    AIEntryReviewView(parsed: parsed) { entry in
                        viewModel.addTimeEntry(
                            propertyId: entry.property?.id ?? viewModel.properties.first?.id ?? UUID(),
                            participant: entry.participant,
                            category: entry.category,
                            hours: entry.hours,
                            date: Date(),
                            notes: entry.notes
                        )
                        aiInput = ""
                        aiParsedEntry = nil
                    }
                }
            }
            .sheet(isPresented: $showingAIEntry) {
                AIInputSheet(isPresented: $showingAIEntry) { text in
                    processAIInput(text)
                }
            }
            .sheet(isPresented: $showingQuickLog) {
                if let category = selectedCustomCategory {
                    QuickLogEntryView(customCategory: category)
                }
            }
        }
        .onAppear {
            if viewModel.properties.count == 1 {
                entryPropertyId = viewModel.properties[0].id
            }
        }
    }

    // MARK: - Main Scroll Content
    private var mainScrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                headerSection
                statsStrip
                mainEntryCard
                quickLogSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(colors.background)
        .overlay(alignment: .bottom) {
            if showingSaved {
                savedBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showingSaved)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Track Time")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(colors.textPrimary)
                Text(Date(), style: .date)
                    .font(.system(size: 14))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Stats Strip
    private var statsStrip: some View {
        HStack(spacing: 12) {
            TodayStatChip(label: "Today", value: String(format: "%.1fh", todayHours))
            TodayStatChip(label: "This Week", value: String(format: "%.1fh", weeklyHours))
            TodayStatChip(label: "This Month", value: String(format: "%.1fh", monthlyHours))
        }
    }

    // MARK: - Main Entry Card
    private var mainEntryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(systemIcon: "plus.circle", text: "LOG TIME")

            VStack(spacing: 0) {
                // Freeform text area
                ZStack(alignment: .topLeading) {
                    if entryNotes.isEmpty {
                        Text("What did you work on?")
                            .foregroundStyle(colors.textTertiary)
                            .font(.system(size: 16))
                            .padding(.top, 16)
                            .padding(.leading, 16)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $entryNotes)
                        .frame(minHeight: 80, maxHeight: 120)
                        .font(.system(size: 16))
                        .foregroundStyle(colors.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .background(colors.background)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // Category chips
                categoryChipsSection
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                Divider().padding(.horizontal, 16)

                // Property row (only if multiple properties)
                if viewModel.properties.count > 1 {
                    propertyRow
                    Divider().padding(.leading, 52)
                }

                hoursRow
                Divider().padding(.leading, 52)

                dateRow
                Divider().padding(.leading, 52)

                participantRow

                Divider().padding(.horizontal, 16)

                bottomActionRow
            }
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Category Chips
    private var categoryChipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ActivityCategory.allCases, id: \.self) { cat in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                entryCategory = cat
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 11, weight: .medium))
                                Text(cat.rawValue)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                if !cat.countsForREPS {
                                    Text("non-REPS")
                                        .font(.system(size: 9))
                                        .opacity(0.8)
                                }
                            }
                            .foregroundStyle(entryCategory == cat ? .white : colors.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(entryCategory == cat ? AppColors.primary : colors.backgroundTertiary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Form Rows
    private var propertyRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "house")
                .font(.system(size: 16))
                .foregroundStyle(AppColors.primary)
                .frame(width: 24)

            Picker("Property", selection: $entryPropertyId) {
                Text("Select property").tag(nil as UUID?)
                ForEach(viewModel.properties) { p in
                    Text(p.name).tag(p.id as UUID?)
                }
            }
            .tint(colors.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var hoursRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "clock")
                .font(.system(size: 16))
                .foregroundStyle(AppColors.primary)
                .frame(width: 24)

            Text("Hours")
                .font(.system(size: 15))
                .foregroundStyle(colors.textPrimary)

            Spacer()

            HStack(spacing: 18) {
                Button {
                    if entryHours > 0.25 { entryHours -= 0.25 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(colors.textTertiary)
                }
                .buttonStyle(.plain)

                Text(entryHours.formatted(.number.precision(.fractionLength(0...2))) + "h")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                    .frame(minWidth: 44, alignment: .center)

                Button {
                    if entryHours < 24 { entryHours += 0.25 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(AppColors.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var dateRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar")
                .font(.system(size: 16))
                .foregroundStyle(AppColors.primary)
                .frame(width: 24)

            DatePicker("Date", selection: $entryDate, displayedComponents: .date)
                .tint(AppColors.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var participantRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "person")
                .font(.system(size: 16))
                .foregroundStyle(AppColors.primary)
                .frame(width: 24)

            Text("For")
                .font(.system(size: 15))
                .foregroundStyle(colors.textPrimary)

            Spacer()

            Picker("Participant", selection: $entryParticipant) {
                Text("Self").tag(Participant.selfParticipant)
                Text("Spouse").tag(Participant.spouse)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var bottomActionRow: some View {
        HStack(spacing: 10) {
            // Photo attachment
            PhotosPicker(
                selection: $entryPhotoItems,
                maxSelectionCount: 5,
                matching: .images
            ) {
                HStack(spacing: 6) {
                    Image(systemName: entryAttachments.isEmpty ? "paperclip" : "paperclip.badge.ellipsis")
                        .font(.system(size: 15))
                    if !entryAttachments.isEmpty {
                        Text("\(entryAttachments.count)")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .foregroundStyle(entryAttachments.isEmpty ? colors.textSecondary : AppColors.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(colors.backgroundTertiary)
                .clipShape(Capsule())
            }
            .onChange(of: entryPhotoItems) { _, newItems in
                Task { await loadPhotos(from: newItems) }
            }

            // AI assist button
            Button {
                showingAIEntry = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                    Text("AI")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(AppColors.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(AppColors.primarySurface)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            // Log Time — black pill (Tiimo style)
            Button {
                saveMainEntry()
            } label: {
                Text("Log Time")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(effectivePropertyId == nil ? Color(hex: "CCCCCC") : Color(hex: "1A1A1A"))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(effectivePropertyId == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Quick Log Section
    private var quickLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(systemIcon: "bolt", text: "QUICK LOG")

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(categoryManager.allCategories) { category in
                    CategoryGridButton(
                        icon: category.iconName,
                        title: category.name,
                        color: Color(hex: category.colorHex)
                    ) {
                        selectedCustomCategory = category
                        showingQuickLog = true
                    }
                }
            }
        }
    }

    // MARK: - Saved Banner
    private var savedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)
            Text("Time logged!")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(hex: "1A1A1A"))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }

    // MARK: - Section Label Helper
    private func sectionLabel(systemIcon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemIcon)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
        }
        .foregroundStyle(colors.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(colors.backgroundTertiary)
        .clipShape(Capsule())
    }

    // MARK: - Helpers
    private var effectivePropertyId: UUID? {
        if viewModel.properties.count == 1 { return viewModel.properties[0].id }
        return entryPropertyId
    }

    private func saveMainEntry() {
        guard let propId = effectivePropertyId else { return }
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
        entryAttachments = []
        entryPhotoItems = []
        withAnimation(.spring(response: 0.4)) { showingSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showingSaved = false }
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

    private func processAIInput(_ text: String) {
        Task {
            isProcessingAI = true
            aiParsedEntry = await AITimeEntryService.shared.parseTimeEntry(
                from: text,
                properties: viewModel.properties
            )
            isProcessingAI = false
            if aiParsedEntry != nil {
                showingAIResult = true
            } else {
                aiErrorMessage = "Couldn't understand that. Try: '2 hours fixing the kitchen sink at Oak St'"
            }
        }
    }

    // MARK: - Computed Hours
    private var todayHours: Double {
        let today = Calendar.current.startOfDay(for: Date())
        return viewModel.timeEntries
            .filter { Calendar.current.isDate($0.date, inSameDayAs: today) && $0.countsForREPS }
            .reduce(0) { $0 + $1.hours }
    }

    private var weeklyHours: Double {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else { return 0 }
        return viewModel.timeEntries.filter { $0.date >= start && $0.countsForREPS }.reduce(0) { $0 + $1.hours }
    }

    private var monthlyHours: Double {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: Date())) else { return 0 }
        return viewModel.timeEntries.filter { $0.date >= start && $0.countsForREPS }.reduce(0) { $0 + $1.hours }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppColors.primarySurface)
                    .frame(width: 100, height: 100)
                Image(systemName: "house")
                    .font(.system(size: 36))
                    .foregroundStyle(AppColors.primary)
            }
            Text("Add a Property First")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(colors.textPrimary)
            Text("You need at least one property\nbefore logging time")
                .font(.system(size: 15))
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.background)
    }
}

// MARK: - Today Stat Chip (Tiimo-style)
struct TodayStatChip: View {
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(colors.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Category Grid Button (Tiimo-style)
struct CategoryGridButton: View {
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                DynamicBadgeView(iconName: icon, bgColor: color, fgColor: .white, size: 52, iconScale: 0.42)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 8)
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Stat Badge (used by ReportsView)
struct QuickStatBadge: View {
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            DynamicIconView(name: icon, size: 16, color: color)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(colors.textPrimary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - AI Input Sheet
struct AIInputSheet: View {
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var text: String = ""
    @State private var isProcessing: Bool = false
    let onSubmit: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(AppColors.primary)
                        Text("AI Time Entry")
                            .font(.system(size: 22, weight: .bold))
                    }
                    Text("Describe what you worked on in plain English. AI will parse the category, hours, and property.")
                        .font(.system(size: 14))
                        .foregroundStyle(colors.textSecondary)
                        .lineSpacing(3)
                }

                // Examples
                VStack(alignment: .leading, spacing: 6) {
                    Text("EXAMPLES")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(colors.textSecondary)

                    ForEach([
                        "Fixed the leaky faucet at Oak St for 2.5 hours",
                        "Met with new tenant at Main Ave, 1 hour leasing",
                        "Wife did bookkeeping for both properties, 3 hours"
                    ], id: \.self) { example in
                        Button {
                            text = example
                        } label: {
                            Text(example)
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppColors.primarySurface)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Text input
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Type your entry here...")
                            .foregroundStyle(colors.textTertiary)
                            .font(.system(size: 15))
                            .padding(.top, 14)
                            .padding(.leading, 14)
                    }
                    TextEditor(text: $text)
                        .frame(height: 100)
                        .font(.system(size: 15))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                }
                .background(colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer()

                // Submit button
                Button {
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    isProcessing = true
                    onSubmit(text)
                    isPresented = false
                } label: {
                    HStack(spacing: 8) {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isProcessing ? "Processing..." : "Parse with AI →")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color(hex: "CCCCCC") : Color(hex: "1A1A1A"))
                    .clipShape(Capsule())
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(24)
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
    }
}

// MARK: - Quick Log Entry View (Sheet)
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
                            Image(systemName: "house")
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
                        Text(String(format: "%.2gh hours", hours))
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

// MARK: - AI Entry Review View
struct AIEntryReviewView: View {
    @Environment(\.dismiss) var dismiss
    let parsed: ParsedTimeEntry
    let onSave: (ParsedTimeEntry) -> Void

    @State private var hours: Double
    @State private var selectedProperty: RentalProperty?
    @State private var selectedCategory: ActivityCategory
    @State private var selectedParticipant: Participant
    @State private var notes: String

    init(parsed: ParsedTimeEntry, onSave: @escaping (ParsedTimeEntry) -> Void) {
        self.parsed = parsed
        self.onSave = onSave
        _hours = State(initialValue: parsed.hours)
        _selectedProperty = State(initialValue: parsed.property)
        _selectedCategory = State(initialValue: parsed.category)
        _selectedParticipant = State(initialValue: parsed.participant)
        _notes = State(initialValue: parsed.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(AppColors.primary)
                        Text("Review the AI suggestion and adjust if needed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("AI Suggestion")
                }

                Section("Property") {
                    if let property = selectedProperty {
                        HStack {
                            Image(systemName: "house")
                                .foregroundStyle(AppColors.primary)
                            Text(property.name)
                        }
                    } else {
                        Text("No property matched — please select manually")
                            .foregroundStyle(.red)
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(ActivityCategory.allCases, id: \.self) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                }

                Section("Hours") {
                    Stepper(value: $hours, in: 0.25...24, step: 0.25) {
                        Text(String(format: "%.2g hours", hours))
                    }
                }

                Section("Participant") {
                    Picker("Participant", selection: $selectedParticipant) {
                        Text("Self").tag(Participant.selfParticipant)
                        Text("Spouse").tag(Participant.spouse)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Notes") {
                    TextField("Notes", text: $notes)
                }
            }
            .navigationTitle("Confirm Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let entry = ParsedTimeEntry(
                            property: selectedProperty,
                            category: selectedCategory,
                            hours: hours,
                            participant: selectedParticipant,
                            notes: notes
                        )
                        onSave(entry)
                        dismiss()
                    }
                    .disabled(selectedProperty == nil)
                }
            }
        }
    }
}

#Preview {
    TimeLogView()
        .environmentObject(AppViewModel())
        .environmentObject(CategoryManager.shared)
}
