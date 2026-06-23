import SwiftUI
import MapKit
import CoreLocation
import LucideIcons

struct PropertiesView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    @State private var showingAddProperty = false
    @State private var selectedProperty: RentalProperty?
    @State private var showingPaywall = false
    @State private var propertyToDelete: RentalProperty?
    @State private var showingDeleteConfirmation = false
#if DEBUG
    @State private var didHandleDebugLaunchSurface = false
#endif

    private var totalPortfolioHours: Double {
        viewModel.properties.reduce(0) { partial, property in
            partial + viewModel.totalHoursForProperty(property.id)
        }
    }

    private var ltrCount: Int {
        viewModel.properties.filter { $0.propertyType == .ltr }.count
    }

    private var strCount: Int {
        viewModel.properties.filter { $0.propertyType == .str }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LHMobileCanvas()

                if viewModel.properties.isEmpty {
                    // MARK: - Empty State
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 18) {
                            headerSection
                            emptyPortfolioCard
                            setupPreviewCard
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, AppSpacing.tabContentBottomInset)
                    }
                } else {
                    // MARK: - Property List
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 18) {
                            headerSection
                            portfolioSummaryCard

                            ForEach(viewModel.properties) { property in
                                PropertyListCard(
                                    property: property,
                                    hours: viewModel.totalHoursForProperty(property.id),
                                    yearHours: viewModel.hoursForProperty(property, year: Calendar.current.component(.year, from: Date())),
                                    entryCount: viewModel.timeEntries.filter { $0.propertyId == property.id }.count,
                                    onOpen: {
                                        selectedProperty = property
                                    },
                                    onDelete: {
                                    propertyToDelete = property
                                    showingDeleteConfirmation = true
                                    }
                                )
                            }

                            // Add Property button at bottom of list
                            addPropertyRow
                                .padding(.top, 2)
                            .guidedSpotlightTarget(.addProperty)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, AppSpacing.tabContentBottomInset)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingAddProperty, onDismiss: {
                NotificationCenter.default.post(name: .resumeGuidedOnboardingOverlay, object: nil)
            }) {
                AddPropertyView()
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(showPaywall: $showingPaywall)
            }
            .sheet(item: $selectedProperty) { property in
                PropertyDetailView(property: property)
            }
            .alert("Delete Property?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { propertyToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let property = propertyToDelete {
                        viewModel.deleteProperty(property)
                    }
                    propertyToDelete = nil
                }
            } message: {
                Text("This will permanently delete \"\(propertyToDelete?.name ?? "")\" and all its time entries. This cannot be undone.")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openAddProperty)) { _ in
                if viewModel.canAddProperty() {
                    NotificationCenter.default.post(name: .suspendGuidedOnboardingOverlay, object: nil)
                    showingAddProperty = true
                } else {
                    showingPaywall = true
                }
            }
#if DEBUG
            .onAppear {
                handleDebugLaunchSurfaceIfNeeded()
            }
#endif
        }
    }

    private var emptyPortfolioCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                JellyBadge(systemName: "building-2", color: AppColors.primary, wash: colors.primarySurface, size: 52)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Create the property record")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Then log repairs, management, leasing, and spouse work against the right rental.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                openAddProperty()
            } label: {
                Label { Text("Add first property") } icon: { lucideImage(Lucide.plus) }
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(colors.action)
                    .foregroundStyle(AppColors.onAction)
                    .clipShape(Capsule())
            }
            .buttonStyle(.lhPressable)
            .guidedSpotlightTarget(.addProperty)
        }
        .padding(18)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(colors.border.opacity(0.25), lineWidth: 1)
        }
    }

    private var setupPreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What this unlocks")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)

            setupPreviewRow(icon: Lucide.clock3, title: "Cleaner time logs", detail: "Each entry links to a property for review.")
            setupPreviewRow(icon: Lucide.badgeCheck, title: "Tax-ready grouping", detail: "LTR and STR activity stays separated.")
            setupPreviewRow(icon: Lucide.fileText, title: "Better exports", detail: "Reports can show hours by property.")
        }
        .padding(18)
        .background(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.72 : 0.78))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(colors.border.opacity(0.22), lineWidth: 1)
        }
    }

    private func setupPreviewRow(icon: UIImage, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            LucideIcon(image: icon, size: 18)
                .foregroundStyle(colors.action)
                .frame(width: 34, height: 34)
                .background(colors.actionSurface)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Text(detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var portfolioSummaryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portfolio evidence")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text("Hours organized by rental type")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                Text(String(format: "%.0fh", totalPortfolioHours))
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            HStack(spacing: 10) {
                portfolioMetric(title: "Properties", value: "\(viewModel.properties.count)", icon: Lucide.building2, color: AppColors.primary, wash: colors.primarySurface)
                portfolioMetric(title: "LTR", value: "\(ltrCount)", icon: Lucide.house, color: AppColors.sage, wash: colors.sageWash)
                portfolioMetric(title: "STR", value: "\(strCount)", icon: Lucide.bedDouble, color: AppColors.honey, wash: colors.honeyWash)
            }
        }
        .padding(18)
        .premiumGlassCard(cornerRadius: 24, colors: colors, colorScheme: colorScheme)
    }

    private func portfolioMetric(title: String, value: String, icon: UIImage, color: Color, wash: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LucideIcon(image: icon, size: 16)
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(wash)
                .clipShape(Circle())
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.64 : 0.74))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var addPropertyRow: some View {
        Button {
            openAddProperty()
        } label: {
            HStack(spacing: 12) {
                LucideIcon(image: Lucide.plus, size: 18)
                    .foregroundStyle(colors.action)
                    .frame(width: 38, height: 38)
                    .background(colors.actionSurface)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add another property")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text(viewModel.canAddProperty() ? "Keep each rental's evidence separate." : "Upgrade to track more properties.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                LucideIcon(image: Lucide.chevronRight, size: 18)
                    .foregroundStyle(colors.textTertiary)
            }
            .padding(16)
            .background(colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(colors.border.opacity(0.24), lineWidth: 1)
            }
        }
        .buttonStyle(.lhPressable)
    }

    private func openAddProperty() {
        if viewModel.canAddProperty() {
            showingAddProperty = true
        } else {
            showingPaywall = true
        }
    }

#if DEBUG
    private func handleDebugLaunchSurfaceIfNeeded() {
        guard !didHandleDebugLaunchSurface else { return }
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-LHOpenAddProperty") || args.contains("-LHOpenFirstPropertyDetail") else { return }
        didHandleDebugLaunchSurface = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if args.contains("-LHOpenAddProperty") {
                openAddProperty()
            } else if args.contains("-LHOpenFirstPropertyDetail"),
                      let firstProperty = viewModel.properties.first {
                selectedProperty = firstProperty
            }
        }
    }
#endif

    // MARK: - Header
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Properties")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .minimumScaleFactor(0.82)
                Text(propertyHeaderSubtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            Button {
                openAddProperty()
            } label: {
                    LucideIcon(image: Lucide.circlePlus, size: 22)
                    .foregroundStyle(colors.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .guidedSpotlightTarget(.addProperty)
            .accessibilityLabel("Add property")
        }
    }

    private var propertyHeaderSubtitle: String {
        if viewModel.properties.isEmpty {
            return "Add the rental each hour should belong to."
        }
        return "\(viewModel.properties.count) rental \(viewModel.properties.count == 1 ? "place" : "places")"
    }
}

// MARK: - Property List Card
struct PropertyListCard: View {
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    let property: RentalProperty
    let hours: Double
    let yearHours: Double
    let entryCount: Int
    let onOpen: () -> Void
    let onDelete: () -> Void

    private var typeColor: Color {
        property.propertyType == .str ? AppColors.honey : AppColors.sage
    }

    private var typeWash: Color {
        property.propertyType == .str ? colors.honeyWash : colors.sageWash
    }

    private var goalHours: Double {
        property.propertyType == .str ? 100 : 750
    }

    private var progress: Double {
        min(max(yearHours / max(goalHours, 1), 0), 1)
    }

    private var evidenceLabel: String {
        property.propertyType == .str ? "STR material participation" : "REPS evidence"
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    JellyBadge(
                        systemName: property.propertyType == .str ? "bed-double" : "house",
                        color: typeColor,
                        wash: typeWash,
                        size: 52
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(property.name)
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                            .lineLimit(1)

                        Text(property.address)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(colors.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    LucideIcon(image: Lucide.chevronRight, size: 18)
                        .foregroundStyle(colors.textTertiary)
                        .padding(.top, 6)
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(evidenceLabel)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(colors.textSecondary)
                        Spacer()
                        Text(String(format: "%.0fh / %.0fh", yearHours, goalHours))
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(colors.textPrimary)
                            .monospacedDigit()
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(colors.backgroundTertiary)
                            Capsule()
                                .fill(LinearGradient(colors: [typeColor, typeColor.opacity(0.62)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: proxy.size.width * progress)
                        }
                    }
                    .frame(height: 8)
                }

                HStack(spacing: 10) {
                    propertyMetric(title: property.propertyType.rawValue, value: "Type")
                    propertyMetric(title: String(format: "%.1fh", hours), value: "Total")
                    propertyMetric(title: "\(entryCount)", value: "Logs")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(property.name), \(property.address), \(property.propertyType.rawValue), \(String(format: "%.1f hours logged", hours))")
        .accessibilityHint("Opens property details")
        .accessibilityElement(children: .ignore)
        .padding(18)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(colors.border.opacity(0.28), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            Menu {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete property", systemImage: "trash")
                }
            } label: {
                LucideIcon(image: Lucide.ellipsis, size: 18)
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More actions for \(property.name)")
            .padding(.top, 54)
            .padding(.trailing, 14)
        }
    }

    private func propertyMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textSecondary)
            Text(title)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(colors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension View {
    @ViewBuilder
    func premiumGlassCard(cornerRadius: CGFloat, colors: AdaptiveColors, colorScheme: ColorScheme) -> some View {
        if #available(iOS 26.0, *) {
            self
                .background(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.42 : 0.34))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .glassEffect(.regular.tint(colors.actionSurface.opacity(colorScheme == .dark ? 0.16 : 0.32)), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(colors.border.opacity(0.24), lineWidth: 1)
                }
        }
    }
}

// MARK: - Add Property View
struct AddPropertyView: View {
    private enum FocusedField {
        case name
        case address
    }

    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    let editingProperty: RentalProperty?

    @State private var name = ""
    @State private var address = ""
    @State private var propertyType: PropertyType = .ltr
    @State private var addressResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var showDuplicateWarning = false
    @FocusState private var focusedField: FocusedField?

    init(property: RentalProperty? = nil) {
        self.editingProperty = property
        if let property = property {
            _name = State(initialValue: property.name)
            _address = State(initialValue: property.address)
            _propertyType = State(initialValue: property.propertyType)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LHMobileCanvas()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        addPropertyHeader
                        propertySetupSummary
                        propertyIdentitySection
                        propertyTypeSection
                        firstPropertyNudge
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 120)
                }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .bottom) {
                savePropertyFooter
            }
            .alert("Duplicate Name", isPresented: $showDuplicateWarning) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("A property named \"\(name)\" already exists. Please use a different name.")
            }
        }
    }

    private var addPropertyHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    LucideIcon(image: Lucide.x, size: 20)
                        .foregroundStyle(colors.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(colors.backgroundTertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")

                Spacer()
            }

            Text(editingProperty != nil ? "Edit property" : "Add property")
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)
                .lineSpacing(-2)
                .minimumScaleFactor(0.82)

            Text("Name the place, choose the rental type, and keep future hours organized.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(colors.textSecondary)
                .lineSpacing(3)
        }
    }

    private var propertySetupSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 13) {
                JellyBadge(systemName: "clipboard-check", color: AppColors.primary, wash: colors.primarySurface, size: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text(editingProperty == nil ? "Create the evidence container" : "Keep the evidence container current")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text("Every log, report, and export becomes easier to review once the property identity is clean.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                setupSummaryPill(icon: Lucide.house, title: "Name", value: name.isEmpty ? "Needed" : "Ready")
                setupSummaryPill(icon: Lucide.mapPin, title: "Address", value: address.isEmpty ? "Needed" : "Ready")
                setupSummaryPill(icon: propertyType == .str ? Lucide.bedDouble : Lucide.house, title: "Type", value: propertyType.rawValue)
            }
        }
        .padding(18)
        .premiumGlassCard(cornerRadius: 24, colors: colors, colorScheme: colorScheme)
    }

    private func setupSummaryPill(icon: UIImage, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            LucideIcon(image: icon, size: 15)
                .foregroundStyle(colors.action)
                .frame(width: 28, height: 28)
                .background(colors.actionSurface)
                .clipShape(Circle())
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textSecondary)
            Text(value)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.64 : 0.76))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var propertyIdentitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            propertyTextField(
                title: "Property name",
                placeholder: "Oak Street Duplex",
                text: $name,
                icon: Lucide.house,
                accessibilityIdentifier: "property.name",
                focusedField: .name,
                submitLabel: .next
            )
            .onSubmit {
                focusedField = .address
            }

            VStack(alignment: .leading, spacing: 8) {
                propertyTextField(
                    title: "Address",
                    placeholder: "123 Oak Street",
                    text: $address,
                    icon: Lucide.mapPin,
                    accessibilityIdentifier: "property.address",
                    focusedField: .address,
                    submitLabel: .done
                )
                    .onSubmit {
                        focusedField = nil
                    }
                    .onChange(of: address) { _, newValue in
                        if newValue.count > 2 {
                            searchAddress(query: newValue)
                        } else {
                            addressResults = []
                        }
                    }

                if !addressResults.isEmpty && focusedField == .address {
                    VStack(spacing: 0) {
                        ForEach(addressResults.prefix(5), id: \.self) { item in
                            Button {
                                selectAddress(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Unknown")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(colors.textPrimary)
                                    if let addr = item.placemark.title {
                                        Text(addr)
                                            .font(AppTypography.caption)
                                            .foregroundStyle(colors.textSecondary)
                                            .lineLimit(2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 14)
                                .background(colors.backgroundSecondary)
                            }
                            .buttonStyle(.plain)

                            if item != addressResults.prefix(5).last {
                                Divider()
                            }
                        }
                    }
                    .background(colors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(colors.border.opacity(0.28), lineWidth: 1)
                    }
                }
            }
        }
        .padding(18)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(colors.border.opacity(0.28), lineWidth: 1)
        }
    }

    private func propertyTextField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        icon: UIImage,
        accessibilityIdentifier: String,
        focusedField field: FocusedField,
        submitLabel: SubmitLabel
    ) -> some View {
        HStack(spacing: 12) {
            LucideIcon(image: icon, size: 18)
                .foregroundStyle(colors.textPrimary)
                .frame(width: 38, height: 38)
                .background(colors.backgroundTertiary)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                TextField("", text: text, prompt: Text(placeholder).foregroundStyle(colors.textSecondary))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: field)
                    .submitLabel(submitLabel)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier(accessibilityIdentifier)
            }
        }
        .padding(14)
        .background(colors.backgroundTertiary.opacity(colorScheme == .dark ? 0.72 : 0.9))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            focusedField = field
        }
    }

    private var propertyTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Evidence profile")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Text("LTR and STR hours support different tax questions, so choose the profile before logging.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(colors.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                propertyTypeOption(.ltr, title: "Long-term", subtitle: "LTR", icon: Lucide.house, color: AppColors.sage)
                propertyTypeOption(.str, title: "Short-term", subtitle: "STR", icon: Lucide.bedDouble, color: AppColors.honey)
            }
        }
        .padding(18)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(colors.border.opacity(0.25), lineWidth: 1)
        }
    }

    private func propertyTypeOption(_ type: PropertyType, title: String, subtitle: String, icon: UIImage, color: Color) -> some View {
        Button {
            animate(AppAnimation.quick) {
                propertyType = type
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                LucideIcon(image: icon, size: 22)
                    .foregroundStyle(propertyType == type ? AppColors.charcoal : colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(propertyType == type ? color : colors.backgroundTertiary)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(propertyType == type ? color.opacity(colorScheme == .dark ? 0.22 : 0.28) : colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(propertyType == type ? color.opacity(0.62) : colors.border.opacity(0.28), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var firstPropertyNudge: some View {
        if editingProperty == nil && viewModel.properties.isEmpty && !GuidedOnboardingStore.isCompleted && !GuidedOnboardingStore.isSkipped {
            HStack(spacing: 10) {
                LHIconTile(icon: Lucide.mapPinHouse, color: AppColors.sage, wash: colors.sageWash, size: 34, isActive: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("A nickname is enough")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text("Use the name you naturally say when logging work.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
            }
            .padding(14)
            .background(AppColors.sageWash.opacity(colorScheme == .dark ? 0.18 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var savePropertyFooter: some View {
        VStack(spacing: 0) {
            Button {
                saveProperty()
            } label: {
                Text(editingProperty != nil ? "Save Changes" : "Save Property")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(canSaveProperty ? AppColors.onAction : colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(canSaveProperty ? colors.action : colors.backgroundTertiary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSaveProperty)
            .accessibilityIdentifier("property.save")
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
        }
    }

    private var canSaveProperty: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveProperty() {
        guard canSaveProperty else { return }
        let normalizedName = normalizedPropertyName(name)
        if viewModel.properties.contains(where: { property in
            property.id != editingProperty?.id && normalizedPropertyName(property.name) == normalizedName
        }) {
            showDuplicateWarning = true
            return
        }
        if let existingProperty = editingProperty {
            var updatedProperty = existingProperty
            updatedProperty.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedProperty.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedProperty.propertyType = propertyType
            viewModel.updateProperty(updatedProperty)
        } else {
            viewModel.addProperty(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                type: propertyType
            )
        }
        dismiss()
    }

    private func normalizedPropertyName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    func searchAddress(query: String) {
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address

        let search = MKLocalSearch(request: request)
        search.start { response, error in
            isSearching = false
            if let response = response {
                addressResults = response.mapItems
            } else {
                addressResults = []
            }
        }
    }

    func selectAddress(_ item: MKMapItem) {
        let placemark = item.placemark
        var addressString = ""

        if let streetNumber = placemark.subThoroughfare {
            addressString += streetNumber + " "
        }
        if let street = placemark.thoroughfare {
            addressString += street + ", "
        }
        if let city = placemark.locality {
            addressString += city + ", "
        }
        if let state = placemark.administrativeArea {
            addressString += state + " "
        }
        if let zip = placemark.postalCode {
            addressString += zip
        }

        address = addressString.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        addressResults = []
        focusedField = nil
    }

    private func animate(_ animation: Animation = AppAnimation.smooth, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }
}

// MARK: - Property Detail View
struct PropertyDetailView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    let property: RentalProperty

    @State private var name: String
    @State private var address: String
    @State private var propertyType: PropertyType
    @State private var hasChanges = false
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var addressResults: [MKMapItem] = []
    @FocusState private var isAddressFocusedDetail: Bool

    init(property: RentalProperty) {
        self.property = property
        _name = State(initialValue: property.name)
        _address = State(initialValue: property.address)
        _propertyType = State(initialValue: property.propertyType)
    }

    private var typeColor: Color {
        propertyType == .str ? AppColors.honey : AppColors.sage
    }

    private var typeWash: Color {
        propertyType == .str ? colors.honeyWash : colors.sageWash
    }

    private var evidenceGoalHours: Double {
        propertyType == .str ? 100 : 750
    }

    private var evidenceProgress: Double {
        min(max(yearHours / max(evidenceGoalHours, 1), 0), 1)
    }

    private var evidenceTitle: String {
        propertyType == .str ? "STR material participation" : "REPS evidence"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader
                    evidenceOverviewCard
                    propertyDetailsCard
                    locationCard
                    if hasChanges {
                        saveButton
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .background { LHMobileCanvas() }
            .navigationTitle("Property Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(colors.textSecondary)
                }
            }
            .onAppear {
                loadCoordinate()
            }
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 14) {
            JellyBadge(
                systemName: propertyType == .str ? "bed-double" : "house",
                color: typeColor,
                wash: typeWash,
                size: 54
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(name.isEmpty ? "Unnamed property" : name)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(2)
                Text(address.isEmpty ? "No address added" : address)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(18)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xxl))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.xxl)
                .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
        }
    }

    private var propertyDetailsCard: some View {
        propertyDetailCard(title: "Property identity") {
            VStack(spacing: 12) {
                propertyTextField("Name", text: $name)

                VStack(alignment: .leading, spacing: 8) {
                    propertyTextField("Address", text: $address)
                        .focused($isAddressFocusedDetail)
                        .onChange(of: address) { _, newValue in
                            hasChanges = true
                            if newValue.count > 2 {
                                searchAddress(query: newValue)
                            } else {
                                addressResults = []
                            }
                        }

                    if !addressResults.isEmpty && isAddressFocusedDetail {
                        addressResultsMenu
                    }
                }

                Picker("Type", selection: $propertyType) {
                    Text("Long-Term Rental").tag(PropertyType.ltr)
                    Text("Short-Term Rental").tag(PropertyType.str)
                }
                .pickerStyle(.segmented)
                .onChange(of: propertyType) { _, _ in hasChanges = true }
            }
        }
    }

    private var evidenceOverviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(evidenceTitle)
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text(propertyType == .str ? "Track toward the 100-hour material participation test." : "Track annual hours toward the 750-hour REPS threshold.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(String(format: "%.0fh", yearHours))
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("This tax year")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textSecondary)
                    Spacer()
                    Text(String(format: "%.0fh / %.0fh", yearHours, evidenceGoalHours))
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                        .monospacedDigit()
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(colors.backgroundTertiary)
                        Capsule()
                            .fill(LinearGradient(colors: [typeColor, typeColor.opacity(0.62)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * evidenceProgress)
                    }
                }
                .frame(height: 8)
            }

            HStack(spacing: 10) {
                evidenceMetric(title: "Total", value: String(format: "%.1fh", totalHours))
                evidenceMetric(title: "Logs", value: "\(entryCount)")
                evidenceMetric(title: "Type", value: propertyType.rawValue)
            }
        }
        .padding(18)
        .premiumGlassCard(cornerRadius: 24, colors: colors, colorScheme: colorScheme)
    }

    private func evidenceMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(colors.textSecondary)
            Text(value)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(colors.backgroundSecondary.opacity(colorScheme == .dark ? 0.64 : 0.76))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func propertyTextField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .font(AppTypography.body)
            .foregroundStyle(colors.textPrimary)
            .padding(14)
            .background(colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
            .overlay {
                RoundedRectangle(cornerRadius: AppCornerRadius.large)
                    .strokeBorder(colors.border.opacity(0.25), lineWidth: 1)
            }
            .onChange(of: text.wrappedValue) { _, _ in hasChanges = true }
    }

    private var addressResultsMenu: some View {
        VStack(spacing: 0) {
            ForEach(Array(addressResults.prefix(5).enumerated()), id: \.element) { index, item in
                Button {
                    selectAddress(item)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? "Unknown")
                            .font(AppTypography.body)
                            .foregroundStyle(colors.textPrimary)
                        if let addr = item.placemark.title {
                            Text(addr)
                                .font(AppTypography.caption)
                                .foregroundStyle(colors.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)

                if index < min(addressResults.count, 5) - 1 {
                    Divider()
                }
            }
        }
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.large)
                .strokeBorder(colors.border.opacity(0.35), lineWidth: 1)
        }
    }

    private var locationCard: some View {
        propertyDetailCard(title: "Location") {
            if let coordinate = coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))) {
                    Annotation("", coordinate: coordinate) {
                        LucideIcon(image: Lucide.house, size: 16)
                            .foregroundStyle(AppColors.primary)
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading location...")
                        .font(AppTypography.body)
                        .foregroundStyle(colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }
        }
    }

    private var saveButton: some View {
        Button { saveChanges() } label: {
            Text("Save changes")
                .font(AppTypography.button)
                .foregroundStyle(AppColors.onAction)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(colors.action)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func propertyDetailCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
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

    func loadCoordinate() {
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(address) { placemarks, _ in
            if let location = placemarks?.first?.location {
                Task { @MainActor in
                    self.coordinate = location.coordinate
                }
            }
        }
    }

    var totalHours: Double {
        viewModel.totalHoursForProperty(property.id)
    }

    var yearHours: Double {
        let currentYear = Calendar.current.component(.year, from: Date())
        return viewModel.hoursForProperty(property, year: currentYear)
    }

    var entryCount: Int {
        viewModel.timeEntries.filter { $0.propertyId == property.id }.count
    }

    func searchAddress(query: String) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address

        let search = MKLocalSearch(request: request)
        search.start { response, error in
            if let response = response {
                Task { @MainActor in
                    self.addressResults = response.mapItems
                }
            }
        }
    }

    func selectAddress(_ item: MKMapItem) {
        let placemark = item.placemark
        var addressString = ""

        if let streetNumber = placemark.subThoroughfare {
            addressString += streetNumber + " "
        }
        if let street = placemark.thoroughfare {
            addressString += street + ", "
        }
        if let city = placemark.locality {
            addressString += city + ", "
        }
        if let state = placemark.administrativeArea {
            addressString += state + " "
        }
        if let zip = placemark.postalCode {
            addressString += zip
        }

        address = addressString.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        addressResults = []
        isAddressFocusedDetail = false
        hasChanges = true
    }

    func saveChanges() {
        var updated = property
        updated.name = name
        updated.address = address
        updated.propertyType = propertyType
        viewModel.updateProperty(updated)
        hasChanges = false
        dismiss()
    }
}

#Preview {
    PropertiesView()
        .environmentObject(AppViewModel())
}
