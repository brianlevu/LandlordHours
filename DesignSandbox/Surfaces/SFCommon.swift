// Surfaces lane — the 2.0 surfaces that had no design: widgets, launch, toasts, notifications,
// Siri/Shortcuts. Sandbox only, mock data. Launch: -LHScreen sf-<name> -appearance light|dark [-LHType xxl]
// System chrome drawn here (home screen, lock screen, notification platters, Shortcuts) is a
// MOCK OF SYSTEM UI; every frame that contains it says so.
import SwiftUI

// MARK: - Host

struct SFHost: View {
    let name: String
    private var scheme: ColorScheme {
        UserDefaults.standard.string(forKey: "appearance") == "dark" ? .dark : .light
    }

    var body: some View {
        content
            .tint(LHB.action)
            .modifier(TypeSizeOverride())
            .onAppear { S2Font.register() }
    }

    /// System surfaces (home, lock, Siri over blur) keep a white status bar like iOS does on a
    /// wallpaper; the content inside still follows the requested appearance.
    private func onWallpaper<V: View>(_ v: V) -> some View {
        v.environment(\.colorScheme, scheme).preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        switch name {
        // 1. Widgets
        case "sf-home-a": onWallpaper(SFHomeScreen(page: .a))
        case "sf-home-b": onWallpaper(SFHomeScreen(page: .b))
        case "sf-home-tinted": onWallpaper(SFHomeScreen(page: .a, tinted: true))
        case "sf-lock-widgets": onWallpaper(SFLockWidgets())
        case "sf-lock-states": onWallpaper(SFLockStates())
        // 2. Launch
        case "sf-launch": SFLaunch().preferredColorScheme(.dark).environment(\.colorScheme, scheme)
        case "sf-launch-to-today": SFLaunchToToday(progress: 0.55).preferredColorScheme(scheme)
        case "sf-launch-to-welcome": SFLaunchToWelcome(progress: 0.5).preferredColorScheme(.dark).environment(\.colorScheme, scheme)
        // 3. Toasts
        case "sf-toast-undo": SFToastFrame(kind: .undo).preferredColorScheme(scheme)
        case "sf-toast-save-error": SFToastFrame(kind: .saveError).preferredColorScheme(scheme)
        case "sf-toast-load-error": SFToastFrame(kind: .loadError).preferredColorScheme(scheme)
        case "sf-toast-property-added": SFToastFrame(kind: .propertyAdded).preferredColorScheme(scheme)
        case "sf-toast-board": SFToastBoard().preferredColorScheme(scheme)
        // 4. Notifications
        case "sf-notif-list": onWallpaper(SFNotificationLock(set: .main))
        case "sf-notif-followups": onWallpaper(SFNotificationLock(set: .followUps))
        case "sf-notif-expanded": onWallpaper(SFNotificationExpanded())
        // 5. Siri / Shortcuts
        case "sf-shortcuts": SFShortcutsPage().preferredColorScheme(scheme)
        case "sf-siri-snippet": SFSiriSnippetFrame().preferredColorScheme(scheme)
        default:
            List(SFHost.all, id: \.self) { Text($0) }
        }
    }

    static let all = [
        "sf-home-a", "sf-home-b", "sf-home-tinted", "sf-lock-widgets", "sf-lock-states",
        "sf-launch", "sf-launch-to-today", "sf-launch-to-welcome",
        "sf-toast-undo", "sf-toast-save-error", "sf-toast-load-error", "sf-toast-property-added", "sf-toast-board",
        "sf-notif-list", "sf-notif-followups", "sf-notif-expanded",
        "sf-shortcuts", "sf-siri-snippet",
    ]
}

// MARK: - Mark B (brand/logo/mark-b.svg, drawn in its 1024 space)

struct MarkB: View {
    /// nil = colour; otherwise every part in one tint (the mono template).
    var mono: Color? = nil

    var body: some View {
        Canvas { c, s in
            let k = s.width / 1024
            c.scaleBy(x: k, y: k)
            c.translateBy(x: 10, y: -11.5)
            let draft = mono ?? LHB.draftingHero
            let plaster = mono ?? LHB.plaster
            let terra = mono ?? LHB.terracotta
            let timber = mono ?? LHB.timber
            func line(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat, _ col: Color) {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                c.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
            }
            line(.init(x: 512, y: 232), .init(x: 836, y: 486), 26, draft)
            line(.init(x: 770, y: 436), .init(x: 770, y: 700), 26, draft)
            c.stroke(Path(roundedRect: CGRect(x: 588, y: 540, width: 120, height: 96), cornerRadius: 12), with: .color(draft), lineWidth: 26)
            c.fill(Path(roundedRect: CGRect(x: 222, y: 808, width: 580, height: 40), cornerRadius: 10), with: .color(plaster))
            c.fill(Path(CGRect(x: 250, y: 470, width: 262, height: 342)), with: .color(plaster))
            c.fill(Path(CGRect(x: 512, y: 690, width: 258, height: 122)), with: .color(plaster))
            line(.init(x: 512, y: 232), .init(x: 188, y: 486), 66, terra)
            var door = Path()
            door.move(to: .init(x: 382, y: 812))
            door.addLine(to: .init(x: 382, y: 683))
            door.addArc(center: .init(x: 429, y: 683), radius: 47, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            door.addLine(to: .init(x: 476, y: 812))
            door.closeSubpath()
            c.fill(door, with: .color(timber))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The real app icon (mark B on blueprint), as the system shows it.
struct SFAppIcon: View {
    var size: CGFloat = 38
    var body: some View {
        Image("lh_icon_b").resizable().interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

// MARK: - Wallpaper (neutral photo-like, so widgets are judged off-brand, not on blueprint)

struct SFWallpaper: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        // A dusk-blue/sand photo stand-in, mid-dark like most real wallpapers, so the system's
        // white Lock Screen text and our widgets are judged on a realistic background.
        let light: [Color] = [
            Color(hex: 0x3E6A96), Color(hex: 0x4D79A3), Color(hex: 0x5E86AA),
            Color(hex: 0x335E88), Color(hex: 0x5E7476), Color(hex: 0x7D6C55),
            Color(hex: 0x24435A), Color(hex: 0x544838), Color(hex: 0x6E553D),
        ]
        let dark: [Color] = [
            Color(hex: 0x1C2C3E), Color(hex: 0x24384C), Color(hex: 0x2E4152),
            Color(hex: 0x14222F), Color(hex: 0x2A3638), Color(hex: 0x3B3428),
            Color(hex: 0x0C141B), Color(hex: 0x231F18), Color(hex: 0x34291D),
        ]
        MeshGradient(width: 3, height: 3,
                     points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.6, 0.42], [1, 0.5], [0, 1], [0.45, 1], [1, 1]],
                     colors: scheme == .dark ? dark : light)
        .ignoresSafeArea()
    }
}

/// "MOCK OF SYSTEM UI" tag — every frame that draws Apple chrome carries it.
struct SystemMockTag: View {
    var text = "Mock of system UI"
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced)).textCase(.uppercase).tracking(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(.black.opacity(0.55)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .accessibilityHidden(true)
    }
}

// MARK: - The one toast

/// One toast system for the whole app (Inbox, Today, Properties, save errors). It is the Inbox
/// toast anatomy (glyph · message · one action) on the Today undo-toast glass, with a rounded
/// rectangle so a second line wraps cleanly instead of fattening a capsule.
struct SFToastSpec: Equatable {
    enum Kind { case success, neutral, problem }
    var kind: Kind
    var message: String
    var action: String? = nil

    var symbol: String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .neutral: "arrow.uturn.backward.circle.fill"
        case .problem: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch kind {
        case .success: LHB.positive
        case .neutral: LHB.textSecondary
        case .problem: LHB.caution
        }
    }
}

struct SFToast: View {
    let spec: SFToastSpec
    var onAction: () -> Void = {}
    @Environment(\.accessibilityReduceTransparency) private var solid
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: spec.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(spec.tint)
                .accessibilityHidden(true)
            Text(spec.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LHB.textPrimary)
                .lineLimit(dts.isAccessibilitySize ? 4 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let a = spec.action {
                Button(a, action: onAction)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LHB.action)
                    .frame(minWidth: 44, minHeight: 44)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("toast.action")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, spec.action == nil ? 16 : 8)
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .background { if solid { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(LHB.card) } }
        .glassEffect(solid ? .identity : .regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("toast")
    }
}
