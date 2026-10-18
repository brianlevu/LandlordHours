import SwiftUI

/// One-time $29.99. The hero is the real report page; the price is the most prominent thing on the card;
/// Restore sits directly under the buy button.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
        ScrollView {
            VStack(spacing: 0) {
                hero
                planCard
                    .padding(.horizontal, 16)
                    .padding(.top, -48)
                features
                    .padding(.horizontal, 20)
                    .padding(.top, 36)
                    .padding(.bottom, 48)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(LH.canvas)
        .ignoresSafeArea(edges: .top)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .close) { dismiss() }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var hero: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x0E0B24), Color(hex: 0x2A1F78), Color(hex: 0x5B4CDB)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 18) {
                Text("The record your\naccountant gets")
                    .font(.system(size: 24, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                PDFThumb(width: 214)
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            }
            .padding(.top, 104)
        }
        .frame(height: 470)
        .clipped()
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("LandlordHours Pro").font(.title3.weight(.semibold))
                Spacer()
                Text("PAY ONCE")
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(LH.action)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(LH.actionWash, in: Capsule())
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("$29.99")
                    .font(.system(size: 48, weight: .bold))
                    .monospacedDigit()
                    .tracking(-0.5)
                Text("once, yours to keep")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
            Text("Export the PDF, keep every property, and turn on location for all of them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            Button("Unlock for $29.99") {}
                .buttonStyle(PrimaryCapsule())
                .padding(.top, 20)
            Button("Restore purchase") {}
                .font(.subheadline.weight(.medium))
                .foregroundStyle(LH.action)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 4)

            Divider().padding(.vertical, 8)
            HStack(spacing: 20) {
                Label("No subscription", systemImage: "checkmark.circle")
                Label("Family Sharing", systemImage: "person.2")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .padding(20)
        .background(LH.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.10), radius: 20, y: 8)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("What you get").font(.title3.weight(.semibold))
            Feature(symbol: "doc.richtext", title: "A PDF your accountant can use",
                    text: "Every hour, where it came from, and when you confirmed it.")
            Feature(symbol: "house.and.flag", title: "All your properties",
                    text: "Free covers one. Pro covers as many as you own.")
            Feature(symbol: "location", title: "Location for every property",
                    text: "Beta. Free covers one address.")
            Feature(symbol: "person.2", title: "Spouse hours and the 50% rule",
                    text: "See both of you toward the same goal.")
            Text("Finding and confirming hours stays free.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
