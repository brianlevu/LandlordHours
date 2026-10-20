import SwiftUI

/// The 14 sample calendar events (OnbFlow.sampleEvents) as Inbox rows: tool, category, when.
@MainActor
enum OnbEvents {
    struct Event {
        let title: String
        let hours: Double
        let tool: String
        let category: String
        let kind: Category
        let when: String
    }

    static let all: [Event] = OnbFlow.sampleEvents.enumerated().map { i, e in
        let (tool, cat, kind): (String, String, Category) = {
            switch e.0 {
            case "Plumber", "Water heater repair": ("bp_tool_repairs_36", "Repairs", .repairs)
            case "Showing", "Lease signing": ("bp_tool_showing_36", "Leasing", .leasing)
            case "Inspection": ("bp_tool_inspection_36", "Inspections", .inspections)
            case "Hardware store run": ("bp_tool_supplies_36", "Supplies", .supplies)
            case "Call with tenant": ("bp_tool_comms_36", "Tenant calls", .tenant)
            case "Turnover cleaning": ("bp_tool_cleaning_36", "Cleaning", .cleaning)
            case "Bookkeeping": ("bp_tool_bookkeeping_36", "Bookkeeping", .bookkeeping)
            case "Contractor walkthrough": ("bp_tool_renovation_36", "Renovation", .renovation)
            case "HOA meeting": ("bp_tool_management_36", "Management", .management)
            default: ("bp_tool_legal_36", "Paperwork", .legal)
            }
        }()
        return Event(title: e.0, hours: e.1, tool: tool, category: cat, kind: kind,
                     when: "Calendar · Oct \(16 - i / 2)")
    }

    /// "2h", "1h 30m", "30m".
    static func duration(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        if m < 60 { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }
}

/// One suggestion with its visible next action: Confirm, or Not work.
struct OnbEventRow: View {
    @Bindable var flow: OnbFlow
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let e = OnbEvents.all[index]
        let place = flow.name.isEmpty ? "Oak Street duplex" : flow.name
        OnbSampleRow(hours: OnbEvents.duration(e.hours), tool: e.tool, when: e.when,
                     title: "\(e.title) at \(place)", category: e.category, categoryColor: onbCategoryColor(e.kind),
                     onConfirm: { act { flow.confirmed.insert(index) } },
                     onSkip: { act { flow.skipped.insert(index) } },
                     id: "\(index)")
    }

    private func act(_ change: () -> Void) {
        withAnimation(reduce ? .easeInOut(duration: 0.2) : .spring(response: 0.34, dampingFraction: 0.88)) {
            change()
            flow.inboxBadge = max(0, OnbEvents.all.count - flow.confirmed.count - flow.skipped.count)
        }
    }
}

/// Inbox, where "Review 14 suggestions" lands: every suggestion, one tap each.
struct OnbInbox: View {
    @Bindable var flow: OnbFlow
    @Environment(\.onbScheme) private var scheme

    private var open: [Int] { OnbEvents.all.indices.filter { !flow.confirmed.contains($0) && !flow.skipped.contains($0) } }
    private var confirmedHours: Double { flow.confirmed.reduce(0) { $0 + OnbEvents.all[$1].hours } }

    var body: some View {
        ZStack(alignment: .bottom) {
            PC.canvas.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Inbox").prodDisplay().foregroundStyle(PC.textPrimary).padding(.top, 52)
                    Text("\(open.count) from your calendar in the last 90 days. Confirm the ones that were rental work.")
                        .font(.subheadline).foregroundStyle(PC.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !flow.confirmed.isEmpty {
                        Label("\(OnbFlow.hours(confirmedHours)) confirmed · counted toward your goal", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PC.positive)
                            .padding(.horizontal, 14).frame(minHeight: 40)
                            .background(PC.positiveSurface, in: Capsule())
                            .transition(.opacity)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(open.enumerated()), id: \.element) { k, i in
                            if k > 0 { Divider().overlay(PC.border).padding(.leading, 82) }
                            OnbEventRow(flow: flow, index: i)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(PC.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            OnbTabBar(badge: flow.inboxBadge, inbox: true)
        }
        .environment(\.colorScheme, scheme)
    }
}
