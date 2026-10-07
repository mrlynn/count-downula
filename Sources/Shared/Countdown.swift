import Foundation

/// Value-type view of a countdown, shared by the Mac app, the watch app and the complications.
/// Persistence lives in `CountdownRecord`; photos are loaded separately so this stays cheap to copy.
struct Countdown: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case event   // counts down to a calendar date
        case timer   // counts down a duration from when it was created
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

    func isPast(at now: Date) -> Bool { targetDate <= now }

    /// Fraction of the time from creation to target that has elapsed (0...1).
    func progress(at now: Date) -> Double {
        let total = targetDate.timeIntervalSince(createdAt)
        guard total > 0 else { return 1 }
        return min(max(now.timeIntervalSince(createdAt) / total, 0), 1)
    }

    /// Key that changes whenever the photo may have changed; use it to invalidate image caches.
    var imageCacheKey: String { "\(id.uuidString)-\(updatedAt.timeIntervalSinceReferenceDate)" }
}

extension Array where Element == Countdown {
    /// The countdown complications and other glanceable surfaces show by default:
    /// the soonest pinned upcoming countdown, else the soonest upcoming one.
    func featured(at now: Date) -> Countdown? {
        let upcoming = filter { !$0.isPast(at: now) }.sorted { $0.targetDate < $1.targetDate }
        return upcoming.first(where: \.isPinned) ?? upcoming.first
    }
}

struct TimeParts {
    let days: Int
    let hours: Int
    let minutes: Int
    let seconds: Int
    let isPast: Bool

    init(from now: Date, to target: Date) {
        let interval = target.timeIntervalSince(now)
        isPast = interval <= 0
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
    /// Short form for the menu bar: "12d 4h", "3h 05m", "04:59".
    static func compact(from now: Date, to target: Date) -> String {
        let p = TimeParts(from: now, to: target)
        if p.isPast { return "Done" }
        if p.days > 0 { return "\(p.days)d \(p.hours)h" }
        if p.hours > 0 { return String(format: "%dh %02dm", p.hours, p.minutes) }
        return String(format: "%02d:%02d", p.minutes, p.seconds)
    }

    /// Readable form for list rows: "12 days, 4 hrs" / "3 hrs, 5 min" / "2 days ago".
    static func relative(from now: Date, to target: Date) -> String {
        let p = TimeParts(from: now, to: target)
        let body: String
        if p.days > 0 {
            body = "\(p.days) \(p.days == 1 ? "day" : "days"), \(p.hours) \(p.hours == 1 ? "hr" : "hrs")"
        } else if p.hours > 0 {
            body = "\(p.hours) \(p.hours == 1 ? "hr" : "hrs"), \(p.minutes) min"
        } else {
            body = String(format: "%d:%02d", p.minutes, p.seconds)
        }
        return p.isPast ? "\(body) ago" : body
    }
}
