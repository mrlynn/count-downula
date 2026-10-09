import XCTest

final class AfterZeroTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let zero = Date(timeIntervalSince1970: 1_793_404_800)  // 2026-10-31 00:00 UTC

    private func wedding(madeDaysBefore days: Double = 142) -> Countdown {
        Countdown(title: "Wedding", details: "", targetDate: zero, createdAt: zero - days * day)
    }

    private func remote(kind: Countdown.Kind = .countUp, kept: Bool = true, recap: Recap? = nil) -> RemoteCountdown {
        RemoteCountdown(title: "Wedding", details: "", targetDate: zero, createdAt: zero - 142 * day,
                        updatedAt: zero + day, kind: kind, style: .default, milestones: MilestonePreset.countUpDefaults(),
                        hasPhoto: false, memberCount: 22, keptCounting: kept, recap: recap)
    }

    private func member(of countdown: Countdown, staysFinished: Bool? = nil) -> Countdown {
        var copy = countdown
        copy.extras.subscription = SharedSubscription(slug: "k7Pq2mXa", url: URL(string: "https://go.countdowncula.com/c/k7Pq2mXa")!,
                                                      joinedAt: zero - day, staysFinished: staysFinished)
        return copy
    }

    func testOnlyDatesThatCameAndWentGetARecap() {
        XCTAssertTrue(wedding().hasReachedZero(at: zero + 1))
        XCTAssertFalse(wedding().hasReachedZero(at: zero - 1))
        var birthday = wedding()
        birthday.extras.repeatsYearly = true
        XCTAssertFalse(birthday.hasReachedZero(at: zero + 1), "Rolls on to next year instead")
        let timer = Countdown(title: "Tea", details: "", targetDate: zero, kind: .timer, createdAt: zero - 300)
        XCTAssertFalse(timer.hasReachedZero(at: zero + 1))
    }

    func testTheCardSaysHowLongItWasCounted() {
        XCTAssertEqual(Recap.counted(wedding()), "142 days")
        XCTAssertEqual(Recap.counted(wedding(madeDaysBefore: 1)), "1 day")
        XCTAssertEqual(Recap.counted(wedding(madeDaysBefore: 5.0 / 24)), "5 hours")
        XCTAssertNil(Recap.counted(wedding(madeDaysBefore: 0)))
    }

    func testThePeopleLineMatchesTheServer() {
        let recap = Recap(counted: .init(days: 142, hours: 3_408), people: 23, notes: 41, closest: ["Dana"])
        XCTAssertEqual(recap.peopleLine(), "23 of us · 41 notes in the coffin · Dana guessed closest")
        XCTAssertEqual(Recap(people: 1_204, notes: 0, closest: ["Ana", "Ben", "Cy"]).peopleLine(isPublic: true),
                       "1,204 counted down · \(["Ana", "Ben", "Cy"].formatted(.list(type: .and))) guessed closest",
                       "Names are joined the way the person's language joins them")
        XCTAssertNil(Recap(people: 1, notes: 0, closest: []).peopleLine(), "Nobody else counted")
    }

    func testKeepCountingCountsUpFromZero() {
        var countdown = wedding()
        countdown.extras.repeatsYearly = true
        countdown.keepCounting(at: zero + day)
        XCTAssertEqual(countdown.kind, .countUp)
        XCTAssertEqual(countdown.targetDate, zero, "Counts up from the day it happened")
        XCTAssertEqual(countdown.extras.keptCountingAt, zero + day)
        XCTAssertFalse(countdown.extras.repeatsYearly)
        XCTAssertTrue(countdown.milestones.contains { $0.title == "1 year" })
        XCTAssertEqual(Recap.counted(countdown), "142 days", "The recap still knows the wait")
    }

    func testMembersFollowTheOwnerUpFromZero() {
        let copy = SharedCountdowns.apply(remote(), to: member(of: wedding()))
        XCTAssertEqual(copy.kind, .countUp)
        XCTAssertNotNil(copy.extras.keptCountingAt)
    }

    func testAMemberCanStayAtZero() {
        let copy = SharedCountdowns.apply(remote(), to: member(of: wedding(), staysFinished: true))
        XCTAssertEqual(copy.kind, .event)
        XCTAssertNotNil(copy.extras.keptCountingAt, "Still marked, so the switch stays on screen")
        XCTAssertFalse(copy.milestones.contains { $0.isElapsedTrigger }, "No count-up milestones on a countdown")
        let back = SharedCountdowns.apply(remote(kind: .event, kept: false), to: copy)
        XCTAssertNil(back.extras.keptCountingAt, "The owner turned it back")
    }

    func testTheServerRecapDecodes() throws {
        let json = """
        {"url":"https://go.countdowncula.com/c/k7Pq2mXa","memberCount":22,
         "recap":{"counted":{"days":142,"hours":3408},"people":23,"notes":41,"closest":["Dana"]},
         "countdown":{"title":"Wedding","details":"","targetDate":"2026-10-31T00:00:00.000Z","createdAt":"2026-06-11T00:00:00.000Z",
         "updatedAt":"2026-11-01T00:00:00.000Z","kind":"countUp","hasPhoto":false,"keptCounting":true}}
        """
        let remote = try RemoteCountdown.decode(Data(json.utf8))
        XCTAssertTrue(remote.keptCounting)
        XCTAssertEqual(remote.recap, Recap(counted: .init(days: 142, hours: 3_408), people: 23, notes: 41, closest: ["Dana"]))
    }

    func testAnniversariesComeBackEachYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let first = NotificationPlan.anniversary(for: wedding(), now: zero + day, calendar: calendar)
        XCTAssertEqual(first?.date, calendar.date(byAdding: .year, value: 1, to: zero))
        XCTAssertEqual(first?.body, "A year ago today. Look back, and share how it went.")
        let third = NotificationPlan.anniversary(for: wedding(), now: zero + 800 * day, calendar: calendar)
        XCTAssertEqual(third?.date, calendar.date(byAdding: .year, value: 3, to: zero))
        XCTAssertNil(NotificationPlan.anniversary(for: wedding(), now: zero - day, calendar: calendar), "Not before zero")
        var kept = wedding()
        kept.keepCounting(at: zero + day)
        XCTAssertNil(NotificationPlan.anniversary(for: kept, now: zero + day, calendar: calendar), "Its yearly milestones do that")
    }

    func testDeletionsSayWhenTheyHappened() {
        XCTAssertEqual(Analytics.deletionSource(for: wedding(), at: zero - day), "before_zero")
        XCTAssertEqual(Analytics.deletionSource(for: wedding(), at: zero + 10 * day), "after_zero_30d")
        XCTAssertEqual(Analytics.deletionSource(for: wedding(), at: zero + 40 * day), "after_zero_later")
        let countUp = Countdown(title: "Sober", details: "", targetDate: zero, kind: .countUp, createdAt: zero)
        XCTAssertEqual(Analytics.deletionSource(for: countUp, at: zero + day), "count_up")
    }
}
