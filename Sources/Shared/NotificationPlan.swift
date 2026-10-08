import Foundation

/// Every alert a device should schedule: countdown completions and milestones, soonest first.
/// iOS and watchOS keep at most 64 pending requests per app, so the soonest ones win.
enum NotificationPlan {
    enum Sound: Hashable {
        case standard
        /// A sound file in the app bundle.
        case named(String)
        /// No sound: the final countdown already played up to zero.
        case silent
    }

    struct Item: Hashable {
        let identifier: String
        let countdownID: UUID
        let date: Date
        let title: String
        let body: String
        var sound: Sound = .standard
    }

    /// The Count's final ten seconds, ending on the chime at zero. Ships as an original placeholder
    /// until the voice is recorded; replace the file with the recording under the same name.
    static let finalCountdownSound = "count-final-10.caf"
    static let finalCountdownLead: TimeInterval = 10

    /// `includeFinalCountdown` adds the Count's spoken final ten seconds for countdowns in the Count's voice.
    /// Only the iPhone ships the sound, so only it asks for them.
    static func items(for countdowns: [Countdown], now: Date, limit: Int, includeFinalCountdown: Bool = false) -> [Item] {
        var items: [Item] = []
        for countdown in countdowns {
            if !countdown.countsUp, countdown.targetDate > now {
                var finish = completion(for: countdown)
                if includeFinalCountdown, countdown.extras.voice == .count,
                   countdown.targetDate - finalCountdownLead > now {
                    items.append(finalCountdown(for: countdown))
                    finish.sound = .silent
                }
                items.append(finish)
            }
            for scheduled in countdown.scheduledMilestones where scheduled.date > now {
                items.append(milestone(scheduled, of: countdown))
            }
        }
        return Array(items.sorted { $0.date < $1.date }.prefix(limit))
    }

    static func completion(for countdown: Countdown) -> Item {
        let speaks = countdown.extras.voice == .count
        return Item(
            identifier: countdown.id.uuidString,
            countdownID: countdown.id,
            date: countdown.targetDate,
            title: "\(speaks ? CountLines.emoji : completionEmoji(for: countdown)) \(countdown.title)",
            body: speaks ? CountLines.completion(for: countdown)
                : countdown.details.isEmpty ? "The countdown is complete!" : countdown.details
        )
    }

    static func finalCountdown(for countdown: Countdown) -> Item {
        Item(
            identifier: "\(countdown.id.uuidString)#final",
            countdownID: countdown.id,
            date: countdown.targetDate - finalCountdownLead,
            title: "\(CountLines.emoji) \(countdown.title)",
            body: "Ten seconds. Count with me.",
            sound: .named(finalCountdownSound)
        )
    }

    static func milestone(_ scheduled: ScheduledMilestone, of countdown: Countdown) -> Item {
        let speaks = countdown.extras.voice == .count
        return Item(
            identifier: "\(countdown.id.uuidString)#\(scheduled.milestone.id.uuidString)",
            countdownID: countdown.id,
            date: scheduled.date,
            title: "\(scheduled.milestone.displayEmoji) \(countdown.title)",
            body: speaks ? CountLines.milestone(scheduled, of: countdown) : scheduled.milestone.title
        )
    }

    private static func completionEmoji(for countdown: Countdown) -> String {
        switch countdown.extras.auto?.kind {
        case .sunrise: "🌅"
        case .sunset: "🌇"
        case .fullMoon: "🌕"
        case nil: countdown.kind == .timer ? "⏰" : "🎉"
        }
    }
}
