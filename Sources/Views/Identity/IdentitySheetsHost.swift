import SwiftUI

// MARK: - Where the identity sheets present (over Today, from the app root)
//
// The two-sets question (P4, once per held set, largest first; swipe down = decide later), the
// bulk question (P28), the zone-gone question (P31) and the account-changed question (P13).
// Presented as sheets in compact width. In the two-pane layout (package J) they keep presenting
// as sheets until J1's `PaneContext` lands; J then pushes them in the work pane (hand-off note).

struct IdentitySheetsHost: ViewModifier {
    @ObservedObject var identity: IdentityCoordinator
    let viewModel: AppViewModel
    @State private var shown: Sheet?

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { activeSheet }, set: { if $0 == nil { dismissed() } })) { sheet in
                Group {
                    switch sheet {
                    case .zoneGone: ZoneGoneSheet()
                    case .accountChanged: AccountChangedSheet()
                    case .bulk: BulkAbsenceSheet()
                    case .question(let group): MergeQuestionSheet(group: group, index: identity.pendingIndex, total: identity.pendingTotal)
                    }
                }
                .environmentObject(viewModel)
                .onAppear { shown = sheet }
            }
    }

    enum Sheet: Identifiable, Equatable {
        case zoneGone, accountChanged, bulk
        case question(ArchivedGroup)
        var id: String {
            switch self {
            case .zoneGone: return "zoneGone"
            case .accountChanged: return "accountChanged"
            case .bulk: return "bulk"
            case .question(let g): return "q-\(g.id)"
            }
        }
    }

    /// One at a time, in this order: what pauses sync first, then the bulk hold, then the question.
    private var activeSheet: Sheet? {
        guard viewModel.rootState == .app else { return nil }
        if identity.zoneGone { return .zoneGone }
        if identity.accountChanged && !identity.accountChangedDeferred { return .accountChanged }
        if identity.bulkHold != nil && !identity.bulkDeferred { return .bulk }
        if let group = identity.pendingQuestion, !identity.questionDeferred { return .question(group) }
        return nil
    }

    /// Swipe down = decide later (held, listed under Earlier records). Only the sheet that was
    /// showing, and only when it is still unanswered.
    private func dismissed() {
        switch shown {
        case .question(let group)?:
            if identity.pendingQuestion?.id == group.id { identity.questionDeferred = true }
        case .bulk?:
            if identity.bulkHold != nil { identity.bulkDeferred = true }
        case .accountChanged?:
            if identity.accountChanged { identity.accountChangedDeferred = true }
        case .zoneGone?, nil:
            break
        }
        shown = nil
    }
}

extension View {
    func identitySheets(_ viewModel: AppViewModel) -> some View {
        modifier(IdentitySheetsHost(identity: viewModel.identity, viewModel: viewModel))
    }
}
