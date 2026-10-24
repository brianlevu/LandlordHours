import SwiftUI

// MARK: - Celebration Type (1.x)
//
// The 1.x full-screen confetti is retired (standard §B.3: one milestone beat, on the milestone
// screen only). `CelebrationType` stays because the background queue persists its ids; anything
// still raised through `AppViewModel.triggerCelebration` now shows as the one toast.

enum CelebrationType: Identifiable, Equatable {
    case propertyAdded
    case goalMet
    case greatWork
    case weeklyStreak
    case hoursLogged(milestone: Int)

    var id: String {
        switch self {
        case .propertyAdded: return "propertyAdded"
        case .goalMet: return "goalMet"
        case .greatWork: return "greatWork"
        case .weeklyStreak: return "weeklyStreak"
        case .hoursLogged(let m): return "hoursLogged_\(m)"
        }
    }

    /// The toast's words (§C: one beat, then quiet).
    var title: String {
        switch self {
        case .propertyAdded: return String(localized: "celebration.propertyAdded", defaultValue: "Rental added.", table: "Today")
        case .goalMet: return String(localized: "celebration.goalMet", defaultValue: "Goal hours on the record.", table: "Today")
        case .greatWork: return String(localized: "celebration.saved", defaultValue: "Saved.", table: "Today")
        case .weeklyStreak: return String(localized: "celebration.streak", defaultValue: "Three weeks in a row.", table: "Today")
        case .hoursLogged(let m): return String(localized: "celebration.hours", defaultValue: "\(m) hours.", table: "Today")
        }
    }
}

// MARK: - Milestone Tracker

final class MilestoneTracker {
    static let shared = MilestoneTracker()

    private var key: String { UserScope.key("LandlordHours.celebratedMilestones") }

    private var celebrated: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: key) }
    }

    func shouldCelebrate(_ type: CelebrationType, year: Int) -> Bool {
        !celebrated.contains("\(year)_\(type.id)")
    }

    func markCelebrated(_ type: CelebrationType, year: Int) {
        var set = celebrated
        set.insert("\(year)_\(type.id)")
        celebrated = set
    }

    func reload() {}
}

// MARK: - Celebration Overlay View (1.x entry point)

/// Shows a 1.x celebration as the one toast, then clears itself. Draws nothing.
struct CelebrationOverlayView: View {
    let type: CelebrationType
    let onDismiss: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                LHToastCenter.shared.show(.success, type.title)
                onDismiss()
            }
    }
}

// MARK: - The milestone beat (standard §B.3 `houseStageAdvance`)

/// One confetti burst in the house palette (timber, terracotta, cream): at most 24 pieces, no
/// streamers, stars or glitter, falling once from above the frame, ≤ 0.60 s. Bound to `trigger`;
/// draws nothing under Reduce Motion. Decorative (hidden from VoiceOver).
struct HouseConfettiBeat: View {
    /// Bumped once when the beat should play.
    let trigger: Int
    /// The width the pieces spread across (the hero frame).
    let width: CGFloat
    /// How far they fall (stops above the number block).
    let fall: CGFloat

    static let pieceCount = 24
    static let duration: Double = 0.60

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var progress: CGFloat = 0
    @State private var shown = false

    private struct Piece {
        let x: CGFloat
        let delay: Double
        let size: CGSize
        let spin: Double
        let colour: Int
    }

    /// Deterministic layout (the same burst every time; frames are reproducible).
    private static let pieces: [Piece] = (0..<pieceCount).map { i in
        let t = Double(i) / Double(pieceCount)
        let jitter = (sin(Double(i) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
        return Piece(x: CGFloat(0.08 + 0.84 * ((t + abs(jitter) * 0.37).truncatingRemainder(dividingBy: 1))),
                     delay: abs(jitter) * 0.12,
                     size: i % 3 == 0 ? CGSize(width: 6, height: 6) : CGSize(width: 4, height: 9),
                     spin: 120 + abs(jitter) * 240,
                     colour: i % 3)
    }

    private var palette: [Color] {
        [AppColors.timber, AppColors.terracotta, AdaptiveColors(colorScheme: .light).pageTop]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if shown && !reduceMotion {
                ForEach(0..<Self.pieces.count, id: \.self) { i in
                    let piece = Self.pieces[i]
                    Capsule()
                        .fill(palette[piece.colour])
                        .frame(width: piece.size.width, height: piece.size.height)
                        .rotationEffect(.degrees(piece.spin * Double(progress)))
                        .position(x: piece.x * width, y: -12 + (fall + 12) * progress * CGFloat(1 - piece.delay))
                        .opacity(progress < 0.85 ? 1 : Double((1 - progress) / 0.15))
                }
            }
        }
        .frame(width: width, height: fall, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            progress = 0
            shown = true
            withAnimation(.easeIn(duration: Self.duration)) { progress = 1 }
        }
    }
}
