import SwiftUI

// MARK: - Legacy stake shim (plan package B → deleted with package C's HouseHeroView)
//
// v2 retires the onboarding lot scene (the blueprint band, the linework, the hats and the scan
// line): Welcome shows the crafted house and the steps carry no picture (standard §H.5). The
// stake and flag below are kept ONLY because `House/HouseHeroView.swift` (package C, deleted when
// the Today port lands) still draws them. Nothing in onboarding uses them. Delete this file in the
// same change that deletes `HouseHeroView.swift`.

enum OnbScene {
    /// Measured on the k00 lot render: where the stake stands (HouseHeroView's camera).
    static let stakeBase = CGPoint(x: 0.62, y: 0.79)
}

struct OnbFlag: View {
    let name: String
    var maxTextWidth: CGFloat? = nil
    var body: some View {
        HStack(spacing: 0) {
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HouseTokens.flagInk)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: maxTextWidth, alignment: .leading)
                .padding(.leading, 7).padding(.trailing, 4)
                .padding(.vertical, 2)
                .frame(maxHeight: .infinity)
                .background(HouseTokens.flagPaper)
            OnbPennantTail().fill(HouseTokens.flagPaper).frame(width: 9)
        }
        .overlay(alignment: .leading) { Rectangle().fill(HouseTokens.timberDark).frame(width: 2) }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1.5)
        .dynamicTypeSize(.large)           // drawn into the scene; the sheet carries the readable copy
        .accessibilityHidden(true)
    }
}

private struct OnbPennantTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.35, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath()
        return p
    }
}

/// The stake + flag, in a hero's keyframe camera (Today).
struct OnbMiniStake: View {
    var name: String
    /// Room to the right of the post; the sign shrinks or wraps to fit it, never clips.
    var maxFlagWidth: CGFloat? = nil
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
                    .overlay(alignment: .leading) {
                        let w = maxFlagWidth ?? (s - s * b.x - 6)
                        OnbFlag(name: name, maxTextWidth: max(40, w - 22))
                            .frame(minHeight: 16)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: w, alignment: .leading)
                    }
                    .position(x: s * b.x + 1.5, y: s * b.y - s * 0.2 + 8)
            }
        }
        .accessibilityHidden(true)
    }
}
