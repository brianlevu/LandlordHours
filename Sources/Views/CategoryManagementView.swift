import SwiftUI
import LucideIcons

struct CategoryManagementView: View {
    @EnvironmentObject var categoryManager: CategoryManager
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var showingAddCategory = false
    @State private var editingCategory: CustomCategory?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                categorySection(
                    title: "Default categories",
                    detail: "Built-in categories used throughout LandlordHours.",
                    categories: categoryManager.defaultCategories.map { CustomCategory(name: $0.name, iconName: $0.icon, colorHex: $0.color, countsForREPS: $0.countsForREPS) },
                    editable: false
                )

                customSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background { LHMobileCanvas() }
        .navigationTitle("Manage categories")
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

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Custom categories")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Text("Tap a category to edit it.")
                    .font(AppTypography.caption)
                    .foregroundStyle(colors.textSecondary)
            }

            if categoryManager.customCategories.isEmpty {
                VStack(spacing: 10) {
                    JellyBadge(systemName: "tag", color: AppColors.sage, wash: colors.sageWash, size: 54)
                    Text("No custom categories")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text("Add your own categories when the defaults do not match how you work.")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xxl))
                .overlay {
                    RoundedRectangle(cornerRadius: AppCornerRadius.xxl)
                        .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
                }
            } else {
                categoryRows(categories: categoryManager.customCategories, editable: true)
            }
        }
    }

    private func categorySection(title: String, detail: String, categories: [CustomCategory], editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Text(detail)
                    .font(AppTypography.caption)
                    .foregroundStyle(colors.textSecondary)
            }
            categoryRows(categories: categories, editable: editable)
        }
    }

    private func categoryRows(categories: [CustomCategory], editable: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                HStack(spacing: 8) {
                    Button {
                        if editable {
                            editingCategory = category
                        }
                    } label: {
                        categoryRowContent(category, editable: editable)
                    }
                    .buttonStyle(.plain)

                    if editable {
                        Button(role: .destructive) {
                            categoryManager.deleteCategory(category)
                        } label: {
                            LucideIcon(image: Lucide.trash2, size: 16)
                                .foregroundStyle(AppColors.coral)
                                .frame(width: 38, height: 38)
                                .background(colors.coralWash)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete \(category.name)")
                    }
                }
                .padding(.vertical, 11)

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

    private func categoryRowContent(_ category: CustomCategory, editable: Bool) -> some View {
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
            if editable {
                LucideIcon(image: Lucide.chevronRight, size: 16)
                    .foregroundStyle(colors.textTertiary)
            } else {
                Text("Default")
                    .font(AppTypography.caption)
                    .foregroundStyle(colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    nameCard
                    iconCard
                    colorCard
                    repsCard
                    previewCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background { LHMobileCanvas() }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(editingCategory == nil ? "Add category" : "Edit category")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)
            Text("Customize how work is grouped in your reports.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(colors.textSecondary)
        }
    }

    private var nameCard: some View {
        categoryEditCard(title: "Name") {
            TextField("Enter name", text: $name)
                .font(AppTypography.body)
                .foregroundStyle(colors.textPrimary)
                .padding(14)
                .background(colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
        }
    }

    private var iconCard: some View {
        categoryEditCard(title: "Icon") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                ForEach(availableCategoryIcons, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                    } label: {
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(selectedIcon == icon ? Color(hex: selectedColor) : colors.textSecondary)
                            .frame(width: 38, height: 38)
                            .background(selectedIcon == icon ? Color(hex: selectedColor).opacity(colorScheme == .dark ? 0.24 : 0.16) : colors.backgroundTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var colorCard: some View {
        categoryEditCard(title: "Color") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                ForEach(availableCategoryColors, id: \.self) { color in
                    Button {
                        selectedColor = color
                    } label: {
                        Circle()
                            .fill(Color(hex: color))
                            .frame(width: 34, height: 34)
                            .overlay {
                                Circle()
                                    .stroke(selectedColor == color ? colors.textPrimary : Color.clear, lineWidth: 2)
                            }
                            .overlay {
                                LucideIcon(image: Lucide.check, size: 11)
                                    .foregroundStyle(AppColors.onAction)
                                    .opacity(selectedColor == color ? 1 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var repsCard: some View {
        categoryEditCard(title: "Qualification") {
            Toggle("Count for REPS", isOn: $countsForREPS)
                .font(AppTypography.body)
            Text("Only qualifying real estate work counts toward the 750-hour REPS goal.")
                .font(AppTypography.caption)
                .foregroundStyle(colors.textSecondary)
        }
    }

    private var previewCard: some View {
        categoryEditCard(title: "Preview") {
            HStack(spacing: 12) {
                Image(systemName: selectedIcon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: selectedColor))
                    .frame(width: 38, height: 38)
                    .background(Color(hex: selectedColor).opacity(colorScheme == .dark ? 0.18 : 0.12))
                    .clipShape(Circle())
                Text(name.isEmpty ? "Category name" : name)
                    .font(AppTypography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(name.isEmpty ? colors.textTertiary : colors.textPrimary)
                Spacer()
            }
        }
    }

    private func categoryEditCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textPrimary)
            content()
        }
        .padding(18)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xxl))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.xxl)
                .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
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
