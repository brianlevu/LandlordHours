import SwiftUI

struct CategoryManagementView: View {
    @EnvironmentObject var categoryManager: CategoryManager
    @State private var showingAddCategory = false
    @State private var editingCategory: CustomCategory?
    
    var body: some View {
        List {
            Section {
                ForEach(categoryManager.defaultCategories.map { CustomCategory(name: $0.name, iconName: $0.icon, colorHex: $0.color, countsForREPS: $0.countsForREPS) }) { category in
                    HStack {
                        DynamicIconView(name: category.iconName, size: 20, color: Color(hex: category.colorHex))
                            .frame(width: 30)
                        Text(category.name)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text("Default")
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            } header: {
                Text("Default Categories")
            } footer: {
                Text("These categories cannot be deleted but are used throughout the app.")
            }
            
            Section {
                if categoryManager.customCategories.isEmpty {
                    VStack(spacing: 12) {
                        LHSoftBadge(icon: .tag, color: AppColors.primary, size: 56)
                        Text("No Custom Categories")
                            .font(.headline)
                            .foregroundStyle(AppColors.textSecondary)
                        Text("Tap + to add your own categories")
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ForEach(categoryManager.customCategories) { category in
                        HStack {
                            DynamicIconView(name: category.iconName, size: 20, color: Color(hex: category.colorHex))
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name)
                                    .foregroundStyle(AppColors.textPrimary)
                                Text(category.countsForREPS ? "Counts for REPS" : "Doesn't count")
                                    .font(.caption)
                                    .foregroundStyle(category.countsForREPS ? AppColors.success : AppColors.textTertiary)
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
                    LHIconView(icon: .plusCircle, size: 24, color: AppColors.primary)
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
                }
                
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(availableCategoryIcons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                DynamicIconView(name: icon, size: 20, color: selectedIcon == icon ? Color(hex: selectedColor) : AppColors.textSecondary)
                                    .frame(width: 36, height: 36)
                                    .background(selectedIcon == icon ? Color(hex: selectedColor).opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
                                        LHIconView(icon: .checkmark, size: 10, color: .white)
                                            .opacity(selectedColor == color ? 1 : 0)
                                    )
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section {
                    Toggle("Count for REPS", isOn: $countsForREPS)
                } footer: {
                    Text("IRS requires 750 hours of material participation. Only activities marked as counting will contribute to this goal.")
                }
                
                Section("Preview") {
                    HStack {
                        DynamicIconView(name: selectedIcon, size: 20, color: Color(hex: selectedColor))
                            .frame(width: 30)
                        Text(name.isEmpty ? "Category Name" : name)
                            .foregroundStyle(name.isEmpty ? AppColors.textTertiary : AppColors.textPrimary)
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
