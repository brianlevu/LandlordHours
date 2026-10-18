// Creative directions layered on the r4 baseline. Launch arg: -LHDirection waypoint|clayhouse|inkwell
// Spec: AgentScratch/landlordhours/2026-10-18/creative/directions.md
import SwiftUI
import MapKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum LHDirection: String {
    case baseline, waypoint, clayhouse, inkwell
    static let current: LHDirection =
        UserDefaults.standard.string(forKey: "LHDirection").flatMap(LHDirection.init(rawValue:)) ?? .baseline
}

enum Ink {
    static let ink = Color(light: 0x1A1A2E, dark: 0xF2F2F7)
    static let graphite = Color(light: 0x6B6F7B, dark: 0x9DA2AE)
    static let rose = Color(light: 0xB4306A, dark: 0xF28AB8)
    static let clayChip = Color(light: 0xD7D9DF, dark: 0x3A3C44)
}

// MARK: - Category palette (directions.md, exact hex)

enum Category: String, CaseIterable {
    case repairs, renovation, cleaning, leasing, tenant, bookkeeping, travel, inspections, legal, supplies, management

    var hex: (deep: UInt32, bright: UInt32) {
        switch self {
        case .repairs: (0xB5451B, 0xF2916D)
        case .renovation: (0x7F6300, 0xE3C84A)
        case .cleaning: (0x0A6E96, 0x5CC4EA)
        case .leasing: (0x8A2E8F, 0xE07BE6)
        case .tenant: (0x2B5FD9, 0x7FA6FF)
        case .bookkeeping: (0x55701A, 0xB5CF5A)
        case .travel: (0x0D747E, 0x4FC3CF)
        case .inspections: (0x4A5A78, 0xA9B7D6)
        case .legal: (0x3B3F4A, 0xC3C7D1)
        case .supplies: (0x8C5B3C, 0xD9A383)
        case .management: (0x2E6B3F, 0x7FCB93)
        }
    }
    var tone: Color { Color(light: hex.deep, dark: hex.bright) }
    var wash: Color { Color(light: hex.deep, dark: hex.bright, lightAlpha: 0.12, darkAlpha: 0.20) }

    var label: String {
        switch self {
        case .repairs: "Repairs"
        case .renovation: "Renovation"
        case .cleaning: "Cleaning"
        case .leasing: "Leasing"
        case .tenant: "Tenants"
        case .bookkeeping: "Bookkeeping"
        case .travel: "Travel"
        case .inspections: "Inspections"
        case .legal: "Legal & admin"
        case .supplies: "Supplies"
        case .management: "Management"
        }
    }
    /// Base SF Symbol (outline). Every one has a `.fill` sibling, which Inkwell layers under it.
    var symbol: String {
        switch self {
        case .repairs: "wrench.adjustable"
        case .renovation: "paintbrush.pointed"
        case .cleaning: "bubbles.and.sparkles"
        case .leasing: "key.horizontal"
        case .tenant: "bubble.left.and.text.bubble.right"
        case .bookkeeping: "book.closed"
        case .travel: "car.side"
        case .inspections: "list.clipboard"
        case .legal: "doc.text"
        case .supplies: "shippingbox"
        case .management: "building.2"
        }
    }
    var clayAsset: String {
        switch self {
        case .repairs: "clay-icon-repairs"
        case .renovation: "clay-icon-renovation"
        case .cleaning: "clay-icon-cleaning-turnover"
        case .leasing: "clay-icon-showing-leasing"
        case .tenant: "clay-icon-tenant-comms"
        case .bookkeeping: "clay-icon-bookkeeping"
        case .travel: "clay-icon-travel"
        case .inspections: "clay-icon-inspection"
        case .legal: "clay-icon-legal-admin"
        case .supplies: "clay-icon-supplies"
        case .management: "clay-icon-property-mgmt"
        }
    }

    static let forSuggestion: [String: Category] = [
        "plumber": .repairs, "showing": .leasing, "homedepot": .supplies, "oakvisit": .travel,
        "turnover": .cleaning, "books": .bookkeeping, "insurance": .legal, "hoa": .management,
        "roof": .inspections, "lease": .leasing, "appliance": .repairs, "lowes": .supplies,
        "paint": .renovation, "tax": .legal,
    ]
    static let forRecord: [String: Category] = [
        "Plumber": .repairs, "Home Depot run": .supplies, "Visit": .travel, "Unit 2 repairs": .renovation,
        "Tenant calls": .tenant, "Turnover clean": .cleaning, "HOA meeting": .management,
        "Bookkeeping": .bookkeeping, "Roof inspection": .inspections,
    ]
}

extension Suggestion { var category: Category { Category.forSuggestion[id] ?? .repairs } }
extension RecordEntry { var category: Category { Category.forRecord[title] ?? .repairs } }

// MARK: - Property identity

struct Prop: Hashable {
    let key: String
    let name: String
    let pin: String       // 1-letter monogram (Waypoint pin)
    let seal: String      // 2-letter monogram (Inkwell seal)
    let hex: (UInt32, UInt32)
    let coords: [CLLocationCoordinate2D]
    let span: Double
    let clayHouse: String

    var color: Color { Color(light: hex.0, dark: hex.1) }

    static func == (a: Prop, b: Prop) -> Bool { a.key == b.key }
    func hash(into h: inout Hasher) { h.combine(key) }

    static let pine = Prop(key: "pine", name: "Pine Cabin", pin: "P", seal: "PC", hex: (0x0D747E, 0x4FC3CF),
                           coords: [.init(latitude: 34.24390, longitude: -116.91140)], span: 0.007, clayHouse: "clay-house-cabin-str")
    static let oak = Prop(key: "oak", name: "Oak Street Duplex", pin: "O", seal: "OS", hex: (0x2B5FD9, 0x7FA6FF),
                          coords: [.init(latitude: 33.98060, longitude: -117.37550)], span: 0.007, clayHouse: "clay-house-duplex")
    static let both = Prop(key: "both", name: "Both properties", pin: "2", seal: "2P", hex: (0x3B3F4A, 0xC3C7D1),
                           coords: [.init(latitude: 34.24390, longitude: -116.91140), .init(latitude: 33.98060, longitude: -117.37550)],
                           span: 0.75, clayHouse: "clay-house-single-family")

    static func named(_ n: String) -> Prop {
        if n.hasPrefix("Pine") { return .pine }
        if n.hasPrefix("Oak") { return .oak }
        return .both
    }
}

// MARK: - Map snapshots (MKMapSnapshotter, muted, desaturated, cached in memory + Caches/)

@MainActor
@Observable
final class MapSnaps {
    static let shared = MapSnaps()
    private(set) var images: [String: UIImage] = [:]
    private var inFlight: Set<String> = []
    private let ci = CIContext()

    func key(_ p: Prop, _ pt: CGFloat, dark: Bool) -> String { "\(p.key)-v2-\(dark ? "d" : "l")" }

    func load(_ p: Prop, pt: CGFloat, dark: Bool) {
        let k = key(p, pt, dark: dark)
        guard images[k] == nil, !inFlight.contains(k) else { return }
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("map-\(k).png")
        if let data = try? Data(contentsOf: url), let img = UIImage(data: data, scale: 3) {
            images[k] = img
            return
        }
        inFlight.insert(k)
        let o = MKMapSnapshotter.Options()
        let lat = p.coords.map(\.latitude).reduce(0, +) / Double(p.coords.count)
        let lon = p.coords.map(\.longitude).reduce(0, +) / Double(p.coords.count)
        o.region = MKCoordinateRegion(center: .init(latitude: lat, longitude: lon),
                                      span: .init(latitudeDelta: p.span, longitudeDelta: p.span))
        o.size = CGSize(width: 220, height: 220)
        o.scale = 2
        o.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        o.pointOfInterestFilter = .excludingAll
        o.showsBuildings = true
        o.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        MKMapSnapshotter(options: o).start { snap, _ in
            Task { @MainActor in
                self.inFlight.remove(k)
                guard let raw = snap?.image else { return }
                let img = self.desaturate(raw) ?? raw
                self.images[k] = img
                if let png = img.pngData() { try? png.write(to: url) }
            }
        }
    }

    private func desaturate(_ img: UIImage) -> UIImage? {
        guard let cg = img.cgImage else { return nil }
        let f = CIFilter.colorControls()
        f.inputImage = CIImage(cgImage: cg)
        f.saturation = 0.4
        guard let out = f.outputImage, let cgOut = ci.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cgOut, scale: img.scale, orientation: .up)
    }
}

struct MapTile: View {
    let prop: Prop
    var size: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let snaps = MapSnaps.shared
        ZStack {
            if let img = snaps.images[snaps.key(prop, size, dark: dark)] {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                MiniMap()
            }
            if prop.coords.count > 1 {
                HStack(spacing: size * 0.18) {
                    MapPin(letter: "P", color: Prop.pine.color, size: max(12, size * 0.22))
                    MapPin(letter: "O", color: Prop.oak.color, size: max(12, size * 0.22))
                }
            } else {
                MapPin(letter: prop.pin, color: prop.color, size: max(12, size * 0.26))
                    .offset(y: -size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size >= 60 ? 14 : 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size >= 60 ? 14 : 10, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .task(id: dark) { snaps.load(prop, pt: size, dark: dark) }
        .accessibilityLabel("\(prop.name) map")
    }
}

struct MapPin: View {
    var letter: String
    var color: Color
    var size: CGFloat
    var body: some View {
        VStack(spacing: -size * 0.18) {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(.white, lineWidth: max(1.2, size * 0.1)))
                .overlay(Text(letter).font(.system(size: size * 0.5, weight: .bold, design: .rounded)).foregroundStyle(.white))
            Triangle().fill(color).frame(width: size * 0.36, height: size * 0.3)
        }
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Category icon, per direction

struct CategoryIcon: View {
    let cat: Category
    var size: CGFloat = 40
    var dir: LHDirection = .current
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch dir {
        case .waypoint:
            Circle()
                .fill(cat.tone)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: filled(cat.symbol))
                        .font(.system(size: size * 0.44, weight: .medium))
                        .foregroundStyle(scheme == .dark ? Color(hex: 0x1C1C1E) : .white)
                }
        case .clayhouse:
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(cat.wash)
                .frame(width: size, height: size)
                .overlay {
                    if let ui = UIImage(named: cat.clayAsset) {
                        Image(uiImage: ui).resizable().scaledToFit().padding(size * 0.12)
                    } else {
                        Image(systemName: filled(cat.symbol)).font(.system(size: size * 0.45)).foregroundStyle(cat.tone)
                    }
                }
        case .inkwell:
            ZStack {
                Image(systemName: filled(cat.symbol)).foregroundStyle(cat.tone)
                Image(systemName: cat.symbol).foregroundStyle(Ink.ink)
            }
            .font(.system(size: size * 0.6, weight: .regular))
            .frame(width: size, height: size)
        case .baseline:
            Circle().fill(cat.wash).frame(width: size, height: size)
        }
    }
}

// MARK: - Source badges (graphite, shape-coded, never colored)

extension SourceKind {
    var badgeSymbol: String {
        switch self {
        case .calendar: "calendar"
        case .receipt: "ticket"
        case .location: "location.fill"
        case .timer: "timer"
        case .manual: "pencil"
        }
    }
}

struct SourceBadge: View {
    let kind: SourceKind
    var confirmed = false
    var dir: LHDirection = .current

    var body: some View {
        switch dir {
        case .waypoint:
            // A pin: graphite square head with the source glyph, pointer below; green check at the foot once confirmed.
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: -1) {
                    RoundedRectangle(cornerRadius: kind == .location ? 7 : 3.5, style: .continuous)
                        .fill(Ink.graphite)
                        .frame(width: 14, height: 14)
                        .overlay(Image(systemName: kind.badgeSymbol).font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
                    Triangle().fill(Ink.graphite).frame(width: 6, height: 4)
                }
                if confirmed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white, LH.positive)
                        .offset(x: 5, y: 1)
                }
            }
            .frame(width: 18, height: 18)
        case .clayhouse:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Ink.clayChip)
                .frame(width: 18, height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .black.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                )
                .overlay(Image(systemName: kind.badgeSymbol).font(.system(size: 9, weight: .bold)).foregroundStyle(Ink.graphite))
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        case .inkwell:
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Ink.graphite, lineWidth: 1)
                    .frame(width: 18, height: 14)
                    .overlay(Image(systemName: kind.badgeSymbol).font(.system(size: 7.5, weight: .semibold)).foregroundStyle(Ink.graphite))
                Text(kind == .manual ? "BY HAND" : kind.label.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Ink.graphite)
            }
        case .baseline:
            Image(systemName: kind.symbol).foregroundStyle(kind.tint)
        }
    }
}

/// Inkwell's confirmed mark.
struct LoggedStamp: View {
    var animated = false
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        Text("LOGGED")
            .font(.system(size: 11, weight: .heavy))
            .tracking(1)
            .foregroundStyle(LH.positive)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(LH.positive, lineWidth: 1.5))
            .rotationEffect(.degrees(-6))
            .scaleEffect(animated && !pressed && !reduce ? 1.25 : 1)
            .opacity(animated && !pressed ? 0 : 1)
            .onAppear {
                guard animated else { return }
                withAnimation(reduce ? .easeOut(duration: 0.2) : .easeOut(duration: 0.18)) { pressed = true }
            }
    }
}

// MARK: - Property marks

struct PropertyMark: View {
    let prop: Prop
    var size: CGFloat = 36
    var dir: LHDirection = .current

    var body: some View {
        switch dir {
        case .waypoint:
            MapTile(prop: prop, size: size)
        case .clayhouse:
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(prop.color.opacity(0.14))
                .frame(width: size, height: size)
                .overlay {
                    if let ui = UIImage(named: prop.clayHouse) {
                        Image(uiImage: ui).resizable().scaledToFit().padding(size * 0.08)
                    } else {
                        Image(systemName: "house.fill").foregroundStyle(prop.color)
                    }
                }
        case .inkwell:
            Circle()
                .strokeBorder(prop.color, lineWidth: 1.5)
                .frame(width: size, height: size)
                .overlay(
                    Text(prop.seal)
                        .font(.system(size: size * 0.36, weight: .semibold, design: .serif))
                        .foregroundStyle(prop.color)
                )
        case .baseline:
            EmptyView()
        }
    }
}

// MARK: - Illustrations

enum ArtKind { case welcome, emptyToday, emptyInbox, inboxBanner }

struct DirectionArt: View {
    let kind: ArtKind
    var dir: LHDirection = .current
    @Environment(\.colorScheme) private var scheme

    private var name: String? {
        switch (dir, kind) {
        case (.waypoint, .welcome): "way-scene-welcome"
        case (.waypoint, .emptyToday): "way-scene-empty-today"
        case (.waypoint, .emptyInbox), (.waypoint, .inboxBanner): "way-scene-empty-inbox"
        case (.clayhouse, .welcome): "clay-scene-welcome"
        case (.clayhouse, .emptyToday): "clay-scene-empty-today"
        case (.clayhouse, .emptyInbox), (.clayhouse, .inboxBanner): "clay-scene-empty-inbox"
        case (.inkwell, .welcome), (.inkwell, .emptyToday): "ink-cabin"
        case (.inkwell, .emptyInbox), (.inkwell, .inboxBanner): "ink-receipt-envelope"
        default: nil
        }
    }

    var body: some View {
        if let name, let ui = UIImage(named: name) {
            let img = Image(uiImage: ui).resizable().scaledToFit()
            if dir == .inkwell && scheme == .dark {
                // Black line art needs paper in dark mode.
                img.padding(10)
                    .background(Color(hex: 0xF4F1EA), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                img
            }
        } else {
            Image(systemName: "house.lodge").font(.system(size: 64)).foregroundStyle(LH.secondaryText)
        }
    }
}

/// A non-category symbol drawn in a direction's icon language (Welcome bullets).
struct ToneGlyph: View {
    var symbol: String
    var tone: Category
    var size: CGFloat
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        switch LHDirection.current {
        case .waypoint:
            Circle().fill(tone.tone).frame(width: size, height: size)
                .overlay(Image(systemName: filled(symbol)).font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(scheme == .dark ? Color(hex: 0x1C1C1E) : .white))
        case .clayhouse:
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(tone.wash)
                .frame(width: size, height: size)
                .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .black.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .overlay(Image(systemName: filled(symbol)).font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(tone.tone))
                .shadow(color: tone.tone.opacity(0.18), radius: 3, y: 2)
        default:
            ZStack {
                Image(systemName: filled(symbol)).foregroundStyle(tone.tone)
                Image(systemName: symbol).foregroundStyle(Ink.ink)
            }
            .font(.system(size: size * 0.7))
            .frame(width: size, height: size)
        }
    }
}

/// The `.fill` variant when SF Symbols has one, else the base symbol.
func filled(_ base: String) -> String {
    UIImage(systemName: base + ".fill") != nil ? base + ".fill" : base
}
