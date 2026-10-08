import Foundation

/// Every alert a device should schedule: countdown completions and milestones, soonest first.
/// iOS and watchOS keep at most 64 pending requests per app, so the soonest ones win.
enum NotificationPlan {
    struct Item: Hashable {
        let identifier: String
        let countdownID: UUID
        let date: Date
        let title: String
        let body: String
    }

    static func items(for countdowns: [Countdown], now: Date, limit: Int) -> [Item] {
        var items: [Item] = []
        for countdown in countdowns {
            if !countdown.countsUp, countdown.targetDate > now {
                items.append(completion(for: countdown))
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
