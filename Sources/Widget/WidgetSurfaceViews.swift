import SwiftUI
import UIKit
import WidgetKit
import AppIntents

// MARK: - 2.2 widget views (the crafted house, dusk and night)
//
// Standard §H.5 and §1.26, plan package I. Medium, large and extra large draw the crafted house at
// 120 (a house-only thumbnail cut from the stills, `scripts/widget/make_widget_house.py`), lit when
// hours were logged today, on the dusk page in light and the night page in dark. One rental draws
// its own house and "212 of 750 hours"; two or more draw the skyline and "312 hours across 3
// rentals", never a summed goal (§H.1 H10). Small and the Lock Screen accessories carry the mono
// mark B: a 3D bitmap cannot tint, the mark can. Tinted and clear Home Screens draw the mark in the
// house's slot and white inks (the system supplies the tint).
//
// Words come from `WidgetSurfaceDisplay` (Sources/Shared/WidgetSurface.swift) and the `Widgets`
// string catalog. Colours are `BrandHex` tokens only. Numbers are SF Rounded, tabular (Fraunces is
// not in the extension bundle). Text uses Dynamic Type styles; at accessibility sizes the
// secondary lines drop so the number and the pace still fit.
//
// These views are compiled into the widget extension and, for DEBUG capture boards only, into the
// app (WidgetCaptureBoard). They take a `WidgetSurfaceDisplay` and nothing else.

/// How the system is drawing the widget.
enum WidgetLook: Equatable {
    /// Full colour (the default Home Screen).
    case fullColor
    /// iOS tinted / clear Home Screen: the system removes our background and tints the content.
    case accented
}

enum WidgetFont {
    /// The SF Rounded bold numeral at `size` (already scaled by the caller's `@ScaledMetric`).
    static func numeral(_ size: CGFloat) -> Font {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        return Font(UIFont(descriptor: descriptor, size: size))
    }
}

extension View {
    /// A widget is a fixed-size surface: its text grows with Dynamic Type up to the first
    /// accessibility size, where the secondary lines drop out so the number and the pace still fit.
    func widgetTypeCap() -> some View { dynamicTypeSize(...DynamicTypeSize.accessibility1) }
}

/// The page inks for one appearance (§H.4: only these inks are text on the dusk page).
struct WidgetInk {
    let scheme: ColorScheme
    var look: WidgetLook = .fullColor

    private var dark: Bool { scheme == .dark }
    private var tinted: Bool { look == .accented }

    var primary: Color { tinted ? .white : Color(brandHex: dark ? BrandHex.darkTextPrimary : BrandHex.textPrimary) }
    var secondary: Color { tinted ? Color.white.opacity(0.75) : Color(brandHex: dark ? BrandHex.darkTextSecondary : BrandHex.textSecondary) }
    var action: Color { tinted ? .white : Color(brandHex: dark ? BrandHex.darkAction : BrandHex.brand) }
    var onAction: Color { tinted ? .white : Color(brandHex: dark ? BrandHex.darkOnAction : BrandHex.card) }
    var actionFill: Color { tinted ? Color.white.opacity(0.2) : Color(brandHex: dark ? BrandHex.darkAction : BrandHex.brand) }
    var actionSurface: Color { tinted ? Color.white.opacity(0.16) : Color(brandHex: dark ? BrandHex.darkActionSurface : BrandHex.actionSurface) }
    var behind: Color { tinted ? .white : Color(brandHex: dark ? BrandHex.darkBehind : BrandHex.behind) }
    var positive: Color { tinted ? .white : Color(brandHex: dark ? BrandHex.darkPositive : BrandHex.positiveOnPage) }
    var cardFill: Color { tinted ? Color.white.opacity(0.1) : Color(brandHex: dark ? BrandHex.darkCard : BrandHex.card) }
    var cardEdge: Color { tinted ? Color.white.opacity(0.28) : Color(brandHex: dark ? BrandHex.darkPageCardEdge : BrandHex.pageCardEdge) }
    var divider: Color { tinted ? Color.white.opacity(0.2) : Color(brandHex: dark ? BrandHex.darkBorder : BrandHex.border) }
    var spill: Color { Color(brandHex: BrandHex.spill).opacity(dark ? BrandHex.darkSpillOpacity : BrandHex.spillOpacity) }

    func tone(_ tone: WidgetSurfaceDisplay.Tone) -> Color {
        switch tone {
        case .behind: return behind
        case .positive: return positive
        case .neutral: return secondary
        case .action: return action
        }
    }
}

/// The page under a house: dusk in light, night in dark (§H.4, vertical gradient). Small, with no
/// house, keeps the plain canvas (lists and forms are paper; only screens with the house get the page).
struct WidgetPage: View {
    var withHouse = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Group {
            if withHouse {
                LinearGradient(stops: [
                    .init(color: Color(brandHex: dark ? BrandHex.darkNightTop : BrandHex.duskTop), location: 0),
                    .init(color: Color(brandHex: dark ? BrandHex.darkNightTop : BrandHex.duskMid), location: 0.32),
                    .init(color: Color(brandHex: dark ? BrandHex.darkNightBottom : BrandHex.duskBottom), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            } else {
                Color(brandHex: dark ? BrandHex.darkCanvas : BrandHex.canvas)
            }
        }
        .accessibilityHidden(true)
    }
}

/// One house thumbnail: lit or unlit art, at a side, standing on a warm pool of light when lit.
struct WidgetHouseThumb: View {
    let asset: String
    let side: CGFloat
    var lit = true
    var scale: CGFloat = 1
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(decorative: asset)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: side, height: side)
            .scaleEffect(scale, anchor: UnitPoint(x: 0.5, y: 0.72))
            .accessibilityHidden(true)
    }
}

/// The warm pool the windows throw on the page (×0.2 when no window is lit).
private struct WidgetSpill: View {
    let width: CGFloat
    let lit: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = WidgetInk(scheme: scheme)
        Circle()
            .fill(RadialGradient(colors: [ink.spill, ink.spill.opacity(0)], center: .center, startRadius: 0, endRadius: width * 0.5))
            .frame(width: width, height: width)
            .scaleEffect(y: 0.34)
            .frame(width: width, height: width * 0.34)
            .opacity(lit ? 1 : 0.2)
            .accessibilityHidden(true)
    }
}

/// Night only: a cool light behind the lot (0.50 to 0 inside 0.88 of the slot) and a rim ellipse
/// (0.34 to 0), so the silhouette reads on the night page (standard §H.4, as `CraftHouseView`).
private struct WidgetBacklight: View {
    let side: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if scheme == .dark {
            let glow = Color(brandHex: BrandHex.darkBacklight)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [glow.opacity(0.50), glow.opacity(0.20), glow.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: side * 0.44))
                    .frame(width: side * 0.88, height: side * 0.88)
                    .offset(y: side * 0.03)
                Circle()
                    .fill(RadialGradient(colors: [glow.opacity(0.34), glow.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: side * 0.46))
                    .frame(width: side * 0.92, height: side * 0.92)
                    .scaleEffect(y: 0.34)
                    .offset(y: side * 0.31)
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
        }
    }
}

/// The house slot: one rental's house, or the skyline of every rental, or the mark B when tinted.
struct WidgetHouseSlot: View {
    let display: WidgetSurfaceDisplay
    let look: WidgetLook
    /// The slot's square side.
    let side: CGFloat
    /// The skyline's width when it may be wider than the single house's square (the frame side `S` of §H.1 H10).
    var skylineWidth: CGFloat? = nil

    /// The width the slot takes in its row.
    var width: CGFloat { look != .accented && display.isAllRentals && display.houses.count > 1 ? (skylineWidth ?? side) : side }

    var body: some View {
        if look == .accented {
            LHMarkShape()
                .fill(Color.white.opacity(0.92))
                .frame(width: side * 0.6, height: side * 0.6)
                .frame(width: side, height: side)
                .widgetAccentable()
                .accessibilityHidden(true)
        } else if display.isAllRentals, display.houses.count > 1 {
            skyline
        } else {
            single
        }
    }

    private var anyLit: Bool { display.snapshot.loggedToday || display.houses.contains { $0.lit } }

    private var single: some View {
        let houseSide = side * 0.96
        let lit = display.state == .noProperty ? false : display.snapshot.loggedToday
        let asset = display.state == .noProperty
            ? WidgetHouseArt.assetName(stage: "craft_started", lit: false)
            : display.singleHouseAsset
        return ZStack(alignment: .bottom) {
            WidgetSpill(width: side * 0.9, lit: lit).offset(y: -side * 0.1)
            WidgetBacklight(side: side)
            WidgetHouseThumb(asset: asset, side: houseSide, lit: lit,
                             scale: WidgetHouseArt.stageScale(stage: display.snapshot.houseStage))
        }
        .frame(width: side, height: side, alignment: .bottom)
    }

    private var skyline: some View {
        let frame = skylineWidth ?? side
        let shown = WidgetSkyline.visible(display.houses, frame: frame)
        let houseSide = WidgetSkyline.houseSide(frame: frame, count: shown.count)
        return ZStack(alignment: .bottom) {
            WidgetSpill(width: frame * 0.96, lit: anyLit).offset(y: -houseSide * 0.12)
            WidgetBacklight(side: max(frame * 0.8, houseSide * 2)).frame(height: houseSide)
            HStack(alignment: .bottom, spacing: WidgetSkyline.gapFraction * frame) {
                ForEach(shown) { rental in
                    WidgetHouseThumb(asset: WidgetHouseArt.assetName(stage: rental.stage, lit: rental.lit), side: houseSide, lit: rental.lit)
                }
            }
        }
        .frame(width: frame, height: min(side, houseSide * 1.7), alignment: .bottom)
    }
}

/// When `frozenNow` is set (captures), the timer draws a fixed "0:42"; otherwise it ticks.
private struct WidgetFrozenNowKey: EnvironmentKey { static let defaultValue: Date? = nil }
/// True only on the DEBUG capture board, which has no WidgetKit host to draw accessory backgrounds.
private struct WidgetHarnessKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var widgetFrozenNow: Date? {
        get { self[WidgetFrozenNowKey.self] }
        set { self[WidgetFrozenNowKey.self] = newValue }
    }
    var widgetHarness: Bool {
        get { self[WidgetHarnessKey.self] }
        set { self[WidgetHarnessKey.self] = newValue }
    }
}

/// The timer's elapsed time: live in the widget, fixed in captures.
struct WidgetElapsedText: View {
    let start: Date
    @Environment(\.widgetFrozenNow) private var frozenNow

    var body: some View {
        if let frozenNow {
            Text(WidgetSurfaceDisplay.elapsedText(from: start, to: frozenNow))
        } else {
            Text(start, style: .timer)
        }
    }
}

// MARK: - Shared pieces

/// The number and what it counts: "212" / "of 750 hours", or the timer.
private struct WidgetNumberBlock: View {
    let display: WidgetSurfaceDisplay
    let ink: WidgetInk
    var numeral: CGFloat = 46
    var alignment: HorizontalAlignment = .leading
    var showsStatus = true
    var statusLines = 3
    /// Short on height (medium at a large text size): the caption shrinks to one line instead of wrapping.
    var captionShrinks = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var ax: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            if display.state == .noProperty {
                Text(display.caption)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                numberText
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .widgetAccentable()
                if !ax {
                    Text(display.state == .timer ? String(localized: "widget.timer.running", defaultValue: "Timer running", table: "Widgets") : display.caption)
                        .font(.subheadline)
                        .foregroundStyle(ink.secondary)
                        .lineLimit(captionShrinks ? 1 : nil)
                        .minimumScaleFactor(captionShrinks ? 0.6 : 1)
                        .layoutPriority(1)
                }
                if showsStatus, let status = display.status {
                    statusRow(status)
                        .padding(.top, 3)
                }
            }
        }
    }

    @ViewBuilder private var numberText: some View {
        if display.state == .timer, let start = display.snapshot.timerStart {
            WidgetElapsedText(start: start)
                .font(WidgetFont.numeral(numeral * 0.82))
                .monospacedDigit()
                .foregroundStyle(ink.primary)
        } else {
            Text(display.number)
                .font(WidgetFont.numeral(numeral))
                .monospacedDigit()
                .foregroundStyle(ink.primary)
        }
    }

    private func statusRow(_ s: WidgetSurfaceDisplay.Status) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: s.symbol).font(.caption.weight(.bold))
            Text(s.text).lineLimit(ax ? max(3, statusLines) : statusLines)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(ink.tone(s.tone))
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// "3 to confirm": the one tappable thing on medium (a Link, so it opens its own place).
private struct WidgetPill: View {
    let pill: WidgetSurfaceDisplay.Pill
    let ink: WidgetInk

    var body: some View {
        Link(destination: pill.url) {
            HStack(spacing: 5) {
                Image(systemName: pill.symbol).font(.caption.weight(.bold))
                Text(pill.text).lineLimit(1).minimumScaleFactor(0.6)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ink.onAction)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(Capsule().fill(ink.actionFill))
        }
        .widgetAccentable()
    }
}

/// The footer of the left column: the pill when something waits, else the stage in words.
private struct WidgetFooter: View {
    let display: WidgetSurfaceDisplay
    let ink: WidgetInk
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let pill = display.pill {
            WidgetPill(pill: pill, ink: ink)
        } else if typeSize <= .large, display.state != .timer, display.state != .noProperty, let stage = display.stageLine {
            Text(stage)
                .font(.footnote)
                .foregroundStyle(ink.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

/// The pill every row control wears: one grammar for Confirm and Review (44pt tall, action ink on
/// the action surface). `Confirm` is a Button on a WidgetConfirmIntent; `Review` is a Link.
private struct WidgetRowPill: View {
    let text: String
    let ink: WidgetInk

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ink.action)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Capsule().fill(ink.actionSurface))
            .accessibilityLabel(text)
    }
}

/// The first-run call to action on large and extra large: one full-width pill, "Add a rental".
private struct WidgetAddRentalButton: View {
    let display: WidgetSurfaceDisplay
    let ink: WidgetInk

    var body: some View {
        if let pill = display.pill {
            Link(destination: pill.url) {
                HStack(spacing: 6) {
                    Image(systemName: pill.symbol).font(.subheadline.weight(.bold))
                    Text(pill.text).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                .foregroundStyle(ink.onAction)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Capsule().fill(ink.actionFill))
            }
            .widgetAccentable()
        }
    }
}

/// To confirm: up to `limit` rows in one grouped container with hairline dividers, each with an
/// interactive Confirm (§1.27 Widgets). A row that cannot be logged in one tap reads "Review".
/// Rows are 56pt or more and grow with Dynamic Type (D1); with no rental the card is the
/// "Add a rental" button instead.
private struct WidgetConfirmCard: View {
    let display: WidgetSurfaceDisplay
    let ink: WidgetInk
    let limit: Int
    /// The most rows at an accessibility size (the rows are tall there).
    var axLimit = 2
    /// The most rows above the default text size, so the card never outgrows its widget.
    var largeTypeLimit = 3

    @ScaledMetric(relativeTo: .body) private var rowMin: CGFloat = 56
    @Environment(\.dynamicTypeSize) private var typeSize
    private var ax: Bool { typeSize.isAccessibilitySize }
    private var rowCap: Int { ax ? min(limit, axLimit) : (typeSize > .large ? min(limit, largeTypeLimit) : limit) }
    private var rows: [WidgetConfirmRow] { Array(display.confirmRows.prefix(rowCap)) }

    var body: some View {
        if display.state == .noProperty {
            WidgetAddRentalButton(display: display, ink: ink)
        } else {
            card
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            if rows.isEmpty {
                caughtUp
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Rectangle().fill(ink.divider).frame(height: 0.5).padding(.leading, 14) }
                    rowView(row)
                }
                if display.pendingCount > rows.count {
                    Rectangle().fill(ink.divider).frame(height: 0.5).padding(.leading, 14)
                    Link(destination: WidgetLinks.inbox) {
                        HStack {
                            Text(String(localized: "widget.card.more", defaultValue: "See all \(display.pendingCount)", table: "Widgets"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ink.action)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(ink.secondary)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ink.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(ink.cardEdge, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var caughtUp: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(ink.positive).widgetAccentable()
            Text(String(localized: "widget.card.caughtUp", defaultValue: "Nothing waiting to confirm.", table: "Widgets"))
                .font(.subheadline)
                .foregroundStyle(ink.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: rowMin)
    }

    @ViewBuilder private func rowView(_ row: WidgetConfirmRow) -> some View {
        if ax {
            VStack(alignment: .leading, spacing: 6) {
                rowText(row)
                control(row)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: rowMin, alignment: .leading)
        } else {
            HStack(spacing: 10) {
                rowText(row)
                control(row)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: rowMin)
        }
    }

    private func rowText(_ row: WidgetConfirmRow) -> some View {
        Link(destination: WidgetLinks.inbox) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(ax ? 3 : 1)
                    .minimumScaleFactor(ax ? 1 : 0.8)
                if !ax {
                    Text(display.detail(for: row))
                        .font(.caption)
                        .foregroundStyle(ink.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func control(_ row: WidgetConfirmRow) -> some View {
        if row.canConfirm {
            Button(intent: WidgetConfirmIntent(key: row.key)) {
                WidgetRowPill(text: String(localized: "widget.card.confirm", defaultValue: "Confirm", table: "Widgets"), ink: ink)
            }
            .buttonStyle(.plain)
            .widgetAccentable()
        } else {
            Link(destination: WidgetLinks.inbox) {
                WidgetRowPill(text: String(localized: "widget.card.review", defaultValue: "Review", table: "Widgets"), ink: ink)
            }
            .widgetAccentable()
        }
    }
}

// MARK: - Home Screen

struct WidgetSmallView: View {
    let display: WidgetSurfaceDisplay
    var look: WidgetLook = .fullColor
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var numeral: CGFloat = 52

    var body: some View {
        let ink = WidgetInk(scheme: scheme, look: look)
        VStack(alignment: .leading, spacing: 0) {
            if typeSize <= .large {
                LHMarkShape()
                    .fill(ink.action)
                    .frame(width: 24, height: 24)
                    .widgetAccentable()
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 6)
            WidgetNumberBlock(display: display, ink: ink, numeral: min(numeral, typeSize > .large ? 40 : 56), statusLines: 4)
        }
        .padding(typeSize > .large ? 12 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.accessibilityLabel)
    }
}

struct WidgetMediumView: View {
    let display: WidgetSurfaceDisplay
    var look: WidgetLook = .fullColor
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var numeral: CGFloat = 46

    var body: some View {
        let ink = WidgetInk(scheme: scheme, look: look)
        GeometryReader { geo in
            let slot = min(geo.size.height - 22, 150)
            let house = WidgetHouseSlot(display: display, look: look, side: slot, skylineWidth: 168)
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetNumberBlock(display: display, ink: ink, numeral: typeSize > .large ? min(numeral, 40) : numeral, captionShrinks: typeSize > .large && display.isAllRentals)
                    Spacer(minLength: 4)
                    WidgetFooter(display: display, ink: ink)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.trailing, 8)
                house
                    .frame(width: house.width, height: geo.size.height, alignment: .bottom)
            }
            .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 10))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(display.accessibilityLabel)
    }
}

struct WidgetLargeView: View {
    let display: WidgetSurfaceDisplay
    var look: WidgetLook = .fullColor
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var numeral: CGFloat = 46

    var body: some View {
        let ink = WidgetInk(scheme: scheme, look: look)
        VStack(spacing: 12) {
            // The house block takes whatever the rows leave, so a short list never leaves a blank tail.
            GeometryReader { geo in
                let side = min(geo.size.height, 176)
                let house = WidgetHouseSlot(display: display, look: look, side: side, skylineWidth: 200)
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        WidgetNumberBlock(display: display, ink: ink, numeral: numeral)
                        Spacer(minLength: 4)
                        if typeSize <= .large, display.state != .timer, display.state != .noProperty, let stage = display.stageLine {
                            Text(stage)
                                .font(.footnote)
                                .foregroundStyle(ink.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.trailing, 8)
                    house.frame(width: house.width, height: geo.size.height, alignment: .bottom)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            WidgetConfirmCard(display: display, ink: ink, limit: 3, axLimit: 1, largeTypeLimit: 2)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
    }
}

/// The iPad Home Screen: a mini Today on the left (house, number, pace), five rows on the right.
/// With nothing to confirm the house takes the whole left half and the card sits under the number.
struct WidgetExtraLargeView: View {
    let display: WidgetSurfaceDisplay
    var look: WidgetLook = .fullColor
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .largeTitle) private var numeral: CGFloat = 54

    var body: some View {
        let ink = WidgetInk(scheme: scheme, look: look)
        Group {
            if display.confirmRows.count < 2 || display.state == .noProperty {
                settled(ink)
            } else {
                HStack(alignment: .top, spacing: 18) {
                    WidgetTodayColumn(display: display, look: look, ink: ink, numeral: numeral, houseSide: 168)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    WidgetConfirmCard(display: display, ink: ink, limit: 5, largeTypeLimit: 3)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
    }

    private func settled(_ ink: WidgetInk) -> some View {
        GeometryReader { geo in
            let side = min(geo.size.height, 280)
            let house = WidgetHouseSlot(display: display, look: look, side: side, skylineWidth: min(geo.size.width * 0.46, 330))
            HStack(alignment: .center, spacing: 18) {
                house.frame(width: house.width, height: geo.size.height, alignment: .bottom)
                VStack(alignment: .leading, spacing: 0) {
                    if display.state == .noProperty { Spacer(minLength: 8) }
                    WidgetNumberBlock(display: display, ink: ink, numeral: numeral)
                    Spacer(minLength: display.state == .noProperty ? 16 : 8)
                    if display.state == .timer, let pill = display.pill {
                        WidgetPill(pill: pill, ink: ink)
                    } else {
                        WidgetConfirmCard(display: display, ink: ink, limit: 5)
                    }
                    if display.state == .noProperty { Spacer(minLength: 8) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// The iPad Lock Screen in landscape: the mini Today stacked above three rows.
struct WidgetExtraLargePortraitView: View {
    let display: WidgetSurfaceDisplay
    var look: WidgetLook = .fullColor
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .largeTitle) private var numeral: CGFloat = 54

    var body: some View {
        let ink = WidgetInk(scheme: scheme, look: look)
        VStack(spacing: 14) {
            GeometryReader { geo in
                let side = min(geo.size.height * 0.58, geo.size.width - 20, 300)
                WidgetTodayColumn(display: display, look: look, ink: ink, numeral: numeral, houseSide: side)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            WidgetConfirmCard(display: display, ink: ink, limit: 3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
    }
}

/// The mini Today: the house (or skyline) centred, the number under it, then the pace.
private struct WidgetTodayColumn: View {
    let display: WidgetSurfaceDisplay
    let look: WidgetLook
    let ink: WidgetInk
    let numeral: CGFloat
    let houseSide: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            WidgetHouseSlot(display: display, look: look, side: houseSide, skylineWidth: min(houseSide * 1.6, 300))
            WidgetNumberBlock(display: display, ink: ink, numeral: numeral, alignment: .center)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if let pill = display.pill, display.state == .timer {
                WidgetPill(pill: pill, ink: ink).padding(.top, 6)
            }
        }
    }
}

// MARK: - Lock Screen (vibrant: one colour, the system tints it)

/// The accessory's circle backing: the system's in a widget, a stand-in on the capture board.
struct WidgetAccessoryBacking: View {
    @Environment(\.widgetHarness) private var harness
    var body: some View {
        if harness {
            Circle().fill(Color.black.opacity(0.22))
        } else {
            AccessoryWidgetBackground()
        }
    }
}

struct WidgetCircularHoursView: View {
    let display: WidgetSurfaceDisplay

    var body: some View {
        ZStack {
            WidgetAccessoryBacking()
            if display.hasRing {
                Circle().stroke(Color.white.opacity(0.28), lineWidth: 5).padding(6)
                Circle()
                    .trim(from: 0, to: display.progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(6)
                    .widgetAccentable()
            }
            VStack(spacing: 0) {
                face
                LHMarkShape().fill(Color.white).frame(width: 15, height: 15)
            }
            .foregroundStyle(Color.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.hoursFace.accessibilityLabel)
    }

    @ViewBuilder private var face: some View {
        let f = display.hoursFace
        if display.state == .timer, let start = display.snapshot.timerStart {
            WidgetElapsedText(start: start)
                .font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: 52)
        } else if let symbol = f.symbol {
            Image(systemName: symbol).font(.system(size: 20, weight: .bold))
        } else {
            Text(f.text).font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: 52)
        }
    }
}

struct WidgetCircularPendingView: View {
    let display: WidgetSurfaceDisplay

    var body: some View {
        let f = display.pendingFace
        ZStack {
            WidgetAccessoryBacking()
            VStack(spacing: 1) {
                if let symbol = f.symbol { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)) }
                Text(f.text)
                    .font(.system(size: f.isLarge ? 22 : 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(Color.white)
            .widgetAccentable()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(f.accessibilityLabel)
    }
}

struct WidgetRectangularView: View {
    let display: WidgetSurfaceDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                LHMarkShape().fill(Color.white).frame(width: 14, height: 14)
                Text(display.rectangularTitle).font(.system(size: 13, weight: .semibold))
            }
            .widgetAccentable()
            headline
                .font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(display.rectangularLine)
                .font(.system(size: 13))
                .opacity(0.9)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var headline: some View {
        if display.state == .timer, let start = display.snapshot.timerStart {
            HStack(spacing: 0) {
                WidgetElapsedText(start: start)
                Text(" · \(display.timerPropertyName)")
            }
        } else {
            Text(display.rectangularHeadline(elapsed: ""))
        }
    }
}

struct WidgetInlineView: View {
    let display: WidgetSurfaceDisplay
    @Environment(\.widgetFrozenNow) private var frozenNow

    var body: some View {
        // Inline widgets draw one Text + one image; a live timer would need its own Text, so the
        // timer shows the minutes at the last refresh (the timeline refreshes every minute while it runs).
        let elapsed = display.snapshot.timerStart.map { WidgetSurfaceDisplay.elapsedText(from: $0, to: frozenNow ?? Date()) } ?? ""
        Label(display.inlineText(elapsed: elapsed), systemImage: display.inlineSymbol)
    }
}
