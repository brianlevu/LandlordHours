import SwiftUI
import UIKit

// §1a PaywallView(context:) — sell Pro by showing the record itself.

enum PaywallState: String {
    case ready, priceLoading, priceFailed, buying, askToBuy, failed, success, restoring, restoreNone
}

struct S2Paywall: View {
    var context: PaywallContext = .export
    var state: PaywallState = .ready
    /// No confirmed entries yet → sample page with a SAMPLE stamp.
    var sample = false
    /// The page is still rendering → DraftingLoader stands in.
    var pageLoading = false
    var scrolledToBenefits = false
    var familySharing = true

    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    @State private var successTick = 0

    private var big: Bool { dts >= .xxLarge }

    private var headline: String {
        switch context {
        case .export: "The record your accountant gets"
        case .secondProperty: "Track every rental"
        case .todayUnlock: "Your hours, on paper"
        case .settings: "LandlordHours Pro"
        }
    }

    private var planLine: String {
        switch context {
        case .export: "Export 2026 as a PDF or spreadsheet, any time."
        case .secondProperty(let n): "Add \(n ?? "your next rental") and every place after it. Your hours stay put."
        case .todayUnlock: "Turn \(sample ? "your" : "212") confirmed hours into a clean record."
        case .settings: "Every rental, the PDF and spreadsheet, and location for all of them."
        }
    }

    private var nextStep: String {
        switch context {
        case .export: "Export 2026"
        case .secondProperty(let n): "Add \(n ?? "a property")"
        case .todayUnlock: "See your record"
        case .settings: "Done"
        }
    }

    @Environment(\.colorScheme) private var windowScheme
    @Environment(\.requestedScheme) private var requested

    /// The window runs dark while the paywall is up (light status-bar text over the blue hero, in
    /// both themes); the page itself keeps the user's scheme through its environment.
    var body: some View {
        page.environment(\.colorScheme, requested ?? windowScheme)
            .onAppear { S2StatusBar.shared.overHero = true }
            .onDisappear { S2StatusBar.shared.overHero = false }
    }

    private var page: some View {
        GeometryReader { g in
            let heroH = g.size.height * (big ? 0.30 : 0.46) + g.safeAreaInsets.top
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        hero(width: g.size.width, height: heroH, top: g.safeAreaInsets.top)
                        planCard
                            .padding(.horizontal, 16)
                            .padding(.top, -40)
                        benefits
                            .id("benefits")
                            .padding(.horizontal, 20)
                            .padding(.top, 32)
                        footer.padding(.top, 28).padding(.bottom, 40)
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
                    let over = y < heroH - g.safeAreaInsets.top - 8
                    if S2StatusBar.shared.overHero != over { S2StatusBar.shared.overHero = over }
                }
                .onAppear {
                    if scrolledToBenefits { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo("benefits", anchor: .top) } }
                }
            }
            .overlay(alignment: .top) {
                // A solid band behind the status bar: blueprint while the hero is under it,
                // canvas once scrolled past. iOS picks the status-bar ink from what is behind it,
                // so a uniform band keeps the clock legible (white on blue, dark on canvas).
                (S2StatusBar.shared.overHero ? LHB.brand : LHB.canvas)
                    .frame(height: g.safeAreaInsets.top)
                    .frame(maxWidth: .infinity)
                    .offset(y: -g.safeAreaInsets.top)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.2), value: S2StatusBar.shared.overHero)
            }
            .overlay(alignment: .topTrailing) {
                GlassClose().environment(\.colorScheme, .dark).padding(.trailing, 16).padding(.top, 4)
            }
        }
        .background(LHB.canvas.ignoresSafeArea())
        .onAppear {
            withAnimation(reduce ? .easeOut(duration: 0.2) : .easeOut(duration: 0.28).delay(0.06)) { shown = true }
            if state == .success { successTick += 1 }
        }
        .sensoryFeedback(.success, trigger: successTick)
    }

    // MARK: Hero

    private func hero(width: CGFloat, height: CGFloat, top: CGFloat) -> some View {
        ZStack(alignment: .top) {
            S2Paper(radius: 0)
            VStack(spacing: big ? 14 : 22) {
                Text(headline)
                    .font(S2Font.display(28, opsz: 72, dts: dts))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(dts.isAccessibilitySize ? 4 : 2)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, dts.isAccessibilitySize ? 24 : 60)
                    .padding(.trailing, dts.isAccessibilitySize ? 36 : 0)
                    .accessibilityAddTraits(.isHeader)
                if !dts.isAccessibilitySize {
                    phone(width: width * 0.62)
                        .opacity(shown ? 1 : 0)
                        .offset(y: shown || reduce ? 0 : 12)
                }
            }
            .padding(.top, top + 20)
            .padding(.bottom, dts.isAccessibilitySize ? 64 : 0)
        }
        .frame(height: dts.isAccessibilitySize ? nil : height, alignment: .top)
        .clipped()
    }

    private func phone(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 44, style: .continuous)
            .strokeBorder(LHB.draftingHero, lineWidth: 2)
            .frame(width: width, height: width * 2.05)
            .overlay(alignment: .top) {
                Group {
                    if pageLoading {
                        DraftingLoader(kind: .document).frame(width: width * 0.6).padding(.top, 40)
                    } else {
                        RecordPage(highlight: highlight, sample: sample)
                            .frame(width: width - 24)
                            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                            .padding(.top, 12)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sample ? "A sample page of the PDF record" : "Page 1 of your PDF record")
    }

    private var highlight: RecordPage.Highlight {
        switch context {
        case .secondProperty: .newRow
        case .todayUnlock: .total
        default: .none
        }
    }

    // MARK: Plan card

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            (dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))) {
                Text("LandlordHours Pro").font(.headline).foregroundStyle(LHB.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6).allowsTightening(true)
                Text("PAY ONCE")
                    .font(.system(size: 11, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(LHB.action)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(LHB.actionSurface))
                Spacer(minLength: 0)
            }
            priceRow
            Text(planLine)
                .font(.subheadline).foregroundStyle(LHB.textSecondary)
                .lineLimit(big ? 4 : 2)
                .fixedSize(horizontal: false, vertical: true)
            statusLine
            buyButton
            if state != .success {
                Button(state == .restoring ? "Checking…" : "Restore purchase") {}
                    .font(.subheadline).foregroundStyle(LHB.action)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .overlay(alignment: .bottom) {
                        if state == .restoring { DraftingLine(color: LHB.draftingInk).frame(width: 90).offset(y: -2) }
                    }
            }
            if state == .restoreNone {
                Text("No purchase found on this Apple Account.")
                    .font(.footnote).foregroundStyle(LHB.textSecondary).frame(maxWidth: .infinity)
            }
            Rectangle().fill(LHB.border).frame(height: 0.5)
            VStack(alignment: .leading, spacing: 8) {
                Label("No subscription", systemImage: "infinity")
                if familySharing { Label("Family Sharing", systemImage: "person.2") }
            }
            .font(.subheadline).foregroundStyle(LHB.textSecondary)
            .labelStyle(S2LabelStyle())
        }
        .padding(20)
        .s2Card(24)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
    }

    @ViewBuilder private var priceRow: some View {
        switch state {
        case .success:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 34)).foregroundStyle(LHB.positive)
                Text("Pro is yours").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(LHB.textPrimary)
            }
            .transition(.opacity)
        case .priceFailed:
            EmptyView()
        case .priceLoading:
            PlaceholderBar(width: 120, height: 40)
        default:
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("$29.99").roundedNumber(44).foregroundStyle(LHB.textPrimary)
                    Text("once, yours to keep").font(.subheadline).foregroundStyle(LHB.textSecondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("$29.99").roundedNumber(44).foregroundStyle(LHB.textPrimary)
                    Text("once, yours to keep").font(.subheadline).foregroundStyle(LHB.textSecondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("29 dollars 99, one-time purchase")
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch state {
        case .priceFailed:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                Text("Couldn’t reach the App Store.")
                Spacer(minLength: 4)
                Button("Try again") {}.fontWeight(.semibold).foregroundStyle(LHB.action)
            }
            .font(.subheadline).foregroundStyle(LHB.caution)
        case .askToBuy:
            Label("Waiting for approval. Pro unlocks when it comes through.", systemImage: "clock")
                .font(.subheadline).foregroundStyle(LHB.textSecondary).labelStyle(S2LabelStyle())
        default: EmptyView()
        }
    }

    @ViewBuilder private var buyButton: some View {
        let label: String = {
            switch state {
            case .priceLoading, .priceFailed: return "Unlock Pro"
            case .buying: return "Waiting for the App Store"
            case .askToBuy: return "Done"
            case .success: return nextStep
            default: return big ? "Unlock Pro" : "Unlock for $29.99"
            }
        }()
        VStack(spacing: 8) {
            Button {} label: {
                Text(label).contentTransition(.opacity).lineLimit(2).multilineTextAlignment(.center)
            }
            .buttonStyle(S2Primary())
            .disabled(state == .priceLoading || state == .priceFailed)
            .overlay(alignment: .bottom) {
                if state == .buying {
                    DraftingLine(color: Color(light: 0x8FD3FF, dark: 0x0B1230), lineWidth: 2).padding(.horizontal, 26).padding(.bottom, 6)
                }
            }
            .accessibilityIdentifier("paywall.buy")
            if state == .failed {
                Text("That didn’t go through. Try again in a moment.")
                    .font(.subheadline).foregroundStyle(LHB.caution).multilineTextAlignment(.center)
            }
        }
    }

    // MARK: Benefits + footer

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What you get").s2Section().padding(.horizontal, 4)
            benefit("house.fill", "Every rental", "Free covers one.")
            benefit("doc.richtext", "PDF and spreadsheet", "Ready for your accountant.")
            benefit("location.fill", "Location for every rental", "Visits turn into hours to confirm.")
            benefit("calendar.badge.checkmark", "Where each hour came from", "Calendar, location, receipt or typed.")
        }
    }

    private func benefit(_ symbol: String, _ title: String, _ line: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(LHB.action).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(LHB.textPrimary)
                Text(line).font(.subheadline).foregroundStyle(LHB.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("Terms"); Text("·"); Text("Privacy")
        }
        .font(.footnote).foregroundStyle(LHB.textSecondary)
    }
}

struct S2LabelStyle: LabelStyle {
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 22
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) { configuration.icon.frame(minWidth: iconWidth); configuration.title }
    }
}

// MARK: - The record page (page 1 of the PDF, drawn plain)

struct RecordPage: View {
    enum Highlight { case none, newRow, total }
    var highlight: Highlight = .none
    var sample = false

    private let ink = Color(hex: 0x121B33)
    private let grey = Color(hex: 0x6B7280)
    private let rule = Color(hex: 0xD5DBEA)

    private var rows: [(String, String, String)] {
        // A free user has one rental: the page shows only that one. The second row exists only
        // as the cyan "new row" preview in the .secondProperty context.
        let own = sample ? [("Sample Cabin", "Long stays", "140.5")] : [("Pine Cabin", "A few nights", "212.0")]
        return highlight == .newRow ? own + [("Oak Street Duplex", "Long stays", "—")] : own
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("LANDLORDHOURS").font(.system(size: 6.5, weight: .semibold, design: .monospaced)).tracking(0.8).foregroundStyle(LHB.brand)
                Spacer()
                Text("Page 1 of 4").font(.system(size: 6)).foregroundStyle(grey)
            }
            Text("2026 hours record").font(.system(size: 13, weight: .semibold, design: .serif)).foregroundStyle(ink)
            Text(sample ? "Sample owner · Jan 1 – Oct 19, 2026" : "Nguyen Le · Jan 1 – Oct 19, 2026").font(.system(size: 6.5)).foregroundStyle(grey)
            Rectangle().fill(rule).frame(height: 0.5)
            HStack {
                Text("PROPERTY"); Spacer(); Text("HOURS")
            }
            .font(.system(size: 5.5, weight: .semibold)).foregroundStyle(grey)
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                let isNew = highlight == .newRow && i == 1
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.0).font(.system(size: 7.5, weight: .semibold))
                        Text(r.1).font(.system(size: 5.5)).foregroundStyle(grey)
                    }
                    Spacer()
                    Text(isNew ? "—" : r.2).font(.system(size: 7.5, weight: .semibold)).monospacedDigit()
                }
                .foregroundStyle(ink)
                .padding(.horizontal, isNew ? 4 : 0).padding(.vertical, isNew ? 3 : 0)
                .background { if isNew { RoundedRectangle(cornerRadius: 3).fill(LHB.draftingHero.opacity(0.28)) } }
                .overlay { if isNew { RoundedRectangle(cornerRadius: 3).strokeBorder(Color(hex: 0x2369B5), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2])) } }
            }
            Rectangle().fill(rule).frame(height: 0.5)
            HStack {
                Text("Total confirmed").font(.system(size: 7.5, weight: .semibold))
                Spacer()
                Text(sample ? "140.5h" : "212.0h").font(.system(size: 9, weight: .bold)).monospacedDigit()
            }
            .foregroundStyle(ink)
            .padding(.horizontal, highlight == .total ? 4 : 0).padding(.vertical, highlight == .total ? 3 : 0)
            .background { if highlight == .total { RoundedRectangle(cornerRadius: 3).fill(LHB.draftingHero.opacity(0.28)) } }
            Text("BY KIND OF WORK").font(.system(size: 5.5, weight: .semibold)).foregroundStyle(grey).padding(.top, 4)
            ForEach([("Repairs", 0.42), ("Management", 0.27), ("Leasing", 0.18), ("Bookkeeping", 0.13)], id: \.0) { k in
                HStack(spacing: 4) {
                    Text(k.0).font(.system(size: 6)).frame(width: 46, alignment: .leading)
                    GeometryReader { g in
                        Capsule().fill(Color(hex: 0x2369B5).opacity(0.7)).frame(width: g.size.width * k.1)
                    }
                    .frame(height: 3.5)
                }
                .foregroundStyle(ink)
            }
            Text("ENTRIES").font(.system(size: 5.5, weight: .semibold)).foregroundStyle(grey).padding(.top, 4)
            ForEach(0..<6, id: \.self) { i in
                HStack {
                    Text(["Oct 18", "Oct 16", "Oct 12", "Oct 8", "Oct 4", "Sep 30"][i]).frame(width: 26, alignment: .leading)
                    Text(["Plumber", "Showing", "Key handoff", "Monthly books", "Gutter repair", "Tenant call"][i])
                    Spacer()
                    Text(["2.0", "1.0", "0.5", "1.5", "3.0", "0.5"][i]).monospacedDigit()
                }
                .font(.system(size: 6)).foregroundStyle(ink)
                Rectangle().fill(rule.opacity(0.6)).frame(height: 0.3)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .padding(.top, 18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .overlay(alignment: .topTrailing) {
            if sample {
                Text("SAMPLE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                    .foregroundStyle(Color(hex: 0x2369B5).opacity(0.55))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(hex: 0x2369B5).opacity(0.55), lineWidth: 1.5))
                    .rotationEffect(.degrees(-6))
                    .padding(.top, 34).padding(.trailing, 12)
            }
        }
        .environment(\.colorScheme, .light)
    }
}
