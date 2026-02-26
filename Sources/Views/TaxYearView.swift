import SwiftUI
import LucideIcons

struct TaxYearView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    
    let taxYears = [2026, 2025, 2024, 2023, 2022, 2021]
    
    var body: some View {
        List {
            Section {
                ForEach(taxYears, id: \.self) { year in
                    Button {
                        selectYear(year)
                    } label: {
                        HStack {
                            Text(String(year))
                                .foregroundStyle(selectedYear == year ? AppColors.primary : AppColors.textPrimary)
                            Spacer()
                            if selectedYear == year {
                                LucideIcon(image: Lucide.check, size: 14)
                                    .foregroundStyle(AppColors.primary)
                            }
                        }
                    }
                }
            } header: {
                Text("Select Tax Year")
            } footer: {
                Text("IRS requires 750 hours of material participation per tax year for real estate professional status.")
            }
            
            Section("Current Year Stats") {
                HStack {
                    Text("Total Hours")
                    Spacer()
                    Text(String(format: "%.1f hours", totalHoursForYear))
                        .foregroundStyle(AppColors.primary)
                }
                
                HStack {
                    Text("REPS Goal")
                    Spacer()
                    Text("750 hours")
                        .foregroundStyle(AppColors.textSecondary)
                }
                
                HStack {
                    Text("Progress")
                    Spacer()
                    Text("\(Int(progressPercentage))%")
                        .foregroundStyle(progressPercentage >= 100 ? AppColors.success : AppColors.warning)
                }
                
                ProgressView(value: min(progressPercentage, 100), total: 100)
                    .tint(progressPercentage >= 100 ? AppColors.success : AppColors.primary)
            }
            
            Section("Properties Worked") {
                let properties = propertiesWorkedThisYear
                if properties.isEmpty {
                    Text("No entries for this year")
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    ForEach(properties, id: \.self) { property in
                        HStack {
                            LucideIcon(image: Lucide.house, size: 16)
                            .foregroundStyle(AppColors.primary)
                            Text(property)
                                .foregroundStyle(AppColors.textPrimary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Tax Year")
    }
    
    var totalHoursForYear: Double {
        let calendar = Calendar.current
        return viewModel.timeEntries
            .filter { entry in
                let entryYear = calendar.component(.year, from: entry.date)
                return entryYear == selectedYear && entry.category.countsForREPS
            }
            .reduce(0) { $0 + $1.hours }
    }
    
    var progressPercentage: Double {
        return (totalHoursForYear / 750.0) * 100
    }
    
    var propertiesWorkedThisYear: [String] {
        let calendar = Calendar.current
        let properties = viewModel.timeEntries
            .filter { entry in
                let entryYear = calendar.component(.year, from: entry.date)
                return entryYear == selectedYear && entry.category.countsForREPS
            }
            .map { $0.getPropertyName(from: viewModel.properties) }
        
        return Array(Set(properties)).sorted()
    }
    
    func selectYear(_ year: Int) {
        selectedYear = year
        UserDefaults.standard.set(year, forKey: UserScope.key("selectedTaxYear"))
    }
}

#Preview {
    NavigationStack {
        TaxYearView()
            .environmentObject(AppViewModel())
    }
}
