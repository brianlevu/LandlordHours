import SwiftUI
import UIKit

#if DEBUG
// MARK: - DEBUG capture boards for the 2.0 surfaces (compiled out of Release)
//
//   -LHSurfaceBoard <name> -LHColorScheme light|dark [-LHTypeSize xxl|ax3]
//
// Boards draw the PRODUCTION views (WidgetSurfaceViews.swift, LHToast, LandlordHoursSiriSnippet,
// the real LaunchScreen.storyboard) on a stand-in wallpaper. WidgetKit can't be hosted in an app,
// so the Home/Lock Screen chrome, the accessory backing and the tinted-mode material are mocks;
// every board that draws them carries a "Mock of system UI" tag. Widget sizes for a 402pt-wide
// iPhone (HIG table): small 162, medium 344×162, circular 72, rectangular 160×72.
//
// Real-shell toasts: `-LHDebugToast saveError|loadError|propertyAdded|timerDiscarded|undo`
// (ContentView). Notifications: `-LHDebugPostSampleNotifications` (SurfaceNotificationSamples).

struct SurfaceBoardLaunch {
    let name: String
    let scheme: ColorScheme
    let typeSize: DynamicTypeSize?

    static let current: SurfaceBoardLaunch? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LHSurfaceBoard"), args.indices.contains(i + 1) else { return nil }
        func value(_ flag: String) -> String? {
            guard let j = args.firstIndex(of: flag), args.indices.contains(j + 1) else { return nil }
            return args[j + 1]
        }
        let scheme: ColorScheme = value("-LHColorScheme") == "dark" ? .dark : .light
        let size: DynamicTypeSize?
        switch value("-LHTypeSize") {
        case "xxl": size = .xxxLarge
        case "ax3": size = .accessibility3
        default: size = nil
        }
        return SurfaceBoardLaunch(name: args[i + 1], scheme: scheme, typeSize: size)
    }()
}

/// Frozen sample snapshots (the sandbox's states), all at 9:41 with a 0:42 timer.
enum SurfaceSamples {
    static let now = Date(timeIntervalSince1970: 1_792_400_000)

    static func snapshot(
        properties: Int = 2, hours: Double, goal: WidgetSurfaceSnapshot.Goal = .reps750, required: Double = 600,
        pending: Int, timer: Bool = false, focusName: String? = nil
    ) -> WidgetSurfaceSnapshot {
        let progress = HouseProgress(hours: properties == 0 ? 0 : hours, goal: .reps750)
        return WidgetSurfaceSnapshot(
            updatedAt: now, taxYear: 2026, propertyCount: properties, hours: hours, goal: goal,
            goalHours: goal == .reps750 ? 750 : (goal == .mp500 ? 500 : 100), requiredHoursToDate: required,
            pendingCount: pending, timerStart: timer ? now.addingTimeInterval(-42 * 60) : nil,
            timerPropertyName: timer ? "Pine Cabin" : nil,
            houseKeyframe: progress.keyframe.rawValue, stageTitle: progress.stage.spokenName,
            nextStepLabel: progress.nextMilestoneLabel,
            focusName: focusName
        )
    }

    /// 2.1: several rentals, Today focused on one with its own 100-hour target.
    static let focused = snapshot(properties: 3, hours: 12, goal: .mp100, required: 81, pending: 0, focusName: "Santa Ray Ave")
    static let focusedMet = snapshot(properties: 8, hours: 112, goal: .mp100, required: 81, pending: 2, focusName: "Lake House")

    static let behind = snapshot(hours: 212, pending: 3)
    static let onPace = snapshot(hours: 640, pending: 0)
    static let empty = snapshot(properties: 1, hours: 0, required: 300, pending: 0)
    static let noProperty = snapshot(properties: 0, hours: 0, required: 0, pending: 0)
    static let met = snapshot(hours: 768, required: 700, pending: 1)
    static let timer = snapshot(hours: 212, pending: 3, timer: true)
}

struct SurfaceCaptureRoot: View {
    let launch: SurfaceBoardLaunch

    var body: some View {
        board
            .environment(\.widgetFrozenNow, SurfaceSamples.now)
            .environment(\.widgetHarness, true)
            .modifier(OptionalTypeSize(size: launch.typeSize))
    }

    @ViewBuilder private var board: some View {
        switch launch.name {
        case "widgets-home-a": WallpaperBoard(scheme: launch.scheme) { HomeWidgetsA() }
        case "widgets-home-b": WallpaperBoard(scheme: launch.scheme) { HomeWidgetsB() }
        case "widgets-home-focus": WallpaperBoard(scheme: launch.scheme) { HomeWidgetsFocus() }
        case "widgets-home-c": WallpaperBoard(scheme: launch.scheme) { HomeWidgetsC() }
        case "widgets-tinted": WallpaperBoard(scheme: launch.scheme, dim: true) { HomeWidgetsA(look: .accented) }
        case "widgets-lock": WallpaperBoard(scheme: launch.scheme) { LockStatesBoard() }
        case "launch-storyboard": LaunchStoryboardView().ignoresSafeArea().preferredColorScheme(launch.scheme)
            .onAppear { LaunchStatusBarWindow.show() }
        case "siri": SiriBoard().preferredColorScheme(launch.scheme)
        case "toast-board": ToastBoard().preferredColorScheme(launch.scheme)
        default: Text("Unknown board \(launch.name)")
        }
    }
}

private struct OptionalTypeSize: ViewModifier {
    let size: DynamicTypeSize?
    func body(content: Content) -> some View {
        if let size { content.dynamicTypeSize(size) } else { content }
    }
}

// MARK: Wallpaper + mock tag

private struct WallpaperBoard<Content: View>: View {
    let scheme: ColorScheme
    var dim = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            wallpaper.ignoresSafeArea()
            if dim { Color.black.opacity(0.35).ignoresSafeArea() }
            VStack(spacing: 0) {
                content()
                Spacer(minLength: 0)
                MockTag(text: dim ? "Mock of system UI · tinted mode" : "Mock of system UI").padding(.bottom, 12)
            }
            .padding(.top, 8)
        }
        // The system draws a white status bar on a wallpaper.
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var wallpaper: some View {
        let light: [Color] = [Color(brandHex: "3E6A96"), Color(brandHex: "4D79A3"), Color(brandHex: "5E86AA"),
                              Color(brandHex: "335E88"), Color(brandHex: "5E7476"), Color(brandHex: "7D6C55"),
                              Color(brandHex: "24435A"), Color(brandHex: "544838"), Color(brandHex: "6E553D")]
        let dark: [Color] = [Color(brandHex: "1C2C3E"), Color(brandHex: "24384C"), Color(brandHex: "2E4152"),
                             Color(brandHex: "14222F"), Color(brandHex: "2A3638"), Color(brandHex: "3B3428"),
                             Color(brandHex: "0C141B"), Color(brandHex: "231F18"), Color(brandHex: "34291D")]
        if #available(iOS 18.0, *) {
            MeshGradient(width: 3, height: 3,
                         points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.6, 0.42], [1, 0.5], [0, 1], [0.45, 1], [1, 1]],
                         colors: scheme == .dark ? dark : light)
        } else {
            LinearGradient(colors: scheme == .dark ? dark : light, startPoint: .top, endPoint: .bottom)
        }
    }
}

private struct MockTag: View {
    var text = "Mock of system UI"
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced)).textCase(.uppercase).tracking(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(.black.opacity(0.55)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }
}

// MARK: Home Screen widgets

/// A Home Screen widget at its real size: blueprint paper (or the tinted material), clipped.
private struct HomeTile<Content: View>: View {
    let size: CGSize
    var look: WidgetLook = .fullColor
    let caption: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                if look == .accented {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(brandHex: "10202E").opacity(0.35)))
                } else {
                    WidgetBlueprintPaper()
                }
                content()
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text(caption).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1).lineLimit(1)
        }
    }
}

private let small = CGSize(width: 162, height: 162)
private let medium = CGSize(width: 344, height: 162)

private struct HomeWidgetsA: View {
    var look: WidgetLook = .fullColor
    var body: some View {
        VStack(spacing: 14) {
            HomeTile(size: medium, look: look, caption: "Medium · behind, 3 to confirm") {
                WidgetMediumView(display: .init(snapshot: SurfaceSamples.behind), look: look)
            }
            HStack(spacing: 20) {
                HomeTile(size: small, look: look, caption: "Small · behind") { WidgetSmallView(display: .init(snapshot: SurfaceSamples.behind), look: look) }
                HomeTile(size: small, look: look, caption: "Small · timer") { WidgetSmallView(display: .init(snapshot: SurfaceSamples.timer), look: look) }
            }
            HomeTile(size: medium, look: look, caption: "Medium · on pace, caught up") {
                WidgetMediumView(display: .init(snapshot: SurfaceSamples.onPace), look: look)
            }
        }
    }
}

/// 2.1: the widget follows Today's focus (one rental of several, named).
private struct HomeWidgetsFocus: View {
    var body: some View {
        VStack(spacing: 14) {
            HomeTile(size: medium, caption: "Medium · focused rental, behind") { WidgetMediumView(display: .init(snapshot: SurfaceSamples.focused)) }
            HStack(spacing: 20) {
                HomeTile(size: small, caption: "Small · focused rental") { WidgetSmallView(display: .init(snapshot: SurfaceSamples.focused)) }
                HomeTile(size: small, caption: "Small · focused, 100 reached") { WidgetSmallView(display: .init(snapshot: SurfaceSamples.focusedMet)) }
            }
            HomeTile(size: medium, caption: "Medium · focused, 2 to confirm") { WidgetMediumView(display: .init(snapshot: SurfaceSamples.focusedMet)) }
        }
    }
}

private struct HomeWidgetsB: View {
    var body: some View {
        VStack(spacing: 14) {
            HomeTile(size: medium, caption: "Medium · on pace, caught up") { WidgetMediumView(display: .init(snapshot: SurfaceSamples.onPace)) }
            HStack(spacing: 20) {
                HomeTile(size: small, caption: "Small · nothing yet") { WidgetSmallView(display: .init(snapshot: SurfaceSamples.empty)) }
                HomeTile(size: small, caption: "Small · no property") { WidgetSmallView(display: .init(snapshot: SurfaceSamples.noProperty)) }
            }
            HomeTile(size: medium, caption: "Medium · goal met") { WidgetMediumView(display: .init(snapshot: SurfaceSamples.met)) }
        }
    }
}

private struct HomeWidgetsC: View {
    var body: some View {
        VStack(spacing: 14) {
            HomeTile(size: medium, caption: "Medium · timer") { WidgetMediumView(display: .init(snapshot: SurfaceSamples.timer)) }
            HomeTile(size: medium, caption: "Medium · no property") { WidgetMediumView(display: .init(snapshot: SurfaceSamples.noProperty)) }
            HStack(spacing: 20) {
                HomeTile(size: small, caption: "Small · on pace") { WidgetSmallView(display: .init(snapshot: SurfaceSamples.onPace)) }
                HomeTile(size: small, caption: "Small · goal met") { WidgetSmallView(display: .init(snapshot: SurfaceSamples.met)) }
            }
        }
    }
}

// MARK: Lock Screen

private struct LockStatesBoard: View {
    private let rows: [(String, WidgetSurfaceSnapshot)] = [
        ("Behind", SurfaceSamples.behind), ("On pace", SurfaceSamples.onPace), ("Nothing yet", SurfaceSamples.empty),
        ("No property", SurfaceSamples.noProperty), ("Goal met", SurfaceSamples.met), ("Timer", SurfaceSamples.timer),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LOCK SCREEN WIDGETS · ALL STATES")
                .font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(1.3).foregroundStyle(.white)
            ForEach(rows, id: \.0) { row in
                let d = WidgetSurfaceDisplay(snapshot: row.1)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(row.0.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1)
                            .foregroundStyle(.white.opacity(0.85))
                        WidgetInlineView(display: d).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    }
                    HStack(spacing: 10) {
                        WidgetRectangularView(display: d).frame(width: 160, height: 72)
                        WidgetCircularHoursView(display: d).frame(width: 72, height: 72)
                        WidgetCircularPendingView(display: d).frame(width: 72, height: 72)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Launch (the real storyboard)

private struct LaunchStoryboardView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIStoryboard(name: "LaunchScreen", bundle: .main).instantiateInitialViewController() ?? UIViewController()
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

// MARK: Siri

private struct SiriBoard: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let display = WidgetSurfaceDisplay(snapshot: SurfaceSamples.behind)
        ScrollView {
            VStack(spacing: 10) {
                Text("You have 212 of your 750 hours for 2026. You’re 388 hours behind pace, and 3 visits are waiting for you to confirm.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(scheme == .dark ? Color.white : Color(brandHex: BrandHex.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.regularMaterial))
                LandlordHoursSiriSnippet(display: display)
                MockTag(text: "Mock of system UI · Siri").padding(.top, 8)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
        .background(Color(brandHex: scheme == .dark ? BrandHex.darkCanvas : BrandHex.canvas).ignoresSafeArea())
    }
}

// MARK: Toasts

private struct ToastBoard: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Toasts").lhDisplayFont(.largeTitle).foregroundStyle(colors.textPrimary)
                header("Undo", colors)
                LHToast(spec: .init(kind: .neutral, message: "Marked not rental work", actionTitle: "Undo"))
                LHToast(spec: .init(kind: .neutral, message: "Timer discarded", actionTitle: "Undo"))
                header("Saved", colors)
                LHToast(spec: .init(kind: .success, message: "Added Oak Street Duplex"))
                LHToast(spec: .init(kind: .success, message: "Logged 2h at Pine Cabin", actionTitle: "Undo"))
                header("Something went wrong", colors)
                LHToast(spec: .init(kind: .problem, message: AppViewModel.saveFailureMessage, actionTitle: "Retry"))
                LHToast(spec: .init(kind: .problem, message: AppViewModel.loadFailureMessage, actionTitle: "Help"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(colors.background.ignoresSafeArea())
    }

    private func header(_ text: String, _ colors: AdaptiveColors) -> some View {
        Text(text.uppercased())
            .font(.system(.caption, design: .monospaced).weight(.medium)).tracking(1.3)
            .foregroundStyle(colors.textSecondary)
            .padding(.top, 8)
    }
}
#endif
