#if DEBUG
import SwiftUI
import WidgetKit

/// Debug-only screen (launch with `-complicationGallery`) that renders each complication at roughly
/// its on-face size, so the designs can be checked in the simulator without editing a watch face.
struct ComplicationGallery: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let featured = store.countdowns.featured(at: now)
            let entry = CountdownEntry(
                date: now,
                countdown: featured ?? CountdownEntry.sample.countdown,
                thumbnail: featured.flatMap { store.thumbnail(for: $0) }?.jpegData(compressionQuality: 0.8)
            )
            let timer = store.countdowns.first { $0.kind == .timer && !$0.isPast(at: now) }

            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        CircularComplication(entry: entry).frame(width: 50, height: 50)
                        if let timer {
                            CircularComplication(entry: CountdownEntry(date: now, countdown: timer))
                                .frame(width: 50, height: 50)
                        }
                        CircularComplication(entry: CountdownEntry(date: now, countdown: nil))
                            .frame(width: 50, height: 50)
                    }
                    RectangularComplication(entry: entry)
                        .frame(width: 170, height: 54)
                    if let timer {
                        RectangularComplication(entry: CountdownEntry(date: now, countdown: timer))
                            .frame(width: 170, height: 54)
                    }
                    InlineComplication(entry: entry)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
#endif
