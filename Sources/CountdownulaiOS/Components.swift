import SwiftUI

/// A countdown's background: its photo, scene, gradient or color, with the fang dial over plain backgrounds.
struct CountdownArtwork: View {
    @Environment(PhoneStore.self) private var store
    let countdown: Countdown
    var useThumbnail = false
    var now = Date()
    /// Tucks the placeholder dial into the top-right corner so text can sit over the artwork.
    var dialInCorner = false
    /// Overrides the stored photo (the editor's unsaved preview).
    var previewImage: UIImage?

    var body: some View {
        let image = previewImage ?? (useThumbnail ? store.thumbnail(for: countdown) : store.image(for: countdown))
        StyledBackdrop(
            style: countdown.style,
            photo: image.map { Image(uiImage: $0) },
            dialRemaining: countdown.isPast(at: now) ? 0 : 1 - countdown.progress(at: now),
            dialPadding: useThumbnail ? 8 : dialInCorner ? 18 : 40,
            dialAlignment: dialInCorner ? .topTrailing : .center,
            dialMaxWidth: dialInCorner ? 72 : nil
        )
    }
}

/// The big styled card: backdrop, title and a live D/H/M/S readout. Used for the hero, the detail
/// header and the editor's preview.
struct StyledCountdownCard: View {
    let countdown: Countdown
    let now: Date
    var badge: String?
    var subtitle: Text?
    var previewImage: UIImage?
    var height: CGFloat = 260

    var body: some View {
        let style = countdown.style
        let parts = TimeParts(from: now, to: countdown.targetDate)

        CountdownArtwork(countdown: countdown, now: now, dialInCorner: true, previewImage: previewImage)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay { StyleScrim(style: style) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .tracking(1.2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(style.accentColor, in: Capsule())
                        }
                        subtitle
                            .font(.caption.weight(.medium))
                            .foregroundStyle(style.foregroundColor.opacity(0.8))
                    }
                    Text(countdown.title.isEmpty ? "Untitled" : countdown.title)
                        .font(style.font(.title))
                        .lineLimit(2)
                    TimeBlocks(parts: parts, tileColor: style.foregroundColor.opacity(0.14), size: 30, style: style)
                        .environment(\.colorScheme, style.hasLightText ? .dark : .light)
                }
                .foregroundStyle(style.foregroundColor)
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
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
    var style = CountdownStyle.default

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
                .font(style.font(size: size))
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
