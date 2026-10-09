import SwiftUI
import WidgetKit

/// Desktop and Notification Center widgets for the Mac, drawn by the same views as the iPhone's
/// Home Screen widgets. They read the snapshot the menu bar app writes to its App Group, and a click
/// opens that countdown in the menu bar popover.
@main
struct CountdownulaMacWidgets: WidgetBundle {
    var body: some Widget {
        MacCountdownWidget()
        UpNextWidget()
    }
}

struct MacCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SharedConfig.widgetKind,
            intent: SelectCountdownIntent.self,
            provider: CountdownProvider()
        ) { entry in
            HomeCountdownView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackdrop(photo: entry.photo, style: entry.countdown?.style ?? .default)
                }
                .widgetURL(entry.countdown.map { CountdownLink.url(for: $0.id) })
        }
        .configurationDisplayName("Countdown")
        .description("Time left until one of your countdowns.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}
