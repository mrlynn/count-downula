import SwiftUI
import WidgetKit

/// Home Screen / StandBy layout for a single countdown. Same structure at every size; larger sizes
/// get bigger type, the description and the date.
struct HomeCountdownView: View {
    @Environment(\.widgetFamily) private var family
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

    private func content(_ countdown: Countdown) -> some View {
        let parts = TimeParts(from: entry.date, to: countdown.targetDate)
        let remaining = parts.isPast ? 0 : 1 - countdown.progress(at: entry.date)
        // Without a photo, the large size fills its middle with a big dial instead.
        let showsBigDial = isLarge && entry.photo == nil

        return VStack(alignment: .leading, spacing: isSmall ? 2 : 6) {
            HStack(alignment: .top, spacing: 6) {
                if !showsBigDial {
                    FangDial(remaining: remaining, trackOpacity: 0.35)
                        .foregroundStyle(Color.countdownulaBlood)
                        .widgetAccentable()
                        .frame(width: isSmall ? 24 : 28, height: isSmall ? 24 : 28)
                }
                if !isSmall {
                    Text(countdown.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if countdown.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            if showsBigDial {
                FangDial(remaining: remaining, trackOpacity: 0.3)
                    .foregroundStyle(Color.countdownulaBlood)
                    .widgetAccentable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 6)
            } else {
                Spacer(minLength: 0)
            }

            if isLarge, !countdown.details.isEmpty {
                Text(countdown.details)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(3)
                    .padding(.bottom, 4)
            }

            bigTime(parts, target: countdown.targetDate)

            if isSmall {
                Text(countdown.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            } else {
                ProgressView(value: countdown.progress(at: entry.date))
                    .tint(Color.countdownulaBlood)
                    .widgetAccentable()
                Text(countdown.targetDate, format: .dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// "16 days 7 hrs" while there are days left, a live timer inside the last day, "Done" after.
    @ViewBuilder
    private func bigTime(_ parts: TimeParts, target: Date) -> some View {
        let valueSize: CGFloat = isSmall ? 44 : isLarge ? 64 : 48
        if parts.isPast {
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.system(size: valueSize * 0.6, weight: .bold, design: .rounded))
        } else if parts.days > 0 {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(parts.days)")
                    .font(.system(size: valueSize, weight: .bold, design: .rounded))
                    .widgetAccentable()
                Text(parts.days == 1 ? "day" : "days")
                    .font(.system(size: valueSize * 0.34, weight: .semibold, design: .rounded))
                if parts.hours > 0 {
                    Text("\(parts.hours) \(parts.hours == 1 ? "hr" : "hrs")")
                        .font(.system(size: valueSize * 0.34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        } else {
            Text(timerInterval: entry.date...target, countsDown: true)
                .font(.system(size: valueSize * 0.72, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
        }
    }
}
