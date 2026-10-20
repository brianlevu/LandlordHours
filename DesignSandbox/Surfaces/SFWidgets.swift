import SwiftUI

// §1 Home and Lock Screen widgets. Families = what the widget target supports today:
// systemSmall, systemMedium, accessoryCircular, accessoryRectangular, accessoryInline.
// Sizes (pt) for a 402×874 iPhone (16 Pro / 17 Pro, the capture device):
//   small 162×162 · medium 344×162 · circular 72×72 · rectangular 160×72 · inline one line.
// Home widgets are the Today hero in miniature: theme-fixed blueprint paper, the house at its
// real stage, SF Rounded number, SF Mono label. REPS shows YOUR hours only (IRC 469(c)(7)(B)).

enum SFWidgetSize {
    static let small = CGSize(width: 162, height: 162)
    static let medium = CGSize(width: 344, height: 162)
    static let circular: CGFloat = 72
    static let rectangular = CGSize(width: 160, height: 72)
    static let radius: CGFloat = 22
}

/// One snapshot drives every family (production: EngagementWidgetSnapshot + a pending count).
struct SFWidgetData {
    enum Kind { case behind, onPace, empty, noProperty, met, timer }
    var kind: Kind
    var hours: Double
    var goal: Double = 750
    var gap: Int = 0
    var pending: Int = 0

    static let behind = SFWidgetData(kind: .behind, hours: 212, gap: 388, pending: 3)
    static let onPace = SFWidgetData(kind: .onPace, hours: 640, pending: 0)
    static let empty = SFWidgetData(kind: .empty, hours: 0, pending: 0)
    static let noProperty = SFWidgetData(kind: .noProperty, hours: 0, pending: 0)
    static let met = SFWidgetData(kind: .met, hours: 768, pending: 1)
    static let timer = SFWidgetData(kind: .timer, hours: 212, gap: 388, pending: 3)

    var houseKey: String { S2House.keyframe(kind == .noProperty ? 0 : hours) }
    var number: String { "\(Int(hours))" }

    /// The pace line, same words as the Today hero.
    var status: (symbol: String, text: String, color: Color)? {
        switch kind {
        case .behind, .timer: ("exclamationmark.circle.fill", "Behind by \(gap)h", Color(hex: 0xFFB454))
        case .onPace: ("checkmark.circle.fill", "On pace", LHB.positiveOnHero)
        case .met: ("checkmark.seal.fill", "House finished", LHB.positiveOnHero)
        case .empty: ("circle.dashed", "Nothing confirmed yet", LHB.onHeroSecondary)
        case .noProperty: nil
        }
    }

    var stage: String {
        switch kind {
        case .noProperty: "An empty lot"
        default:
            hours < 1 ? "An empty lot" : hours < 100 ? "Breaking ground" : hours < 500 ? "Frame going up" : hours < 750 ? "Siding going up" : "Keys in hand"
        }
    }

    var nextMark: String {
        hours < 100 ? "Foundation at 100h" : hours < 500 ? "Roof at 500h" : hours < 750 ? "Keys at 750h" : "Every hour still counts"
    }
}

// MARK: - Home widgets (full colour)

/// Blueprint paper clipped to the widget shape (ContainerRelativeShape in production).
struct SFWidgetPaper: View {
    var body: some View { S2Paper(radius: SFWidgetSize.radius) }
}

struct SFSmallWidget: View {
    let d: SFWidgetData
    var tinted = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            house
                .frame(width: 98, height: 98)
                .position(x: 162 - 49 - 4, y: 30 + 49)
            VStack(alignment: .leading, spacing: 0) {
                Text(d.kind == .timer ? "Timer" : "Your hours").drafting(labelColor, size: 10)
                    .accessibilityHidden(true)
                if d.kind == .noProperty {
                    Spacer(minLength: 0)
                    Text("Add a property to start the house.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(primary)
                        .lineLimit(3)
                        .frame(width: 120, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else if d.kind == .timer {
                    Text("0:42")
                        .roundedNumber(34)
                        .foregroundStyle(primary)
                        .padding(.top, 4)
                    Text("Pine Cabin").font(.system(size: 13, weight: .medium)).foregroundStyle(secondary)
                    Spacer(minLength: 0)
                    statusLine(("timer", "Running", LHB.draftingHero))
                } else {
                    Text(d.number)
                        .roundedNumber(36)
                        .foregroundStyle(primary)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 4)
                    Text("of \(Int(d.goal))h").font(.system(size: 13, weight: .medium)).foregroundStyle(secondary)
                    Spacer(minLength: 0)
                    if let s = d.status { statusLine(s) }
                }
            }
            .padding(14)
            .frame(width: 162, height: 162, alignment: .topLeading)
        }
        .frame(width: 162, height: 162)
        .clipShape(RoundedRectangle(cornerRadius: SFWidgetSize.radius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }

    private var a11y: String {
        switch d.kind {
        case .noProperty: "LandlordHours. Add a property to start the house."
        case .timer: "Timer running at Pine Cabin, 42 minutes."
        default: "\(d.number) of your \(Int(d.goal)) hours. \(d.status?.text ?? "")"
        }
    }

    private func statusLine(_ s: (symbol: String, text: String, color: Color)) -> some View {
        HStack(spacing: 4) {
            Image(systemName: s.symbol).font(.system(size: 11, weight: .bold))
            Text(s.text).lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(tinted ? .white : s.color)
    }

    @ViewBuilder private var background: some View {
        if tinted { SFTintedBackground() } else { SFWidgetPaper() }
    }
    @ViewBuilder private var house: some View {
        if tinted {
            MarkB(mono: .white.opacity(0.9)).padding(18).offset(y: 6)
        } else {
            HouseArt(key: d.houseKey).opacity(d.kind == .timer ? 0.55 : 1)
        }
    }
    private var primary: Color { .white }
    private var secondary: Color { tinted ? .white.opacity(0.7) : LHB.onHeroSecondary }
    private var labelColor: Color { tinted ? .white.opacity(0.7) : LHB.draftingHero }
}

struct SFMediumWidget: View {
    let d: SFWidgetData
    var tinted = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if tinted { SFTintedBackground() } else { SFWidgetPaper() }
            Group {
                if tinted {
                    MarkB(mono: .white.opacity(0.9)).padding(30)
                } else {
                    HouseArt(key: d.houseKey).opacity(d.kind == .timer ? 0.55 : 1)
                }
            }
            .frame(width: 158, height: 158)
            .position(x: 344 - 79 - 2, y: 162 / 2 + 6)

            VStack(alignment: .leading, spacing: 0) {
                Text(label).drafting(tinted ? .white.opacity(0.7) : LHB.draftingHero, size: 10)
                if d.kind == .noProperty {
                    Text("Add a property to start the house.")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    Spacer(minLength: 0)
                    pill("Add property", symbol: "plus")
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(d.kind == .timer ? "0:42" : d.number).roundedNumber(40).foregroundStyle(.white)
                        Text(d.kind == .timer ? "Pine Cabin" : "of \(Int(d.goal))h")
                            .font(.system(size: 15, weight: .medium)).foregroundStyle(tinted ? .white.opacity(0.7) : LHB.onHeroSecondary)
                            .lineLimit(1)
                    }
                    .padding(.top, 2)
                    if let s = d.kind == .timer ? (symbol: "timer", text: "Timer running", color: LHB.draftingHero) : d.status {
                        HStack(spacing: 4) {
                            Image(systemName: s.symbol).font(.system(size: 11, weight: .bold))
                            Text(s.text).lineLimit(1)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tinted ? .white : s.color)
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    if d.kind == .timer {
                        pill("Stop and review", symbol: "stop.fill")
                    } else if d.pending > 0 {
                        pill("\(d.pending) to confirm", symbol: "tray.fill")
                    } else {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(d.stage).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            Text(d.nextMark).font(.system(size: 12)).foregroundStyle(tinted ? .white.opacity(0.7) : LHB.onHeroSecondary)
                        }
                    }
                }
            }
            .padding(16)
            .frame(width: 186, height: 162, alignment: .topLeading)
        }
        .frame(width: 344, height: 162)
        .clipShape(RoundedRectangle(cornerRadius: SFWidgetSize.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch d.kind {
        case .timer: "Timer · today"
        case .noProperty: "LandlordHours"
        default: "Your REPS hours · 2026"
        }
    }

    /// The one tappable thing in the widget (a Link in production). White pill on blueprint,
    /// as on the paywall and Welcome.
    private func pill(_ t: String, symbol: String) -> some View {
        Label(t, systemImage: symbol)
            .font(.system(size: 13, weight: .semibold))
            .labelStyle(TightLabel2())
            .foregroundStyle(tinted ? .white : LHB.brand)
            .padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(tinted ? .white.opacity(0.18) : .white))
    }
}

struct TightLabel2: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon.font(.system(size: 11, weight: .bold)); configuration.title }
    }
}

/// iOS tinted / clear mode removes our background; this approximates the system's dark material.
struct SFTintedBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: SFWidgetSize.radius, style: .continuous)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .overlay(RoundedRectangle(cornerRadius: SFWidgetSize.radius, style: .continuous).fill(Color(hex: 0x10202E).opacity(0.35)))
    }
}

// MARK: - Home screen mock

struct SFHomeScreen: View {
    enum Page { case a, b }
    var page: Page
    var tinted = false

    var body: some View {
        ZStack(alignment: .top) {
            SFWallpaper()
            if tinted { Color.black.opacity(0.35).ignoresSafeArea() }
            VStack(spacing: 0) {
                switch page {
                case .a:
                    labelled("Medium · behind, 3 to confirm") { SFMediumWidget(d: .behind, tinted: tinted) }
                    HStack(spacing: 20) {
                        labelled("Small · behind") { SFSmallWidget(d: .behind, tinted: tinted) }
                        labelled("Small · timer") { SFSmallWidget(d: .timer, tinted: tinted) }
                    }
                    .padding(.top, 14)
                    iconRow.padding(.top, 22)
                case .b:
                    labelled("Medium · on pace, caught up") { SFMediumWidget(d: .onPace) }
                    HStack(spacing: 20) {
                        labelled("Small · nothing yet") { SFSmallWidget(d: .empty) }
                        labelled("Small · no property") { SFSmallWidget(d: .noProperty) }
                    }
                    .padding(.top, 14)
                    labelled("Medium · goal met") { SFMediumWidget(d: .met) }.padding(.top, 14)
                }
                Spacer(minLength: 0)
                SystemMockTag(text: tinted ? "Mock of system UI · tinted mode" : "Mock of system UI").padding(.bottom, 12)
                dock
            }
            .padding(.top, 8)
        }
    }

    private func labelled<V: View>(_ t: String, @ViewBuilder _ v: () -> V) -> some View {
        VStack(spacing: 5) {
            v()
            Text(t).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .lineLimit(1)
        }
    }

    private var iconRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(SFHomeScreen.apps.enumerated()), id: \.offset) { _, a in
                VStack(spacing: 5) {
                    if a.0 == "LandlordHours" {
                        SFAppIcon(size: 62)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(a.2.gradient)
                            .frame(width: 62, height: 62)
                            .overlay(Image(systemName: a.1).font(.system(size: 28, weight: .medium)).foregroundStyle(.white))
                            .opacity(tinted ? 0.6 : 1)
                    }
                    Text(a.0).font(.system(size: 12)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                }
                .frame(width: 86)
            }
        }
    }

    static let apps: [(String, String, Color)] = [
        ("LandlordHours", "", .clear), ("Calendar", "calendar", Color(hex: 0xE5484D)),
        ("Notes", "note.text", Color(hex: 0xE8A317)), ("Maps", "map.fill", Color(hex: 0x30A46C)),
    ]

    private var dock: some View {
        HStack(spacing: 24) {
            ForEach([("phone.fill", Color(hex: 0x30A46C)), ("safari.fill", Color(hex: 0x2F7FE0)), ("message.fill", Color(hex: 0x30A46C)), ("camera.fill", Color(hex: 0x6B7280))], id: \.0) { s in
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(s.1.gradient)
                    .frame(width: 62, height: 62)
                    .overlay(Image(systemName: s.0).font(.system(size: 26, weight: .medium)).foregroundStyle(.white))
                    .opacity(tinted ? 0.6 : 1)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }
}

// MARK: - Lock Screen accessories (vibrant: the system renders them as one white tint)

struct SFAccessoryCircular: View {
    let d: SFWidgetData
    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.16))
            let p = d.kind == .noProperty ? 0 : min(1, d.hours / d.goal)
            Circle().stroke(.white.opacity(0.28), lineWidth: 5).padding(6)
            Circle().trim(from: 0, to: p).stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(6)
            VStack(spacing: 0) {
                if d.kind == .met {
                    Image(systemName: "checkmark").font(.system(size: 20, weight: .bold))
                } else if d.kind == .noProperty {
                    Image(systemName: "plus").font(.system(size: 20, weight: .semibold))
                } else if d.kind == .timer {
                    Text("0:42").font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                } else {
                    Text(d.number).font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
                        .minimumScaleFactor(0.7)
                }
                MarkB(mono: .white).frame(width: 15, height: 15)
            }
            .foregroundStyle(.white)
        }
        .frame(width: 72, height: 72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(d.kind == .noProperty ? "Add a property" : "\(d.number) of your \(Int(d.goal)) hours")
    }
}

/// Counted-or-pending accessory: inbox count big, for people who want "what needs me".
struct SFAccessoryCircularPending: View {
    let n: Int
    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.16))
            VStack(spacing: 1) {
                Image(systemName: n == 0 ? "checkmark" : "tray.fill").font(.system(size: 13, weight: .semibold))
                Text(n == 0 ? "Done" : "\(n)").font(.system(size: n == 0 ? 13 : 22, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            .foregroundStyle(.white)
        }
        .frame(width: 72, height: 72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(n == 0 ? "Nothing to confirm" : "\(n) to confirm")
    }
}

struct SFAccessoryRectangular: View {
    let d: SFWidgetData
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                MarkB(mono: .white).frame(width: 14, height: 14)
                Text(d.kind == .timer ? "Timer" : "Your hours").font(.system(size: 13, weight: .semibold))
            }
            switch d.kind {
            case .noProperty:
                Text("Add a property").font(.system(size: 17, weight: .bold, design: .rounded))
                Text("to start the house").font(.system(size: 13)).opacity(0.75)
            case .timer:
                Text("0:42 · Pine Cabin").font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                Text("Stop it to review").font(.system(size: 13)).opacity(0.75)
            default:
                Text("\(d.number) of \(Int(d.goal))h").font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(rectLine).font(.system(size: 13)).opacity(0.75).lineLimit(1).minimumScaleFactor(0.85)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 160, height: 72, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var rectLine: String {
        switch d.kind {
        case .behind: d.pending > 0 ? "\(d.pending) to confirm" : "Behind by \(d.gap)h"
        case .onPace: "On pace"
        case .empty: "Nothing confirmed yet"
        case .met: "House finished"
        default: ""
        }
    }
}

struct SFAccessoryInline: View {
    let d: SFWidgetData
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: d.kind == .timer ? "timer" : "house.fill")
            Text(text)
        }
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
    }
    var text: String {
        switch d.kind {
        case .behind: d.pending > 0 ? "\(d.number) of 750h · \(d.pending) to confirm" : "\(d.number) of 750h"
        case .onPace: "\(d.number) of 750h · on pace"
        case .empty: "0 of 750h so far"
        case .noProperty: "Add a property"
        case .met: "750h reached"
        case .timer: "Timer 0:42 · Pine Cabin"
        }
    }
}

/// Lock Screen layout: date line (inline widget sits beside the date), clock, widget row.
struct SFLockChrome<Widgets: View, Below: View>: View {
    var inline: String? = nil
    var inlineView: AnyView? = nil
    @ViewBuilder var widgets: () -> Widgets
    @ViewBuilder var below: () -> Below

    var body: some View {
        ZStack(alignment: .top) {
            SFWallpaper()
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text("Mon 19")
                    if let inlineView { inlineView }
                }
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.top, 20)
                Text("9:41")
                    .font(.system(size: 96, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.top, -6)
                widgets().padding(.top, 2)
                below()
                Spacer(minLength: 0)
                HStack {
                    QuickButton(symbol: "flashlight.off.fill")
                    Spacer()
                    SystemMockTag()
                    Spacer()
                    QuickButton(symbol: "camera.fill")
                }
                .padding(.horizontal, 46)
                .padding(.bottom, 4)
            }
        }
    }
}

struct SFLockWidgets: View {
    var body: some View {
        SFLockChrome(inlineView: AnyView(SFAccessoryInline(d: .behind))) {
            HStack(spacing: 12) {
                SFAccessoryRectangular(d: .behind)
                SFAccessoryCircular(d: .behind)
                SFAccessoryCircularPending(n: 3)
            }
        } below: { EmptyView() }
    }
}

/// Every accessory family in every state, on the Lock Screen wallpaper, at real size.
struct SFLockStates: View {
    private let rows: [(String, SFWidgetData)] = [
        ("Behind", .behind), ("On pace", .onPace), ("Nothing yet", .empty),
        ("No property", .noProperty), ("Goal met", .met), ("Timer", .timer),
    ]
    var body: some View {
        ZStack(alignment: .top) {
            SFWallpaper()
            Color.black.opacity(0.12).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                Text("Lock Screen widgets · all states").drafting(.white, size: 11).padding(.top, 8)
                ForEach(rows, id: \.0) { r in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(r.0.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1)
                                .foregroundStyle(.white.opacity(0.85))
                            SFAccessoryInline(d: r.1).font(.system(size: 15)).scaleEffect(0.9, anchor: .leading)
                        }
                        HStack(spacing: 10) {
                            SFAccessoryRectangular(d: r.1)
                            SFAccessoryCircular(d: r.1)
                            SFAccessoryCircularPending(n: r.1.pending)
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack { Spacer(); SystemMockTag(); Spacer() }.padding(.bottom, 4)
            }
            .padding(.horizontal, 24)
        }
    }
}
