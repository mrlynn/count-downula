import SwiftUI

/// A countdown's background on every surface: its photo, a drawn scene, a gradient or a solid color.
/// Callers pass the photo as an `Image` so this works the same with UIImage and NSImage.
struct StyledBackdrop: View {
    let style: CountdownStyle
    var photo: Image?
    /// Draws the fang dial (in the accent color) over plain backgrounds so they don't look empty.
    /// nil hides it; otherwise it's the fraction of the wait that's left.
    var dialRemaining: Double?
    var dialPadding: CGFloat = 40
    var dialAlignment: Alignment = .center
    var dialMaxWidth: CGFloat?

    var body: some View {
        ZStack(alignment: dialAlignment) {
            background
            if let dialRemaining, showsDial {
                FangDial(remaining: dialRemaining, trackOpacity: 0.3)
                    .foregroundStyle(style.accentColor)
                    .frame(maxWidth: dialMaxWidth)
                    .padding(dialPadding)
            }
        }
    }

    private var resolved: CountdownStyle.Background {
        switch style.background {
        case .automatic, .photo:
            photo == nil ? .gradient(.night) : .photo
        default:
            style.background
        }
    }

    private var showsDial: Bool {
        switch resolved {
        case .gradient, .solid: true
        default: false
        }
    }

    @ViewBuilder
    private var background: some View {
        switch resolved {
        case .photo:
            // Fill whatever frame the caller gives, without the photo's aspect ratio widening the layout.
            Color.clear
                .overlay {
                    photo?
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        case let .scene(scene):
            SceneArt(scene: scene)
        case let .gradient(spec):
            spec.linearGradient
        case let .solid(color):
            color.color
        case .automatic:
            LinearGradient.countdownulaNight
        }
    }
}

/// Darkens (or, for dark text, lightens) the lower part of a backdrop so text on top stays readable.
struct StyleScrim: View {
    let style: CountdownStyle
    var strength: Double = 1

    var body: some View {
        let tint: Color = style.hasLightText ? .black : .white
        LinearGradient(colors: [tint.opacity(0.1 * strength), tint.opacity(0.65 * strength)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// "15d 23h" when far off, a live ticking timer inside the last day, "Done" afterwards.
/// A count-up shows the time since it began the same way, ticking up.
struct CountdownTimeText: View {
    let countdown: Countdown
    let now: Date

    var body: some View {
        let parts = countdown.timeParts(at: now)
        if parts.isPast {
            Text("Done")
        } else if parts.days > 0 {
            Text("\(parts.days)d \(parts.hours)h")
        } else if parts.countsUp {
            Text(timerInterval: countdown.targetDate...Date.distantFuture, countsDown: false)
                .monospacedDigit()
        } else {
            Text(timerInterval: now...countdown.targetDate, countsDown: true)
                .monospacedDigit()
        }
    }
}
