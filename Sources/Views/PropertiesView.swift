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

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.properties.isEmpty {
                    // MARK: - Empty State
                    VStack(spacing: 20) {
                        JellyBadge(
                            systemName: "building-2",
                            color: AppColors.primary,
                            wash: colors.primarySurface,
                            size: 72
                        )

                        Text("No Properties Yet")
                            .font(AppTypography.headline)
                            .foregroundStyle(colors.textPrimary)

                        Text("Add your first rental property\nto start tracking time")
                            .font(AppTypography.body)
                            .foregroundStyle(colors.textSecondary)
                            .multilineTextAlignment(.center)

                        Button {
                            if viewModel.canAddProperty() {
                                showingAddProperty = true
                            } else {
                                showingPaywall = true
                            }
                        } label: {
                            Label { Text("Add Property") } icon: { lucideImage(Lucide.plus) }
                                .font(AppTypography.button)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppColors.primary)
                                .foregroundStyle(Color.white)
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(colors.background)
                } else {
                    // MARK: - Property List
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(viewModel.properties) { property in
                                PropertyListCard(property: property, hours: viewModel.totalHoursForProperty(property.id)) {
                                    viewModel.deleteProperty(property)
                                }
                                .onTapGesture {
                                    selectedProperty = property
                                }
                            }

                            // Add Property button at bottom of list
                            Button {
                                if viewModel.canAddProperty() {
                                    showingAddProperty = true
                                } else {
                                    showingPaywall = true
                                }
                            } label: {
                                Label { Text("Add Property") } icon: { lucideImage(Lucide.plus) }
                                    .font(AppTypography.button)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(AppColors.primary)
                                    .foregroundStyle(Color.white)
                                    .clipShape(Capsule())
                            }
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .background(colors.background)
                }
            }
            .navigationTitle("Properties")
            .toolbar {
                Button {
                    if viewModel.canAddProperty() {
                        showingAddProperty = true
                    } else {
                        showingPaywall = true
                    }
                } label: {
                    LucideIcon(image: Lucide.circlePlus, size: 22)
                        .foregroundStyle(AppColors.primary)
                }
            }
            .sheet(isPresented: $showingAddProperty) {
                AddPropertyView()
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(showPaywall: $showingPaywall)
            }
            .sheet(item: $selectedProperty) { property in
                PropertyDetailView(property: property)
            }
        }
    }
}

// MARK: - Property List Card
struct PropertyListCard: View {
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    let property: RentalProperty
    let hours: Double
    let onDelete: () -> Void

    private var typeColor: Color {
        property.propertyType == .str ? AppColors.honey : AppColors.primary
    }

    var body: some View {
        HStack(spacing: 14) {
            // Jelly icon badge
            JellyBadge(
                systemName: property.propertyType == .str ? "bed-double" : "house",
                color: typeColor,
                wash: property.propertyType == .str ? colors.honeyWash : colors.primarySurface,
                size: 52
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(property.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)

                Text(property.address)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    // Type badge capsule
                    Text(property.propertyType.rawValue)
                        .font(AppTypography.label)
                        .foregroundStyle(typeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            property.propertyType == .str
                                ? colors.honeyWash
                                : colors.primarySurface
                        )
                        .clipShape(Capsule())

                    Text(String(format: "%.1fh total", hours))
                        .font(AppTypography.caption)
                        .foregroundStyle(colors.textSecondary)
                }
            }

            Spacer()

            Button(action: onDelete) {
                LucideIcon(image: Lucide.trash2, size: 14)
                    .foregroundStyle(AppColors.coral.opacity(0.8))
            }
        }
        .padding(16)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.xl))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 10, x: 0, y: 2)
    }
}

// MARK: - Add Property View
struct AddPropertyView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    let editingProperty: RentalProperty?

    @State private var name = ""
    @State private var address = ""
    @State private var propertyType: PropertyType = .ltr
    @State private var addressResults: [MKMapItem] = []
    @State private var isSearching = false
    @FocusState private var isAddressFocused: Bool

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
            Form {
                Section {
                    TextField("Property Name", text: $name)

                    // Address with autocomplete
                    ZStack(alignment: .topLeading) {
                        TextField("Address", text: $address)
                            .focused($isAddressFocused)
                            .onChange(of: address) { _, newValue in
                                if newValue.count > 2 {
                                    searchAddress(query: newValue)
                                } else {
                                    addressResults = []
                                }
                            }

                        if !addressResults.isEmpty && isAddressFocused {
                            VStack(spacing: 0) {
                                ForEach(addressResults.prefix(5), id: \.self) { item in
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
                                        .background(colors.backgroundSecondary)
                                    }
                                    .buttonStyle(.plain)

                                    Divider()
                                }
                            }
                            .background(colors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.small))
                            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                        }
                    }
                }

                Section("Property Type") {
                    Picker("Type", selection: $propertyType) {
                        HStack {
                            LucideIcon(image: Lucide.house, size: 16)
                                .foregroundStyle(AppColors.primary)
                            Text("Long-Term Rental")
                        }
                        .tag(PropertyType.ltr)

                        HStack {
                            LucideIcon(image: Lucide.bedDouble, size: 16)
                                .foregroundStyle(AppColors.honey)
                            Text("Short-Term (Airbnb/VRBO)")
                        }
                        .tag(PropertyType.str)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.background)
            .navigationTitle(editingProperty != nil ? "Edit Property" : "Add Property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let existingProperty = editingProperty {
                            // Update existing property
                            var updatedProperty = existingProperty
                            updatedProperty.name = name
                            updatedProperty.address = address
                            updatedProperty.propertyType = propertyType
                            viewModel.updateProperty(updatedProperty)
                        } else {
                            // Add new property
                            viewModel.addProperty(name: name, address: address, type: propertyType)
                        }
                        dismiss()
                    }
                    .disabled(name.isEmpty || address.isEmpty)
                    .foregroundStyle(name.isEmpty || address.isEmpty ? colors.textTertiary : AppColors.primary)
                }
            }
        }
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
        isAddressFocused = false
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
    @State private var showingEditSheet = false
    @State private var addressResults: [MKMapItem] = []
    @FocusState private var isAddressFocusedDetail: Bool

    init(property: RentalProperty) {
        self.property = property
        _name = State(initialValue: property.name)
        _address = State(initialValue: property.address)
        _propertyType = State(initialValue: property.propertyType)
    }

    private var typeColor: Color {
        propertyType == .str ? AppColors.honey : AppColors.primary
    }

    var body: some View {
        NavigationStack {
            List {
                // Property header with JellyBadge
                Section {
                    HStack(spacing: 14) {
                        JellyBadge(
                            systemName: propertyType == .str ? "bed-double" : "house",
                            color: typeColor,
                            wash: propertyType == .str ? colors.honeyWash : colors.primarySurface,
                            size: 48
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(name)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(colors.textPrimary)
                            Text(address)
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(colors.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .listRowBackground(colors.backgroundSecondary)
                }

                Section("Property Details") {
                    TextField("Name", text: $name)
                        .onChange(of: name) { _, _ in hasChanges = true }

                    // Address with autocomplete
                    ZStack(alignment: .topLeading) {
                        TextField("Address", text: $address)
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
                            VStack(spacing: 0) {
                                ForEach(addressResults.prefix(5), id: \.self) { item in
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
                                        .background(colors.backgroundSecondary)
                                    }
                                    .buttonStyle(.plain)

                                    Divider()
                                }
                            }
                            .background(colors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.small))
                            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                        }
                    }

                    Picker("Type", selection: $propertyType) {
                        Text("Long-Term Rental").tag(PropertyType.ltr)
                        Text("Short-Term Rental").tag(PropertyType.str)
                    }
                    .onChange(of: propertyType) { _, _ in hasChanges = true }
                }
                .listRowBackground(colors.backgroundSecondary)

                Section("Statistics") {
                    HStack {
                        Text("Total Hours Logged")
                            .font(AppTypography.body)
                            .foregroundStyle(colors.textPrimary)
                        Spacer()
                        Text(String(format: "%.1f hours", totalHours))
                            .font(AppTypography.body)
                            .foregroundStyle(colors.textSecondary)
                    }

                    HStack {
                        Text("This Year")
                            .font(AppTypography.body)
                            .foregroundStyle(colors.textPrimary)
                        Spacer()
                        Text(String(format: "%.1f hours", yearHours))
                            .font(AppTypography.body)
                            .foregroundStyle(colors.textSecondary)
                    }

                    HStack {
                        Text("Time Entries")
                            .font(AppTypography.body)
                            .foregroundStyle(colors.textPrimary)
                        Spacer()
                        Text("\(entryCount)")
                            .font(AppTypography.body)
                            .foregroundStyle(colors.textSecondary)
                    }
                }
                .listRowBackground(colors.backgroundSecondary)

                Section("Location") {
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
                        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
                    } else {
                        HStack {
                            Spacer()
                            ProgressView("Loading location...")
                                .foregroundStyle(colors.textSecondary)
                            Spacer()
                        }
                    }
                }
                .listRowBackground(colors.backgroundSecondary)

                if hasChanges {
                    Section {
                        Button {
                            saveChanges()
                        } label: {
                            Text("Save Changes")
                                .font(AppTypography.button)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundStyle(Color.white)
                        }
                        .listRowBackground(AppColors.primary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.background)
            .navigationTitle("Property Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(colors.textSecondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        showingEditSheet = true
                    }
                    .foregroundStyle(AppColors.primary)
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                AddPropertyView(property: property)
            }
            .onAppear {
                loadCoordinate()
            }
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
