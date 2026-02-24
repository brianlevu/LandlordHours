import SwiftUI
import MapKit
import CoreLocation

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
                    VStack(spacing: 20) {
                        LHSoftBadge(icon: .properties, color: AppColors.primary, size: 72)
                        Text("No Properties Yet")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(colors.textPrimary)
                        Text("Add your first rental property\nto start tracking time")
                            .font(.system(size: 15))
                            .foregroundStyle(colors.textSecondary)
                            .multilineTextAlignment(.center)
                        Button {
                            if viewModel.canAddProperty() {
                                showingAddProperty = true
                            } else {
                                showingPaywall = true
                            }
                        } label: {
                            Label("Add Property", systemImage: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .padding(.horizontal, 28)
                                .padding(.vertical, 14)
                                .background(AppColors.primary)
                                .foregroundStyle(Color.white)
                                .clipShape(Capsule())
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(colors.background)
                } else {
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
                    LHIconView(icon: .plusCircle, size: 24, color: AppColors.primary)
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

struct PropertyListCard: View {
    @Environment(\.colorScheme) var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    let property: RentalProperty
    let hours: Double
    let onDelete: () -> Void

    private var typeColor: Color { property.propertyType == .str ? AppColors.warning : AppColors.primary }

    var body: some View {
        HStack(spacing: 16) {
            LHIconBadge(icon: property.propertyType == .str ? .properties : .home, bgColor: typeColor, fgColor: .white, size: 56)

            VStack(alignment: .leading, spacing: 5) {
                Text(property.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Text(property.address)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(property.propertyType.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(typeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(typeColor.opacity(0.1))
                        .clipShape(Capsule())

                    Text(String(format: "%.1fh total", hours))
                        .font(.system(size: 11))
                        .foregroundStyle(colors.textSecondary)
                }
            }

            Spacer()

            Button(action: onDelete) {
                LHIconView(icon: .trash, size: 14, color: .red.opacity(0.6))
            }
        }
        .padding(16)
        .background(colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 10, x: 0, y: 2)
    }
}

struct AddPropertyView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    
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
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                            if let addr = item.placemark.title {
                                                Text(addr)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 12)
                                        .background(Color(.systemBackground))
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                }
                            }
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                        }
                    }
                }
                
                Section("Property Type") {
                    Picker("Type", selection: $propertyType) {
                        HStack {
                            LHIconView(icon: .home, size: 18, color: AppColors.primary)
                            Text("Long-Term Rental")
                        }
                        .tag(PropertyType.ltr)

                        HStack {
                            LHIconView(icon: .home, size: 18, color: AppColors.primary)
                            Text("Short-Term (Airbnb/VRBO)")
                        }
                        .tag(PropertyType.str)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Add Property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
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
    
    var body: some View {
        NavigationStack {
            List {
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
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                            if let addr = item.placemark.title {
                                                Text(addr)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 12)
                                        .background(Color(.systemBackground))
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                }
                            }
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                        }
                    }
                    
                    Picker("Type", selection: $propertyType) {
                        Text("Long-Term Rental").tag(PropertyType.ltr)
                        Text("Short-Term Rental").tag(PropertyType.str)
                    }
                    .onChange(of: propertyType) { _, _ in hasChanges = true }
                }
                
                Section("Statistics") {
                    HStack {
                        Text("Total Hours Logged")
                        Spacer()
                        Text(String(format: "%.1f hours", totalHours))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("This Year")
                        Spacer()
                        Text(String(format: "%.1f hours", yearHours))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Time Entries")
                        Spacer()
                        Text("\(entryCount)")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Location") {
                    if let coordinate = coordinate {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))) {
                            Annotation("", coordinate: coordinate) {
                                Image(systemName: "house.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        ProgressView("Loading location...")
                    }
                }
                
                if hasChanges {
                    Section {
                        Button("Save Changes") {
                            saveChanges()
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Property Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        showingEditSheet = true
                    }
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
