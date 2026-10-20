import SwiftUI

// MARK: - §5 Siri / Shortcuts

/// App Shortcuts as the Shortcuts app and Spotlight show them. Tile colour: `.navy` (closest
/// ShortcutTileColor to blueprint #1E3FA6; `.purple` retired). Symbols are SF Symbols, as the
/// API requires. Destinations use 2.0 names: Today, Inbox, Records, Properties, Log time.
struct SFShortcutsPage: View {
    private let tiles: [(String, String)] = [
        ("Log time", "square.and.pencil"),
        ("To confirm", "tray.fill"),
        ("My hours", "house.fill"),
        ("Records", "list.bullet.rectangle.fill"),
    ]
    private let phrases: [String] = [
        "“Log time in LandlordHours”",
        "“What’s waiting in LandlordHours”",
        "“How many hours do I have in LandlordHours”",
        "“Show my records in LandlordHours”",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    SFAppIcon(size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LandlordHours").font(.system(size: 28, weight: .bold))
                        Text("4 shortcuts").font(.subheadline).foregroundStyle(LHB.textSecondary)
                    }
                }
                .padding(.top, 12)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(tiles, id: \.0) { t in tile(t.0, t.1) }
                }
                .padding(.top, 22)
                Text("Ask Siri").font(.footnote.weight(.semibold)).textCase(.uppercase).foregroundStyle(LHB.textSecondary)
                    .padding(.top, 28).padding(.leading, 4)
                VStack(spacing: 0) {
                    ForEach(Array(phrases.enumerated()), id: \.offset) { i, p in
                        HStack {
                            Image(systemName: "waveform").foregroundStyle(LHB.textSecondary)
                            Text(p).font(.body)
                            Spacer()
                        }
                        .padding(.horizontal, 16).frame(minHeight: 48)
                        if i < phrases.count - 1 { Divider().padding(.leading, 44) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))
                .padding(.top, 8)
                HStack { Spacer(); SystemMockTag(); Spacer() }.padding(.top, 28)
            }
            .padding(.horizontal, 20)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    private func tile(_ title: String, _ symbol: String) -> some View {
        VStack(alignment: .leading) {
            Image(systemName: symbol).font(.system(size: 24, weight: .medium))
            Spacer()
            Text(title).font(.system(size: 17, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x3A55B4), Color(hex: 0x223A8C)], startPoint: .top, endPoint: .bottom)))
        .accessibilityElement(children: .combine)
    }
}

/// "How many hours do I have in LandlordHours": the answer is spoken, and a snippet (the
/// Today hero in miniature, read-only) shows the same numbers. REPS counts your own hours.
struct SFSiriSnippetFrame: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack(alignment: .top) {
            Tabs(tab: .today, pending: 3) { S2Today(state: .launch) }
                .blur(radius: 18)
                .overlay(Color.black.opacity(scheme == .dark ? 0.35 : 0.12).ignoresSafeArea())
                .allowsHitTesting(false)
            VStack(spacing: 10) {
                Text("You have 212 of your 750 hours for 2026. You’re 388 behind pace, and 3 visits are waiting for you to confirm.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(scheme == .dark ? .white : Color(hex: 0x111111))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular.tint(scheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.6)), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                SFSiriSnippet()
                SystemMockTag().padding(.top, 8)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
    }
}

/// The snippet view itself (ShowsSnippetView). Theme-fixed blueprint, like the hero.
struct SFSiriSnippet: View {
    @ScaledMetric(relativeTo: .largeTitle) private var number: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var houseSize: CGFloat = 170
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        ZStack(alignment: .topLeading) {
            S2Paper(radius: 26)
            // At accessibility sizes the text takes the full width and the house steps back.
            HouseArt(key: S2House.keyframe(212)).frame(width: min(houseSize, 200), height: min(houseSize, 200))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 4, y: 8)
                .opacity(dts.isAccessibilitySize ? 0.35 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your REPS hours · 2026").font(.system(.caption2, design: .monospaced).weight(.medium))
                    .textCase(.uppercase).tracking(1.3).foregroundStyle(LHB.draftingHero)
                Text("212").font(.system(size: number, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white).padding(.top, 2)
                Text("of 750h").font(.subheadline.weight(.medium)).foregroundStyle(LHB.onHeroSecondary)
                Spacer(minLength: 12)
                (Text(Image(systemName: "exclamationmark.circle.fill")) + Text(" Behind by 388h"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color(hex: 0xFFB454))
                    .fixedSize(horizontal: false, vertical: true)
                Label("3 to confirm", systemImage: "tray.fill")
                    .font(.footnote.weight(.semibold)).labelStyle(TightLabel2())
                    .foregroundStyle(LHB.brand)
                    .padding(.horizontal, 12).padding(.vertical, 6).frame(minHeight: 30)
                    .background(Capsule().fill(.white))
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .frame(minHeight: 200)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - §2 Launch screen

/// Exactly what LaunchScreen.storyboard can draw: one colour fill (#1E3FA6 in both
/// appearances) and one centred image (mark B colour PDF, 112pt). No text, no grid.
struct SFLaunch: View {
    var body: some View {
        ZStack {
            LHB.brand
            MarkB().frame(width: 112, height: 112).offset(y: -12)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// First app frame → Today. The app's first frame repeats the launch screen exactly, then the
/// blueprint shrinks into the Today hero card (300ms, ease-out) while the mark fades out and
/// the canvas appears around it. Frozen at `progress` for review.
struct SFLaunchToToday: View {
    var progress: CGFloat
    /// The hero card's frame on a 402×874 screen (measured from the today capture).
    static let hero = CGRect(x: 20, y: SFLaunchToToday.heroY, width: 362, height: 320)
    static let heroY: CGFloat = 212

    var body: some View {
        ZStack {
            Tabs(tab: .today) { S2Today(state: .launch) }
                .opacity(Double(min(1, progress * 1.4)))
        GeometryReader { g in
            let full = CGRect(origin: .zero, size: g.size)
            let p = progress
            let r = CGRect(x: lerp(full.minX, Self.hero.minX, p), y: lerp(full.minY, Self.hero.minY, p),
                           width: lerp(full.width, Self.hero.width, p), height: lerp(full.height, Self.hero.height, p))
            ZStack(alignment: .topLeading) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24 * p + 55 * (1 - p), style: .continuous)
                        .fill(LHB.brand)
                    S2Paper(radius: 24 * p + 55 * (1 - p)).opacity(Double(p))
                    // The hero's own content rides in the bottom of the shrinking sheet and fades up,
                    // so when the sheet lands it IS the hero card.
                    TodayHero(hours: 212, status: "Behind by 388h")
                        .frame(width: r.width)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .opacity(Double(min(1, max(0, (p - 0.3) / 0.6))))
                        .clipShape(RoundedRectangle(cornerRadius: 24 * p + 55 * (1 - p), style: .continuous))
                    MarkB().frame(width: 112, height: 112)
                        .offset(y: -12 * (1 - p))
                        .scaleEffect(1 - 0.3 * p)
                        .opacity(Double(max(0, 1 - p * 1.8)))
                }
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)
                .opacity(Double(max(0, 1 - max(0, p - 0.8) * 5)))
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
}

/// First app frame → Welcome. Welcome is already blueprint, so nothing moves but ink: the
/// grid draws in, the mark lifts and fades, the drafted house fades up in its place.
struct SFLaunchToWelcome: View {
    var progress: CGFloat
    var body: some View {
        let p = progress
        ZStack(alignment: .top) {
            LHB.brand.ignoresSafeArea()
            S2Paper(radius: 0).opacity(Double(p)).ignoresSafeArea()
            if let l = S2House.linework("bp_house_k00_lot_lines") {
                Image(uiImage: l).renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(LHB.draftingHero)
                    .frame(width: 262, height: 262)
                    .padding(.top, 57)
                    .opacity(Double(p))
                    .scaleEffect(0.92 + 0.08 * p)
            }
            MarkB().frame(width: 112, height: 112)
                .scaleEffect(1 + 0.4 * p)
                .opacity(Double(max(0, 1 - p * 2.5)))
                .offset(y: -12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                Color.clear.frame(height: 318)
                Text("Here’s what you’ll build").drafting(size: 12).frame(maxWidth: .infinity)
                Text("Every hour builds the house.").font(S2Font.display(30, opsz: 144, soft: 50, dts: .large)).foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .opacity(Double(max(0, p * 2 - 1)))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
