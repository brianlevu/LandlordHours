import SwiftUI
import LucideIcons

#if DEBUG
// MARK: - "Check my goal" and the Inbox card that leads to it (prototype)

private enum WhoDoesMost: CaseIterable, Hashable {
    case me, meAndSpouse, someoneElse, notSure

    var title: String {
        switch self {
        case .me: return String(localized: "Me", table: "HomeProto")
        case .meAndSpouse: return String(localized: "Me and my spouse", table: "HomeProto")
        case .someoneElse: return String(localized: "A cleaner, manager or contractor", table: "HomeProto")
        case .notSure: return String(localized: "Not sure", table: "HomeProto")
        }
    }

    /// The short form for the collapsed row.
    var short: String {
        switch self {
        case .someoneElse: return String(localized: "Someone else", table: "HomeProto")
        default: return title
        }
    }
}

struct HomeProtoGoalCheckRoot: View {
    let step: HomeProtoLaunch.Step
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        if step == .inbox { HomeProtoInboxPage() } else { HomeProtoCheckPage(scrollToDiff: step == .diff) }
    }
}

// MARK: Inbox card

struct HomeProtoInboxPage: View {
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Inbox", tableName: "HomeProto")
                    .font(LHFont.fraunces(.largeTitle)).foregroundStyle(colors.textPrimary)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                card
            }
            .padding(.horizontal, 20).padding(.bottom, 40)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                LucideIcon(image: Lucide.calendar, size: 16).foregroundStyle(colors.draftingInk)
                Text("From your calendar", tableName: "HomeProto")
                    .font(mono(11)).textCase(.uppercase).tracking(1.3).foregroundStyle(colors.draftingInk)
            }
            Text("A cleaner seems to work at Santa Ray Ave", tableName: "HomeProto")
                .font(.title3.weight(.semibold)).foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("A weekly “Turnover clean” is on your calendar there. Do they do more hours at Santa Ray Ave than you?", tableName: "HomeProto")
                .font(.subheadline).foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                choice(String(localized: "Yes, they do more", table: "HomeProto"), primary: true)
                choice(String(localized: "No, I do more", table: "HomeProto"), primary: false)
                choice(String(localized: "That’s not a cleaner", table: "HomeProto"), primary: false)
            }
            .padding(.top, 4)
            Text("Nothing changes until you tap.", tableName: "HomeProto")
                .font(.footnote).foregroundStyle(colors.textSecondary)
        }
        .padding(18)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func choice(_ title: String, primary: Bool) -> some View {
        Button {} label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primary ? colors.onAction : colors.action)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12)
                .background(Capsule().fill(primary ? colors.action : colors.actionSurface))
        }
        .buttonStyle(.lhPressable)
    }

    private func mono(_ size: CGFloat) -> Font { .system(.caption2, design: .monospaced).weight(.medium) }
}

// MARK: Check my goal

struct HomeProtoCheckPage: View {
    let scrollToDiff: Bool
    @State private var santa: WhoDoesMost = .someoneElse
    @State private var delaney: WhoDoesMost = .someoneElse
    @State private var yeandle: WhoDoesMost = .someoneElse
    @State private var open = "santa"
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private func mono(_ size: CGFloat) -> Font { .system(.caption2, design: .monospaced).weight(.medium) }

    /// 100 only while nobody else does more at that rental; otherwise 500 (no comparison).
    private var santaTarget: Int { (santa == .me || santa == .meAndSpouse) ? 100 : 500 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Check my goal", tableName: "HomeProto")
                        .font(LHFont.fraunces(.largeTitle)).foregroundStyle(colors.textPrimary)
                        .padding(.top, 8)
                        .accessibilityAddTraits(.isHeader)
                    Text("Say who does most of the hands-on work at each rental. The app shows what it would track, and you choose.", tableName: "HomeProto")
                        .font(.subheadline).foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    question(id: "santa", name: "Santa Ray Ave", answer: $santa)
                    question(id: "delaney", name: "Delaney Ct", answer: $delaney)
                    question(id: "yeandle", name: "Yeandle Ave", answer: $yeandle)
                    diff.id("diff")
                    buttons
                    Text("Reaching a number is based on your records; your CPA decides what it means.", tableName: "HomeProto")
                        .font(.footnote).foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {} label: {
                        Text("Share with your CPA", tableName: "HomeProto")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(colors.action)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.lhPressable)
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
            .onAppear { if scrollToDiff { DispatchQueue.main.async { proxy.scrollTo("diff", anchor: .top) } } }
        }
    }

    // MARK: Question

    @ViewBuilder private func question(id: String, name: String, answer: Binding<WhoDoesMost>) -> some View {
        let isOpen = open == id
        VStack(alignment: .leading, spacing: 10) {
            if isOpen {
                Text("Who does most of the hands-on work at \(name)?", tableName: "HomeProto")
                    .font(.headline).foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    ForEach(WhoDoesMost.allCases, id: \.self) { option in
                        let selected = answer.wrappedValue == option
                        Button { answer.wrappedValue = option } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(selected ? colors.action : colors.textTertiary)
                                Text(option.title).font(.subheadline.weight(.medium))
                                    .foregroundStyle(colors.textPrimary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(selected ? colors.actionSurface : colors.backgroundTertiary,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.lhPressable)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            } else {
                Button { withAnimation(AppAnimation.standard) { open = id } } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.headline).foregroundStyle(colors.textPrimary)
                            Text(answer.wrappedValue.short).font(.subheadline).foregroundStyle(colors.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Text("Change", tableName: "HomeProto")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(colors.action)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.lhPressable)
            }
        }
        .padding(16)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: Diff

    private var diff: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What the app would track", tableName: "HomeProto")
                .font(mono(11)).textCase(.uppercase).tracking(1.3).foregroundStyle(colors.draftingInk)
                .accessibilityAddTraits(.isHeader)
            diffRow(name: "Santa Ray Ave", from: String(localized: "100 hours", table: "HomeProto"),
                    to: santaTarget == 100 ? nil : String(localized: "500 hours", table: "HomeProto"),
                    why: santaTarget == 100
                        ? String(localized: "You do most of the work, so 100 hours and more than anyone else still fits", table: "HomeProto")
                        : String(localized: "Someone else does more hours here, so 100 can’t be reached. 500 doesn’t compare you with anyone", table: "HomeProto"))
            Divider().overlay(colors.border)
            diffRow(name: "Delaney Ct", from: String(localized: "Record only", table: "HomeProto"), to: nil,
                    why: String(localized: "A manager does most of the work here", table: "HomeProto"))
            Divider().overlay(colors.border)
            diffRow(name: "Yeandle Ave", from: String(localized: "Record only", table: "HomeProto"), to: nil,
                    why: String(localized: "Long stays have no target under your goal", table: "HomeProto"))
        }
        .padding(16)
        .background(colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func diffRow(name: String, from: String, to: String?, why: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.headline).foregroundStyle(colors.textPrimary)
            if let to {
                HStack(spacing: 8) {
                    Text(from).strikethrough().foregroundStyle(colors.textSecondary)
                    LucideIcon(image: Lucide.chevronRight, size: 14).foregroundStyle(colors.textSecondary)
                    Text(to).fontWeight(.semibold).foregroundStyle(colors.action)
                }
                .font(.subheadline)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "From \(from) to \(to)", table: "HomeProto"))
            } else {
                Text("\(from) · no change", tableName: "HomeProto").font(.subheadline).foregroundStyle(colors.textPrimary)
            }
            Text(why).font(.footnote).foregroundStyle(colors.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            if santaTarget != 100 {
                Button {} label: {
                    Text("Switch Santa Ray Ave to 500", tableName: "HomeProto")
                        .font(.body.weight(.semibold)).foregroundStyle(colors.onAction)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 52).padding(.horizontal, 16)
                        .background(Capsule().fill(colors.action))
                }
                .buttonStyle(.lhPressable)
            }
            Button {} label: {
                Text("Keep what I have", tableName: "HomeProto")
                    .font(.body.weight(.semibold)).foregroundStyle(colors.action)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(colors.actionSurface))
            }
            .buttonStyle(.lhPressable)
        }
    }
}
#endif
