import SwiftUI

/// How a countdown looks: its background, the type its numbers are set in, and its colors.
/// Synced as a small JSON blob on `CountdownRecord`, and carried in the widget snapshot.
struct CountdownStyle: Codable, Hashable {
    enum Background: Codable, Hashable {
        /// The photo if there is one, otherwise the midnight-to-blood gradient (how every countdown looked before styles).
        case automatic
        case photo
        case scene(SceneID)
        case gradient(GradientSpec)
        case solid(RGBAColor)

        /// Whether a stored photo is shown. Anything else means the photo can be dropped on save.
        var usesPhoto: Bool {
            switch self {
            case .automatic, .photo: true
            default: false
            }
        }
    }

    enum FontDesign: String, Codable, CaseIterable, Identifiable {
        case rounded, classic, serif, mono, condensed, expanded

        var id: String { rawValue }

        var name: String {
            switch self {
            case .rounded: "Rounded"
            case .classic: "Classic"
            case .serif: "Serif"
            case .mono: "Mono"
            case .condensed: "Condensed"
            case .expanded: "Wide"
            }
        }

        var design: Font.Design {
            switch self {
            case .rounded: .rounded
            case .serif: .serif
            case .mono: .monospaced
            case .classic, .condensed, .expanded: .default
            }
        }

        var width: Font.Width? {
            switch self {
            case .condensed: .condensed
            case .expanded: .expanded
            default: nil
            }
        }
    }

    enum FontWeight: String, Codable, CaseIterable, Identifiable {
        case regular, medium, semibold, bold, heavy, black

        var id: String { rawValue }
        var name: String { rawValue.capitalized }

        var weight: Font.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            case .heavy: .heavy
            case .black: .black
            }
        }
    }

    var background: Background = .automatic
    var font: FontDesign = .rounded
    var weight: FontWeight = .bold
    /// Text drawn over the background. nil means white.
    var textColor: RGBAColor?
    /// The dial, progress bars and badges. nil means Countdownula red.
    var accent: RGBAColor?

    static let `default` = CountdownStyle()
}

// MARK: - Resolved values

extension CountdownStyle {
    var accentColor: Color { accent?.color ?? .countdownulaBlood }
    var foregroundColor: Color { textColor?.color ?? .white }

    /// Light text needs a dark scrim behind it; dark text gets a light one instead.
    var hasLightText: Bool { (textColor?.luminance ?? 1) > 0.5 }

    func font(size: CGFloat) -> Font {
        let font = Font.system(size: size, weight: weight.weight, design: self.font.design)
        return self.font.width.map { font.width($0) } ?? font
    }

    func font(_ textStyle: Font.TextStyle) -> Font {
        let font = Font.system(textStyle, design: self.font.design, weight: weight.weight)
        return self.font.width.map { font.width($0) } ?? font
    }
}

// MARK: - Colors and gradients

/// A color that survives the trip through JSON and CloudKit (sRGB, gamma-encoded components).
struct RGBAColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double = 1

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    init(hex: UInt32, opacity: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.opacity = opacity
    }

    /// Captures any SwiftUI color, e.g. from a `ColorPicker`.
    init(_ color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        // Resolved components are linear; store them gamma-encoded like every other sRGB value.
        func encode(_ linear: Float) -> Double {
            let v = min(max(Double(linear), 0), 1)
            return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        }
        red = encode(resolved.linearRed)
        green = encode(resolved.linearGreen)
        blue = encode(resolved.linearBlue)
        opacity = Double(resolved.opacity)
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity) }

    /// Relative luminance (0 black ... 1 white), close enough to pick a scrim.
    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    static let white = RGBAColor(red: 1, green: 1, blue: 1)
}

struct GradientSpec: Codable, Hashable {
    var stops: [RGBAColor]
    /// Degrees; 0 runs left to right, 90 top to bottom.
    var angle: Double = 135

    var linearGradient: LinearGradient {
        let radians = angle * .pi / 180
        let dx = cos(radians) / 2
        let dy = sin(radians) / 2
        return LinearGradient(
            colors: stops.map(\.color),
            startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
            endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
        )
    }

    /// The midnight-to-blood backdrop used by the app icon, widgets and Live Activities.
    static let night = GradientSpec(stops: [RGBAColor(red: 0.30, green: 0.04, blue: 0.12),
                                            RGBAColor(red: 0.06, green: 0.02, blue: 0.05)], angle: 45)

    static let presets: [(name: String, spec: GradientSpec)] = [
        ("Night", night),
        ("Ember", GradientSpec(stops: [RGBAColor(hex: 0xF83600), RGBAColor(hex: 0x6A0D1B)], angle: 120)),
        ("Sunset", GradientSpec(stops: [RGBAColor(hex: 0xFF9A5A), RGBAColor(hex: 0xE94E77), RGBAColor(hex: 0x4B2A6B)], angle: 90)),
        ("Peach", GradientSpec(stops: [RGBAColor(hex: 0xFFD3A5), RGBAColor(hex: 0xFD6585)], angle: 135)),
        ("Candy", GradientSpec(stops: [RGBAColor(hex: 0xFF6FD8), RGBAColor(hex: 0x3813C2)], angle: 135)),
        ("Lavender", GradientSpec(stops: [RGBAColor(hex: 0xC3A6FF), RGBAColor(hex: 0x5B3E96)], angle: 100)),
        ("Ocean", GradientSpec(stops: [RGBAColor(hex: 0x2BC0E4), RGBAColor(hex: 0x1A3D7C)], angle: 90)),
        ("Aurora", GradientSpec(stops: [RGBAColor(hex: 0x43E97B), RGBAColor(hex: 0x1E6F8A), RGBAColor(hex: 0x14213D)], angle: 70)),
        ("Forest", GradientSpec(stops: [RGBAColor(hex: 0x5A8F3C), RGBAColor(hex: 0x173B2A)], angle: 110)),
        ("Gold", GradientSpec(stops: [RGBAColor(hex: 0xF7D774), RGBAColor(hex: 0xB0702A)], angle: 135)),
        ("Graphite", GradientSpec(stops: [RGBAColor(hex: 0x5C6370), RGBAColor(hex: 0x16181D)], angle: 135)),
        ("Mint", GradientSpec(stops: [RGBAColor(hex: 0xD4FC79), RGBAColor(hex: 0x6DD5C4)], angle: 135)),
    ]
}

extension LinearGradient {
    static let countdownulaNight = GradientSpec.night.linearGradient
}
