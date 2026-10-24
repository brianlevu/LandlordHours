import SwiftUI

#if DEBUG
// MARK: - Retired DEBUG mocks (plan package C)
//
// The step-0 mocks (`Debug/DirCraft`, `Debug/DirA`, `Debug/StdProto`, `Debug/HomeProto`) are
// deleted now that the crafted Today ships on real data. `LandlordHoursAppEntry.swift` (package A)
// still names their launch types, so these stand-ins keep it compiling: every `current` is nil,
// so the normal app root always runs. Package A deletes the branches (and this file) in cleanup.
//
// Captures that used `-LHDirection CRAFT` now run the real Today with `-LHCraftSeed`,
// `-LHCraftFocus`, `-LHCraftWindows`, `-LHCraftFirstHour` and `-LHCraftScroll`
// (`Today/TodayDebugSeed.swift`).

struct CraftLaunch: Equatable { static let current: CraftLaunch? = nil }
struct DirALaunch: Equatable { static let current: DirALaunch? = nil }
struct StdProtoLaunch: Equatable { static let current: StdProtoLaunch? = nil }
struct HomeProtoLaunch: Equatable { static let current: HomeProtoLaunch? = nil }

struct DirCraftRoot: View {
    let launch: CraftLaunch
    var body: some View { EmptyView() }
}

struct DirARoot: View {
    let launch: DirALaunch
    var body: some View { EmptyView() }
}

struct StdProtoRoot: View {
    let launch: StdProtoLaunch
    var body: some View { EmptyView() }
}

struct HomeProtoRoot: View {
    let config: HomeProtoLaunch
    var body: some View { EmptyView() }
}
#endif
