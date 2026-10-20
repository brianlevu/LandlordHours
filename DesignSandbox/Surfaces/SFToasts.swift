import SwiftUI

// §3 Toasts. One component (SFToast) in the bottom band above the tab bar, where the approved
// Today undo toast lives. It replaces: the 1.x property-added confetti, the LHErrorBanner card,
// and the plain-text UndoToast.

enum SFToastKind { case undo, saveError, loadError, propertyAdded }

extension SFToastKind {
    var spec: SFToastSpec {
        switch self {
        case .undo: SFToastSpec(kind: .neutral, message: "Marked not landlord work", action: "Undo")
        case .saveError: SFToastSpec(kind: .problem, message: "Couldn’t save your last change. Your iPhone may be out of space.", action: "Retry")
        case .loadError: SFToastSpec(kind: .problem, message: "Couldn’t open your records. They’re still safe on this iPhone.", action: "Help")
        case .propertyAdded: SFToastSpec(kind: .success, message: "Added The Arroyo Seco Schoolhouse Lofts, Unit 4B")
        }
    }
}

struct SFToastFrame: View {
    let kind: SFToastKind
    var body: some View {
        switch kind {
        case .propertyAdded:
            Tabs(tab: .properties, toast: kind.spec) { S2PropertiesList(state: .list) }
        default:
            Tabs(tab: .today, toast: kind.spec) { S2Today(state: .confirm3) }
        }
    }
}

/// Every toast, one under the other, on the canvas and on a card, for the anatomy review.
struct SFToastBoard: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DisplayTitle(text: "Toasts")
                Text("One toast for the whole app. A glyph says what happened, the message says it in plain words, and there is at most one action.")
                    .font(.subheadline).foregroundStyle(LHB.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                S2Header("Undo").padding(.top, 8)
                SFToast(spec: SFToastKind.undo.spec)
                SFToast(spec: SFToastSpec(kind: .neutral, message: "Timer discarded", action: "Undo"))
                S2Header("Saved").padding(.top, 8)
                SFToast(spec: SFToastSpec(kind: .success, message: "Added Oak Street Duplex"))
                SFToast(spec: SFToastSpec(kind: .success, message: "Logged 2h at Pine Cabin", action: "Undo"))
                S2Header("Something went wrong").padding(.top, 8)
                SFToast(spec: SFToastKind.saveError.spec)
                SFToast(spec: SFToastKind.loadError.spec)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(LHB.canvas.ignoresSafeArea())
        .overlay(alignment: .top) { TopEdgeFade() }
    }
}
