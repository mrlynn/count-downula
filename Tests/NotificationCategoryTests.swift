import XCTest

final class NotificationCategoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour: TimeInterval = 3_600

    private func event(inHours hours: Double) -> Countdown {
        Countdown(title: "Launch", details: "", targetDate: now + hours * hour, createdAt: now - 24 * hour)
    }

    func testMilestonesInTheFinalHoursOfferTheLockScreen() {
        let launch = event(inHours: 48)
        XCTAssertEqual(NotificationPlan.milestoneCategory(at: launch.targetDate - hour, of: launch), .soon)
        XCTAssertEqual(NotificationPlan.milestoneCategory(at: launch.targetDate - 8 * hour, of: launch), .soon)
        XCTAssertEqual(NotificationPlan.milestoneCategory(at: launch.targetDate - 9 * hour, of: launch), .milestone)
        let sober = Countdown(title: "Sober", details: "", targetDate: now, kind: .countUp, createdAt: now)
        XCTAssertEqual(NotificationPlan.milestoneCategory(at: now + 7 * 24 * hour, of: sober), .milestone,
                       "Count-ups never reach zero, so no Lock Screen offer")
    }

    func testZeroOffersTheRecapAndForSharedOnesTheCoffin() {
        var launch = event(inHours: 2)
        XCTAssertEqual(NotificationPlan.completion(for: launch).category, .done)
        launch.extras.link = PublishedLink(slug: "k7Pq2mXa", url: URL(string: "https://go.countdowncula.com/c/k7Pq2mXa")!, publishedAt: now)
        XCTAssertEqual(NotificationPlan.completion(for: launch).category, .doneCoffin)

        var joined = event(inHours: 2)
        joined.extras.subscription = SharedSubscription(slug: "k7Pq2mXa", url: URL(string: "https://go.countdowncula.com/c/k7Pq2mXa")!, joinedAt: now)
        XCTAssertEqual(NotificationPlan.completion(for: joined).category, .doneCoffin)
        joined.extras.subscription?.isPublic = true
        XCTAssertEqual(NotificationPlan.completion(for: joined).category, .done, "Public crypt entries have no coffin")
    }

    func testThingsThatRollOnHaveNothingToLookBackOn() {
        let timer = Countdown(title: "Tea", details: "", targetDate: now + 300, kind: .timer, createdAt: now)
        XCTAssertNil(NotificationPlan.completion(for: timer).category)
        var birthday = event(inHours: 2)
        birthday.extras.repeatsYearly = true
        XCTAssertNil(NotificationPlan.completion(for: birthday).category)
        var sunrise = event(inHours: 2)
        sunrise.extras.auto = AutoDate(kind: .sunrise)
        XCTAssertNil(NotificationPlan.completion(for: sunrise).category)
    }

    func testThePlanCarriesTheCategories() {
        var launch = event(inHours: 48)
        launch.milestones = [MilestonePreset.oneHour.milestone, MilestonePreset.oneDay.milestone]
        let items = NotificationPlan.items(for: [launch], now: now, limit: 60)
        XCTAssertEqual(items.map(\.category), [.milestone, .soon, .done])
    }
}
