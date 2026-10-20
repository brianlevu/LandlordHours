import SwiftUI

// Launch: -LHScreen <name> [-appearance light|dark] [-LHType xxl|ax3]
// Every name below is one capture. See scripts in /Users/brian/tmp/sandbox-screens/.

enum S2Route {
    static var requested: String? { UserDefaults.standard.string(forKey: "LHScreen") }

    static var typeSize: DynamicTypeSize? {
        switch UserDefaults.standard.string(forKey: "LHType") {
        case "xxl": .xxLarge
        case "xxxl": .xxxLarge
        case "ax3": .accessibility3
        default: nil
        }
    }

    static let all: [String] = [
        // Paywall ×4 contexts + states
        "paywall-export", "paywall-export-below", "paywall-second", "paywall-today", "paywall-settings",
        "paywall-sample", "paywall-pageloading", "paywall-price-loading", "paywall-price-failed", "paywall-buying",
        "paywall-asktobuy", "paywall-failed", "paywall-success", "paywall-success-second", "paywall-restoring", "paywall-restore-none",
        // Locked preview: page, card, row
        "lock-export", "lock-export-unlocked", "lock-today-record", "lock-properties", "lock-settings",
        // Inbox free-at-limit
        "limit-row", "limit-sheet", "limit-picker", "limit-waiting",
        // Today below the house
        "today-confirm", "today-confirm-more", "today-caughtup", "today-caughtup-off", "today-noproperty", "today-loading",
        "today-week", "today-week-midweek", "today-timer-running", "today-draft", "today-swipe", "today-timer-discarded",
        // Log
        "log-empty", "log-typed", "log-filled", "log-keyboard", "log-invalid",
        "log-voice-first", "log-voice-listening", "log-voice-filled", "log-voice-denied", "log-voice-demo",
        "log-picker-category", "log-picker-property", "log-picker-property-limit", "log-quick", "log-not-counted",
        // Timer
        "timer-idle", "timer-running", "timer-review",
        // Properties
        "props-list", "props-list-mp", "props-list-info", "props-12", "props-12-bottom", "props-empty", "props-loading", "props-limit",
        "prop-detail", "prop-detail-lower", "prop-detail-520", "prop-add", "prop-edit", "prop-edit-delete",
        // Leftovers
        "house-ladder",
        "restore", "restore-confirm", "delete-hold", "delete-hold-mid", "help", "help-filled", "learn", "learn-article",
    ]
}

struct S2Host: View {
    let name: String
    @Environment(\.requestedScheme) private var scheme

    var body: some View {
        content
            .tint(LHB.action)
            .preferredColorScheme(name.hasPrefix("paywall") && S2StatusBar.shared.overHero ? .dark : scheme)
            .modifier(TypeSizeOverride())
            .onAppear { S2Font.register() }
    }

    @ViewBuilder private var content: some View {
        switch name {
        // Paywall
        case "paywall-export": S2Paywall(context: .export)
        case "paywall-export-below": S2Paywall(context: .export, scrolledToBenefits: true)
        case "paywall-second": S2Paywall(context: .secondProperty("Oak Street Duplex"))
        case "paywall-today": S2Paywall(context: .todayUnlock)
        case "paywall-settings": S2Paywall(context: .settings)
        case "paywall-sample": S2Paywall(context: .export, sample: true)
        case "paywall-pageloading": S2Paywall(context: .export, pageLoading: true)
        case "paywall-price-loading": S2Paywall(context: .export, state: .priceLoading)
        case "paywall-price-failed": S2Paywall(context: .export, state: .priceFailed)
        case "paywall-buying": S2Paywall(context: .export, state: .buying)
        case "paywall-asktobuy": S2Paywall(context: .export, state: .askToBuy)
        case "paywall-failed": S2Paywall(context: .export, state: .failed)
        case "paywall-success": S2Paywall(context: .export, state: .success)
        case "paywall-success-second": S2Paywall(context: .secondProperty("Oak Street Duplex"), state: .success)
        case "paywall-restoring": S2Paywall(context: .settings, state: .restoring)
        case "paywall-restore-none": S2Paywall(context: .settings, state: .restoreNone)
        // Locks
        case "lock-export": PaywallPresenter(context: .export) { open in S2ExportPage(locked: true, onUnlock: open) }
        case "lock-export-unlocked": S2ExportPage(locked: false)
        case "lock-today-record": Tabs(tab: .today) { S2Today(state: .freeRecord) }
        case "lock-properties": Tabs(tab: .properties) { PaywallPresenter(context: .secondProperty(nil)) { open in S2PropertiesList(state: .limit, onUnlock: open) } }
        case "lock-settings": PaywallPresenter(context: .settings) { open in S2Settings(onUnlock: open) }
        // Inbox limit
        case "limit-row": Tabs(tab: .inbox) { S2InboxLimit(state: .row) }
        case "limit-sheet": Tabs(tab: .inbox) { S2InboxLimit(state: .sheet) }
        case "limit-picker": Tabs(tab: .inbox) { S2InboxLimit(state: .picker) }
        case "limit-waiting": Tabs(tab: .inbox) { S2InboxLimit(state: .waiting) }
        // Today
        case "today-confirm": Tabs(tab: .today) { S2Today(state: .confirm3) }
        case "today-confirm-more": Tabs(tab: .today, pending: 8) { S2Today(state: .confirmMore) }
        case "today-caughtup": Tabs(tab: .today, pending: 0) { S2Today(state: .caughtUp) }
        case "today-caughtup-off": Tabs(tab: .today, pending: 0) { S2Today(state: .caughtUpOff) }
        case "today-noproperty": Tabs(tab: .today, pending: 0) { S2Today(state: .noProperty) }
        case "today-loading": Tabs(tab: .today, pending: 0) { S2Today(state: .loading) }
        case "today-week": Tabs(tab: .today) { S2Today(state: .week) }
        case "today-week-midweek": Tabs(tab: .today) { S2Today(state: .weekMid) }
        case "today-timer-running": Tabs(tab: .today) { S2Today(state: .timerRunning) }
        case "today-draft": Tabs(tab: .today) { S2Today(state: .draft) }
        case "today-swipe": Tabs(tab: .today) { S2Today(state: .confirmTop) }
        case "today-timer-discarded": Tabs(tab: .today) { S2Today(state: .timerDiscarded) }
        // Log
        case let n where n.hasPrefix("log-"): OverToday { logSheet(n) }
        case "timer-idle": OverToday { TimerSheet(state: .idle) }
        case "timer-running": OverToday { TimerSheet(state: .running) }
        case "timer-review": OverToday { LogTimeSheet(state: .review) }
        // Properties
        case "props-list": Tabs(tab: .properties) { S2PropertiesList(state: .list) }
        case "props-list-mp": Tabs(tab: .properties) { S2PropertiesList(state: .list, perPropertyGoal: true) }
        case "props-list-info": Tabs(tab: .properties) { S2PropertiesList(state: .list, showInfo: true) }
        case "props-12": Tabs(tab: .properties) { S2PropertiesList(state: .twelve) }
        case "props-12-bottom": Tabs(tab: .properties) { S2PropertiesList(state: .twelveBottom) }
        case "props-empty": Tabs(tab: .properties, pending: 0) { S2PropertiesList(state: .empty) }
        case "props-loading": Tabs(tab: .properties, pending: 0) { S2PropertiesList(state: .loading) }
        case "props-limit": Tabs(tab: .properties) { S2PropertiesList(state: .limit) }
        case "prop-detail": NavigationStack { S2PropertyDetail(p: S2Data.pine) }
        case "prop-detail-lower": NavigationStack { S2PropertyDetail(p: S2Data.pine, scrolled: true) }
        case "prop-detail-520": NavigationStack { S2PropertyDetail(p: S2Data.oak) }
        case "prop-add": OverProps { S2PropertyEdit(state: .add) }
        case "prop-edit": OverProps { S2PropertyEdit(state: .edit) }
        case "prop-edit-delete": OverProps { S2PropertyEdit(state: .editDelete) }
        // Leftovers
        case "restore": OverSettings { S2Restore() }
        case "restore-confirm": OverSettings { S2Restore(confirm: true) }
        case "delete-hold": S2DeleteAll()
        case "delete-hold-mid": S2DeleteAll(frozenProgress: 0.55)
        case "house-ladder": HouseLadder()
        case "help": S2Help()
        case "help-filled": S2Help(filled: true)
        case "learn": S2Learn()
        case "learn-article": S2Learn(article: true)
        default:
            List(S2Route.all, id: \.self) { Text($0) }
        }
    }

    @ViewBuilder private func logSheet(_ n: String) -> some View {
        switch n {
        case "log-typed": LogTimeSheet(state: .typed)
        case "log-filled": LogTimeSheet(state: .filled)
        case "log-keyboard": LogTimeSheet(state: .keyboard)
        case "log-invalid": LogTimeSheet(state: .invalid)
        case "log-voice-first": LogTimeSheet(state: .voiceFirst)
        case "log-voice-listening": LogTimeSheet(state: .listening)
        case "log-voice-filled": LogTimeSheet(state: .voiceFilled)
        case "log-voice-denied": LogTimeSheet(state: .voiceDenied)
        case "log-voice-demo": LogTimeSheet(state: .voiceDemo)
        case "log-picker-category": LogTimeSheet(state: .filled, picker: .category)
        case "log-picker-property": LogTimeSheet(state: .filled, picker: .property)
        case "log-picker-property-limit": LogTimeSheet(state: .filled, picker: .property, limitPicker: true)
        case "log-quick": LogTimeSheet(state: .quick)
        case "log-not-counted": LogTimeSheet(state: .notCounted)
        default: LogTimeSheet(state: .empty)
        }
    }
}

struct TypeSizeOverride: ViewModifier {
    func body(content: Content) -> some View {
        if let t = S2Route.typeSize { content.dynamicTypeSize(t) } else { content }
    }
}

/// Tapping any "Unlock Pro" opens the paywall for that context.
struct PaywallPresenter<C: View>: View {
    let context: PaywallContext
    @ViewBuilder var content: (@escaping () -> Void) -> C
    @State private var open = false
    var body: some View {
        content { open = true }
            .fullScreenCover(isPresented: $open) { S2Paywall(context: context) }
    }
}

/// A sheet presented over Today (the "+" flow), so captures show the real sheet chrome.
struct OverToday<S: View>: View {
    @ViewBuilder var sheet: () -> S
    @State private var shown = true
    var body: some View {
        Tabs(tab: .today) { S2Today(state: .confirm3) }
            .sheet(isPresented: $shown) {
                sheet().modifier(TypeSizeOverride()).presentationDetents([.large]).presentationBackground(LHB.canvas).interactiveDismissDisabled()
            }
    }
}

struct OverProps<S: View>: View {
    @ViewBuilder var sheet: () -> S
    @State private var shown = true
    var body: some View {
        Tabs(tab: .properties) { S2PropertiesList(state: .list) }
            .sheet(isPresented: $shown) { sheet().modifier(TypeSizeOverride()).presentationDetents([.large]).presentationBackground(LHB.canvas) }
    }
}

struct OverSettings<S: View>: View {
    @ViewBuilder var sheet: () -> S
    @State private var shown = true
    var body: some View {
        S2Settings(pro: true)
            .sheet(isPresented: $shown) { sheet().modifier(TypeSizeOverride()).presentationDetents([.medium, .large]).presentationBackground(LHB.canvas) }
    }
}

// MARK: - Tab bar (production floating glass bar, brand tokens)

enum S2Tab: Hashable { case today, inbox, records, properties }

/// The one pending count: tab badge, Today's To confirm capsule and "Review all N" all read it.
@Observable final class S2InboxCount {
    var pending: Int
    /// The undo toast lives in the bottom band, above the tab bar, never over content.
    var toast: String?
    /// Surfaces lane: the one toast system (glyph · message · action).
    var spec: SFToastSpec?
    init(_ n: Int) { pending = n }
}

struct Tabs<C: View>: View {
    let tab: S2Tab
    @State private var inbox: S2InboxCount
    let content: () -> C

    init(tab: S2Tab, pending: Int = 3, toast: SFToastSpec? = nil, @ViewBuilder content: @escaping () -> C) {
        self.tab = tab
        let box = S2InboxCount(pending)
        box.spec = toast
        _inbox = State(initialValue: box)
        self.content = content
    }

    var body: some View {
        content()
            .environment(inbox)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // One bottom band: an opaque canvas scrim behind the tab pill, the "+" and the gap
                // between them, with a short fade on top. Scroll views inset to it automatically.
                VStack(spacing: 10) {
                    if let sp = inbox.spec {
                        SFToast(spec: sp).padding(.horizontal, 20).transition(.toast)
                    } else if let t = inbox.toast {
                        UndoToast(text: t).transition(.toast).accessibilityIdentifier("today.toast")
                    }
                    S2TabBar(selection: tab, badge: inbox.pending)
                }
                .padding(.top, 18)
                .frame(maxWidth: .infinity)
                .background {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [LHB.canvas.opacity(0), LHB.canvas], startPoint: .top, endPoint: .bottom).frame(height: 18)
                        LHB.canvas
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
                }
                .animation(.easeOut(duration: 0.22), value: inbox.toast)
            }
    }
}

struct S2TabBar: View {
    var selection: S2Tab
    var badge: Int
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var solid
    private var tint: Color { scheme == .dark ? Color(hex: 0x141C3F, alpha: 0.72) : Color.white.opacity(0.78) }
    private let items: [(S2Tab, String, String)] = [
        (.today, "Today", "sun.max"), (.inbox, "Inbox", "tray"),
        (.records, "Records", "list.bullet.rectangle"), (.properties, "Properties", "house"),
    ]

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(items, id: \.0) { item in
                        let on = selection == item.0
                        VStack(spacing: 3) {
                            Image(systemName: on ? item.2 + ".fill" : item.2)
                                .font(.system(size: 19, weight: .medium)).frame(height: 24)
                                .overlay(alignment: .topTrailing) {
                                    if item.0 == .inbox && badge > 0 {
                                        Text("\(badge)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                                            .foregroundStyle(LHB.onAction)
                                            .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                                            .background(LHB.action, in: Capsule())
                                            .offset(x: 12, y: -6)
                                    }
                                }
                            Text(item.1).font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(on ? LHB.action : LHB.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background { if on { Capsule().fill(LHB.textPrimary.opacity(0.08)) } }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(4)
                .glassEffect(solid ? .identity : .regular.tint(tint).interactive(), in: Capsule())
                .background { if solid { Capsule().fill(LHB.card) } }
                Image(systemName: "plus").font(.system(size: 22, weight: .medium)).foregroundStyle(LHB.textPrimary)
                    .frame(width: 62, height: 62)
                    .glassEffect(solid ? .identity : .regular.tint(tint).interactive(), in: Circle())
                    .accessibilityLabel("Log time")
                    .contextMenu {
                        Button("Log time", systemImage: "square.and.pencil") {}
                        Button("Start a timer", systemImage: "timer") {}
                    }
            }
        }
        .padding(.horizontal, 20)
    }
}


/// Review frame: the property mini-house (48 and 120) and the Today hero house at 0, 128, 520 and 800h.
struct HouseLadder: View {
    private let hours: [Double] = [0, 128, 520, 800]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DisplayTitle(text: "House ladder")
                S2Header("Property mini-house · 48pt (capped at the 500h roof)")
                HStack(spacing: 0) {
                    ForEach(hours, id: \.self) { h in
                        VStack(spacing: 6) {
                            PropertyHouse(hours: h, size: 48)
                                .accessibilityIdentifier("ladder.\(Int(h))")
                            Text("\(Int(h))h · \(houseStage(h))").font(.caption2).foregroundStyle(LHB.textSecondary)
                                .multilineTextAlignment(.center).frame(height: 44, alignment: .top)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                S2Header("Property mini-house · 120pt")
                HStack(spacing: 0) {
                    ForEach(hours, id: \.self) { h in PropertyHouse(hours: h, size: 84).frame(maxWidth: .infinity) }
                }
                S2Header("Today hero house · uncapped")
                HStack(spacing: 0) {
                    ForEach(hours, id: \.self) { h in
                        HouseArt(key: S2House.keyframe(h)).frame(width: 88, height: 88)
                            .background(S2Paper(radius: 14)).frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(20)
        }
        .background(LHB.canvas.ignoresSafeArea())
    }
}
