import SwiftUI
import UIKit

#if DEBUG
// MARK: - Duo concept B, "the model room" (DEBUG mock, throwaway)
//
// Unfold the iPhone Duo and the front door of the house opens (a pre-rendered Blender clip, 0.8 s, played over the
// live layout, hit-testing off). Inside is the landlord's model room: every rental stands on one timber shelf as the
// diorama it already is (same stills, same lit/unlit twins, nothing per rental), with the numbers and the To confirm
// list on the plain page below. Folding plays the clip in reverse.
//
//   -LHDirection CRAFT -LHDuoSnapshot      writes the open-layout snapshots (669x951 pt @3x, light + dark,
//                                          1, 3 and 8 rentals) to Documents/duo/ via ImageRenderer, because the
//                                          simulator cannot be unfolded by an agent (posture is a Device Hub GUI action).
//
// The system chrome on the open layout (regular width: a top tab bar and a toolbar "+") is drawn by TabView in the app;
// ImageRenderer cannot draw a TabView, so the snapshot carries a flat stand-in in the same slot (DuoChromeStandIn).

struct DuoRental: Identifiable, Equatable {
    let id: String
    let name: String
    var logged: Double
    let goal: Double
    var lit: Bool
    var art: CraftArt { CraftFocus.art(hours: logged, goal: goal) }
}

enum DuoSeed {
    static let three: [DuoRental] = [
        DuoRental(id: "santa", name: "Santa Ray Ave", logged: 46, goal: 100, lit: true),
        DuoRental(id: "delaney", name: "Delaney Ct", logged: 4, goal: 100, lit: false),
        DuoRental(id: "pine", name: "Pine Cabin", logged: 262, goal: 500, lit: false),
    ]
    static let one: [DuoRental] = [three[0]]
    static let eight: [DuoRental] = three + [
        DuoRental(id: "harbor", name: "Harbor Loft", logged: 88, goal: 100, lit: true),
        DuoRental(id: "elm", name: "12 Elm St", logged: 120, goal: 100, lit: false),
        DuoRental(id: "mesa", name: "Mesa Duplex", logged: 31, goal: 100, lit: false),
        DuoRental(id: "bay", name: "Bayview 4B", logged: 410, goal: 750, lit: true),
        DuoRental(id: "oak", name: "Oak Cottage", logged: 9, goal: 100, lit: false),
    ]
}

/// The open layout. One column (band B: Duo open portrait 669 and iPad portrait share it), capped at 600.
struct DuoInsideView: View {
    @State var rentals: [DuoRental]
    @State var focusID: String
    var suggestions: [StdSuggestion]
    /// Snapshot mode: the shelf is a plain HStack (ImageRenderer does not draw ScrollView content past the origin).
    var still = false
    var openLog: () -> Void = {}

    @State private var confirmed: Set<String> = []
    @State private var removed: Set<String> = []
    private var env = CraftEnv()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(rentals: [DuoRental], focusID: String? = nil, suggestions: [StdSuggestion], still: Bool = false, openLog: @escaping () -> Void = {}) {
        _rentals = State(initialValue: rentals)
        _focusID = State(initialValue: focusID ?? rentals[0].id)
        self.suggestions = suggestions; self.still = still; self.openLog = openLog
    }

    private var c: CraftColors { env.c }
    private var focus: DuoRental { rentals.first { $0.id == focusID } ?? rentals[0] }
    /// Model size on the shelf: 300 for one or two rentals (the rental-page medium size, §H.5), 220 from three on
    /// (the diorama floor, §H.5), and the shelf scrolls sideways.
    private var side: CGFloat { rentals.count <= 2 ? 300 : 220 }
    private var items: [StdSuggestion] { suggestions.filter { !removed.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            DuoChromeStandIn(openLog: openLog).padding(.top, 8)
            shelfHeader.padding(.top, 16)
            shelf.padding(.top, 4)
            numberBlock.padding(.top, 14)
            confirmBlock.padding(.top, 18)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background { CraftPage() }
    }

    // MARK: The shelf

    private var shelfHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(CL("Your rentals · \(rentals.count)")).font(.headline).foregroundStyle(c.ink).accessibilityAddTraits(.isHeader)
            Spacer()
            Text(CL("\(rentals.filter(\.lit).count) worked on today"))
                .font(.subheadline).foregroundStyle(c.textSecondary)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder private var shelf: some View {
        if still || rentals.count <= 2 {
            shelfRow.fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: rentals.count <= 2 ? .center : .leading)
                .background(alignment: .top) { plank }
                .clipped()
        } else {
            ScrollView(.horizontal) { shelfRow.background(alignment: .top) { plank } }.scrollIndicators(.hidden)
        }
    }

    private var shelfRow: some View {
        HStack(alignment: .top, spacing: rentals.count <= 2 ? 0 : -14) {
            ForEach(rentals) { r in model(r) }
        }
    }

    /// The plank runs under every model, one rendered timber strip (duo_shelf, Any = dusk, Dark = night), tiled.
    /// The still's lot block ends at 88.7% of its height; the plank's top edge meets it there.
    private var plank: some View {
        Image("duo_shelf").resizable(resizingMode: .tile)
            .frame(height: 16)
            .offset(y: side * 0.875)
            .accessibilityHidden(true)
    }

    private func model(_ r: DuoRental) -> some View {
        let selected = r.id == focusID
        return Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.30, bounce: 0)) { focusID = r.id }
        } label: {
            VStack(spacing: side * 0.04) {
                Image(r.lit ? r.art.rawValue : (CraftHouseArt.unlitName(for: r.art) ?? r.art.rawValue))
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: side, height: side)
                    .background {
                        // §H.4 night backlight, per model, so an unlit silhouette still reads on the night page.
                        if scheme == .dark {
                            RadialGradient(colors: [c.backlight.opacity(0.42), c.backlight.opacity(0)], center: UnitPoint(x: 0.5, y: 0.5),
                                           startRadius: 0, endRadius: side * 0.44)
                        }
                    }
                    .padding(.bottom, -side * 0.05)
                VStack(spacing: 1) {
                    Text(r.name).font(.subheadline.weight(.semibold)).foregroundStyle(c.ink).lineLimit(1)
                    Text(CL("\(Int(r.logged)) of \(Int(r.goal))h")).font(.footnote).foregroundStyle(c.textSecondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? c.chip : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? c.chipBorder : .clear, lineWidth: 0.8))
            }
            .frame(width: side)
        }
        .buttonStyle(DAPress())
        .accessibilityLabel(CL("\(r.name), \(Int(r.logged)) of \(Int(r.goal)) hours, \(r.lit ? CL("lights on") : CL("lights off"))"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            Button(CL("Log time here"), systemImage: "plus") { focusID = r.id; openLog() }
            Button(CL("Open rental"), systemImage: "house") {}
        }
    }

    // MARK: The number for the rental in focus

    private var numberBlock: some View {
        VStack(spacing: 2) {
            Text(verbatim: "\(Int(focus.logged))")
                .font(DAFont.fraunces(size: 84, opsz: 144, wght: 600)).tracking(-2)
                .foregroundStyle(c.ink)
                .contentTransition(.numericText(value: focus.logged))
                .lineLimit(1)
            Text(CL("of \(Int(focus.goal)) hours · \(focus.name)")).font(.body).foregroundStyle(c.textSecondary)
            paceLine.padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    private var paceLine: some View {
        let f = CraftFocus(id: focus.id, name: focus.name, logged: focus.logged, goal: focus.goal, art: focus.art)
        let lead = f.done ? c.positive : (f.isBehind ? c.behind : c.positive)
        return (Text(f.pace.lead).foregroundStyle(lead).fontWeight(.semibold) + Text(verbatim: " ") + Text(f.pace.rest).foregroundStyle(c.textSecondary))
            .font(.subheadline)
    }

    // MARK: To confirm: four rows on the open layout (one on the closed outer display)

    private var confirmBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CL("To confirm · \(items.count)")).font(.headline).foregroundStyle(c.ink)
                .accessibilityAddTraits(.isHeader).padding(.horizontal, 4)
            DuoSection {
                ForEach(Array(items.prefix(rentals.count <= 2 ? 3 : 4).enumerated()), id: \.element.id) { i, item in
                    if i > 0 { DAHairline().padding(.leading, 50) }
                    DAActionRow(item: item, confirmed: confirmed.contains(item.id)) { confirm(item) }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                }
                DAHairline()
                Button(CL("See all \(items.count)")) {}
                    .font(.subheadline.weight(.semibold)).foregroundStyle(c.action)
                    .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(DAPress())
            }
        }
    }

    private func confirm(_ item: StdSuggestion) {
        withAnimation(.easeOut(duration: 0.15)) { _ = confirmed.insert(item.id) }
        DADemo.after(0.45) {
            withAnimation(.spring(duration: 0.25, bounce: 0)) { _ = removed.insert(item.id) }
            guard let i = rentals.firstIndex(where: { $0.id == focusID }) else { return }
            withAnimation(.spring(duration: 0.40, bounce: 0)) {
                rentals[i].logged += item.hours ?? 0
                rentals[i].lit = true          // the model's windows come on: someone worked here today
            }
        }
    }
}

private struct DuoSection<Content: View>: View {
    @ViewBuilder var content: Content
    private var env = DAEnv()
    private var craft = CraftEnv()
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(spacing: 0) { content }
            .background(env.c.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(craft.c.cardEdge, lineWidth: 1))
    }
}

/// Stand-in for the regular-width system chrome (top tab bar + toolbar "+ Log time"); TabView draws the real one.
struct DuoChromeStandIn: View {
    var openLog: () -> Void = {}
    private var env = CraftEnv()
    var body: some View {
        let c = env.c
        HStack(spacing: 0) {
            Spacer(minLength: 56)
            HStack(spacing: 4) {
                ForEach([(CL("Today"), true), (CL("Inbox"), false), (CL("Records"), false), (CL("Rentals"), false)], id: \.0) { t in
                    Text(t.0).font(.subheadline.weight(.semibold))
                        .foregroundStyle(t.1 ? c.action : c.ink)
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(t.1 ? c.chip : .clear, in: Capsule())
                }
            }
            .padding(4)
            .background(c.chip.opacity(0.7), in: Capsule())
            .overlay(Capsule().strokeBorder(c.chipBorder, lineWidth: 0.5))
            Spacer(minLength: 8)
            Button(action: openLog) {
                Image(systemName: "plus").font(.body.weight(.semibold)).foregroundStyle(c.ink)
                    .frame(width: 44, height: 44)
                    .background(c.chip, in: Circle()).overlay(Circle().strokeBorder(c.chipBorder, lineWidth: 0.5))
            }
            .accessibilityLabel(CL("Log time"))
        }
    }
}

// MARK: - Snapshot hook

enum DuoSnapshot {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("-LHDuoSnapshot") }

    @MainActor static func run() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("duo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sugg = StdSeed.make("brian").suggestions
        let sets: [(String, [DuoRental])] = [("3", DuoSeed.three), ("1", DuoSeed.one), ("8", DuoSeed.eight)]
        for (name, rentals) in sets {
            for dark in [false, true] {
                let view = DuoInsideView(rentals: rentals, suggestions: sugg, still: true)
                    .padding(.top, 44)                       // inner display top safe area (camera)
                    .frame(width: 669, height: 951, alignment: .top)
                    .background { CraftPage() }
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .environment(\.dynamicTypeSize, .large)
                let r = ImageRenderer(content: view)
                r.scale = 3
                r.isOpaque = true
                if let img = r.uiImage, let data = img.pngData() {
                    let fn = dir.appendingPathComponent("open-\(name)rentals-\(dark ? "night" : "dusk").png")
                    try? data.write(to: fn)
                    NSLog("DUO_SNAPSHOT %@", fn.path)
                }
            }
        }
        NSLog("DUO_SNAPSHOT_DONE")
    }
}
#endif
