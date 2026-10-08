import XCTest

final class CountUpTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func countUp(daysAgo: Double) -> Countdown {
        Countdown(title: "Smoke-Free", details: "", targetDate: now - daysAgo * day, kind: .countUp, createdAt: now)
    }

    func testCountUpIsNeverPastOrUpcoming() {
        let c = countUp(daysAgo: 47)
        XCTAssertFalse(c.isPast(at: now))
        XCTAssertFalse(c.isUpcoming(at: now))
        let parts = c.timeParts(at: now)
        XCTAssertEqual(parts.days, 47)
        XCTAssertTrue(parts.countsUp)
        XCTAssertFalse(parts.isPast)
        XCTAssertEqual(CountdownFormat.compact(c, at: now), "47d 0h")
    }

    func testLongSpansShowYearsAndMonths() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: 2014, month: 1, day: 10, hour: 11))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 13))!
        XCTAssertEqual(CountdownFormat.years(between: start, and: end, calendar: calendar), "12y 8mo")
        XCTAssertEqual(CountdownFormat.years(between: end, and: start, calendar: calendar), "12y 8mo")
        let anniversary = calendar.date(from: DateComponents(year: 2015, month: 1, day: 10, hour: 12))!
        XCTAssertEqual(CountdownFormat.years(between: start, and: anniversary, calendar: calendar), "1y")

        // Under a year stays in days; a year or more switches over, counting up or down.
        XCTAssertEqual(CountdownFormat.compact(countUp(daysAgo: 364), at: now), "364d 0h")
        XCTAssertTrue(CountdownFormat.compact(countUp(daysAgo: 4_652), at: now).hasPrefix("12y"))
        XCTAssertTrue(CountdownFormat.compact(from: now, to: now + 400 * day).hasPrefix("1y"))
    }

    func testMilestonesCountFromTheStartAndDriveProgress() {
        var c = countUp(daysAgo: 45)
        c.milestones = MilestonePreset.countUpDefaults()
        XCTAssertEqual(c.nextMilestone(at: now)?.milestone.title, "60 days")
        // 30 days reached, 60 next: halfway between them.
        XCTAssertEqual(c.progress(at: now), 0.5, accuracy: 0.001)
    }

    func testCountUpsSkipCompletionAlerts() {
        var c = countUp(daysAgo: 1)
        c.milestones = [Milestone(title: "1 week", trigger: .elapsed(7 * day))]
        let items = NotificationPlan.items(for: [c], now: now, limit: 60)
        XCTAssertEqual(items.map(\.body), ["1 week"])
    }

    func testFeaturedPrefersPinnedCountdownThenPinnedCountUp() {
        var pinnedUp = countUp(daysAgo: 3)
        pinnedUp.isPinned = true
        let soon = Countdown(title: "Soon", details: "", targetDate: now + day)
        XCTAssertEqual([soon, pinnedUp].featured(at: now)?.title, "Smoke-Free")
        var pinnedSoon = soon
        pinnedSoon.isPinned = true
        XCTAssertEqual([pinnedSoon, pinnedUp].featured(at: now)?.title, "Soon")
    }

    func testResetKeepsHistoryAndBest() {
        var c = countUp(daysAgo: 30)
        c.milestones = [Milestone(title: "1 week", trigger: .elapsed(7 * day), celebratedAt: now)]
        c.resetStreak(at: now)
        XCTAssertEqual(c.targetDate, now)
        XCTAssertEqual(c.extras.streak.runs.count, 1)
        XCTAssertEqual(c.bestStreak(at: now + 2 * day), 30 * day)
        XCTAssertEqual(c.bestStreak(at: now + 40 * day), 40 * day)
        XCTAssertNil(c.milestones[0].celebratedAt)
    }

    func testSavings() {
        let savings = Savings(amountPerDay: 12, currencyCode: "USD")
        XCTAssertEqual(savings.saved(since: now - 10 * day, at: now), 120, accuracy: 0.001)
        XCTAssertEqual(savings.saved(since: now + day, at: now), 0)
    }

    func testYearlyRolloverWaitsADayThenMovesOn() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let birthday = calendar.date(from: DateComponents(year: 2027, month: 3, day: 14, hour: 9))!
        var c = Countdown(title: "Sam", details: "", targetDate: birthday, createdAt: birthday - 30 * day)
        c.extras.repeatsYearly = true
        c.hasNotified = true

        XCTAssertFalse(c.rollToNextYear(at: birthday + 3_600, calendar: calendar))
        XCTAssertTrue(c.rollToNextYear(at: birthday + day + 1, calendar: calendar))
        XCTAssertEqual(c.targetDate, calendar.date(from: DateComponents(year: 2028, month: 3, day: 14, hour: 9)))
        XCTAssertEqual(c.createdAt, birthday)
        XCTAssertFalse(c.hasNotified)
    }

    func testLeapDayComesBackInLeapYears() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let leap = calendar.date(from: DateComponents(year: 2028, month: 2, day: 29))!
        var c = Countdown(title: "Leap", details: "", targetDate: leap, createdAt: leap - day)
        c.extras.repeatsYearly = true

        var seen: [DateComponents] = []
        var clock = leap
        for _ in 0..<4 {
            clock = c.targetDate + 2 * day
            XCTAssertTrue(c.rollToNextYear(at: clock, calendar: calendar))
            seen.append(calendar.dateComponents([.year, .month, .day], from: c.targetDate))
        }
        XCTAssertEqual(seen.map(\.day), [28, 28, 28, 29])
        XCTAssertEqual(seen.last?.year, 2032)
    }

    func testExtrasRoundTripThroughRecord() {
        let record = CountdownRecord()
        var c = countUp(daysAgo: 5)
        c.extras.savings = Savings(amountPerDay: 3.5, currencyCode: "EUR")
        c.extras.streak.runs = [.init(start: now - 20 * day, end: now - 5 * day)]
        record.apply(c)
        XCTAssertEqual(record.countdown.extras, c.extras)
        XCTAssertEqual(record.countdown.kind, .countUp)
    }
}
