import SwiftUI
import LucideIcons

struct TaxYearView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    let taxYears = [2026, 2025, 2024, 2023, 2022, 2021]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                yearPickerCard
                statsCard
                propertiesCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .background { LHMobileCanvas() }
        .navigationTitle("Tax Year")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tax year")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)
            Text("Review annual hours, REPS progress, and active properties.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(colors.textSecondary)
        }
    }

    private var yearPickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select year")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 10) {
                ForEach(taxYears, id: \.self) { year in
                    Button { selectYear(year) } label: {
                        HStack(spacing: 6) {
                            Text(String(year))
                            if selectedYear == year {
                                LucideIcon(image: Lucide.check, size: 13)
                            }
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedYear == year ? AppColors.charcoal : colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(selectedYear == year ? AppColors.sage : colors.backgroundTertiary)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(selectedYear == year ? Color.clear : colors.border.opacity(0.35), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("REPS is measured by tax year: more than 750 qualifying real estate hours plus the 50% rule.")
                .font(AppTypography.caption)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xxl))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.xxl)
                .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
        }
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Current year")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)

            statRow("Total hours", value: String(format: "%.1f hours", totalHoursForYear), color: AppColors.sage)
            statRow("REPS target", value: "750 hours", color: colors.textPrimary)
            statRow("Progress", value: "\(Int(progressPercentage))%", color: progressPercentage >= 100 ? AppColors.sage : AppColors.honey)

            ProgressView(value: min(progressPercentage, 100), total: 100)
                .tint(progressPercentage >= 100 ? AppColors.sage : AppColors.honey)
        }
        .padding(18)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xxl))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.xxl)
                .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
        }
    }

    private func statRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(AppTypography.body)
                .foregroundStyle(colors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
    }

    private var propertiesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Properties worked")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)

            let properties = propertiesWorkedThisYear
            if properties.isEmpty {
                Text("No qualifying entries for this year.")
                    .font(AppTypography.body)
                    .foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(properties, id: \.self) { property in
                    HStack(spacing: 10) {
                        LHIconTile(icon: Lucide.house, color: AppColors.sage, wash: colors.sageWash, size: 34, isActive: true)
                        Text(property)
                            .font(AppTypography.body)
                            .foregroundStyle(colors.textPrimary)
                        Spacer()
                    }
                }
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
