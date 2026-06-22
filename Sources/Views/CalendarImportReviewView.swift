import SwiftUI
import EventKit
import LucideIcons

// MARK: - Calendar Import View (Main Entry Point)

struct CalendarImportView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    enum Step {
        case intro
        case pickCalendars
        case review([DetectedCalendarEntry])
        case success(Int)
    }

    @State private var step: Step = .intro
    @State private var availableCalendars: [EKCalendar] = []
    @State private var selectedCalendarIds: Set<String> = []
    @State private var isScanning = false
    @State private var permissionDenied = false

    private var hasSelection: Bool {
        !selectedCalendarIds.isEmpty
    }

    var body: some View {
        Group {
            switch step {
            case .intro:
                introScreen
            case .pickCalendars:
                calendarPickerScreen
            case .review(let entries):
                reviewScreen(entries)
            case .success(let count):
                successScreen(count)
            }
        }
        .background(colors.background)
        .navigationTitle("Calendar Import")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    LucideIcon(image: Lucide.calendar, size: 16)
                        .foregroundStyle(colors.textPrimary)
                    Text("Calendar Import")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                }
            }
            if case .pickCalendars = step {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        scanAndReview()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(hasSelection ? AppColors.primary : AppColors.cloud)
                                .frame(width: 32, height: 32)
                            LucideIcon(image: Lucide.check, size: 16)
                                .foregroundStyle(hasSelection ? AppColors.onAction : colors.textTertiary)
                        }
                    }
                    .disabled(!hasSelection || isScanning)
                }
            }
        }
        .alert("Calendar Access Denied", isPresented: $permissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please allow calendar access in Settings to import your events.")
        }
    }

    // MARK: - Screen 1: Intro

    private var introScreen: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    // Header
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Import your\ncalendar")
                            .font(.system(size: 28, weight: .regular, design: .serif))
                            .foregroundStyle(colors.textPrimary)
                            .lineSpacing(2)

                        Text("We'll scan your calendar for property-related events and pre-fill your time log.")
                            .font(AppTypography.body)
                            .foregroundStyle(colors.textSecondary)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 20)

                    // Calendar mockup card
                    calendarMockup
                        .padding(.horizontal, 28)
                }
                .padding(.bottom, 100)
            }

            Spacer(minLength: 0)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                requestAccessAndProceed()
            } label: {
                Text("Import calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.onAction)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .background(.ultraThinMaterial)
        }
        .hidesAppTabBar()
    }

    // Calendar mockup (visual preview of what import looks like)
    private var calendarMockup: some View {
        VStack(spacing: 0) {
            // Day header
            HStack {
                LucideIcon(image: Lucide.chevronLeft, size: 14)
                    .foregroundStyle(colors.textTertiary)
                Spacer()
                VStack(spacing: 2) {
                    Text("Today")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(Date(), style: .date)
                        .font(.system(size: 12))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                LucideIcon(image: Lucide.chevronRight, size: 14)
                    .foregroundStyle(colors.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            // Sample events
            VStack(spacing: 0) {
                mockupEvent(time: "9:00 AM", title: "Tenant showing", hours: "1 hour", color: AppColors.sky)
                Divider().padding(.leading, 60)
                mockupEvent(time: "11:00 AM", title: "Plumber visit", hours: "2 hours", color: AppColors.coral)
                Divider().padding(.leading, 60)
                mockupEvent(time: "2:00 PM", title: "Lease signing", hours: "1.5 hours", color: AppColors.sage)
            }
        }
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.xl)
                .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
        }
    }

    private func mockupEvent(time: String, title: String, hours: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Text(time)
                .font(.system(size: 11))
                .foregroundStyle(colors.textTertiary)
                .frame(width: 48, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(colors.textPrimary)
                Text(hours)
                    .font(.system(size: 12))
                    .foregroundStyle(colors.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Screen 2: Calendar Picker

    private var calendarPickerScreen: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose and customize\nyour calendars")
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(colors.textPrimary)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 16)

            if isScanning {
                Spacer()
                ProgressView("Scanning events...")
                    .foregroundStyle(colors.textSecondary)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(calendarSources, id: \.name) { source in
                            calendarSourceSection(source)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // Group calendars by source
    private var calendarSources: [CalendarSource] {
        let grouped = Dictionary(grouping: availableCalendars) { cal -> String in
            cal.source.title
        }
        return grouped.map { CalendarSource(name: $0.key, calendars: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.name < $1.name }
    }

    private func calendarSourceSection(_ source: CalendarSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(source.name)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(colors.textPrimary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(source.calendars.enumerated()), id: \.element.calendarIdentifier) { index, calendar in
                    calendarRow(calendar)
                    if index < source.calendars.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        }
    }

    private func calendarRow(_ calendar: EKCalendar) -> some View {
        let isSelected = selectedCalendarIds.contains(calendar.calendarIdentifier)
        return Button {
            if isSelected {
                selectedCalendarIds.remove(calendar.calendarIdentifier)
            } else {
                selectedCalendarIds.insert(calendar.calendarIdentifier)
            }
        } label: {
            HStack(spacing: 12) {
                // Calendar color dot
                Circle()
                    .fill(Color(cgColor: calendar.cgColor))
                    .frame(width: 28, height: 28)
                    .overlay(
                        LucideIcon(image: Lucide.calendar, size: 14)
                            .foregroundStyle(.white.opacity(0.8))
                    )

                Text(calendar.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(colors.textPrimary)

                Spacer()

                // Circle toggle (like reference design)
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? AppColors.primary : AppColors.cloud, lineWidth: 1.5)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(AppColors.primary)
                            .frame(width: 24, height: 24)
                        LucideIcon(image: Lucide.check, size: 14)
                            .foregroundStyle(AppColors.onAction)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Screen 3: Review Detected Entries

    private func reviewScreen(_ entries: [DetectedCalendarEntry]) -> some View {
        CalendarImportReviewView(detectedEntries: entries)
    }

    // MARK: - Screen 4: Success

    private func successScreen(_ count: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()
            JellyBadge(systemName: "circle-check", color: AppColors.sage, wash: AdaptiveColors(colorScheme: colorScheme).sageWash, size: 64)
            Text("\(count) Entries Imported")
                .font(AppTypography.title2)
                .foregroundStyle(colors.textPrimary)
            Text("Your calendar events have been added to your time log. You can edit them anytime.")
                .font(AppTypography.body)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Actions

    private func requestAccessAndProceed() {
        Task {
            let granted = await CalendarImportService.shared.requestAccess()
            if granted {
                availableCalendars = CalendarImportService.shared.availableCalendars()
                selectedCalendarIds = Set(availableCalendars.map { $0.calendarIdentifier })
                animate(AppAnimation.standard) { step = .pickCalendars }
            } else {
                permissionDenied = true
            }
        }
    }

    private func scanAndReview() {
        isScanning = true
        // Run scan off main thread
        Task.detached { [selectedCalendarIds, properties = viewModel.properties] in
            let entries = CalendarImportService.shared.scanCalendars(
                selectedCalendarIds,
                properties: properties
            )
            await MainActor.run {
                isScanning = false
                animate(AppAnimation.standard) {
                    step = .review(entries)
                }
            }
        }
    }

    private func animate(_ animation: Animation = AppAnimation.smooth, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }
}

// Helper for grouping calendars
private struct CalendarSource {
    let name: String
    let calendars: [EKCalendar]
}

// MARK: - Review View (Screen 3 — Entry List)

struct CalendarImportReviewView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State var detectedEntries: [DetectedCalendarEntry]
    @State private var importCount = 0
    @State private var didImport = false

    private var selectedCount: Int {
        detectedEntries.filter(\.isSelected).count
    }

    private var allSelected: Bool {
        !detectedEntries.isEmpty && detectedEntries.allSatisfy(\.isSelected)
    }

    var body: some View {
        VStack(spacing: 0) {
            if didImport {
                successState
            } else if detectedEntries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .toolbar {
            if !didImport && !detectedEntries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(allSelected ? "Deselect All" : "Select All") {
                        let newValue = !allSelected
                        for i in detectedEntries.indices {
                            detectedEntries[i].isSelected = newValue
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.primary)
                }
            }
        }
    }

    // MARK: - Entry List

    private var entryList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                LucideIcon(image: Lucide.calendar, size: 16)
                    .foregroundStyle(AppColors.primary)
                Text("\(detectedEntries.count) events detected")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                Spacer()
                Text("\(selectedCount) selected")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.primary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(detectedEntries.enumerated()), id: \.element.id) { index, _ in
                        CalendarImportRow(
                            entry: $detectedEntries[index],
                            properties: viewModel.properties,
                            colors: colors
                        )
                        if index < detectedEntries.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
                .overlay {
                    RoundedRectangle(cornerRadius: AppCornerRadius.xl)
                        .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }

            Spacer(minLength: 0)
        }
        .safeAreaInset(edge: .bottom) {
            importButton
        }
        .hidesAppTabBar()
    }

    private var importButton: some View {
        Button {
            importCount = viewModel.importCalendarEntries(detectedEntries)
            animate(AppAnimation.standard) { didImport = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } label: {
            HStack(spacing: 8) {
                LucideIcon(image: Lucide.download, size: 16)
                    .foregroundStyle(AppColors.onAction)
                Text("Import \(selectedCount) Entries")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.onAction)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(selectedCount > 0 ? AppColors.primary : AppColors.mist)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(selectedCount == 0)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    // MARK: - Success

    private var successState: some View {
        VStack(spacing: 20) {
            Spacer()
            JellyBadge(systemName: "circle-check", color: AppColors.sage, wash: colors.sageWash, size: 64)
            Text("\(importCount) Entries Imported")
                .font(AppTypography.title2)
                .foregroundStyle(colors.textPrimary)
            Text("Your calendar events have been added to your time log. You can edit them anytime.")
                .font(AppTypography.body)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            JellyBadge(systemName: "calendar", color: AppColors.primary, wash: colors.primarySurface, size: 64)
            Text("No Events Found")
                .font(AppTypography.title2)
                .foregroundStyle(colors.textPrimary)
            Text("No property-related calendar events were found in the last 90 days.")
                .font(AppTypography.body)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private func animate(_ animation: Animation = AppAnimation.smooth, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }
}

// MARK: - Calendar Import Row

struct CalendarImportRow: View {
    @Binding var entry: DetectedCalendarEntry
    let properties: [RentalProperty]
    let colors: AdaptiveColors

    private var propertyName: String {
        guard let id = entry.propertyId else { return "No Property" }
        return properties.first { $0.id == id }?.name ?? "Unknown"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button {
                entry.isSelected.toggle()
            } label: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(entry.isSelected ? AppColors.primary : Color.clear)
                    .frame(width: 22, height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(entry.isSelected ? AppColors.primary : AppColors.cloud, lineWidth: 1.5)
                    )
                    .overlay {
                        if entry.isSelected {
                            LucideIcon(image: Lucide.check, size: 14)
                                .foregroundStyle(AppColors.onAction)
                        }
                    }
            }
            .buttonStyle(.plain)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.eventTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(entry.isSelected ? colors.textPrimary : colors.textTertiary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(entry.eventDate, style: .date)
                        .font(AppTypography.caption)
                        .foregroundStyle(colors.textSecondary)

                    Menu {
                        ForEach(ActivityCategory.allCases, id: \.self) { cat in
                            Button {
                                entry.category = cat
                            } label: {
                                HStack {
                                    Text(cat.chipLabel)
                                    if entry.category == cat {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(entry.category.color)
                                .frame(width: 6, height: 6)
                            Text(entry.category.chipLabel)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(colors.textSecondary)
                            LucideIcon(image: Lucide.chevronDown, size: 8)
                                .foregroundStyle(colors.textTertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.snow)
                        .clipShape(Capsule())
                    }

                    if properties.count > 1 {
                        Menu {
                            ForEach(properties) { property in
                                Button {
                                    entry.propertyId = property.id
                                } label: {
                                    HStack {
                                        Text(property.name)
                                        if entry.propertyId == property.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(propertyName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(colors.textSecondary)
                                    .lineLimit(1)
                                LucideIcon(image: Lucide.chevronDown, size: 8)
                                    .foregroundStyle(colors.textTertiary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColors.snow)
                            .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer()

            Text(String(format: "%.1fh", entry.hours))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(entry.isSelected ? colors.textPrimary : colors.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(entry.isSelected ? 1.0 : 0.6)
    }
}
