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
                    .animation(AppAnimation.smooth, value: showingSaved)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Track Time")
                    .font(AppTypography.headline)
                    .foregroundStyle(colors.textPrimary)
                Text(Date(), style: .date)
                    .font(AppTypography.caption)
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Main Entry Card
    private var mainEntryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(lucideIcon: Lucide.circlePlus, text: "LOG TIME")

            VStack(spacing: 0) {
                // Freeform text area
                ZStack(alignment: .topLeading) {
                    if entryNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("What did you work on?")
                                .foregroundStyle(colors.textTertiary)
                                .font(.system(size: 16, design: .rounded))
                            HStack(spacing: 4) {
                                LucideIcon(image: Lucide.sparkles, size: 11)
                                Text("Describe your work and we'll fill in the details")
                                    .font(AppTypography.caption)
                            }
                            .foregroundStyle(AppColors.mist)
                        }
                        .padding(.top, 16)
                        .padding(.leading, 16)
                        .allowsHitTesting(false)
                    }
                    TextEditor(text: $entryNotes)
                        .frame(minHeight: 80, maxHeight: 120)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .background(colors.backgroundTertiary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                        .strokeBorder(
                            entryNotes.isEmpty ? colors.border.opacity(0.3) : AppColors.primaryLight.opacity(0.5),
                            lineWidth: 1.5
                        )
                )
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
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 16, x: 0, y: 4)
        }
    }

    // MARK: - Category Chips
    private var categoryChipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category")
                .font(AppTypography.caption)
                .foregroundStyle(colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 16)

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
                                    .strokeBorder(Color.clear, lineWidth: 1.5)
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
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    /// Returns a short chip label (not the full rawValue)
    private func categoryChipLabel(for cat: ActivityCategory) -> String {
        switch cat {
        case .repairs: return "Repairs"
        case .management: return "Management"
        case .leasing: return "Leasing"
        case .bookkeeping: return "Bookkeeping"
        case .legal: return "Legal"
        case .insurance: return "Insurance"
        case .travel: return "Travel"
        case .renovations: return "Renovations"
        case .investing: return "Investing"
        case .financing: return "Financing"
        case .contractNegotiation: return "Contracts"
        }
    }

    /// Returns the colored dot for each category, matching the HTML mockup
    private func categoryDotColor(for cat: ActivityCategory) -> Color {
        switch cat {
        case .repairs: return AppColors.coral
        case .management: return AppColors.sage
        case .leasing: return AppColors.sky
        case .bookkeeping: return AppColors.honey
        case .legal: return AppColors.rose
        case .insurance: return Color(hex: "8B7EC8")
        case .travel: return Color(hex: "E8A87C")
        case .renovations: return Color(hex: "7B8EC8")
        case .investing: return AppColors.mist
        case .financing: return AppColors.cloud
        case .contractNegotiation: return AppColors.slate
        }
    }

    // MARK: - Form Rows
    private var propertyRow: some View {
        HStack(spacing: 14) {
            LucideIcon(image: Lucide.house, size: 16)
                .foregroundStyle(AppColors.primary)
                .frame(width: 24)

            Picker("Property", selection: $entryPropertyId) {
                Text("Select property").tag(nil as UUID?)
                ForEach(viewModel.properties) { p in
                    Text(p.name).tag(p.id as UUID?)
                }
            }
            .tint(colors.textPrimary)
            .font(AppTypography.body)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var hoursRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hours")
                .font(AppTypography.caption)
                .foregroundStyle(colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 16)

            HStack(spacing: 24) {
                Spacer()

                Button {
                    if entryHours > 0.25 {
                        withAnimation(AppAnimation.quick) { entryHours -= 0.25 }
                    }
                } label: {
                    LucideIcon(image: Lucide.minus, size: 16)
                        .foregroundStyle(colors.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(colors.backgroundSecondary)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(colors.border, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)

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

                Button {
                    if entryHours < 24 {
                        withAnimation(AppAnimation.quick) { entryHours += 0.25 }
                    }
                } label: {
                    LucideIcon(image: Lucide.plus, size: 16)
                        .foregroundStyle(colors.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(colors.backgroundSecondary)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(colors.border, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.vertical, 10)
    }

    private var dateRow: some View {
        HStack(spacing: 14) {
            LucideIcon(image: Lucide.calendar, size: 16)
                .foregroundStyle(AppColors.sky)
                .frame(width: 24)

            DatePicker("Date", selection: $entryDate, displayedComponents: .date)
                .tint(AppColors.primary)
                .font(AppTypography.body)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var participantRow: some View {
        HStack(spacing: 14) {
            LucideIcon(image: Lucide.user, size: 16)
                .foregroundStyle(AppColors.sage)
                .frame(width: 24)

            Text("For")
                .font(AppTypography.body)
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
        VStack(spacing: 0) {
            // Attach receipt or document
            PhotosPicker(
                selection: $entryPhotoItems,
                maxSelectionCount: 5,
                matching: .images
            ) {
                HStack(spacing: 8) {
                    LucideIcon(image: Lucide.paperclip, size: 15)
                    Text(entryAttachments.isEmpty ? "Attach receipt or document" : "Attached (\(entryAttachments.count))")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(entryAttachments.isEmpty ? AppColors.slate : AppColors.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppColors.snow)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
            }
            .onChange(of: entryPhotoItems) { _, newItems in
                Task { await loadPhotos(from: newItems) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)

            // Log Time — full-width violet capsule
            Button {
                saveMainEntry()
            } label: {
                Text("Log Time")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(effectivePropertyId == nil ? AppColors.mist : AppColors.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(effectivePropertyId == nil)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Quick Log Section
    private var quickLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(lucideIcon: Lucide.bolt, text: "QUICK LOG")

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

    // MARK: - Section Label Helper
    private func sectionLabel(lucideIcon: UIImage, text: String) -> some View {
        HStack(spacing: 5) {
            LucideIcon(image: lucideIcon, size: 11)
            Text(text)
                .font(AppTypography.label)
                .tracking(1.5)
        }
        .foregroundStyle(colors.textSecondary)
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
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)
            Text(label)
                .font(AppTypography.label)
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.white.opacity(0.65)
        )
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.large)
                .fill(.ultraThinMaterial)
                .opacity(0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
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
                JellyBadge(
                    systemName: icon,
                    color: color,
                    wash: color.opacity(0.15),
                    size: 48
                )
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
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
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 8, x: 0, y: 2)
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
                    HStack(spacing: 10) {
                        JellyBadge(
                            systemName: "sparkles",
                            color: AppColors.primary,
                            wash: colors.primarySurface,
                            size: 36
                        )
                        Text("AI Time Entry")
                            .font(AppTypography.title2)
                            .foregroundStyle(colors.textPrimary)
                    }
                    Text("Describe what you worked on in plain English. AI will parse the category, hours, and property.")
                        .font(AppTypography.body)
                        .foregroundStyle(colors.textSecondary)
                        .lineSpacing(3)
                }

                // Examples
                VStack(alignment: .leading, spacing: 8) {
                    Text("EXAMPLES")
                        .font(AppTypography.label)
                        .tracking(1.5)
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
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(colors.primarySurface)
                                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Text input
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Type your entry here...")
                            .foregroundStyle(colors.textTertiary)
                            .font(AppTypography.body)
                            .padding(.top, 14)
                            .padding(.leading, 14)
                    }
                    TextEditor(text: $text)
                        .frame(height: 100)
                        .font(AppTypography.body)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                }
                .background(colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))

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
                            LucideIcon(image: Lucide.sparkles, size: 16)
                        }
                        Text(isProcessing ? "Processing..." : "Parse with AI")
                            .font(AppTypography.buttonLarge)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? AppColors.mist
                        : AppColors.primary
                    )
                    .clipShape(Capsule())
                    .shadow(
                        color: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? .clear
                        : AppColors.primary.opacity(0.3),
                        radius: 12,
                        y: 4
                    )
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(24)
            .background(colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .font(AppTypography.body)
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
                        LucideIcon(image: Lucide.sparkles, size: 16)
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
                            LucideIcon(image: Lucide.house, size: 16)
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
