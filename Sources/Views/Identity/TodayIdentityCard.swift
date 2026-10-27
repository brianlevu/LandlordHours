import SwiftUI
import UIKit

// MARK: - The one identity notice on Today (P10, P11, P12, P25, P28 entry, P29, P13 later, quota)
//
// C owns the slot (under the hero) and how a notice card sits on the page; K owns when one shows
// and what it says. One glyph, at most two short lines, one `.secondary` action and a "Not now"
// `.tertiary` where the notice can be dismissed. On the dusk/night page: the card fill with the
// 1pt page edge (LHRowGroup(onPage:)).

struct TodayIdentityCard: View {
    let notice: TodayIdentityNotice
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showEarlier = false
    @State private var showBulk = false

    var body: some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        LHRowGroup(onPage: true) {
            // One row: glyph, the words, then the text actions stacked at the trailing edge, so
            // the card has no empty band under the words (D4).
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                                      : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                LHRowGlyph(systemImage: glyph, tint: tint)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if actionTitle != nil || dismissible {
                    VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 0) {
                        if let actionTitle {
                            Button(actionTitle, action: act)
                                .buttonStyle(LHButton.tertiary)
                                .accessibilityIdentifier("today.identity.action")
                        }
                        if dismissible {
                            Button(String(localized: "Not now", table: "Identity")) {
                                withAnimation(AppAnimation.quick) { viewModel.identity.dismissNotice(notice) }
                            }
                            .buttonStyle(LHButton.tertiary)
                            .accessibilityIdentifier("today.identity.dismiss")
                        }
                    }
                    .layoutPriority(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.identity.\(notice.id)")
        .sheet(isPresented: $showEarlier) {
            NavigationStack { EarlierRecordsView() }.environmentObject(viewModel)
        }
        .sheet(isPresented: $showBulk) {
            BulkAbsenceSheet().environmentObject(viewModel)
        }
    }

    private var glyph: String {
        switch notice {
        case .iCloudOff: return "icloud.slash"
        case .cloudWaiting: return "icloud"
        case .unified: return "checkmark.icloud"
        case .needsSpace: return "externaldrive.badge.exclamationmark"
        case .settingsKept: return "slider.horizontal.3"
        case .bulkWaiting: return "exclamationmark.icloud"
        case .accountChangedLater: return "person.icloud"
        case .iCloudFull: return "exclamationmark.icloud"
        }
    }

    private var tint: LHRowGlyph.Tint {
        switch notice {
        case .needsSpace, .bulkWaiting, .iCloudFull: return .caution
        case .unified: return .positive
        default: return .informational
        }
    }

    private var text: String {
        switch notice {
        case .iCloudOff:
            return String(localized: "Your hours are only on this iPhone. Turn on iCloud for Dormer to keep a copy.", table: "Identity")
        case .cloudWaiting:
            return String(localized: "Some earlier records may be in iCloud. They’ll be added when iCloud is back.", table: "Identity")
        case .unified:
            return String(localized: "No more sign-in. Everything you tracked is in one place now.", table: "Identity")
        case .needsSpace(let bytes):
            let size = ByteCountFormatter.string(fromByteCount: Int64(max(bytes, 1_000_000)), countStyle: .file)
            return String(localized: "Not enough space to update your records. Free up about \(size) and reopen Dormer. Nothing has changed yet.", table: "Identity")
        case .settingsKept:
            return String(localized: "We kept the settings from your earlier records. Your setup answers from today are in Settings.", table: "Identity")
        case .bulkWaiting(let hours, let total):
            return String(localized: "\(IdentityCopy.hours(hours)) of \(IdentityCopy.hours(total)) aren’t in iCloud anymore. Nothing has been deleted here.", table: "Identity")
        case .accountChangedLater:
            return String(localized: "This iPhone uses a different iCloud now. Sync is paused until you choose.", table: "Identity")
        case .iCloudFull:
            return String(localized: "iCloud is full. Your records are safe on this iPhone; free up iCloud space to keep syncing.", table: "Identity")
        }
    }

    private var actionTitle: String? {
        switch notice {
        case .iCloudOff: return String(localized: "Turn on", table: "Identity")
        case .unified: return viewModel.identity.earlierCount > 0 ? String(localized: "See what changed", table: "Identity") : nil
        case .bulkWaiting: return String(localized: "Answer now", table: "Identity")
        case .accountChangedLater: return String(localized: "Choose", table: "Identity")
        case .settingsKept: return String(localized: "See them", table: "Identity")
        case .cloudWaiting, .needsSpace, .iCloudFull: return nil
        }
    }

    private var dismissible: Bool {
        switch notice {
        case .iCloudOff, .unified, .settingsKept, .cloudWaiting: return true
        case .needsSpace, .bulkWaiting, .accountChangedLater, .iCloudFull: return false
        }
    }

    private func act() {
        switch notice {
        case .iCloudOff:
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        case .unified:
            viewModel.identity.dismissNotice(.unified)
            showEarlier = true
        case .bulkWaiting:
            showBulk = true
        case .accountChangedLater:
            viewModel.identity.showAccountChangedAgain()
        case .settingsKept:
            NotificationCenter.default.post(name: .switchToTab, object: ShellTab.settingsIndex)
        case .cloudWaiting, .needsSpace, .iCloudFull:
            break
        }
    }
}
