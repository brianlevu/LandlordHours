// LHDesignSandbox — a throwaway SwiftUI design sandbox for LandlordHours 2.0.
// Launch args:  -screen <id>   -appearance light|dark
import SwiftUI

enum SandboxScreen: String, CaseIterable, Identifiable {
    case todayBehind = "today-behind"
    case todayOnPace = "today-onpace"
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

    var id: String { rawValue }

    var scenario: Scenario {
        switch self {
        case .todayOnPace: .onPace
        case .emptyToday: .empty
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
                if let screen {
                    ScreenHost(screen: screen)
                } else {
                    GalleryView()
                }
            }
            .environment(store)
            .tint(LH.action)
            .preferredColorScheme(scheme)
        }
    }
}

struct ScreenHost: View {
    let screen: SandboxScreen

    var body: some View {
        switch screen {
        case .todayBehind, .todayOnPace, .emptyToday:
            RootTabs(initial: .today)
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

    init(initial: AppTab, openDetail: String? = nil, openSettings: Bool = false) {
        _tab = State(initialValue: initial)
        _showSettings = State(initialValue: openSettings)
        self.openDetail = openDetail
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                TodayView(showSettings: $showSettings, goInbox: { tab = .inbox })
            }
            Tab("Inbox", systemImage: "tray", value: AppTab.inbox) {
                InboxView(openDetail: openDetail)
            }
            .badge(store.pendingCount)
            Tab("Records", systemImage: "list.bullet.rectangle", value: AppTab.records) {
                RecordsView(goInbox: { tab = .inbox })
            }
            Tab("Properties", systemImage: "house", value: AppTab.properties) {
                PropertiesView()
            }
            Tab("Log time", systemImage: "plus", value: AppTab.add, role: .search) {
                Color.clear
            }
        }
        .onChange(of: tab) { old, new in
            if new == .add {
                tab = old
                showAdd = true
            }
        }
        .sheet(isPresented: $showAdd) {
            SuggestionDetailSheet(suggestion: nil) { _ in }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}
