import Foundation

/// Optional extras, synced together as one JSON blob: streak history and savings for count-ups,
/// yearly repeat for dates like birthdays, sunrise and full moon dates, and the notification voice.
struct CountdownExtras: Codable, Hashable {
    /// Earlier runs of a count-up, kept when it's reset.
    var streak = StreakHistory()
    /// Money not spent, for "smoke-free" style count-ups.
    var savings: Savings?
    /// Birthdays and anniversaries roll over to next year once the day has passed. Still written for
    /// yearly repeats so builds that predate `repeatRule` keep rolling them; read `repetition` instead.
    var repeatsYearly = false
    /// How a date repeats: weekly, monthly, every N days, weekdays or yearly. Builds that predate it
    /// drop it when they edit the countdown, which leaves a one-off (or a yearly one, via `repeatsYearly`).
    var repeatRule: Repetition?
    /// The original date of a repeating countdown, so Feb 29 and the 31st come back when they exist.
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
    /// A date pool: friends guess when it happens. Set by the owner; members get it with the copy.
    var pool: DatePool?
    /// When a finished countdown became a count-up from its zero (Keep Counting). Members get it
    /// from the owner's copy, so it marks a count-up that still has a recap and a coffin.
    var keptCountingAt: Date?
    /// The calendar event it was imported from (its external identifier), so a later version can
    /// offer to update it from Calendar.
    var calendarEventID: String?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case streak, savings, repeatsYearly, yearlyAnchor, link, subscription, voice, auto, pool, keptCountingAt
        case repeatRule = "repeat"
        case calendarEventID = "calendarEvent"
    }

    /// How this date repeats, if it does. Setting it keeps `repeatsYearly` in step for older builds.
    var repetition: Repetition? {
        get { repeatRule ?? (repeatsYearly ? .yearly : nil) }
        set {
            repeatRule = newValue
            repeatsYearly = newValue == .yearly
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streak = (try? c.decodeIfPresent(StreakHistory.self, forKey: .streak)) ?? StreakHistory()
        savings = try? c.decodeIfPresent(Savings.self, forKey: .savings)
        repeatsYearly = (try? c.decodeIfPresent(Bool.self, forKey: .repeatsYearly)) ?? false
        repeatRule = try? c.decodeIfPresent(Repetition.self, forKey: .repeatRule)
        yearlyAnchor = try? c.decodeIfPresent(Date.self, forKey: .yearlyAnchor)
        link = try? c.decodeIfPresent(PublishedLink.self, forKey: .link)
        subscription = try? c.decodeIfPresent(SharedSubscription.self, forKey: .subscription)
        voice = (try? c.decodeIfPresent(NotificationVoice.self, forKey: .voice)) ?? .standard
        auto = try? c.decodeIfPresent(AutoDate.self, forKey: .auto)
        pool = try? c.decodeIfPresent(DatePool.self, forKey: .pool)
        keptCountingAt = try? c.decodeIfPresent(Date.self, forKey: .keptCountingAt)
        calendarEventID = try? c.decodeIfPresent(String.self, forKey: .calendarEventID)
    }
}

/// How a countdown's date comes around again.
enum Repetition: Codable, Hashable {
    case weekly
    case monthly
    case yearly
    /// Monday to Friday, at the countdown's time.
    case weekdays
    /// Every so many days: 1 for daily, 14 for a fortnight.
    case everyDays(Int)

    /// "Every week", "Every 3 days".
    var label: String {
        switch self {
        case .weekly: L("Every week")
        case .monthly: L("Every month")
        case .yearly: L("Every year")
        case .weekdays: L("Every weekday")
        case let .everyDays(n): n == 1 ? L("Every day") : L("Every \(n) days")
        }
    }

    /// How long a passed date stays "done" before moving on, so its alert and confetti get their
    /// moment. Shorter for dates that come around often.
    var gracePeriod: TimeInterval {
        switch self {
        case .yearly, .monthly: 86_400
        case .weekly: 6 * 3_600
        case let .everyDays(n): n >= 3 ? 6 * 3_600 : 3_600
        case .weekdays: 3_600
        }
    }

    /// The `index`th date after `anchor` (index 1 is the first repeat), or nil for weekdays, which
    /// don't step evenly.
    func step(_ index: Int, from anchor: Date, calendar: Calendar) -> Date? {
        switch self {
        case .weekly: calendar.date(byAdding: .day, value: 7 * index, to: anchor)
        case .monthly: calendar.date(byAdding: .month, value: index, to: anchor)
        case .yearly: calendar.date(byAdding: .year, value: index, to: anchor)
        case let .everyDays(n): calendar.date(byAdding: .day, value: max(1, n) * index, to: anchor)
        case .weekdays: nil
        }
    }
}

/// A date pool on a countdown: friends guess when it happens, and when the owner sets the real
/// date, the closest guess wins. Bragging rights only. The countdown's own date is the owner's
/// estimate until then.
struct DatePool: Codable, Hashable {
    /// No more guesses.
    var closed = false
    /// The real date, once the owner sets it. The countdown's target becomes this too.
    var answer: Date?

    var isSettled: Bool { answer != nil }
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
    /// This member stays at zero when the owner keeps counting up from it.
    var staysFinished: Bool?
    /// The owner bought a Host Pass for it: bigger coffin notes, custom link.
    var isHosted: Bool?
}

/// A countdown's public page on the Count Downcula server.
struct PublishedLink: Codable, Hashable {
    var slug: String
    /// The link to share: the random one, or the custom one once a host sets it.
    var url: URL
    var publishedAt: Date
    /// A Host Pass is applied to it.
    var isHosted: Bool?
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
    /// Milestones become celebratable again. A joined count-up is the owner's to reset.
    mutating func resetStreak(at date: Date) {
        guard countsUp, extras.subscription == nil, date > targetDate else { return }
        extras.streak.runs.append(.init(start: targetDate, end: date))
        targetDate = date
        for index in milestones.indices { milestones[index].celebratedAt = nil }
    }
}

// MARK: - Yearly repeat

extension Countdown {
    /// A yearly date stays "done" for a day so its notification and confetti get their moment.
    static let yearlyGracePeriod: TimeInterval = 86_400

    /// The next occurrence once this one has passed (plus its grace period), or nil if nothing to do.
    func nextRepeatOccurrence(after now: Date, calendar: Calendar = .current) -> Date? {
        guard let rule = extras.repetition, kind == .event, targetDate + rule.gracePeriod <= now else { return nil }
        if rule == .weekdays {
            // Day by day from this one, skipping Saturdays and Sundays.
            var next = targetDate
            for _ in 0..<20_000 {
                guard let day = calendar.date(byAdding: .day, value: 1, to: next) else { return nil }
                next = day
                if !calendar.isDateInWeekend(next), next + rule.gracePeriod > now { return next }
            }
            return nil
        }
        // Counting from the anchor (not the last occurrence) keeps Feb 29 and the 31st when they exist.
        let anchor = extras.yearlyAnchor ?? targetDate
        for index in 1..<20_000 {
            guard let next = rule.step(index, from: anchor, calendar: calendar) else { return nil }
            if next + rule.gracePeriod > now { return next }
        }
        return nil
    }

    /// The next yearly occurrence, for callers that only deal in yearly dates.
    func nextYearlyOccurrence(after now: Date, calendar: Calendar = .current) -> Date? {
        extras.repetition == .yearly ? nextRepeatOccurrence(after: now, calendar: calendar) : nil
    }

    /// Moves a past repeating countdown to its next occurrence. The wait since the last one becomes
    /// the new progress range, and the alert and milestone celebrations are armed again.
    mutating func rollToNextYear(at now: Date, calendar: Calendar = .current) -> Bool {
        guard let next = nextRepeatOccurrence(after: now, calendar: calendar) else { return false }
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
        nextRepeatOccurrence(after: now, calendar: calendar) ?? nextAutoOccurrence(after: now)
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
