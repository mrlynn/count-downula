import XCTest

final class CountUnitTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US")
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, in zone: String? = nil) -> Date {
        var c = calendar
        if let zone { c.timeZone = TimeZone(identifier: zone)! }
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func countdown(_ unit: CountUnit, to target: Date, kind: Countdown.Kind = .event, from created: Date? = nil) -> Countdown {
        var c = Countdown(title: "Trip", details: "", targetDate: target, kind: kind, createdAt: created ?? target - 100 * 86_400)
        c.extras.unit = unit
        return c
    }

    // MARK: - Sleeps

    func testChristmasEveMorningIsOneSleep() {
        XCTAssertEqual(UnitCount.sleeps(from: date(2026, 12, 24, 10), to: date(2026, 12, 25), bedtime: 0, calendar: calendar), 1)
        XCTAssertEqual(UnitCount.sleeps(from: date(2026, 12, 24, 10), to: date(2026, 12, 25, 7), bedtime: 0, calendar: calendar), 1)
        XCTAssertEqual(UnitCount.sleeps(from: date(2026, 12, 20, 10), to: date(2026, 12, 25), bedtime: 0, calendar: calendar), 5)
    }

    func testABedtimeEndsTheDaysSleepEarly() {
        let eight = 20 * 60
        XCTAssertEqual(UnitCount.sleeps(from: date(2026, 12, 24, 19), to: date(2026, 12, 25, 7), bedtime: eight, calendar: calendar), 1)
        XCTAssertEqual(UnitCount.sleeps(from: date(2026, 12, 24, 21), to: date(2026, 12, 25, 7), bedtime: eight, calendar: calendar), 0,
                       "Already in bed: no sleeps left")
        XCTAssertEqual(UnitCount.sleeps(from: date(2026, 12, 25, 7), to: date(2026, 12, 25, 6), bedtime: 0, calendar: calendar), 0)
    }

    // MARK: - Workdays and weekends (Friday, October 9, 2026)

    func testWorkdaysCountTodayAndSkipWeekends() {
        let friday = date(2026, 10, 9, 9)
        XCTAssertEqual(UnitCount.workdays(from: friday, to: date(2026, 10, 19), calendar: calendar), 6)
        XCTAssertEqual(UnitCount.workdays(from: friday, to: date(2026, 10, 12, 9), calendar: calendar), 1, "Just today")
        XCTAssertEqual(UnitCount.workdays(from: friday, to: date(2026, 10, 9, 17), calendar: calendar), 0, "The day itself")
        XCTAssertEqual(UnitCount.workdays(from: friday, to: date(2027, 10, 8), calendar: calendar), 260, "A year without walking it")
    }

    func testWeekendsIncludeTheOneUnderWay() {
        XCTAssertEqual(UnitCount.weekends(from: date(2026, 10, 9, 9), to: date(2026, 10, 19), calendar: calendar), 2)
        XCTAssertEqual(UnitCount.weekends(from: date(2026, 10, 10, 9), to: date(2026, 10, 12), calendar: calendar), 1, "Saturday")
        XCTAssertEqual(UnitCount.weekends(from: date(2026, 10, 11, 9), to: date(2026, 10, 19), calendar: calendar), 2, "Sunday")
        XCTAssertEqual(UnitCount.weekends(from: date(2026, 10, 12, 9), to: date(2026, 10, 16), calendar: calendar), 0)
    }

    // MARK: - Readings

    func testWeeksReadAsWeeksAndDaysUntilTheLastWeek() {
        let now = date(2026, 10, 9, 9)
        let reading = countdown(.weeks, to: now + 47 * 86_400 + 3_600).reading(at: now, calendar: calendar)
        XCTAssertEqual(reading?.compact, "6w 5d")
        XCTAssertEqual(reading?.tiles.map(\.value), ["6", "5"])
        XCTAssertNil(countdown(.weeks, to: now + 6 * 86_400).reading(at: now, calendar: calendar))
    }

    func testPercentRoundsDownSoItNeverSaysDoneEarly() {
        let now = date(2026, 10, 9, 9)
        let c = countdown(.percent, to: now + 1, from: now - 99_999)
        XCTAssertEqual(c.reading(at: now, calendar: calendar)?.tiles.first?.value,
                       (0.99).formatted(.percent.precision(.fractionLength(0))))
    }

    func testAUnitThatDoesntFitFallsBackToDaysAndHours() {
        let now = date(2026, 10, 9, 9)
        let since = countdown(.sleeps, to: now - 30 * 86_400, kind: .countUp)
        XCTAssertEqual(since.countUnit, .daysHours)
        XCTAssertNil(since.reading(at: now, calendar: calendar))
        XCTAssertNil(countdown(.sleeps, to: now - 60).reading(at: now, calendar: calendar), "Done")
        XCTAssertEqual(countdown(.sleeps, to: date(2026, 10, 12, 9)).reading(at: now, calendar: calendar)?.compact, "3 sleeps")
    }

    // MARK: - Time zones

    func testATimeZoneKeepsTheClockTimeAsTyped() {
        let typed = date(2026, 10, 30, 18, 40)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(typed.sameClockTime(from: calendar.timeZone, to: tokyo), date(2026, 10, 30, 18, 40, in: "Asia/Tokyo"))
    }

    func testRepeatsKeepTheirTimeInTheirOwnZone() {
        // New York leaves daylight saving on November 1; a 9am Tokyo meeting stays 9am in Tokyo.
        let first = date(2026, 10, 30, 9, in: "Asia/Tokyo")
        var c = Countdown(title: "Standup", details: "", targetDate: first, createdAt: first - 86_400)
        c.extras.repetition = .weekly
        c.extras.timeZone = "Asia/Tokyo"
        XCTAssertTrue(c.rollToNextYear(at: first + 7 * 3_600))
        XCTAssertEqual(c.targetDate, date(2026, 11, 6, 9, in: "Asia/Tokyo"))
    }

    func testOlderJSONStillDecodesAndNewFieldsRoundTrip() throws {
        let old = try JSONDecoder().decode(CountdownExtras.self, from: Data(#"{"voice":"count"}"#.utf8))
        XCTAssertNil(old.unit)
        XCTAssertNil(old.timeZone)

        var extras = CountdownExtras()
        extras.unit = .sleeps
        extras.bedtime = 1_200
        extras.timeZone = "Asia/Tokyo"
        let back = try JSONDecoder().decode(CountdownExtras.self, from: JSONEncoder().encode(extras))
        XCTAssertEqual(back, extras)

        let future = try JSONDecoder().decode(CountdownExtras.self, from: Data(#"{"unit":"fortnights"}"#.utf8))
        XCTAssertNil(future.unit, "A unit from a newer build reads as days and hours")
    }
}
