import SwiftUI

/// Share-sheet receipt capture. Host = a photo of the receipt (as if shared from Photos);
/// our extension renders as a sheet. Store, total and date are read; hours are required and empty.
struct ShareReceiptHost: View {
    @State private var show = false
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ReceiptPaper()
                .frame(width: 260)
                .rotationEffect(.degrees(-2))
                .padding(.bottom, 420)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            show = true
        }
        .sheet(isPresented: $show) {
            ShareReceiptSheet()
                .presentationDetents([.fraction(0.84)])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
        }
    }
}

struct ShareReceiptSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var hours: Double? = nil
    @State private var property = 0
    @State private var saved = false
    @State private var tick = 0

    private let properties = [("Pine Cabin", "Short-term · Big Bear Lake"), ("Oak Street Duplex", "Long-term · Riverside")]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") {}.foregroundStyle(LH.action)
                Spacer()
                Text("LandlordHours").font(.headline)
                Spacer()
                Button("Cancel") {}.hidden()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Receipt row
                    HStack(spacing: 14) {
                        ReceiptPaper(compact: true)
                            .frame(width: 44, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(LH.separator, lineWidth: 0.5))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Home Depot").font(.body.weight(.semibold))
                            Text("$212.40 · Thu, Oct 16").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer()
                    }

                    // Brex-style verification
                    VStack(spacing: 10) {
                        Text("Read from the receipt, on your iPhone")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ReadChip("Store")
                            ReadChip("Total")
                            ReadChip("Date")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(LH.tertiaryFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.top, 20)

                    // Hours: required, empty
                    HStack(alignment: .firstTextBaseline) {
                        Text("How long did this take?").font(.body.weight(.semibold))
                        Spacer()
                        if hours == nil {
                            Text("Required")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(LH.caution)
                                .transition(.opacity)
                        }
                    }
                    .padding(.top, 28)

                    HStack(spacing: 12) {
                        StepButton(symbol: "minus", enabled: (hours ?? 0) > 0.5) {
                            withAnimation(Motion.snappy(reduce)) { hours = max(0.5, (hours ?? 0.5) - 0.5) }
                            tick += 1
                        }
                        Spacer()
                        Group {
                            if let hours {
                                let (h, m) = fmtHM(hours)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("\(h)").font(.system(size: 34, weight: .semibold))
                                        .contentTransition(.numericText(value: Double(h)))
                                    Text("h").font(.title3).foregroundStyle(.secondary)
                                    Text(String(format: "%02d", m)).font(.system(size: 34, weight: .semibold))
                                        .contentTransition(.numericText(value: Double(m)))
                                        .padding(.leading, 4)
                                    Text("m").font(.title3).foregroundStyle(.secondary)
                                }
                                .monospacedDigit()
                            } else {
                                Text("Add hours")
                                    .font(.title3)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(height: 44)
                        Spacer()
                        StepButton(symbol: "plus", enabled: (hours ?? 0) < 12) {
                            withAnimation(Motion.snappy(reduce)) { hours = (hours ?? 0) + 0.5 }
                            tick += 1
                        }
                        .accessibilityIdentifier("receipt-plus")
                    }
                    .padding(12)
                    .background(LH.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(hours == nil ? LH.caution.opacity(0.6) : .clear, lineWidth: 1.5)
                    }
                    .padding(.top, 10)

                    Text("A receipt can't say how long you worked, so we never guess. Count the shopping trip and the time spent using what you bought.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    // Add to
                    Text("Add to").font(.body.weight(.semibold)).padding(.top, 28)
                    VStack(spacing: 0) {
                        ForEach(properties.indices, id: \.self) { i in
                            Button {
                                withAnimation(Motion.snappy(reduce)) { property = i }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: i == 0 ? "house.lodge" : "building.2")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32, height: 32)
                                        .background(LH.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(properties[i].0).foregroundStyle(.primary)
                                        Text(properties[i].1).font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if property == i {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(LH.action)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .frame(minHeight: 56)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 58)
                        }
                        HStack(spacing: 12) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(LH.action)
                                .frame(width: 32, height: 32)
                            Text("Other work").foregroundStyle(LH.action)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                    }
                    .background(LH.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.top, 10)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            ZStack {
                if saved {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(LH.positive)
                            .symbolEffect(.bounce, value: saved)
                        Text("Saved to \(properties[property].0)").font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    Button {
                        withAnimation(Motion.collapse(reduce)) { saved = true }
                    } label: {
                        Text(hours == nil ? "Add hours to save" : "Add \(fmt(hours ?? 0)) h to \(properties[property].0)")
                            .contentTransition(.numericText(value: hours ?? 0))
                    }
                    .buttonStyle(PrimaryCapsule())
                    .disabled(hours == nil)
                    .accessibilityIdentifier("receipt-save")
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(LH.canvas)
        .sensoryFeedback(.selection, trigger: tick)
        .sensoryFeedback(.success, trigger: saved)
    }
}

struct ReadChip: View {
    var text: String
    init(_ t: String) { text = t }
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(LH.positive)
            Text(text).foregroundStyle(.primary)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(LH.positiveWash, in: Capsule())
    }
}

/// A drawn receipt (no stock imagery).
struct ReceiptPaper: View {
    var compact = false
    var body: some View {
        let items: [(String, String)] = [
            ("PVC PIPE 3/4 IN 10FT", "18.94"), ("SHARKBITE COUPLING", "12.48"),
            ("WAX RING W/ FLANGE", "6.97"), ("TOILET FILL VALVE", "14.98"),
            ("PAINT EGGSHELL 1GAL", "42.98"), ("ROLLER KIT 9IN", "16.97"),
            ("DRYWALL PATCH KIT", "9.98"), ("CAULK WHITE 2PK", "11.94"),
            ("SMOKE ALARM 2PK", "59.97"),
        ]
        VStack(alignment: .leading, spacing: compact ? 1 : 5) {
            Text("THE HOME DEPOT").font(.system(size: compact ? 5 : 17, weight: .heavy)).frame(maxWidth: .infinity)
            Text("#6658 BIG BEAR LAKE, CA").font(.system(size: compact ? 3 : 10, design: .monospaced)).frame(maxWidth: .infinity)
            Text("10/16/26  11:42 AM").font(.system(size: compact ? 3 : 10, design: .monospaced)).frame(maxWidth: .infinity)
                .padding(.bottom, compact ? 1 : 6)
            ForEach(items, id: \.0) { item in
                HStack {
                    Text(item.0)
                    Spacer()
                    Text(item.1)
                }
                .font(.system(size: compact ? 3 : 10, design: .monospaced))
            }
            Divider().padding(.vertical, compact ? 1 : 4)
            HStack {
                Text("SUBTOTAL"); Spacer(); Text("196.21")
            }.font(.system(size: compact ? 3 : 10, design: .monospaced))
            HStack {
                Text("SALES TAX"); Spacer(); Text("16.19")
            }.font(.system(size: compact ? 3 : 10, design: .monospaced))
            HStack {
                Text("TOTAL").fontWeight(.bold); Spacer(); Text("$212.40").fontWeight(.bold)
            }.font(.system(size: compact ? 4 : 12, design: .monospaced))
        }
        .foregroundStyle(Color(hex: 0x2A2A2A))
        .padding(compact ? 4 : 18)
        .background(Color(hex: 0xFBFAF6))
        .shadow(color: .black.opacity(compact ? 0 : 0.3), radius: 20, y: 10)
        .environment(\.colorScheme, .light)
    }
}
