#if os(iOS) || os(macOS)
import EventKit
import SwiftUI

/// An upcoming calendar event, as the import pickers on iPhone and Mac list it.
struct CalendarEventRow: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let isAllDay: Bool
    let location: String?
    let calendarColor: Color
    let repetition: Repetition?
    /// The event's identifier across devices, saved on the countdown so it isn't offered twice.
    let externalID: String?

    var countdown: Countdown {
        CountdownImport.event(title: title, start: start, location: location, repetition: repetition, eventID: externalID)
    }
}

/// Reads the next 90 days of the person's calendars, on the device. Only the countdowns made from
/// picked events sync.
enum CalendarEvents {
    /// Asks for full calendar access, then the upcoming events with each repeating one listed once,
    /// at its next occurrence. Nil when access is refused.
    static func upcoming(now: Date = Date()) async -> [CalendarEventRow]? {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToEvents()) == true else { return nil }
        let predicate = store.predicateForEvents(withStart: now, end: now + CountdownImport.calendarWindow, calendars: nil)
        // A weekly meeting shouldn't fill the list.
        var seen = Set<String>()
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .compactMap { event in
                let key = event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? UUID().uuidString
                guard event.startDate > now, seen.insert(key).inserted else { return nil }
                return CalendarEventRow(id: key, title: event.title ?? L("Untitled Event"), start: event.startDate,
                                        isAllDay: event.isAllDay, location: event.location,
                                        calendarColor: Color(cgColor: event.calendar.cgColor),
                                        repetition: repetition(for: event.recurrenceRules?.first),
                                        externalID: event.calendarItemExternalIdentifier)
            }
    }

    /// The event's own repeat, when it's one we can follow; anything fancier imports as a one-off.
    static func repetition(for rule: EKRecurrenceRule?) -> Repetition? {
        guard let rule else { return nil }
        // "The fourth Thursday of November" or "the last Friday of the month" move around the
        // calendar; ours repeat on the same date, so those come in as one-offs.
        let byWeekday = !(rule.daysOfTheWeek ?? []).isEmpty || !(rule.setPositions ?? []).isEmpty
        if (rule.frequency == .yearly || rule.frequency == .monthly), byWeekday || !(rule.daysOfTheMonth ?? []).isEmpty && rule.daysOfTheMonth!.count > 1 {
            return nil
        }
        switch (rule.frequency, rule.interval) {
        case (.yearly, 1): return .yearly
        case (.monthly, 1): return .monthly
        case (.weekly, 1) where (rule.daysOfTheWeek?.count ?? 0) <= 1: return .weekly
        case (.weekly, 1) where Set(rule.daysOfTheWeek?.map(\.dayOfTheWeek) ?? []) == [.monday, .tuesday, .wednesday, .thursday, .friday]:
            return .weekdays
        case let (.weekly, n) where (rule.daysOfTheWeek?.count ?? 0) <= 1: return .everyDays(7 * n)
        case let (.daily, n): return .everyDays(n)
        default: return nil
        }
    }

    /// The rows grouped under month headings ("October 2026"), in order.
    static func byMonth(_ rows: [CalendarEventRow]) -> [(title: String, rows: [CalendarEventRow])] {
        var groups: [(title: String, rows: [CalendarEventRow])] = []
        for row in rows {
            let title = row.start.formatted(.dateTime.month(.wide).year())
            if groups.last?.title == title { groups[groups.count - 1].rows.append(row) } else { groups.append((title, [row])) }
        }
        return groups
    }
}
#endif
