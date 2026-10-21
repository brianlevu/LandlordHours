import SwiftUI
import UIKit

// MARK: - The one toast (2.0 surfaces lane)
//
// One toast for the whole app: Inbox, Today, Log time, Properties and save/load errors. It is the
// Inbox toast anatomy (glyph · message · at most one action), full width just above the tab bar,
// on a rounded rectangle so a second line wraps cleanly. Approved design: sandbox-surfaces 92e1bc8
// (SFToast), toast board in surfaces-frames-r2. It replaces the 1.x property-added confetti, the
// LHErrorBanner card and the r4 "Timer discarded" capsule.
//
// Tokens (named, BrandHex): surface `toastSurface` (light #FFFFFF card / dark #1B2550 tertiary),
// 1pt `border` hairline, shadow black 12% / 40% r16 y4, radius 22. Glyph tint: positive /
// textSecondary / caution. Action text: `action`. At accessibility sizes the action drops under
// the message. The glyph scales with Dynamic Type.
//
// Use it two ways:
//   - `LHToastCenter.shared.show(...)` from anywhere: queued, timed, shown by the shell.
//   - `LHToast(spec:onAction:)` directly when a screen owns its own toast state (the Inbox).

enum LHToastMetrics {
    static let radius: CGFloat = 22
    static let minHeight: CGFloat = 52
    static let shadowRadius: CGFloat = 16
    static let shadowY: CGFloat = 4
    static func shadowOpacity(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.4 : 0.12 }
}

struct LHToastSpec: Equatable, Identifiable {
    enum Kind: Equatable {
        /// Something was saved ("Added Oak Street Duplex", "Logged 2h").
        case success
        /// Something was undone or set aside ("Marked not rental work", "Timer discarded").
        case neutral
        /// Something didn't work ("Couldn't save your last change…").
        case problem
    }

    var id = UUID()
    var kind: Kind
    var message: String
    /// The one action's label ("Undo", "Retry", "Help"); nil for none.
    var actionTitle: String?

    static func == (a: LHToastSpec, b: LHToastSpec) -> Bool {
        a.id == b.id && a.kind == b.kind && a.message == b.message && a.actionTitle == b.actionTitle
    }

    var symbol: String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .neutral: return "arrow.uturn.backward.circle.fill"
        case .problem: return "exclamationmark.triangle.fill"
        }
    }

    /// Seconds on screen: an action needs time to reach; a problem stays longest.
    var duration: TimeInterval {
        switch kind {
        case .problem: return 8
        case .success, .neutral: return actionTitle == nil ? 4 : 5
        }
    }

    /// VoiceOver announcement.
    var announcement: String {
        guard let actionTitle else { return message }
        return "\(message). \(actionTitle) is available."
    }
}

struct LHToast: View {
    let spec: LHToastSpec
    var onAction: () -> Void = {}
    /// Accessibility identifiers: `<prefix>` on the toast, `<prefix>.action` on its button.
    var identifier = "toast"
    var actionIdentifier: String? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var glyphSize: CGFloat = 18
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var tint: Color {
        switch spec.kind {
        case .success: return colors.positive
        case .neutral: return colors.textSecondary
        case .problem: return colors.caution
        }
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: spec.symbol)
                    .font(.system(size: glyphSize, weight: .semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(spec.message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let title = spec.actionTitle {
                Button(title, action: onAction)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.action)
                    .frame(minWidth: 44, minHeight: 44)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .buttonStyle(.lhPressable)
                    .accessibilityIdentifier(actionIdentifier ?? "\(identifier).action")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, spec.actionTitle == nil ? 16 : 8)
        .padding(.vertical, 6)
        .frame(minHeight: LHToastMetrics.minHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LHToastMetrics.radius, style: .continuous)
                .fill(colors.toastSurface)
                .shadow(color: .black.opacity(LHToastMetrics.shadowOpacity(colorScheme)),
                        radius: LHToastMetrics.shadowRadius, y: LHToastMetrics.shadowY)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LHToastMetrics.radius, style: .continuous)
                .strokeBorder(colors.border, lineWidth: 1)
        )
        .compositingGroup()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Center (queue + timing)

/// App-wide toast queue. One toast at a time; later ones wait their turn (FIFO). A repeat of the
/// toast on screen (same kind and message) is dropped. At most `maxQueued` wait; when full, the
/// oldest waiting non-problem toast is dropped (a problem is never dropped for a success).
@MainActor
final class LHToastCenter: ObservableObject {
    static let shared: LHToastCenter = {
        #if DEBUG
        // Captures (-LHDebugToast) hold the toast on screen.
        if ProcessInfo.processInfo.arguments.contains("-LHDebugToast") {
            return LHToastCenter(sleep: { _ in try? await Task.sleep(for: .seconds(3600)) })
        }
        #endif
        return LHToastCenter()
    }()

    @Published private(set) var current: LHToastSpec?
    private(set) var queue: [LHToastSpec] = []
    var maxQueued = 3

    private var actions: [UUID: () -> Void] = [:]
    private var timer: Task<Void, Never>?
    /// Waits `seconds`; injectable so tests drive time.
    private let sleep: (TimeInterval) async -> Void
    private let announce: (String) -> Void

    init(
        sleep: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
        announce: @escaping (String) -> Void = { UIAccessibility.post(notification: .announcement, argument: $0) }
    ) {
        self.sleep = sleep
        self.announce = announce
    }

    /// Queues a toast. `action` runs when its button is tapped (the toast closes first).
    @discardableResult
    func show(_ kind: LHToastSpec.Kind, _ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) -> LHToastSpec {
        show(LHToastSpec(kind: kind, message: message, actionTitle: action == nil ? nil : actionTitle), action: action)
    }

    @discardableResult
    func show(_ spec: LHToastSpec, action: (() -> Void)? = nil) -> LHToastSpec {
        if let current, current.kind == spec.kind, current.message == spec.message { return current }
        if queue.contains(where: { $0.kind == spec.kind && $0.message == spec.message }) { return spec }
        if let action { actions[spec.id] = action }
        if current == nil {
            present(spec)
        } else {
            queue.append(spec)
            trimQueue()
        }
        return spec
    }

    /// The button on the current toast.
    func performAction() {
        guard let spec = current else { return }
        let action = actions[spec.id]
        dismissCurrent()
        action?()
    }

    /// Closes the current toast and shows the next one, if any.
    func dismissCurrent() {
        timer?.cancel()
        timer = nil
        if let spec = current { actions[spec.id] = nil }
        current = nil
        if !queue.isEmpty { present(queue.removeFirst()) }
    }

    /// Removes everything (sign-out, profile switch).
    func clear() {
        timer?.cancel()
        timer = nil
        queue.removeAll()
        actions.removeAll()
        current = nil
    }

    private func present(_ spec: LHToastSpec) {
        current = spec
        announce(spec.announcement)
        let id = spec.id
        timer = Task { [weak self, sleep] in
            await sleep(spec.duration)
            guard !Task.isCancelled, let self, self.current?.id == id else { return }
            self.dismissCurrent()
        }
    }

    private func trimQueue() {
        while queue.count > maxQueued {
            if let index = queue.firstIndex(where: { $0.kind != .problem }) {
                actions[queue[index].id] = nil
                queue.remove(at: index)
            } else {
                actions[queue[0].id] = nil
                queue.removeFirst()
            }
        }
    }
}

/// The shell's toast slot: shows `LHToastCenter.current` with a slide (Reduce Motion: none).
struct LHToastHost: View {
    @ObservedObject var center: LHToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let spec = center.current {
                LHToast(spec: spec, onAction: { center.performAction() })
                    .id(spec.id)
                    // Slides only: a fade would let row text show through mid-transition.
                    .transition(reduceMotion ? .identity : .move(edge: .bottom))
            }
        }
        .lhMotion(AppAnimation.reveal, value: center.current?.id)
    }
}
