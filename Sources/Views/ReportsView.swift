import SwiftUI
import PDFKit

struct ReportsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var showingExportSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Year Selector
                    YearSelector(selectedYear: $selectedYear)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    // REPS Progress Ring (Large)
                    REPSProgressRingCard(
                        selfHours: viewModel.totalHoursForParticipant(.selfParticipant, year: selectedYear),
                        spouseHours: viewModel.totalHoursForParticipant(.spouse, year: selectedYear),
                        meets50Percent: viewModel.meets50PercentRule(year: selectedYear)
                    )
                    .padding(.horizontal)
                    
                    // Quick Stats
                    HStack(spacing: 12) {
                        QuickStatBadge(
                            title: "This Week",
                            value: thisWeekHours,
                            icon: "calendar",
                            color: AppColors.primary
                        )
                        QuickStatBadge(
                            title: "This Month",
                            value: thisMonthHours,
                            icon: "calendar.badge.clock",
                            color: .purple
                        )
                    }
                    .padding(.horizontal)
                    
                    // Breakdown by Property
                    PropertyBreakdownSection(
                        properties: viewModel.properties,
                        viewModel: viewModel,
                        selectedYear: selectedYear
                    )
                    
                    // Breakdown by Category
                    CategoryBreakdownSection(
                        viewModel: viewModel,
                        selectedYear: selectedYear
                    )
                }
                .padding(.bottom, 20)
            }
            .background(colors.background)
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingExportSheet = true
                    } label: {
                        LHIconView(icon: .share, size: 20, color: AppColors.primary)
                    }
                }
            }
            .sheet(isPresented: $showingExportSheet) {
                ExportPDFView(year: selectedYear)
            }
        }
    }
    
    var thisWeekHours: String {
        guard let weekStart = Date().startOfWeek else { return "0h" }
        let hours = viewModel.timeEntries
            .filter { $0.date >= weekStart && $0.countsForREPS }
            .reduce(0) { $0 + $1.hours }
        return String(format: "%.1fh", hours)
    }
    
    var thisMonthHours: String {
        guard let monthStart = Date().startOfMonth else { return "0h" }
        let hours = viewModel.timeEntries
            .filter { $0.date >= monthStart && $0.countsForREPS }
            .reduce(0) { $0 + $1.hours }
        return String(format: "%.1fh", hours)
    }
}

// MARK: - Year Selector
struct YearSelector: View {
    @Binding var selectedYear: Int
    
    var body: some View {
        HStack {
            Button {
                if selectedYear > 2020 { selectedYear -= 1 }
            } label: {
                LHIconView(icon: .chevronLeft, size: 16, color: AppColors.primary, strokeStyle: true)
            }
            
            Spacer()
            
            Text(String(selectedYear))
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            Button {
                if selectedYear < 2030 { selectedYear += 1 }
            } label: {
                LHIconView(icon: .chevronRight, size: 16, color: AppColors.primary, strokeStyle: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - REPS Progress Ring Card
struct REPSProgressRingCard: View {
    let selfHours: Double
    let spouseHours: Double
    let meets50Percent: Bool
    
    var totalHours: Double { selfHours + spouseHours }
    var progress: Double { min(totalHours / 750.0, 1.0) }
    var remainingHours: Double { max(750.0 - totalHours, 0) }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("REPS Progress")
                    .font(.headline)
                Spacer()
                if meets50Percent {
                    HStack(spacing: 4) {
                        LHIconView(icon: .seal, size: 14, color: .green)
                        Text("50% Rule Met")
                    }
                    .font(.caption)
                    .foregroundStyle(.green)
                }
            }
            
            // Large Progress Ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        progress >= 1.0 ? AppColors.success : AppColors.primary,
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.8, dampingFraction: 0.75), value: progress)
                
                VStack(spacing: 4) {
                    Text(String(format: "%.0f", totalHours))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("of 750 hours")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if remainingHours > 0 {
                        Text(String(format: "%.0f hours to go", remainingHours))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(height: 200)
            
            // Participant Stats
            HStack(spacing: 0) {
                ParticipantStatBox(
                    name: "You",
                    hours: selfHours,
                    color: AppColors.primary,
                    icon: "person.fill"
                )
                
                Divider()
                    .frame(height: 40)
                
                ParticipantStatBox(
                    name: "Spouse",
                    hours: spouseHours,
                    color: .purple,
                    icon: "person.2.fill"
                )
            }
            
            // Status Message
            if totalHours >= 750 {
                HStack {
                    LHIconView(icon: .party, size: 18, color: .green)
                    Text("750-hour requirement met!")
                }
                .font(.headline)
                .foregroundStyle(.green)
                .padding(.top, 8)
            }
        }
        .padding(24)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

struct ParticipantStatBox: View {
    let name: String
    let hours: Double
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            DynamicIconView(name: icon, size: 24, color: color)
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1fh", hours))
                .font(.title3)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PropertyBreakdownSection: View {
    let properties: [RentalProperty]
    let viewModel: AppViewModel
    let selectedYear: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Property")
                .font(.headline)
                .padding(.horizontal)
            
            if properties.isEmpty {
                EmptySectionCard(icon: .home, message: "No properties added")
            } else {
                VStack(spacing: 8) {
                    ForEach(properties) { property in
                        let hours = viewModel.hoursForProperty(property, year: selectedYear)
                        PropertyBreakdownRow(property: property, hours: hours, totalHours: viewModel.totalHoursAllParticipants(year: selectedYear))
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct PropertyBreakdownRow: View {
    let property: RentalProperty
    let hours: Double
    let totalHours: Double
    
    var progress: Double {
        guard totalHours > 0 else { return 0 }
        return hours / totalHours
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                DynamicIconView(name: property.propertyType.icon, size: 16, color: property.propertyType == .str ? .orange : .blue)
                Text(property.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(String(format: "%.1fh", hours))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(property.propertyType == .str ? Color.orange : Color.blue)
                        .frame(width: geometry.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Category Breakdown Section
struct CategoryBreakdownSection: View {
    let viewModel: AppViewModel
    let selectedYear: Int
    
    var categoryBreakdown: [(ActivityCategory, Double)] {
        let entries = viewModel.entriesForYear(selectedYear)
        var breakdown: [ActivityCategory: Double] = [:]
        
        for entry in entries where entry.countsForREPS {
            breakdown[entry.category, default: 0] += entry.hours
        }
        
        return breakdown.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Category")
                .font(.headline)
                .padding(.horizontal)
            
            if categoryBreakdown.isEmpty {
                EmptySectionCard(icon: .tag, message: "No time entries yet")
            } else {
                VStack(spacing: 8) {
                    ForEach(categoryBreakdown, id: \.0) { category, hours in
                        CategoryBreakdownRow(
                            category: category,
                            hours: hours,
                            totalHours: viewModel.totalHoursAllParticipants(year: selectedYear)
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct CategoryBreakdownRow: View {
    let category: ActivityCategory
    let hours: Double
    let totalHours: Double
    
    var progress: Double {
        guard totalHours > 0 else { return 0 }
        return hours / totalHours
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                DynamicIconView(name: category.icon, size: 16, color: .purple)
                Text(category.rawValue)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.1fh", hours))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.purple)
                        .frame(width: geometry.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Empty Section Card
struct EmptySectionCard: View {
    let icon: LHIcon
    let message: String

    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                LHSoftBadge(icon: icon, color: .secondary, size: 40)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 24)
            Spacer()
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

#Preview {
    ReportsView()
        .environmentObject(AppViewModel())
}
