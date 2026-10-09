import Foundation

/// What a countdown counts in: days and hours (the default), weeks, sleeps, workdays, weekends,
/// or how far along the wait is. Stored in extras; a build that predates it shows days and hours.
enum CountUnit: String, Codable, CaseIterable, Identifiable {
    case daysHours
    case weeks
    case sleeps
    case workdays
    case weekends
    case percent

    var id: String { rawValue }

    var name: String {
        switch self {
        case .daysHours: L("Days and hours")
        case .weeks: L("Weeks")
        case .sleeps: L("Sleeps")
        case .workdays: L("Workdays")
        case .weekends: L("Weekends")
        case .percent: L("Percent")
        }
    }

    /// Sleeps, workdays and weekends are about a day still to come; weeks read as well counting up;
    /// percent needs a start and an end.
    func fits(_ kind: Countdown.Kind) -> Bool {
        switch self {
        case .daysHours: true
        case .weeks: kind != .timer
        case .sleeps, .workdays, .weekends: kind == .event
        case .percent: kind != .countUp
        }
    }

    static func available(for kind: Countdown.Kind) -> [CountUnit] { allCases.filter { $0.fits(kind) } }
}

/// A countdown read in its unit: "12 sleeps", "6w 5d", "82%".
struct UnitReading: Hashable {
    struct Tile: Hashable {
        let value: String
        let label: String
    }

    /// Menu bar, rows, widgets: "12 sleeps", "6w 5d".
    let compact: String
    /// Detail view, share card, Siri: "12 sleeps", "6 weeks, 5 days", "82% of the way there".
    let long: String
    /// The big readout: one or two tiles in place of days, hours, minutes and seconds.
    let tiles: [Tile]
}

extension Countdown {
    /// The unit it's shown in, falling back to days and hours where the chosen one doesn't fit.
    var countUnit: CountUnit {
        guard let unit = extras.unit, unit.fits(kind) else { return .daysHours }
        return unit
    }

    /// The countdown in its unit, or nil to show days and hours: when that's the unit, once it's
    /// done, and in the final stretch (no sleeps or workdays left, under a week), where the
    /// ticking clock says more.
    func reading(at now: Date, calendar: Calendar = .current) -> UnitReading? {
        let unit = countUnit
        guard unit != .daysHours, !isPast(at: now) else { return nil }
        switch unit {
        case .daysHours:
            return nil
        case .weeks:
            let days = timeParts(at: now).days
            guard days >= 7 else { return nil }
            let w = days / 7, d = days % 7
            let weeks = L("\(w) weeks"), dayText = L("\(d) days")
            return UnitReading(
                compact: d > 0 ? L("\(w)w \(d)d") : L("\(w)w"),
                long: d > 0 ? L("\(weeks), \(dayText)") : weeks,
                tiles: [.init(value: "\(w)", label: L("Weeks")), .init(value: "\(d)", label: L("Days"))]
            )
        case .sleeps:
            let n = UnitCount.sleeps(from: now, to: targetDate, bedtime: extras.bedtime ?? 0, calendar: calendar)
            guard n > 0 else { return nil }
            let text = L("\(n) sleeps")
            return UnitReading(compact: text, long: text, tiles: [.init(value: "\(n)", label: L("Sleeps"))])
        case .workdays:
            let n = UnitCount.workdays(from: now, to: targetDate, calendar: calendar)
            guard n > 0 else { return nil }
            let text = L("\(n) workdays")
            return UnitReading(compact: text, long: text, tiles: [.init(value: "\(n)", label: L("Workdays"))])
        case .weekends:
            let n = UnitCount.weekends(from: now, to: targetDate, calendar: calendar)
            guard n > 0 else { return nil }
            let text = L("\(n) weekends")
            return UnitReading(compact: text, long: text, tiles: [.init(value: "\(n)", label: L("Weekends"))])
        case .percent:
            // Rounded down, so it never reads 100% before zero.
            let fraction = (progress(at: now) * 100).rounded(.down) / 100
            let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
            return UnitReading(compact: percent, long: L("\(percent) of the way there"),
                               tiles: [.init(value: percent, label: L("There"))])
        }
    }
}

/// Counting days on the calendar, in the viewer's own time zone: you sleep and work where you are.
enum UnitCount {
    /// Bedtimes from now until the target: a sleep at each `bedtime` (minutes after midnight; 0 is
    /// midnight) after now and no later than the target. Christmas Eve morning is one sleep from
    /// Christmas; after bedtime that night, none.
    static func sleeps(from now: Date, to target: Date, bedtime: Int, calendar: Calendar) -> Int {
        guard target > now else { return 0 }
        let days = dayCount(from: now, to: target, calendar: calendar)
        var count = days + 1
        if minutes(of: now, calendar: calendar) >= bedtime { count -= 1 }
        if minutes(of: target, calendar: calendar) < bedtime { count -= 1 }
        return max(0, count)
    }

    /// Weekdays from today up to the day before the target: today counts, the day itself doesn't.
    /// Weekends follow the region's calendar. Public holidays come later.
    static func workdays(from now: Date, to target: Date, calendar: Calendar) -> Int {
        guard target > now else { return 0 }
        let today = calendar.startOfDay(for: now)
        return count(dayCount(from: now, to: target, calendar: calendar)) { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return false }
            return !calendar.isDateInWeekend(day)
        }
    }

    /// Weekends from now until the target day, this one included if it's under way.
    static func weekends(from now: Date, to target: Date, calendar: Calendar) -> Int {
        guard target > now else { return 0 }
        let today = calendar.startOfDay(for: now)
        let isWeekend = { (offset: Int) -> Bool in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return false }
            return calendar.isDateInWeekend(day)
        }
        // A weekend is a run of weekend days; count the days that start one, and today if it's in one.
        let days = dayCount(from: now, to: target, calendar: calendar)
        let starts = count(days) { isWeekend($0) && !isWeekend($0 - 1) }
        let underWay = days > 0 && isWeekend(0) && isWeekend(-1) ? 1 : 0
        return starts + underWay
    }

    /// Calendar days from now's day to the target's day.
    static func dayCount(from now: Date, to target: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: target)).day ?? 0
    }

    private static func minutes(of date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Offsets in 0..<n that match a test that repeats every week, without walking years of days.
    private static func count(_ n: Int, where matches: (Int) -> Bool) -> Int {
        guard n > 0 else { return 0 }
        let perWeek = (0..<7).filter(matches).count
        let tail = (n / 7 * 7..<n).filter(matches).count
        return n / 7 * perWeek + tail
    }
}

// MARK: - Time zones

extension Countdown {
    /// The zone its date is set in: the one chosen for it ("landing in Tokyo"), else this device's.
    var timeZone: TimeZone {
        extras.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    /// Set to a zone that reads differently from here at its date: show both times.
    var foreignTimeZone: TimeZone? {
        guard let id = extras.timeZone, let zone = TimeZone(identifier: id) else { return nil }
        let here = TimeZone.current
        return zone.secondsFromGMT(for: targetDate) == here.secondsFromGMT(for: targetDate) ? nil : zone
    }

    /// The calendar its date repeats on, so a 9am Tokyo meeting stays 9am in Tokyo.
    var eventCalendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar
    }
}

extension TimeZone {
    /// "Tokyo", from "Asia/Tokyo"; "GMT+9" if there's no city.
    var cityName: String {
        guard let city = identifier.split(separator: "/").last, identifier.contains("/") else {
            return localizedName(for: .shortGeneric, locale: .current) ?? identifier
        }
        return city.replacingOccurrences(of: "_", with: " ")
    }
}

extension Countdown {
    /// A date set in another zone, read there: "Nov 1, 2026 at 6:40 PM in Tokyo", shown under the
    /// date as read here. Nil when its zone reads the same as this device's.
    func timeThere(locale: Locale = .current) -> String? {
        guard let zone = foreignTimeZone else { return nil }
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale)
        style.timeZone = zone
        let there = targetDate.formatted(style)
        return L("\(there) in \(zone.cityName)")
    }
}
