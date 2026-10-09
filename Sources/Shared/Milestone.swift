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

    /// A count-up's kind of milestone ("30 days"), meaningless on a countdown.
    var isElapsedTrigger: Bool {
        if case .elapsed = trigger { return true }
        return false
    }

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
    /// A count-up's `targetDate` is its start.
    var startDate: Date { countsUp ? targetDate : createdAt }

    /// Milestones that fall inside the countdown, soonest first. One that resolves before the
    /// countdown began or after it ends (say "100 days to go" on a 30-day countdown) is left out.
    var scheduledMilestones: [ScheduledMilestone] {
        milestones
            .map { ScheduledMilestone(milestone: $0, date: $0.date(for: self)) }
            .filter { $0.date > startDate && (countsUp || $0.date < targetDate) }
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
        case .halfway: Milestone(title: L("Halfway there"), emoji: "🌓", trigger: .fraction(0.5))
        case .hundredDays: Milestone(title: L("100 days to go"), emoji: "💯", trigger: .remaining(100 * 86_400))
        case .thirtyDays: Milestone(title: L("30 days to go"), emoji: "🗓️", trigger: .remaining(30 * 86_400))
        case .oneWeek: Milestone(title: L("1 week to go"), emoji: "✨", trigger: .remaining(7 * 86_400))
        case .oneDay: Milestone(title: L("Tomorrow!"), emoji: "🥳", trigger: .remaining(86_400))
        case .oneHour: Milestone(title: L("1 hour to go"), emoji: "⏳", trigger: .remaining(3_600))
        }
    }

    /// The chips a count-up starts with: the first day, week and month, then the long haul.
    static func countUpDefaults() -> [Milestone] {
        let day: TimeInterval = 86_400
        var milestones = [
            Milestone(title: L("24 hours"), emoji: "🌱", trigger: .elapsed(day)),
            Milestone(title: L("1 week"), emoji: "✨", trigger: .elapsed(7 * day)),
            Milestone(title: L("30 days"), emoji: "🗓️", trigger: .elapsed(30 * day)),
            Milestone(title: L("60 days"), emoji: "💪", trigger: .elapsed(60 * day)),
            Milestone(title: L("90 days"), emoji: "🏅", trigger: .elapsed(90 * day)),
            Milestone(title: L("6 months"), emoji: "🌟", trigger: .elapsed(182 * day)),
            Milestone(title: L("1 year"), emoji: "🏆", trigger: .elapsed(365 * day)),
        ]
        for year in 2...10 {
            milestones.append(Milestone(title: L("\(year) years"), emoji: "🏆", trigger: .elapsed(Double(year) * 365 * day)))
        }
        return milestones
    }

    /// Presets that would land between now and the target.
    static func available(for countdown: Countdown, now: Date) -> [MilestonePreset] {
        guard !countdown.countsUp else { return [] }
        return allCases.filter { preset in
            let date = preset.milestone.date(for: countdown)
            return date > now && date < countdown.targetDate
                && !countdown.milestones.contains { $0.trigger == preset.milestone.trigger }
        }
    }
}
