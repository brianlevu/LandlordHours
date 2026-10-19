import SwiftUI

/// One keyframe of the Blueprint house: the built pass with the tinted linework ABOVE it (the
/// built structure is already cut out of the linework, so lines only show over unbuilt parts).
/// Each pair shares one 320 pt square camera. Decorative: the container owns the a11y label.
struct HouseArtView: View {
    let keyframe: HouseKeyframe
    var canvas: HouseCanvas = .blueprintHero
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Image(decorative: keyframe.builtImageName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
            Image(decorative: keyframe.linesImageName)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .foregroundStyle(canvas.linework(for: colorScheme))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The linework only, for the backfill sketch-in.
struct HouseLineworkView: View {
    let keyframe: HouseKeyframe
    var canvas: HouseCanvas = .blueprintHero
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(decorative: keyframe.linesImageName)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .foregroundStyle(canvas.linework(for: colorScheme))
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

/// Found-but-unconfirmed hours: the keyframe's built silhouette drawn as drafting hatch, never
/// solid ("a graphic never shows an unconfirmed hour").
struct HouseHatchedView: View {
    let keyframe: HouseKeyframe
    var canvas: HouseCanvas = .blueprintHero
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tint = canvas.linework(for: colorScheme)
        ZStack {
            Image(decorative: keyframe.builtImageName)
                .resizable()
                .scaledToFit()
                .opacity(0.12)
                .saturation(0)
            HouseHatchPattern()
                .stroke(tint, lineWidth: 1.4)
                .mask(
                    Image(decorative: keyframe.builtImageName)
                        .resizable()
                        .scaledToFit()
                )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Diagonal drafting hatch.
struct HouseHatchPattern: Shape {
    var spacing: CGFloat = 7
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = -rect.height
        while x < rect.width {
            p.move(to: CGPoint(x: rect.minX + x, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + x + rect.height, y: rect.minY))
            x += spacing
        }
        return p
    }
}

/// Reveals content from the bottom up: everything below `progress` (0 = nothing, 1 = all) shows,
/// with a soft edge. Animates its geometry, never gradient stops.
struct HouseRisingMask: View, Animatable {
    var progress: CGFloat
    var feather: CGFloat = 0.04

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            let visible = max(0, min(1, progress)) * (1 + feather) * h
            let edge = min(feather * h, visible)
            VStack(spacing: 0) {
                Color.clear
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: edge)
                Color.black.frame(height: max(0, visible - edge))
            }
            .frame(width: g.size.width, height: h, alignment: .bottom)
            .clipped()
        }
    }
}
