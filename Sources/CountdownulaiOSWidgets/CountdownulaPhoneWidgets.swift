import SwiftUI
import WidgetKit

@main
struct CountdownulaPhoneWidgets: WidgetBundle {
    var body: some Widget {
        CountdownWidget()
        UpNextWidget()
        CountdownLiveActivity()
        if #available(iOS 18.0, *) {
            QuickTimerControl()
            NextUpControl()
        }
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
            // Extra large shows up on iPad.
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

private struct CountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CountdownEntry

    var body: some View {
        switch family {
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge:
            HomeCountdownView(entry: entry)
        default:
            ComplicationView(entry: entry)
        }
    }
}
