import SwiftUI
import WidgetKit

/// Shared by the watch and iPhone widget extensions and the watch app's debug gallery.
struct CountdownEntry: TimelineEntry {
    let date: Date
    let countdown: Countdown?
    var thumbnail: Data?
    /// Display-size photo for Home Screen widgets (iPhone only).
    var photo: Data?

    static var sample: CountdownEntry {
        let now = Date()
        return CountdownEntry(
            date: now,
            countdown: Countdown(title: "Vacation", details: "", targetDate: now + 16 * 86_400 + 25_200,
                                 createdAt: now - 30 * 86_400)
        )
    }
}

/// Routes to the view for the current complication family.
struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: CountdownEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            RectangularComplication(entry: entry, showsPhoto: renderingMode == .fullColor)
        #if os(watchOS)
        case .accessoryCorner:
            CornerComplication(entry: entry)
        #endif
        case .accessoryInline:
            InlineComplication(entry: entry)
        default:
            CircularComplication(entry: entry)
        }
    }
}

// MARK: - Circular: the fanged ring drains as the date approaches

struct CircularComplication: View {
    let entry: CountdownEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()

            if let countdown = entry.countdown {
                let parts = TimeParts(from: entry.date, to: countdown.targetDate)
                FangDial(remaining: parts.isPast ? 0 : 1 - countdown.progress(at: entry.date), trackOpacity: 0.3)
                    .foregroundStyle(countdown.style.accentColor)
                    .widgetAccentable()
                    .padding(2)

                centerLabel(parts: parts, target: countdown.targetDate)
                    .offset(y: -3)
            } else {
                FangMark()
                    .foregroundStyle(Color.countdownulaBlood)
                    .widgetAccentable()
                    .padding(6)
            }
        }
    }

    @ViewBuilder
    private func centerLabel(parts: TimeParts, target: Date) -> some View {
        if parts.isPast {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
        } else if parts.days > 0 || parts.hours > 0 {
            let value = parts.days > 0 ? parts.days : parts.hours
            let unit = parts.days > 0 ? (parts.days == 1 ? "DAY" : "DAYS") : (parts.hours == 1 ? "HR" : "HRS")
            VStack(spacing: -2) {
                Text("\(value)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.system(size: 7, weight: .semibold))
            }
        } else {
            Text(timerInterval: entry.date...target, countsDown: true)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .frame(width: 30)
        }
    }
}

// MARK: - Rectangular: title, live time, progress (+ photo on full-color faces / Smart Stack)

struct RectangularComplication: View {
    let entry: CountdownEntry
    var showsPhoto = true

    var body: some View {
        if let countdown = entry.countdown {
            let isPast = countdown.isPast(at: entry.date)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        FangMark()
                            .foregroundStyle(countdown.style.accentColor)
                            .widgetAccentable()
                            .frame(width: 13, height: 13)
                        Text(countdown.title)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    timeText(countdown, isPast: isPast)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    ProgressView(value: countdown.progress(at: entry.date))
                        .tint(countdown.style.accentColor)
                        .widgetAccentable()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsPhoto, let data = entry.thumbnail, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        } else {
            HStack(spacing: 6) {
                FangMark()
                    .foregroundStyle(Color.countdownulaBlood)
                    .widgetAccentable()
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading) {
                    Text("Count Downula").font(.headline)
                    Text("No upcoming countdowns").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func timeText(_ countdown: Countdown, isPast: Bool) -> some View {
        let parts = TimeParts(from: entry.date, to: countdown.targetDate)
        if isPast {
            Text("Done")
        } else if parts.days > 0 {
            Text("\(parts.days)d \(parts.hours)h")
        } else {
            Text(timerInterval: entry.date...countdown.targetDate, countsDown: true)
        }
    }
}

#if os(watchOS)
// MARK: - Corner: short value with a curved gauge

struct CornerComplication: View {
    let entry: CountdownEntry

    var body: some View {
        let countdown = entry.countdown
        let parts = countdown.map { TimeParts(from: entry.date, to: $0.targetDate) }

        ZStack {
            AccessoryWidgetBackground()
            Group {
                if let parts, !parts.isPast {
                    Text(parts.days > 0 ? "\(parts.days)d" : parts.hours > 0 ? "\(parts.hours)h" : "\(max(parts.minutes, 1))m")
                } else {
                    Image(systemName: countdown == nil ? "hourglass" : "checkmark")
                }
            }
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .widgetAccentable()
        }
        .widgetLabel {
            if let countdown {
                ProgressView(value: 1 - countdown.progress(at: entry.date)) {
                    Text(countdown.title)
                }
                .tint(Color.countdownulaBlood)
            }
        }
    }
}

#endif

// MARK: - Inline: one line of text at the top of the face

struct InlineComplication: View {
    let entry: CountdownEntry

    var body: some View {
        if let countdown = entry.countdown {
            let parts = TimeParts(from: entry.date, to: countdown.targetDate)
            if parts.isPast {
                Text("\(countdown.title) · Done")
            } else if parts.days > 0 {
                Text("\(countdown.title) · \(parts.days)d \(parts.hours)h")
            } else {
                Text("\(countdown.title) · ") + Text(timerInterval: entry.date...countdown.targetDate, countsDown: true)
            }
        } else {
            Text("No countdowns")
        }
    }
}
