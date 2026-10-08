import Foundation

/// Alert text in Count Downcula's voice, for countdowns that opt in. Each moment has several lines so
/// the same one doesn't come back every time; the pick is stable for a given countdown and moment,
/// so every device shows the same line and rescheduling doesn't change it.
///
/// The Count is our own character. Keep new lines original: no catchphrases or counting bits
/// borrowed from other vampires.
enum CountLines {
    static let emoji = "🦇"

    static func completion(for countdown: Countdown) -> String {
        let title = countdown.title
        let pool: [String]
        switch countdown.extras.auto?.kind {
        case .sunrise:
            pool = [
                "Sunrise. Into the coffin with you, and draw the lid.",
                "The sun is up. Curtains closed, cape on, see you tonight.",
                "Dawn has come. I'll be in the cellar if anyone needs me.",
            ]
        case .sunset:
            pool = [
                "Sunset. The night is ours again.",
                "The sun has gone. Rise, stretch, and fetch your cape.",
                "Dusk at last. I was getting so tired of daylight.",
            ]
        case .fullMoon:
            pool = [
                "Full moon tonight. Mind the wolves, they never mind you.",
                "The moon is full and the night is bright. Perfect for a long walk.",
                "Full moon. Even the bats are taking photos.",
            ]
        case nil where countdown.kind == .timer:
            pool = [
                "Time's up. The hourglass is empty, and so is my patience.",
                "Done. Every grain of sand accounted for.",
                "The timer has run dry. Back to the land of the living.",
            ]
        case nil:
            pool = isHalloweenWeek(countdown.targetDate) ? [
                "\(title) is here, in the best week of the year.",
                "The bats are out and the wait is over. \(title) has arrived.",
            ] : [
                "The wait is over. \(title) is here, and the night is yours.",
                "At last. I counted every second, and there are none left.",
                "Zero. My favorite number, because of what comes after it.",
                "\(title) has arrived. I have waited centuries for less.",
            ]
        }
        return pick(pool, seed: "\(countdown.id.uuidString)@\(Int(countdown.targetDate.timeIntervalSince1970))")
    }

    static func milestone(_ scheduled: ScheduledMilestone, of countdown: Countdown) -> String {
        let seed = "\(countdown.id.uuidString)#\(scheduled.milestone.id.uuidString)"
        if countdown.countsUp {
            let reached = scheduled.milestone.title
            return pick([
                "\(reached). I counted every night of it, and every one was yours.",
                "\(reached) and still going. The night watch salutes you.",
                "\(reached). Not bad for a mortal. Not bad at all.",
            ], seed: seed)
        }
        if case let .fraction(fraction) = scheduled.milestone.trigger, abs(fraction - 0.5) < 0.001 {
            return pick([
                "Halfway there. Half the wait behind you, half still waiting in the dark.",
                "Halfway to \(countdown.title). The candle is burning down nicely.",
            ], seed: seed)
        }

        let left = timeLeft(countdown.targetDate.timeIntervalSince(scheduled.date))
        let remain = left.isPlural ? "remain" : "remains"
        if isHalloweenWeek(scheduled.date) {
            return pick([
                "\(left.text.capitalizedFirst) \(remain), and the bats are restless.",
                "\(left.text.capitalizedFirst) until \(countdown.title). The pumpkins are watching.",
            ], seed: seed)
        }
        switch left.unit {
        case .nights where left.count >= 14:
            return pick([
                "\(left.text.capitalizedFirst) \(remain) until \(countdown.title). I have waited longer for a good bite.",
                "\(left.text.capitalizedFirst) to go. Time moves slowly in the castle, but it moves.",
                "\(left.text.capitalizedFirst) \(remain). Plenty of time to plan, and plenty of time to dread.",
            ], seed: seed)
        case .nights where left.count > 1:
            return pick([
                "\(left.text.capitalizedFirst) \(remain). The anticipation is... delicious.",
                "Only \(left.text) until \(countdown.title). I can almost taste it.",
                "\(left.text.capitalizedFirst) \(remain). Lay out your finest cape.",
            ], seed: seed)
        case .nights:
            return pick([
                "One more sunset until \(countdown.title).",
                "Tomorrow night. Try to sleep, if you sleep at all.",
            ], seed: seed)
        case .hours, .minutes:
            return pick([
                "\(left.text.capitalizedFirst) to go. I can hear the clock ticking from here.",
                "\(left.text.capitalizedFirst) \(remain). Steady now. Fangs in.",
            ], seed: seed)
        }
    }

    // MARK: - Helpers

    struct TimeLeft {
        enum Unit { case nights, hours, minutes }
        let count: Int
        let unit: Unit

        var isPlural: Bool { count != 1 }

        /// "three nights", "one hour", "45 minutes".
        var text: String {
            let number = count <= 100 ? (Self.words.string(from: count as NSNumber) ?? "\(count)") : "\(count)"
            let name = switch unit {
            case .nights: count == 1 ? "night" : "nights"
            case .hours: count == 1 ? "hour" : "hours"
            case .minutes: count == 1 ? "minute" : "minutes"
            }
            return "\(number) \(name)"
        }

        private static let words: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .spellOut
            formatter.locale = Locale(identifier: "en_US")
            return formatter
        }()
    }

    /// Rounded to the nearest whole unit, switching to a smaller unit below about one of the larger.
    static func timeLeft(_ interval: TimeInterval) -> TimeLeft {
        if interval >= 23 * 3_600 { return TimeLeft(count: Int((interval / 86_400).rounded()), unit: .nights) }
        if interval >= 55 * 60 { return TimeLeft(count: Int((interval / 3_600).rounded()), unit: .hours) }
        return TimeLeft(count: max(1, Int((interval / 60).rounded())), unit: .minutes)
    }

    /// October 25 to 31, when the Halloween lines take over.
    static func isHalloweenWeek(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return parts.month == 10 && (parts.day ?? 0) >= 25
    }

    /// The same line for the same seed on every device and every run (Swift's own hashing is
    /// randomized per launch, so this uses FNV-1a).
    static func pick(_ pool: [String], seed: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return pool[Int(hash % UInt64(pool.count))]
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
