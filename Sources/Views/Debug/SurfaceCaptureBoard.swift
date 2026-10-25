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
        pending: Int, timer: Bool = false
    ) -> WidgetSurfaceSnapshot {
        return WidgetSurfaceSnapshot(
            updatedAt: now, taxYear: 2026, propertyCount: properties, hours: hours, goal: goal,
            goalHours: goal == .reps750 ? 750 : (goal == .mp500 ? 500 : 100), requiredHoursToDate: required,
            pendingCount: pending, timerStart: timer ? now.addingTimeInterval(-42 * 60) : nil,
            timerPropertyName: timer ? "Pine Cabin" : nil,
            houseKeyframe: "", stageTitle: "", nextStepLabel: "",
            houseStage: WidgetSamples.stage(hours, goal == .reps750 ? 750 : (goal == .mp500 ? 500 : 100)),
            loggedToday: pending > 0, paceReady: true
        )
    }

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
        // Home Screen widget frames (all families, states, appearances and type sizes): package I,
        // Sources/Widget/WidgetCaptureBoards.swift.
        case "widget-export": WidgetExportBoard()
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
