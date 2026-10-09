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

    /// Which buttons an alert offers when it's long-pressed. The iPhone registers the actions (see
    /// `NotificationActions`); other devices schedule the same items without them.
    enum Category: String, CaseIterable {
        /// A milestone in the final 8 hours: Put on Lock Screen, Share.
        case soon = "countdown.soon"
        /// Any other milestone: Share.
        case milestone = "countdown.milestone"
        /// A countdown reaching zero: Share the Recap.
        case done = "countdown.done"
        /// A shared countdown reaching zero: Open the Coffin, Share the Recap.
        case doneCoffin = "countdown.done.coffin"
        /// A year on: Share the Recap.
        case anniversary = "countdown.anniversary"
    }

    struct Item: Hashable {
        let identifier: String
        let countdownID: UUID
        let date: Date
        let title: String
        let body: String
        var sound: Sound = .standard
        var category: Category?
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
            if let anniversary = anniversary(for: countdown, now: now) { items.append(anniversary) }
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
                : countdown.details.isEmpty ? "The countdown is complete!" : countdown.details,
            category: completionCategory(for: countdown)
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
            body: speaks ? CountLines.milestone(scheduled, of: countdown) : scheduled.milestone.title,
            category: milestoneCategory(at: scheduled.date, of: countdown)
        )
    }

    /// A year after a countdown reached zero (and every year after), a nudge to look back and
    /// reshare its recap. Tapping it opens the countdown.
    static func anniversary(for countdown: Countdown, now: Date, calendar: Calendar = .current) -> Item? {
        guard countdown.hasReachedZero(at: now) else { return nil }
        for years in 1...50 {
            guard let date = calendar.date(byAdding: .year, value: years, to: countdown.targetDate) else { return nil }
            guard date > now else { continue }
            return Item(
                identifier: "\(countdown.id.uuidString)#anniversary",
                countdownID: countdown.id,
                date: date,
                title: "🦇 \(countdown.title)",
                body: years == 1 ? "A year ago today. Look back, and share how it went." : "\(years) years ago today. Look back, and share how it went.",
                category: .anniversary
            )
        }
        return nil
    }

    /// Zero on a date that comes and goes gets the recap; a shared one with a coffin opens it too.
    /// Timers, birthdays and sunrises roll on, so there's nothing to look back on.
    static func completionCategory(for countdown: Countdown) -> Category? {
        guard countdown.kind == .event, !countdown.extras.repeatsYearly, countdown.extras.auto == nil else { return nil }
        let hasCoffin = countdown.extras.link != nil
            || (countdown.extras.subscription != nil && countdown.extras.subscription?.isPublic != true)
        return hasCoffin ? .doneCoffin : .done
    }

    /// A milestone close enough to zero that the Lock Screen can follow it from there, or any other.
    static func milestoneCategory(at date: Date, of countdown: Countdown) -> Category {
        guard !countdown.countsUp else { return .milestone }
        let lead = countdown.targetDate.timeIntervalSince(date)
        return lead > 0 && lead <= 8 * 3_600 ? .soon : .milestone
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
