import SwiftUI

// MARK: - Report (Flighty Delay Report idiom)

struct ReportView: View {
    @State private var range = 0
    @State private var showExport = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Picker("Range", selection: $range) {
                    Text("2026").tag(0)
                    Text("All time").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Your hours").sectionLabel()
                        Spacer()
                        SharePill()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("212h").font(.system(size: 44, weight: .bold)).monospacedDigit()
                        Text("of 750").font(.title2).foregroundStyle(LH.secondaryText)
                    }
                    .padding(.top, 4)
                    Text("Through Oct 18 · 74 days left in the year")
                        .font(.subheadline).foregroundStyle(LH.secondaryText)
                }

                BreakdownSection(title: "By property", rows: [
                    ("Pine Cabin", 0.60, "128h"), ("Oak Street", 0.40, "84h"),
                ], color: LH.action)

                BreakdownSection(title: "By kind of work", rows: [
                    ("Repairs", 0.38, "81h"), ("Leasing", 0.21, "44h"), ("Cleaning", 0.16, "34h"),
                    ("Admin", 0.14, "30h"), ("Management", 0.11, "23h"),
                ], color: LH.action.opacity(0.75))

                BreakdownSection(title: "Who did it", rows: [
                    ("Me", 0.82, "173h 30m"), ("Spouse", 0.18, "38h 30m"),
                ], color: LH.action.opacity(0.75))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Where the hours came from").sectionLabel()
                    HStack(spacing: 0) {
                        SourceStat(kind: .calendar, value: "61%")
                        SourceStat(kind: .manual, value: "22%")
                        SourceStat(kind: .timer, value: "11%")
                        SourceStat(kind: .receipt, value: "6%")
                    }
                    .padding(.vertical, 14)
                    .lhCard(radius: 16)
                    Text("Every entry was confirmed by you. The PDF shows when each was detected and confirmed.")
                        .font(.footnote).foregroundStyle(LH.secondaryText)
                }

                Button("Export PDF") { showExport = true }
                    .buttonStyle(PrimaryCapsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(LH.canvas)
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: $showExport) { ExportView(locked: true) }
    }
}

struct SharePill: View {
    var body: some View {
        Label("Share", systemImage: "square.and.arrow.up")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(LH.card, in: Capsule())
    }
}

struct SourceStat: View {
    var kind: SourceKind
    var value: String
    var body: some View {
        VStack(spacing: 6) {
            SourceTile(kind: kind, size: 32)
            Text(value).font(.body.weight(.semibold)).monospacedDigit()
            Text(kind == .manual ? "By hand" : kind.label).font(.caption).foregroundStyle(LH.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

struct BreakdownSection: View {
    var title: String
    var rows: [(String, Double, String)]
    var color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).sectionLabel()
            VStack(spacing: 12) {
                ForEach(rows, id: \.0) { r in
                    HStack(spacing: 12) {
                        Text(r.0).font(.subheadline.weight(.semibold)).lineLimit(1).fixedSize().frame(width: 100, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(LH.fill)
                                Capsule().fill(color).frame(width: max(10, g.size.width * r.1))
                            }
                        }
                        .frame(height: 10)
                        Text(r.2).font(.subheadline).foregroundStyle(LH.secondaryText).monospacedDigit()
                            .frame(width: 76, alignment: .trailing).lineLimit(1).fixedSize()
                    }
                }
            }
        }
    }
}

// MARK: - Export (Crouton PDF preview + toggles)

struct ExportView: View {
    var locked: Bool
    @State private var receipts = true
    @State private var spouse = true
    @State private var sources = true
    @State private var range = 0
    @State private var paywall = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack(spacing: 8) {
                    RangeChip(title: "This year", on: range == 0)
                    RangeChip(title: "Last year", on: range == 1)
                    RangeChip(title: "Custom", on: range == 2)
                    Spacer()
                }

                ZStack {
                    PDFThumb(width: 236, locked: locked)
                    if locked {
                        VStack(spacing: 10) {
                            Spacer()
                            Text("This is the record your accountant gets.")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color(hex: 0x1A1A1A))
                                .frame(width: 200)
                                .multilineTextAlignment(.center)
                            Button {
                                paywall = true
                            } label: {
                                Label("Unlock Pro", systemImage: "lock.open.fill")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(LH.onAction)
                                    .padding(.horizontal, 22)
                                    .frame(height: 44)
                                    .background(LH.action, in: Capsule())
                                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                            }
                            .buttonStyle(Pressable())
                            Spacer().frame(height: 70)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 0) {
                    ToggleRow(title: "Include receipts", isOn: $receipts)
                    Divider().padding(.leading, 16)
                    ToggleRow(title: "Include spouse hours", isOn: $spouse)
                    Divider().padding(.leading, 16)
                    ToggleRow(title: "Show where each entry came from", isOn: $sources)
                }
                .background(LH.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .allowsHitTesting(!locked)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .background(LH.canvas)
        .navigationTitle("PDF")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !locked {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Export") {}
                        .buttonStyle(.glassProminent)
                        .tint(LH.action)
                        .fontWeight(.semibold)
                }
            }
        }
        .fullScreenCover(isPresented: $paywall) { PaywallView() }
    }
}

struct RangeChip: View {
    var title: String
    var on: Bool
    var body: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(on ? LH.action : .primary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(on ? LH.actionWash : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? LH.action : LH.separator, lineWidth: on ? 1.5 : 1))
    }
}

struct ToggleRow: View {
    var title: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(title, isOn: $isOn)
            .tint(LH.action)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
    }
}

struct PDFThumb: View {
    var width: CGFloat
    var locked = false
    var body: some View {
        let s = width / 612
        ZStack(alignment: .top) {
            ReportPage()
            if locked {
                ReportPage()
                    .blur(radius: 9)
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0.0),
                                               .init(color: .clear, location: 0.30),
                                               .init(color: .black, location: 0.40),
                                               .init(color: .black, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                LinearGradient(stops: [.init(color: .clear, location: 0.3),
                                       .init(color: .white.opacity(0.55), location: 0.55),
                                       .init(color: .white.opacity(0.8), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .frame(width: 612, height: 792)
        .scaleEffect(s, anchor: .topLeading)
        .frame(width: width, height: 792 * s, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
        .accessibilityLabel("Preview of the PDF report")
    }
}

/// The real report page, drawn at US Letter points (612×792). Used by Export, Locked and the Paywall hero.
struct ReportPage: View {
    private let rows: [(String, String, String, String, String, String)] = [
        ("Oct 16", "Home Depot run (repairs)", "Pine Cabin", "1h 30m", "Receipt", "Oct 16"),
        ("Oct 14", "Plumber visit", "Pine Cabin", "2h", "Calendar", "Oct 15"),
        ("Oct 12", "Site visit", "Oak Street", "1h 15m", "Location", "Oct 12"),
        ("Oct 11", "Unit 2 repairs", "Oak Street", "3h 30m", "Timer", "Oct 11"),
        ("Oct 10", "Tenant calls", "Oak Street", "45m", "Manual", "Oct 10"),
        ("Oct 9", "Turnover clean (spouse)", "Pine Cabin", "3h", "Calendar", "Oct 9"),
        ("Oct 6", "Bookkeeping", "Both", "1h 30m", "Calendar", "Oct 7"),
        ("Oct 2", "Insurance review", "Oak Street", "1h", "Calendar", "Oct 2"),
        ("Sep 23", "HOA meeting", "Oak Street", "2h", "Calendar", "Sep 24"),
        ("Sep 21", "Bookkeeping", "Both", "2h 30m", "Manual", "Sep 21"),
        ("Sep 12", "Roof inspection", "Pine Cabin", "1h 30m", "Calendar", "Sep 21"),
        ("Sep 8", "Lease signing (spouse)", "Oak Street", "1h", "Calendar", "Sep 8"),
        ("Sep 3", "Fridge delivery", "Pine Cabin", "2h", "Calendar", "Sep 3"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Real Estate Activity Record").font(.system(size: 22, weight: .bold))
                    Text("Tax year 2026 · Maria Alvarez and Daniel Alvarez (joint)")
                        .font(.system(size: 10.5)).foregroundStyle(Color(hex: 0x555555))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("LandlordHours").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: 0x5B4CDB))
                    Text("Generated Oct 18, 2026").font(.system(size: 9)).foregroundStyle(Color(hex: 0x777777))
                }
            }

            HStack(spacing: 0) {
                pageStat("212h", "Hours logged")
                pageStat("750h", "REPS goal")
                pageStat("64%", "Share of work time")
                pageStat("38h 30m", "Spouse hours")
            }
            .padding(.vertical, 12)
            .background(Color(hex: 0xF4F3FA))
            .padding(.top, 18)

            Text("By property").font(.system(size: 11, weight: .semibold)).padding(.top, 18)
            pageBar("Pine Cabin · short-term", 0.6, "128h")
            pageBar("Oak Street Duplex · long-term", 0.4, "84h")

            Text("Entries").font(.system(size: 11, weight: .semibold)).padding(.top, 18).padding(.bottom, 6)
            tableRow(("Date", "Activity", "Property", "Hours", "Source", "Confirmed"), header: true)
            ForEach(rows.indices, id: \.self) { i in
                tableRow(rows[i], header: false)
                    .background(i % 2 == 0 ? Color(hex: 0xFAFAFC) : .white)
            }
            Spacer(minLength: 0)
            Text("Every entry was reviewed and confirmed by the taxpayer. Detected and confirmed dates are shown for entries suggested by the app. Page 1 of 6")
                .font(.system(size: 8)).foregroundStyle(Color(hex: 0x777777))
        }
        .padding(40)
        .frame(width: 612, height: 792, alignment: .topLeading)
        .background(.white)
        .foregroundStyle(Color(hex: 0x1A1A1A))
        .environment(\.colorScheme, .light)
    }

    private func pageStat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 18, weight: .semibold)).monospacedDigit()
            Text(l).font(.system(size: 8.5)).foregroundStyle(Color(hex: 0x666666))
        }
        .frame(maxWidth: .infinity)
    }

    private func pageBar(_ l: String, _ f: Double, _ v: String) -> some View {
        HStack(spacing: 10) {
            Text(l).font(.system(size: 9.5)).frame(width: 170, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0xECEBF5))
                    Capsule().fill(Color(hex: 0x5B4CDB)).frame(width: g.size.width * f)
                }
            }
            .frame(height: 7)
            Text(v).font(.system(size: 9.5)).monospacedDigit().frame(width: 50, alignment: .trailing)
        }
        .padding(.top, 7)
    }

    private func tableRow(_ r: (String, String, String, String, String, String), header: Bool) -> some View {
        HStack(spacing: 6) {
            Text(r.0).frame(width: 44, alignment: .leading)
            Text(r.1).frame(maxWidth: .infinity, alignment: .leading)
            Text(r.2).frame(width: 74, alignment: .leading)
            Text(r.3).frame(width: 46, alignment: .trailing)
            Text(r.4).frame(width: 56, alignment: .leading).padding(.leading, 8)
            Text(r.5).frame(width: 54, alignment: .leading)
        }
        .font(.system(size: 9, weight: header ? .semibold : .regular))
        .foregroundStyle(header ? Color(hex: 0x666666) : Color(hex: 0x1A1A1A))
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xE6E6EC)).frame(height: 0.5) }
    }
}
