import XCTest

final class MilestoneTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func countdown(startDaysAgo: Double = 10, endsInDays: Double = 10) -> Countdown {
        Countdown(title: "Trip", details: "", targetDate: now + endsInDays * day, createdAt: now - startDaysAgo * day)
    }

    func testTriggerDates() {
        let c = countdown()
        XCTAssertEqual(Milestone(title: "", trigger: .date(now)).date(for: c), now)
        XCTAssertEqual(Milestone(title: "", trigger: .remaining(day)).date(for: c), c.targetDate - day)
        XCTAssertEqual(Milestone(title: "", trigger: .fraction(0.5)).date(for: c), now)
        XCTAssertEqual(Milestone(title: "", trigger: .elapsed(2 * day)).date(for: c), c.createdAt + 2 * day)
    }

    func testMilestonesOutsideTheCountdownAreHidden() {
        var c = countdown(startDaysAgo: 1, endsInDays: 20)
        c.milestones = [MilestonePreset.hundredDays.milestone, MilestonePreset.oneWeek.milestone]
        XCTAssertEqual(c.scheduledMilestones.map(\.milestone.title), ["1 week to go"])
    }

    func testNextAndUncelebrated() {
        var c = countdown()
        let reached = Milestone(title: "Booked", trigger: .date(now - day))
        let ancient = Milestone(title: "Ages ago", trigger: .elapsed(1))
        let upcoming = MilestonePreset.oneWeek.milestone
        c.createdAt = now - 30 * day
        c.milestones = [upcoming, reached, ancient]
        XCTAssertEqual(c.nextMilestone(at: now)?.milestone.title, "1 week to go")
        XCTAssertEqual(c.uncelebratedMilestones(at: now).map(\.milestone.title), ["Booked"])

        c.milestones[1].celebratedAt = now
        XCTAssertTrue(c.uncelebratedMilestones(at: now).isEmpty)
    }

    func testMovingTheDateResetsCelebrations() {
        var c = countdown()
        var milestone = MilestonePreset.halfway.milestone
        milestone.celebratedAt = now
        c.milestones = [milestone]
        c.targetDate = now + 100 * day  // halfway is now in the future
        c.resetMilestonesInFuture(at: now)
        XCTAssertNil(c.milestones[0].celebratedAt)
    }

    func testPresetsOnlyOfferWhatFits() {
        let c = countdown(startDaysAgo: 1, endsInDays: 3)
        let presets = MilestonePreset.available(for: c, now: now)
        XCTAssertTrue(presets.contains(.halfway))
        XCTAssertTrue(presets.contains(.oneDay))
        XCTAssertFalse(presets.contains(.oneWeek))
        XCTAssertFalse(presets.contains(.hundredDays))
    }

    func testNotificationPlanMergesSortsAndCaps() {
        var a = countdown(endsInDays: 5)
        a.milestones = [MilestonePreset.oneDay.milestone, MilestonePreset.halfway.milestone]
        let b = Countdown(title: "Soon", details: "", targetDate: now + 3_600, createdAt: now - day)
        let past = Countdown(title: "Old", details: "", targetDate: now - day, createdAt: now - 9 * day)

        let items = NotificationPlan.items(for: [a, b, past], now: now, limit: 60)
        XCTAssertEqual(items.map(\.title), ["🎉 Soon", "🥳 Trip", "🎉 Trip"])  // halfway already passed
        XCTAssertEqual(items.map(\.date), items.map(\.date).sorted())
        XCTAssertEqual(items[1].identifier, "\(a.id.uuidString)#\(a.milestones[0].id.uuidString)")

        XCTAssertEqual(NotificationPlan.items(for: [a, b], now: now, limit: 2).count, 2)
    }

    func testRecordRoundTripsMilestonesAndKeepsUnreadable() {
        let record = CountdownRecord()
        var c = countdown()
        c.milestones = [MilestonePreset.halfway.milestone]
        record.apply(c)
        XCTAssertEqual(record.countdown.milestones, c.milestones)

        c.milestones = []
        record.apply(c)
        XCTAssertNil(record.milestonesData)

        let future = Data(#"[{"id":"6F1C2A3B-4D5E-4F60-8A7B-9C0D1E2F3A4B","title":"x","trigger":{"weekday":{}}}]"#.utf8)
        record.milestonesData = future
        record.apply(c)
        XCTAssertEqual(record.milestonesData, future)
    }
}
