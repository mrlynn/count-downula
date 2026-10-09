import Foundation

/// What a countdown added up to once it reached zero: "Sonoma. 142 days counted." A shared one
/// adds the people from the server: "23 of us · 41 notes in the coffin · Dana guessed closest".
/// The server's half is `server/src/lib/recapText.ts`; the words match.
struct Recap: Codable, Equatable {
    struct Span: Codable, Equatable {
        var days: Int
        var hours: Int
    }

    /// From when it was made to zero. Left out for public crypt entries.
    var counted: Span?
    /// Everyone who counted down: the owner plus members.
    var people: Int
    /// Notes and photos in the coffin, opened at zero.
    var notes: Int
    /// The closest guess or guesses, once a pool settled.
    var closest: [String]

    /// "23 of us · 41 notes in the coffin · Dana guessed closest", or nil for a countdown nobody shared.
    func peopleLine(isPublic: Bool = false) -> String? {
        var parts: [String] = []
        if people > 1 { parts.append(isPublic ? L("\(people) counted down") : L("\(people) of us")) }
        if notes > 0 { parts.append(L("\(notes) notes in the coffin")) }
        if !closest.isEmpty {
            let names = Array(closest.prefix(3)).formatted(.list(type: .and))
            parts.append(L("\(names) guessed closest"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// How long a countdown was counted, from when it was made to zero: ("142 days", "counted").
    /// Nil when it was made at or after its own zero.
    static func counted(_ countdown: Countdown) -> String? {
        let seconds = Int(countdown.targetDate.timeIntervalSince(countdown.createdAt))
        let days = seconds / 86_400, hours = seconds / 3_600
        if days >= 1 { return L("\(days) days") }
        if hours >= 1 { return L("\(hours) hours") }
        return nil
    }
}

extension Countdown {
    /// A date that came and went: the countdowns that get a recap and the Keep Counting offer.
    /// Timers, count-ups and dates that roll on by themselves (birthdays, sunrises) don't.
    func hasReachedZero(at now: Date) -> Bool {
        kind == .event && isPast(at: now) && extras.repetition == nil && extras.auto == nil
    }

    /// Turns a finished countdown into a count-up from its zero: "Days until the wedding" becomes
    /// "Married 1 year". The date stays, so the recap and the coffin still know when zero was.
    mutating func keepCounting(at now: Date = Date()) {
        kind = .countUp
        milestones = MilestonePreset.countUpDefaults()
        extras.keptCountingAt = now
        extras.repetition = nil
        // A count-up never finishes; builds that predate count-ups would otherwise alert again.
        hasNotified = true
    }
}
