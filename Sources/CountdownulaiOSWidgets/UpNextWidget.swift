import SwiftUI
import WidgetKit

/// The next few countdowns as a list (medium and large Home Screen sizes).
struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpNext", provider: UpNextProvider()) { entry in
            UpNextView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackdrop()
                }
        }
        .configurationDisplayName("Up Next")
        .description("Your next few countdowns.")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct UpNextEntry: TimelineEntry {
    let date: Date
    let countdowns: [Countdown]
    var thumbnails: [UUID: Data] = [:]

    func upcoming(limit: Int) -> [Countdown] {
        let upcoming = countdowns.filter { $0.isUpcoming(at: date) }.sorted { $0.targetDate < $1.targetDate }
        // Pinned countdowns lead, like everywhere else.
        return Array((upcoming.filter(\.isPinned) + upcoming.filter { !$0.isPinned }).prefix(limit))
    }
}

struct UpNextProvider: TimelineProvider {
    private static let maxRows = 6

    func placeholder(in context: Context) -> UpNextEntry {
        let now = Date()
        return UpNextEntry(date: now, countdowns: [
            Countdown(title: "Vacation", details: "", targetDate: now + 16 * 86_400, createdAt: now - 30 * 86_400),
            Countdown(title: "Birthday", details: "", targetDate: now + 9 * 86_400, createdAt: now - 20 * 86_400),
            Countdown(title: "Launch", details: "", targetDate: now + 5 * 3_600, createdAt: now - 86_400),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (UpNextEntry) -> Void) {
        let entry = makeEntry(at: Date())
        completion(context.isPreview && entry.countdowns.isEmpty ? placeholder(in: context) : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpNextEntry>) -> Void) {
        let now = Date()
        let base = makeEntry(at: now)
        // Refresh wherever any visible row's text changes, over the next 12 hours.
        let horizon = now + 12 * 3_600
        var dates: Set<Date> = [now]
        for countdown in base.upcoming(limit: Self.maxRows) {
            for date in CountdownProvider.entryDates(for: countdown.targetDate, from: now) where date <= horizon {
                dates.insert(date)
            }
        }
        let entries = dates.sorted().prefix(150).map {
            UpNextEntry(date: $0, countdowns: base.countdowns, thumbnails: base.thumbnails)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func makeEntry(at now: Date) -> UpNextEntry {
        let all = WidgetSnapshot.read().filter { $0.isUpcoming(at: now) }
        var thumbnails: [UUID: Data] = [:]
        for countdown in all where countdown.hasImage {
            thumbnails[countdown.id] = WidgetSnapshot.thumbnail(for: countdown.id)
        }
        return UpNextEntry(date: now, countdowns: all, thumbnails: thumbnails)
    }
}

private struct UpNextView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpNextEntry

    var body: some View {
        let isLarge = family == .systemLarge || family == .systemExtraLarge
        let rows = entry.upcoming(limit: isLarge ? 6 : 3)

        VStack(alignment: .leading, spacing: isLarge ? 10 : 6) {
            HStack(spacing: 6) {
                FangMark()
                    .foregroundStyle(Color.countdownulaBlood)
                    .widgetAccentable()
                    .frame(width: 16, height: 16)
                Text("UP NEXT")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.7))
            }

            if rows.isEmpty {
                Spacer()
                Text("No upcoming countdowns")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(rows) { countdown in
                    Link(destination: CountdownLink.url(for: countdown.id)) {
                        row(countdown, isLarge: isLarge)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
    }

    private func row(_ countdown: Countdown, isLarge: Bool) -> some View {
        let side: CGFloat = isLarge ? 38 : 30
        let parts = TimeParts(from: entry.date, to: countdown.targetDate)

        return HStack(spacing: 10) {
            Group {
                if let data = entry.thumbnails[countdown.id], let image = WidgetImage.image(from: data, maxPixelDimension: 120) {
                    FullColorPhoto(image: image)
                } else {
                    FangDial(remaining: 1 - countdown.progress(at: entry.date), trackOpacity: 0.35)
                        .foregroundStyle(countdown.style.accentColor)
                        .widgetAccentable()
                        .padding(4)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(countdown.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(countdown.targetDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer(minLength: 4)

            Group {
                if parts.days > 0 {
                    Text("\(parts.days)d \(parts.hours)h")
                } else {
                    Text(timerInterval: entry.date...countdown.targetDate, countsDown: true)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80, alignment: .trailing)
                }
            }
            .font(.system(.headline, design: .rounded).weight(.bold))
            .monospacedDigit()
            .lineLimit(1)
            .widgetAccentable()
        }
    }
}

/// Keeps photos in color on iOS 18's tinted Home Screen.
private struct FullColorPhoto: View {
    let image: Image

    var body: some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            image.resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
        } else {
            image.resizable().scaledToFill()
        }
    }
}
