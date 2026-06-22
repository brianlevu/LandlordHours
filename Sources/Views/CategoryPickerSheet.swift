import SwiftUI

struct CategoryPickerSheet: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var categoryManager: CategoryManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var selectedCustomCategory: CustomCategory?
    @State private var showingQuickLog = false
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    categorySection(
                        title: "Default categories",
                        categories: categoryManager.defaultCategories.map { CustomCategory(name: $0.name, iconName: $0.icon, colorHex: $0.color, countsForREPS: $0.countsForREPS) }
                    )

                    if !categoryManager.customCategories.isEmpty {
                        categorySection(title: "Custom categories", categories: categoryManager.customCategories)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background { LHMobileCanvas() }
            .navigationTitle("Select category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingQuickLog) {
                if let custom = selectedCustomCategory {
                    QuickLogEntryView(customCategory: custom)
                }
            }
        }
    }

    private func categorySection(title: String, categories: [CustomCategory]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)

            VStack(spacing: 0) {
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                    categoryRow(category)
                    if index < categories.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xxl))
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.xxl)
                    .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
            }
        }
    }

    private func categoryRow(_ category: CustomCategory) -> some View {
        Button {
            selectedCustomCategory = category
            showingQuickLog = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: category.iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: category.colorHex))
                    .frame(width: 38, height: 38)
                    .background(Color(hex: category.colorHex).opacity(colorScheme == .dark ? 0.18 : 0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(colors.textPrimary)
                    Text(category.countsForREPS ? "Counts for REPS" : "Does not count for REPS")
                        .font(AppTypography.caption)
                        .foregroundStyle(category.countsForREPS ? AppColors.sage : colors.textTertiary)
                }
                Spacer()
            }
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }
}
