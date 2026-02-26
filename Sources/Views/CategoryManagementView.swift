import SwiftUI
import LucideIcons

struct CategoryManagementView: View {
    @EnvironmentObject var categoryManager: CategoryManager
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var showingAddCategory = false
    @State private var editingCategory: CustomCategory?

    var body: some View {
        List {
            Section {
                ForEach(categoryManager.defaultCategories.map { CustomCategory(name: $0.name, iconName: $0.icon, colorHex: $0.color, countsForREPS: $0.countsForREPS) }) { category in
                    HStack {
                        Image(systemName: category.iconName)
                            .font(.system(size: 18))
                            .foregroundStyle(Color(hex: category.colorHex))
                            .frame(width: 30)
                        Text(category.name)
                            .font(AppTypography.body)
                            .foregroundStyle(colors.textPrimary)
                        Spacer()
                        Text("Default")
                            .font(AppTypography.caption)
                            .foregroundStyle(colors.textTertiary)
                    }
                }
            } header: {
                Text("Default Categories")
                    .font(AppTypography.label)
                    .tracking(1.5)
            } footer: {
                Text("These categories cannot be deleted but are used throughout the app.")
            }

            Section {
                if categoryManager.customCategories.isEmpty {
                    VStack(spacing: 12) {
                        JellyBadge(systemName: "tag", color: AppColors.primary, wash: colors.primarySurface, size: 56)
                        Text("No Custom Categories")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(colors.textSecondary)
                        Text("Tap + to add your own categories")
                            .font(AppTypography.caption)
                            .foregroundStyle(colors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ForEach(categoryManager.customCategories) { category in
                        HStack {
                            Image(systemName: category.iconName)
                                .font(.system(size: 18))
                                .foregroundStyle(Color(hex: category.colorHex))
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name)
                                    .font(AppTypography.body)
                                    .foregroundStyle(colors.textPrimary)
                                Text(category.countsForREPS ? "Counts for REPS" : "Doesn't count")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(category.countsForREPS ? AppColors.sage : colors.textTertiary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingCategory = category
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let category = categoryManager.customCategories[index]
                            categoryManager.deleteCategory(category)
                        }
                    }
                }
            } header: {
                Text("Custom Categories")
                    .font(AppTypography.label)
                    .tracking(1.5)
            } footer: {
                Text("Swipe to delete or tap to edit custom categories.")
            }
        }
        .navigationTitle("Manage Categories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddCategory = true
                } label: {
                    LucideIcon(image: Lucide.circlePlus, size: 24)
                        .foregroundStyle(AppColors.primary)
                }
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            AddEditCategoryView()
        }
        .sheet(item: $editingCategory) { category in
            AddEditCategoryView(editingCategory: category)
        }
    }
}

// MARK: - Add/Edit Category View
struct AddEditCategoryView: View {
    @EnvironmentObject var categoryManager: CategoryManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var editingCategory: CustomCategory?

    @State private var name: String = ""
    @State private var selectedIcon: String = "star.fill"
    @State private var selectedColor: String = "8B5CF6"
    @State private var countsForREPS: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Category Name") {
                    TextField("Enter name", text: $name)
                        .font(AppTypography.body)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(availableCategoryIcons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(selectedIcon == icon ? Color(hex: selectedColor) : colors.textSecondary)
                                    .frame(width: 36, height: 36)
                                    .background(selectedIcon == icon ? Color(hex: selectedColor).opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.small))
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(availableCategoryColors, id: \.self) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColor == color ? Color.white : Color.clear, lineWidth: 2)
                                    )
                                    .overlay(
                                        LucideIcon(image: Lucide.check, size: 10)
                                            .foregroundStyle(.white)
                                            .opacity(selectedColor == color ? 1 : 0)
                                    )
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    Toggle("Count for REPS", isOn: $countsForREPS)
                        .font(AppTypography.body)
                } footer: {
                    Text("IRS requires 750 hours of material participation. Only activities marked as counting will contribute to this goal.")
                }

                Section("Preview") {
                    HStack {
                        Image(systemName: selectedIcon)
                            .font(.system(size: 18))
                            .foregroundStyle(Color(hex: selectedColor))
                            .frame(width: 30)
                        Text(name.isEmpty ? "Category Name" : name)
                            .font(AppTypography.body)
                            .foregroundStyle(name.isEmpty ? colors.textTertiary : colors.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(editingCategory == nil ? "Add Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCategory()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                if let category = editingCategory {
                    name = category.name
                    selectedIcon = category.iconName
                    selectedColor = category.colorHex
                    countsForREPS = category.countsForREPS
                }
            }
        }
    }

    func saveCategory() {
        let category = CustomCategory(
            id: editingCategory?.id ?? UUID(),
            name: name,
            iconName: selectedIcon,
            colorHex: selectedColor,
            countsForREPS: countsForREPS
        )

        if editingCategory != nil {
            categoryManager.updateCategory(category)
        } else {
            categoryManager.addCategory(category)
        }

        dismiss()
    }
}

#Preview {
    NavigationStack {
        CategoryManagementView()
    }
}
