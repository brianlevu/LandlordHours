// Copied verbatim from release/2.0 (e52177e) so the sandbox renders the shipped house.
import SwiftUI
import UIKit
import CoreImage

/// The exported linework (template, alpha only) with its alpha lifted by
/// `HouseMotion.lineworkAlphaGain`, so tinted strokes reach the drafting token's contrast instead
/// of a 0.36-alpha ghost. Built once per asset and cached. Decorative.
struct HouseLineworkImage: View {
    let name: String

    var body: some View {
        Group {
            if let image = HouseLineworkStore.image(named: name) {
                Image(uiImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(decorative: name)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            }
        }
        .accessibilityHidden(true)
    }
}

enum HouseLineworkStore {
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()
    private static let context = CIContext()

    static func image(named name: String, gain: Double = HouseMotion.lineworkAlphaGain) -> UIImage? {
        let key = "\(name)@\(gain)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = UIImage(named: name), let cg = source.cgImage else { return nil }
        let input = CIImage(cgImage: cg)
        guard let matrix = CIFilter(name: "CIColorMatrix"), let clamp = CIFilter(name: "CIColorClamp") else { return nil }
        matrix.setValue(input, forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(gain)), forKey: "inputAVector")
        clamp.setValue(matrix.outputImage, forKey: kCIInputImageKey)
        guard let output = clamp.outputImage,
              let rendered = context.createCGImage(output, from: input.extent) else { return nil }
        let image = UIImage(cgImage: rendered, scale: source.scale, orientation: .up).withRenderingMode(.alwaysTemplate)
        cache.setObject(image, forKey: key)
        return image
    }
}

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
            HouseLineworkImage(name: keyframe.linesImageName)
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
        HouseLineworkImage(name: keyframe.linesImageName)
            .foregroundStyle(canvas.linework(for: colorScheme))
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

/// Found-but-unconfirmed hours: the keyframe's built silhouette drawn as drafting hatch, never
/// solid ("a graphic never shows an unconfirmed hour").
struct HouseHatchedView: View {
    let keyframe: HouseKeyframe
    /// Already-solid keyframe whose silhouette is cut out of the hatch, so only the new storeys
    /// (not the ground or confirmed parts) read as suggestions.
    var subtracting: HouseKeyframe? = nil
    var canvas: HouseCanvas = .blueprintHero
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tint = canvas.linework(for: colorScheme)
        ZStack {
            Image(decorative: keyframe.builtImageName)
                .resizable()
                .scaledToFit()
                .saturation(0)
                .opacity(0.12)
                .mask(silhouette)
            HouseHatchPattern()
                .stroke(tint, lineWidth: 1.4)
                .mask(silhouette)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var silhouette: some View {
        ZStack {
            Image(decorative: keyframe.builtImageName).resizable().scaledToFit()
            if let subtracting, subtracting != keyframe {
                Image(decorative: subtracting.builtImageName).resizable().scaledToFit()
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
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
struct HouseRisingMask: View, @MainActor Animatable {
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
