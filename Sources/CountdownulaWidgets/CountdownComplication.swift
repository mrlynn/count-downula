import AppIntents
import SwiftUI
import WidgetKit

#if os(watchOS)
@main
struct CountdownulaWidgets: WidgetBundle {
    var body: some Widget {
        CountdownComplication()
    }
}

struct CountdownComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SharedConfig.widgetKind,
            intent: SelectCountdownIntent.self,
            provider: CountdownProvider()
        ) { entry in
            ComplicationView(entry: entry)
                // Shown in the Smart Stack; watch faces strip it automatically.
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(red: 0.30, green: 0.04, blue: 0.12), .black],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Countdown")
        .description("Time left until one of your countdowns.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}
#endif

// MARK: - Configuration

struct CountdownEntity: AppEntity {
    let id: UUID
    let title: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Countdown"
    static let defaultQuery = CountdownEntityQuery()

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    init(_ countdown: Countdown) {
        id = countdown.id
        title = countdown.title
    }
}

struct CountdownEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [CountdownEntity] {
        WidgetSnapshot.read().filter { identifiers.contains($0.id) }.map(CountdownEntity.init)
    }

    func suggestedEntities() async throws -> [CountdownEntity] {
        let now = Date()
        return WidgetSnapshot.read()
            .filter { !$0.isPast(at: now) }
            .sorted { $0.targetDate < $1.targetDate }
            .map(CountdownEntity.init)
    }
}

struct SelectCountdownIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Countdown"
    static let description = IntentDescription("Pick a countdown, or leave it empty to show the next one up.")

    @Parameter(title: "Countdown")
    var countdown: CountdownEntity?

    init() {}

    init(countdown: CountdownEntity?) {
        self.countdown = countdown
    }
}

// MARK: - Timeline

struct CountdownProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CountdownEntry { .sample }

    func snapshot(for configuration: SelectCountdownIntent, in context: Context) async -> CountdownEntry {
        let now = Date()
        guard let countdown = resolve(configuration, at: now) else {
            return context.isPreview ? .sample : CountdownEntry(date: now, countdown: nil)
        }
        return CountdownEntry(date: now, countdown: countdown, thumbnail: WidgetSnapshot.thumbnail(for: countdown.id),
                              photo: WidgetSnapshot.photo(for: countdown))
    }

    func timeline(for configuration: SelectCountdownIntent, in context: Context) async -> Timeline<CountdownEntry> {
        let now = Date()
        guard let countdown = resolve(configuration, at: now) else {
            return Timeline(entries: [CountdownEntry(date: now, countdown: nil)], policy: .after(now + 3_600))
        }
        let thumbnail = WidgetSnapshot.thumbnail(for: countdown.id)
        let photo = WidgetSnapshot.photo(for: countdown)
        let entries = Self.entryDates(for: countdown.targetDate, from: now).map {
            CountdownEntry(date: $0, countdown: countdown, thumbnail: thumbnail, photo: photo)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    func recommendations() -> [AppIntentRecommendation<SelectCountdownIntent>] {
        let now = Date()
        let upcoming = WidgetSnapshot.read()
            .filter { !$0.isPast(at: now) }
            .sorted { $0.targetDate < $1.targetDate }
            .prefix(12)
        return [AppIntentRecommendation(intent: SelectCountdownIntent(), description: "Next Up")]
            + upcoming.map {
                AppIntentRecommendation(intent: SelectCountdownIntent(countdown: CountdownEntity($0)),
                                        description: Text($0.title))
            }
    }

    /// A fixed countdown falls back to "next up" once it has been finished for a day (or was deleted).
    private func resolve(_ configuration: SelectCountdownIntent, at now: Date) -> Countdown? {
        let all = WidgetSnapshot.read()
        if let id = configuration.countdown?.id,
           let chosen = all.first(where: { $0.id == id }),
           chosen.targetDate > now - 86_400 {
            return chosen
        }
        return all.featured(at: now)
    }

    /// Entries land exactly where the displayed text changes: on each hour boundary before the target
    /// (for "15d 23h" and the dial), each minute in the final hour, and at the target itself.
    /// The live timer text handles the seconds in between.
    static func entryDates(for target: Date, from now: Date) -> [Date] {
        var dates: Set<Date> = [now]
        let remaining = target.timeIntervalSince(now)
        guard remaining > 0 else { return [now] }

        let hoursLeft = Int(remaining / 3_600)
        for k in stride(from: hoursLeft, through: max(1, hoursLeft - 23), by: -1) {
            let date = target - TimeInterval(k) * 3_600
            if date > now { dates.insert(date) }
        }
        if remaining < 3_600 * 2 {
            for k in 1...60 {
                let date = target - TimeInterval(k) * 60
                if date > now { dates.insert(date) }
            }
        }
        dates.insert(target)
        return dates.sorted()
    }
}
