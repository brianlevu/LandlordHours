import SwiftUI

// Shared onboarding scaffold: 28pt bold title, 17pt secondary body, pinned bottom actions.
struct OnboardingScaffold<Content: View, Footer: View>: View {
    var step: Int
    var title: String
    var body_: String
    var tag: String? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if step > 0 {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                Spacer()
                StepDots(step: step)
                Spacer()
                if step > 0 { Color.clear.frame(width: 44, height: 44) }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(title)
                            .font(.title.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if tag != nil {
                        BetaTag().padding(.top, 10)
                    }
                    Text(body_)
                        .font(.body)
                        .foregroundStyle(LH.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                    content
                        .padding(.top, 28)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 12) { footer }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .background(Color(uiColor: .systemBackground))
    }
}

struct StepDots: View {
    var step: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<4) { i in
                Capsule()
                    .fill(i == step ? LH.action : LH.fill)
                    .frame(width: i == step ? 18 : 6, height: 6)
            }
        }
        .accessibilityLabel("Step \(step + 1) of 4")
    }
}

struct PrivacyFooter: View {
    var title: String
    var message: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 20))
                .foregroundStyle(LH.positive)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(LH.positive)
                Text(message).font(.footnote).foregroundStyle(LH.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(LH.positiveWash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - A. Welcome

struct OnboardingWelcome: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 56)
            AppMark(size: 64)
            Text("Rental work,\nnoticed for you.")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.4)
                .padding(.top, 28)
            Text("LandlordHours finds the hours you already spend on your rentals and builds the record your accountant needs.")
                .font(.body)
                .foregroundStyle(LH.secondaryText)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 22) {
                Feature(symbol: "calendar", title: "Finds work on your calendar",
                        text: "Plumber visits, showings and turnovers become suggestions.")
                Feature(symbol: "checkmark.circle", title: "Asks before it saves",
                        text: "Nothing goes in your record until you confirm it.")
                Feature(symbol: "doc.text", title: "Ready for tax time",
                        text: "A clean PDF of every hour, with where it came from.")
            }
            .padding(.top, 40)

            Spacer()
            Button("Get started") {}
                .buttonStyle(PrimaryCapsule())
            Text("Your records stay on your iPhone and in your iCloud.")
                .font(.footnote)
                .foregroundStyle(LH.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .background(Color(uiColor: .systemBackground))
    }
}

struct AppMark: View {
    var size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x6E5FF0), Color(hex: 0x4A3BC4)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                ZStack {
                    Image(systemName: "house.fill")
                        .font(.system(size: size * 0.46, weight: .semibold))
                        .foregroundStyle(.white)
                    Image(systemName: "clock.fill")
                        .font(.system(size: size * 0.2, weight: .bold))
                        .foregroundStyle(Color(hex: 0x4A3BC4))
                        .offset(y: size * 0.06)
                }
            }
            .shadow(color: Color(hex: 0x4A3BC4).opacity(0.25), radius: 10, y: 4)
            .accessibilityHidden(true)
    }
}

struct Feature: View {
    var symbol: String
    var title: String
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(LH.action)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(text).font(.subheadline).foregroundStyle(LH.secondaryText)
            }
        }
    }
}

// MARK: - D. Add property

struct OnboardingProperty: View {
    @State private var type = 1
    @State private var manager = 1

    var body: some View {
        OnboardingScaffold(step: 1, title: "Add your first property",
                           body_: "We use it to match calendar events and receipts to the right place.") {
            VStack(alignment: .leading, spacing: 28) {
                VStack(spacing: 0) {
                    FieldRow(label: "Name", value: "Pine Cabin")
                    Divider().padding(.leading, 16)
                    FieldRow(label: "Address", value: "41 Ridge Rd, Big Bear Lake")
                }
                .background(LH.tertiaryFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("How do guests stay?").sectionLabel()
                    Picker("Type", selection: $type) {
                        Text("Long-term").tag(0)
                        Text("Short-term").tag(1)
                    }
                    .pickerStyle(.segmented)
                    Text("Short-term means an average stay of 7 days or less.")
                        .font(.footnote).foregroundStyle(LH.secondaryText)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Who does the work?").sectionLabel()
                    VStack(spacing: 0) {
                        RadioRow(symbol: "person", title: "Just me", text: "I look after it myself", on: manager == 0)
                        Divider().padding(.leading, 52)
                        RadioRow(symbol: "person.2", title: "Me and my spouse", text: "Both of our hours count if we file jointly", on: manager == 1)
                        Divider().padding(.leading, 52)
                        RadioRow(symbol: "building.2", title: "A property manager", text: "Their hours don't count toward yours", on: manager == 2)
                    }
                    .background(LH.tertiaryFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        } footer: {
            Button("Continue") {}.buttonStyle(PrimaryCapsule())
        }
    }
}

struct FieldRow: View {
    var label: String
    var value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(LH.secondaryText).frame(width: 80, alignment: .leading)
            Text(value)
            Spacer()
        }
        .font(.body)
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
}

struct RadioRow: View {
    var symbol: String
    var title: String
    var text: String
    var on: Bool
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(LH.secondaryText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(text).font(.footnote).foregroundStyle(LH.secondaryText)
            }
            Spacer()
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(on ? LH.action : Color(uiColor: .tertiaryLabel))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 60)
    }
}

// MARK: - E. Calendar priming

struct OnboardingCalendar: View {
    @State private var on = true
    var body: some View {
        OnboardingScaffold(step: 2, title: "Find rental work in your calendar",
                           body_: "We look for things like plumber, showing and turnover, then ask you before anything is saved.") {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 0) {
                    Toggle(isOn: $on) {
                        Label("Find rental work in my calendar", systemImage: "calendar")
                    }
                    .tint(LH.action)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    Divider().padding(.leading, 52)
                    HStack {
                        Label("Choose calendars", systemImage: "checklist")
                        Spacer()
                        Text("2 of 4").foregroundStyle(LH.secondaryText)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                }
                .labelStyle(SettingsLabel())
                .background(LH.tertiaryFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text("What a suggestion looks like").sectionLabel()
                    HStack(spacing: 12) {
                        VStack(spacing: 0) {
                            Text("2").font(.system(size: 24, weight: .semibold))
                            Text("Hours").font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(LH.secondaryText)
                        }
                        .frame(width: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Label {
                                Text("Calendar · Tue 9–11")
                            } icon: {
                                Image(systemName: "calendar").foregroundStyle(LH.srcCalendar)
                            }
                            .labelStyle(TightLabel())
                            .font(.subheadline).foregroundStyle(LH.secondaryText)
                            Text("\(Text("Plumber").fontWeight(.semibold)) at \(Text("Pine Cabin").fontWeight(.semibold))")
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(LH.tertiaryFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text("We'll look back 90 days, so your first suggestions are ready right away.")
                        .font(.footnote).foregroundStyle(LH.secondaryText)
                }
            }
        } footer: {
            PrivacyFooter(title: "Stays on your iPhone",
                          message: "We read event titles on device. Only events you confirm are saved.")
                .padding(.bottom, 8)
            Button("Continue") {}.buttonStyle(PrimaryCapsule())
            Button("Not now") {}
                .font(.body).foregroundStyle(LH.action).frame(minHeight: 44)
        }
    }
}

struct SettingsLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 14) {
            configuration.icon
                .font(.system(size: 18))
                .foregroundStyle(LH.secondaryText)
                .frame(width: 22)
            configuration.title
        }
    }
}

// MARK: - E2. Location "Always" priming (beta)

struct OnboardingLocation: View {
    var body: some View {
        OnboardingScaffold(step: 3, title: "Notice when you're at Oak Street",
                           body_: "To notice when you arrive and leave while the app is closed, iOS asks for Always access.",
                           tag: "Beta") {
            VStack(spacing: 10) {
                SystemAlertPreview()
                    .fixedSize(horizontal: false, vertical: true)
                    .scaleEffect(0.84)
                    .padding(.vertical, -30)
                Text("When iOS asks, pick “Change to Always Allow.”")
                    .font(.footnote)
                    .foregroundStyle(LH.secondaryText)
                    .multilineTextAlignment(.center)
                PrivacyFooter(title: "Only your property addresses",
                              message: "We check for arrivals at the addresses you add. Your location history is never stored or sent.")
                    .padding(.top, 24)
            }
            .frame(maxWidth: .infinity)
        } footer: {
            Button("Continue") {}.buttonStyle(PrimaryCapsule())
            Button("Not now") {}
                .font(.body).foregroundStyle(LH.action).frame(minHeight: 44)
        }
    }
}

/// Static replica of the iOS "upgrade to Always" alert, used as a preview (Sesame idiom).
struct SystemAlertPreview: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Allow “LandlordHours” to also use your location even when you are not using the app?")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("We only check the addresses of the properties you add.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(LH.secondaryText)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 16)

            MiniMap()
                .frame(height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)

            VStack(spacing: 8) {
                alertButton("Keep Only While Using", highlighted: false)
                alertButton("Change to Always Allow", highlighted: true)
            }
            .padding(16)
        }
        .frame(width: 300)
        .background(scheme == .dark ? Color(hex: 0x2C2C2E) : Color(hex: 0xF2F2F7),
                    in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview of the iOS location prompt")
    }

    private func alertButton(_ t: String, highlighted: Bool) -> some View {
        Text(t)
            .font(.body.weight(highlighted ? .semibold : .regular))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Color.primary.opacity(0.07), in: Capsule())
            .overlay {
                if highlighted { Capsule().strokeBorder(LH.action, lineWidth: 2) }
            }
    }
}

struct MiniMap: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { ctx, size in
            let bg = scheme == .dark ? Color(hex: 0x3A3A3C) : Color(hex: 0xE9E6DF)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))
            let road = scheme == .dark ? Color(hex: 0x56565A) : Color.white
            for (i, y) in [0.3, 0.72].enumerated() {
                var p = Path(); p.move(to: CGPoint(x: 0, y: size.height * y))
                p.addLine(to: CGPoint(x: size.width, y: size.height * (y + (i == 0 ? 0.1 : -0.15))))
                ctx.stroke(p, with: .color(road), lineWidth: 6)
            }
            for x in [0.25, 0.62] {
                var p = Path(); p.move(to: CGPoint(x: size.width * x, y: 0))
                p.addLine(to: CGPoint(x: size.width * (x + 0.05), y: size.height))
                ctx.stroke(p, with: .color(road), lineWidth: 4)
            }
            let park = scheme == .dark ? Color(hex: 0x2F4A36) : Color(hex: 0xCFE5C8)
            ctx.fill(Path(roundedRect: CGRect(x: size.width * 0.7, y: size.height * 0.05, width: size.width * 0.25, height: size.height * 0.35), cornerRadius: 6), with: .color(park))
        }
        .overlay {
            ZStack {
                Circle().fill(Color(hex: 0x0A84FF).opacity(0.18)).frame(width: 64, height: 64)
                Circle().fill(.white).frame(width: 16, height: 16)
                Circle().fill(Color(hex: 0x0A84FF)).frame(width: 12, height: 12)
            }
        }
    }
}
