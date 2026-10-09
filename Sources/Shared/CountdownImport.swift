import Foundation

/// Countdowns made from what people already have: calendar events and their contacts' birthdays.
/// The pickers live with each app; this turns what they hand back into countdowns, the same way on
/// every device.
enum CountdownImport {
    /// How far ahead the calendar picker looks.
    static let calendarWindow: TimeInterval = 90 * 86_400

    /// A countdown to a calendar event, with a scene that fits its title and place. `repetition` is
    /// the event's own repeat, when it maps onto one of ours.
    static func event(title: String, start: Date, location: String?, repetition: Repetition?,
                      eventID: String?, now: Date = Date()) -> Countdown {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var countdown = Countdown(title: name.isEmpty ? L("Untitled Event") : String(name.prefix(120)),
                                  details: String(place.prefix(1_000)), targetDate: start, createdAt: now)
        countdown.style = CountdownStyle(background: .scene(DraftExtractor.scene(for: "\(name) \(place)")), font: .rounded)
        countdown.extras.repetition = repetition
        countdown.extras.calendarEventID = eventID
        return countdown
    }

    /// A yearly countdown to someone's birthday, at the start of the day. Without a birth year it
    /// counts from 2000, a leap year, so a Feb 29 birthday lands on Feb 28 in other years.
    static func birthday(name: String, month: Int, day: Int, year: Int?, now: Date = Date(),
                         calendar: Calendar = .current) -> Countdown? {
        guard let anchor = calendar.date(from: DateComponents(year: year ?? 2000, month: month, day: day)),
              calendar.component(.month, from: anchor) == month else { return nil }
        let today = calendar.startOfDay(for: now)
        var next = anchor
        for years in 0..<200 {
            guard let date = calendar.date(byAdding: .year, value: years, to: anchor) else { return nil }
            next = date
            if date >= today { break }
        }
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var countdown = Countdown(title: who.isEmpty ? L("Birthday") : L("\(who)\u{2019}s Birthday"), details: "",
                                  targetDate: next, createdAt: now)
        countdown.style = CountdownStyle(background: .scene(.birthday), font: .rounded)
        countdown.extras.repetition = .yearly
        countdown.extras.yearlyAnchor = anchor
        return countdown
    }

    /// How many more active countdowns fit in the free tier, or nil when there's no limit.
    static func room(in countdowns: [Countdown], unlocked: Bool, at now: Date = Date()) -> Int? {
        unlocked ? nil : max(0, SharedConfig.freeActiveLimit - Entitlements.activeCount(in: countdowns, at: now))
    }

    /// Splits picked countdowns into the ones that fit now and the ones held back for Unlimited,
    /// soonest first so the dates closest at hand make it in.
    static func split(_ picked: [Countdown], room: Int?) -> (fits: [Countdown], heldBack: [Countdown]) {
        let soonest = picked.sorted { $0.targetDate < $1.targetDate }
        guard let room else { return (soonest, []) }
        return (Array(soonest.prefix(room)), Array(soonest.dropFirst(room)))
    }
}
