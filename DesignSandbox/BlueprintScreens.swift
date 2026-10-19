import SwiftUI

// MARK: - Today hero

struct BlueprintHero: View {
    @Environment(MockStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shownHours: Double = 0
    @State private var count: Int = 0
    @State private var board: CGPoint? = nil
    @State private var boardScale: CGFloat = 1
    @State private var boardOpacity = 1.0
    @State private var boardText = ""
    @State private var boardTag = false
    @State private var glow = 0.0
    @State private var landTick = 0
    var onMilestone: () -> Void = {}

    private var pendingHours: Double { store.pending.reduce(0) { $0 + ($1.hours ?? 0) } }

    private var status: (String, Color, String) {
        if !store.hasProperties || store.hoursLogged == 0 { return ("Getting started", OnHero.secondary, "circle.dashed") }
        return store.pace >= 0
            ? ("On pace · \(fmtDur(store.pace)) ahead", OnHero.positive, "arrow.up.circle.fill")
            : ("Behind by \(fmtDur(-store.pace))", OnHero.caution, "exclamationmark.circle.fill")
    }

    /// Stage words instead of a numeric ruler (the house's stages are not linear in hours).
    private var stage: String {
        let h = Double(count)
        if h < 100 { return "Foundation · \(Int(100 - h))h to go" }
        if h < 500 { return "Frame going up · roof at 500h" }
        if h < 750 { return "Roof on · keys at 750h" }
        return "Keys in the door"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            BlueprintPaper()
            GeometryReader { g in
                let hs = min(g.size.height * 0.96, g.size.width * 0.57)
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("2026 · REPS goal")
                            .font(.footnote.weight(.semibold)).textCase(.uppercase).tracking(0.3)
                            .foregroundStyle(OnHero.secondary)
                        Text("\(count)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            // Integer steps, no per-digit roll: rolling digits flash wrong numbers (498 -> 599 -> 500).
                            .contentTransition(.identity)
                            .padding(.top, 2)
                        Text("of 750h").font(.title3.weight(.medium)).foregroundStyle(OnHero.secondary)
                        Spacer()
                        Label(status.0, systemImage: status.2)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(status.1)
                            .lineLimit(2)
                            .frame(width: g.size.width - hs - 24, alignment: .leading)
                        Text(stage)
                            .font(.footnote).foregroundStyle(OnHero.secondary)
                            .lineLimit(2)
                            .frame(width: g.size.width - hs - 24, alignment: .leading)
                    }
                    .padding(20)
                    .frame(maxHeight: .infinity, alignment: .topLeading)

                    BlueprintHouse(hours: shownHours, hatchHours: shownHours + pendingHours, glowBand: glow, showScale: false)
                        .frame(width: hs, height: hs)
                        .position(x: g.size.width - hs / 2 + 2, y: g.size.height - hs / 2 + 4)

                    if let board {
                        Clapboard(label: boardText, tagShown: boardTag)
                            .frame(width: hs * 0.56, height: 13)
                            .scaleEffect(x: 1, y: boardScale)
                            .rotationEffect(.degrees(-6))
                            .position(board)
                            .opacity(boardOpacity)
                    }
                }
                .onChange(of: store.hoursLogged) { old, new in
                    guard new > old else { shownHours = new; count = Int(new); return }
                    let houseCX = g.size.width - hs / 2 + 2
                    let lineY = g.size.height - hs + hs * BlueprintHouse.buildY(new) + 4
                    boardText = "+\(fmtDur(new - old))"
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))     // let a sheet finish dismissing
                        if reduce {
                            withAnimation(.easeInOut(duration: 0.2)) { shownHours = new; count = Int(new) }
                            landTick += 1
                            if old < 500 && new >= 500 { onMilestone() }
                            return
                        }
                        // 1. slide in and settle
                        boardTag = false; boardOpacity = 1; boardScale = 1
                        // Enters from above the house, inside the illustration's bounds (never over the text column).
                        board = CGPoint(x: houseCX + hs * 0.05, y: lineY - hs * 0.32)
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) { board = CGPoint(x: houseCX, y: lineY) }
                        try? await Task.sleep(for: .milliseconds(320))
                        // 2. land: haptic, tag, the house takes the course, count up
                        landTick += 1
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { boardTag = true }
                        // Critically damped: the house only ever gains, never overshoots back.
                        withAnimation(.spring(response: 0.5, dampingFraction: 1.0)) { shownHours = max(shownHours, new) }
                        withAnimation(.easeOut(duration: 0.15)) { glow = 1 }
                        let from = count, to = Int(new)
                        let steps = max(1, to - from)
                        for i in 1...steps {
                            withAnimation(.snappy(duration: 0.12)) { count = from + i }
                            try? await Task.sleep(for: .milliseconds(max(40, 300 / steps)))
                        }
                        // 3. absorb into the house (≤700 ms after landing) and finish
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            boardScale = 0.15; boardOpacity = 0; boardTag = false; glow = 0
                        }
                        try? await Task.sleep(for: .milliseconds(330))
                        board = nil
                        if old < 500 && new >= 500 {
                            try? await Task.sleep(for: .milliseconds(250))
                            onMilestone()
                        }
                    }
                }
            }
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: BP.blueprint.opacity(0.25), radius: 16, y: 8)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 1), trigger: landTick)
        .onAppear { shownHours = store.hoursLogged; count = Int(store.hoursLogged) }
    }
}

// MARK: - Category tools (materials washes)

struct ToolIcon: View {
    let cat: Category
    var size: CGFloat = 36
    var body: some View {
        let m = BP.material(cat)
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(m.opacity(0.12))
            .frame(width: size, height: size)
            .overlay {
                if let img = conceptImage("bp-tool-\(cat.rawValue)") {
                    img.resizable().scaledToFit().padding(size * 0.06)
                } else {
                    // Neutral placeholder: never mix flat SF Symbols into the 3D set.
                    RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                        .strokeBorder(BP.drafting.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .padding(size * 0.18)
                }
            }
    }
}

struct HouseTypeThumb: View {
    let prop: Prop
    var size: CGFloat = 40
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(BP.blueprint)
            .frame(width: size, height: size)
            .overlay {
                if let img = conceptImage(prop.key == "pine" ? "bp-type-cabin" : prop.key == "oak" ? "bp-type-duplex" : "bp-type-single") {
                    img.resizable().scaledToFit().padding(size * 0.06)
                } else {
                    BlueprintHouse(hours: prop.key == "pine" ? 600 : 300, showScale: false).padding(2)
                }
            }
    }
}

// MARK: - 500h milestone

struct BlueprintMilestone: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dismiss) private var dismiss
    @State private var roofDrop: CGFloat = -34
    @State private var roofFill = 0.0
    @State private var plaque = false
    @State private var landed = 0
    @State private var shown = false

    var body: some View {
        ZStack {
            BlueprintPaper().ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Continue") { dismiss() }
                        .accessibilityIdentifier("milestone-continue")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BP.blueprint)
                        .padding(.horizontal, 18).frame(height: 40)
                        .background(.white, in: Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Text("Roof's on.")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 20)
                    .padding(.bottom, 26)       // the roof's drop path (34 pt) stays clear of the title
                    .zIndex(1)

                ZStack(alignment: .topLeading) {
                    BlueprintHouse(hours: 500, roofDrop: roofDrop, roofFill: roofFill, showScale: false)
                        .frame(width: 290, height: 290)
                    Plaque(number: 500)
                        .scaleEffect(plaque ? 1 : 0.6, anchor: .bottom)
                        .opacity(plaque ? 1 : 0)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 3)
                        .position(x: 290 * 0.80, y: 290 * 0.80)     // standing on the plinth's front-right edge
                }
                .frame(width: 290, height: 290)
                .padding(.top, 8)

                Text("500 confirmed hours in 2026")
                    .font(.title3.weight(.semibold)).foregroundStyle(.white)
                    .padding(.top, 18)
                Text("Material participation test 1 met, based on your records.")
                    .font(.body).foregroundStyle(OnHero.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36).padding(.top, 6)
                Text("October 18, 2026")
                    .font(.footnote.weight(.semibold)).textCase(.uppercase).tracking(0.4)
                    .foregroundStyle(BP.drafting)
                    .padding(.top, 14)
                Spacer()
                Button {} label: { Label("Share", systemImage: "square.and.arrow.up") }
                    .buttonStyle(HeroPill())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: landed)
        .sensoryFeedback(.success, trigger: shown)
        .preferredColorScheme(.dark)      // light status-bar content over the blueprint bleed
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            shown = true
            if reduce {
                roofDrop = 0
                withAnimation(.easeInOut(duration: 0.3)) { roofFill = 1; plaque = true }
                return
            }
            withAnimation(.easeOut(duration: 0.25)) { roofFill = 0.35 }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { roofDrop = 0 }
            try? await Task.sleep(for: .milliseconds(380))
            landed += 1
            withAnimation(.easeOut(duration: 0.6)) { roofFill = 1 }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { plaque = true }
        }
    }
}

struct Plaque: View {
    var number: Int
    var body: some View {
        Group {
            if let img = conceptImage("bp-plaque-blank") {
                ZStack {
                    img.resizable().scaledToFit()
                    VStack(spacing: -2) {
                        Text("\(number)").font(.system(size: 30, weight: .heavy, design: .serif))
                        Text("HOURS").font(.system(size: 8, weight: .bold)).tracking(1.6)
                    }
                    .foregroundStyle(Color(hex: 0x5C4316).opacity(0.85))
                    .shadow(color: .white.opacity(0.5), radius: 0, x: 0, y: 1)
                    .offset(x: 2, y: -2)
                    .rotationEffect(.degrees(-4))
                }
                .frame(width: 112, height: 112)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0xF2D78C), BP.brass, Color(hex: 0xA9833A)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(hex: 0x8C6A2C), lineWidth: 1.5).padding(4)
                    VStack(spacing: 0) {
                        Text("\(number)").font(.system(size: 26, weight: .heavy, design: .serif)).foregroundStyle(Color(hex: 0x5C4316))
                        Text("HOURS").font(.system(size: 8, weight: .bold)).tracking(1.5).foregroundStyle(Color(hex: 0x5C4316))
                    }
                }
                .frame(width: 84, height: 64)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 4)
            }
        }
    }
}

// MARK: - Welcome

struct BlueprintWelcome: View {
    @State private var backfill = false
    var body: some View {
        ZStack {
            BlueprintPaper().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if let img = conceptImage("bp-welcome") {
                        img.resizable().scaledToFit()
                    } else {
                        BlueprintHouse(hours: 360, showScale: false)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .padding(.top, 20)

                Text("Every hour\nbuilds the house.")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(.white)
                    .padding(.top, 20)
                Text("LandlordHours finds the hours you already spend on your rentals. Each one you confirm goes up on the frame, until 750 puts the keys in the door.")
                    .font(.body)
                    .foregroundStyle(OnHero.secondary)
                    .padding(.top, 12)
                HStack(spacing: 18) {
                    stage("square.stack.3d.down.forward.fill", "100h", "Foundation")
                    stage("house.fill", "500h", "Roof")
                    stage("key.fill", "750h", "Keys")
                }
                .padding(.top, 22)
                Spacer()
                Button("Get started") { backfill = true }
                    .buttonStyle(HeroPill())
                    .accessibilityIdentifier("welcome-start")
                Text("Your records stay on your iPhone and in your iCloud.")
                    .font(.footnote).foregroundStyle(OnHero.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 14).padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $backfill) { BlueprintBackfill() }
    }
    private func stage(_ sym: String, _ h: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: sym).font(.system(size: 15, weight: .semibold)).foregroundStyle(BP.drafting)
            VStack(alignment: .leading, spacing: 0) {
                Text(h).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                Text(label).font(.caption).foregroundStyle(OnHero.secondary)
            }
        }
    }
}

// MARK: - Day-1 backfill reveal

struct BlueprintBackfill: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var lines = 0.0
    @State private var hatch = 0.0
    @State private var tick = 0
    var body: some View {
        ZStack {
            BlueprintPaper().ignoresSafeArea()
            VStack(spacing: 0) {
                Text("Looking back 90 days")
                    .font(.footnote.weight(.semibold)).textCase(.uppercase).tracking(0.4)
                    .foregroundStyle(BP.drafting)
                    .padding(.top, 40)
                Text("\(Int(hatch))h found")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: hatch))
                    .padding(.top, 8)
                Text("from your calendar")
                    .font(.title3).foregroundStyle(OnHero.secondary)
                BlueprintHouse(hours: 0, hatchHours: hatch, linework: lines, showScale: false)
                    .frame(width: 320, height: 320)
                    .padding(.top, 16)
                Text("Nothing is saved until you confirm.")
                    .font(.body.weight(.semibold)).foregroundStyle(.white)
                    .padding(.top, 8)
                Text("Hatched storeys are suggestions. They turn solid only when you say they were work.")
                    .font(.subheadline).foregroundStyle(OnHero.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 40).padding(.top, 4)
                Spacer()
                Button("Review 14 suggestions") {}.buttonStyle(HeroPill()).padding(.horizontal, 24).padding(.bottom, 12)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: tick)
        .preferredColorScheme(.dark)
        .task {
            if reduce { lines = 1; hatch = 212; return }
            // Sketch-in 0.15–0.95 s, hatched hours 0.55–2.05 s: done inside 2.5 s.
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeOut(duration: 0.8)) { lines = 1 }
            try? await Task.sleep(for: .milliseconds(400))
            for step in 1...20 {
                let v = 212.0 * Double(step) / 20
                withAnimation(.linear(duration: 0.075)) { hatch = v }
                if Int(v) / 50 > tick { tick = Int(v) / 50 }
                try? await Task.sleep(for: .milliseconds(75))
            }
        }
    }
}

// MARK: - Empty lot

struct EmptyLot: View {
    @State private var flutter = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        Group {
            if let img = conceptImage("bp-empty-lot") {
                img.resizable().scaledToFit()
            } else {
                GeometryReader { g in
                    let s = g.size.width
                    ZStack(alignment: .topLeading) {
                        HouseLines().stroke(BP.drafting.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        Path { p in p.move(to: .init(x: s * 0.08, y: s * 0.9)); p.addLine(to: .init(x: s * 0.92, y: s * 0.9)) }
                            .stroke(BP.drafting, lineWidth: 1.5)
                        // Surveyor's stake + flag
                        Rectangle().fill(BP.timber).frame(width: 4, height: s * 0.24).position(x: s * 0.5, y: s * 0.78)
                        Path { p in p.move(to: .init(x: 0, y: 0)); p.addLine(to: .init(x: s * 0.14, y: s * 0.035)); p.addLine(to: .init(x: 0, y: s * 0.07)); p.closeSubpath() }
                            .fill(Color(hex: 0xFF8A3D))
                            .frame(width: s * 0.14, height: s * 0.07)
                            .rotation3DEffect(.degrees(flutter ? 0 : 25), axis: (x: 0, y: 1, z: 0), anchor: .leading)
                            .position(x: s * 0.5 + s * 0.07 + 2, y: s * 0.69)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
        .onAppear {
            guard !reduce else { flutter = true; return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4).delay(0.4)) { flutter = true }
        }
    }
}

struct BlueprintEmptyHero: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            BlueprintPaper()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("2026 · REPS goal").font(.footnote.weight(.semibold)).textCase(.uppercase).tracking(0.3).foregroundStyle(OnHero.secondary)
                    Text("0").font(.system(size: 56, weight: .bold, design: .rounded)).foregroundStyle(.white).padding(.top, 2)
                    Text("of 750h").font(.title3.weight(.medium)).foregroundStyle(OnHero.secondary)
                    Spacer()
                    Text("An empty lot.").font(.headline).foregroundStyle(.white)
                    Text("Add a property and every hour you confirm goes up on it.")
                        .font(.footnote).foregroundStyle(OnHero.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                EmptyLot().frame(width: 164, height: 164).padding(.trailing, 16).padding(.bottom, 16)
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - Live Activity (mock of system UI)

struct BlueprintLiveActivity: View {
    var start: Date
    var body: some View {
        HStack(spacing: 12) {
            BlueprintHouse(hours: 212, showScale: false)
                .frame(width: 56, height: 56)
                .background(BP.blueprintDeep, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Pine Cabin · Repairs").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text(timerInterval: start...start.addingTimeInterval(8 * 3600), countsDown: false)
                    .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(BP.drafting)
                Text("Plumber visit · ends 11:00").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text("212h").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text("Stop").font(.system(size: 14, weight: .semibold)).foregroundStyle(BP.blueprint)
                    .padding(.horizontal, 14).frame(height: 30).background(.white, in: Capsule())
            }
        }
        .padding(14)
        .background {
            ZStack {
                BlueprintPaper()
                LinearGradient(colors: [.clear, .black.opacity(0.15)], startPoint: .top, endPoint: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

// MARK: - Inbox banner on blueprint

struct BlueprintInboxBanner: View {
    @Environment(MockStore.self) private var store
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if let img = conceptImage("bp-rolled-blueprint") {
                    img.resizable().scaledToFit()
                } else {
                    ZStack {
                        ToolIcon(cat: .repairs, size: 34).offset(x: -14, y: 8)
                        ToolIcon(cat: .leasing, size: 34).offset(x: 14, y: -10)
                    }
                }
            }
            .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text("14 things from the last 90 days")
                    .font(.body.weight(.semibold)).foregroundStyle(.white)
                Text("Confirm the ones that were work and they go up on the house.")
                    .font(.subheadline).foregroundStyle(OnHero.secondary)
                HStack(spacing: 6) {
                    Text("\(store.pendingCount)").font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(store.pendingCount)))
                    Text("to confirm").font(.subheadline).foregroundStyle(OnHero.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(BlueprintPaper().clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)))
    }
}

/// The newest course of the house: a timber clapboard with grain and nail heads.
struct Clapboard: View {
    var label: String
    var tagShown: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(LinearGradient(colors: [Color(hex: 0xF0BE7A), BP.timber, BP.timberDark], startPoint: .top, endPoint: .bottom))
            Path { p in
                p.move(to: .init(x: 6, y: 4)); p.addCurve(to: .init(x: 120, y: 5), control1: .init(x: 40, y: 2), control2: .init(x: 80, y: 7))
                p.move(to: .init(x: 30, y: 9)); p.addCurve(to: .init(x: 150, y: 8), control1: .init(x: 70, y: 11), control2: .init(x: 110, y: 6))
            }.stroke(Color(hex: 0x9E6A2E).opacity(0.35), lineWidth: 0.8)
            HStack {
                Circle().fill(Color(hex: 0x6E4A20)).frame(width: 3, height: 3)
                Spacer()
                Circle().fill(Color(hex: 0x6E4A20)).frame(width: 3, height: 3)
            }
            .padding(.horizontal, 6)
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
        .overlay(alignment: .top) {
            Text(label)
                .font(.caption.weight(.heavy)).monospacedDigit()
                .foregroundStyle(BP.blueprint)
                .padding(.horizontal, 8).frame(height: 20)
                .background(.white, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                .offset(y: -26)
                .scaleEffect(tagShown ? 1 : 0.6, anchor: .bottom)
                .opacity(tagShown ? 1 : 0)
        }
    }
}
