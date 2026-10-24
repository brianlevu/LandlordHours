import SwiftUI
import UIKit

#if DEBUG
// MARK: - Inbox (§2.12 secondary screen): the empty state is the world

struct PorchInboxScreen: View {
    let seed: PorchSeed
    let empty: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var removed: Set<String> = []
    @State private var confirmed: Set<String> = []
    @State private var confirmCount = 0
    @State private var sky = PorchSky.now()

    private var c: PorchColors { PorchColors(scheme) }
    private var open: [StdSuggestion] { empty ? [] : seed.std.suggestions.filter { !removed.contains($0.id) } }
    private var safeTop: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.safeAreaInsets.top ?? 59
    }

    var body: some View {
        Group {
            if open.isEmpty { emptyWorld } else { filled }
        }
        .modifier(PorchSkyStatusBar())
        .sensoryFeedback(.success, trigger: confirmCount)
    }

    // MARK: Empty: sky at the real clock, the dark house on the horizon

    private var emptyWorld: some View {
        GeometryReader { g in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: safeTop + (typeSize.isAccessibilitySize ? 8 : 40))
                    PorchHouse(lit: 0, sky: sky, size: typeSize.isAccessibilitySize ? 120 : 220)
                        .background(alignment: .bottom) {
                            Rectangle().fill(.white.opacity(0.35)).frame(width: g.size.width, height: 1)
                                .offset(y: -((typeSize.isAccessibilitySize ? 120 : 220) * 0.22))
                        }
                    Text(P("No hours to confirm."))
                        .font(.system(.title, design: .serif, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 28)
                        .accessibilityAddTraits(.isHeader)
                    Text(P("Calendar events and reminders that look like rental work show up here."))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                    Button(P("Log time")) {}
                        .buttonStyle(PorchPrimary(onSky: true))
                        .padding(.top, 28)
                        .frame(maxWidth: 280)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
                .frame(minHeight: g.size.height, alignment: .top)
            }
            .scrollIndicators(.hidden)
            .background {
                PorchSkyView(sky: sky, dark: scheme == .dark, height: g.size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom,
                             deepUntil: g.size.height + g.safeAreaInsets.top - 60)
                    .ignoresSafeArea()
            }
        }
        .ignoresSafeArea(edges: .top)
        .modifier(PorchHideTopEdge())
    }

    // MARK: Filled: the count on the sky, rows below the horizon in day groups

    private var filled: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Color.clear.frame(height: safeTop + 16)
                    Text(P("Inbox")).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "\(open.count)")
                            .font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText(value: Double(open.count)))
                        Text(P("to confirm")).font(.title3.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .accessibilityElement(children: .combine)
                    Text(StdCanon.nothingCounts).font(.subheadline).foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                    Color.clear.frame(height: 56)
                }
                .frame(maxWidth: .infinity)
                .background(alignment: .top) {
                    GeometryReader { g in
                        PorchSkyView(sky: sky, dark: scheme == .dark, height: g.size.height, deepUntil: g.size.height - 44)
                    }
                }
                .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.4)).frame(height: 1) }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(stdDayGroups(open), id: \.name) { group in
                        PorchSectionHeader(title: group.name).padding(.top, 20)
                        VStack(spacing: 0) {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { i, item in
                                if i > 0 { Rectangle().fill(c.border).frame(height: 0.5).padding(.leading, 50) }
                                PorchActionRow(item: item, confirmed: confirmed.contains(item.id)) { confirm(item) }
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(c.surface))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(c.border, lineWidth: 0.5))
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
        .background(c.ground)
        .ignoresSafeArea(edges: .top)
        .modifier(PorchHideTopEdge())
        .safeAreaInset(edge: .bottom) { batchBar }
    }

    @ViewBuilder private var batchBar: some View {
        let likely = open.filter(\.isLikely)
        if likely.count >= 2 {
            Button { for item in likely { confirm(item) } } label: {
                Text(StdCanon.confirmLikely(likely.count))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(c.onAction)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .modifier(PorchBatchStyle())
            // Leaves the trailing band to the "+" (44pt + 20pt edge + 12pt gap).
            .padding(.leading, 20).padding(.trailing, 84).padding(.bottom, 8)
        }
    }

    private func confirm(_ item: StdSuggestion) {
        guard !confirmed.contains(item.id) else { return }
        withAnimation(.easeOut(duration: 0.12)) { _ = confirmed.insert(item.id) }
        confirmCount += 1
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 620_000_000)
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.25, bounce: 0)) { _ = removed.insert(item.id) }
        }
    }
}

/// The pinned batch bar: glass (iOS 26) tinted action, else a solid action capsule.
struct PorchBatchStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let c = PorchColors(scheme)
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent).tint(c.action)
        } else {
            content.buttonStyle(PorchPrimary())
        }
    }
}
#endif
