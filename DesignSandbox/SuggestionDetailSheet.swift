import SwiftUI

/// Suggestion detail / edit sheet (Flighty header + status band, Brick value rows, Skyscanner stepper).
/// With `suggestion == nil` it is the manual "Log time" sheet behind the + button.
struct SuggestionDetailSheet: View {
    let suggestion: Suggestion?
    var onConfirm: (Double) -> Void
    var onDismissItem: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var hours: Double
    @State private var who = 0
    @State private var property = "Pine Cabin"
    @State private var pressTick = 0
    @State private var fitHeight: CGFloat = 640
    @State private var detent: PresentationDetent = .medium
    private var detents: Set<PresentationDetent> { [.medium, .height(fitHeight)] }

    init(suggestion: Suggestion?, onConfirm: @escaping (Double) -> Void, onDismissItem: @escaping () -> Void = {}) {
        self.suggestion = suggestion
        self.onConfirm = onConfirm
        self.onDismissItem = onDismissItem
        _hours = State(initialValue: suggestion?.hours ?? 1)
        _property = State(initialValue: suggestion?.property ?? "Pine Cabin")
    }

    private var kind: SourceKind { suggestion?.kind ?? .manual }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                if let s = suggestion, s.kind == .calendar, let h = s.hours {
                    statusBand(h)
                        .padding(.top, 20)
                }

                hoursHero
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                valueRows
                    .padding(.horizontal, 16)
                    .padding(.top, 24)

                VStack(spacing: 14) {
                    Button {
                        onConfirm(hours)
                        dismiss()
                    } label: {
                        Text("Log \(fmtDur(hours))")
                            .contentTransition(.numericText(value: hours))
                    }
                    .buttonStyle(PrimaryCapsule())
                    .accessibilityIdentifier("confirm-log")

                    if suggestion != nil {
                        Button("Not work") {
                            onDismissItem()
                            dismiss()
                        }
                        .font(.body)
                        .foregroundStyle(LH.destructive)
                        .frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 8)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                fitHeight = h + 8
                detent = .height(fitHeight)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(LH.canvas)
        .presentationDetents(detents, selection: $detent)
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(nil)
        .sensoryFeedback(.selection, trigger: pressTick)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            SourceTile(kind: kind, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrowText).eyebrow()
                Group {
                    if let s = suggestion {
                        Text("\(Text(s.noun).fontWeight(.semibold)) \(s.joiner) \(Text(s.property).fontWeight(.semibold))")
                    } else {
                        Text("Log time").fontWeight(.semibold)
                    }
                }
                .font(.title2)
                .lineLimit(2)
            }
            Spacer(minLength: 8)
            GlassCircleButton { dismiss() }
        }
    }

    private var eyebrowText: String {
        guard let s = suggestion else { return "Added by you · Today" }
        switch s.kind {
        case .calendar: return "Calendar · Tue, Oct 14"
        case .receipt: return "Receipt · Thu, Oct 16"
        case .location: return "Location · Sun, Oct 12"
        default: return s.when
        }
    }

    private func statusBand(_ h: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Scheduled \(Text(fmtDur(h)).foregroundStyle(LH.positive))")
                .font(.title3.weight(.semibold))
            Text("Your calendar had this from 9:00 to 11:00. Change it if the work ran long or short.")
                .font(.subheadline)
                .foregroundStyle(LH.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LH.tertiaryFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var hoursHero: some View {
        let (h, m) = fmtHM(hours)
        return VStack(alignment: .leading, spacing: 12) {
            Text("How long were you working?")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(LH.secondaryText)
            HStack(spacing: 12) {
                StepButton(symbol: "minus", enabled: hours > 0.25) {
                    withAnimation(Motion.snappy(reduce)) { hours = max(0.25, hours - 0.25) }
                    pressTick += 1
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(h)").font(.system(size: 40, weight: .semibold))
                        .contentTransition(.numericText(value: Double(h)))
                    Text("h").font(.title2).foregroundStyle(LH.secondaryText).padding(.leading, -3)
                    Text(String(format: "%02d", m)).font(.system(size: 40, weight: .semibold))
                        .contentTransition(.numericText(value: Double(m)))
                        .padding(.leading, 8)
                    Text("m").font(.title2).foregroundStyle(LH.secondaryText).padding(.leading, -3)
                }
                .monospacedDigit()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("hours-value")
                Spacer()
                StepButton(symbol: "plus", enabled: hours < 12) {
                    withAnimation(Motion.snappy(reduce)) { hours = min(12, hours + 0.25) }
                    pressTick += 1
                }
                .accessibilityIdentifier("hours-plus")
            }
            .padding(16)
            .lhCard(radius: 16)
            if let cap = suggestion?.capMinutes {
                Text("You were there for \(fmtDur(Double(cap) / 60)), so we cap it there.")
                    .font(.footnote)
                    .foregroundStyle(LH.secondaryText)
            }
        }
    }

    private var valueRows: some View {
        VStack(spacing: 0) {
            ValueRow(label: "Property") {
                Menu {
                    Button("Pine Cabin") { property = "Pine Cabin" }
                    Button("Oak Street Duplex") { property = "Oak Street Duplex" }
                } label: {
                    HStack(spacing: 4) {
                        Text(property)
                        Image(systemName: "chevron.up.chevron.down").font(.footnote)
                    }
                    .foregroundStyle(.primary)
                }
            }
            Divider().padding(.leading, 16)
            ValueRow(label: "Who") {
                Picker("Who", selection: $who) {
                    Text("Me").tag(0)
                    Text("Spouse").tag(1)
                    Text("Both").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
            Divider().padding(.leading, 16)
            ValueRow(label: "Category") { chevronValue("Repairs") }
            Divider().padding(.leading, 16)
            ValueRow(label: "Date") { chevronValue(suggestion == nil ? "Today" : "Tue, Oct 14") }
        }
        .background(LH.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func chevronValue(_ v: String) -> some View {
        HStack(spacing: 6) {
            Text(v).foregroundStyle(.primary)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
    }
}

struct ValueRow<Trailing: View>: View {
    var label: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack {
            Text(label).foregroundStyle(LH.secondaryText)
            Spacer()
            trailing
        }
        .font(.body)
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
}

struct StepButton: View {
    var symbol: String
    var enabled: Bool = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(enabled ? Color.primary : LH.secondaryText)
                .background(LH.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(Pressable())
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? "More time" : "Less time")
    }
}
