import SwiftUI

// MARK: - THE locked preview (redesign-specs §0)
//
// One lock for the whole app. It replaces the four 1.x idioms (the Unlock card, the "PRO" text,
// the "Upgrade" row and the lone lock glyph).
// - The real content renders; its first block stays sharp.
// - Below the fold the content blurs (10pt; 4pt for a row) under a fade to the surface.
// - On top: one line saying what is locked, one saying what stays active and free, and one
//   "Unlock Pro" capsule that opens the paywall ABOUT this entry point.
// - After a purchase the blur lifts (10 → 0 over 300ms, ease-out) and the caller carries on.
//
// Sizes: `.page` (a whole surface), `.card` (one block), `.row` (a ghost row).

enum LockSize: Equatable { case page, card, row }

struct LockedPreview<Sharp: View, Locked: View>: View {
    let size: LockSize
    let entry: LockEntry
    let line: String
    let keeps: String
    var unlocked = false
    /// The fade's target colour: the canvas for pages, the card for cards.
    var surface: Color? = nil
    /// A stamp drawn on top of the blur (e.g. "PREVIEW" over a blurred page), never blurred.
    var stamp: String? = nil
    /// Side inset of a `.row` lock's line and button (0 inside a List row, which insets already).
    var rowInset: CGFloat = 16
    var onUnlock: () -> Void
    @ViewBuilder var sharp: () -> Sharp
    @ViewBuilder var locked: () -> Locked

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reported = false

    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }
    private var blur: CGFloat { unlocked ? 0 : (size == .row ? 4 : 10) }
    private var motion: Animation { reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.3) }

    var body: some View {
        Group {
            switch size {
            case .row: row
            case .page, .card: block
            }
        }
        .animation(motion, value: unlocked)
        .onAppear {
            guard !unlocked, !reported else { return }
            reported = true
            Analytics.lockPreviewShown(entry: entry)
        }
    }

    private var block: some View {
        VStack(alignment: .leading, spacing: 0) {
            sharp()
            ZStack(alignment: .top) {
                locked()
                    .blur(radius: blur)
                    .allowsHitTesting(unlocked)
                    .accessibilityHidden(!unlocked)
                if !unlocked {
                    let fill = surface ?? colors.background
                    VStack(spacing: 0) {
                        LinearGradient(colors: [fill.opacity(0), fill.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 48)
                        fill.opacity(0.85)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
                    cta
                        .padding(.top, size == .page ? 72 : 40)
                        .transition(.opacity)
                    if let stamp {
                        LockStamp(text: stamp)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 14)
                            .padding(.trailing, 18)
                            .transition(.opacity)
                    }
                }
            }
            .clipped()
        }
    }

    private var cta: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(line)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.textPrimary)
                    .accessibilityIdentifier("lock.line")
                Text(keeps)
                    .font(.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .accessibilityIdentifier("lock.keeps")
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            UnlockProButton(entry: entry, action: onUnlock)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lock.\(entry.rawValue)")
    }

    private var row: some View {
        VStack(spacing: 0) {
            locked()
                .blur(radius: blur)
                .opacity(unlocked ? 1 : 0.6)
                .allowsHitTesting(unlocked)
                .accessibilityHidden(!unlocked)
            if !unlocked {
                let layout = dts.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                    : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line).font(.subheadline.weight(.semibold)).foregroundStyle(colors.textPrimary)
                            .accessibilityIdentifier("lock.line")
                        Text(keeps).font(.footnote).foregroundStyle(colors.textSecondary)
                            .accessibilityIdentifier("lock.keeps")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    UnlockProButton(entry: entry, action: onUnlock).fixedSize()
                }
                .padding(.horizontal, rowInset)
                .padding(.top, 4)
                .padding(.bottom, 14)
                .transition(.opacity)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("lock.\(entry.rawValue)")
            }
        }
    }
}

extension LockedPreview where Sharp == EmptyView {
    /// A row (or block) with nothing kept sharp.
    init(size: LockSize, entry: LockEntry, line: String, keeps: String, unlocked: Bool = false, surface: Color? = nil,
         rowInset: CGFloat = 16, onUnlock: @escaping () -> Void, @ViewBuilder content: @escaping () -> Locked) {
        self.init(size: size, entry: entry, line: line, keeps: keeps, unlocked: unlocked, surface: surface,
                  rowInset: rowInset, onUnlock: onUnlock, sharp: { EmptyView() }, locked: content)
    }
}

/// The one "Unlock Pro" action: a 44pt primary capsule with `lock.fill`, spelled the same
/// everywhere.
struct UnlockProButton: View {
    var entry: LockEntry
    var title = "Unlock Pro"
    var fullWidth = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            // Glyph and words drawn explicitly: some containers (List rows) render a Label as
            // icon-only, which hid "Unlock Pro" in Settings.
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").accessibilityHidden(true)
                Text(title)
            }
        }
        .buttonStyle(ProUnlockButtonStyle(fullWidth: fullWidth))
        .accessibilityLabel(title)
        .accessibilityHint("Opens LandlordHours Pro")
        .accessibilityIdentifier("lock.unlock")
    }
}

struct ProUnlockButtonStyle: ButtonStyle {
    var fullWidth = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        configuration.label
            .font(fullWidth ? AppTypography.buttonLarge : .subheadline.weight(.semibold))
            .foregroundStyle(colors.onAction)
            .lineLimit(fullWidth ? 2 : 1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: fullWidth ? 52 : 44)
            .background(Capsule().fill(colors.action))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : AppAnimation.feedback, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Tinted (44pt, action on actionSurface, 15 semibold). Settings' "See Pro".
struct ProTintedButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let colors = AdaptiveColors(colorScheme: colorScheme)
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(colors.action)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(Capsule().fill(colors.actionSurface))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : AppAnimation.feedback, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

// MARK: - The one paywall host

/// Installed once on the shell. Presents `ProPaywallPresenter.shared.request` full screen.
struct ProPaywallHost: ViewModifier {
    @ObservedObject var presenter: ProPaywallPresenter = .shared
    @EnvironmentObject private var viewModel: AppViewModel

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $presenter.request) { request in
            PaywallView(
                context: request.context,
                entry: request.entry,
                year: request.year,
                propertyName: request.propertyName,
                confirmedHours: request.confirmedHours,
                onUnlocked: request.onUnlocked,
                onClose: { presenter.dismiss() }
            )
            .environmentObject(viewModel)
        }
    }
}

extension View {
    /// Lets any screen open the one paywall through `ProPaywallPresenter.shared`.
    func proPaywallHost() -> some View { modifier(ProPaywallHost()) }

    /// Presents the paywall from a local `PaywallContext?`/request binding as a full-screen cover.
    func proPaywall(_ request: Binding<ProPaywallRequest?>) -> some View {
        modifier(LocalPaywallCover(request: request))
    }
}

private struct LocalPaywallCover: ViewModifier {
    @Binding var request: ProPaywallRequest?
    @EnvironmentObject private var viewModel: AppViewModel

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $request) { request in
            PaywallView(
                context: request.context,
                entry: request.entry,
                year: request.year,
                propertyName: request.propertyName,
                confirmedHours: request.confirmedHours,
                onUnlocked: request.onUnlocked,
                onClose: { self.request = nil }
            )
            .environmentObject(viewModel)
        }
    }
}

/// A drafting-ink stamp, unblurred, on top of a locked preview (≥5:1 on the canvas and card).
struct LockStamp: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let ink = AdaptiveColors(colorScheme: colorScheme).draftingInk
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1.5)
            .foregroundStyle(ink)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 4).fill(AdaptiveColors(colorScheme: colorScheme).backgroundSecondary))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(ink, lineWidth: 1.5))
            .rotationEffect(.degrees(-6))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityIdentifier("lock.stamp")
    }
}
