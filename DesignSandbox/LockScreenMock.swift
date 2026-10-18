import SwiftUI

/// MOCK OF SYSTEM UI. A faithful SwiftUI rendering of the iOS Lock Screen with our
/// Live Activity and an expanded end-of-event notification. Not the real system surface.
struct LockScreenMock: View {
    @Environment(\.colorScheme) private var scheme
    @State private var start = Date().addingTimeInterval(-(42 * 60 + 18))

    var body: some View {
        ZStack {
            Wallpaper()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                statusIcons
                    .padding(.horizontal, 28)
                    .padding(.top, 14)

                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.top, 8)

                Text("Saturday, October 18")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 6)
                Text("9:41")
                    .font(.system(size: 104, weight: .semibold))
                    .tracking(-2)
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.top, -12)

                Spacer(minLength: 12)

                VStack(spacing: 10) {
                    LiveActivityCard(start: start)
                    NotificationExpanded()
                }
                .padding(.horizontal, 10)

                Spacer(minLength: 12)

                HStack {
                    QuickButton(symbol: "flashlight.off.fill")
                    Spacer()
                    Text("Mock of system UI")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.35), in: Capsule())
                    Spacer()
                    QuickButton(symbol: "camera.fill")
                }
                .padding(.horizontal, 46)
                .padding(.bottom, 6)
            }
        }
        .statusBarHidden(true)
        .environment(\.colorScheme, scheme)
    }

    private var statusIcons: some View {
        HStack(spacing: 6) {
            Text("Verizon")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Image(systemName: "cellularbars")
            Image(systemName: "wifi")
            Image(systemName: "battery.100percent")
                .font(.system(size: 19))
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
    }
}

struct Wallpaper: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let light: [Color] = [
            Color(hex: 0x7B6EE8), Color(hex: 0x9C8CF2), Color(hex: 0xC9A6E8),
            Color(hex: 0x5A4FC9), Color(hex: 0x8A79E6), Color(hex: 0xE3A9B8),
            Color(hex: 0x2E2A7A), Color(hex: 0x4B3FA6), Color(hex: 0xC27A8E),
        ]
        let dark: [Color] = [
            Color(hex: 0x231C5C), Color(hex: 0x352A85), Color(hex: 0x4A2F6E),
            Color(hex: 0x15123D), Color(hex: 0x2B2270), Color(hex: 0x5A2C55),
            Color(hex: 0x07061A), Color(hex: 0x120F33), Color(hex: 0x3A1A3A),
        ]
        MeshGradient(width: 3, height: 3,
                     points: [[0, 0], [0.5, 0], [1, 0],
                              [0, 0.5], [0.55, 0.45], [1, 0.55],
                              [0, 1], [0.5, 1], [1, 1]],
                     colors: scheme == .dark ? dark : light)
    }
}

struct QuickButton: View {
    var symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20))
            .foregroundStyle(.white)
            .frame(width: 50, height: 50)
            .glassEffect(.regular, in: Circle())
    }
}

/// Live Activity — lock screen presentation (Flighty two-ends + strip, Fitness tinted timer).
struct LiveActivityCard: View {
    var start: Date
    private let violet = Color(hex: 0xA99BFF)
    private let green = Color(hex: 0x30D158)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Pine Cabin", systemImage: "house.fill")
                    .labelStyle(TightLabel())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("LANDLORDHOURS")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.white.opacity(0.6))
            }

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Started 9:00")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                    Text("Ends 11:00")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Text(timerInterval: start...start.addingTimeInterval(8 * 3600), countsDown: false)
                    .font(.system(size: 40, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(violet)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 170, alignment: .trailing)
            }
            .padding(.top, 8)

            ProgressView(timerInterval: start...start.addingTimeInterval(2 * 3600), countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(violet)
            .padding(.top, 10)

            Divider().overlay(.white.opacity(0.18)).padding(.top, 12)

            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Plumber visit")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("From your calendar")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Text("Stop")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .background(.white, in: Capsule())
            }
            .padding(.top, 10)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.black.opacity(0.62))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .environment(\.colorScheme, .dark)
    }
}

/// End-of-event notification, long-pressed so its actions show (expanded).
struct NotificationExpanded: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                AppMark(size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text("Plumber visit just ended")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text("now")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Text("Log 2 h at Pine Cabin? It goes in your record only if you say so.")
                        .font(.system(size: 15))
                }
            }
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(spacing: 0) {
                actionRow("Log 2 h", symbol: "checkmark.circle")
                Divider().padding(.leading, 16)
                actionRow("Edit…", symbol: "pencil")
                Divider().padding(.leading, 16)
                actionRow("Not work", symbol: "xmark.circle")
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .frame(width: 250)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actionRow(_ t: String, symbol: String) -> some View {
        HStack {
            Text(t).font(.system(size: 17))
            Spacer()
            Image(systemName: symbol).font(.system(size: 17))
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }
}
