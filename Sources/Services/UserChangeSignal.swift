import Foundation

// MARK: - "Show the result where it happened" (2.3 step-0 seam; owner: package E)
//
// AppViewModel records each change the user makes themselves (a Log time save, an Inbox confirm).
// Package E implements the signal: Today opens on that rental once, plays the build there, then
// respects a manual pick (memory item 6). Never record iCloud sync, Inbox scans or imports here.
// Until E lands, recording does nothing.
final class UserChangeSignal {
    static let shared = UserChangeSignal()

    enum Kind: String, Sendable {
        /// Log time saved hours.
        case logged
        /// An Inbox or To confirm suggestion was confirmed.
        case confirmed
    }

    func record(rentalID: UUID, kind: Kind) {}
}
