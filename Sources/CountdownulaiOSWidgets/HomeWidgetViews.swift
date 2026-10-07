import SwiftUI
import WidgetKit

/// Home Screen / StandBy layout for a single countdown. Same structure at every size; larger sizes
/// get bigger type, the description and the date.
struct HomeCountdownView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    let entry: CountdownEntry

    var body: some View {
        if let countdown = entry.countdown {
            content(countdown)
        } else {
            VStack(spacing: 8) {
                FangMark()
                    .foregroundStyle(Color.countdownulaBlood)
                    .widgetAccentable()
                    .frame(width: 48, height: 48)
                Text("No upcoming countdowns")
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var isSmall: Bool { family == .systemSmall }
    private var isLarge: Bool { family == .systemLarge }

    /// The countdown's style, except where the system strips the background (StandBy, tinted).
    private func style(for countdown: Countdown) -> CountdownStyle {
        var style = countdown.style
        if !showsBackground { style.textColor = nil }
        return style
    }

    private func content(_ countdown: Countdown) -> some View {
        let style = style(for: countdown)
        let text = style.foregroundColor
        let parts = TimeParts(from: entry.date, to: countdown.targetDate)
        let remaining = parts.isPast ? 0 : 1 - countdown.progress(at: entry.date)
        // Without a photo, the large size fills its middle with a big dial instead.
        let showsBigDial = isLarge && entry.photo == nil

        return VStack(alignment: .leading, spacing: isSmall ? 2 : 6) {
            HStack(alignment: .top, spacing: 6) {
                if !showsBigDial {
                    FangDial(remaining: remaining, trackOpacity: 0.35)
                        .foregroundStyle(style.accentColor)
                        .widgetAccentable()
                        .frame(width: isSmall ? 24 : 28, height: isSmall ? 24 : 28)
                }
                if !isSmall {
                    Text(countdown.title)
                        .font(style.font(.headline))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if countdown.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(text.opacity(0.7))
                }
            }

            if showsBigDial {
                FangDial(remaining: remaining, trackOpacity: 0.3)
                    .foregroundStyle(style.accentColor)
                    .widgetAccentable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 6)
            } else {
                Spacer(minLength: 0)
            }

            if isLarge, !countdown.details.isEmpty {
                Text(countdown.details)
                    .font(.subheadline)
                    .foregroundStyle(text.opacity(0.8))
                    .lineLimit(3)
                    .padding(.bottom, 4)
            }

            bigTime(parts, target: countdown.targetDate, style: style)

            if isSmall {
                Text(countdown.title)
                    .font(style.font(.subheadline))
                    .lineLimit(2)
            } else {
                ProgressView(value: countdown.progress(at: entry.date))
                    .tint(style.accentColor)
                    .widgetAccentable()
                Text(countdown.targetDate, format: .dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(text.opacity(0.7))
            }
        }
        .foregroundStyle(text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// "16 days 7 hrs" while there are days left, a live timer inside the last day, "Done" after.
    @ViewBuilder
    private func bigTime(_ parts: TimeParts, target: Date, style: CountdownStyle) -> some View {
        let valueSize: CGFloat = isSmall ? 44 : isLarge ? 64 : 48
        if parts.isPast {
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(style.font(size: valueSize * 0.6))
        } else if parts.days > 0 {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(parts.days)")
                    .font(style.font(size: valueSize))
                    .widgetAccentable()
                Text(parts.days == 1 ? "day" : "days")
                    .font(style.font(size: valueSize * 0.34))
                if parts.hours > 0 {
                    Text("\(parts.hours) \(parts.hours == 1 ? "hr" : "hrs")")
                        .font(style.font(size: valueSize * 0.34))
                        .foregroundStyle(style.foregroundColor.opacity(0.7))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        } else {
            Text(timerInterval: entry.date...target, countsDown: true)
                .font(style.font(size: valueSize * 0.72))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
        }
    }
}
