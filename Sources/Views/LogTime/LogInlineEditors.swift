import SwiftUI

// MARK: - Inline editors: a tapped row opens in place, one at a time (replaces the pushed pickers)
//
// Chips are `LHChip` (a pick is a chip, §1.16), the hours editor is `LHStepper` (§1.9) with the five
// usual lengths as quick picks above it, the day editor is Today / Yesterday and the system's compact
// date picker. `sheetUnfold` carries the open (the row's transition).

extension LogTimeSheet {
    /// Rentals the user logged against most recently first; the rest in their own order.
    var propertiesByRecency: [RentalProperty] {
        let lastUsed = Dictionary(grouping: viewModel.timeEntries, by: \.propertyId).mapValues { $0.map(\.date).max() ?? .distantPast }
        return properties.enumerated().sorted { a, b in
            let l = lastUsed[a.element.id] ?? .distantPast, r = lastUsed[b.element.id] ?? .distantPast
            return l != r ? l > r : a.offset < b.offset
        }.map(\.element)
    }

    @ViewBuilder func editor(_ field: LogField) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch field {
            case .property: propertyEditor
            case .category: categoryEditor
            case .hours: hoursEditor
            case .date: dateEditor
            case .participant, .description: EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.editor.\(field)")
    }

    // MARK: Rental: chips for up to six, a search for more, "Add a rental" last

    @ViewBuilder var propertyEditor: some View {
        let ordered = propertiesByRecency
        if ordered.count > 6 {
            LHField(lt("Search your rentals"), text: $propertySearch, identifier: "log.property.search")
        }
        let needle = propertySearch.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = ordered.count > 6 && !needle.isEmpty
            ? ordered.filter { ($0.name + " " + $0.address + " " + $0.aliases.joined(separator: " ")).lowercased().contains(needle) }
            : ordered
        LogChipFlow(spacing: 8) {
            ForEach(Array(shown.prefix(ordered.count > 6 ? 12 : 6).enumerated()), id: \.element.id) { index, property in
                LHChip(property.name, isSelected: form.propertyId == property.id) { pick(property: property.id) }
                    .accessibilityIdentifier("log.pick.property.\(index)")
            }
        }
        if viewModel.canAddProperty() {
            Button {
                onClose()
                NotificationCenter.default.post(name: .switchToPropertiesAndOpenAddProperty, object: nil)
            } label: {
                Label(lt("Add a rental"), systemImage: "plus")
            }
            .buttonStyle(LHButton.tertiary)
            .accessibilityIdentifier("log.pick.addProperty")
        } else {
            PropertiesAtLimitRow(firstPropertyName: properties.first?.name) { openPaywall() }
        }
    }

    /// ProGate's at-limit paywall (`.secondProperty`); after a purchase, go straight to adding the rental.
    func openPaywall() {
        paywall = ProPaywallRequest(context: ProGate.context(for: .propertiesLimit), entry: .propertiesLimit, onUnlocked: {
            onClose()
            NotificationCenter.default.post(name: .switchToPropertiesAndOpenAddProperty, object: nil)
        })
    }

    // MARK: Kind of work: the kinds that count, then the ones that never do

    @ViewBuilder var categoryEditor: some View {
        LogChipFlow(spacing: 8) {
            ForEach(LogCategoryGroups.counted, id: \.self) { category in
                LHChip(category.inboxLabel, isSelected: form.category == category) { pick(category: category) }
                    .accessibilityIdentifier("log.pick.category.\(category.blueprintToolName)")
            }
        }
        VStack(alignment: .leading, spacing: 4) {
            LHSectionHeader(lt("Doesn\u{2019}t count toward your hours"), style: .day)
            LogChipFlow(spacing: 8) {
                ForEach(LogCategoryGroups.notCounted, id: \.self) { category in
                    LHChip(category.inboxLabel, isSelected: form.category == category) { pick(category: category) }
                        .accessibilityIdentifier("log.pick.category.\(category.blueprintToolName)")
                }
            }
        }
    }

    // MARK: How long: quick picks and a 15-minute stepper

    @ViewBuilder var hoursEditor: some View {
        LogChipFlow(spacing: 8) {
            ForEach([0.5, 1, 1.5, 2, 4], id: \.self) { value in
                let title = LogTimeFormat.hours(value)
                LHChip(title, isSelected: !form.hoursIsDefault && abs(form.hours - value) < 0.01) { set(hours: value, collapse: true) }
                    .accessibilityLabel(LHFormat.spokenHours(value))
                    .accessibilityIdentifier("log.chip.\(title.replacingOccurrences(of: " ", with: ""))")
            }
        }
        LHStepper(hours: Binding(get: { form.hours }, set: { set(hours: $0, collapse: false) }),
                  step: LogForm.step, range: 0...LogForm.maxHours, label: lt("How long"))
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("log.hours.value")
    }

    // MARK: Date: Today and Yesterday, then a calendar

    @ViewBuilder var dateEditor: some View {
        let calendar = Calendar.current
        LogChipFlow(spacing: 8) {
            LHChip(lt("Today"), isSelected: calendar.isDateInToday(form.date)) {
                set(date: LogForm.merge(day: Date(), timeOf: form.date))
            }
            .accessibilityIdentifier("log.pick.today")
            LHChip(lt("Yesterday"), isSelected: calendar.isDateInYesterday(form.date)) {
                set(date: LogForm.merge(day: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date(), timeOf: form.date))
            }
            .accessibilityIdentifier("log.pick.yesterday")
        }
        DatePicker(lt("Date"), selection: Binding(get: { form.date }, set: { set(date: LogForm.merge(day: $0, timeOf: form.date)) }),
                   in: ...Date(), displayedComponents: .date)
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(colors.action)
            .accessibilityIdentifier("log.datePicker")
    }
}

extension LogForm {
    /// The day of `day` with the time of day of `timeOf` (the note picks the day; the time stays).
    static func merge(day: Date, timeOf: Date, calendar: Calendar = .current) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: timeOf)
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0,
                             of: calendar.startOfDay(for: day)) ?? day
    }

    func isUserSet(_ field: LogField) -> Bool { userSet.contains(field) }
}
