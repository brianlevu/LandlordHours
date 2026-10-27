import SwiftUI

// MARK: - Rentals gallery (Brian, 2026-10-26; standard §1.4 exception)
//
// The Rentals tab with two or more rentals: a two-column gallery of house tiles. A browse and
// identity screen, so the house is the point. Tile: house at its stage (lit by `loggedToday`),
// the name (wraps at whole words), "88 of 100h", and one pace line. Gutters 20, tile radius 20,
// tile padding 12, 8 between house and words. From XXL the grid is one column and the tile
// lays the house beside the words (above them from AX1), so nothing clips.

/// The house still on a tile: the transparent lit or unlit still (lot included) scaled so the lot
/// fills the tile's width, sitting on the tile's own surface. No box, no crop: the frame is cut
/// where the art is already clear.
struct RentalTileHouse: View {
    let stage: CraftStage
    let lit: Bool

    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { colorScheme == .dark }

    /// Measured on the five stills (alpha > 8): art spans x 0.085–0.949 and y 0.05–0.939 of the
    /// square, centred at x 0.5165, ground at y 0.939.
    private static let art = (centerX: 0.5165 as CGFloat, bottom: 0.94 as CGFloat)
    /// Art width over the frame's width, and the frame's height over its width. At 1.05 the
    /// tallest house (0.89 of the square) is 0.935 of the width, inside 0.95.
    private static let scale: CGFloat = 1.05
    static let heightRatio: CGFloat = 0.95

    var body: some View {
        Color.clear
            .aspectRatio(1 / Self.heightRatio, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    let side = geo.size.width * Self.scale
                    let center = CGPoint(x: geo.size.width / 2 - side * (Self.art.centerX - 0.5),
                                         y: geo.size.height - side * (Self.art.bottom - 0.5))
                    ZStack {
                        backlight(side: side, strength: Self.backlightStrength(stage)).position(center)
                        Image(stage.assetName(lit: lit))
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: side, height: side)
                            .brightness(dark ? Self.nightLift(stage) : 0)
                            .position(center)
                    }
                }
            }
            .accessibilityHidden(true)
    }
}

extension RentalTileHouse {
    /// Night only (standard §H.4 `backlight`, the Today night page's recipe at the tile's art side):
    /// a cool light behind the lot, 0.50 → 0 inside 0.88 × side, plus a rim ellipse 0.34 → 0, both
    /// times `strength`, so an unlit roofed house reads against the tile. Light mode draws none.
    /// Roofed stages take 1.4 × (an unlit roof measured 1.68:1 on the tile with none, 2.98 with it);
    /// the framing stages draw none: their pale wood already reads (2.5-2.7:1 unlit) and any glow behind it only lowers that.
    static func backlightStrength(_ stage: CraftStage) -> Double { stage.isFraming ? 0 : 1.4 }

    @ViewBuilder fileprivate func backlight(side: CGFloat, strength k: Double) -> some View {
        if dark, k > 0 {
            let glow = AdaptiveColors(colorScheme: colorScheme).backlight
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [glow.opacity(0.50 * k), glow.opacity(0.20 * k), glow.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: side * 0.44))
                    .frame(width: side * 0.88, height: side * 0.88)
                    .offset(y: side * 0.03)
                Circle()
                    .fill(RadialGradient(colors: [glow.opacity(0.34 * k), glow.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: side * 0.46))
                    .frame(width: side * 0.92, height: side * 0.92)
                    .scaleEffect(y: 0.34)
                    .offset(y: side * 0.31)
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
        }
    }

    /// The hero's night ambient lift for the stages without a moon rim (`CraftHouseView.nightLift`).
    fileprivate static func nightLift(_ stage: CraftStage) -> Double { CraftHouseView.nightLift(stage) }
}

struct RentalGallery: View {
    let tiles: [RentalTileModel]
    var open: (UUID) -> Void
    var edit: (UUID) -> Void
    var delete: (UUID) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    static let spacing: CGFloat = 20

    var body: some View {
        let columns = typeSize >= .xxLarge
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Self.spacing), GridItem(.flexible())]
        LazyVGrid(columns: columns, alignment: .leading, spacing: Self.spacing) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                RentalTile(tile: tile) { open(tile.id) }
                    .contextMenu {
                        Button(RentalsText.open, systemImage: "house") { open(tile.id) }
                        Button(RentalsText.edit, systemImage: "pencil") { edit(tile.id) }
                        Button(RentalsText.delete, systemImage: "trash", role: .destructive) { delete(tile.id) }
                    }
                    .accessibilityAction(named: Text(RentalsText.edit)) { edit(tile.id) }
                    .accessibilityAction(named: Text(RentalsText.delete)) { delete(tile.id) }
                    .accessibilityIdentifier("properties.tile.\(index)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("properties.gallery")
    }
}

struct RentalTile: View {
    let tile: RentalTileModel
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var colors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    private var paceInk: Color {
        switch tile.pace.tone {
        case .positive: return colors.positive
        case .behind: return colors.behind
        case .neutral: return colors.textSecondary
        }
    }

    var body: some View {
        Button(action: action) {
            layout
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(colors.backgroundSecondary, in: shape)
                .overlay {
                    if colorScheme == .dark { shape.strokeBorder(colors.border, lineWidth: LHMetrics.hairline) }
                }
                .contentShape(shape)
        }
        .buttonStyle(LHButton.press)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.spoken)
        .accessibilityAddTraits(.isButton)
        .hoverEffect(.highlight)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: LHMetrics.cardRadius, style: .continuous) }

    @ViewBuilder private var layout: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                house.frame(width: 160)
                words
            }
        } else if typeSize >= .xxLarge {
            HStack(alignment: .center, spacing: 16) {
                house.frame(width: 128)
                words
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                house
                words
                Spacer(minLength: 0)
            }
        }
    }

    private var house: some View { RentalTileHouse(stage: tile.row.stage, lit: tile.row.lit) }

    private var words: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.row.name)
                .font(.headline)
                .foregroundStyle(colors.textPrimary)
            Text(tile.hoursLine)
                .font(.subheadline.monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(colors.textSecondary)
            Text(tile.pace.text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(paceInk)
        }
        .multilineTextAlignment(.leading)
    }
}
