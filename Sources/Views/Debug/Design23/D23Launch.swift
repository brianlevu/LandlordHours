import SwiftUI

#if DEBUG
// MARK: - 2.3 design sandbox (DEBUG only; never ships)
//
// Hi-fi designs for 2.3, rendered with the real LH* components on the real Today and rental page.
// Nothing here is feature code: data is fixed sample data, buttons only move between frames.
//
//   -LHD23 <scene>   with the Today seed:
//       -LHMockScenario emptyMainTabs -LHCraftSeed d23 -LHCraftFocus 1 -LHSeedSuggestions inbox
//
//   Today sections   today-care · today-learn · today-both        (add -LHCraftScroll to scroll)
//   Care plan        care-plan · care-plan-str                     (pushed from Today)
//   Learning         lesson-<lesson>-<card> (1-1 … 3-3) · lessons  (sheet / pushed)
//   Paywall          paywall · trial-start · day12 · pick-free · free-rental-settings
//                    rental-viewonly (pushes the real rental page for Oak Street Duplex)
//   Nudges           reminders (pushed) · lock (a board, no app shell)
//
// Two one-line DEBUG hooks place the slots: `DashboardView.belowHero` (D23TodaySlot) and
// `PropertyDetailView.page` (D23RentalSlot). The lock board is a branch in the app entry.

enum D23 {
    static var scene: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LHD23"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    static var showsCare: Bool { scene == "today-care" || scene == "today-both" }
    static var showsLearn: Bool { scene == "today-learn" || scene == "today-both" }

    /// Trial dates from the capture day: the reminder 12 days in, the renewal 14 days in.
    static let trialStart = Calendar.current.startOfDay(for: Date())
    static var reminderDate: Date { Calendar.current.date(byAdding: .day, value: 12, to: trialStart) ?? trialStart }
    static var renewDate: Date { Calendar.current.date(byAdding: .day, value: 14, to: trialStart) ?? trialStart }
    static var nextSwitchDate: Date { Calendar.current.date(byAdding: .month, value: 1, to: trialStart) ?? trialStart }

    static func short(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static let price = "$99.99"
    static let freeRental = "Pine Cabin"
    static let viewOnlyRental = "Oak Street Duplex"
}

// MARK: - Shared pieces

/// The one done marker for care items and lessons: the row's 36pt glyph tile turns `positive`
/// with a checkmark. Not the 22pt confirm circle (§1.3), which stays the To confirm control.
struct D23DoneTile: View {
    var body: some View {
        LHRowGlyph(systemImage: "checkmark", tint: .positive)
    }
}

/// A 4pt progress bar: `border` track (`actionSurface` reads as the track on cards), `action` fill.
/// The onboarding progress (§1.24) at 4pt so it reads at card scale.
struct D23ProgressBar: View {
    let value: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(colors.actionSurface)
                Capsule().fill(colors.action).frame(width: max(4, proxy.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// Today's section header (the To confirm header's style): `.headline` with an optional trailing
/// `.tertiary`, 4pt inset to line up with the card's corner.
struct D23TodayHeader: View {
    let title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AdaptiveColors(colorScheme: colorScheme).textPrimary)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing, let action {
                Button(trailing, action: action).buttonStyle(LHButton.tertiary)
            }
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 24)
    }
}

/// A plain section on the canvas: `LHSectionHeader` then content, 8 apart.
struct D23Section<Content: View>: View {
    let title: String
    var count: Int? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: LHMetrics.headerToContent) {
            LHSectionHeader(title, count: count)
                .padding(.horizontal, 4)
            content
        }
    }
}

/// The background of a pinned sheet foot: opaque, with a 16pt fade above it so content that
/// scrolls under the button softens instead of being cut flat.
struct D23FootFade: View {
    let color: Color
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [color.opacity(0), color], startPoint: .top, endPoint: .bottom)
                .frame(height: 16)
            color
        }
        .padding(.top, -16)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }
}

/// Presents state without animation, after the page has settled (captures).
@MainActor
func d23Present(after seconds: Double = 0.4, _ body: @escaping () -> Void) {
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(seconds))
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }
}

// MARK: - Today slot

/// Placed under To confirm on Today. Draws the new 2.3 sections for the `today-*` scenes, and
/// presents every other scene from Today, so each frame sits in the real shell.
struct D23TodaySlot: View {
    let rentalName: String
    let hours: Double
    let goal: Double

    @EnvironmentObject private var viewModel: AppViewModel
    @State private var showCarePlan = false
    @State private var carePlanKind: D23CareRental = .pine
    @State private var lesson: D23LessonOpen?
    @State private var showLessons = false
    @State private var showPaywall = false
    @State private var showTrialStart = false
    @State private var showDay12 = false
    @State private var showPickFree = false
    @State private var showFreeSettings = false
    @State private var showReminders = false
    @State private var showViewOnly = false
    @State private var didPresent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if D23.showsLearn {
                D23MilestoneCard(hours: hours, goal: goal,
                                 onRead: { lesson = D23LessonOpen(lesson: 0, card: 0) },
                                 onSeeAll: { showLessons = true })
                    .padding(.top, LHMetrics.sectionGap)
            }
            if D23.showsCare {
                D23CareTodaySection(rental: .pine,
                                    onSeePlan: { carePlanKind = .pine; showCarePlan = true },
                                    onItem: { _ in })
                    .padding(.top, LHMetrics.sectionGap)
            }
        }
        .padding(.horizontal, LHMetrics.gutter)
        .navigationDestination(isPresented: $showCarePlan) { D23CarePlanView(rental: carePlanKind) }
        .navigationDestination(isPresented: $showLessons) { D23LessonListView() }
        .navigationDestination(isPresented: $showFreeSettings) { D23FreeRentalSettingsView() }
        .navigationDestination(isPresented: $showReminders) { D23RemindersView() }
        .navigationDestination(isPresented: $showViewOnly) {
            if let oak = viewModel.properties.first(where: { $0.name == D23.viewOnlyRental }) {
                PropertyDetailView(propertyId: oak.id, onEdit: { _ in })
            }
        }
        .sheet(item: $lesson) { open in
            D23LessonSheet(lessonIndex: open.lesson, startCard: open.card)
        }
        .fullScreenCover(isPresented: $showPaywall) { D23PaywallView() }
        .fullScreenCover(isPresented: $showTrialStart) { D23TrialStartView() }
        .sheet(isPresented: $showDay12) {
            D23Day12Sheet()
                .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPickFree) {
            D23PickFreeSheet()
                .presentationDetents([.fraction(0.7), .large])
                .presentationDragIndicator(.visible)
        }
        .task { present() }
    }

    private func present() {
        guard !didPresent, let scene = D23.scene else { return }
        didPresent = true
        // Trial (Pro) for every scene except the free-plan ones and the paywall itself.
        let free = ["paywall", "pick-free", "free-rental-settings", "rental-viewonly"].contains(scene)
        if free {
            UserDefaults.standard.set(false, forKey: UserScope.key("isProUser"))
            SubscriptionManager.shared.checkSubscriptionStatus()
        } else {
            SubscriptionManager.shared.unlockPro()
        }
        d23Present(after: 0.6) {
            switch scene {
            case "care-plan": carePlanKind = .pine; showCarePlan = true
            case "care-plan-str": carePlanKind = .lakeside; showCarePlan = true
            case "lessons": showLessons = true
            case "paywall": showPaywall = true
            case "trial-start": showTrialStart = true
            case "day12": showDay12 = true
            case "pick-free": showPickFree = true
            case "free-rental-settings": showFreeSettings = true
            case "reminders": showReminders = true
            case "rental-viewonly": showViewOnly = true
            default:
                if scene.hasPrefix("lesson-") {
                    let parts = scene.dropFirst("lesson-".count).split(separator: "-").compactMap { Int($0) }
                    if parts.count == 2 { lesson = D23LessonOpen(lesson: parts[0] - 1, card: parts[1] - 1) }
                }
            }
        }
    }
}

struct D23LessonOpen: Identifiable, Equatable {
    let lesson: Int
    let card: Int
    var id: String { "\(lesson)-\(card)" }
}

// MARK: - Rental slot

/// Placed between the rental page's hero and body. Only the view-only scene draws anything.
struct D23RentalSlot: View {
    let property: RentalProperty

    var body: some View {
        if D23.scene == "rental-viewonly", property.name == D23.viewOnlyRental {
            D23ViewOnlyCard(rentalName: property.name, hours: 46)
                .padding(.horizontal, LHMetrics.gutter)
                .padding(.top, LHMetrics.sectionGap)
        }
    }
}

// MARK: - Board root (no app shell)

struct D23BoardLaunch {
    let name: String
    static let current: D23BoardLaunch? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LHD23Board"), args.indices.contains(i + 1) else { return nil }
        return D23BoardLaunch(name: args[i + 1])
    }()
}

struct D23BoardRoot: View {
    let launch: D23BoardLaunch
    var body: some View {
        switch launch.name {
        case "lock": D23LockBoard()
        default: Text("Unknown board \(launch.name)")
        }
    }
}
#endif
