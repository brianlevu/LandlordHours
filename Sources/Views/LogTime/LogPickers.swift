import SwiftUI

// MARK: - Log time pickers (spec §3c): "Kind of work" and "Which rental?"

/// The 44pt close button the confirm sheet uses (Cancel/Close pills are retired).
struct LogSheetCloseButton: View {
    var identifier = "log.close"
    var action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(colors.textPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(colors.backgroundSecondary))
                .overlay(Circle().strokeBorder(colors.border, lineWidth: 0.5))
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel("Close")
        .accessibilityIdentifier(identifier)
    }
}

/// "Kind of work": a 3-column grid of the kinds that count, then the investor kinds under
/// "Doesn't count toward hours" (they can be logged for the record, never counted).
struct LogCategoryPicker: View {
    let selected: ActivityCategory?
    var onPick: (ActivityCategory) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pickTick = 0

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center) {
                    Text("Kind of work")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    LogSheetCloseButton(identifier: "picker.close") { dismiss() }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                    ForEach(LogCategoryGroups.counted, id: \.self) { category in
                        gridCell(category, colors: colors)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    PropertySectionHeader("Doesn\u{2019}t count toward hours")
                    VStack(spacing: 0) {
                        ForEach(Array(LogCategoryGroups.notCounted.enumerated()), id: \.element) { index, category in
                            notCountedRow(category, colors: colors)
                            if index < LogCategoryGroups.notCounted.count - 1 {
                                Rectangle().fill(colors.border.opacity(0.7)).frame(height: 0.5).padding(.leading, 64)
                            }
                        }
                    }
                    .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text("Investor work. Log it for your records; it never counts toward the 750 or 500-hour tests or the house.")
                        .font(.footnote)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }
            .padding(20)
        }
        .background(colors.background.ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .light), trigger: pickTick)
        .accessibilityIdentifier("picker.category")
    }

    private var columns: Int {
        if dynamicTypeSize.isAccessibilitySize { return 1 }
        return dynamicTypeSize >= .xxLarge ? 2 : 3
    }

    private func pick(_ category: ActivityCategory) {
        pickTick += 1
        onPick(category)
        dismiss()
    }

    private func gridCell(_ category: ActivityCategory, colors: AdaptiveColors) -> some View {
        let on = category == selected
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(HStackLayout(spacing: 14)) : AnyLayout(VStackLayout(spacing: 8))
        return Button { pick(category) } label: {
            layout {
                CategoryToolTile(category: category, size: 56)
                Text(category.inboxLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if stacked { Spacer(minLength: 0) }
            }
            .padding(.horizontal, stacked ? 16 : 6)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(on ? colors.action : .clear, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(colors.onAction, colors.action)
                        .padding(8)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel(category.inboxLabel)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("picker.category.\(category.blueprintToolName)")
    }

    private func notCountedRow(_ category: ActivityCategory, colors: AdaptiveColors) -> some View {
        let on = category == selected
        let stacked = dynamicTypeSize.isAccessibilitySize
        return Button { pick(category) } label: {
            HStack(spacing: 12) {
                CategoryToolTile(category: category, size: 36)
                let labels = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
                labels {
                    Text(category.inboxLabel)
                        .font(.body)
                        .foregroundStyle(colors.textPrimary)
                    if !stacked { Spacer(minLength: 8) }
                    Text("Not counted")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(colors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(colors.backgroundTertiary))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if on {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colors.action)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.lhPressable)
        .accessibilityLabel("\(category.inboxLabel), not counted toward hours")
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("picker.category.\(category.blueprintToolName)")
    }
}

/// "Which rental?": 60pt rows with the seal, name and short address. The last row adds a
/// property; at the free limit it is the `.row` lock (what stays active + one Unlock Pro).
struct LogPropertyPicker: View {
    let properties: [RentalProperty]
    let selected: UUID?
    var onPick: (UUID) -> Void
    var onAddProperty: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showPaywall = false
    @State private var pickTick = 0

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center) {
                    Text("Which rental?")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    LogSheetCloseButton(identifier: "picker.close") { dismiss() }
                }
                VStack(spacing: 0) {
                    ForEach(Array(properties.enumerated()), id: \.element.id) { index, property in
                        row(property, index: index, colors: colors)
                        Rectangle().fill(colors.border.opacity(0.7)).frame(height: 0.5).padding(.leading, 60)
                    }
                    if LogProGate.canAddProperty(viewModel) {
                        Button {
                            dismiss()
                            onAddProperty()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(colors.action)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(colors.actionSurface))
                                Text("Add a property")
                                    .font(.body)
                                    .foregroundStyle(colors.action)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.lhPressable)
                        .accessibilityIdentifier("picker.addProperty")
                    } else {
                        PropertiesAtLimitRow(firstPropertyName: properties.first?.name) { showPaywall = true }
                    }
                }
                .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(20)
        }
        .background(colors.background.ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .light), trigger: pickTick)
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: LogProGate.paywallContext, onClose: { showPaywall = false })
        }
        .accessibilityIdentifier("picker.property")
    }

    private func row(_ property: RentalProperty, index: Int, colors: AdaptiveColors) -> some View {
        let on = property.id == selected
        return Button {
            pickTick += 1
            onPick(property.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                PropertySeal(property, in: properties, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(property.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !property.address.isEmpty {
                        Text(property.address)
                            .font(.subheadline)
                            .foregroundStyle(colors.textSecondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    }
                }
                Spacer(minLength: 8)
                if on {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colors.action)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.lhPressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : [.isButton])
        .accessibilityIdentifier("picker.property.\(index)")
    }
}

/// The one seam to the Pro gate for Log time.
/// INTEGRATION (wp-paywall): when `ProGate` lands on release/2.0, swap these two lines for it;
/// callers keep asking `canAddProperty` and opening `paywallContext`.
enum LogProGate {
    @MainActor static func canAddProperty(_ viewModel: AppViewModel) -> Bool { viewModel.canAddProperty() }
    static let paywallContext: PaywallContext = PropertyLimit.paywallContext
}
