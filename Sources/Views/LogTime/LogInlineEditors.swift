import SwiftUI
import LucideIcons

// MARK: - Inline editors: a tapped row opens in place, one at a time (replaces the pushed pickers)

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
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.editor.\(field)")
    }

    // MARK: Rental: chips for up to six, a search for more, "Add a rental" last

    @ViewBuilder var propertyEditor: some View {
        let ordered = propertiesByRecency
        if ordered.count > 6 {
            TextField("Search your rentals", text: $propertySearch)
                .font(.body)
                .foregroundStyle(colors.textPrimary)
                .tint(colors.action)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Capsule().fill(colors.background))
                .overlay(Capsule().strokeBorder(colors.sheetStroke, lineWidth: 1))
                .accessibilityIdentifier("log.property.search")
        }
        let needle = propertySearch.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = ordered.count > 6 && !needle.isEmpty
            ? ordered.filter { ($0.name + " " + $0.address + " " + $0.aliases.joined(separator: " ")).lowercased().contains(needle) }
            : ordered
        LogChipFlow(spacing: 8) {
            ForEach(Array(shown.prefix(ordered.count > 6 ? 12 : 6).enumerated()), id: \.element.id) { index, property in
                LogChip(title: property.name, selected: form.propertyId == property.id, identifier: "log.pick.property.\(index)") {
                    pick(property: property.id)
                }
            }
        }
        if viewModel.canAddProperty() {
            Button {
                onClose()
                NotificationCenter.default.post(name: .switchToPropertiesAndOpenAddProperty, object: nil)
            } label: {
                HStack(spacing: 8) {
                    LucideIcon(image: Lucide.plus, size: 16)
                    Text("Add a rental").font(.subheadline.weight(.medium))
                }
                .foregroundStyle(colors.actionText)
                .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.lhPressable)
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
                LogChip(title: category.inboxLabel, selected: form.category == category,
                        identifier: "log.pick.category.\(category.blueprintToolName)") { pick(category: category) }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Doesn\u{2019}t count toward your hours")
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .textCase(.uppercase)
                .tracking(1.3)
                .foregroundStyle(colors.draftingInk)
                .fixedSize(horizontal: false, vertical: true)
            LogChipFlow(spacing: 8) {
                ForEach(LogCategoryGroups.notCounted, id: \.self) { category in
                    LogChip(title: category.inboxLabel, selected: form.category == category,
                            identifier: "log.pick.category.\(category.blueprintToolName)") { pick(category: category) }
                }
            }
        }
    }

    // MARK: How long: presets and a 15-minute stepper

    @ViewBuilder var hoursEditor: some View {
        LogChipFlow(spacing: 8) {
            ForEach([0.5, 1, 1.5, 2, 4], id: \.self) { value in
                let title = LogTimeFormat.hours(value)
                LogChip(title: title, selected: !form.hoursIsDefault && abs(form.hours - value) < 0.01,
                        identifier: "log.chip.\(title.replacingOccurrences(of: " ", with: ""))") { set(hours: value, collapse: true) }
                    .accessibilityLabel(InboxFormat.spokenHours(value))
            }
        }
        hoursStepper
    }

    var hoursStepper: some View {
        let layout = isAX ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            stepButton(Lucide.minus, label: String(localized: "Less time"), identifier: "log.hours.minus", enabled: form.hours > 0) {
                set(hours: form.hours - LogForm.step, collapse: false)
            }
            Text(verbatim: LogTimeFormat.hours(form.hours))
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(form.hours > 0 ? colors.textPrimary : colors.textTertiary)
                .contentTransition(.numericText(value: form.hours))
                .frame(minWidth: 110)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("How long")
                .accessibilityValue(InboxFormat.spokenHours(form.hours))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: set(hours: min(LogForm.maxHours, form.hours + LogForm.step), collapse: false)
                    case .decrement: set(hours: max(0, form.hours - LogForm.step), collapse: false)
                    @unknown default: break
                    }
                }
                .accessibilityIdentifier("log.hours.value")
            stepButton(Lucide.plus, label: String(localized: "More time"), identifier: "log.hours.plus", enabled: form.hours < LogForm.maxHours) {
                set(hours: form.hours + LogForm.step, collapse: false)
            }
        }
        .frame(maxWidth: .infinity)
    }

    func stepButton(_ image: UIImage, label: String, identifier: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(image: image, size: 20)
                .foregroundStyle(enabled ? colors.textPrimary : colors.textTertiary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(colors.sheetCard))
                .overlay(Circle().strokeBorder(colors.sheetStroke, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.lhPressable)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    // MARK: Date: Today and Yesterday, then a calendar

    @ViewBuilder var dateEditor: some View {
        let calendar = Calendar.current
        LogChipFlow(spacing: 8) {
            LogChip(title: String(localized: "Today"), selected: calendar.isDateInToday(form.date), identifier: "log.pick.today") {
                set(date: LogForm.merge(day: Date(), timeOf: form.date))
            }
            LogChip(title: String(localized: "Yesterday"), selected: calendar.isDateInYesterday(form.date), identifier: "log.pick.yesterday") {
                set(date: LogForm.merge(day: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date(), timeOf: form.date))
            }
        }
        DatePicker("Date", selection: Binding(get: { form.date }, set: { set(date: LogForm.merge(day: $0, timeOf: form.date)) }),
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
