import SwiftUI

/// Photo for a countdown, or the fanged dial on a dark gradient when it has none.
struct CountdownArtwork: View {
    @Environment(PhoneStore.self) private var store
    let countdown: Countdown
    var useThumbnail = false
    var now = Date()
    /// Tucks the placeholder dial into the top-right corner so text can sit over the artwork.
    var dialInCorner = false

    var body: some View {
        if let image = useThumbnail ? store.thumbnail(for: countdown) : store.image(for: countdown) {
            // Fill whatever frame the caller gives, without the photo's aspect ratio widening the layout.
            Color.clear
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else {
            ZStack(alignment: dialInCorner ? .topTrailing : .center) {
                LinearGradient.countdownulaNight
                FangDial(remaining: countdown.isPast(at: now) ? 0 : 1 - countdown.progress(at: now), trackOpacity: 0.3)
                    .foregroundStyle(Color.countdownulaBlood)
                    .frame(maxWidth: dialInCorner ? 72 : nil)
                    .padding(useThumbnail ? 8 : dialInCorner ? 18 : 40)
            }
        }
    }
}

extension LinearGradient {
    /// The midnight-to-blood backdrop used by the app icon, widgets and Live Activities.
    static let countdownulaNight = LinearGradient(
        colors: [Color(red: 0.30, green: 0.04, blue: 0.12), Color(red: 0.06, green: 0.02, blue: 0.05)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// "15d 23h" when far off, a live ticking timer inside the last day, "Done" afterwards.
struct CountdownTimeText: View {
    let countdown: Countdown
    let now: Date

    var body: some View {
        let parts = TimeParts(from: now, to: countdown.targetDate)
        if parts.isPast {
            Text("Done")
        } else if parts.days > 0 {
            Text("\(parts.days)d \(parts.hours)h")
        } else {
            Text(timerInterval: now...countdown.targetDate, countsDown: true)
                .monospacedDigit()
        }
    }
}

/// Days / hours / minutes / seconds tiles.
struct TimeBlocks: View {
    let parts: TimeParts
    var tileColor = Color.primary.opacity(0.06)
    var size: CGFloat = 34

    var body: some View {
        HStack(spacing: 8) {
            block(parts.days, "Days")
            block(parts.hours, "Hours")
            block(parts.minutes, "Min")
            block(parts.seconds, "Sec")
        }
        .opacity(parts.isPast ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(parts.isPast
            ? "Finished"
            : "\(parts.days) days, \(parts.hours) hours, \(parts.minutes) minutes, \(parts.seconds) seconds left")
    }

    private func block(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%02d", value))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(tileColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
