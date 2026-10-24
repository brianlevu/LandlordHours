import SwiftUI
import UIKit

#if DEBUG
// MARK: - Hero ambient layer (Brian, 2026-10-23: "I don't want this to feel too empty")
//
// Drafted linework in the house's own ink (drafting cyan, 1pt), low opacity, in a fixed
// 190 x 64pt box at the card's top-right corner, behind the house and clear of the number.
// Clouds drift right → left, one loop every 46–58s, staggered. A flock of three chevrons glides
// across every 20–40s with a slow wing beat and fades in and out. Everything fades to zero
// before the box's left edge, so nothing reaches the number.
//
// Core Animation, not a per-frame SwiftUI redraw: the motion runs in the render server, so the
// app process stays near idle (a 30fps TimelineView + Canvas measured 7.5% CPU in the sim).
//
// Pauses (layer speed 0): off screen, app not active, Low Power Mode. Reduce Motion: static
// clouds, no birds. Birds are off unless `-LHStdAmbientBirds`; `-LHStdAmbientDemo` then flies them at 3s and 14s.

struct StdHeroAmbient: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var onScreen = true
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private static let off = ProcessInfo.processInfo.arguments.contains("-LHStdAmbientOff")

    var body: some View {
        Group {
            if Self.off {
                Color.clear
            } else {
                StdAmbientSky(paused: !onScreen || scenePhase != .active || lowPower, still: reduceMotion)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onGeometryChange(for: Bool.self) { proxy in
            let f = proxy.frame(in: .global)
            return f.maxY > 0 && f.minY < UIScreen.main.bounds.height
        } action: { onScreen = $0 }
        .onDisappear { onScreen = false }
        .onAppear { onScreen = true }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}

private struct StdAmbientSky: UIViewRepresentable {
    let paused: Bool
    let still: Bool

    func makeUIView(context: Context) -> StdAmbientSkyView { StdAmbientSkyView() }

    func updateUIView(_ view: StdAmbientSkyView, context: Context) {
        view.configure(still: still)
        view.setPaused(paused)
    }
}

final class StdAmbientSkyView: UIView {
    private let sky = CALayer()
    private let fade = CAGradientLayer()
    private var cloudLayers: [CAShapeLayer] = []
    private var flock: CALayer?
    private var still: Bool?
    private var paused = false
    private var flightTimer: Timer?
    private var flights = 0
    private static let demo = ProcessInfo.processInfo.arguments.contains("-LHStdAmbientDemo")
    private static let birds = ProcessInfo.processInfo.arguments.contains("-LHStdAmbientBirds")
    private static let ink = UIColor(HouseTokens.drafting).cgColor

    private struct Cloud { let period: CFTimeInterval; let phase: Double; let y: CGFloat; let w: CGFloat; let alpha: Float }
    private static let clouds: [Cloud] = [
        Cloud(period: 52, phase: 0.15, y: 18, w: 46, alpha: 0.32),
        Cloud(period: 58, phase: 0.62, y: 40, w: 34, alpha: 0.26),
        Cloud(period: 46, phase: 0.88, y: 10, w: 28, alpha: 0.22),
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.addSublayer(sky)
        // Edge fade: zero at the number side (left) and at the card edge (right).
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [UIColor.clear.cgColor, UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        fade.locations = [0, 0.10, 0.34, 0.86, 1]
        sky.mask = fade
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { flightTimer?.invalidate() }

    override func layoutSubviews() {
        super.layoutSubviews()
        sky.frame = bounds
        fade.frame = bounds
        if let still { build(still: still) }
    }

    func configure(still: Bool) {
        guard self.still != still else { return }
        self.still = still
        build(still: still)
    }

    // MARK: Build

    private func build(still: Bool) {
        guard bounds.width > 0 else { return }
        cloudLayers.forEach { $0.removeFromSuperlayer() }
        cloudLayers = []
        flock?.removeFromSuperlayer()
        flock = nil
        flightTimer?.invalidate()
        let w = bounds.width
        for (i, c) in Self.clouds.enumerated() {
            let l = CAShapeLayer()
            l.path = Self.cloudPath(width: c.w)
            l.bounds = CGRect(x: 0, y: 0, width: c.w, height: c.w * 0.4)
            l.strokeColor = Self.ink
            l.fillColor = nil
            l.lineWidth = 1
            l.lineCap = .round
            l.lineJoin = .round
            l.opacity = c.alpha
            let startX = w + 45, endX: CGFloat = -45
            if still {
                // Reduce Motion: three clouds resting in the sky.
                l.position = CGPoint(x: w * [0.78, 0.52, 0.95][i], y: c.y)
            } else {
                l.position = CGPoint(x: startX, y: c.y)
                let a = CABasicAnimation(keyPath: "position.x")
                a.fromValue = startX
                a.toValue = endX
                a.duration = c.period
                a.repeatCount = .infinity
                a.timeOffset = c.period * c.phase
                a.timingFunction = CAMediaTimingFunction(name: .linear)
                l.add(a, forKey: "drift")
            }
            sky.addSublayer(l)
            cloudLayers.append(l)
        }
        // Birds are parked (2026-10-23: a concept decision is pending); the clouds are the base layer.
        guard !still, Self.birds else { return }
        scheduleFlight(after: Self.demo ? 3 : Double.random(in: 8...20))
    }

    private func scheduleFlight(after delay: TimeInterval) {
        flightTimer?.invalidate()
        flightTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            if !self.paused { self.fly() }
            self.flights += 1
            let next = Self.demo ? (self.flights == 1 ? 11 : 30) : Double.random(in: 20...40)
            self.scheduleFlight(after: next)
        }
    }

    // MARK: The flock

    private func fly() {
        flock?.removeFromSuperlayer()
        let w = bounds.width
        let group = CALayer()
        group.frame = bounds
        let offsets: [CGPoint] = [.zero, CGPoint(x: 9, y: 5), CGPoint(x: 15, y: -3)]
        let duration: CFTimeInterval = 9
        for (i, o) in offsets.enumerated() {
            let b = CAShapeLayer()
            b.bounds = CGRect(x: -7, y: -4, width: 14, height: 8)
            b.path = Self.birdPath(lift: 2.7)
            b.strokeColor = Self.ink
            b.fillColor = nil
            b.lineWidth = 1
            b.lineCap = .round
            b.opacity = 0
            // Glide: a shallow arc right → left.
            let path = UIBezierPath()
            path.move(to: CGPoint(x: w + 10 + o.x, y: 22 + o.y))
            path.addQuadCurve(to: CGPoint(x: 10 + o.x, y: 20 + o.y), controlPoint: CGPoint(x: w * 0.5 + o.x, y: 6 + o.y))
            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path.cgPath
            move.duration = duration
            move.calculationMode = .paced
            let alpha = CAKeyframeAnimation(keyPath: "opacity")
            alpha.values = [0, 0.55, 0.55, 0]
            alpha.keyTimes = [0, 0.18, 0.82, 1]
            alpha.duration = duration
            // Wing beat: the chevron's lift changes, slowly (about 0.7s a beat).
            let flap = CABasicAnimation(keyPath: "path")
            flap.fromValue = Self.birdPath(lift: 0.6)
            flap.toValue = Self.birdPath(lift: 2.8)
            flap.duration = 0.35
            flap.autoreverses = true
            flap.repeatCount = .infinity
            flap.timeOffset = Double(i) * 0.23
            flap.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            b.add(move, forKey: "glide")
            b.add(alpha, forKey: "fade")
            b.add(flap, forKey: "flap")
            b.position = CGPoint(x: 10 + o.x, y: 20 + o.y)
            group.addSublayer(b)
        }
        sky.addSublayer(group)
        flock = group
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.2) { [weak self, weak group] in
            guard let group, self?.flock === group else { return }
            group.removeFromSuperlayer()
            self?.flock = nil
        }
    }

    // MARK: Pause (layer speed 0 keeps the frame where it is)

    func setPaused(_ p: Bool) {
        guard p != paused else { return }
        paused = p
        if p {
            let t = sky.convertTime(CACurrentMediaTime(), from: nil)
            sky.speed = 0
            sky.timeOffset = t
        } else {
            let pausedAt = sky.timeOffset
            sky.speed = 1
            sky.timeOffset = 0
            sky.beginTime = 0
            sky.beginTime = sky.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        }
    }

    // MARK: Paths

    /// A drafted cloud: three arcs over a flat base.
    private static func cloudPath(width w: CGFloat) -> CGPath {
        let h = w * 0.34, base = w * 0.38
        let p = UIBezierPath()
        p.move(to: CGPoint(x: w * 0.06, y: base))
        p.addLine(to: CGPoint(x: w * 0.94, y: base))
        p.addArc(withCenter: CGPoint(x: w * 0.80, y: base - h * 0.30), radius: h * 0.42,
                 startAngle: .pi / 3, endAngle: -.pi * 5 / 6, clockwise: false)
        p.addArc(withCenter: CGPoint(x: w * 0.50, y: base - h * 0.52), radius: h * 0.58,
                 startAngle: -.pi / 18, endAngle: -.pi, clockwise: false)
        p.addArc(withCenter: CGPoint(x: w * 0.20, y: base - h * 0.28), radius: h * 0.38,
                 startAngle: -.pi / 4.5, endAngle: -.pi * 4 / 3, clockwise: false)
        return p.cgPath
    }

    /// A line-drawn bird: two slightly curved wings meeting at the body. Same point count for every
    /// lift, so the path animation interpolates.
    private static func birdPath(lift: CGFloat) -> CGPath {
        let span: CGFloat = 5.5
        let p = UIBezierPath()
        p.move(to: CGPoint(x: -span, y: -lift))
        p.addQuadCurve(to: .zero, controlPoint: CGPoint(x: -span * 0.45, y: -lift * 0.2))
        p.addQuadCurve(to: CGPoint(x: span, y: -lift), controlPoint: CGPoint(x: span * 0.45, y: -lift * 0.2))
        return p.cgPath
    }
}
#endif
