import XCTest

final class AnalyticsTests: XCTestCase {
    private var suite: UserDefaults!
    private let now = Date(timeIntervalSince1970: 1_791_547_200)  // 2026-10-09 12:00 UTC

    override func setUp() {
        suite = UserDefaults(suiteName: "AnalyticsTests")!
        suite.removePersistentDomain(forName: "AnalyticsTests")
        Analytics.defaults = suite
        Analytics.isSendingPaused = true
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: "AnalyticsTests")
        Analytics.defaults = .standard
        Analytics.isSendingPaused = false
    }

    func testOnUntilTurnedOffAndTurningOffDropsTheQueue() {
        XCTAssertTrue(Analytics.isEnabled)
        Analytics.log(.countdownCreated, source: "typed", at: now)
        XCTAssertEqual(Analytics.pending.count, 1)
        Analytics.setEnabled(false)
        XCTAssertTrue(Analytics.pending.isEmpty)
        Analytics.log(.countdownCreated, at: now)
        XCTAssertTrue(Analytics.pending.isEmpty, "Nothing is kept while it's off")
        XCTAssertNil(Analytics.clientHeader, "Requests don't say which app they're from either")
    }

    func testActiveOncePerDay() {
        Analytics.appBecameActive(at: now)
        Analytics.appBecameActive(at: now + 3_600)
        XCTAssertEqual(Analytics.pending.map(\.name), ["active"])
        Analytics.appBecameActive(at: now + 86_400)
        XCTAssertEqual(Analytics.pending.map(\.name), ["active", "active"])
    }

    func testResetStartsOverAsANewInstall() {
        let first = Analytics.installID
        XCTAssertEqual(Analytics.installID, first, "Stable until reset")
        Analytics.log(.paywallShown, at: now)
        // The Settings app's switch, picked up the next time the app comes forward.
        suite.set(true, forKey: "resetAnalyticsID")
        Analytics.appBecameActive(at: now)
        XCTAssertNotEqual(Analytics.installID, first)
        XCTAssertFalse(suite.bool(forKey: "resetAnalyticsID"))
        XCTAssertEqual(Analytics.pending.map(\.name), ["active"], "Events from before the reset are gone")
    }

    func testTheQueueKeepsTheNewest() {
        for i in 0..<(Analytics.queueLimit + 5) {
            Analytics.log(.shareSheetOpened, source: "s\(i)", at: now)
        }
        XCTAssertEqual(Analytics.pending.count, Analytics.queueLimit)
        XCTAssertEqual(Analytics.pending.first?.source, "s5")
    }

    func testBatchBodyMatchesTheServer() throws {
        let event = Analytics.Queued(name: "install_from_link", at: now, slug: "k7Pq2mXa", source: nil)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Analytics.body(for: [event])) as? [String: Any])
        XCTAssertEqual(json["installId"] as? String, Analytics.installID)
        XCTAssertEqual(json["platform"] as? String, "macos")
        XCTAssertNotNil(json["appVersion"] as? String)
        let events = try XCTUnwrap(json["events"] as? [[String: Any]])
        XCTAssertEqual(events.first?["name"] as? String, "install_from_link")
        XCTAssertEqual(events.first?["at"] as? String, "2026-10-09T12:00:00Z")
        XCTAssertEqual(events.first?["slug"] as? String, "k7Pq2mXa")
    }

    func testSourcesForCountdownsNobodyLabeled() {
        var event = Countdown(title: "Sonoma", details: "", targetDate: now + 86_400)
        XCTAssertEqual(Analytics.source(for: event), "typed")
        event.extras.repeatsYearly = true
        XCTAssertEqual(Analytics.source(for: event), "typed_yearly")
        XCTAssertEqual(Analytics.source(for: Countdown(title: "Tea", details: "", targetDate: now + 300, kind: .timer, createdAt: now)), "timer")
        var sunrise = Countdown(title: "Sunrise", details: "", targetDate: now + 3_600)
        sunrise.extras.auto = AutoDate(kind: .sunrise)
        XCTAssertEqual(Analytics.source(for: sunrise), "vampire_hours")
    }
}
