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
                    WidgetBackdrop(photo: entry.photo, style: entry.countdown?.style ?? .default)
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

/// The countdown's photo, scene, gradient or color under a scrim. StandBy and tinted Home Screens
/// remove it, so the views on top switch to plain white text there.
struct WidgetBackdrop: View {
    var photo: Data?
    var style: CountdownStyle = .default

    var body: some View {
        let image = photo.flatMap { ImageDownsampling.image(from: $0, maxPixelDimension: 700) }
        StyledBackdrop(style: style, photo: image.map { Image(uiImage: $0) })
            .overlay {
                if image != nil || style.background != .automatic { StyleScrim(style: style) }
            }
    }
}
