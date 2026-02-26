import SwiftUI

// MARK: - LandlordHours Custom Icon System
// Tiimo-inspired: soft, rounded, friendly icons with color-coded badges

// MARK: - Icon Identifier
enum LHIcon: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    // Tab Bar
    case home, properties, track, reports, settings

    // Activity Categories
    case repairs, management, leasing, bookkeeping, legal
    case insurance, travel, renovations, investing, financing, contract

    // People
    case person, personTwo

    // UI Actions
    case plus, plusCircle, trash, pencil, close, share, checkmark

    // Navigation
    case chevronRight, chevronLeft, chevronDown

    // Status & Info
    case clock, calendar, calendarClock, crown, sparkles, bolt
    case star, info, party, checklist, signOut, seal

    // Communication
    case envelope, phone, chat

    // Objects
    case tag, flag, lock, eye, camera, lightbulb, megaphone
    case paintbrush, drop, creditcard, banknote
    case doc, docGear, folder, chartPie, chartLine
    case bus, airplane, tram, target, percent, icloud

    // Number badges
    case num1, num2, num3
}

// MARK: - Icon Shape
struct LHIconShape: Shape {
    let icon: LHIcon

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let ox = rect.minX + (rect.width - s) / 2
        let oy = rect.minY + (rect.height - s) / 2

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x / 24 * s, y: oy + y / 24 * s)
        }
        func v(_ x: CGFloat) -> CGFloat { x / 24 * s }

        var path = Path()

        switch icon {
        // ─── TAB BAR ────────────────────────────────────────
        case .home:
            // Rounded house with chimney
            path.move(to: p(12, 3))
            path.addLine(to: p(2.5, 11))
            path.addLine(to: p(5, 11))
            path.addLine(to: p(5, 20))
            path.addQuadCurve(to: p(6, 21), control: p(5, 21))
            path.addLine(to: p(18, 21))
            path.addQuadCurve(to: p(19, 20), control: p(19, 21))
            path.addLine(to: p(19, 11))
            path.addLine(to: p(21.5, 11))
            path.closeSubpath()
            // Door
            path.addRoundedRect(in: CGRect(x: ox + v(9.5), y: oy + v(14.5), width: v(5), height: v(6.5)), cornerSize: CGSize(width: v(1.5), height: v(1.5)))

        case .properties:
            // Two buildings with windows
            path.addRoundedRect(in: CGRect(x: ox + v(2), y: oy + v(4), width: v(11), height: v(17)), cornerSize: CGSize(width: v(2), height: v(2)))
            path.addRoundedRect(in: CGRect(x: ox + v(14.5), y: oy + v(9), width: v(7.5), height: v(12)), cornerSize: CGSize(width: v(1.5), height: v(1.5)))
            // Windows left building
            path.addRoundedRect(in: CGRect(x: ox + v(4.5), y: oy + v(7), width: v(2.5), height: v(2.5)), cornerSize: CGSize(width: v(0.5), height: v(0.5)))
            path.addRoundedRect(in: CGRect(x: ox + v(8.5), y: oy + v(7), width: v(2.5), height: v(2.5)), cornerSize: CGSize(width: v(0.5), height: v(0.5)))
            path.addRoundedRect(in: CGRect(x: ox + v(4.5), y: oy + v(11.5), width: v(2.5), height: v(2.5)), cornerSize: CGSize(width: v(0.5), height: v(0.5)))
            path.addRoundedRect(in: CGRect(x: ox + v(8.5), y: oy + v(11.5), width: v(2.5), height: v(2.5)), cornerSize: CGSize(width: v(0.5), height: v(0.5)))
            // Door left
            path.addRoundedRect(in: CGRect(x: ox + v(5.5), y: oy + v(16), width: v(4), height: v(5)), cornerSize: CGSize(width: v(1), height: v(1)))
            // Windows right building
            path.addRoundedRect(in: CGRect(x: ox + v(16.5), y: oy + v(11.5), width: v(2.5), height: v(2.5)), cornerSize: CGSize(width: v(0.5), height: v(0.5)))
            path.addRoundedRect(in: CGRect(x: ox + v(16.5), y: oy + v(15.5), width: v(2.5), height: v(2.5)), cornerSize: CGSize(width: v(0.5), height: v(0.5)))

        case .track:
            // Stopwatch
            let cx = ox + v(12)
            let cy = oy + v(13)
            let r = v(8.5)
            path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            // Top button
            path.addRoundedRect(in: CGRect(x: ox + v(10.5), y: oy + v(1.5), width: v(3), height: v(3.5)), cornerSize: CGSize(width: v(1), height: v(1)))
            // Minute hand (up)
            path.addRoundedRect(in: CGRect(x: ox + v(11.3), y: oy + v(7.5), width: v(1.4), height: v(5.5)), cornerSize: CGSize(width: v(0.7), height: v(0.7)))
            // Second hand (right)
            path.addRoundedRect(in: CGRect(x: ox + v(12), y: oy + v(12.3), width: v(4.5), height: v(1.4)), cornerSize: CGSize(width: v(0.7), height: v(0.7)))
            // Center dot
            path.addEllipse(in: CGRect(x: cx - v(1.2), y: cy - v(1.2), width: v(2.4), height: v(2.4)))

        case .reports:
            // Three rounded bars
            path.addRoundedRect(in: CGRect(x: ox + v(3), y: oy + v(14), width: v(4.5), height: v(7)), cornerSize: CGSize(width: v(1.5), height: v(1.5)))
            path.addRoundedRect(in: CGRect(x: ox + v(9.75), y: oy + v(8), width: v(4.5), height: v(13)), cornerSize: CGSize(width: v(1.5), height: v(1.5)))
            path.addRoundedRect(in: CGRect(x: ox + v(16.5), y: oy + v(3), width: v(4.5), height: v(18)), cornerSize: CGSize(width: v(1.5), height: v(1.5)))

        case .settings:
            // Gear with 6 teeth
            let cx = ox + v(12)
            let cy = oy + v(12)
            let outerR = v(10)
            let innerR = v(7.5)
            let toothW = v(3.5)
            for i in 0..<6 {
                let angle = CGFloat(i) * .pi / 3 - .pi / 2
                let tx = cx + cos(angle) * (outerR - v(1))
                let ty = cy + sin(angle) * (outerR - v(1))
                path.addRoundedRect(in: CGRect(x: tx - toothW / 2, y: ty - toothW / 2, width: toothW, height: toothW), cornerSize: CGSize(width: v(0.8), height: v(0.8)))
            }
            path.addEllipse(in: CGRect(x: cx - innerR, y: cy - innerR, width: innerR * 2, height: innerR * 2))
            // Center hole
            path.addEllipse(in: CGRect(x: cx - v(3), y: cy - v(3), width: v(6), height: v(6)))

        // ─── ACTIVITY CATEGORIES ────────────────────────────
        case .repairs:
            // Wrench
            path.move(to: p(5, 7))
            path.addQuadCurve(to: p(7, 3), control: p(3, 4))
            path.addQuadCurve(to: p(11, 5), control: p(9, 2))
            path.addQuadCurve(to: p(10, 8), control: p(12, 6.5))
            path.addLine(to: p(17, 15))
            path.addQuadCurve(to: p(20, 15), control: p(18.5, 13.5))
            path.addQuadCurve(to: p(21, 19), control: p(22, 17))
            path.addQuadCurve(to: p(17, 20), control: p(20, 22))
            path.addQuadCurve(to: p(16, 17), control: p(15, 19))
            path.addLine(to: p(9, 10))
            path.addQuadCurve(to: p(5, 7), control: p(7, 9.5))
            path.closeSubpath()

        case .management:
            // Clipboard
            path.addRoundedRect(in: CGRect(x: ox + v(4), y: oy + v(4), width: v(16), height: v(18)), cornerSize: CGSize(width: v(2.5), height: v(2.5)))
            // Clip at top
            path.addRoundedRect(in: CGRect(x: ox + v(8.5), y: oy + v(2), width: v(7), height: v(4)), cornerSize: CGSize(width: v(1.5), height: v(1.5)))
            // Lines
            path.addRoundedRect(in: CGRect(x: ox + v(7), y: oy + v(10), width: v(10), height: v(1.5)), cornerSize: CGSize(width: v(0.75), height: v(0.75)))
            path.addRoundedRect(in: CGRect(x: ox + v(7), y: oy + v(14), width: v(7), height: v(1.5)), cornerSize: CGSize(width: v(0.75), height: v(0.75)))
            path.addRoundedRect(in: CGRect(x: ox + v(7), y: oy + v(18), width: v(5), height: v(1.5)), cornerSize: CGSize(width: v(0.75), height: v(0.75)))

        case .leasing:
            // Key with round head
            let headCx = ox + v(7.5)
            let headCy = oy + v(8)
            let headR = v(4.5)
            path.addEllipse(in: CGRect(x: headCx - headR, y: headCy - headR, width: headR * 2, height: headR * 2))
            // Hole in head
            path.addEllipse(in: CGRect(x: headCx - v(1.8), y: headCy - v(1.8), width: v(3.6), height: v(3.6)))
            // Shaft
            path.addRoundedRect(in: CGRect(x: ox + v(11), y: oy + v(6.8), width: v(10), height: v(2.4)), cornerSize: CGSize(width: v(1.2), height: v(1.2)))
            // Teeth
            path.addRoundedRect(in: CGRect(x: ox + v(16), y: oy + v(9.2), width: v(1.8), height: v(3)), cornerSize: CGSize(width: v(0.5), height: v(0.5)))
            path.addRoundedRect(in: CGRect(x: ox + v(19.2), y: oy + v(9.2), width: v(1.8), height: v(4)), cornerSize: CGSize(width: v(0.5), height: v(0.5)))

        case .bookkeeping:
            // Calculator
            path.addRoundedRect(in: CGRect(x: ox + v(4), y: oy + v(2), width: v(16), height: v(20)), cornerSize: CGSize(width: v(3), height: v(3)))
            // Screen
            path.addRoundedRect(in: CGRect(x: ox + v(6.5), y: oy + v(4.5), width: v(11), height: v(4.5)), cornerSize: CGSize(width: v(1.5), height: v(1.5)))
            // Buttons row 1
            path.addRoundedRect(in: CGRect(x: ox + v(6.5), y: oy + v(11.5), width: v(3), height: v(2.5)), cornerSize: CGSize(width: v(0.8), height: v(0.8)))
            path.addRoundedRect(in: CGRect(x: ox + v(10.5), y: oy + v(11.5), width: v(3), height: v(2.5)), cornerSize: CGSize(width: v(0.8), height: v(0.8)))
            path.addRoundedRect(in: CGRect(x: ox + v(14.5), y: oy + v(11.5), width: v(3), height: v(2.5)), cornerSize: CGSize(width: v(0.8), height: v(0.8)))
            // Buttons row 2
            path.addRoundedRect(in: CGRect(x: ox + v(6.5), y: oy + v(15.5), width: v(3), height: v(2.5)), cornerSize: CGSize(width: v(0.8), height: v(0.8)))
            path.addRoundedRect(in: CGRect(x: ox + v(10.5), y: oy + v(15.5), width: v(3), height: v(2.5)), cornerSize: CGSize(width: v(0.8), height: v(0.8)))
            path.addRoundedRect(in: CGRect(x: ox + v(14.5), y: oy + v(15.5), width: v(3), height: v(2.5)), cornerSize: CGSize(width: v(0.8), height: v(0.8)))
            // Bottom row
            path.addRoundedRect(in: CGRect(x: ox + v(6.5), y: oy + v(19.5), width: v(7), height: v(1)), cornerSize: CGSize(width: v(0.5), height: v(0.5)))

        case .legal:
            // Scales of justice
            // Pillar
            path.addRoundedRect(in: CGRect(x: ox + v(11), y: oy + v(4), width: v(2), height: v(14)), cornerSize: CGSize(width: v(1), height: v(1)))
            // Base
            path.addRoundedRect(in: CGRect(x: ox + v(6), y: oy + v(19), width: v(12), height: v(2.5)), cornerSize: CGSize(width: v(1.2), height: v(1.2)))
            // Beam
            path.addRoundedRect(in: CGRect(x: ox + v(2.5), y: oy + v(5), width: v(19), height: v(2)), cornerSize: CGSize(width: v(1), height: v(1)))
            // Left pan
            path.move(to: p(3, 8))
            path.addQuadCurve(to: p(9, 8), control: p(6, 14))
            path.closeSubpath()
            // Right pan
            path.move(to: p(15, 8))
            path.addQuadCurve(to: p(21, 8), control: p(18, 14))
            path.closeSubpath()

        case .insurance:
            // Shield with checkmark
            path.move(to: p(12, 2.5))
            path.addQuadCurve(to: p(3, 6), control: p(7, 3))
            path.addLine(to: p(3, 13))
            path.addQuadCurve(to: p(12, 21.5), control: p(3, 19))
            path.addQuadCurve(to: p(21, 13), control: p(21, 19))
            path.addLine(to: p(21, 6))
            path.addQuadCurve(to: p(12, 2.5), control: p(17, 3))
            path.closeSubpath()
            // Checkmark
            path.move(to: p(8, 12.5))
            path.addLine(to: p(11, 15.5))
            path.addLine(to: p(16.5, 9))

        case .travel:
            // Car side view
            // Body
            path.move(to: p(2, 14))
            path.addLine(to: p(2, 12))
            path.addQuadCurve(to: p(4, 10), control: p(2, 10))
            path.addLine(to: p(7, 10))
            path.addLine(to: p(9, 6))
            path.addQuadCurve(to: p(10, 5.5), control: p(9.3, 5.5))
            path.addLine(to: p(17, 5.5))
            path.addQuadCurve(to: p(18.5, 7), control: p(18, 5.5))
            path.addLine(to: p(20, 10))
            path.addQuadCurve(to: p(22, 12), control: p(22, 10))
            path.addLine(to: p(22, 14))
            path.addQuadCurve(to: p(21, 15), control: p(22, 15))
            path.addLine(to: p(19, 15))
            // Right wheel cutout
            path.addQuadCurve(to: p(15, 15), control: p(17, 18))
            path.addLine(to: p(9, 15))
            // Left wheel cutout
            path.addQuadCurve(to: p(5, 15), control: p(7, 18))
            path.addLine(to: p(3, 15))
            path.addQuadCurve(to: p(2, 14), control: p(2, 15))
            path.closeSubpath()
            // Windshield line
            path.move(to: p(8, 10))
            path.addLine(to: p(13, 10))

        case .renovations:
            // Hammer
            // Handle (diagonal)
            path.move(to: p(4, 21))
            path.addQuadCurve(to: p(5.5, 20), control: p(4, 20))
            path.addLine(to: p(14, 11.5))
            path.addQuadCurve(to: p(13, 10), control: p(14.5, 10.5))
            path.addLine(to: p(4.5, 18.5))
            path.addQuadCurve(to: p(4, 21), control: p(3.5, 19.5))
            path.closeSubpath()
            // Head
            path.move(to: p(12, 11))
            path.addQuadCurve(to: p(13, 9), control: p(11.5, 10))
            path.addLine(to: p(19, 3))
            path.addQuadCurve(to: p(21, 3), control: p(20, 2))
            path.addQuadCurve(to: p(21, 5), control: p(22, 4))
            path.addLine(to: p(15, 11))
            path.addQuadCurve(to: p(12, 11), control: p(14, 12))
            path.closeSubpath()

        case .investing:
            // Upward trending chart
            // Axis
            path.addRoundedRect(in: CGRect(x: ox + v(3), y: oy + v(3), width: v(1.8), height: v(17)), cornerSize: CGSize(width: v(0.9), height: v(0.9)))
            path.addRoundedRect(in: CGRect(x: ox + v(3), y: oy + v(18.2), width: v(18), height: v(1.8)), cornerSize: CGSize(width: v(0.9), height: v(0.9)))
            // Line going up (as filled shape)
            path.move(to: p(6, 16))
            path.addLine(to: p(10, 12))
            path.addLine(to: p(13, 14))
            path.addLine(to: p(19, 6))
            path.addLine(to: p(20, 7.5))
            path.addLine(to: p(13.5, 15.5))
            path.addLine(to: p(10.5, 13.5))
            path.addLine(to: p(7.5, 17.5))
            path.closeSubpath()
            // Arrow tip
            path.move(to: p(19, 6))
            path.addLine(to: p(19, 9))
            path.addLine(to: p(16, 6))
            path.closeSubpath()

        case .financing:
            // Dollar sign in circle
            let cr = v(9.5)
            let ccx = ox + v(12)
            let ccy = oy + v(12)
            path.addEllipse(in: CGRect(x: ccx - cr, y: ccy - cr, width: cr * 2, height: cr * 2))
            // Dollar S shape
            path.addRoundedRect(in: CGRect(x: ox + v(11.2), y: oy + v(4.5), width: v(1.6), height: v(15)), cornerSize: CGSize(width: v(0.8), height: v(0.8)))
            path.move(to: p(15, 9))
            path.addQuadCurve(to: p(9, 9), control: p(12, 6.5))
            path.addQuadCurve(to: p(12, 12), control: p(8, 11))
            path.addQuadCurve(to: p(15, 15), control: p(16, 13))
            path.addQuadCurve(to: p(9, 15), control: p(12, 17.5))

        case .contract:
            // Document with signature
            path.addRoundedRect(in: CGRect(x: ox + v(4), y: oy + v(2), width: v(16), height: v(20)), cornerSize: CGSize(width: v(2.5), height: v(2.5)))
            // Lines
            path.addRoundedRect(in: CGRect(x: ox + v(7), y: oy + v(6), width: v(10), height: v(1.5)), cornerSize: CGSize(width: v(0.75), height: v(0.75)))
            path.addRoundedRect(in: CGRect(x: ox + v(7), y: oy + v(9.5), width: v(8), height: v(1.5)), cornerSize: CGSize(width: v(0.75), height: v(0.75)))
            // Signature squiggle
            path.move(to: p(7, 16))
            path.addQuadCurve(to: p(10, 14), control: p(8, 13))
            path.addQuadCurve(to: p(13, 16), control: p(12, 17))
            path.addQuadCurve(to: p(17, 15), control: p(15, 14))

        // ─── PEOPLE ────────────────────────────────────────
        case .person:
            // Head
            path.addEllipse(in: CGRect(x: ox + v(8), y: oy + v(2.5), width: v(8), height: v(8)))
            // Body
            path.move(to: p(5, 21))
            path.addQuadCurve(to: p(12, 13), control: p(5, 13))
            path.addQuadCurve(to: p(19, 21), control: p(19, 13))
            path.closeSubpath()

        case .personTwo:
            // Person 1 (front)
            path.addEllipse(in: CGRect(x: ox + v(6), y: oy + v(3), width: v(7), height: v(7)))
            path.move(to: p(3, 21))
            path.addQuadCurve(to: p(9.5, 13), control: p(3, 13))
            path.addQuadCurve(to: p(16, 21), control: p(16, 13))
            path.closeSubpath()
            // Person 2 (behind, slightly offset)
            path.addEllipse(in: CGRect(x: ox + v(13), y: oy + v(4), width: v(6), height: v(6)))
            path.move(to: p(13, 21))
            path.addQuadCurve(to: p(16, 13), control: p(13, 13))
            path.addQuadCurve(to: p(21, 21), control: p(21, 13))
            path.closeSubpath()

        // ─── UI ACTIONS ────────────────────────────────────
        case .plus:
            path.addRoundedRect(in: CGRect(x: ox + v(10.5), y: oy + v(4), width: v(3), height: v(16)), cornerSize: CGSize(width: v(1.5), height: v(1.5)))
            path.addRoundedRect(in: CGRect(x: ox + v(4), y: oy + v(10.5), width: v(16), height: v(3)), cornerSize: CGSize(width: v(1.5), height: v(1.5)))

        case .plusCircle:
            path.addEllipse(in: CGRect(x: ox + v(1.5), y: oy + v(1.5), width: v(21), height: v(21)))
            path.addRoundedRect(in: CGRect(x: ox + v(10.8), y: oy + v(6), width: v(2.4), height: v(12)), cornerSize: CGSize(width: v(1.2), height: v(1.2)))
            path.addRoundedRect(in: CGRect(x: ox + v(6), y: oy + v(10.8), width: v(12), height: v(2.4)), cornerSize: CGSize(width: v(1.2), height: v(1.2)))

        case .trash:
            // Lid
            path.addRoundedRect(in: CGRect(x: ox + v(4), y: oy + v(4), width: v(16), height: v(2.5)), cornerSize: CGSize(width: v(1.2), height: v(1.2)))
            // Handle on lid
            path.addRoundedRect(in: CGRect(x: ox + v(9), y: oy + v(2), width: v(6), height: v(2.5)), cornerSize: CGSize(width: v(1.2), height: v(1.2)))
            // Body
            path.move(to: p(5.5, 7.5))
            path.addLine(to: p(6.5, 20))
            path.addQuadCurve(to: p(8, 21.5), control: p(6.5, 21.5))
            path.addLine(to: p(16, 21.5))
            path.addQuadCurve(to: p(17.5, 20), control: p(17.5, 21.5))
            path.addLine(to: p(18.5, 7.5))
            path.closeSubpath()
            // Lines
            path.addRoundedRect(in: CGRect(x: ox + v(9.5), y: oy + v(10), width: v(1.2), height: v(8)), cornerSize: CGSize(width: v(0.6), height: v(0.6)))
            path.addRoundedRect(in: CGRect(x: ox + v(13.3), y: oy + v(10), width: v(1.2), height: v(8)), cornerSize: CGSize(width: v(0.6), height: v(0.6)))

        case .pencil:
            // Pencil body
            path.move(to: p(17, 3))
            path.addQuadCurve(to: p(20, 3.5), control: p(19, 2))
            path.addQuadCurve(to: p(21, 7), control: p(22, 5))
            path.addLine(to: p(8, 20))
            path.addQuadCurve(to: p(4, 21), control: p(6, 21))
            path.addQuadCurve(to: p(3, 17), control: p(3, 19))
            path.closeSubpath()
            // Tip line
            path.move(to: p(6, 17))
            path.addLine(to: p(17.5, 5.5))

        case .close:
            // X mark
            path.move(to: p(5.5, 5.5))
            path.addLine(to: p(18.5, 18.5))
            path.move(to: p(18.5, 5.5))
            path.addLine(to: p(5.5, 18.5))

        case .share:
            // Box with up arrow
            path.addRoundedRect(in: CGRect(x: ox + v(4), y: oy + v(10), width: v(16), height: v(12)), cornerSize: CGSize(width: v(2.5), height: v(2.5)))
            // Arrow shaft
            path.addRoundedRect(in: CGRect(x: ox + v(11), y: oy + v(2), width: v(2), height: v(12)), cornerSize: CGSize(width: v(1), height: v(1)))
            // Arrow head
            path.move(to: p(12, 2))
            path.addLine(to: p(7.5, 7))
            path.addLine(to: p(16.5, 7))
            path.closeSubpath()

        case .checkmark:
            path.move(to: p(4, 12.5))
            path.addLine(to: p(9.5, 18.5))
            path.addLine(to: p(20, 5.5))

        // ─── NAVIGATION ────────────────────────────────────
        case .chevronRight:
            path.move(to: p(9, 4))
            path.addLine(to: p(16, 12))
            path.addLine(to: p(9, 20))

        case .chevronLeft:
            path.move(to: p(15, 4))
            path.addLine(to: p(8, 12))
            path.addLine(to: p(15, 20))

        case .chevronDown:
            path.move(to: p(4, 9))
            path.addLine(to: p(12, 16))
            path.addLine(to: p(20, 9))

        // ─── STATUS & INFO ─────────────────────────────────
        case .clock:
            let cr2 = v(9.5)
            let cx2 = ox + v(12)
            let cy2 = oy + v(12)
            path.addEllipse(in: CGRect(x: cx2 - cr2, y: cy2 - cr2, width: cr2 * 2, height: cr2 * 2))
            // Hour hand
            path.addRoundedRect(in: CGRect(x: ox + v(11.2), y: oy + v(6), width: v(1.6), height: v(6.5)), cornerSize: CGSize(width: v(0.8), height: v(0.8)))
            // Minute hand
            path.addRoundedRect(in: CGRect(x: ox + v(11.8), y: oy + v(11), width: v(5), height: v(1.6)), cornerSize: CGSize(width: v(0.8), height: v(0.8)))
            // Center dot
            path.addEllipse(in: CGRect(x: cx2 - v(1.3), y: cy2 - v(1.3), width: v(2.6), height: v(2.6)))

        case .calendar:
            // Body
            path.addRoundedRect(in: CGRect(x: ox + v(3), y: oy + v(4.5), width: v(18), height: v(16.5)), cornerSize: CGSize(width: v(2.5), height: v(2.5)))
            // Top rings
            path.addRoundedRect(in: CGRect(x: ox + v(7.5), y: oy + v(2.5), width: v(1.8), height: v(4)), cornerSize: CGSize(width: v(0.9), height: v(0.9)))
            path.addRoundedRect(in: CGRect(x: ox + v(14.7), y: oy + v(2.5), width: v(1.8), height: v(4)), cornerSize: CGSize(width: v(0.9), height: v(0.9)))
            // Date dots
            path.addRoundedRect(in: CGRect(x: ox + v(6.5), y: oy + v(11), width: v(2.5), height: v(2.5)), cornerSize: CGSize(width: v(0.8), height: v(0.8)))
            path.addRoundedRect(in: CGRect(x: ox + v(10.75), y: oy + v(11), width: v(2.5), height: v(2.5)), cornerSize: CGSize(width: v(0.8), height: v(0.8)))
            path.addRoundedRect(in: CGRect(x: ox + v(15), y: oy + v(11), width: v(2.5), height: v(2.5)), cornerSize: CGSize(width: v(0.8), height: v(0.8)))
            path.addRoundedRect(in: CGRect(x: ox + v(6.5), y: oy + v(15.5), width: v(2.5), height: v(2.5)), cornerSize: CGSize(width: v(0.8), height: v(0.8)))
            path.addRoundedRect(in: CGRect(x: ox + v(10.75), y: oy + v(15.5), width: v(2.5), height: v(2.5)), cornerSize: CGSize(width: v(0.8), height: v(0.8)))

        case .calendarClock:
            // Same as calendar but with clock overlay
            path.addRoundedRect(in: CGRect(x: ox + v(3), y: oy + v(4.5), width: v(15), height: v(16.5)), cornerSize: CGSize(width: v(2.5), height: v(2.5)))
            path.addRoundedRect(in: CGRect(x: ox + v(7.5), y: oy + v(2.5), width: v(1.8), height: v(4)), cornerSize: CGSize(width: v(0.9), height: v(0.9)))
            path.addRoundedRect(in: CGRect(x: ox + v(13), y: oy + v(2.5), width: v(1.8), height: v(4)), cornerSize: CGSize(width: v(0.9), height: v(0.9)))
            // Small clock
            let scr = v(4.5)
            let scx = ox + v(18)
            let scy = oy + v(16)
            path.addEllipse(in: CGRect(x: scx - scr, y: scy - scr, width: scr * 2, height: scr * 2))

        case .crown:
            // Crown shape
            path.move(to: p(3, 18))
            path.addLine(to: p(4, 8))
            path.addLine(to: p(8, 12))
            path.addLine(to: p(12, 5))
            path.addLine(to: p(16, 12))
            path.addLine(to: p(20, 8))
            path.addLine(to: p(21, 18))
            path.closeSubpath()
            // Base band
            path.addRoundedRect(in: CGRect(x: ox + v(3), y: oy + v(18), width: v(18), height: v(3)), cornerSize: CGSize(width: v(1.5), height: v(1.5)))

        case .sparkles:
            // Three sparkle stars
            // Main sparkle (center-right)
            path.move(to: p(14, 3))
            path.addQuadCurve(to: p(19, 10), control: p(16, 8))
            path.addQuadCurve(to: p(14, 17), control: p(16, 12))
            path.addQuadCurve(to: p(9, 10), control: p(12, 12))
            path.addQuadCurve(to: p(14, 3), control: p(12, 8))
            path.closeSubpath()
            // Small sparkle (left)
            path.move(to: p(5, 4))
            path.addQuadCurve(to: p(8, 8), control: p(6, 6))
            path.addQuadCurve(to: p(5, 12), control: p(6, 10))
            path.addQuadCurve(to: p(2, 8), control: p(4, 10))
            path.addQuadCurve(to: p(5, 4), control: p(4, 6))
            path.closeSubpath()
            // Tiny sparkle (bottom-left)
            path.move(to: p(6, 16))
            path.addQuadCurve(to: p(8, 18.5), control: p(7, 17))
            path.addQuadCurve(to: p(6, 21), control: p(7, 20))
            path.addQuadCurve(to: p(4, 18.5), control: p(5, 20))
            path.addQuadCurve(to: p(6, 16), control: p(5, 17))
            path.closeSubpath()

        case .bolt:
            // Lightning bolt
            path.move(to: p(14, 2))
            path.addLine(to: p(6, 13))
            path.addLine(to: p(11, 13))
            path.addLine(to: p(10, 22))
            path.addLine(to: p(18, 11))
            path.addLine(to: p(13, 11))
            path.closeSubpath()

        case .star:
            // 5-pointed star
            let cx3 = ox + v(12)
            let cy3 = oy + v(12)
            for i in 0..<5 {
                let outerAngle = CGFloat(i) * 2 * .pi / 5 - .pi / 2
                let innerAngle = outerAngle + .pi / 5
                let outerPt = CGPoint(x: cx3 + cos(outerAngle) * v(10), y: cy3 + sin(outerAngle) * v(10))
                let innerPt = CGPoint(x: cx3 + cos(innerAngle) * v(4.5), y: cy3 + sin(innerAngle) * v(4.5))
                if i == 0 { path.move(to: outerPt) }
                else { path.addLine(to: outerPt) }
                path.addLine(to: innerPt)
            }
            path.closeSubpath()

        case .info:
            // Circle with i
            path.addEllipse(in: CGRect(x: ox + v(2.5), y: oy + v(2.5), width: v(19), height: v(19)))
            // Dot
            path.addEllipse(in: CGRect(x: ox + v(10.5), y: oy + v(6.5), width: v(3), height: v(3)))
            // Line
            path.addRoundedRect(in: CGRect(x: ox + v(10.5), y: oy + v(11.5), width: v(3), height: v(7)), cornerSize: CGSize(width: v(1.5), height: v(1.5)))

        case .party:
            // Party popper - cone with streamers
            path.move(to: p(4, 20))
            path.addLine(to: p(10, 8))
            path.addQuadCurve(to: p(16, 14), control: p(14, 10))
            path.closeSubpath()
            // Streamers
            path.move(to: p(13, 7))
            path.addQuadCurve(to: p(19, 3), control: p(15, 3))
            path.move(to: p(16, 10))
            path.addQuadCurve(to: p(21, 7), control: p(20, 10))
            path.move(to: p(17, 13))
            path.addQuadCurve(to: p(21, 12), control: p(19, 14))
            // Confetti dots
            path.addEllipse(in: CGRect(x: ox + v(8), y: oy + v(3), width: v(2), height: v(2)))
            path.addEllipse(in: CGRect(x: ox + v(18), y: oy + v(5), width: v(1.5), height: v(1.5)))
            path.addEllipse(in: CGRect(x: ox + v(20), y: oy + v(14), width: v(1.5), height: v(1.5)))

        case .checklist:
            // Checkmarks and lines
            // Item 1
            path.move(to: p(4, 6))
            path.addLine(to: p(6, 8.5))
            path.addLine(to: p(10, 4))
            path.move(to: p(12, 6.5))
            path.addLine(to: p(20, 6.5))
            // Item 2
            path.move(to: p(4, 12.5))
            path.addLine(to: p(6, 15))
            path.addLine(to: p(10, 10.5))
            path.move(to: p(12, 13))
            path.addLine(to: p(20, 13))
            // Item 3
            path.addRoundedRect(in: CGRect(x: ox + v(4), y: oy + v(17.5), width: v(5), height: v(4)), cornerSize: CGSize(width: v(1), height: v(1)))
            path.move(to: p(12, 19.5))
            path.addLine(to: p(20, 19.5))

        case .signOut:
            // Door with arrow
            path.addRoundedRect(in: CGRect(x: ox + v(3), y: oy + v(3), width: v(10), height: v(18)), cornerSize: CGSize(width: v(2), height: v(2)))
            // Arrow shaft
            path.addRoundedRect(in: CGRect(x: ox + v(11), y: oy + v(11), width: v(9), height: v(2)), cornerSize: CGSize(width: v(1), height: v(1)))
            // Arrow head
            path.move(to: p(17, 7.5))
            path.addLine(to: p(21.5, 12))
            path.addLine(to: p(17, 16.5))

        case .seal:
            // Checkmark seal / badge
            let sealCx = ox + v(12)
            let sealCy = oy + v(12)
            // Wavy circle
            for i in 0..<12 {
                let angle = CGFloat(i) * .pi / 6
                let nextAngle = CGFloat(i + 1) * .pi / 6
                let midAngle = (angle + nextAngle) / 2
                let r1 = v(10.5)
                let r2 = v(8.5)
                let pt = CGPoint(x: sealCx + cos(nextAngle) * r1, y: sealCy + sin(nextAngle) * r1)
                let ctrl = CGPoint(x: sealCx + cos(midAngle) * r2, y: sealCy + sin(midAngle) * r2)
                if i == 0 {
                    path.move(to: CGPoint(x: sealCx + cos(angle) * r1, y: sealCy + sin(angle) * r1))
                }
                path.addQuadCurve(to: pt, control: ctrl)
            }
            path.closeSubpath()
            // Checkmark inside
            path.move(to: p(8, 12.5))
            path.addLine(to: p(11, 15.5))
            path.addLine(to: p(16.5, 9))

        // ─── COMMUNICATION ─────────────────────────────────
        case .envelope:
            // Envelope body
            path.addRoundedRect(in: CGRect(x: ox + v(2), y: oy + v(5), width: v(20), height: v(14)), cornerSize: CGSize(width: v(2.5), height: v(2.5)))
            // Flap
            path.move(to: p(2.5, 6))
            path.addLine(to: p(12, 14))
            path.addLine(to: p(21.5, 6))

        case .phone:
            // Phone
            path.addRoundedRect(in: CGRect(x: ox + v(5), y: oy + v(2), width: v(14), height: v(20)), cornerSize: CGSize(width: v(3), height: v(3)))
            // Screen
            path.addRoundedRect(in: CGRect(x: ox + v(7), y: oy + v(4.5), width: v(10), height: v(12.5)), cornerSize: CGSize(width: v(1.5), height: v(1.5)))
            // Home button
            path.addEllipse(in: CGRect(x: ox + v(10.5), y: oy + v(18.5), width: v(3), height: v(2)))

        case .chat:
            // Chat bubble
            path.move(to: p(4, 5))
            path.addQuadCurve(to: p(20, 5), control: p(12, 2))
            path.addQuadCurve(to: p(20, 15), control: p(22, 10))
            path.addQuadCurve(to: p(4, 15), control: p(12, 18))
            path.addQuadCurve(to: p(4, 5), control: p(2, 10))
            path.closeSubpath()
            // Tail
            path.move(to: p(6, 15))
            path.addQuadCurve(to: p(3, 21), control: p(3, 18))
            path.addQuadCurve(to: p(10, 16), control: p(8, 19))
            // Dots
            path.addEllipse(in: CGRect(x: ox + v(7.5), y: oy + v(9), width: v(2), height: v(2)))
            path.addEllipse(in: CGRect(x: ox + v(11), y: oy + v(9), width: v(2), height: v(2)))
            path.addEllipse(in: CGRect(x: ox + v(14.5), y: oy + v(9), width: v(2), height: v(2)))

        // ─── OBJECTS ────────────────────────────────────────
        case .tag:
            path.move(to: p(3, 4))
            path.addLine(to: p(13, 4))
            path.addLine(to: p(21, 12))
            path.addLine(to: p(12, 21))
            path.addLine(to: p(3, 12))
            path.closeSubpath()
            // Hole
            path.addEllipse(in: CGRect(x: ox + v(6.5), y: oy + v(6.5), width: v(3), height: v(3)))

        case .flag:
            // Pole
            path.addRoundedRect(in: CGRect(x: ox + v(4), y: oy + v(2), width: v(2), height: v(20)), cornerSize: CGSize(width: v(1), height: v(1)))
            // Flag
            path.move(to: p(6, 3))
            path.addLine(to: p(20, 6))
            path.addLine(to: p(6, 13))
            path.closeSubpath()

        case .lock:
            // Body
            path.addRoundedRect(in: CGRect(x: ox + v(5), y: oy + v(10), width: v(14), height: v(11)), cornerSize: CGSize(width: v(2.5), height: v(2.5)))
            // Shackle
            path.move(to: p(8, 10))
            path.addLine(to: p(8, 7))
            path.addQuadCurve(to: p(16, 7), control: p(12, 2))
            path.addLine(to: p(16, 10))
            // Keyhole
            path.addEllipse(in: CGRect(x: ox + v(10.5), y: oy + v(13.5), width: v(3), height: v(3)))
            path.addRoundedRect(in: CGRect(x: ox + v(11.2), y: oy + v(15.5), width: v(1.6), height: v(3)), cornerSize: CGSize(width: v(0.8), height: v(0.8)))

        case .eye:
            // Eye shape
            path.move(to: p(2, 12))
            path.addQuadCurve(to: p(12, 5), control: p(6, 5))
            path.addQuadCurve(to: p(22, 12), control: p(18, 5))
            path.addQuadCurve(to: p(12, 19), control: p(18, 19))
            path.addQuadCurve(to: p(2, 12), control: p(6, 19))
            path.closeSubpath()
            // Iris
            path.addEllipse(in: CGRect(x: ox + v(8.5), y: oy + v(8.5), width: v(7), height: v(7)))
            // Pupil
            path.addEllipse(in: CGRect(x: ox + v(10.5), y: oy + v(10.5), width: v(3), height: v(3)))

        case .camera:
            // Body
            path.addRoundedRect(in: CGRect(x: ox + v(2), y: oy + v(7), width: v(20), height: v(13)), cornerSize: CGSize(width: v(2.5), height: v(2.5)))
            // Top bump
            path.addRoundedRect(in: CGRect(x: ox + v(8), y: oy + v(4), width: v(8), height: v(4)), cornerSize: CGSize(width: v(1.5), height: v(1.5)))
            // Lens
            let lensR = v(3.5)
            let lensCx = ox + v(12)
            let lensCy = oy + v(14)
            path.addEllipse(in: CGRect(x: lensCx - lensR, y: lensCy - lensR, width: lensR * 2, height: lensR * 2))

        case .lightbulb:
            // Bulb
            path.addEllipse(in: CGRect(x: ox + v(5), y: oy + v(2), width: v(14), height: v(14)))
            // Base
            path.addRoundedRect(in: CGRect(x: ox + v(8), y: oy + v(16), width: v(8), height: v(2)), cornerSize: CGSize(width: v(0.5), height: v(0.5)))
            path.addRoundedRect(in: CGRect(x: ox + v(9), y: oy + v(19), width: v(6), height: v(2)), cornerSize: CGSize(width: v(1), height: v(1)))
            // Filament
            path.move(to: p(10, 12))
            path.addQuadCurve(to: p(14, 12), control: p(12, 8))

        case .megaphone:
            // Cone
            path.move(to: p(18, 4))
            path.addLine(to: p(18, 18))
            path.addLine(to: p(6, 14))
            path.addLine(to: p(6, 8))
            path.closeSubpath()
            // Speaker base
            path.addRoundedRect(in: CGRect(x: ox + v(3), y: oy + v(7.5), width: v(4), height: v(7)), cornerSize: CGSize(width: v(1.5), height: v(1.5)))
            // Sound waves
            path.move(to: p(20, 8))
            path.addQuadCurve(to: p(20, 14), control: p(22, 11))

        case .paintbrush:
            // Handle
            path.move(to: p(4, 21))
            path.addQuadCurve(to: p(6, 19), control: p(4, 19.5))
            path.addLine(to: p(15, 10))
            path.addLine(to: p(13, 8))
            path.addLine(to: p(4.5, 17))
            path.addQuadCurve(to: p(4, 21), control: p(3, 19))
            path.closeSubpath()
            // Brush head
            path.move(to: p(14, 9))
            path.addLine(to: p(16, 11))
            path.addQuadCurve(to: p(21, 6), control: p(19, 9))
            path.addQuadCurve(to: p(18, 3), control: p(22, 3))
            path.addQuadCurve(to: p(14, 9), control: p(15, 6))
            path.closeSubpath()

        case .drop:
            // Water drop
            path.move(to: p(12, 3))
            path.addQuadCurve(to: p(5, 14), control: p(6, 8))
            path.addQuadCurve(to: p(12, 21), control: p(5, 19))
            path.addQuadCurve(to: p(19, 14), control: p(19, 19))
            path.addQuadCurve(to: p(12, 3), control: p(18, 8))
            path.closeSubpath()

        case .creditcard:
            // Card body
            path.addRoundedRect(in: CGRect(x: ox + v(2), y: oy + v(5), width: v(20), height: v(14)), cornerSize: CGSize(width: v(2.5), height: v(2.5)))
            // Stripe
            path.addRect(CGRect(x: ox + v(2), y: oy + v(8.5), width: v(20), height: v(3)))
            // Chip
            path.addRoundedRect(in: CGRect(x: ox + v(5), y: oy + v(14), width: v(4), height: v(2.5)), cornerSize: CGSize(width: v(0.5), height: v(0.5)))

        case .banknote:
            path.addRoundedRect(in: CGRect(x: ox + v(1.5), y: oy + v(5.5), width: v(21), height: v(13)), cornerSize: CGSize(width: v(2), height: v(2)))
            // Inner border
            path.addRoundedRect(in: CGRect(x: ox + v(3.5), y: oy + v(7.5), width: v(17), height: v(9)), cornerSize: CGSize(width: v(1.5), height: v(1.5)))
            // Dollar symbol (center circle)
            path.addEllipse(in: CGRect(x: ox + v(9), y: oy + v(9), width: v(6), height: v(6)))

        case .doc:
            // Document
            path.addRoundedRect(in: CGRect(x: ox + v(4), y: oy + v(2), width: v(16), height: v(20)), cornerSize: CGSize(width: v(2.5), height: v(2.5)))
            // Lines
            path.addRoundedRect(in: CGRect(x: ox + v(7), y: oy + v(7), width: v(10), height: v(1.5)), cornerSize: CGSize(width: v(0.75), height: v(0.75)))
            path.addRoundedRect(in: CGRect(x: ox + v(7), y: oy + v(11), width: v(8), height: v(1.5)), cornerSize: CGSize(width: v(0.75), height: v(0.75)))
            path.addRoundedRect(in: CGRect(x: ox + v(7), y: oy + v(15), width: v(6), height: v(1.5)), cornerSize: CGSize(width: v(0.75), height: v(0.75)))

        case .docGear:
            // Document with gear
            path.addRoundedRect(in: CGRect(x: ox + v(3), y: oy + v(2), width: v(14), height: v(18)), cornerSize: CGSize(width: v(2), height: v(2)))
            path.addRoundedRect(in: CGRect(x: ox + v(6), y: oy + v(6), width: v(8), height: v(1.3)), cornerSize: CGSize(width: v(0.6), height: v(0.6)))
            path.addRoundedRect(in: CGRect(x: ox + v(6), y: oy + v(9), width: v(5), height: v(1.3)), cornerSize: CGSize(width: v(0.6), height: v(0.6)))
            // Small gear
            let gx = ox + v(18.5)
            let gy = oy + v(17)
            let gr = v(3.5)
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3
                let tw = v(1.5)
                let ttx = gx + cos(a) * (gr - v(0.5))
                let tty = gy + sin(a) * (gr - v(0.5))
                path.addRoundedRect(in: CGRect(x: ttx - tw / 2, y: tty - tw / 2, width: tw, height: tw), cornerSize: CGSize(width: v(0.3), height: v(0.3)))
            }
            path.addEllipse(in: CGRect(x: gx - v(2.5), y: gy - v(2.5), width: v(5), height: v(5)))
            path.addEllipse(in: CGRect(x: gx - v(1.2), y: gy - v(1.2), width: v(2.4), height: v(2.4)))

        case .folder:
            // Folder body
            path.move(to: p(2, 7))
            path.addQuadCurve(to: p(4, 5), control: p(2, 5))
            path.addLine(to: p(9, 5))
            path.addLine(to: p(11, 7))
            path.addLine(to: p(20, 7))
            path.addQuadCurve(to: p(22, 9), control: p(22, 7))
            path.addLine(to: p(22, 19))
            path.addQuadCurve(to: p(20, 21), control: p(22, 21))
            path.addLine(to: p(4, 21))
            path.addQuadCurve(to: p(2, 19), control: p(2, 21))
            path.closeSubpath()

        case .chartPie:
            // Pie chart
            let pcx = ox + v(12)
            let pcy = oy + v(12)
            let pr = v(9.5)
            path.addEllipse(in: CGRect(x: pcx - pr, y: pcy - pr, width: pr * 2, height: pr * 2))
            // Slice lines
            path.move(to: CGPoint(x: pcx, y: pcy))
            path.addLine(to: CGPoint(x: pcx, y: pcy - pr))
            path.move(to: CGPoint(x: pcx, y: pcy))
            path.addLine(to: CGPoint(x: pcx + cos(.pi / 4) * pr, y: pcy + sin(.pi / 4) * pr))
            path.move(to: CGPoint(x: pcx, y: pcy))
            path.addLine(to: CGPoint(x: pcx - cos(.pi / 6) * pr, y: pcy + sin(.pi / 6) * pr))

        case .chartLine:
            // Line chart
            path.addRoundedRect(in: CGRect(x: ox + v(3), y: oy + v(3), width: v(1.5), height: v(17)), cornerSize: CGSize(width: v(0.75), height: v(0.75)))
            path.addRoundedRect(in: CGRect(x: ox + v(3), y: oy + v(18.5), width: v(18), height: v(1.5)), cornerSize: CGSize(width: v(0.75), height: v(0.75)))
            // Line
            path.move(to: p(6, 16))
            path.addLine(to: p(10, 10))
            path.addLine(to: p(14, 13))
            path.addLine(to: p(19, 6))

        case .bus:
            path.addRoundedRect(in: CGRect(x: ox + v(3), y: oy + v(4), width: v(18), height: v(14)), cornerSize: CGSize(width: v(3), height: v(3)))
            // Windows
            path.addRoundedRect(in: CGRect(x: ox + v(5.5), y: oy + v(7), width: v(5), height: v(4)), cornerSize: CGSize(width: v(1), height: v(1)))
            path.addRoundedRect(in: CGRect(x: ox + v(13.5), y: oy + v(7), width: v(5), height: v(4)), cornerSize: CGSize(width: v(1), height: v(1)))
            // Wheels
            path.addEllipse(in: CGRect(x: ox + v(6), y: oy + v(16.5), width: v(3.5), height: v(3.5)))
            path.addEllipse(in: CGRect(x: ox + v(14.5), y: oy + v(16.5), width: v(3.5), height: v(3.5)))

        case .airplane:
            // Airplane
            path.move(to: p(12, 2))
            path.addQuadCurve(to: p(14, 8), control: p(14, 4))
            path.addLine(to: p(21, 11))
            path.addQuadCurve(to: p(21, 13), control: p(22, 12))
            path.addLine(to: p(14, 11))
            path.addLine(to: p(14, 17))
            path.addLine(to: p(18, 19))
            path.addQuadCurve(to: p(17, 20.5), control: p(18, 20.5))
            path.addLine(to: p(12, 19))
            path.addLine(to: p(7, 20.5))
            path.addQuadCurve(to: p(6, 19), control: p(6, 20.5))
            path.addLine(to: p(10, 17))
            path.addLine(to: p(10, 11))
            path.addLine(to: p(3, 13))
            path.addQuadCurve(to: p(3, 11), control: p(2, 12))
            path.addLine(to: p(10, 8))
            path.addQuadCurve(to: p(12, 2), control: p(10, 4))
            path.closeSubpath()

        case .tram:
            // Tram/streetcar
            path.addRoundedRect(in: CGRect(x: ox + v(4), y: oy + v(5), width: v(16), height: v(13)), cornerSize: CGSize(width: v(3), height: v(3)))
            // Top pole
            path.addRoundedRect(in: CGRect(x: ox + v(11), y: oy + v(2), width: v(2), height: v(4)), cornerSize: CGSize(width: v(1), height: v(1)))
            // Wire
            path.move(to: p(7, 2.5))
            path.addLine(to: p(17, 2.5))
            // Windows
            path.addRoundedRect(in: CGRect(x: ox + v(6.5), y: oy + v(8), width: v(4), height: v(3.5)), cornerSize: CGSize(width: v(1), height: v(1)))
            path.addRoundedRect(in: CGRect(x: ox + v(13.5), y: oy + v(8), width: v(4), height: v(3.5)), cornerSize: CGSize(width: v(1), height: v(1)))
            // Wheels
            path.addEllipse(in: CGRect(x: ox + v(7), y: oy + v(17), width: v(3), height: v(3)))
            path.addEllipse(in: CGRect(x: ox + v(14), y: oy + v(17), width: v(3), height: v(3)))

        case .target:
            // Target / bullseye
            path.addEllipse(in: CGRect(x: ox + v(2), y: oy + v(2), width: v(20), height: v(20)))
            path.addEllipse(in: CGRect(x: ox + v(5.5), y: oy + v(5.5), width: v(13), height: v(13)))
            path.addEllipse(in: CGRect(x: ox + v(9), y: oy + v(9), width: v(6), height: v(6)))

        case .percent:
            // Percent sign
            path.addEllipse(in: CGRect(x: ox + v(4), y: oy + v(4), width: v(6), height: v(6)))
            path.addEllipse(in: CGRect(x: ox + v(14), y: oy + v(14), width: v(6), height: v(6)))
            // Diagonal line
            path.move(to: p(18, 4))
            path.addLine(to: p(6, 20))

        case .icloud:
            // Cloud shape
            path.move(to: p(6, 18))
            path.addQuadCurve(to: p(4, 14), control: p(2, 17))
            path.addQuadCurve(to: p(8, 9), control: p(4, 10))
            path.addQuadCurve(to: p(14, 7), control: p(10, 6))
            path.addQuadCurve(to: p(20, 10), control: p(18, 6))
            path.addQuadCurve(to: p(20, 18), control: p(23, 13))
            path.closeSubpath()

        // ─── NUMBER BADGES ─────────────────────────────────
        case .num1:
            path.addEllipse(in: CGRect(x: ox + v(2), y: oy + v(2), width: v(20), height: v(20)))
            path.move(to: p(10, 8.5))
            path.addLine(to: p(13, 7))
            path.addLine(to: p(13, 17))
            path.move(to: p(9.5, 17))
            path.addLine(to: p(16, 17))

        case .num2:
            path.addEllipse(in: CGRect(x: ox + v(2), y: oy + v(2), width: v(20), height: v(20)))
            path.move(to: p(8, 10))
            path.addQuadCurve(to: p(12, 7), control: p(8, 7))
            path.addQuadCurve(to: p(16, 10), control: p(16, 7))
            path.addLine(to: p(8, 17))
            path.addLine(to: p(16, 17))

        case .num3:
            path.addEllipse(in: CGRect(x: ox + v(2), y: oy + v(2), width: v(20), height: v(20)))
            path.move(to: p(8, 8))
            path.addQuadCurve(to: p(12, 7), control: p(10, 6.5))
            path.addQuadCurve(to: p(12, 12), control: p(15, 8))
            path.addQuadCurve(to: p(12, 17), control: p(15, 16))
            path.addQuadCurve(to: p(8, 16), control: p(10, 17.5))
        }

        return path
    }
}

// MARK: - Icon View (renders single icon)
struct LHIconView: View {
    let icon: LHIcon
    var size: CGFloat = 24
    var color: Color = AppColors.primary
    var strokeStyle: Bool = false

    private var strokeIcons: Set<LHIcon> {
        [.close, .checkmark, .chevronRight, .chevronLeft, .chevronDown,
         .checklist, .chartLine, .percent, .envelope, .insurance]
    }

    var body: some View {
        Group {
            if strokeStyle || strokeIcons.contains(icon) {
                LHIconShape(icon: icon)
                    .stroke(color, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round, lineJoin: .round))
            } else {
                LHIconShape(icon: icon)
                    .fill(color)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Icon Badge (Tiimo-style colored background)
struct LHIconBadge: View {
    let icon: LHIcon
    var bgColor: Color = AppColors.primary
    var fgColor: Color = .white
    var size: CGFloat = 44
    var iconScale: CGFloat = 0.5
    var cornerRadius: CGFloat? = nil
    var useGradient: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.28)
                .fill(
                    useGradient ?
                    AnyShapeStyle(
                        LinearGradient(
                            colors: [bgColor.opacity(0.9), bgColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    ) :
                    AnyShapeStyle(bgColor)
                )
                .shadow(color: bgColor.opacity(0.25), radius: size * 0.08, y: size * 0.04)

            LHIconView(icon: icon, size: size * iconScale, color: fgColor)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Soft Badge (pastel background, darker icon)
struct LHSoftBadge: View {
    let icon: LHIcon
    var color: Color = AppColors.primary
    var size: CGFloat = 44
    var iconScale: CGFloat = 0.5

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(color.opacity(0.12))

            LHIconView(icon: icon, size: size * iconScale, color: color)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Circle Badge
struct LHCircleBadge: View {
    let icon: LHIcon
    var bgColor: Color = AppColors.primary
    var fgColor: Color = .white
    var size: CGFloat = 44
    var iconScale: CGFloat = 0.5

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [bgColor.opacity(0.85), bgColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: bgColor.opacity(0.3), radius: size * 0.08, y: size * 0.04)

            LHIconView(icon: icon, size: size * iconScale, color: fgColor)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Tab Bar Icon
struct LHTabIcon: View {
    let icon: LHIcon
    let label: String
    var isSelected: Bool = false

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(AppColors.primary.opacity(0.12))
                        .frame(width: 36, height: 36)
                }

                LHIconView(
                    icon: icon,
                    size: 22,
                    color: isSelected ? AppColors.primary : (colorScheme == .dark ? Color.gray : AppColors.textTertiary)
                )
            }

            Text(label)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AppColors.primary : (colorScheme == .dark ? Color.gray : AppColors.textTertiary))
        }
    }
}

// MARK: - SF Symbol to LHIcon Mapping
extension LHIcon {
    /// Map SF Symbol names to LHIcon cases for backward compatibility
    static func from(sfSymbol: String) -> LHIcon? {
        let mapping: [String: LHIcon] = [
            "house.fill": .home,
            "building.2.fill": .properties,
            "building.fill": .properties,
            "timer": .track,
            "chart.bar.fill": .reports,
            "gearshape.fill": .settings,
            "wrench.fill": .repairs,
            "folder.fill": .folder,
            "building.2": .properties,
            "key.fill": .leasing,
            "doc.text.fill": .doc,
            "building.columns.fill": .legal,
            "shield.fill": .insurance,
            "car.fill": .travel,
            "hammer.fill": .renovations,
            "chart.line.uptrend.xyaxis": .investing,
            "dollarsign.circle.fill": .financing,
            "signature": .contract,
            "calculator": .bookkeeping,
            "doc.badge.gearshape": .docGear,
            "person.fill": .person,
            "person.2.fill": .personTwo,
            "plus": .plus,
            "plus.circle.fill": .plusCircle,
            "trash": .trash,
            "pencil": .pencil,
            "xmark": .close,
            "square.and.arrow.up": .share,
            "checkmark": .checkmark,
            "checkmark.circle.fill": .checkmark,
            "checkmark.seal.fill": .seal,
            "chevron.right": .chevronRight,
            "chevron.left": .chevronLeft,
            "chevron.down": .chevronDown,
            "clock.fill": .clock,
            "calendar": .calendar,
            "calendar.badge.clock": .calendarClock,
            "crown.fill": .crown,
            "sparkles": .sparkles,
            "bolt.fill": .bolt,
            "star.fill": .star,
            "info.circle.fill": .info,
            "info.circle": .info,
            "party.popper.fill": .party,
            "checklist": .checklist,
            "rectangle.portrait.and.arrow.right": .signOut,
            "envelope.fill": .envelope,
            "phone.fill": .phone,
            "bubble.left.fill": .chat,
            "tag.fill": .tag,
            "flag.fill": .flag,
            "lock.fill": .lock,
            "eye.fill": .eye,
            "camera.fill": .camera,
            "lightbulb.fill": .lightbulb,
            "megaphone.fill": .megaphone,
            "paintbrush.fill": .paintbrush,
            "drop.fill": .drop,
            "creditcard.fill": .creditcard,
            "banknote.fill": .banknote,
            "doc.fill": .doc,
            "chart.pie.fill": .chartPie,
            "bus.fill": .bus,
            "airplane": .airplane,
            "tram.fill": .tram,
            "target": .target,
            "percent": .percent,
            "icloud.fill": .icloud,
            "questionmark.circle.fill": .info,
            "heart.fill": .star,
            "square.grid.2x2": .management,
            "1.circle.fill": .num1,
            "2.circle.fill": .num2,
            "3.circle.fill": .num3,
            "chart.bar.doc.horizontal": .reports,
            "person.circle.fill": .person,
            "apple.logo": .home, // fallback
        ]
        return mapping[sfSymbol]
    }

    /// Get the SF Symbol name this icon replaces (for use in tab items)
    @available(iOS 16.0, *)
    @MainActor var tabItemImage: Image {
        let renderer = ImageRenderer(content:
            LHIconShape(icon: self)
                .fill(.black)
                .frame(width: 24, height: 24)
        )
        renderer.scale = 3.0
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage.withRenderingMode(.alwaysTemplate))
        }
        return Image(systemName: "questionmark")
    }
}

// MARK: - Dynamic Icon View (accepts either LHIcon or SF Symbol string)
struct DynamicIconView: View {
    let name: String
    var size: CGFloat = 24
    var color: Color = AppColors.primary

    var body: some View {
        if let lhIcon = LHIcon.from(sfSymbol: name) {
            LHIconView(icon: lhIcon, size: size, color: color)
        } else {
            // Fallback to SF Symbol for any unmapped icons
            Image(systemName: name)
                .font(.system(size: size * 0.7))
                .foregroundStyle(color)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Dynamic Badge View (accepts SF Symbol string)
struct DynamicBadgeView: View {
    let iconName: String
    var bgColor: Color = AppColors.primary
    var fgColor: Color = .white
    var size: CGFloat = 44
    var iconScale: CGFloat = 0.5

    var body: some View {
        if let lhIcon = LHIcon.from(sfSymbol: iconName) {
            LHIconBadge(icon: lhIcon, bgColor: bgColor, fgColor: fgColor, size: size, iconScale: iconScale)
        } else {
            // Fallback badge with SF Symbol
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.28)
                    .fill(
                        LinearGradient(
                            colors: [bgColor.opacity(0.9), bgColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: bgColor.opacity(0.25), radius: size * 0.08, y: size * 0.04)

                Image(systemName: iconName)
                    .font(.system(size: size * iconScale))
                    .foregroundStyle(fgColor)
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Category Badge Colors
extension LHIcon {
    static func categoryColor(for name: String) -> Color {
        let mapping: [String: Color] = [
            "Repairs & Maintenance": Color(hex: "8B5CF6"),
            "Property Management": Color(hex: "34D399"),
            "Leasing & Tenant Relations": Color(hex: "60A5FA"),
            "Bookkeeping & Financial": Color(hex: "FBBF24"),
            "Legal & Compliance": Color(hex: "F472B6"),
            "Insurance & Claims": Color(hex: "A78BFA"),
            "Travel to Property": Color(hex: "3B82F6"),
            "Renovations & Improvements": Color(hex: "EF4444"),
            "Investing Decisions": Color(hex: "6B7280"),
            "Financing": Color(hex: "F59E0B"),
            "Contract Negotiation": Color(hex: "EC4899"),
        ]
        return mapping[name] ?? AppColors.primary
    }
}

// MARK: - Preview
#Preview("Icon Gallery") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
            ForEach(LHIcon.allCases) { icon in
                VStack(spacing: 8) {
                    LHIconBadge(
                        icon: icon,
                        bgColor: AppColors.primary,
                        size: 48
                    )
                    Text(icon.rawValue)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding()
    }
}

#Preview("Badge Styles") {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            LHIconBadge(icon: .home, bgColor: AppColors.primary, size: 56)
            LHSoftBadge(icon: .properties, color: Color(hex: "34D399"), size: 56)
            LHCircleBadge(icon: .track, bgColor: Color(hex: "60A5FA"), size: 56)
            LHIconBadge(icon: .reports, bgColor: Color(hex: "FBBF24"), size: 56)
        }

        HStack(spacing: 16) {
            LHIconBadge(icon: .repairs, bgColor: Color(hex: "8B5CF6"), size: 48)
            LHIconBadge(icon: .leasing, bgColor: Color(hex: "60A5FA"), size: 48)
            LHIconBadge(icon: .travel, bgColor: Color(hex: "3B82F6"), size: 48)
            LHIconBadge(icon: .renovations, bgColor: Color(hex: "EF4444"), size: 48)
        }

        HStack(spacing: 24) {
            LHTabIcon(icon: .home, label: "Home", isSelected: true)
            LHTabIcon(icon: .properties, label: "Properties")
            LHTabIcon(icon: .track, label: "Track")
            LHTabIcon(icon: .reports, label: "Reports")
            LHTabIcon(icon: .settings, label: "Settings")
        }
    }
    .padding()
}

// MARK: - Lucide Icon Bridge
import LucideIcons

/// SwiftUI Image from a Lucide UIImage. Use `.renderingMode(.template)` to tint via `foregroundStyle`.
struct LucideIcon: View {
    let image: UIImage
    var size: CGFloat = 24

    var body: some View {
        Image(uiImage: image)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// Convenience: map a Lucide static property name to a SwiftUI Image.
/// Usage: `lucideImage(Lucide.house)` or just use `LucideIcon(image: Lucide.house)`
func lucideImage(_ img: UIImage) -> Image {
    Image(uiImage: img).renderingMode(.template)
}
