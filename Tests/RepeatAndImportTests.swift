import XCTest

final class RepeatAndImportTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func repeating(_ rule: Repetition, at target: Date) -> Countdown {
        var c = Countdown(title: "Payday", details: "", targetDate: target, createdAt: target - 86_400)
        c.extras.repetition = rule
        return c
    }

    func testWeeklyRollsToTheSameTimeNextWeekAfterItsGrace() {
        let friday = date(2026, 10, 9, 17)  // a Friday, 5 pm
        var c = repeating(.weekly, at: friday)
        XCTAssertFalse(c.rollToNextYear(at: friday + 3_600, calendar: calendar), "Still in its 6 hour moment")
        XCTAssertTrue(c.rollToNextYear(at: friday + 7 * 3_600, calendar: calendar))
        XCTAssertEqual(c.targetDate, date(2026, 10, 16, 17))
        XCTAssertEqual(c.createdAt, friday, "The week since becomes the progress range")
    }

    func testMonthlyKeepsTheThirtyFirstWhenItExists() {
        var c = repeating(.monthly, at: date(2026, 1, 31, 9))
        XCTAssertTrue(c.rollToNextYear(at: date(2026, 2, 2), calendar: calendar))
        XCTAssertEqual(c.targetDate, date(2026, 2, 28, 9))
        XCTAssertTrue(c.rollToNextYear(at: date(2026, 3, 2), calendar: calendar))
        XCTAssertEqual(c.targetDate, date(2026, 3, 31, 9), "Counted from the anchor, so back to the 31st")
    }

    func testWeekdaysSkipTheWeekend() {
        var c = repeating(.weekdays, at: date(2026, 10, 9, 17))  // Friday
        XCTAssertTrue(c.rollToNextYear(at: date(2026, 10, 9, 19), calendar: calendar))
        XCTAssertEqual(c.targetDate, date(2026, 10, 12, 17), "Monday")
    }

    func testEveryFewDaysCatchesUpAfterAGap() {
        var c = repeating(.everyDays(3), at: date(2026, 10, 1, 8))
        XCTAssertTrue(c.rollToNextYear(at: date(2026, 10, 9, 20), calendar: calendar))
        XCTAssertEqual(c.targetDate, date(2026, 10, 10, 8))
    }

    func testYearlyStillWritesTheOldFlagAndOthersDont() throws {
        var extras = CountdownExtras()
        extras.repetition = .yearly
        XCTAssertTrue(extras.repeatsYearly, "Older builds keep rolling birthdays")
        extras.repetition = .weekly
        XCTAssertFalse(extras.repeatsYearly)
        let decoded = try JSONDecoder().decode(CountdownExtras.self, from: JSONEncoder().encode(extras))
        XCTAssertEqual(decoded.repetition, .weekly)
        let old = try JSONDecoder().decode(CountdownExtras.self, from: Data(#"{"repeatsYearly":true}"#.utf8))
        XCTAssertEqual(old.repetition, .yearly, "What older builds wrote still reads as yearly")
    }

    func testRepeatingDatesNeverReachZero() {
        let c = repeating(.monthly, at: date(2026, 10, 1))
        XCTAssertFalse(c.hasReachedZero(at: date(2026, 10, 1, 1)))
        XCTAssertNil(NotificationPlan.completionCategory(for: c))
    }

    func testCalendarEventsBecomeStyledCountdowns() {
        let c = CountdownImport.event(title: "  Maya's Wedding ", start: date(2026, 11, 21, 16), location: "Sonoma",
                                      repetition: nil, eventID: "ABC-123", now: date(2026, 10, 9))
        XCTAssertEqual(c.title, "Maya's Wedding")
        XCTAssertEqual(c.details, "Sonoma")
        XCTAssertEqual(c.style.background, .scene(.wedding))
        XCTAssertEqual(c.extras.calendarEventID, "ABC-123")
        XCTAssertEqual(CountdownImport.event(title: "", start: .now, location: nil, repetition: .weekly, eventID: nil).title, "Untitled Event")
    }

    func testBirthdaysCountToTheNextOneAndRepeat() throws {
        let now = date(2026, 10, 9, 12)
        let sam = try XCTUnwrap(CountdownImport.birthday(name: "Sam", month: 3, day: 14, year: 1990, now: now, calendar: calendar))
        XCTAssertEqual(sam.title, "Sam\u{2019}s Birthday")
        XCTAssertEqual(sam.targetDate, date(2027, 3, 14))
        XCTAssertEqual(sam.extras.repetition, .yearly)
        let today = try XCTUnwrap(CountdownImport.birthday(name: "Ana", month: 10, day: 9, year: nil, now: now, calendar: calendar))
        XCTAssertEqual(today.targetDate, date(2026, 10, 9), "Today's birthday is today")
        let leap = try XCTUnwrap(CountdownImport.birthday(name: "Leo", month: 2, day: 29, year: nil, now: now, calendar: calendar))
        XCTAssertEqual(leap.targetDate, date(2027, 2, 28), "Feb 28 in a common year")
        XCTAssertNil(CountdownImport.birthday(name: "X", month: 2, day: 30, year: nil, now: now, calendar: calendar))
    }

    func testImportsFillTheFreeTierSoonestFirst() {
        let now = date(2026, 10, 9)
        let existing = [Countdown(title: "Trip", details: "", targetDate: now + 86_400)]
        XCTAssertEqual(CountdownImport.room(in: existing, unlocked: false, at: now), SharedConfig.freeActiveLimit - 1)
        XCTAssertNil(CountdownImport.room(in: existing, unlocked: true, at: now))
        let picked = [9, 2, 5, 1].map { Countdown(title: "In \($0)", details: "", targetDate: now + Double($0) * 86_400) }
        let (fits, heldBack) = CountdownImport.split(picked, room: 2)
        XCTAssertEqual(fits.map(\.title), ["In 1", "In 2"])
        XCTAssertEqual(heldBack.map(\.title), ["In 5", "In 9"])
        XCTAssertEqual(CountdownImport.split(picked, room: nil).heldBack.count, 0)
    }
}
