import SwiftUI

#if DEBUG
// MARK: - Paywall B and the plan states (2.3 design sandbox)
//
// Model: everyone keeps 1 rental free, for good. Pro (every rental, the PDF and spreadsheet, care
// plans, lessons) starts with Apple's 14-day free trial, then renews at $99.99 a year.
// Paywall B leads with the trial timeline (Today → Day 12 reminder → Day 14 renewal), then the
// price card. Apple 3.1.2: "$99.99" is the largest price text on screen; the renewal and how to
// cancel sit beside the button, and the title never says "free".

// MARK: Timeline

struct D23TimelineStep: Identifiable {
    let id: Int
    let symbol: String
    let title: String
    let text: String
    var reached = false
}

/// A vertical timeline: 32pt nodes joined by a 2pt line. A reached node is `action` with
/// `onAction` ink; later nodes are the `actionSurface` wash with `action` ink.
struct D23Timeline: View {
    let steps: [D23TimelineStep]
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var node: CGFloat = 32

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Image(systemName: step.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(step.reached ? colors.onAction : colors.action)
                            .frame(width: node, height: node)
                            .background(step.reached ? colors.action : colors.actionSurface, in: Circle())
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(step.reached ? colors.action : colors.border)
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                                .padding(.vertical, 4)
                        }
                    }
                    .frame(width: node)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.headline)
                            .foregroundStyle(colors.textPrimary)
                        Text(step.text)
                            .font(.subheadline)
                            .foregroundStyle(colors.textSecondary)
                    }
                    .padding(.top, 5)
                    .padding(.bottom, index < steps.count - 1 ? 18 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: Paywall B

struct D23PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var steps: [D23TimelineStep] {
        [
            D23TimelineStep(id: 0, symbol: "lock.open", title: "Today",
                            text: "Pro is on: every rental, your PDF, care plans and lessons.", reached: true),
            D23TimelineStep(id: 1, symbol: "bell", title: "In 12 days · \(D23.short(D23.reminderDate))",
                            text: "We remind you that the trial ends in 2 days."),
            D23TimelineStep(id: 2, symbol: "calendar", title: "In 14 days · \(D23.short(D23.renewDate))",
                            text: "Pro renews at \(D23.price) a year. Cancel at least a day before and you pay nothing."),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("How your trial works")
                        .font(LHFont.screenTitle(size: 28))
                        .foregroundStyle(colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(LHButton.icon)
                        .accessibilityLabel("Close")
                }
                .padding(.top, 16)

                D23Timeline(steps: steps)
                    .padding(.top, 20)

                priceCard
                    .padding(.top, LHMetrics.sectionGap)

                D23Section(title: "In Pro") {
                    LHRowGroup(onPage: true) {
                        LHRow.Browse(title: "Every rental", meta: "Log at as many as you own", systemImage: "house", showsChevron: false)
                        LHDivider(leadingInset: LHRow.browseDividerInset)
                        LHRow.Browse(title: "The PDF for your CPA", meta: "Plus the spreadsheet", systemImage: "doc.text", showsChevron: false)
                        LHDivider(leadingInset: LHRow.browseDividerInset)
                        LHRow.Browse(title: "Care plans and lessons", meta: "For each rental", systemImage: "checklist", showsChevron: false)
                    }
                }
                .padding(.top, LHMetrics.sectionGap)

                Text("Not now? You keep logging at one rental for free, and every hour stays.")
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 12)
            }
            .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        .background { LHPage() }
        .accessibilityIdentifier("paywall23")
    }

    private var priceCard: some View {
        let shape = RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Dormer Pro")
                    .font(.headline)
                    .foregroundStyle(colors.textPrimary)
                Spacer(minLength: 8)
                LHTag("14 days free", tone: .action)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(D23.price)
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(colors.textPrimary)
                Text("a year")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
            }
            .padding(.top, 6)
            .accessibilityElement(children: .combine)
            Text("Free for 14 days, then \(D23.price) a year. Renews each year until you cancel.")
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LHMetrics.cardPadding)
        .background(colors.backgroundSecondary, in: shape)
        .overlay { shape.strokeBorder(colors.pageCardEdge, lineWidth: 1) }
    }

    private var foot: some View {
        VStack(spacing: 4) {
            Button("Start free trial") { }
                .buttonStyle(LHButton.primary)
            Text("Cancel any time in Settings, at least a day before it renews.")
                .font(.footnote)
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            HStack(spacing: 20) {
                Button("Restore purchase") { }
                Button("Terms") { }
                Button("Privacy") { }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(colors.action)
            .frame(minHeight: LHMetrics.minTap)
        }
        .padding(.horizontal, LHMetrics.gutter)
        .padding(.top, 12)
        .background {
            // Opaque, with a soft 16pt fade above it so rows scroll under it cleanly.
            VStack(spacing: 0) {
                LinearGradient(colors: [colors.pageBottom.opacity(0), colors.pageBottom], startPoint: .top, endPoint: .bottom)
                    .frame(height: 16)
                colors.pageBottom
            }
            .padding(.top, -16)
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

// MARK: Trial start

struct D23TrialStartView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                CraftHouseView(stage: .half, windowsLit: true, side: typeSize.isAccessibilitySize ? 160 : 248, fillsStage: false)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                    .padding(.top, 8)
                Text("Your trial is on.")
                    .font(LHFont.screenTitle(size: 34))
                    .foregroundStyle(colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                Text("Everything in Pro is open until \(D23.short(D23.renewDate)). We’ll remind you on \(D23.short(D23.reminderDate)). Then \(D23.price) a year unless you cancel.")
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
                    Text("Try these first")
                        .font(.headline)
                        .foregroundStyle(colors.textPrimary)
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)
                    LHRowGroup(onPage: true) {
                        LHRow.Browse(title: "Add your other rentals", meta: "Each gets its own care plan",
                                     systemImage: "house", action: {})
                        LHDivider(leadingInset: LHRow.browseDividerInset)
                        LHRow.Browse(title: "Make your first PDF", meta: "The record your CPA gets",
                                     systemImage: "doc.text", action: {})
                    }
                }
                .padding(.top, 28)
            }
            .frame(maxWidth: LHMetrics.readingColumn)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("Done") { dismiss() }
                .buttonStyle(LHButton.primary)
                .padding(.horizontal, LHMetrics.gutter)
                .padding(.vertical, 8)
        }
        .background { LHPage() }
        .sensoryFeedback(.success, trigger: true)
        .accessibilityIdentifier("trial.start")
    }
}

// MARK: Day 12 reminder

struct D23Day12Sheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(D23.price)
                        .font(.largeTitle.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(colors.textPrimary)
                    Text("a year, from \(D23.short(D23.renewDate))")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                }
                .accessibilityElement(children: .combine)
                Text("Pro renews on its own. To stop it, cancel in Settings at least a day before.")
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 10) {
                    Text("If you cancel")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.textPrimary)
                    line("checkmark", "Every hour you logged stays.")
                    line("checkmark", "You keep logging at \(D23.freeRental), free.")
                    line("minus", "Other rentals and the PDF need Pro.")
                }
                .padding(LHMetrics.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: LHMetrics.innerRadius, style: .continuous))
                .padding(.top, 20)
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .lhSheetScreen("Your trial ends in 2 days", onClose: { dismiss() }, background: colors.backgroundSecondary)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                Button("Keep Pro") { dismiss() }
                    .buttonStyle(LHButton.primary)
                Button("Cancel in Settings") { }
                    .buttonStyle(LHButton.tertiary)
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.top, 8)
            .background { D23FootFade(color: colors.backgroundSecondary) }
        }
        .background(colors.backgroundSecondary)
        .presentationBackground(colors.backgroundSecondary)
        .accessibilityIdentifier("trial.day12")
    }

    private func line(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(symbol == "checkmark" ? colors.positive : colors.textSecondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(colors.textPrimary)
        }
    }
}

// MARK: Free rental: pick it (after a trial ends without Pro)

struct D23RentalChoice: Identifiable {
    let name: String
    let hours: Int
    var id: String { name }
}

let d23Rentals = [D23RentalChoice(name: "Pine Cabin", hours: 420), D23RentalChoice(name: "Oak Street Duplex", hours: 46)]

/// One rental row with the Settings-style selection (§1.24): a trailing `checkmark` in `action`.
struct D23RentalPickRow: View {
    let rental: D23RentalChoice
    let selected: Bool
    var enabled = true
    /// Shown on a locked row instead of the hours line ("Switch on Nov 30").
    var lockedNote: String? = nil
    var action: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        if enabled {
            Button(action: action) { face(colors) }
                .buttonStyle(LHButton.press)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            // Locked until the monthly switch: full-contrast ink (no 40% dim), not a button.
            face(colors)
                .accessibilityElement(children: .combine)
                .accessibilityHint("You can switch on \(D23.short(D23.nextSwitchDate))")
        }
    }

    private func face(_ colors: AdaptiveColors) -> some View {
            HStack(spacing: 12) {
                LHRowGlyph(systemImage: "house", tint: selected ? .action : .neutral)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rental.name).font(.body).foregroundStyle(colors.textPrimary)
                    Text(lockedNote ?? "\(rental.hours)h this year · kept in your total")
                        .font(.subheadline).foregroundStyle(colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colors.action)
                        .frame(width: LHMetrics.minTap, height: LHMetrics.minTap)
                        .accessibilityHidden(true)
                }
            }
            .padding(LHRow.insets)
            .frame(minHeight: LHMetrics.rowMinHeight)
            .contentShape(Rectangle())
    }
}

struct D23PickFreeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selected = D23.freeRental
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your trial has ended. You can keep logging at one rental for free. Every rental’s hours stay in your total.")
                    .font(.body)
                    .foregroundStyle(colors.textSecondary)
                LHRowGroup {
                    ForEach(Array(d23Rentals.enumerated()), id: \.element.id) { index, rental in
                        if index > 0 { LHDivider(leadingInset: LHRow.browseDividerInset) }
                        D23RentalPickRow(rental: rental, selected: selected == rental.name) {
                            selected = rental.name
                        }
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
                        .strokeBorder(colors.border, lineWidth: 1)
                }
                .padding(.top, 20)
                LHFootnote("You can switch once a month in Settings.")
                    .padding(.horizontal, 4)
                    .padding(.top, 12)
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .lhSheetScreen("Pick your free rental", background: colors.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                Button("Log at \(selected)") { dismiss() }
                    .buttonStyle(LHButton.primary)
                    .contentTransition(.opacity)
                Button("See Pro · \(D23.price) a year") { }
                    .buttonStyle(LHButton.tertiary)
            }
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.top, 8)
            .background { D23FootFade(color: colors.background) }
        }
        .background(colors.background)
        .presentationBackground(colors.background)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityIdentifier("plan.pickFree")
    }
}

// MARK: Free rental in Settings (switch once a month)

struct D23FreeRentalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                D23Section(title: "You log at") {
                    LHRowGroup {
                        ForEach(Array(d23Rentals.enumerated()), id: \.element.id) { index, rental in
                            if index > 0 { LHDivider(leadingInset: LHRow.browseDividerInset) }
                            D23RentalPickRow(rental: rental, selected: rental.name == D23.freeRental,
                                             enabled: rental.name == D23.freeRental,
                                             lockedNote: rental.name == D23.freeRental ? nil
                                                 : "\(rental.hours)h this year · switch on \(D23.short(D23.nextSwitchDate))")
                        }
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.body)
                        .foregroundStyle(colors.textSecondary)
                        .accessibilityHidden(true)
                    Text("You can switch once a month. Your next switch is on \(D23.short(D23.nextSwitchDate)).")
                        .font(.subheadline)
                        .foregroundStyle(colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 4)
                .padding(.top, -12)

                D23Section(title: "Pro") {
                    LHRowGroup {
                        LHRow.Browse(title: "Log at every rental", meta: "\(D23.price) a year, with the PDF",
                                     systemImage: "star", wrapsMeta: true, action: {})
                    }
                }
            }
            .frame(maxWidth: LHMetrics.readingColumn, alignment: .leading)
            .padding(.horizontal, LHMetrics.gutter)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .background { LHCanvas() }
        .lhDetailScreen("Free rental", subtitle: "The free plan logs at one rental.",
                        back: LHBackAction(label: "Back", identifier: "plan.back") { dismiss() })
        .hidesAppTabBar()
        .accessibilityIdentifier("plan.freeRental")
    }
}

// MARK: View-only rental (on the real rental page)

struct D23ViewOnlyCard: View {
    let rentalName: String
    let hours: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        let shape = RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("View only on the free plan")
                    .font(.headline)
                    .foregroundStyle(colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("You log at \(D23.freeRental) for free. The \(hours) hours here stay in your total.")
                .font(.subheadline)
                .foregroundStyle(colors.textSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { actions }
                VStack(alignment: .leading, spacing: 4) { actions }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LHMetrics.cardPadding)
        .background(colors.backgroundSecondary, in: shape)
        .overlay { shape.strokeBorder(colors.pageCardEdge, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rental.viewOnly")
    }

    @ViewBuilder private var actions: some View {
        Button("See Pro · \(D23.price) a year") { }
            .buttonStyle(LHButton.secondary)
        Button("Switch rental") { }
            .buttonStyle(LHButton.tertiary)
    }
}
#endif
