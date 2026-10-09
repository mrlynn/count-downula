import Foundation

/// Value-type view of a countdown, shared by the Mac app, the watch app and the complications.
/// Persistence lives in `CountdownRecord`; photos are loaded separately so this stays cheap to copy.
struct Countdown: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case event   // counts down to a calendar date
        case timer   // counts down a duration from when it was created
        case countUp // counts up from `targetDate`: time since quitting, getting sober, meeting
    }

    var id = UUID()
    var title: String
    var details: String
    var targetDate: Date
    var kind: Kind = .event
    var isPinned = false
    var createdAt = Date()
    var updatedAt = Date()
    var hasNotified = false
    var hasImage = false
    var style = CountdownStyle.default
    var milestones: [Milestone] = []
    var extras = CountdownExtras()

    var countsUp: Bool { kind == .countUp }

    /// A count-up is never "done".
    func isPast(at now: Date) -> Bool { !countsUp && targetDate <= now }

    /// Still counting down: neither finished nor a count-up.
    func isUpcoming(at now: Date) -> Bool { !countsUp && targetDate > now }

    /// Fraction of the wait that has elapsed (0...1). For a count-up, the way to its next milestone.
    func progress(at now: Date) -> Double {
        if countsUp {
            let reached = scheduledMilestones.last { $0.date <= now }?.date ?? startDate
            guard let next = nextMilestone(at: now)?.date else { return 1 }
            let total = next.timeIntervalSince(reached)
            return total > 0 ? min(max(now.timeIntervalSince(reached) / total, 0), 1) : 1
        }
        let total = targetDate.timeIntervalSince(createdAt)
        guard total > 0 else { return 1 }
        return min(max(now.timeIntervalSince(createdAt) / total, 0), 1)
    }

    /// How full the fang dial is drawn: draining toward the target, or for a count-up,
    /// filling toward the next milestone.
    func dialRemaining(at now: Date) -> Double {
        if countsUp { return progress(at: now) }
        return isPast(at: now) ? 0 : 1 - progress(at: now)
    }

    /// Days / hours / minutes / seconds left, or elapsed for a count-up.
    func timeParts(at now: Date) -> TimeParts {
        TimeParts(from: now, to: targetDate, countsUp: countsUp)
    }

    /// Key that changes whenever the photo may have changed; use it to invalidate image caches.
    var imageCacheKey: String { "\(id.uuidString)-\(updatedAt.timeIntervalSinceReferenceDate)" }
}

extension Countdown {
    private enum CodingKeys: String, CodingKey {
        case id, title, details, targetDate, kind, isPinned, createdAt, updatedAt, hasNotified, hasImage, style, milestones, extras
    }

    /// Fields added after 1.1 are optional in the JSON, so snapshots written by an older build still decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        details = try c.decode(String.self, forKey: .details)
        targetDate = try c.decode(Date.self, forKey: .targetDate)
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .event
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        hasNotified = try c.decodeIfPresent(Bool.self, forKey: .hasNotified) ?? false
        hasImage = try c.decodeIfPresent(Bool.self, forKey: .hasImage) ?? false
        // A style written by a newer build may not decode here; fall back rather than drop the countdown.
        style = (try? c.decodeIfPresent(CountdownStyle.self, forKey: .style)) ?? .default
        milestones = (try? c.decodeIfPresent([Milestone].self, forKey: .milestones)) ?? []
        extras = (try? c.decodeIfPresent(CountdownExtras.self, forKey: .extras)) ?? CountdownExtras()
    }
}

extension Array where Element == Countdown {
    /// The countdown complications and other glanceable surfaces show by default: the soonest
    /// pinned upcoming countdown, else a pinned count-up, else the soonest upcoming one.
    func featured(at now: Date) -> Countdown? {
        let upcoming = filter { $0.isUpcoming(at: now) }.sorted { $0.targetDate < $1.targetDate }
        return upcoming.first(where: \.isPinned)
            ?? first { $0.countsUp && $0.isPinned }
            ?? upcoming.first
    }

    /// What a Next Up widget steps through with its cycle button: the featured one first, then the
    /// rest of what's coming, soonest first. `offset` counts presses and wraps around.
    func featured(at now: Date, offset: Int) -> Countdown? {
        guard let first = featured(at: now) else { return nil }
        let rest = filter { $0.isUpcoming(at: now) && $0.id != first.id }.sorted { $0.targetDate < $1.targetDate }
        let order = [first] + rest
        return order[((offset % order.count) + order.count) % order.count]
    }
}

struct TimeParts {
    let days: Int
    let hours: Int
    let minutes: Int
    let seconds: Int
    let isPast: Bool
    /// Elapsed time since `target` rather than time left until it.
    let countsUp: Bool

    init(from now: Date, to target: Date, countsUp: Bool = false) {
        let interval = target.timeIntervalSince(now)
        self.countsUp = countsUp
        isPast = !countsUp && interval <= 0
        var remaining = Int(abs(interval).rounded(.down))
        days = remaining / 86_400
        remaining %= 86_400
        hours = remaining / 3_600
        remaining %= 3_600
        minutes = remaining / 60
        seconds = remaining % 60
    }
}

enum CountdownFormat {
    /// `compact` for a countdown, or the time since a count-up began: "2y 3mo", "47d 3h", "3h 05m", "04:59".
    static func compact(_ countdown: Countdown, at now: Date) -> String {
        guard countdown.countsUp else { return compact(from: now, to: countdown.targetDate) }
        let p = countdown.timeParts(at: now)
        if p.days >= 365 { return years(between: countdown.targetDate, and: now) }
        if p.days > 0 { return L("\(p.days)d \(p.hours)h") }
        if p.hours > 0 { return L("\(p.hours)h \(String(format: "%02d", p.minutes))m") }
        return String(format: "%02d:%02d", p.minutes, p.seconds)
    }

    /// "47 days", "1 year, 3 months", "5 hours" since a count-up began, by the calendar.
    static func elapsed(since start: Date, to now: Date, calendar: Calendar = .current) -> String {
        guard now > start else { return L("Just started") }
        let c = calendar.dateComponents([.year, .month, .day, .hour], from: start, to: now)
        if let y = c.year, y > 0 {
            let years = L("\(y) years")
            guard let m = c.month, m > 0 else { return years }
            let months = L("\(m) months")
            return L("\(years), \(months)")
        }
        let days = calendar.dateComponents([.day], from: start, to: now).day ?? 0
        if days > 0 { return L("\(days) days") }
        return L("\(c.hour ?? 0) hours")
    }

    /// Short form for the menu bar: "1y 2mo", "12d 4h", "3h 05m", "04:59".
    static func compact(from now: Date, to target: Date) -> String {
        let p = TimeParts(from: now, to: target)
        if p.isPast { return L("Done") }
        if p.days >= 365 { return years(between: now, and: target) }
        if p.days > 0 { return L("\(p.days)d \(p.hours)h") }
        if p.hours > 0 { return L("\(p.hours)h \(String(format: "%02d", p.minutes))m") }
        return String(format: "%02d:%02d", p.minutes, p.seconds)
    }

    /// Spans of a year or more, by the calendar: "12y 8mo", "1y". Day counts that long
    /// ("4,652d 23h") are too wide for rows and widgets and hard to read anyway.
    static func years(between start: Date, and end: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: min(start, end), to: max(start, end))
        let years = c.year ?? 0, months = c.month ?? 0
        return months > 0 ? L("\(years)y \(months)mo") : L("\(years)y")
    }

    /// Readable form for list rows: "12 days, 4 hrs" / "3 hrs, 5 min" / "2 days ago".
    static func relative(from now: Date, to target: Date) -> String {
        let p = TimeParts(from: now, to: target)
        let body: String
        if p.days > 0 {
            let days = L("\(p.days) days"), hours = L("\(p.hours) hrs")
            body = L("\(days), \(hours)")
        } else if p.hours > 0 {
            let hours = L("\(p.hours) hrs"), minutes = L("\(p.minutes) min")
            body = L("\(hours), \(minutes)")
        } else {
            body = String(format: "%d:%02d", p.minutes, p.seconds)
        }
        return p.isPast ? L("\(body) ago") : body
    }
}
