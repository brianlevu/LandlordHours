import SwiftUI

// MARK: - System permission prompts (faithful mocks, tagged "mock of system UI")

struct OnbSystemPrompt: View {
    let kind: OnbPrompt
    @Bindable var flow: OnbFlow
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.onbScheme) private var scheme

    private var title: String {
        kind == .calendar ? "“LandlordHours” Would Like Full Access to Your Calendar"
                          : "“LandlordHours” Would Like to Send You Notifications"
    }
    private var message: String {
        kind == .calendar
            ? "LandlordHours reads event titles on your iPhone to suggest rental work, like a plumber visit. Nothing is saved until you confirm it."
            : "Notifications may include alerts, sounds, and icon badges. These can be configured in Settings."
    }
    private var allow: String { kind == .calendar ? "Allow Full Access" : "Allow" }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
            VStack(spacing: 10) {
                if flow.mockLabels { MockTag(onDark: true) }
                VStack(spacing: 0) {
                    VStack(spacing: 6) {
                        Text(title).font(.headline).multilineTextAlignment(.center)
                        Text(message).font(.footnote).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 18)
                    VStack(spacing: 8) {
                        button(allow, primary: true) { resolve(true) }
                        button("Don’t Allow", primary: false) { resolve(false) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .frame(width: 300)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
            }
            .environment(\.colorScheme, scheme)
        }
        .accessibilityAddTraits(.isModal)
    }

    private func button(_ label: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.body.weight(primary ? .semibold : .regular))
                .foregroundStyle(primary ? .white : .primary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(primary ? Color(uiColor: .systemBlue) : Color.primary.opacity(0.08), in: Capsule())
                .scaleEffect(primary && flow.promptPressed ? 0.96 : 1)
                .opacity(primary && flow.promptPressed ? 0.8 : 1)
        }
        .buttonStyle(Pressable())
    }

    private func resolve(_ granted: Bool) {
        withAnimation(.easeOut(duration: 0.2)) { flow.prompt = nil; flow.promptPressed = false }
        if kind == .calendar {
            flow.calendar = granted ? .allowed : .denied
            if granted { flow.startScan(reduce: reduce) }
        } else {
            flow.notify = granted
        }
        flow.next(reduce: reduce)
    }
}

// MARK: - Today landing (after Staked, after a skip, and behind What's new)

struct OnbToday: View {
    @Bindable var flow: OnbFlow
    @Environment(\.onbScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var hours: Double { flow.cohort == .upgrade ? flow.upgradeHours : 0 }
    private var empty: Bool { flow.cohort == .new && flow.skippedProperty }
    private var goalLine: String {
        switch flow.goal {
        case .mp500, .mp100: "2026 · Material participation"
        case .record: "2026 · Record"
        default: "2026 · REPS goal"
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PC.canvas.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(initials)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PC.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(PC.card, in: Circle())
                        Spacer()
                        Image(systemName: "chart.bar")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(PC.textPrimary)
                            .frame(width: 44, height: 44)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).prodDisplay().foregroundStyle(PC.textPrimary)
                        Text(subtitle).font(.subheadline).foregroundStyle(PC.textSecondary)
                    }
                    hero
                    if flow.suggestions > 0 && !empty { toConfirm }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            OnbTabBar(badge: flow.inboxBadge)
        }
        .environment(\.colorScheme, scheme)
    }

    private var initials: String { flow.cohort == .upgrade ? "PC" : (empty ? "LH" : "OS") }
    private var title: String {
        if flow.cohort == .upgrade { return "Today’s work" }
        return empty ? "Add your first property" : "Log your first hour"
    }
    private var subtitle: String {
        if flow.cohort == .upgrade { return "312h counted toward 750 hours this year." }
        if empty { return "Every hour you log starts with a place." }
        return "\(flow.name.isEmpty ? "Oak Street duplex" : flow.name) is staked. Confirm what we found, or log something new."
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            HouseBlueprintPaper()
            GeometryReader { g in
                let hs = min(g.size.width * (empty ? 0.5 : 0.6), g.size.height * 0.9)
                ZStack(alignment: .topLeading) {
                    ZStack {
                        HouseArtView(keyframe: HouseProgress.keyframe(for: hours), canvas: .blueprintHero)
                        if !empty && flow.cohort == .new && flow.foundHours > 0 {
                            HouseHatchedView(keyframe: HouseProgress.keyframe(for: Double(max(100, flow.foundHours)) + 0.0),
                                             subtracting: .k00_lot, canvas: .blueprintHero)
                                .transition(.opacity)
                        }
                        if flow.cohort == .new && !empty {
                            OnbScene.MiniStake(name: flow.name.isEmpty ? "Oak Street duplex" : flow.name)
                        }
                    }
                    .frame(width: hs, height: hs)
                    .position(x: g.size.width - hs / 2 + 6, y: g.size.height - hs / 2 + 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(goalLine).drafting(HouseTokens.drafting)
                        Text("\(Int(hours))")
                            .font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.top, 4)
                        Text(flow.goalHours.map { "of \($0)h" } ?? "hours logged")
                            .font(.title3.weight(.medium)).foregroundStyle(HouseTokens.onHeroSecondary)
                        Spacer(minLength: 8)
                        heroFooter
                    }
                    .padding(20)
                    .frame(maxWidth: g.size.width * (empty ? 0.56 : 0.5), maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder private var heroFooter: some View {
        if empty {
            Text("An empty lot.").font(.headline).foregroundStyle(.white)
            Text("Add a property and every hour you confirm goes up on it.")
                .font(.footnote).foregroundStyle(HouseTokens.onHeroSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {} label: {
                Label("Add property", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PC.brand)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(Pressable())
            .padding(.top, 10)
        } else if flow.cohort == .upgrade {
            Text("Frame going up").font(.headline).foregroundStyle(.white)
            Text("Roof at 500h").font(.footnote).foregroundStyle(HouseTokens.onHeroSecondary)
        } else if flow.foundHours > 0 {
            Text("\(flow.foundHours)h found")
                .font(.headline).foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(flow.foundHours)))
            Text("Hatched until you confirm").font(.footnote).foregroundStyle(HouseTokens.onHeroSecondary)
        } else {
            Text("No hours logged yet").font(.headline).foregroundStyle(.white)
            Text("Foundation at 100h").font(.footnote).foregroundStyle(HouseTokens.onHeroSecondary)
        }
    }

    private var toConfirm: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("To confirm").font(.headline).foregroundStyle(PC.textPrimary)
                Spacer()
                Text("\(flow.suggestions)")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(PC.action)
                    .contentTransition(.numericText(value: Double(flow.suggestions)))
            }
            .padding(.bottom, 4)
            let place = flow.name.isEmpty ? "Oak Street duplex" : flow.name
            OnbSampleRow(hours: "2h", tool: "bp_tool_repairs_36", when: "Calendar · Wed 9–11", title: "Plumber at \(place)", category: "Repairs", categoryColor: BP.material(.repairs))
            Divider().overlay(PC.border).padding(.leading, 64)
            OnbSampleRow(hours: "1h", tool: "bp_tool_showing_36", when: "Calendar · Sat 10–11", title: "Showing at \(place)", category: "Leasing", categoryColor: BP.material(.leasing))
        }
        .padding(16)
        .background(PC.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .transition(.opacity)
    }
}

extension OnbScene {
    /// The stake + flag, in the hero's keyframe camera.
    struct MiniStake: View {
        var name: String
        var body: some View {
            GeometryReader { g in
                let s = g.size.width
                let b = OnbScene.stakeBase
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(HouseTokens.timber)
                        .frame(width: 3, height: s * 0.2)
                        .position(x: s * b.x, y: s * b.y - s * 0.1)
                    Color.clear.frame(width: 1, height: 1)
                        .overlay(alignment: .leading) { Flag(name: name).frame(height: 16).fixedSize().scaleEffect(0.85, anchor: .leading) }
                        .position(x: s * b.x + 1.5, y: s * b.y - s * 0.2 + 8)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

struct OnbTabBar: View {
    var badge: Int
    @Environment(\.colorScheme) private var cs
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                item("Today", "sun.max.fill", on: true)
                item("Inbox", "tray", on: false, badge: badge)
                item("Records", "list.bullet.rectangle", on: false)
                item("Properties", "house", on: false)
            }
            .padding(4)
            .glassEffect(.regular.tint(cs == .dark ? Color(hex: 0x141C3F, alpha: 0.7) : Color.white.opacity(0.78)), in: Capsule())
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(PC.action)
                .frame(width: 62, height: 62)
                .glassEffect(.regular.tint(cs == .dark ? Color(hex: 0x141C3F, alpha: 0.7) : Color.white.opacity(0.78)), in: Circle())
        }
        .padding(.horizontal, 20)
    }

    private func item(_ t: String, _ sym: String, on: Bool, badge: Int = 0) -> some View {
        VStack(spacing: 3) {
            Image(systemName: sym)
                .font(.system(size: 19, weight: .medium))
                .frame(height: 24)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(value: Double(badge)))
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Color(uiColor: .systemRed), in: Capsule())
                            .offset(x: 12, y: -6)
                    }
                }
            Text(t).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(on ? PC.action : PC.textPrimary)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background { if on { Capsule().fill(PC.textPrimary.opacity(0.08)) } }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}

// MARK: - "212h found" reveal: a sheet over Today, once, when the count settles

struct OnbFoundReveal: View {
    @Bindable var flow: OnbFlow
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dismiss) private var dismiss
    @State private var lines = 0.0
    @State private var shown = 0.0

    var body: some View {
        ZStack {
            HouseBlueprintPaper().ignoresSafeArea()
            VStack(spacing: 0) {
                Text("Looking back 90 days").drafting(HouseTokens.drafting).padding(.top, 34)
                Text("\(Int(shown))h found")
                    .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: shown))
                    .padding(.top, 8)
                Text("from your calendar").font(.title3).foregroundStyle(HouseTokens.onHeroSecondary)
                ZStack {
                    HouseArtView(keyframe: .k00_lot, canvas: .blueprintHero).opacity(lines)
                    HouseHatchedView(keyframe: .k06_frame050, subtracting: .k00_lot, canvas: .blueprintHero)
                        .mask(HouseRisingMask(progress: shown / 212))
                    OnbScene.MiniStake(name: flow.name.isEmpty ? "Oak Street duplex" : flow.name)
                }
                .frame(width: 300, height: 300)
                .padding(.top, 8)
                Text("Nothing is saved until you confirm.")
                    .font(.body.weight(.semibold)).foregroundStyle(.white)
                Text("Hatched storeys are suggestions. They turn solid only when you say they were work.")
                    .font(.subheadline).foregroundStyle(HouseTokens.onHeroSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36).padding(.top, 4)
                Spacer(minLength: 12)
                Button("Review \(flow.suggestions) suggestions") { dismiss() }
                    .buttonStyle(ProdHeroPill())
                    .padding(.horizontal, 24)
                Button("Later") { dismiss() }
                    .buttonStyle(ProdLink(color: .white))
                    .padding(.bottom, 8)
            }
        }
        .task {
            if reduce { lines = 1; shown = 212; return }
            withAnimation(.easeOut(duration: 0.6)) { lines = 1 }
            try? await Task.sleep(for: .milliseconds(300))
            for step in 1...16 {
                withAnimation(.linear(duration: 0.07)) { shown = 212 * Double(step) / 16 }
                try? await Task.sleep(for: .milliseconds(70))
            }
        }
    }
}

// MARK: - What's new for upgraders · 1 "Your hours now build a house."

struct OnbWhatsNewHouseStep: View {
    @Bindable var flow: OnbFlow
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        OnbStepScaffold(title: "Your hours now build a house.") {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(Int(flow.upgradeHours))h · frame going up · roof at 500h")
                    .drafting(PC.draftingInk)
                Text("Nothing about your records changed. Same hours, same PDF.")
                    .font(.body)
                    .foregroundStyle(PC.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Each hour you confirm from now on goes up on the frame.")
                    .font(.body)
                    .foregroundStyle(PC.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            Button("Continue") { flow.next(reduce: reduce) }
                .buttonStyle(ProdPrimaryPill())
                .accessibilityIdentifier("onb-primary")
        }
    }
}
