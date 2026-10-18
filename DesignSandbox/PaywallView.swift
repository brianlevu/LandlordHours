import SwiftUI

/// The appearance the viewer asked for, carried past a forced-dark presentation
/// (used so the paywall can force a light status bar over its dark hero in both themes).
private struct RequestedSchemeKey: EnvironmentKey { static let defaultValue: ColorScheme? = nil }
extension EnvironmentValues {
    var requestedScheme: ColorScheme? {
        get { self[RequestedSchemeKey.self] }
        set { self[RequestedSchemeKey.self] = newValue }
    }
}

/// One-time $29.99. The hero is the real report, in a device frame; the price is the most
/// prominent thing on the card; Restore sits directly under the buy button.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestedScheme) private var requested

    private var contentScheme: ColorScheme {
        if let requested { return requested }
        return UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    PaywallHero()
                    planCard
                        .padding(.horizontal, 16)
                        .padding(.top, -64)
                    features
                        .padding(.horizontal, 20)
                        .padding(.top, 36)
                        .padding(.bottom, 48)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(LH.canvas)
            .ignoresSafeArea(edges: .top)
            .environment(\.colorScheme, contentScheme)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        // Light status bar over the dark hero, in both themes. Content keeps the viewer's scheme.
        .preferredColorScheme(.dark)
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("LandlordHours Pro").font(.title3.weight(.semibold))
                Spacer()
                Text("Pay once")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LH.action)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(LH.actionWash, in: Capsule())
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("$29.99")
                    .font(.system(size: 48, weight: .bold))
                    .monospacedDigit()
                    .tracking(-0.5)
                Text("once, yours to keep")
                    .font(.body)
                    .foregroundStyle(LH.secondaryText)
            }
            .padding(.top, 10)
            Text("Export the PDF, keep every property, and turn on location for all of them.")
                .font(.subheadline)
                .foregroundStyle(LH.secondaryText)
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
            .foregroundStyle(LH.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .padding(20)
        .background(LH.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(contentScheme == .dark ? 0 : 0.10), radius: 20, y: 8)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("What you get").sectionLabel()
            Feature(symbol: "doc.richtext", title: "A PDF your accountant can use",
                    text: "Every hour, where it came from, and when you confirmed it.")
            Feature(symbol: "house.and.flag", title: "All your properties",
                    text: "Free covers one. Pro covers as many as you own.")
            Feature(symbol: "location", title: "Location for every property",
                    text: "Free covers one address.")
            Feature(symbol: "person.2", title: "Spouse hours and the 50% rule",
                    text: "See both of you toward the same goal.")
            Text("Finding and confirming hours stays free.")
                .font(.footnote)
                .foregroundStyle(LH.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Dark-to-violet backdrop that dissolves into the page background (no seam), headline,
/// and the real report shown inside a device frame.
struct PaywallHero: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(stops: [
                .init(color: Color(hex: 0x0B0920), location: 0),
                .init(color: Color(hex: 0x24196B), location: 0.45),
                .init(color: Color(hex: 0x4A3CC4), location: 0.72),
                .init(color: LH.canvas, location: 1),
            ], startPoint: .top, endPoint: .bottom)

            VStack(spacing: 22) {
                Text("The record your accountant gets")
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 48)
                DeviceFrame(width: 236) {
                    PDFScreen()
                }
                .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
            }
            .padding(.top, 104)
        }
        .frame(height: 540, alignment: .top)
        .clipped()
    }
}

struct DeviceFrame<Content: View>: View {
    var width: CGFloat
    @ViewBuilder var content: Content
    var body: some View {
        let h = width * 2.17
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: width * 0.19, style: .continuous)
                .fill(Color(hex: 0x16161A))
                .overlay(
                    RoundedRectangle(cornerRadius: width * 0.19, style: .continuous)
                        .strokeBorder(Color(hex: 0x4A4A52), lineWidth: 1.5)
                )
            content
                .frame(width: width - 16, height: h - 16)
                .clipShape(RoundedRectangle(cornerRadius: width * 0.19 - 8, style: .continuous))
                .padding(8)
            Capsule().fill(.black).frame(width: width * 0.3, height: 22).padding(.top, 18)
        }
        .frame(width: width, height: h)
    }
}

/// A miniature of the in-app PDF screen (light), used inside the device frame.
struct PDFScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PDF").font(.system(size: 22, weight: .bold)).padding(.top, 52)
            PDFThumb(width: 188)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: 0xF2F2F7))
        .foregroundStyle(Color(hex: 0x1A1A1A))
        .environment(\.colorScheme, .light)
    }
}
