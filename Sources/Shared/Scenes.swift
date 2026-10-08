import SwiftUI

/// Built-in backgrounds, drawn in code so they cost nothing to ship, stay sharp at any size and
/// look the same in the app, widgets and on the watch. Random details use fixed seeds.
enum SceneID: String, Codable, CaseIterable, Identifiable {
    case midnight, starfield, aurora, sunset, mountains, ocean, snowfall, blossoms, city, confetti, balloons, harvestMoon
    // Occasions, added October 2026. Builds before then keep these styles but show the default backdrop.
    case wedding, airplane, beach, birthday, graduation, baby, hearts, fireworks, stadium, campfire

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
        case .wedding: "Wedding"
        case .airplane: "Airplane"
        case .beach: "Beach"
        case .birthday: "Birthday"
        case .graduation: "Graduation"
        case .baby: "Baby"
        case .hearts: "Hearts"
        case .fireworks: "Fireworks"
        case .stadium: "Game Day"
        case .campfire: "Campfire"
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

        case .wedding:
            sky(&context, rect, [0xFFF6EE, 0xF8DDE0, 0xE9B7C2], angle: 100)
            for _ in 0..<26 {
                let p = CGPoint(x: rng.next() * rect.width, y: rng.next() * rect.height)
                let r = unit(rect) * (0.012 + rng.next() * 0.02)
                var petal = context
                petal.translateBy(x: p.x, y: p.y)
                petal.rotate(by: .degrees(rng.next() * 360))
                petal.fill(Path(ellipseIn: CGRect(x: -r, y: -r * 0.55, width: r * 2, height: r * 1.1)),
                           with: .color(Color(hex: rng.next() > 0.5 ? 0xFFFFFF : 0xF4A7B9).opacity(0.6)))
            }
            let u = unit(rect)
            let center = CGPoint(x: rect.midX, y: rect.height * 0.42)
            var glow = context
            glow.addFilter(.blur(radius: u * 0.06))
            glow.fill(circle(center, u * 0.26), with: .color(.white.opacity(0.7)))
            let gold = Color(hex: 0xD4A645)
            for dx in [-0.075, 0.075] {
                let ring = circle(CGPoint(x: center.x + u * dx, y: center.y), u * 0.12)
                context.stroke(ring, with: .color(Color(hex: 0x9C7425).opacity(0.5)), lineWidth: u * 0.03)
                context.stroke(ring, with: .color(gold), lineWidth: u * 0.022)
            }
            // A stone on the right ring.
            let top = CGPoint(x: center.x + u * 0.075, y: center.y - u * 0.135)
            var stone = Path()
            stone.move(to: CGPoint(x: top.x, y: top.y + u * 0.02))
            stone.addLine(to: CGPoint(x: top.x - u * 0.035, y: top.y - u * 0.015))
            stone.addLine(to: CGPoint(x: top.x - u * 0.018, y: top.y - u * 0.04))
            stone.addLine(to: CGPoint(x: top.x + u * 0.018, y: top.y - u * 0.04))
            stone.addLine(to: CGPoint(x: top.x + u * 0.035, y: top.y - u * 0.015))
            stone.closeSubpath()
            context.fill(stone, with: .linearGradient(Gradient(colors: [.white, Color(hex: 0xBFE3F2)]),
                                                      startPoint: CGPoint(x: top.x, y: top.y - u * 0.04),
                                                      endPoint: CGPoint(x: top.x, y: top.y + u * 0.02)))

        case .airplane:
            sky(&context, rect, [0x2F80D1, 0x6FB5EC, 0xCDE9FA], angle: 90)
            for _ in 0..<5 {
                cloud(&context, at: CGPoint(x: rng.next() * rect.width, y: rect.height * (0.45 + rng.next() * 0.5)),
                      size: unit(rect) * (0.18 + rng.next() * 0.14), opacity: 0.85)
            }
            let u = unit(rect)
            let plane = CGPoint(x: rect.width * 0.66, y: rect.height * 0.3)
            let heading = -18.0
            // The contrail runs back from the tail.
            let back = CGPoint(x: plane.x - cos(heading * .pi / 180) * u * 0.16, y: plane.y - sin(heading * .pi / 180) * u * 0.16)
            for offset in [-0.012, 0.012] {
                var trail = Path()
                trail.move(to: CGPoint(x: back.x, y: back.y + u * offset))
                trail.addLine(to: CGPoint(x: -rect.width * 0.1, y: back.y + (back.x + rect.width * 0.1) * tan(18 * .pi / 180) + u * offset * 3))
                context.stroke(trail, with: .linearGradient(Gradient(colors: [.white.opacity(0.9), .white.opacity(0)]),
                                                            startPoint: back, endPoint: CGPoint(x: 0, y: rect.height * 0.55)),
                               style: StrokeStyle(lineWidth: u * 0.012, lineCap: .round))
            }
            var craft = context
            craft.translateBy(x: plane.x, y: plane.y)
            craft.rotate(by: .degrees(heading))
            craft.fill(airplane(span: u * 0.34), with: .color(.white))

        case .beach:
            sky(&context, rect, [0x56C1E8, 0xB9E8F7], angle: 90, upTo: 0.55)
            let u = unit(rect)
            context.fill(circle(CGPoint(x: rect.width * 0.78, y: rect.height * 0.16), u * 0.08), with: .color(Color(hex: 0xFFF3B0)))
            for _ in 0..<2 {
                cloud(&context, at: CGPoint(x: rng.next() * rect.width * 0.6, y: rect.height * (0.12 + rng.next() * 0.15)),
                      size: u * 0.16, opacity: 0.9)
            }
            let sea = CGRect(x: 0, y: rect.height * 0.55, width: rect.width, height: rect.height * 0.15)
            context.fill(Path(sea), with: .linearGradient(Gradient(colors: [Color(hex: 0x1C8FC4), Color(hex: 0x3CC8D8)]),
                                                         startPoint: CGPoint(x: 0, y: sea.minY), endPoint: CGPoint(x: 0, y: sea.maxY)))
            var sand = Path()
            sand.move(to: CGPoint(x: 0, y: rect.height * 0.7))
            sand.addQuadCurve(to: CGPoint(x: rect.width, y: rect.height * 0.66), control: CGPoint(x: rect.width * 0.5, y: rect.height * 0.64))
            sand.addLine(to: CGPoint(x: rect.width, y: rect.height))
            sand.addLine(to: CGPoint(x: 0, y: rect.height))
            sand.closeSubpath()
            context.fill(sand, with: .linearGradient(Gradient(colors: [Color(hex: 0xF7E1B0), Color(hex: 0xE8C27F)]),
                                                    startPoint: CGPoint(x: 0, y: rect.height * 0.65), endPoint: CGPoint(x: 0, y: rect.height)))
            // Surf line.
            var foam = Path()
            foam.move(to: CGPoint(x: 0, y: rect.height * 0.7))
            foam.addQuadCurve(to: CGPoint(x: rect.width, y: rect.height * 0.66), control: CGPoint(x: rect.width * 0.5, y: rect.height * 0.64))
            context.stroke(foam, with: .color(.white.opacity(0.8)), lineWidth: u * 0.012)
            palm(&context, base: CGPoint(x: rect.width * 0.18, y: rect.height * 0.9), height: rect.height * 0.62, unit: u)

        case .birthday:
            sky(&context, rect, [0xFFD6E0, 0xFFB4C6, 0xC98BD9], angle: 110)
            let palette: [UInt32] = [0xFF4D6D, 0xFFD166, 0x06D6A0, 0x118AB2, 0xFFFFFF]
            for _ in 0..<50 {
                let p = CGPoint(x: rng.next() * rect.width, y: rng.next() * rect.height)
                let w = unit(rect) * (0.012 + rng.next() * 0.012)
                var piece = context
                piece.translateBy(x: p.x, y: p.y)
                piece.rotate(by: .degrees(rng.next() * 360))
                piece.fill(Path(roundedRect: CGRect(x: -w, y: -w * 0.3, width: w * 2, height: w * 0.6), cornerRadius: w * 0.3),
                           with: .color(Color(hex: palette[Int(rng.next() * 5) % 5]).opacity(0.85)))
            }
            cake(&context, center: CGPoint(x: rect.midX, y: rect.height * 0.62), unit: unit(rect))

        case .graduation:
            sky(&context, rect, [0x0E1A3D, 0x1F3A75, 0x3E64A8], angle: 90)
            for _ in 0..<60 {
                let p = CGPoint(x: rng.next() * rect.width, y: rng.next() * rect.height)
                let r = unit(rect) * (0.004 + rng.next() * 0.006)
                context.fill(circle(p, r), with: .color(Color(hex: 0xF2C94C).opacity(0.4 + rng.next() * 0.5)))
            }
            let spots: [(Double, Double, Double, Double)] = [(0.5, 0.42, 0.3, -8), (0.22, 0.22, 0.18, 18), (0.8, 0.2, 0.16, -24), (0.2, 0.72, 0.14, 30), (0.82, 0.7, 0.15, -14)]
            for spot in spots {
                var cap = context
                cap.translateBy(x: rect.width * spot.0, y: rect.height * spot.1)
                cap.rotate(by: .degrees(spot.3))
                mortarboard(&cap, size: unit(rect) * spot.2)
            }

        case .baby:
            sky(&context, rect, [0xD7EEF7, 0xF4E3F0, 0xFDE8DA], angle: 90)
            let u = unit(rect)
            for _ in 0..<4 {
                cloud(&context, at: CGPoint(x: rng.next() * rect.width, y: rect.height * (0.55 + rng.next() * 0.4)),
                      size: u * (0.2 + rng.next() * 0.1), opacity: 0.95)
            }
            for _ in 0..<14 {
                let p = CGPoint(x: rng.next() * rect.width, y: rng.next() * rect.height * 0.6)
                context.fill(star(at: p, radius: u * (0.015 + rng.next() * 0.02)),
                             with: .color(Color(hex: [0xFFD98A, 0xF7A8C4, 0x9BD3EA][Int(rng.next() * 3) % 3])))
            }
            let moonCenter = CGPoint(x: rect.width * 0.7, y: rect.height * 0.28)
            let moon = circle(moonCenter, u * 0.12)
                .subtracting(circle(CGPoint(x: moonCenter.x + u * 0.06, y: moonCenter.y - u * 0.03), u * 0.1))
            var glow = context
            glow.addFilter(.blur(radius: u * 0.04))
            glow.fill(moon, with: .color(Color(hex: 0xFFE7A0).opacity(0.8)))
            context.fill(moon, with: .color(Color(hex: 0xFFE7A0)))

        case .hearts:
            sky(&context, rect, [0xFF6F91, 0xD63A6A, 0x7A1238], angle: 110)
            for _ in 0..<26 {
                let p = CGPoint(x: rng.next() * rect.width, y: rng.next() * rect.height)
                let size = unit(rect) * (0.04 + rng.next() * 0.1)
                var h = context
                h.translateBy(x: p.x, y: p.y)
                h.rotate(by: .degrees((rng.next() - 0.5) * 40))
                h.fill(heart(size: size), with: .color(Color(hex: [0xFFFFFF, 0xFFC2D1, 0xFF8FAB][Int(rng.next() * 3) % 3])
                                                        .opacity(0.35 + rng.next() * 0.5)))
            }
            var big = context
            big.translateBy(x: rect.midX, y: rect.height * 0.42)
            var glow = big
            glow.addFilter(.blur(radius: unit(rect) * 0.05))
            glow.fill(heart(size: unit(rect) * 0.5), with: .color(.white.opacity(0.35)))
            big.fill(heart(size: unit(rect) * 0.4), with: .color(Color(hex: 0xFFF0F4)))

        case .fireworks:
            sky(&context, rect, [0x05061A, 0x111A44, 0x2A1F5C], angle: 90)
            stars(&context, rect, count: 50, maxRadius: 1, alpha: 0.6, rng: &rng)
            let palette: [UInt32] = [0xFF4D6D, 0xFFD166, 0x06D6A0, 0x4CC9F0, 0xC77DFF, 0xFFFFFF]
            let bursts: [(Double, Double, Double)] = [(0.3, 0.28, 0.24), (0.72, 0.22, 0.2), (0.55, 0.52, 0.17), (0.18, 0.6, 0.12), (0.85, 0.55, 0.13)]
            for (i, b) in bursts.enumerated() {
                burst(&context, center: CGPoint(x: rect.width * b.0, y: rect.height * b.1), radius: unit(rect) * b.2,
                      color: Color(hex: palette[i % palette.count]), rng: &rng)
            }
            hills(&context, rect, color: Color(hex: 0x03040D), baseline: 0.92, amplitude: 0.04, peaks: 5, seed: &rng)

        case .stadium:
            stadium(&context, rect, rng: &rng)

        case .campfire:
            sky(&context, rect, [0x0B1026, 0x1E1B4B, 0x4A2C5E], angle: 90)
            stars(&context, rect, count: 90, maxRadius: 1.2, alpha: 0.8, rng: &rng, maxY: 0.6)
            let u = unit(rect)
            var x = -rect.width * 0.05
            while x < rect.width * 1.05 {
                let h = rect.height * (0.22 + rng.next() * 0.2)
                pine(&context, base: CGPoint(x: x, y: rect.height * 0.8), height: h, color: Color(hex: 0x0A0F1E))
                x += rect.width * (0.07 + rng.next() * 0.07)
            }
            var ground = Path()
            ground.move(to: CGPoint(x: 0, y: rect.height * 0.76))
            ground.addQuadCurve(to: CGPoint(x: rect.width, y: rect.height * 0.75), control: CGPoint(x: rect.midX, y: rect.height * 0.72))
            ground.addLine(to: CGPoint(x: rect.width, y: rect.height))
            ground.addLine(to: CGPoint(x: 0, y: rect.height))
            ground.closeSubpath()
            context.fill(ground, with: .color(Color(hex: 0x120D1C)))
            fire(&context, base: CGPoint(x: rect.midX, y: rect.height * 0.86), unit: u)
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

    private static func cloud(_ context: inout GraphicsContext, at p: CGPoint, size: Double, opacity: Double) {
        var puff = Path()
        for (dx, dy, r) in [(-0.3, 0.05, 0.22), (-0.05, -0.1, 0.3), (0.25, 0.0, 0.24), (0.0, 0.1, 0.25)] {
            puff.addPath(circle(CGPoint(x: p.x + size * dx, y: p.y + size * dy), size * r))
        }
        context.fill(puff, with: .color(.white.opacity(opacity)))
    }

    /// Nose at +x, `span` wingtip to wingtip.
    private static func airplane(span s: Double) -> Path {
        var path = Path(roundedRect: CGRect(x: -s * 0.5, y: -s * 0.045, width: s, height: s * 0.09), cornerRadius: s * 0.045)
        for sign in [-1.0, 1.0] {
            var wing = Path()
            wing.move(to: CGPoint(x: s * 0.12, y: 0))
            wing.addLine(to: CGPoint(x: -s * 0.16, y: sign * s * 0.5))
            wing.addLine(to: CGPoint(x: -s * 0.26, y: sign * s * 0.5))
            wing.addLine(to: CGPoint(x: -s * 0.1, y: 0))
            wing.closeSubpath()
            path.addPath(wing)
            var tail = Path()
            tail.move(to: CGPoint(x: -s * 0.36, y: 0))
            tail.addLine(to: CGPoint(x: -s * 0.48, y: sign * s * 0.17))
            tail.addLine(to: CGPoint(x: -s * 0.54, y: sign * s * 0.17))
            tail.addLine(to: CGPoint(x: -s * 0.48, y: 0))
            tail.closeSubpath()
            path.addPath(tail)
        }
        return path
    }

    private static func palm(_ context: inout GraphicsContext, base: CGPoint, height: Double, unit u: Double) {
        let top = CGPoint(x: base.x + u * 0.12, y: base.y - height)
        var trunk = Path()
        trunk.move(to: base)
        trunk.addQuadCurve(to: top, control: CGPoint(x: base.x - u * 0.04, y: base.y - height * 0.6))
        context.stroke(trunk, with: .color(Color(hex: 0x6B4A2B)), style: StrokeStyle(lineWidth: u * 0.035, lineCap: .round))
        for angle in stride(from: -170.0, through: 10, by: 30) {
            var frond = context
            frond.translateBy(x: top.x, y: top.y)
            frond.rotate(by: .degrees(angle))
            var leaf = Path()
            leaf.move(to: .zero)
            leaf.addQuadCurve(to: CGPoint(x: u * 0.24, y: u * 0.06), control: CGPoint(x: u * 0.12, y: -u * 0.07))
            leaf.addQuadCurve(to: .zero, control: CGPoint(x: u * 0.12, y: u * 0.02))
            frond.fill(leaf, with: .color(Color(hex: 0x1F7A4D)))
        }
    }

    private static func cake(_ context: inout GraphicsContext, center: CGPoint, unit u: Double) {
        let tiers: [(Double, Double, UInt32)] = [(0.52, 0.16, 0xFFF4E6), (0.38, 0.13, 0xFFE0EA)]
        var y = center.y + u * 0.2
        var topRect = CGRect.zero
        for tier in tiers {
            let r = CGRect(x: center.x - u * tier.0 / 2, y: y - u * tier.1, width: u * tier.0, height: u * tier.1)
            context.fill(Path(roundedRect: r, cornerRadius: u * 0.02), with: .color(Color(hex: tier.2)))
            // Frosting drips along the top edge.
            var drip = Path()
            drip.move(to: CGPoint(x: r.minX, y: r.minY))
            let n = 6
            for i in 0..<n {
                let x0 = r.minX + r.width * Double(i) / Double(n)
                let x1 = r.minX + r.width * Double(i + 1) / Double(n)
                drip.addQuadCurve(to: CGPoint(x: x1, y: r.minY + u * 0.01), control: CGPoint(x: (x0 + x1) / 2, y: r.minY + u * 0.06))
            }
            drip.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            drip.closeSubpath()
            context.fill(drip, with: .color(Color(hex: 0xFF5D8F)))
            topRect = r
            y = r.minY
        }
        context.fill(Path(roundedRect: CGRect(x: center.x - u * 0.31, y: center.y + u * 0.2, width: u * 0.62, height: u * 0.025),
                          cornerRadius: u * 0.012), with: .color(.white.opacity(0.9)))
        for i in 0..<5 {
            let x = topRect.minX + topRect.width * (Double(i) + 0.5) / 5
            let candle = CGRect(x: x - u * 0.008, y: topRect.minY - u * 0.08, width: u * 0.016, height: u * 0.08)
            context.fill(Path(candle), with: .color(Color(hex: [0x5BC0EB, 0xFFC145, 0x9BC53D, 0xB57EDC, 0xFF5D73][i])))
            let flame = CGPoint(x: x, y: candle.minY - u * 0.018)
            var glow = context
            glow.addFilter(.blur(radius: u * 0.015))
            glow.fill(circle(flame, u * 0.025), with: .color(Color(hex: 0xFFD166).opacity(0.8)))
            context.fill(Path(ellipseIn: CGRect(x: flame.x - u * 0.008, y: flame.y - u * 0.016, width: u * 0.016, height: u * 0.028)),
                         with: .color(Color(hex: 0xFFE9A8)))
        }
    }

    private static func mortarboard(_ context: inout GraphicsContext, size s: Double) {
        context.fill(Path(roundedRect: CGRect(x: -s * 0.24, y: 0, width: s * 0.48, height: s * 0.2), cornerRadius: s * 0.04),
                     with: .color(Color(hex: 0x111111)))
        var board = Path()
        board.move(to: CGPoint(x: 0, y: -s * 0.18))
        board.addLine(to: CGPoint(x: s * 0.5, y: 0))
        board.addLine(to: CGPoint(x: 0, y: s * 0.12))
        board.addLine(to: CGPoint(x: -s * 0.5, y: 0))
        board.closeSubpath()
        context.fill(board, with: .color(Color(hex: 0x1C1C1C)))
        var tassel = Path()
        tassel.move(to: .zero)
        tassel.addLine(to: CGPoint(x: s * 0.36, y: s * 0.04))
        tassel.addLine(to: CGPoint(x: s * 0.36, y: s * 0.3))
        context.stroke(tassel, with: .color(Color(hex: 0xF2C94C)), lineWidth: max(1, s * 0.02))
        context.fill(Path(roundedRect: CGRect(x: s * 0.33, y: s * 0.26, width: s * 0.06, height: s * 0.12), cornerRadius: s * 0.02),
                     with: .color(Color(hex: 0xF2C94C)))
    }

    private static func star(at p: CGPoint, radius r: Double) -> Path {
        var path = Path()
        for i in 0..<10 {
            let a = Double(i) * .pi / 5 - .pi / 2
            let rr = i.isMultiple(of: 2) ? r : r * 0.45
            let point = CGPoint(x: p.x + cos(a) * rr, y: p.y + sin(a) * rr)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// Centered on the origin, `size` wide.
    private static func heart(size s: Double) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: s * 0.35))
        path.addCurve(to: CGPoint(x: -s * 0.5, y: -s * 0.1), control1: CGPoint(x: -s * 0.1, y: s * 0.25), control2: CGPoint(x: -s * 0.5, y: s * 0.1))
        path.addArc(center: CGPoint(x: -s * 0.25, y: -s * 0.12), radius: s * 0.25, startAngle: .degrees(175), endAngle: .degrees(355), clockwise: false)
        path.addArc(center: CGPoint(x: s * 0.25, y: -s * 0.12), radius: s * 0.25, startAngle: .degrees(185), endAngle: .degrees(5), clockwise: false)
        path.addCurve(to: CGPoint(x: 0, y: s * 0.35), control1: CGPoint(x: s * 0.5, y: s * 0.1), control2: CGPoint(x: s * 0.1, y: s * 0.25))
        path.closeSubpath()
        return path
    }

    private static func burst(_ context: inout GraphicsContext, center: CGPoint, radius r: Double, color: Color,
                              rng: inout SeededRandom) {
        var glow = context
        glow.addFilter(.blur(radius: r * 0.3))
        glow.fill(circle(center, r * 0.6), with: .color(color.opacity(0.35)))
        let rays = 22
        for i in 0..<rays {
            let a = Double(i) / Double(rays) * 2 * .pi + rng.next() * 0.1
            let length = r * (0.75 + rng.next() * 0.25)
            let start = CGPoint(x: center.x + cos(a) * r * 0.18, y: center.y + sin(a) * r * 0.18)
            let end = CGPoint(x: center.x + cos(a) * length, y: center.y + sin(a) * length)
            var ray = Path()
            ray.move(to: start)
            ray.addLine(to: end)
            context.stroke(ray, with: .linearGradient(Gradient(colors: [color.opacity(0.1), color]), startPoint: start, endPoint: end),
                           style: StrokeStyle(lineWidth: max(1, r * 0.025), lineCap: .round))
            context.fill(circle(end, max(1, r * 0.028)), with: .color(.white.opacity(0.9)))
        }
    }

    private static func stadium(_ context: inout GraphicsContext, _ rect: CGRect, rng: inout SeededRandom) {
        sky(&context, rect, [0x060B1F, 0x14244D, 0x2B3F73], angle: 90, upTo: 0.5)
        stars(&context, rect, count: 30, maxRadius: 1, alpha: 0.5, rng: &rng, maxY: 0.3)
        let u = unit(rect)
        // Floodlights and their beams.
        for fx in [0.12, 0.88] {
            let lamp = CGPoint(x: rect.width * fx, y: rect.height * 0.14)
            var beam = context
            beam.addFilter(.blur(radius: u * 0.05))
            var cone = Path()
            cone.move(to: lamp)
            cone.addLine(to: CGPoint(x: rect.midX - rect.width * 0.25, y: rect.height * 0.75))
            cone.addLine(to: CGPoint(x: rect.midX + rect.width * 0.25, y: rect.height * 0.75))
            cone.closeSubpath()
            beam.fill(cone, with: .color(Color(hex: 0xFFF6D8).opacity(0.18)))
            context.fill(Path(CGRect(x: lamp.x - u * 0.006, y: lamp.y, width: u * 0.012, height: rect.height * 0.4)),
                         with: .color(Color(hex: 0x0A0F22)))
            let panel = CGRect(x: lamp.x - u * 0.06, y: lamp.y - u * 0.04, width: u * 0.12, height: u * 0.05)
            var glow = context
            glow.addFilter(.blur(radius: u * 0.03))
            glow.fill(Path(panel.insetBy(dx: -u * 0.02, dy: -u * 0.02)), with: .color(Color(hex: 0xFFF6D8).opacity(0.8)))
            context.fill(Path(roundedRect: panel, cornerRadius: u * 0.008), with: .color(Color(hex: 0xFFFBEA)))
        }
        // Stands, dotted with the crowd.
        let stands = CGRect(x: 0, y: rect.height * 0.42, width: rect.width, height: rect.height * 0.16)
        context.fill(Path(stands), with: .color(Color(hex: 0x1A1730)))
        for _ in 0..<220 {
            let p = CGPoint(x: rng.next() * rect.width, y: stands.minY + rng.next() * stands.height)
            context.fill(circle(p, u * 0.004), with: .color(Color(hex: [0xE63946, 0xF1FAEE, 0x457B9D, 0xFFD166][Int(rng.next() * 4) % 4]).opacity(0.7)))
        }
        // The field, striped, in perspective.
        let top = stands.maxY
        let stripes = 8
        for i in 0..<stripes {
            let y0 = top + (rect.height - top) * pow(Double(i) / Double(stripes), 1.4)
            let y1 = top + (rect.height - top) * pow(Double(i + 1) / Double(stripes), 1.4)
            context.fill(Path(CGRect(x: 0, y: y0, width: rect.width, height: y1 - y0 + 0.5)),
                         with: .color(Color(hex: i.isMultiple(of: 2) ? 0x2E8B3E : 0x277A35)))
        }
        var line = Path()
        line.move(to: CGPoint(x: 0, y: top + (rect.height - top) * 0.35))
        line.addLine(to: CGPoint(x: rect.width, y: top + (rect.height - top) * 0.35))
        context.stroke(line, with: .color(.white.opacity(0.6)), lineWidth: max(1, u * 0.006))
    }

    private static func pine(_ context: inout GraphicsContext, base: CGPoint, height h: Double, color: Color) {
        var tree = Path()
        for tier in 0..<3 {
            let top = base.y - h + h * Double(tier) * 0.22
            let width = h * (0.28 + Double(tier) * 0.1)
            tree.move(to: CGPoint(x: base.x, y: top))
            tree.addLine(to: CGPoint(x: base.x + width / 2, y: top + h * 0.45))
            tree.addLine(to: CGPoint(x: base.x - width / 2, y: top + h * 0.45))
            tree.closeSubpath()
        }
        tree.addRect(CGRect(x: base.x - h * 0.03, y: base.y - h * 0.12, width: h * 0.06, height: h * 0.12))
        context.fill(tree, with: .color(color))
    }

    private static func fire(_ context: inout GraphicsContext, base: CGPoint, unit u: Double) {
        var glow = context
        glow.addFilter(.blur(radius: u * 0.12))
        glow.fill(circle(CGPoint(x: base.x, y: base.y - u * 0.08), u * 0.3), with: .color(Color(hex: 0xFF7A1A).opacity(0.5)))
        for (angle, color) in [(-18.0, 0x6B3A1E), (18.0, 0x5A2F17)] as [(Double, UInt32)] {
            var log = context
            log.translateBy(x: base.x, y: base.y)
            log.rotate(by: .degrees(angle))
            log.fill(Path(roundedRect: CGRect(x: -u * 0.14, y: -u * 0.02, width: u * 0.28, height: u * 0.04), cornerRadius: u * 0.02),
                     with: .color(Color(hex: color)))
        }
        for (scale, hex) in [(1.0, 0xFF5A1F), (0.7, 0xFFA62B), (0.42, 0xFFE38A)] as [(Double, UInt32)] {
            let w = u * 0.17 * scale, h = u * 0.3 * scale
            var flame = Path()
            flame.move(to: CGPoint(x: base.x, y: base.y - h))
            flame.addQuadCurve(to: CGPoint(x: base.x + w / 2, y: base.y - u * 0.02), control: CGPoint(x: base.x + w * 0.7, y: base.y - h * 0.45))
            flame.addQuadCurve(to: CGPoint(x: base.x - w / 2, y: base.y - u * 0.02), control: CGPoint(x: base.x, y: base.y + u * 0.02))
            flame.addQuadCurve(to: CGPoint(x: base.x, y: base.y - h), control: CGPoint(x: base.x - w * 0.7, y: base.y - h * 0.45))
            context.fill(flame, with: .color(Color(hex: hex)))
        }
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
