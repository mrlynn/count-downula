import AppIntents
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
    private var isLarge: Bool { family == .systemLarge || family == .systemExtraLarge }

    /// The countdown's style, except where the system strips the background (StandBy, tinted).
    private func style(for countdown: Countdown) -> CountdownStyle {
        var style = countdown.style
        if !showsBackground { style.textColor = nil }
        return style
    }

    /// Buttons that work without opening the app: put it on the Lock Screen in its final hours, pin
    /// or unpin, and step a Next Up widget on to the following countdown.
    @ViewBuilder
    private func controls(for countdown: Countdown, text: Color) -> some View {
        HStack(spacing: 6) {
            #if os(iOS)
            if countdown.isUpcoming(at: entry.date), countdown.targetDate.timeIntervalSince(entry.date) <= 8 * 3_600 {
                WidgetIconButton(symbol: "lock.iphone", label: "Show on Lock Screen", tint: text,
                                 intent: StartWidgetLiveActivityIntent(countdownID: countdown.id))
            }
            WidgetIconButton(symbol: countdown.isPinned ? "pin.fill" : "pin", label: countdown.isPinned ? "Unpin" : "Pin",
                             tint: text, intent: ToggleWidgetPinIntent(countdownID: countdown.id))
            #endif
            if entry.isNextUp {
                WidgetIconButton(symbol: "chevron.forward", label: "Next countdown", tint: text,
                                 intent: CycleWidgetCountdownIntent())
            }
        }
    }

    private func content(_ countdown: Countdown) -> some View {
        let style = style(for: countdown)
        let text = style.foregroundColor
        let parts = countdown.timeParts(at: entry.date)
        let remaining = countdown.dialRemaining(at: entry.date)
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
                if isSmall {
                    if countdown.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(text.opacity(0.7))
                    }
                } else {
                    controls(for: countdown, text: text)
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

            if isLarge, let savings = countdown.extras.savings, countdown.countsUp {
                Text("\(savings.formatted(since: countdown.targetDate, at: entry.date)) saved")
                    .font(style.font(.title3))
                    .foregroundStyle(style.accentColor)
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
                if let next = countdown.nextMilestone(at: entry.date) {
                    Text("Next: \(next.milestone.displayEmoji) \(next.milestone.title) · \(CountdownFormat.compact(from: entry.date, to: next.date))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(text.opacity(0.85))
                        .lineLimit(1)
                }
                ProgressView(value: countdown.progress(at: entry.date))
                    .tint(style.accentColor)
                    .widgetAccentable()
                Group {
                    if countdown.countsUp {
                        Text("Since \(countdown.targetDate.formatted(.dateTime.month(.abbreviated).day().year()))")
                    } else {
                        Text(countdown.targetDate, format: .dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
                    }
                }
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
                    Text("\(parts.hours) hrs")
                        .font(style.font(size: valueSize * 0.34))
                        .foregroundStyle(style.foregroundColor.opacity(0.7))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        } else if parts.countsUp {
            Text(timerInterval: target...Date.distantFuture, countsDown: false)
                .font(style.font(size: valueSize * 0.72))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
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

/// A small round button on a widget that runs an App Intent instead of opening the app.
struct WidgetIconButton<Intent: AppIntent>: View {
    let symbol: String
    let label: String
    let tint: Color
    let intent: Intent

    var body: some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.16), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint.opacity(0.9))
        .accessibilityLabel(label)
    }
}

/// The countdown's photo, scene, gradient or color under a scrim. StandBy and tinted Home Screens
/// remove it, so the views on top switch to plain white text there.
struct WidgetBackdrop: View {
    var photo: Data?
    var style: CountdownStyle = .default

    var body: some View {
        let image = photo.flatMap { WidgetImage.image(from: $0, maxPixelDimension: 700) }
        StyledBackdrop(style: style, photo: image)
            .overlay {
                if image != nil || style.background != .automatic { StyleScrim(style: style) }
            }
    }
}
