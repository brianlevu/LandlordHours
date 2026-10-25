import Foundation
import SwiftUI

// MARK: - Package K's words (P1–P31), all from Identity.xcstrings
//
// Plain, short, read-aloud tested: "rental" not "property", "hours" not "entries", no
// "profile" or "account" (except iCloud's own), no "household" on screen.

enum IdentityCopy {
    static let table = "Identity"

    /// "1 hour", "42 hours", "12h 30m".
    static func hours(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.01 {
            let n = Int(rounded)
            return n == 1 ? String(localized: "1 hour", table: "Identity") : String(localized: "\(n) hours", table: "Identity")
        }
        return LHFormat.hours(value)
    }

    static func rentals(_ n: Int) -> String {
        n == 1 ? String(localized: "1 rental", table: "Identity") : String(localized: "\(n) rentals", table: "Identity")
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    // P1 / P2 / P3
    static var welcomeFooter: String { String(localized: "Your records stay on your iPhone and in your iCloud.", table: "Identity") }
    static var welcomeChecking: String { String(localized: "Checking iCloud for earlier records…", table: "Identity") }
    static func welcomeFound(_ hours: Double) -> String {
        String(localized: "We found \(Self.hours(hours)) from an earlier version. They’re already here.", table: "Identity")
    }

    /// "128 hours at 3 rentals, last on Oct 20."
    static func groupSummary(hours: Double, rentals: Int, last: Date?) -> String {
        if let last {
            return String(localized: "\(Self.hours(hours)) at \(Self.rentals(rentals)), last on \(Self.shortDate(last)).", table: "Identity")
        }
        return String(localized: "\(Self.hours(hours)) at \(Self.rentals(rentals)).", table: "Identity")
    }

    static func groupSource(_ source: GroupSource) -> String {
        switch source {
        case .device: return String(localized: "On this iPhone", table: "Identity")
        case .iCloud: return String(localized: "In iCloud", table: "Identity")
        case .both: return String(localized: "On this iPhone and in iCloud", table: "Identity")
        }
    }

    // P7 / P8 / P9 / restricted
    static func lastSynced(_ date: Date?) -> String {
        guard let date else { return String(localized: "Not synced yet", table: "Identity") }
        if Date().timeIntervalSince(date) < 60 { return String(localized: "Synced just now", table: "Identity") }
        let relative = date.formatted(.relative(presentation: .named))
        return String(localized: "Synced \(relative)", table: "Identity")
    }

    static var footer: String {
        String(localized: "Your records live on this iPhone and in your own iCloud. We never see them. Photos stay on this iPhone.", table: "Identity")
    }
}

extension View {
    /// The pinned primary of an identity sheet sits on the sheet's own fill, so words scrolling
    /// beneath it at accessibility sizes never show through (LHSheet's footer has no fill; noted
    /// for package 0).
    func identitySheetFooter(_ colors: AdaptiveColors) -> some View {
        frame(maxWidth: .infinity)
            .background(alignment: .top) {
                colors.backgroundSecondary
                    .padding(.horizontal, -16)
                    .padding(.top, -8)
                    .padding(.bottom, -40)
            }
    }
}
