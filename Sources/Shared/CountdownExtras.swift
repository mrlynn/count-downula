import Foundation

/// Optional extras, synced together as one JSON blob: streak history and savings for count-ups,
/// yearly repeat for dates like birthdays, sunrise and full moon dates, and the notification voice.
struct CountdownExtras: Codable, Hashable {
    /// Earlier runs of a count-up, kept when it's reset.
    var streak = StreakHistory()
    /// Money not spent, for "smoke-free" style count-ups.
    var savings: Savings?
    /// Birthdays and anniversaries roll over to next year once the day has passed.
    var repeatsYearly = false
    /// The original date of a yearly countdown, so Feb 29 comes back in leap years.
    var yearlyAnchor: Date?
    /// Set once the countdown is published as a live link. Synced, so every device shows the link;
    /// only devices holding the owner token (iCloud Keychain) can edit or unpublish it.
    var link: PublishedLink?
    /// Set when this is someone else's shared countdown you joined. The owner's edits arrive
    /// through it; your pin, alerts and voice stay yours.
    var subscription: SharedSubscription?
    /// How alerts read: plainly, or in Count Downcula's voice.
    var voice: NotificationVoice = .standard
    /// Set on the built-in sunrise, sunset and full moon countdowns, which roll on to the next one.
    var auto: AutoDate?

    init() {}

    private enum CodingKeys: String, CodingKey { case streak, savings, repeatsYearly, yearlyAnchor, link, subscription, voice, auto }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streak = (try? c.decodeIfPresent(StreakHistory.self, forKey: .streak)) ?? StreakHistory()
        savings = try? c.decodeIfPresent(Savings.self, forKey: .savings)
        repeatsYearly = (try? c.decodeIfPresent(Bool.self, forKey: .repeatsYearly)) ?? false
        yearlyAnchor = try? c.decodeIfPresent(Date.self, forKey: .yearlyAnchor)
        link = try? c.decodeIfPresent(PublishedLink.self, forKey: .link)
        subscription = try? c.decodeIfPresent(SharedSubscription.self, forKey: .subscription)
        voice = (try? c.decodeIfPresent(NotificationVoice.self, forKey: .voice)) ?? .standard
        auto = try? c.decodeIfPresent(AutoDate.self, forKey: .auto)
    }
}

enum NotificationVoice: String, Codable, Hashable {
    case standard
    /// Milestone and finish alerts written in the Count's voice. See `CountLines`.
    case count
}

/// A date the countdown works out for itself and moves on to once it passes.
struct AutoDate: Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case sunrise, sunset, fullMoon

        var name: String {
            switch self {
            case .sunrise: "Sunrise"
            case .sunset: "Sunset"
            case .fullMoon: "Full Moon"
            }
        }

        var symbolName: String {
            switch self {
            case .sunrise: "sunrise"
            case .sunset: "sunset"
            case .fullMoon: "moon.circle"
            }
        }
    }

    var kind: Kind
    /// Where the sun is watched from, rounded to a tenth of a degree (about 11 km): close enough for
    /// the sun to the minute, and no more precise than a town. Not needed for the moon.
    var latitude: Double?
    var longitude: Double?

    init(kind: Kind, latitude: Double? = nil, longitude: Double? = nil) {
        self.kind = kind
        self.latitude = latitude.map { ($0 * 10).rounded() / 10 }
        self.longitude = longitude.map { ($0 * 10).rounded() / 10 }
    }

    var needsLocation: Bool { kind != .fullMoon }

    /// The first occurrence after `date`, or nil for a sun countdown with no location.
    func next(after date: Date) -> Date? {
        switch kind {
        case .fullMoon:
            return Astronomy.nextFullMoon(after: date)
        case .sunrise, .sunset:
            guard let latitude, let longitude else { return nil }
            return Astronomy.nextSunEvent(kind == .sunrise ? .rise : .set, after: date,
                                          latitude: latitude, longitude: longitude)
        }
    }

    /// How long one stays "done" before moving on, so its alert and confetti get their moment.
    var gracePeriod: TimeInterval { kind == .fullMoon ? 6 * 3_600 : 15 * 60 }
}

/// Someone else's countdown you're counting down with.
struct SharedSubscription: Codable, Hashable {
    var slug: String
    var url: URL
    var joinedAt: Date
    /// The owner's last edit you've applied, so a refresh only rewrites the countdown when it changed.
    var remoteUpdatedAt: Date?
    /// How many people are counting down, as of the last refresh.
    var memberCount: Int?
    /// A public crypt countdown (no coffin; anyone can join).
    var isPublic: Bool?
}

/// A countdown's public page on the Count Downcula server.
struct PublishedLink: Codable, Hashable {
    var slug: String
    var url: URL
    var publishedAt: Date
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

// MARK: - Sunrise, sunset and full moon

extension Countdown {
    /// The next sunrise, sunset or full moon once this one has passed (plus its grace period).
    func nextAutoOccurrence(after now: Date) -> Date? {
        guard let auto = extras.auto, kind == .event, targetDate + auto.gracePeriod <= now else { return nil }
        return auto.next(after: now)
    }

    /// The date a repeating countdown is about to move on to, if it's due to.
    func nextOccurrence(after now: Date, calendar: Calendar = .current) -> Date? {
        nextYearlyOccurrence(after: now, calendar: calendar) ?? nextAutoOccurrence(after: now)
    }

    /// Moves a passed yearly or sunrise-style countdown on to its next date. Returns true if it moved.
    mutating func rollForward(at now: Date, calendar: Calendar = .current) -> Bool {
        if rollToNextYear(at: now, calendar: calendar) { return true }
        guard let next = nextAutoOccurrence(after: now) else { return false }
        createdAt = max(targetDate, now - 86_400)
        targetDate = next
        hasNotified = false
        for index in milestones.indices { milestones[index].celebratedAt = nil }
        return true
    }
}
