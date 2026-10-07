import Foundation

/// A moment along the way worth celebrating: "Halfway there", "1 week to go".
/// Relative triggers follow the countdown when its date is edited.
struct Milestone: Codable, Hashable, Identifiable {
    enum Trigger: Codable, Hashable {
        /// A fixed moment.
        case date(Date)
        /// This long before the target ("1 week to go").
        case remaining(TimeInterval)
        /// This fraction of the way from the start to the target ("Halfway there").
        case fraction(Double)
        /// This long after the start ("30 days").
        case elapsed(TimeInterval)
    }

    var id = UUID()
    var title: String
    var emoji: String?
    var trigger: Trigger
    /// When the in-app celebration played. Synced, so it plays once across devices.
    var celebratedAt: Date?

    func date(for countdown: Countdown) -> Date {
        switch trigger {
        case let .date(date):
            date
        case let .remaining(interval):
            countdown.targetDate - interval
        case let .fraction(fraction):
            countdown.startDate + countdown.targetDate.timeIntervalSince(countdown.startDate) * fraction
        case let .elapsed(interval):
            countdown.startDate + interval
        }
    }

    var displayEmoji: String { emoji?.isEmpty == false ? emoji! : "🎉" }
}

/// A milestone resolved against its countdown.
struct ScheduledMilestone: Identifiable, Hashable {
    let milestone: Milestone
    let date: Date

    var id: UUID { milestone.id }
}

extension Countdown {
    /// When the wait began: progress, "Halfway" and elapsed milestones count from here.
    var startDate: Date { createdAt }

    /// Milestones that fall inside the countdown, soonest first. One that resolves before the
    /// countdown began or after it ends (say "100 days to go" on a 30-day countdown) is left out.
    var scheduledMilestones: [ScheduledMilestone] {
        milestones
            .map { ScheduledMilestone(milestone: $0, date: $0.date(for: self)) }
            .filter { $0.date > startDate && $0.date < targetDate }
            .sorted { $0.date < $1.date }
    }

    func nextMilestone(at now: Date) -> ScheduledMilestone? {
        scheduledMilestones.first { $0.date > now }
    }

    /// Milestones reached in the last week whose celebration hasn't played yet. Older ones are
    /// skipped so a fresh install doesn't throw a party for something from months ago.
    func uncelebratedMilestones(at now: Date) -> [ScheduledMilestone] {
        scheduledMilestones.filter {
            $0.milestone.celebratedAt == nil && $0.date <= now && $0.date > now - 7 * 86_400
        }
    }

    /// Clears the celebrated flag on milestones that moved back into the future (the date was edited).
    mutating func resetMilestonesInFuture(at now: Date) {
        for index in milestones.indices where milestones[index].celebratedAt != nil {
            if milestones[index].date(for: self) > now { milestones[index].celebratedAt = nil }
        }
    }
}

// MARK: - Presets

enum MilestonePreset: CaseIterable, Identifiable {
    case halfway, hundredDays, thirtyDays, oneWeek, oneDay, oneHour

    var id: Self { self }

    var milestone: Milestone {
        switch self {
        case .halfway: Milestone(title: "Halfway there", emoji: "🌓", trigger: .fraction(0.5))
        case .hundredDays: Milestone(title: "100 days to go", emoji: "💯", trigger: .remaining(100 * 86_400))
        case .thirtyDays: Milestone(title: "30 days to go", emoji: "🗓️", trigger: .remaining(30 * 86_400))
        case .oneWeek: Milestone(title: "1 week to go", emoji: "✨", trigger: .remaining(7 * 86_400))
        case .oneDay: Milestone(title: "Tomorrow!", emoji: "🥳", trigger: .remaining(86_400))
        case .oneHour: Milestone(title: "1 hour to go", emoji: "⏳", trigger: .remaining(3_600))
        }
    }

    /// Presets that would land between now and the target.
    static func available(for countdown: Countdown, now: Date) -> [MilestonePreset] {
        allCases.filter { preset in
            let date = preset.milestone.date(for: countdown)
            return date > now && date < countdown.targetDate
                && !countdown.milestones.contains { $0.trigger == preset.milestone.trigger }
        }
    }
}
