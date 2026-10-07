import SwiftUI
import WidgetKit

@main
struct CountdownulaPhoneWidgets: WidgetBundle {
    var body: some Widget {
        CountdownWidget()
        UpNextWidget()
        CountdownLiveActivity()
    }
}

/// One countdown, everywhere: Home Screen and StandBy (small / medium / large) and the
/// Lock Screen (circular / rectangular / inline, drawn by the same views as the watch complications).
struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SharedConfig.widgetKind,
            intent: SelectCountdownIntent.self,
            provider: CountdownProvider()
        ) { entry in
            CountdownWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackdrop(photo: entry.photo)
                }
                .widgetURL(entry.countdown.map { CountdownLink.url(for: $0.id) })
        }
        .configurationDisplayName("Countdown")
        .description("Time left until one of your countdowns.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

private struct CountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CountdownEntry

    var body: some View {
        switch family {
        case .systemSmall, .systemMedium, .systemLarge:
            HomeCountdownView(entry: entry)
        default:
            ComplicationView(entry: entry)
        }
    }
}

/// The photo under a dark scrim, or the midnight-to-blood gradient. StandBy and tinted Home Screens
/// remove it, so everything on top is plain white text that reads on black too.
struct WidgetBackdrop: View {
    var photo: Data?

    var body: some View {
        if let photo, let image = ImageDownsampling.image(from: photo, maxPixelDimension: 700) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                }
        } else {
            LinearGradient(colors: [Color(red: 0.30, green: 0.04, blue: 0.12), Color(red: 0.06, green: 0.02, blue: 0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
