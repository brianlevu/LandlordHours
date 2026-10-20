// LHDesignSandbox — a throwaway SwiftUI design sandbox for LandlordHours 2.0.
// Launch args:  -screen <id>   -appearance light|dark
import SwiftUI

enum SandboxScreen: String, CaseIterable, Identifiable {
    case todayBehind = "today-behind"
    case todayOnPace = "today-onpace"
    case todayOnPaceScrolled = "today-onpace-scrolled"
    case inbox
    case detail
    case onbWelcome = "onb-welcome"
    case onbProperty = "onb-property"
    case onbCalendar = "onb-calendar"
    case onbLocation = "onb-location"
    case lockscreen
    case share
    case records
    case report
    case export
    case paywall
    case locked
    case settings
    case emptyToday = "empty-today"
    case emptyInbox = "empty-inbox"
    case conceptToday = "concept-today"
    case conceptConfirm = "concept-confirm"
    case conceptTap = "concept-tap"
    case conceptTap500 = "concept-tap-500"
    case conceptMilestone = "concept-milestone"
    case conceptWelcome = "concept-welcome"
    case conceptLockscreen = "concept-lockscreen"
    case conceptEmpty = "concept-empty"
    case conceptBackfill = "concept-backfill"

    var id: String { rawValue }

    var scenario: Scenario {
        switch self {
        case .todayOnPace, .todayOnPaceScrolled: .onPace
        case .emptyToday, .conceptEmpty: .empty
        case .conceptConfirm, .conceptTap: .conceptConfirm
        case .conceptTap500: .nearMilestone
        case .conceptMilestone: .milestone
        case .emptyInbox: .emptyInbox
        default: .behind
        }
    }
}

@main
struct LHDesignSandboxApp: App {
    private let screen: SandboxScreen?
    private let scheme: ColorScheme?
    @State private var store: MockStore

    init() {
        let d = UserDefaults.standard
        let s = d.string(forKey: "screen").flatMap(SandboxScreen.init(rawValue:))
        screen = s
        switch d.string(forKey: "appearance") {
        case "dark": scheme = .dark
        case "light": scheme = .light
        default: scheme = nil
        }
        _store = State(initialValue: MockStore(scenario: s?.scenario ?? .behind))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let s2 = S2Route.requested, s2.hasPrefix("sf-") {
                    SFHost(name: s2)
                } else if let s2 = S2Route.requested {
                    // Screens2 lane (DesignSandbox/Screens2): -LHScreen <name>
                    S2Host(name: s2)
                } else if let screen {
                    ScreenHost(screen: screen)
                } else {
                    GalleryView()
                }
            }
            .environment(store)
            .overlay(alignment: .topLeading) {
                // Screen recordings only: keep the compositor producing frames so simctl's
                // variable-rate video keeps wall-clock time through static moments.
                if UserDefaults.standard.bool(forKey: "recording") { FramePump() }
            }
            .tint(LH.action)
            .environment(\.requestedScheme, scheme)
            .preferredColorScheme(S2Route.requested != nil ? nil : screen == .paywall || (LHConcept.current == .blueprint && [.conceptWelcome, .conceptMilestone, .conceptBackfill].contains(screen)) ? .dark : scheme)
        }
    }
}

struct ScreenHost: View {
    let screen: SandboxScreen

    var body: some View {
        switch screen {
        case .todayBehind, .todayOnPace, .emptyToday:
            RootTabs(initial: .today)
        case .todayOnPaceScrolled:
            RootTabs(initial: .today, scrollToMetrics: true)
        case .inbox, .emptyInbox:
            RootTabs(initial: .inbox)
        case .detail:
            RootTabs(initial: .inbox, openDetail: "plumber")
        case .records:
            RootTabs(initial: .records)
        case .settings:
            RootTabs(initial: .today, openSettings: true)
        case .onbWelcome: OnboardingWelcome()
        case .onbProperty: OnboardingProperty()
        case .onbCalendar: OnboardingCalendar()
        case .onbLocation: OnboardingLocation()
        case .lockscreen: LockScreenMock()
        case .share: ShareReceiptHost()
        case .report: NavigationStack { ReportView() }
        case .export: NavigationStack { ExportView(locked: false) }
        case .locked: NavigationStack { ExportView(locked: true) }
        case .paywall: PaywallView()
        case .conceptToday, .conceptEmpty: ConceptTodayView()
        case .conceptConfirm: ConceptTodayView(autoConfirm: true)
        case .conceptTap, .conceptTap500: ConceptTodayView()
        case .conceptMilestone: BlueprintMilestone()
        case .conceptWelcome: BlueprintWelcome()
        case .conceptLockscreen: LockScreenMock()
        case .conceptBackfill: BlueprintBackfill()
        }
    }
}

/// Default (no launch arg): browse every screen.
struct GalleryView: View {
    @State private var open: SandboxScreen?
    var body: some View {
        NavigationStack {
            List(SandboxScreen.allCases) { s in
                Button(s.rawValue) { open = s }
            }
            .navigationTitle("LH 2.0 Sandbox")
        }
        .fullScreenCover(item: $open) { s in
            ScreenHost(screen: s)
                .environment(MockStore(scenario: s.scenario))
                .overlay(alignment: .bottomLeading) {
                    Button("Gallery") { open = nil }
                        .font(.caption.weight(.semibold))
                        .padding(8)
                        .glassEffect()
                        .padding(.leading, 12)
                        .padding(.bottom, 2)
                }
        }
    }
}

// MARK: - Tabs

enum AppTab: Hashable { case today, inbox, records, properties, add }

struct RootTabs: View {
    @Environment(MockStore.self) private var store
    @State private var tab: AppTab
    @State private var showAdd = false
    @State private var showSettings: Bool
    let openDetail: String?

    let scrollToMetrics: Bool

    init(initial: AppTab, openDetail: String? = nil, openSettings: Bool = false, scrollToMetrics: Bool = false) {
        self.scrollToMetrics = scrollToMetrics
        _tab = State(initialValue: initial)
        _showSettings = State(initialValue: openSettings)
        self.openDetail = openDetail
    }

    var body: some View {
        ZStack {
            switch tab {
            case .today: TodayView(showSettings: $showSettings, goInbox: { tab = .inbox }, scrollToMetrics: scrollToMetrics)
            case .inbox: InboxView(openDetail: openDetail)
            case .records: RecordsView(goInbox: { tab = .inbox })
            case .properties, .add: PropertiesView()
            }
        }
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $tab, inboxBadge: store.pendingCount) { showAdd = true }
        }
        .sheet(isPresented: $showAdd) {
            SuggestionDetailSheet(suggestion: nil) { _ in }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

/// Floating Liquid Glass tab bar: four tabs in one capsule, a separate round "+" (Flighty / Craft).
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    var inboxBadge: Int
    var onAdd: () -> Void
    @Namespace private var ns
    @Environment(\.colorScheme) private var scheme
    /// Denser glass than the default so content doesn't read through (Flighty's bar is near-opaque).
    private var barTint: Color { scheme == .dark ? Color(hex: 0x1C1C1E, alpha: 0.72) : Color.white.opacity(0.78) }
    @Environment(\.accessibilityReduceMotion) private var reduce

    private let items: [(AppTab, String, String)] = [
        (.today, "Today", "sun.max"),
        (.inbox, "Inbox", "tray"),
        (.records, "Records", "list.bullet.rectangle"),
        (.properties, "Properties", "house"),
    ]

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(items, id: \.0) { item in
                        let on = selection == item.0
                        Button {
                            withAnimation(Motion.snappy(reduce)) { selection = item.0 }
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: on ? item.2 + ".fill" : item.2)
                                    .font(.system(size: 19, weight: .medium))
                                    .frame(height: 24)
                                    .overlay(alignment: .topTrailing) {
                                        if item.0 == .inbox && inboxBadge > 0 {
                                            Text("\(inboxBadge)")
                                                .font(.system(size: 11, weight: .semibold))
                                                .monospacedDigit()
                                                .foregroundStyle(.white)
                                                .contentTransition(.numericText(value: Double(inboxBadge)))
                                                .padding(.horizontal, 5)
                                                .frame(minWidth: 18, minHeight: 18)
                                                .background(Color(uiColor: .systemRed), in: Capsule())
                                                .offset(x: 12, y: -6)
                                        }
                                    }
                                Text(item.1)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(on ? LH.action : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background {
                                if on {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.08))
                                        .matchedGeometryEffect(id: "sel", in: ns)
                                }
                            }
                            .contentShape(Capsule())
                        }
                        .buttonStyle(Pressable())
                        .accessibilityLabel(item.1)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(4)
                .glassEffect(.regular.tint(barTint).interactive(), in: Capsule())

                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 62, height: 62)
                }
                .buttonStyle(Pressable())
                .glassEffect(.regular.tint(barTint).interactive(), in: Circle())
                .accessibilityLabel("Log time")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 0)
    }
}

struct FramePump: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Rectangle()
                .fill(Color.black.opacity(0.012 + 0.008 * sin(t * 40)))
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
