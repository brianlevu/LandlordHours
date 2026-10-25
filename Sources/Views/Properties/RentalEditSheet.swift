import SwiftUI
import MapKit

// MARK: - The rental edit sheet (v2, plan package F, row 12)
//
// `LHSheet` (§1.20) on the focused presentation (opaque `.large`, `backgroundSecondary`): title
// "New rental" / "Edit rental" with one `.icon` close · name and address as `LHField`s (the address
// offers map matches as you type) · "How do guests stay?" as `LHSegmented` (an `LHRow.Value` menu at
// AX sizes, where two long segments cannot fit) · other names as removable chips, an `LHField` and
// an "Add" `.tertiary`, with §C.5 line 7 under them · "I live here" as `LHRow.Toggle` · the §F.1
// "House" row (reserved, renders nothing) · "Delete rental" as the one destructive `.tertiary` ·
// the pinned `.primary` "Save" / "Add rental".
//
// A duplicate name is a field error, not an alert (§1.21: alerts only for irreversible acts).
// "Delete rental" closes the sheet and hands the rental to the presenter, whose one alert asks
// "Delete this rental?" with the verbs "Delete" and "Keep".

struct PropertyEditSheet: View {
    let mode: PropertyEditorMode
    /// "Delete rental": the sheet closes and the presenter asks (the one delete alert, §1.21).
    var onDelete: (RentalProperty) -> Void = { _ in }

    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    @State private var name = ""
    @State private var address = ""
    @State private var propertyType: PropertyType = .ltr
    @State private var aliases: [String] = []
    @State private var newAlias = ""
    @State private var isOwnerOccupied = false
    @State private var addressResults: [MKMapItem] = []
    /// The address the user picked from the matches: no search runs for it.
    @State private var pickedAddress: String?
    @State private var nameError: String?
    @State private var loaded = false

    private var ax: Bool { dynamicTypeSize.isAccessibilitySize }

    private var editing: RentalProperty? {
        if case .edit(let p, _) = mode { return viewModel.properties.first { $0.id == p.id } ?? p }
        return nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            LHSheet(editing != nil ? RentalsText.editRental : RentalsText.newRental, onClose: { dismiss() }) {
                VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                    nameAndAddress
                    stay
                    otherNames
                    LHRow.Toggle(RentalsText.liveHere, subtitle: RentalsText.liveHereSubtitle, isOn: $isOwnerOccupied)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                        .accessibilityIdentifier("property.ownerOccupied")
                    RentalHouseLookSlot(property: editing)
                    if editing != nil {
                        Button(RentalsText.deleteRental) {
                            if let editing { requestDelete(editing) }
                        }
                        .buttonStyle(LHButton.destructiveTertiary)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("property.delete")
                    }
                    Color.clear.frame(height: 1).id("propertySheet.bottom")
                }
                .padding(.top, 8)
            } footer: {
                Button(editing != nil ? RentalsText.save : RentalsText.addRental, action: save)
                    .buttonStyle(LHButton.primary)
                    .disabled(!canSave)
                    .accessibilityIdentifier("property.save")
                    .background(alignment: .top) { footerSurface }
            }
#if DEBUG
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-LHPropertySheetScrollBottom") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { proxy.scrollTo("propertySheet.bottom", anchor: .bottom) }
                }
            }
#endif
        }
        .onAppear(perform: load)
        .onChange(of: name) { _, _ in nameError = nil }
    }

    /// `LHSheet`'s footer inset has no surface, so the form showed through around the pinned button
    /// (reported to package A). The button carries the sheet's surface behind it, out to the sheet's
    /// edges and the home indicator, with a 24pt fade above so rows scroll out softly.
    private var footerSurface: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [colors.backgroundSecondary.opacity(0), colors.backgroundSecondary],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 24)
            colors.backgroundSecondary
        }
        .padding(.top, -32)
        .padding(.horizontal, -40)
        .padding(.bottom, -80)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Name and address

    private var nameAndAddress: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel(RentalsText.name)
                LHField(RentalsText.namePlaceholder, text: $name, error: nameError,
                        accessibilityLabel: RentalsText.name, identifier: "property.name")
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
            }
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel(RentalsText.address)
                LHField(RentalsText.addressPlaceholder, text: $address,
                        accessibilityLabel: RentalsText.address, identifier: "property.address")
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onChange(of: address) { _, value in
                        if value == pickedAddress { return }
                        pickedAddress = nil
                        if value.count > 2 { searchAddress(query: value) } else { addressResults = [] }
                    }
                if !addressResults.isEmpty {
                    addressResultsMenu
                }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.textSecondary)
            .accessibilityHidden(true)
    }

    private var addressResultsMenu: some View {
        VStack(spacing: 0) {
            ForEach(Array(addressResults.prefix(5).enumerated()), id: \.element) { index, item in
                Button { selectAddress(item) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? RentalsText.address).font(.body).foregroundStyle(colors.textPrimary)
                        if let line = item.placemark.title {
                            Text(line).font(.footnote).foregroundStyle(colors.textSecondary)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: LHMetrics.minTap, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(LHButton.press)
                if index < min(addressResults.count, 5) - 1 { LHDivider(leadingInset: 16) }
            }
        }
        .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
    }

    // MARK: How guests stay

    private var stay: some View {
        VStack(alignment: .leading, spacing: 8) {
            LHSectionHeader(RentalsText.stayQuestion)
            if ax {
                // At AX sizes two segments cannot hold "Long stays" and "A few nights" whole, so the
                // choice becomes two option rows with the trailing checkmark (§1.24's option rows).
                VStack(spacing: 0) {
                    stayOption(.ltr)
                    LHDivider(leadingInset: 16)
                    stayOption(.str)
                }
                .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("property.stay")
            } else {
                LHSegmented([.init(PropertyType.ltr, RentalsText.kind(.ltr)), .init(PropertyType.str, RentalsText.kind(.str))],
                            selection: $propertyType, accessibilityLabel: RentalsText.stayQuestion)
                    .accessibilityIdentifier("property.stay")
            }
            Text(RentalsText.stayFootnote)
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
        }
    }

    private func stayOption(_ type: PropertyType) -> some View {
        let selected = propertyType == type
        return Button {
            if reduceMotion { propertyType = type } else { withAnimation(AppAnimation.quick) { propertyType = type } }
        } label: {
            HStack(spacing: 12) {
                Text(RentalsText.kind(type))
                    .font(.body)
                    .foregroundStyle(colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colors.action)
                        .frame(minWidth: LHMetrics.minTap, minHeight: LHMetrics.minTap)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: LHMetrics.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(LHButton.press)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Other names

    private var trimmedNewAlias: String { newAlias.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAddAlias: Bool {
        trimmedNewAlias.count >= RentalProperty.aliasMinLength && aliases.count < RentalProperty.maxAliases
    }
    private var aliasHint: String? {
        if aliases.count >= RentalProperty.maxAliases { return RentalsText.aliasFull }
        if !trimmedNewAlias.isEmpty && trimmedNewAlias.count < RentalProperty.aliasMinLength { return RentalsText.aliasTooShort }
        return nil
    }

    private var otherNames: some View {
        VStack(alignment: .leading, spacing: 8) {
            LHSectionHeader(RentalsText.otherNames)
            if !aliases.isEmpty {
                PropertyChipFlow(spacing: 8) {
                    ForEach(aliases, id: \.self) { alias in aliasChip(alias) }
                }
            }
            let layout = ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
            layout {
                LHField(RentalsText.addAnotherName, text: $newAlias, accessibilityLabel: RentalsText.addAnotherName,
                        identifier: "property.alias.field")
                    .submitLabel(.done)
                    .onSubmit(addAlias)
                Button(RentalsText.add, action: addAlias)
                    .buttonStyle(LHButton.tertiary)
                    .disabled(!canAddAlias)
                    .frame(minHeight: LHField.height)
                    .accessibilityIdentifier("property.alias.add")
            }
            if let aliasHint {
                Text(aliasHint)
                    .font(.footnote)
                    .foregroundStyle(colors.caution)
                    .accessibilityIdentifier("property.alias.hint")
            }
            Text(RentalsText.otherNamesFootnote)
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
        }
    }

    private func aliasChip(_ alias: String) -> some View {
        HStack(spacing: 0) {
            Text(alias)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(colors.textPrimary)
                .lineLimit(ax ? 3 : 1)
                .padding(.leading, 12)
            Button {
                if reduceMotion { aliases.removeAll { $0 == alias } } else {
                    withAnimation(AppAnimation.quick) { aliases.removeAll { $0 == alias } }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: LHMetrics.minTap, height: LHMetrics.minTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(LHButton.press)
            .accessibilityLabel(RentalsText.removeName(alias))
        }
        .frame(minHeight: LHChip.height)
        .background(colors.backgroundTertiary, in: Capsule())
        .overlay(Capsule().strokeBorder(colors.border, lineWidth: LHMetrics.hairline))
        .frame(minHeight: LHMetrics.minTap)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.95).combined(with: .opacity))
    }

    private func addAlias() {
        guard canAddAlias else { return }
        let cleaned = RentalProperty.cleanedAliases(aliases + [newAlias])
        newAlias = ""
        guard cleaned != aliases else { return }
        if reduceMotion { aliases = cleaned } else { withAnimation(AppAnimation.quick) { aliases = cleaned } }
    }

    // MARK: Save

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let p = editing else { return }
        name = p.name
        address = p.address
        pickedAddress = p.address
        propertyType = p.propertyType
        aliases = p.aliases
        isOwnerOccupied = p.isOwnerOccupied
        if case .edit(_, let confirmDelete) = mode, confirmDelete {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { requestDelete(p) }
        }
    }

    private func requestDelete(_ property: RentalProperty) {
        onDelete(property)
        dismiss()
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func save() {
        guard canSave else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if viewModel.properties.contains(where: { $0.id != editing?.id && normalized($0.name) == normalized(cleanName) }) {
            nameError = RentalsText.duplicateName
            return
        }
        // Other names and "I live here" are always written, so clearing them sticks.
        let cleanedAliases = RentalProperty.cleanedAliases(aliases + [newAlias])
        if let existing = editing {
            var updated = existing
            updated.name = cleanName
            updated.address = cleanAddress
            updated.propertyType = propertyType
            updated.aliases = cleanedAliases
            updated.isOwnerOccupied = isOwnerOccupied
            viewModel.updateProperty(updated)
        } else {
            viewModel.addProperty(name: cleanName, address: cleanAddress, type: propertyType)
            if var added = viewModel.properties.last, added.name == cleanName,
               !cleanedAliases.isEmpty || isOwnerOccupied {
                added.aliases = cleanedAliases
                added.isOwnerOccupied = isOwnerOccupied
                viewModel.updateProperty(added)
            }
        }
        dismiss()
    }

    private func searchAddress(query: String) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        MKLocalSearch(request: request).start { response, _ in
            Task { @MainActor in
                // A pick or a cleared field while the search ran wins.
                guard pickedAddress == nil, address.count > 2 else { return }
                addressResults = response?.mapItems ?? []
            }
        }
    }

    private func selectAddress(_ item: MKMapItem) {
        let placemark = item.placemark
        var parts = ""
        if let n = placemark.subThoroughfare { parts += n + " " }
        if let street = placemark.thoroughfare { parts += street + ", " }
        if let city = placemark.locality { parts += city + ", " }
        if let state = placemark.administrativeArea { parts += state + " " }
        if let zip = placemark.postalCode { parts += zip }
        let picked = parts.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        pickedAddress = picked
        address = picked
        addressResults = []
    }
}

