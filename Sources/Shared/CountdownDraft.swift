import Foundation

/// A countdown read out of something shared to the app: a ticket, an invite, a confirmation email
/// or a screenshot of one. Always confirmed by the person before it becomes a countdown.
struct CountdownDraft: Codable, Hashable {
    var title: String
    var date: Date?
    var place: String?
    var scene: SceneID

    /// The countdown it becomes once confirmed.
    func countdown(now: Date = Date()) -> Countdown {
        var countdown = Countdown(title: title, details: place ?? "", targetDate: date ?? now + 7 * 86_400, createdAt: now)
        countdown.style = CountdownStyle(background: .scene(scene), font: .rounded)
        return countdown
    }
}

/// Reads a draft out of plain text without a language model: the first future date `NSDataDetector`
/// finds, a title from the most telling line, and a scene from what kind of event it looks like.
/// The Share Extension uses Apple's on-device model when the device has one, and this otherwise.
enum DraftExtractor {
    static func draft(from text: String, now: Date = Date()) -> CountdownDraft {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return CountdownDraft(title: title(from: lines), date: date(in: text, now: now),
                              place: place(in: lines), scene: scene(for: text))
    }

    /// The soonest date that hasn't happened yet. Tickets often put the day and the time on separate
    /// lines ("Saturday, December 12" then "Doors 7:00 PM"), so a time on its own is joined to the day
    /// before it rather than read as today. Dates without a time land at 9 am.
    static func date(in text: String, now: Date, calendar: Calendar = .current) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        struct Found { let date: Date; let text: String; let location: Int }
        let found = detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> Found? in
            guard let date = match.date, let r = Range(match.range, in: text) else { return nil }
            return Found(date: date, text: String(text[r]), location: match.range.location)
        }
        let days = found.filter { containsDay($0.text) }
        let times = found.filter { !containsDay($0.text) && containsTime($0.text) }

        var candidates: [Date] = days.map { day in
            if containsTime(day.text) { return day.date }
            // The first time-only mention after this day, if it comes before the next day.
            let nextDay = days.first { $0.location > day.location }?.location ?? Int.max
            if let time = times.first(where: { $0.location > day.location && $0.location < nextDay }) {
                let parts = calendar.dateComponents([.hour, .minute], from: time.date)
                return calendar.date(bySettingHour: parts.hour ?? 9, minute: parts.minute ?? 0, second: 0, of: day.date) ?? day.date
            }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day.date) ?? day.date
        }
        if candidates.isEmpty { candidates = times.map(\.date) }
        return candidates.filter { $0 > now }.min()
    }

    /// Mentions a day, not just a time: a month, a weekday, a numeric date, today or tomorrow.
    private static func containsDay(_ text: String) -> Bool {
        let months = "jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec"
        let weekdays = "mon|tue|wed|thu|fri|sat|sun"
        let pattern = #"\b(\#(months)|\#(weekdays))|\d{1,4}[/.-]\d{1,2}|today|tomorrow|tonight"#
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func containsTime(_ text: String) -> Bool {
        text.range(of: #"\d{1,2}:\d{2}|\d\s?(am|pm|a\.m\.|p\.m\.)|noon|midnight"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Lines that say what the thing is ("Flight to Lisbon", "Taylor Swift | The Eras Tour") beat
    /// the first line, which is often a brand or a greeting.
    static func title(from lines: [String]) -> String {
        let candidates = lines.filter { line in
            line.count >= 3 && line.count <= 60 && !looksLikeNoise(line)
        }
        let keywords = ["flight", "wedding", "birthday", "party", "concert", "tour", "festival", "trip", "vacation",
                        "game", "match", "show", "reservation", "launch", "premiere", "graduation", "conference",
                        "anniversary", "shower", "reunion", "release"]
        let telling = candidates.first { line in keywords.contains { line.lowercased().contains($0) } }
        return String((telling ?? candidates.first ?? "New Countdown").prefix(60))
    }

    private static func looksLikeNoise(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.hasPrefix("http") || lower.contains("@") { return true }
        if ["confirmation", "receipt", "order #", "booking ref", "dear ", "hi ", "hello", "subject:", "from:", "to:"]
            .contains(where: { lower.hasPrefix($0) }) { return true }
        // Mostly digits and punctuation: dates, codes, prices.
        let letters = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return letters < line.count / 2
    }

    /// The first line that reads like a venue or address.
    static func place(in lines: [String]) -> String? {
        let markers = ["venue:", "location:", "where:", "address:", "at "]
        for line in lines {
            let lower = line.lowercased()
            if let marker = markers.first(where: { lower.hasPrefix($0) }) {
                let value = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return String(value.prefix(80)) }
            }
        }
        return nil
    }

    /// A scene that fits the occasion.
    static func scene(for text: String) -> SceneID {
        let lower = text.lowercased()
        let rules: [([String], SceneID)] = [
            (["halloween", "haunted"], .harvestMoon),
            (["wedding", "engagement", "bridal"], .wedding),
            (["anniversary", "valentine", "date night"], .hearts),
            (["baby", "due date", "gender reveal"], .baby),
            (["birthday", "bday"], .birthday),
            (["graduation", "commencement"], .graduation),
            (["new year", "fireworks", "fourth of july", "july 4"], .fireworks),
            (["party", "celebration"], .confetti),
            (["flight", "airline", "boarding", "airport"], .airplane),
            (["beach", "cruise", "resort", "island"], .beach),
            (["game", "match", "kickoff", "stadium", "tip-off", "playoff"], .stadium),
            (["camping", "campfire", "cabin"], .campfire),
            (["ski", "snow", "christmas", "holiday"], .snowfall),
            (["hike", "national park", "trail"], .mountains),
            (["concert", "tour", "festival", "show", "theater", "theatre", "conference", "city"], .city),
            (["eclipse", "meteor", "star", "launch"], .starfield),
            (["lake", "sail", "ocean", "surf"], .ocean),
        ]
        for (words, scene) in rules where words.contains(where: { lower.contains($0) }) {
            return scene
        }
        return .midnight
    }
}

/// Drafts confirmed in the Share Extension, waiting in the App Group for the app to add them.
/// Extensions can't open their app, so the countdown appears the next time the app comes forward.
enum DraftHandoff {
    private static let key = "DraftHandoff.pending"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: SharedConfig.appGroup) }

    static func add(_ draft: CountdownDraft) {
        guard let defaults else { return }
        var drafts = pending
        drafts.append(draft)
        defaults.set(try? JSONEncoder().encode(drafts), forKey: key)
    }

    static var pending: [CountdownDraft] {
        guard let data = defaults?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CountdownDraft].self, from: data)) ?? []
    }

    static func setPending(_ drafts: [CountdownDraft]) {
        defaults?.set(drafts.isEmpty ? nil : try? JSONEncoder().encode(drafts), forKey: key)
    }

    private static let askedKey = "DraftHandoff.askedToUnlock"

    /// Whether `waiting` drafts held back by the free limit are worth asking about: only when more
    /// arrived since the last ask, so the paywall doesn't come back every time the app comes forward.
    static func shouldAskToUnlock(waiting: Int) -> Bool {
        let asked = defaults?.integer(forKey: askedKey) ?? 0
        defaults?.set(waiting, forKey: askedKey)
        return waiting > asked
    }
}
