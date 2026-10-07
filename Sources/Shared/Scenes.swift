import SwiftUI

/// Built-in backgrounds, drawn in code so they cost nothing to ship, stay sharp at any size and
/// look the same in the app, widgets and on the watch. Random details use fixed seeds.
enum SceneID: String, Codable, CaseIterable, Identifiable {
    case midnight, starfield, aurora, sunset, mountains, ocean, snowfall, blossoms, city, confetti, balloons, harvestMoon

    var id: String { rawValue }

    var name: String {
        switch self {
        case .midnight: "Midnight"
        case .starfield: "Stars"
        case .aurora: "Aurora"
        case .sunset: "Sunset"
        case .mountains: "Mountains"
        case .ocean: "Ocean"
        case .snowfall: "Snow"
        case .blossoms: "Blossoms"
        case .city: "City"
        case .confetti: "Confetti"
        case .balloons: "Balloons"
        case .harvestMoon: "Harvest Moon"
        }
    }
}

struct SceneArt: View {
    let scene: SceneID

    var body: some View {
        Canvas { context, size in
            SceneArt.draw(scene, in: &context, size: size)
        }
    }

    // MARK: - Drawing

    private static func draw(_ scene: SceneID, in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        var rng = SeededRandom(seed: UInt64(bitPattern: Int64(scene.rawValue.hashValueStable)))

        switch scene {
        case .midnight:
            sky(&context, rect, [0x4D0A1F, 0x0F0508], angle: 45)
            stars(&context, rect, count: 40, maxRadius: 1.2, alpha: 0.5, rng: &rng)

        case .starfield:
            sky(&context, rect, [0x0B1033, 0x05060F, 0x000000], angle: 90)
            stars(&context, rect, count: 160, maxRadius: 1.4, alpha: 0.9, rng: &rng)
            for _ in 0..<6 {
                let p = CGPoint(x: rng.next() * rect.width, y: rng.next() * rect.height)
                let r = unit(rect) * 0.012
                var glow = context
                glow.addFilter(.blur(radius: r * 3))
                glow.fill(circle(p, r * 2.5), with: .color(.white.opacity(0.5)))
                context.fill(circle(p, r), with: .color(.white))
            }

        case .aurora:
            sky(&context, rect, [0x0A2A3A, 0x07101F, 0x02040A], angle: 90)
            stars(&context, rect, count: 70, maxRadius: 1.1, alpha: 0.7, rng: &rng)
            var bands = context
            bands.addFilter(.blur(radius: unit(rect) * 0.06))
            let colors: [UInt32] = [0x43E97B, 0x38F9D7, 0x9B5DE5]
            for (i, hex) in colors.enumerated() {
                let baseY = rect.height * (0.25 + Double(i) * 0.12)
                var path = Path()
                path.move(to: CGPoint(x: -20, y: baseY))
                let steps = 24
                for s in 0...steps {
                    let x = rect.width * Double(s) / Double(steps)
                    let y = baseY + sin(Double(s) / 3.2 + Double(i)) * rect.height * 0.06
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                for s in stride(from: steps, through: 0, by: -1) {
                    let x = rect.width * Double(s) / Double(steps)
                    let y = baseY + sin(Double(s) / 3.2 + Double(i)) * rect.height * 0.06 + rect.height * 0.18
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                bands.fill(path, with: .linearGradient(
                    Gradient(colors: [Color(hex: hex).opacity(0.75), Color(hex: hex).opacity(0)]),
                    startPoint: CGPoint(x: 0, y: baseY), endPoint: CGPoint(x: 0, y: baseY + rect.height * 0.2)))
            }
            hills(&context, rect, color: Color(hex: 0x03070C), baseline: 0.88, amplitude: 0.05, seed: &rng)

        case .sunset:
            sky(&context, rect, [0x3B1E54, 0xC0436B, 0xFF8C42, 0xFFC56B], angle: 90, upTo: 0.62)
            let horizon = rect.height * 0.62
            let sun = CGPoint(x: rect.midX, y: horizon)
            var glow = context
            glow.addFilter(.blur(radius: unit(rect) * 0.08))
            glow.fill(circle(sun, unit(rect) * 0.3), with: .color(Color(hex: 0xFFD27A).opacity(0.6)))
            context.fill(circle(sun, unit(rect) * 0.17), with: .color(Color(hex: 0xFFE3A3)))
            let sea = CGRect(x: 0, y: horizon, width: rect.width, height: rect.height - horizon)
            context.fill(Path(sea), with: .linearGradient(
                Gradient(colors: [Color(hex: 0x7A3B6E), Color(hex: 0x23153A)]),
                startPoint: CGPoint(x: 0, y: sea.minY), endPoint: CGPoint(x: 0, y: sea.maxY)))
            for i in 0..<9 {
                let y = horizon + sea.height * (Double(i) + 0.6) / 10
                let w = unit(rect) * (0.32 - Double(i) * 0.025)
                context.fill(Path(roundedRect: CGRect(x: rect.midX - w / 2, y: y, width: w, height: max(1.5, sea.height * 0.025)),
                                  cornerRadius: 2),
                             with: .color(Color(hex: 0xFFD27A).opacity(0.55 - Double(i) * 0.05)))
            }

        case .mountains:
            sky(&context, rect, [0xFBD3A3, 0xF29E8E, 0x8C6BA8], angle: 90)
            context.fill(circle(CGPoint(x: rect.width * 0.72, y: rect.height * 0.3), unit(rect) * 0.09),
                         with: .color(Color(hex: 0xFFF1D6).opacity(0.9)))
            hills(&context, rect, color: Color(hex: 0x8A6AA0), baseline: 0.55, amplitude: 0.2, peaks: 4, seed: &rng)
            hills(&context, rect, color: Color(hex: 0x5D4A84), baseline: 0.68, amplitude: 0.17, peaks: 5, seed: &rng)
            hills(&context, rect, color: Color(hex: 0x332B52), baseline: 0.82, amplitude: 0.12, peaks: 6, seed: &rng)

        case .ocean:
            sky(&context, rect, [0x8ED1F2, 0xD9F1FA], angle: 90, upTo: 0.45)
            context.fill(circle(CGPoint(x: rect.width * 0.22, y: rect.height * 0.2), unit(rect) * 0.08),
                         with: .color(Color(hex: 0xFFF6D5)))
            let layers: [(UInt32, Double)] = [(0x3FA7D6, 0.45), (0x2A7FB8, 0.58), (0x1C5A8E, 0.72), (0x103B66, 0.86)]
            for (i, layer) in layers.enumerated() {
                var path = Path()
                let base = rect.height * layer.1
                path.move(to: CGPoint(x: 0, y: rect.height))
                let steps = 40
                for s in 0...steps {
                    let x = rect.width * Double(s) / Double(steps)
                    let y = base + sin(Double(s) / 2.5 + Double(i) * 1.7) * rect.height * 0.018
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: rect.width, y: rect.height))
                path.closeSubpath()
                context.fill(path, with: .color(Color(hex: layer.0)))
            }

        case .snowfall:
            sky(&context, rect, [0x1B2A4A, 0x3E5A82, 0x9DB4CF], angle: 90)
            hills(&context, rect, color: Color(hex: 0xE8F0F8), baseline: 0.84, amplitude: 0.06, peaks: 3, seed: &rng)
            for _ in 0..<110 {
                let p = CGPoint(x: rng.next() * rect.width, y: rng.next() * rect.height)
                let r = unit(rect) * (0.003 + rng.next() * 0.009)
                context.fill(circle(p, r), with: .color(.white.opacity(0.5 + rng.next() * 0.5)))
            }

        case .blossoms:
            sky(&context, rect, [0xFFE4EC, 0xF9B8CC, 0xE58BB0], angle: 120)
            for _ in 0..<38 {
                let p = CGPoint(x: rng.next() * rect.width, y: rng.next() * rect.height)
                let r = unit(rect) * (0.018 + rng.next() * 0.03)
                var petal = context
                petal.translateBy(x: p.x, y: p.y)
                petal.rotate(by: .degrees(rng.next() * 360))
                let color = [Color(hex: 0xFFFFFF), Color(hex: 0xFFD1DF), Color(hex: 0xF27BA5)][Int(rng.next() * 3) % 3]
                petal.fill(Path(ellipseIn: CGRect(x: -r, y: -r * 0.55, width: r * 2, height: r * 1.1)),
                           with: .color(color.opacity(0.55 + rng.next() * 0.4)))
            }

        case .city:
            sky(&context, rect, [0x1A1036, 0x5A2A6E, 0xE0607E], angle: 90)
            stars(&context, rect, count: 30, maxRadius: 1, alpha: 0.6, rng: &rng, maxY: 0.4)
            var x = -rect.width * 0.02
            while x < rect.width {
                let w = rect.width * (0.06 + rng.next() * 0.08)
                let h = rect.height * (0.18 + rng.next() * 0.35)
                let building = CGRect(x: x, y: rect.height - h, width: w, height: h)
                context.fill(Path(building), with: .color(Color(hex: 0x120A22)))
                let win = max(1.5, w * 0.12)
                var wy = building.minY + win * 1.5
                while wy < building.maxY - win {
                    var wx = building.minX + win
                    while wx < building.maxX - win {
                        if rng.next() > 0.55 {
                            context.fill(Path(CGRect(x: wx, y: wy, width: win, height: win)),
                                         with: .color(Color(hex: 0xFFD98A).opacity(0.85)))
                        }
                        wx += win * 2
                    }
                    wy += win * 2.2
                }
                x += w + rect.width * 0.008
            }

        case .confetti:
            sky(&context, rect, [0x2B0F3A, 0x140A24], angle: 120)
            let palette: [UInt32] = [0xFF4D6D, 0xFFD166, 0x06D6A0, 0x118AB2, 0xC77DFF, 0xFFFFFF]
            for _ in 0..<70 {
                let p = CGPoint(x: rng.next() * rect.width, y: rng.next() * rect.height)
                let w = unit(rect) * (0.03 + rng.next() * 0.03)
                var piece = context
                piece.translateBy(x: p.x, y: p.y)
                piece.rotate(by: .degrees(rng.next() * 360))
                let color = Color(hex: palette[Int(rng.next() * Double(palette.count)) % palette.count])
                let shape = rng.next() > 0.3
                    ? Path(CGRect(x: -w / 2, y: -w * 0.2, width: w, height: w * 0.4))
                    : Path(ellipseIn: CGRect(x: -w / 3, y: -w / 3, width: w * 0.66, height: w * 0.66))
                piece.fill(shape, with: .color(color.opacity(0.9)))
            }

        case .balloons:
            sky(&context, rect, [0x9ED8F5, 0xE6F6FD], angle: 90)
            let palette: [UInt32] = [0xFF5D73, 0xFFC145, 0x5BC0EB, 0x9BC53D, 0xB57EDC]
            for i in 0..<9 {
                let cx = rect.width * (0.08 + Double(i) * 0.105 + (rng.next() - 0.5) * 0.06)
                let cy = rect.height * (0.25 + rng.next() * 0.45)
                let r = unit(rect) * (0.07 + rng.next() * 0.04)
                let color = Color(hex: palette[i % palette.count])
                var string = Path()
                string.move(to: CGPoint(x: cx, y: cy + r * 1.2))
                string.addQuadCurve(to: CGPoint(x: cx + r * 0.3, y: rect.height + 4),
                                    control: CGPoint(x: cx - r * 0.6, y: cy + r * 3))
                context.stroke(string, with: .color(Color(hex: 0x5A6B7A).opacity(0.5)), lineWidth: 1)
                context.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r * 1.2, width: r * 2, height: r * 2.4)),
                             with: .color(color))
                context.fill(Path(ellipseIn: CGRect(x: cx - r * 0.55, y: cy - r * 0.9, width: r * 0.5, height: r * 0.7)),
                             with: .color(.white.opacity(0.35)))
            }

        case .harvestMoon:
            sky(&context, rect, [0x1A0B12, 0x5A1A12, 0xC4501B], angle: 90)
            let moon = CGPoint(x: rect.width * 0.62, y: rect.height * 0.4)
            var glow = context
            glow.addFilter(.blur(radius: unit(rect) * 0.06))
            glow.fill(circle(moon, unit(rect) * 0.3), with: .color(Color(hex: 0xFFB347).opacity(0.5)))
            context.fill(circle(moon, unit(rect) * 0.22), with: .color(Color(hex: 0xFFC46B)))
            for (dx, dy, r) in [(-0.07, 0.02, 0.035), (0.05, 0.08, 0.03), (0.08, -0.06, 0.022)] {
                context.fill(circle(CGPoint(x: moon.x + unit(rect) * dx, y: moon.y + unit(rect) * dy), unit(rect) * r),
                             with: .color(Color(hex: 0xE89A45).opacity(0.6)))
            }
            for i in 0..<4 {
                // Keep the bats clear of the moon so they read as bats, not a face.
                let p = CGPoint(x: rect.width * (0.08 + Double(i) * 0.1 + rng.next() * 0.04),
                                y: rect.height * (0.1 + rng.next() * 0.18))
                context.fill(bat(at: p, span: unit(rect) * (0.09 + rng.next() * 0.05)), with: .color(Color(hex: 0x1A0B12)))
            }
            hills(&context, rect, color: Color(hex: 0x14070C), baseline: 0.82, amplitude: 0.08, peaks: 3, seed: &rng)
        }
    }

    // MARK: - Pieces

    private static func unit(_ rect: CGRect) -> Double { min(rect.width, rect.height) }

    private static func circle(_ center: CGPoint, _ radius: Double) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    /// Fills `rect` (or its top part) with a gradient; 90° runs top to bottom.
    private static func sky(_ context: inout GraphicsContext, _ rect: CGRect, _ hexes: [UInt32], angle: Double,
                            upTo fraction: Double = 1) {
        let radians = angle * .pi / 180
        let area = CGRect(x: 0, y: 0, width: rect.width, height: rect.height * fraction)
        let dx = cos(radians) * area.width / 2
        let dy = sin(radians) * area.height / 2
        context.fill(Path(rect), with: .linearGradient(
            Gradient(colors: hexes.map { Color(hex: $0) }),
            startPoint: CGPoint(x: area.midX - dx, y: area.midY - dy),
            endPoint: CGPoint(x: area.midX + dx, y: area.midY + dy)))
    }

    private static func stars(_ context: inout GraphicsContext, _ rect: CGRect, count: Int, maxRadius: Double,
                              alpha: Double, rng: inout SeededRandom, maxY: Double = 1) {
        // Scale with the canvas so a widget-sized scene isn't a smear of dots.
        let scale = max(1, unit(rect) / 200)
        for _ in 0..<count {
            let p = CGPoint(x: rng.next() * rect.width, y: rng.next() * rect.height * maxY)
            let r = (0.3 + rng.next() * maxRadius) * scale
            context.fill(circle(p, r), with: .color(.white.opacity(alpha * (0.3 + rng.next() * 0.7))))
        }
    }

    private static func hills(_ context: inout GraphicsContext, _ rect: CGRect, color: Color, baseline: Double,
                              amplitude: Double, peaks: Int = 3, seed rng: inout SeededRandom) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height * baseline))
        let segment = rect.width / Double(peaks)
        for i in 0..<peaks {
            let x0 = Double(i) * segment
            let peak = CGPoint(x: x0 + segment * (0.3 + rng.next() * 0.4),
                               y: rect.height * (baseline - amplitude * (0.5 + rng.next() * 0.5)))
            let end = CGPoint(x: x0 + segment, y: rect.height * (baseline - amplitude * rng.next() * 0.25))
            path.addLine(to: peak)
            path.addLine(to: end)
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }

    private static func bat(at p: CGPoint, span: Double) -> Path {
        var path = Path()
        let h = span * 0.35
        path.move(to: CGPoint(x: p.x - span / 2, y: p.y))
        path.addQuadCurve(to: CGPoint(x: p.x - span * 0.15, y: p.y + h * 0.2), control: CGPoint(x: p.x - span * 0.35, y: p.y - h))
        path.addLine(to: CGPoint(x: p.x, y: p.y - h * 0.4))
        path.addLine(to: CGPoint(x: p.x + span * 0.15, y: p.y + h * 0.2))
        path.addQuadCurve(to: CGPoint(x: p.x + span / 2, y: p.y), control: CGPoint(x: p.x + span * 0.35, y: p.y - h))
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + h * 0.6), control: CGPoint(x: p.x + span * 0.2, y: p.y + h))
        path.addQuadCurve(to: CGPoint(x: p.x - span / 2, y: p.y), control: CGPoint(x: p.x - span * 0.2, y: p.y + h))
        path.closeSubpath()
        return path
    }
}

// MARK: - Helpers

/// SplitMix64: tiny, fast and deterministic, so scenes render identically everywhere.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// A value in 0..<1.
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

private extension String {
    /// `hashValue` is randomized per launch; this isn't.
    var hashValueStable: Int {
        unicodeScalars.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1.value) }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self = RGBAColor(hex: hex, opacity: opacity).color
    }
}
