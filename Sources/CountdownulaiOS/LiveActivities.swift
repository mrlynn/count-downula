import ActivityKit
import UIKit

/// Starts, updates and ends countdown Live Activities.
///
/// The iPhone's take on the Mac's "pin to menu bar": a pinned countdown goes live on the Lock Screen
/// and in the Dynamic Island once it's inside its final eight hours (the most iOS keeps one running),
/// and any countdown in that window can be started by hand from its detail screen.
@MainActor
enum LiveActivities {
    static let window: TimeInterval = 8 * 3_600

    private typealias CountdownActivity = Activity<CountdownActivityAttributes>
    private static let autoStartedKey = "LiveActivities.autoStarted"

    static var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    static func isEligible(_ countdown: Countdown, at now: Date = Date()) -> Bool {
        !countdown.isPast(at: now) && countdown.targetDate.timeIntervalSince(now) <= window
    }

    static func isRunning(_ id: UUID) -> Bool {
        running(id) != nil
    }

    static func start(_ countdown: Countdown) {
        guard isEnabled, isEligible(countdown), !isRunning(countdown.id) else { return }
        let attributes = CountdownActivityAttributes(countdownID: countdown.id, kind: countdown.kind)
        do {
            _ = try CountdownActivity.request(attributes: attributes, content: content(for: countdown), pushType: nil)
        } catch {
            print("Countdownula: couldn't start Live Activity: \(error)")
        }
    }

    static func end(_ id: UUID) {
        for activity in CountdownActivity.activities where activity.attributes.countdownID == id {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Keeps running activities in step with the store, ends ones whose countdown finished or was deleted,
    /// and auto-starts pinned countdowns that just entered the window (once per target date, so a
    /// swiped-away activity stays away).
    static func sync(with countdowns: [Countdown]) {
        let now = Date()
        let byID = Dictionary(countdowns.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for activity in CountdownActivity.activities where activity.activityState == .active {
            guard let countdown = byID[activity.attributes.countdownID] else {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
                continue
            }
            let content = content(for: countdown)
            if countdown.isPast(at: now) {
                // Leave the finished state on the Lock Screen for a little while.
                Task { await activity.end(content, dismissalPolicy: .after(countdown.targetDate + 15 * 60)) }
            } else if activity.content.state != content.state {
                Task { await activity.update(content) }
            }
        }

        // Activities can only be requested from the foreground; CloudKit imports can land in the background.
        guard UIApplication.shared.applicationState == .active else { return }
        var autoStarted = Set(UserDefaults.standard.stringArray(forKey: autoStartedKey) ?? [])
        for countdown in countdowns where countdown.isPinned && isEligible(countdown, at: now) {
            let key = "\(countdown.id.uuidString)@\(Int(countdown.targetDate.timeIntervalSince1970))"
            guard !autoStarted.contains(key), !isRunning(countdown.id) else { continue }
            autoStarted.insert(key)
            start(countdown)
        }
        // Only keys for countdowns that still exist are worth remembering.
        autoStarted = autoStarted.filter { key in
            byID.keys.contains { key.hasPrefix($0.uuidString) }
        }
        UserDefaults.standard.set(Array(autoStarted), forKey: autoStartedKey)
    }

    private static func running(_ id: UUID) -> CountdownActivity? {
        CountdownActivity.activities.first { $0.attributes.countdownID == id && $0.activityState == .active }
    }

    private static func content(for countdown: Countdown) -> ActivityContent<CountdownActivityAttributes.ContentState> {
        ActivityContent(
            state: .init(title: countdown.title, startDate: countdown.createdAt, targetDate: countdown.targetDate),
            // Past the target the views switch to their "Done" state, even if the app never runs again.
            staleDate: countdown.targetDate
        )
    }
}
