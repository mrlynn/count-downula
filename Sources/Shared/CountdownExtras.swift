import Foundation

/// Optional extras, synced together as one JSON blob: streak history and savings for count-ups,
/// yearly repeat for dates like birthdays.
struct CountdownExtras: Codable, Hashable {
    /// Earlier runs of a count-up, kept when it's reset.
    var streak = StreakHistory()
    /// Money not spent, for "smoke-free" style count-ups.
    var savings: Savings?
    /// Birthdays and anniversaries roll over to next year once the day has passed.
    var repeatsYearly = false
    /// The original date of a yearly countdown, so Feb 29 comes back in leap years.
    var yearlyAnchor: Date?

    init() {}

    private enum CodingKeys: String, CodingKey { case streak, savings, repeatsYearly, yearlyAnchor }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streak = (try? c.decodeIfPresent(StreakHistory.self, forKey: .streak)) ?? StreakHistory()
        savings = try? c.decodeIfPresent(Savings.self, forKey: .savings)
        repeatsYearly = (try? c.decodeIfPresent(Bool.self, forKey: .repeatsYearly)) ?? false
        yearlyAnchor = try? c.decodeIfPresent(Date.self, forKey: .yearlyAnchor)
    }
}

struct StreakHistory: Codable, Hashable {
    struct Run: Codable, Hashable {
        var start: Date
        var end: Date
        var length: TimeInterval { end.timeIntervalSince(start) }
    }

    var runs: [Run] = []
}

struct Savings: Codable, Hashable {
    var amountPerDay: Double
    var currencyCode: String

    func saved(since start: Date, at now: Date) -> Double {
        max(0, now.timeIntervalSince(start)) / 86_400 * amountPerDay
    }

    func formatted(since start: Date, at now: Date) -> String {
        saved(since: start, at: now).formatted(.currency(code: currencyCode).precision(.fractionLength(0)))
    }
}

// MARK: - Streaks

extension Countdown {
    /// The longest run so far, including the one in progress.
    func bestStreak(at now: Date) -> TimeInterval {
        let current = countsUp ? max(0, now.timeIntervalSince(targetDate)) : 0
        return max(current, extras.streak.runs.map(\.length).max() ?? 0)
    }

    /// Starts a count-up over from `date`, keeping the run that just ended in the history.
    /// Milestones become celebratable again.
    mutating func resetStreak(at date: Date) {
        guard countsUp, date > targetDate else { return }
        extras.streak.runs.append(.init(start: targetDate, end: date))
        targetDate = date
        for index in milestones.indices { milestones[index].celebratedAt = nil }
    }
}

// MARK: - Yearly repeat

extension Countdown {
    /// A repeating date stays "done" for a day so its notification and confetti get their moment.
    static let yearlyGracePeriod: TimeInterval = 86_400

    /// The next occurrence once this year's has passed (plus the grace day), or nil if nothing to do.
    func nextYearlyOccurrence(after now: Date, calendar: Calendar = .current) -> Date? {
        guard extras.repeatsYearly, kind == .event, targetDate + Self.yearlyGracePeriod <= now else { return nil }
        let anchor = extras.yearlyAnchor ?? targetDate
        var years = 1
        while years < 500 {
            // Adding years to the anchor (not the last occurrence) keeps Feb 29 on Feb 29 when it exists.
            if let next = calendar.date(byAdding: .year, value: years, to: anchor), next + Self.yearlyGracePeriod > now {
                return next
            }
            years += 1
        }
        return nil
    }

    /// Moves a past yearly countdown to its next occurrence. The year-long wait becomes the new
    /// progress range, and the alert and milestone celebrations are armed again.
    mutating func rollToNextYear(at now: Date, calendar: Calendar = .current) -> Bool {
        guard let next = nextYearlyOccurrence(after: now, calendar: calendar) else { return false }
        if extras.yearlyAnchor == nil { extras.yearlyAnchor = targetDate }
        createdAt = targetDate
        targetDate = next
        hasNotified = false
        for index in milestones.indices { milestones[index].celebratedAt = nil }
        return true
    }
}
