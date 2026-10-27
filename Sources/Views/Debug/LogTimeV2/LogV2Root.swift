import SwiftUI

#if DEBUG
// MARK: - Log time v2 design sandbox: launch + root (DESIGN ONLY)
//
// The sheet is presented the production way (§1.20 focused: opaque `.large` sheet on
// backgroundSecondary with the system push-back) over a stand-in Today backdrop.

struct LogV2Launch {
    let direction: LogV2Direction
    let state: String
    let play: String?
    let free: Bool
    /// `-LHLogV2R1`: direction A as it was in round 1 (for comparison).
    let r1: Bool
    /// `-LHLogV2Variant beam|object|r2` (A only; default beam, round 3).
    let variant: LogV2Variant
    let scheme: ColorScheme
    let typeSize: DynamicTypeSize?

    static let current: LogV2Launch? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LHLogV2"), args.indices.contains(i + 1),
              let dir = LogV2Direction(rawValue: args[i + 1]) else { return nil }
        func value(_ flag: String) -> String? {
            guard let j = args.firstIndex(of: flag), args.indices.contains(j + 1) else { return nil }
            return args[j + 1]
        }
        let size: DynamicTypeSize?
        switch value("-LHTypeSize") {
        case "xxl": size = .xxxLarge
        case "ax3": size = .accessibility3
        default: size = nil
        }
        return LogV2Launch(direction: dir, state: value("-LHLogV2State") ?? "entry", play: value("-LHLogV2Play"),
                           free: args.contains("-LHLogV2Free"), r1: args.contains("-LHLogV2R1"),
                           variant: LogV2Variant(rawValue: value("-LHLogV2Variant") ?? "beam") ?? .beam,
                           scheme: value("-LHColorScheme") == "dark" ? .dark : .light, typeSize: size)
    }()
}

struct LogV2Root: View {
    let launch: LogV2Launch
    @StateObject private var model: LogV2Model
    @State private var showSheet = true

    init(launch: LogV2Launch) {
        self.launch = launch
        let m = LogV2Model(direction: launch.direction, isFree: launch.free)
        m.r3 = launch.direction == .a && !launch.r1 && launch.variant != .r2
        m.apply(state: launch.state)
        _model = StateObject(wrappedValue: m)
    }

    var body: some View {
        backdrop
            .sheet(isPresented: $showSheet, onDismiss: { model.sheetDismissed() }) {
                sheet
                    .lhSheetPresentation(.focused)
                    .modifier(LogV2PageBackground(enabled: launch.direction == .a && !launch.r1, scheme: launch.scheme))
                    .preferredColorScheme(launch.scheme)
                    .modifier(LogV2TypeSize(size: launch.typeSize))
            }
            .overlay(alignment: .bottom) {
                if model.stage == .logged, let toast = model.toast {
                    LogV2LoggedToast(text: toast)
                        .padding(.horizontal, LHMetrics.gutter)
                        .padding(.bottom, 24)
                        .transition(.opacity.combined(with: .offset(y: 24)))
                }
            }
            .onChange(of: model.stage) { _, stage in
                if stage == .closing || stage == .logged { showSheet = false }
                if stage == .entry && !showSheet { showSheet = true }
            }
            .onAppear { if model.stage == .logged { showSheet = false } }
            .task {
                if let play = launch.play { await model.play(play) }
            }
            .preferredColorScheme(launch.scheme)
            .modifier(LogV2TypeSize(size: launch.typeSize))
    }

    @ViewBuilder private var sheet: some View {
        switch launch.direction {
        case .a:
            if launch.r1 { LogV2SheetA(model: model) }
            else if launch.variant == .r2 { LogV2SheetA2(model: model) }
            else { LogV2SheetR3(model: model, variant: launch.variant) }
        case .b: LogV2SheetB(model: model)
        }
    }

    /// Stand-in for Today behind the sheet: the canvas, the Fraunces title and a quiet row group.
    private var backdrop: some View {
        LogV2Backdrop(onTap: { model.reset(); showSheet = true })
    }
}

/// r2: the A sheet on the tinted page colour (proposed `LHSheetPresentation.focused` on `background`).
struct LogV2PageBackground: ViewModifier {
    let enabled: Bool
    let scheme: ColorScheme
    func body(content: Content) -> some View {
        if enabled { content.presentationBackground(AdaptiveColors(colorScheme: scheme).background) } else { content }
    }
}

struct LogV2TypeSize: ViewModifier {
    let size: DynamicTypeSize?
    func body(content: Content) -> some View {
        if let size { content.dynamicTypeSize(size) } else { content }
    }
}

struct LogV2Backdrop: View {
    var onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LHMetrics.sectionGap) {
                LHScreenTitle("Today", subtitle: "Pine Cabin")
                LHRowGroup {
                    LHRow.Browse(title: "Log time", meta: "Design sandbox · tap to open again", systemImage: "plus", action: onTap)
                }
                .padding(.horizontal, LHMetrics.gutter)
            }
            .padding(.top, 12)
        }
        .background(colors.background.ignoresSafeArea())
    }
}
#endif
