import SwiftUI

/// A short burst of falling confetti for milestones and finished countdowns. Drawn in a Canvas from
/// a fixed seed, so it needs no assets; it draws nothing once `duration` has passed.
struct ConfettiView: View {
    var accent: Color = .countdownulaBlood
    var duration: TimeInterval = 3.5
    @State private var start = Date()

    private static let palette: [Color] = [
        Color(hex: 0xFF4D6D), Color(hex: 0xFFD166), Color(hex: 0x06D6A0),
        Color(hex: 0x118AB2), Color(hex: 0xC77DFF), .white,
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                guard t < duration else { return }
                let colors = Self.palette + [accent, accent]
                let fade = min(1, (duration - t) / 0.8)
                var rng = SeededRandom(seed: 0xC0FFEE)
                for i in 0..<140 {
                    let x0 = rng.next() * size.width
                    let delay = rng.next() * 0.7
                    let fall = 0.35 + rng.next() * 0.45
                    let sway = 10 + rng.next() * 30
                    let spin = (rng.next() - 0.5) * 900
                    let width = 6 + rng.next() * 6
                    let color = colors[Int(rng.next() * Double(colors.count)) % colors.count]
                    let isRound = rng.next() > 0.7

                    let local = t - delay
                    guard local > 0 else { continue }
                    let y = -20 + local * fall * size.height + 0.5 * local * local * size.height * 0.12
                    guard y < size.height + 20 else { continue }
                    let x = x0 + sin(local * 2.6 + Double(i)) * sway

                    var piece = context
                    piece.opacity = fade
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .degrees(spin * local))
                    // Squash horizontally over time so pieces look like they're tumbling.
                    piece.scaleBy(x: abs(cos(local * 4 + Double(i))) * 0.8 + 0.2, y: 1)
                    let rect = isRound
                        ? CGRect(x: -width / 3, y: -width / 3, width: width * 0.66, height: width * 0.66)
                        : CGRect(x: -width / 2, y: -width * 0.2, width: width, height: width * 0.4)
                    piece.fill(isRound ? Path(ellipseIn: rect) : Path(rect), with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
