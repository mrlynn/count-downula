import SwiftUI

// The Countdownula mark drawn natively (same geometry as design/mark.svg, on a 1000-unit artboard),
// so it can double as a live progress dial in complications.

private let ringRadius: CGFloat = 347.5
private let ringWidth: CGFloat = 85
/// The ring runs clockwise from 1 o'clock (-36°) to just before it (-64°), leaving the gap.
private let ringStartDegrees: Double = -36
private let ringSweepFraction: CGFloat = 332.0 / 360.0

/// The lower jaw: fills the bottom of the ring up to a flat lip.
struct FangJawShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1000
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.midX + (x - 500) * s, y: rect.midY + (y - 500) * s)
        }
        var path = Path()
        path.move(to: p(206, 600))
        path.addQuadCurve(to: p(380, 740), control: p(252, 742))
        path.addLine(to: p(620, 740))
        path.addQuadCurve(to: p(794, 600), control: p(748, 742))
        path.addArc(center: p(500, 500), radius: 312 * s,
                    startAngle: .degrees(18.8), endAngle: .degrees(161.2), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// The two fangs hanging from the lip.
struct FangsShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1000
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.midX + (x - 500) * s, y: rect.midY + (y - 500) * s)
        }
        var path = Path()
        for x in [400.0, 600.0] {
            path.move(to: p(x - 38, 736))
            path.addLine(to: p(x + 38, 736))
            path.addLine(to: p(x + 4, 818))
            path.addQuadCurve(to: p(x - 4, 818), control: p(x, 826))
            path.closeSubpath()
        }
        return path
    }
}

/// The clock hand and hub.
struct FangHandShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1000
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let tip = CGPoint(x: center.x + 158 * s, y: center.y - 147.3 * s)
        var hand = Path()
        hand.move(to: center)
        hand.addLine(to: tip)
        var path = hand.strokedPath(StrokeStyle(lineWidth: 58 * s, lineCap: .round))
        path.addEllipse(in: CGRect(x: center.x - 71 * s, y: center.y - 71 * s, width: 142 * s, height: 142 * s))
        return path
    }
}

/// The ring with fangs. `remaining` (0...1) trims the ring so it doubles as a countdown dial;
/// the unfilled part is drawn as a faint track.
struct FangDial: View {
    var remaining: Double = 1
    var trackOpacity: Double = 0.25
    var showsHand = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let s = side / 1000
            let ringSide = ringRadius * 2 * s
            let stroke = StrokeStyle(lineWidth: ringWidth * s, lineCap: .round)

            ZStack {
                Circle()
                    .trim(from: 0, to: ringSweepFraction)
                    .stroke(style: stroke)
                    .opacity(trackOpacity)
                    .frame(width: ringSide, height: ringSide)
                    .rotationEffect(.degrees(ringStartDegrees))

                Circle()
                    .trim(from: 0, to: ringSweepFraction * min(max(remaining, 0), 1))
                    .stroke(style: stroke)
                    .frame(width: ringSide, height: ringSide)
                    .rotationEffect(.degrees(ringStartDegrees))

                FangJawShape()
                if showsHand { FangHandShape() }
            }
            .frame(width: side, height: side)
            .mask {
                // Punch the fangs out of everything so the background shows through.
                ZStack {
                    Rectangle()
                    FangsShape().blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The full logo: ring, fangs and clock hand.
struct FangMark: View {
    var body: some View {
        FangDial(remaining: 1, trackOpacity: 0, showsHand: true)
    }
}

extension Color {
    static let countdownulaBlood = Color(red: 0.85, green: 0.09, blue: 0.20)
    static let countdownulaBone = Color(red: 0.98, green: 0.95, blue: 0.89)
}
