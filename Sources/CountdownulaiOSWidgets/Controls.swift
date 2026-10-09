import AppIntents
import SwiftUI
import WidgetKit

// Control Center, Lock Screen and Action button controls (iOS 18). The app targets iOS 17, so the
// bundle only offers these on 18 and later.

/// Starts a timer of a chosen length and puts it on the Lock Screen, without opening the app.
@available(iOS 18.0, *)
struct QuickTimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "com.countdownula.app.quick-timer", intent: QuickTimerControlConfiguration.self) { configuration in
            ControlWidgetButton(action: StartQuickTimerControlIntent(minutes: configuration.minutes)) {
                Label("\(Self.length(configuration.minutes)) Timer", systemImage: "timer")
            }
        }
        .displayName("Quick Timer")
        .description("Starts a timer and puts it on the Lock Screen.")
    }

    /// "10 min", "1 hr", "1.5 hr".
    static func length(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        return hours == hours.rounded() ? "\(Int(hours)) hr" : String(format: "%.1f hr", hours)
    }
}

@available(iOS 18.0, *)
struct QuickTimerControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Timer Length"

    @Parameter(title: "Minutes", default: 10, inclusiveRange: (1, 720))
    var minutes: Int
}

/// Your next countdown at a glance; tapping it opens it.
@available(iOS 18.0, *)
struct NextUpControl: ControlWidget {
    static let kind = NextUpControlKind.value

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: NextUpValueProvider()) { value in
            ControlWidgetButton(action: OpenCountdownIntent(countdownID: value.id)) {
                Label {
                    Text(value.title)
                    Text(value.timeLeft)
                } icon: {
                    Image(systemName: "hourglass")
                }
            }
        }
        .displayName("Next Up")
        .description("Your next countdown. Tap to open it.")
    }
}

@available(iOS 18.0, *)
struct NextUpValue {
    var id: UUID?
    var title: String
    var timeLeft: String
}

@available(iOS 18.0, *)
struct NextUpValueProvider: ControlValueProvider {
    var previewValue: NextUpValue { NextUpValue(id: nil, title: "Vacation", timeLeft: "16d 7h") }

    /// Controls don't tick; the app reloads them whenever its countdowns change.
    func currentValue() async throws -> NextUpValue {
        let now = Date()
        guard let countdown = WidgetSnapshot.read().featured(at: now) else {
            return NextUpValue(id: nil, title: "Count Downcula", timeLeft: "Nothing coming up")
        }
        return NextUpValue(id: countdown.id, title: countdown.title, timeLeft: CountdownFormat.compact(countdown, at: now))
    }
}
