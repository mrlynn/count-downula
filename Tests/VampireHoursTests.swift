import XCTest

/// Sunrise, sunset and full moon countdowns, and alerts in the Count's voice.
final class VampireHoursTests: XCTestCase {
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func assertClose(_ actual: Date?, _ expected: String, within minutes: Double,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else { return XCTFail("No date", file: file, line: line) }
        let off = abs(actual.timeIntervalSince(date(expected))) / 60
        XCTAssertLessThan(off, minutes, "\(actual) is \(Int(off)) min from \(expected)", file: file, line: line)
    }

    // MARK: - Astronomy

    func testSunriseAndSunsetMatchPublishedTimes() {
        // New York on the June solstice: 5:25 and 8:31 pm EDT.
        let ny = (lat: 40.7128, lon: -74.0060)
        assertClose(Astronomy.nextSunEvent(.rise, after: date("2026-06-21T04:00:00Z"), latitude: ny.lat, longitude: ny.lon),
                    "2026-06-21T09:25:00Z", within: 3)
        assertClose(Astronomy.nextSunEvent(.set, after: date("2026-06-21T04:00:00Z"), latitude: ny.lat, longitude: ny.lon),
                    "2026-06-22T00:31:00Z", within: 3)
        // London on the December solstice: 8:04 am GMT.
        assertClose(Astronomy.nextSunEvent(.rise, after: date("2026-12-21T00:00:00Z"), latitude: 51.5074, longitude: -0.1278),
                    "2026-12-21T08:04:00Z", within: 3)
        // Sydney, across the date line: 5:41 am AEDT on Dec 22 is 18:41 UTC on Dec 21.
        assertClose(Astronomy.nextSunEvent(.rise, after: date("2026-12-21T00:00:00Z"), latitude: -33.8688, longitude: 151.2093),
                    "2026-12-21T18:41:00Z", within: 3)
    }

    func testNextSunriseSkipsPolarNight() throws {
        // Tromsø has no sunrise from late November until mid January.
        let rise = try XCTUnwrap(Astronomy.nextSunEvent(.rise, after: date("2026-12-01T00:00:00Z"),
                                                        latitude: 69.65, longitude: 18.96))
        XCTAssertEqual(Calendar(identifier: .gregorian).component(.month, from: rise), 1)
    }

    func testFullMoonsMatchPublishedTimes() {
        assertClose(Astronomy.nextFullMoon(after: date("2025-10-01T00:00:00Z")), "2025-10-07T03:47:00Z", within: 5)
        assertClose(Astronomy.nextFullMoon(after: date("2025-12-20T00:00:00Z")), "2026-01-03T10:03:00Z", within: 5)
        assertClose(Astronomy.nextFullMoon(after: date("2024-12-01T00:00:00Z")), "2024-12-15T09:02:00Z", within: 5)
        // Just after one full moon, the next is a month away, not the one that just passed.
        assertClose(Astronomy.nextFullMoon(after: date("2025-10-07T04:00:00Z")), "2025-11-05T13:19:00Z", within: 5)
    }

    // MARK: - Rolling forward

    func testSunriseCountdownRollsToTheNextSunriseAfterItsGracePeriod() throws {
        let auto = AutoDate(kind: .sunrise, latitude: 40.7128, longitude: -74.0060)
        XCTAssertEqual(auto.latitude, 40.7, "Stored no more precisely than a town")
        let first = try XCTUnwrap(auto.next(after: date("2026-06-21T04:00:00Z")))
        var countdown = Countdown(title: "Sunrise", details: "", targetDate: first, createdAt: first - 3_600)
        countdown.extras.auto = auto
        countdown.milestones = [Milestone(title: "Soon", trigger: .remaining(600), celebratedAt: first - 600)]
        countdown.hasNotified = true

        XCTAssertFalse(countdown.rollForward(at: first + 60), "Stays done for its grace period")
        XCTAssertTrue(countdown.rollForward(at: first + auto.gracePeriod + 1))
        let gap = countdown.targetDate.timeIntervalSince(first)
        XCTAssertEqual(gap / 3_600, 24, accuracy: 0.1, "The next morning")
        XCTAssertEqual(countdown.createdAt, first, "The night in between becomes the progress range")
        XCTAssertFalse(countdown.hasNotified)
        XCTAssertNil(countdown.milestones[0].celebratedAt)
    }

    func testSunCountdownWithoutALocationStaysPut() {
        var countdown = Countdown(title: "Sunrise", details: "", targetDate: date("2026-06-21T09:25:00Z"))
        countdown.extras.auto = AutoDate(kind: .sunrise)
        XCTAssertFalse(countdown.rollForward(at: date("2026-06-25T00:00:00Z")))
    }

    func testExtrasRoundTripAndOlderJSONStillDecodes() throws {
        var extras = CountdownExtras()
        extras.voice = .count
        extras.auto = AutoDate(kind: .fullMoon)
        let decoded = try JSONDecoder().decode(CountdownExtras.self, from: JSONEncoder().encode(extras))
        XCTAssertEqual(decoded, extras)

        let old = try JSONDecoder().decode(CountdownExtras.self, from: Data(#"{"repeatsYearly":true}"#.utf8))
        XCTAssertEqual(old.voice, .standard)
        XCTAssertNil(old.auto)
        // A kind added by a newer build is dropped rather than failing the whole blob.
        let newer = try JSONDecoder().decode(CountdownExtras.self,
                                             from: Data(#"{"voice":"whisper","auto":{"kind":"eclipse"}}"#.utf8))
        XCTAssertEqual(newer.voice, .standard)
        XCTAssertNil(newer.auto)
    }

    // MARK: - The Count's voice

    func testStandardAlertsAreUnchanged() {
        let countdown = Countdown(title: "Launch", details: "Ship it.", targetDate: date("2026-11-20T17:00:00Z"))
        let item = NotificationPlan.completion(for: countdown)
        XCTAssertEqual(item.title, "🎉 Launch")
        XCTAssertEqual(item.body, "Ship it.")
    }

    func testCountVoiceRewritesAlertsStably() {
        var countdown = Countdown(title: "Launch", details: "Ship it.", targetDate: date("2026-11-20T17:00:00Z"),
                                  createdAt: date("2026-09-01T00:00:00Z"))
        countdown.extras.voice = .count
        countdown.milestones = [MilestonePreset.oneWeek.milestone, MilestonePreset.halfway.milestone]

        let finish = NotificationPlan.completion(for: countdown)
        XCTAssertEqual(finish.title, "🦇 Launch")
        XCTAssertNotEqual(finish.body, "Ship it.")
        XCTAssertEqual(NotificationPlan.completion(for: countdown).body, finish.body, "Same line every time")

        let week = countdown.scheduledMilestones.first { $0.milestone.trigger == .remaining(7 * 86_400) }!
        let line = NotificationPlan.milestone(week, of: countdown).body
        XCTAssertTrue(line.localizedCaseInsensitiveContains("seven nights"), line)

        let halfway = countdown.scheduledMilestones.first { $0.milestone.trigger == .fraction(0.5) }!
        XCTAssertTrue(NotificationPlan.milestone(halfway, of: countdown).body.contains("Halfway"))
    }

    func testTimeLeftReadsNaturally() {
        XCTAssertEqual(CountLines.timeLeft(3 * 86_400).text, "three nights")
        XCTAssertEqual(CountLines.timeLeft(86_400).text, "one night")
        XCTAssertEqual(CountLines.timeLeft(3_600).text, "one hour")
        XCTAssertEqual(CountLines.timeLeft(45 * 60).text, "forty-five minutes")
        XCTAssertEqual(CountLines.timeLeft(365 * 86_400).text, "365 nights")
    }

    func testHalloweenWeekGetsItsOwnLines() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertTrue(CountLines.isHalloweenWeek(date("2026-10-31T12:00:00Z"), calendar: calendar))
        XCTAssertFalse(CountLines.isHalloweenWeek(date("2026-11-01T12:00:00Z"), calendar: calendar))
        XCTAssertFalse(CountLines.isHalloweenWeek(date("2026-10-20T12:00:00Z"), calendar: calendar))
    }

    func testSunriseAlertsSoundLikeSunrise() {
        var countdown = Countdown(title: "Sunrise", details: "Get to your coffin.", targetDate: date("2026-06-21T09:25:00Z"))
        countdown.extras.auto = AutoDate(kind: .sunrise, latitude: 40.7, longitude: -74)
        XCTAssertEqual(NotificationPlan.completion(for: countdown).title, "🌅 Sunrise")
        countdown.extras.voice = .count
        let body = NotificationPlan.completion(for: countdown).body.lowercased()
        XCTAssertTrue(["sun", "dawn"].contains { body.contains($0) }, body)
    }

    // MARK: - Final ten seconds

    func testTheCountsFinalCountdownReplacesTheFinishSound() {
        let now = date("2026-10-08T12:00:00Z")
        var countdown = Countdown(title: "Launch", details: "", targetDate: now + 3_600)
        countdown.extras.voice = .count
        let items = NotificationPlan.items(for: [countdown], now: now, limit: 10, includeFinalCountdown: true)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].date, countdown.targetDate - 10)
        XCTAssertEqual(items[0].sound, .named(NotificationPlan.finalCountdownSound))
        XCTAssertEqual(items[1].date, countdown.targetDate)
        XCTAssertEqual(items[1].sound, .silent, "The chime at zero is in the countdown sound")

        XCTAssertEqual(NotificationPlan.items(for: [countdown], now: now, limit: 10).map(\.sound), [.standard],
                       "Devices without the sound keep the normal alert")
        XCTAssertEqual(NotificationPlan.items(for: [countdown], now: countdown.targetDate - 5, limit: 10,
                                              includeFinalCountdown: true).map(\.sound), [.standard],
                       "Too late to start a ten second countdown")
        countdown.extras.voice = .standard
        XCTAssertEqual(NotificationPlan.items(for: [countdown], now: now, limit: 10, includeFinalCountdown: true).count, 1)
    }
}
