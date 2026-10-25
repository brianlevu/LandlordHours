import SwiftUI

// MARK: - Log time pickers: "Kind of work" and "Which rental?" (the timer's pick rows open these)
//
// `LHSheet` chrome (title left, one `.icon` close right), grouped rows, the 56pt tool renders in the
// picker grid and 36pt in the list (§1.17). The sheet surface is opaque `backgroundSecondary`.

/// "Kind of work": a grid of the kinds that count, then the investor kinds under "Doesn't count
/// toward your hours" (they can be logged for the record, never counted).
struct LogCategoryPicker: View {
    let selected: ActivityCategory?
    var onPick: (ActivityCategory) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pickTick = 0

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        LHSheet(lt("Kind of work"), onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                    ForEach(LogCategoryGroups.counted, id: \.self) { category in
                        gridCell(category)
                    }
                }
                VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
                    LHSectionHeader(lt("Doesn\u{2019}t count toward your hours"))
                    VStack(spacing: 0) {
                        ForEach(Array(LogCategoryGroups.notCounted.enumerated()), id: \.element) { index, category in
                            notCountedRow(category)
                            if index < LogCategoryGroups.notCounted.count - 1 { LHDivider(leadingInset: 64) }
                        }
                    }
                    .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
                    LHFootnote(lt("Investor work. Log it for your records; it never counts toward your hours."))
                }
            }
            .padding(.top, 8)
        }
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

    private func gridCell(_ category: ActivityCategory) -> some View {
        let on = category == selected
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(HStackLayout(spacing: 14)) : AnyLayout(VStackLayout(spacing: 8))
        let shape = RoundedRectangle(cornerRadius: LHMetrics.tileRadius, style: .continuous)
        return Button { pick(category) } label: {
            layout {
                CategoryToolTile(category: category, size: 56)
                Text(category.inboxLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(stacked ? nil : 1)
                    .minimumScaleFactor(0.85)
                if stacked { Spacer(minLength: 0) }
            }
            .padding(.horizontal, stacked ? 16 : 6)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(colors.backgroundTertiary, in: shape)
            .overlay(shape.strokeBorder(on ? colors.action : colors.border, lineWidth: on ? 1.5 : LHMetrics.hairline))
            .animation(AppAnimation.quick, value: on)
            .contentShape(shape)
        }
        .buttonStyle(LHButton.press)
        .accessibilityLabel(category.inboxLabel)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("picker.category.\(category.blueprintToolName)")
    }

    private func notCountedRow(_ category: ActivityCategory) -> some View {
        let on = category == selected
        return LHRow.Browse(title: category.inboxLabel, meta: lt("Not counted"), showsChevron: false, action: { pick(category) }) {
            CategoryToolTile(category: category, size: 36)
        }
        .overlay(alignment: .trailing) {
            if on {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.action)
                    .padding(.trailing, 16)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(lt("\(category.inboxLabel), not counted toward hours"))
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("picker.category.\(category.blueprintToolName)")
    }
}

/// "Which rental?": rows with the seal, name and short address. The last row adds a rental; at the
/// free limit it is the `.row` lock (what stays active + one Unlock Pro).
struct LogPropertyPicker: View {
    let properties: [RentalProperty]
    let selected: UUID?
    var onPick: (UUID) -> Void
    var onAddProperty: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var paywall: ProPaywallRequest?
    @State private var pickTick = 0

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        LHSheet(lt("Which rental?"), onClose: { dismiss() }) {
            VStack(spacing: 0) {
                ForEach(Array(properties.enumerated()), id: \.element.id) { index, property in
                    row(property, index: index)
                    LHDivider(leadingInset: 60)
                }
                if viewModel.canAddProperty() {
                    LHRow.Browse(title: lt("Add a rental"), showsChevron: false, action: {
                        dismiss()
                        onAddProperty()
                    }) {
                        LHRowGlyph(systemImage: "plus")
                    }
                    .accessibilityIdentifier("picker.addProperty")
                } else {
                    PropertiesAtLimitRow(firstPropertyName: properties.first?.name) { openPaywall() }
                }
            }
            .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous))
            .padding(.top, 8)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: pickTick)
        .proPaywall($paywall)
        .accessibilityIdentifier("picker.property")
    }

    /// ProGate's at-limit paywall (`.secondProperty`); after a purchase, go straight to adding the rental.
    private func openPaywall() {
        paywall = ProPaywallRequest(context: ProGate.context(for: .propertiesLimit), entry: .propertiesLimit, onUnlocked: {
            dismiss()
            onAddProperty()
        })
    }

    private func row(_ property: RentalProperty, index: Int) -> some View {
        let on = property.id == selected
        return LHRow.Browse(title: property.name, meta: property.address.isEmpty ? nil : property.address, showsChevron: false,
                            action: {
                                pickTick += 1
                                onPick(property.id)
                                dismiss()
                            }) {
            PropertySeal(property, in: properties, size: 32)
        }
        .overlay(alignment: .trailing) {
            if on {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(colors.action)
                    .padding(.trailing, 16)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : [.isButton])
        .accessibilityIdentifier("picker.property.\(index)")
    }
}
