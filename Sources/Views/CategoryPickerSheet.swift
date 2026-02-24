import SwiftUI

struct CategoryPickerSheet: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var categoryManager: CategoryManager
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedCategory: ActivityCategory?
    @State private var selectedCustomCategory: CustomCategory?
    @State private var showingQuickLog = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("Default Categories") {
                    ForEach(categoryManager.defaultCategories.map { CustomCategory(name: $0.name, iconName: $0.icon, colorHex: $0.color, countsForREPS: $0.countsForREPS) }, id: \.name) { category in
                        Button {
                            selectedCustomCategory = category
                            showingQuickLog = true
                        } label: {
                            HStack {
                                DynamicIconView(name: category.iconName, size: 20, color: Color(hex: category.colorHex))
                                    .frame(width: 30)
                                Text(category.name)
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                            }
                        }
                    }
                }
                
                if !categoryManager.customCategories.isEmpty {
                    Section("Custom Categories") {
                        ForEach(categoryManager.customCategories) { category in
                            Button {
                                selectedCustomCategory = category
                                showingQuickLog = true
                            } label: {
                                HStack {
                                    DynamicIconView(name: category.iconName, size: 20, color: Color(hex: category.colorHex))
                                        .frame(width: 30)
                                    VStack(alignment: .leading) {
                                        Text(category.name)
                                            .foregroundStyle(AppColors.textPrimary)
                                        Text(category.countsForREPS ? "Counts for REPS" : "No REPS")
                                            .font(.caption)
                                            .foregroundStyle(category.countsForREPS ? AppColors.success : AppColors.textTertiary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Category")
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
}
