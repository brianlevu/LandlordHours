import SwiftUI

// MARK: - The Duo's root, fold reader and container (TwoPaneHooks `root`, `division`, `arrangement`)
//
// `DuoDoorRoot` wraps the whole layout once. It owns the door clock (hook closures cannot hold
// state), listens to the hinge (`.unfoldDoor`) and hands the clock to the overlays through
// `\.unfoldClock`. The overlays read it there and draw nothing without it, so a layout installed
// without this root can never crash or show a shut door.

struct DuoDoorRoot: View {
    let content: AnyView
    let split: LayoutSplit

    @StateObject private var clock = UnfoldClock()

    private var posture: FoldPosture { DuoHooks.posture(split) }

    private var activeClock: UnfoldClock {
        #if DEBUG
        return DuoDoorCapture.heldClock ?? clock
        #else
        return clock
        #endif
    }

    var body: some View {
        content
            .environment(\.unfoldClock, activeClock)
            .unfoldDoor(activeClock, posture: posture)
            #if DEBUG
            .task { await DuoDoorCapture.startIfRequested() }
            #endif
    }
}

enum DuoHooks {
    /// The window's fold, from the split `TwoPaneLayout` resolved (no division on iPad).
    static func posture(_ split: LayoutSplit) -> FoldPosture {
        FoldPosture.resolve(division: split.isDivision ? split.gap : nil, in: split.size)
    }

    /// The active `.division` region, frame plus margins, in the root's space (iOS 27.1). Runs in the
    /// root's geometry transform: cheap and free of side effects.
    static func division(_ proxy: GeometryProxy) -> PaneDivision? {
        guard #available(iOS 27.1, *) else { return nil }
        guard let region = proxy.reservedRegions(kind: .division).first(where: \.isActive) else { return nil }
        let f = region.frame, m = region.margins
        return PaneDivision(rect: CGRect(x: f.minX - m.leading, y: f.minY - m.top,
                                         width: f.width + m.leading + m.trailing,
                                         height: f.height + m.top + m.bottom))
    }

    /// The held-open Duo's container: `ArrangementView` split along the fold (iOS 27.1). The house is
    /// the primary; which side the system renders the primary on is must-prove 15 (the house must be
    /// leading). Below 27.1 the layout's own `HStack` stands, so this is never asked for there.
    @MainActor static func arrangement(_ split: LayoutSplit, house: AnyView, work: AnyView) -> AnyView {
        if #available(iOS 27.1, *) {
            return AnyView(
                ArrangementView { house } secondary: { work }
                    .arrangementViewStyle(.split.axes(.horizontal))
                    .splitArrangementLayoutRatio(0.5)
            )
        }
        return AnyView(HStack(spacing: 0) { house; work })
    }
}

// MARK: - The clock in the environment

private struct UnfoldClockKey: EnvironmentKey {
    static let defaultValue: UnfoldClock? = nil
}

extension EnvironmentValues {
    /// The door clock `DuoDoorRoot` shares with the door leaf and the pane light (nil without it).
    var unfoldClock: UnfoldClock? {
        get { self[UnfoldClockKey.self] }
        set { self[UnfoldClockKey.self] = newValue }
    }
}

/// The hero overlay: the door leaf on a fold, nothing elsewhere.
struct DuoDoorOverlay: View {
    let context: TwoPaneHeroContext
    @Environment(\.unfoldClock) private var clock

    var body: some View {
        if let clock, let stage = context.stage, DuoHooks.posture(context.split).hostsDoor {
            DuoFrontDoor(stage: stage, side: context.side, clock: clock)
        }
    }
}

/// The work overlay: the light that wipes in from the fold's edge, nothing elsewhere.
struct DuoPaneLightOverlay: View {
    let split: LayoutSplit
    @Environment(\.unfoldClock) private var clock
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let clock, let edge = DuoHooks.posture(split).workPaneFoldEdge {
            UnfoldLightOverlay(clock: clock, edge: edge, veil: DoorArt.veil(dark: colorScheme == .dark))
        }
    }
}
