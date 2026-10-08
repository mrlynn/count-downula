import XCTest

final class DraftExtractorTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-08T12:00:00Z")!

    private func components(_ date: Date?) -> DateComponents? {
        date.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
    }

    func testFlightConfirmation() {
        let text = """
        Your booking is confirmed
        Confirmation: QX7P2L
        Flight to Lisbon
        TAP Air Portugal TP 210
        Departs Friday, November 20, 2026 at 7:45 PM
        Boarding pass available 24 hours before departure.
        """
        let draft = DraftExtractor.draft(from: text, now: now)
        XCTAssertEqual(draft.title, "Flight to Lisbon")
        XCTAssertEqual(components(draft.date)?.month, 11)
        XCTAssertEqual(components(draft.date)?.day, 20)
        XCTAssertEqual(components(draft.date)?.hour, 19)
        XCTAssertEqual(components(draft.date)?.minute, 45)
        XCTAssertEqual(draft.scene, .sunset)
    }

    func testWeddingInviteWithVenueAndNoTime() {
        let text = """
        Together with their families
        Maya Chen & Theo Park
        request the pleasure of your company at their wedding
        Saturday, June 12, 2027
        Venue: Meadowood, Napa Valley
        """
        let draft = DraftExtractor.draft(from: text, now: now)
        XCTAssertTrue(draft.title.lowercased().contains("wedding"), draft.title)
        XCTAssertEqual(components(draft.date)?.year, 2027)
        XCTAssertEqual(components(draft.date)?.hour, 9, "A day with no time lands in the morning")
        XCTAssertEqual(draft.place, "Meadowood, Napa Valley")
        XCTAssertEqual(draft.scene, .blossoms)
    }

    func testPicksTheSoonestFutureDateNotThePastOrderDate() {
        let text = """
        Order #88123 placed October 1, 2026
        The Eras Tour
        Show date: March 3, 2027 8:00 PM
        Doors open March 3, 2027 6:30 PM
        """
        let draft = DraftExtractor.draft(from: text, now: now)
        XCTAssertEqual(draft.title, "The Eras Tour")
        XCTAssertEqual(components(draft.date)?.hour, 18, "The soonest upcoming time: doors")
        XCTAssertEqual(draft.scene, .city)
    }

    func testNothingUsefulStillGivesAnEditableDraft() {
        let draft = DraftExtractor.draft(from: "https://example.com\n12345", now: now)
        XCTAssertEqual(draft.title, "New Countdown")
        XCTAssertNil(draft.date)
        XCTAssertEqual(draft.scene, .midnight)
        XCTAssertEqual(draft.countdown(now: now).targetDate, now + 7 * 86_400, "Defaults a week out for the person to fix")
    }

    func testHandoffKeepsDraftsUntilTaken() {
        DraftHandoff.setPending([])
        DraftHandoff.add(CountdownDraft(title: "Flight to Lisbon", date: now, place: nil, scene: .sunset))
        DraftHandoff.add(CountdownDraft(title: "Wedding", date: nil, place: "Napa", scene: .blossoms))
        XCTAssertEqual(DraftHandoff.pending.map(\.title), ["Flight to Lisbon", "Wedding"])
        DraftHandoff.setPending([])
        XCTAssertTrue(DraftHandoff.pending.isEmpty)
    }

    func testScreenshotWithDateAndTimesOnSeparateLines() {
        // How text recognition returns a ticket screenshot: the day and the times on separate lines.
        let text = """
        TicketHub
        Order #48213 confirmed
        Your tickets are ready
        Phoebe Bridgers
        Reunion Tour
        Saturday, December 12, 2026
        Doors 7:00 PM · Show 8:30 PM
        Venue: The Greek Theatre, Berkeley
        """
        let draft = DraftExtractor.draft(from: text, now: now)
        let parts = components(draft.date)
        XCTAssertEqual([parts?.month, parts?.day, parts?.hour, parts?.minute], [12, 12, 19, 0],
                       "December 12 at doors, not 7 pm today")
        XCTAssertEqual(draft.place, "The Greek Theatre, Berkeley")
        XCTAssertEqual(draft.scene, .city)
    }

    func testATimeAloneMeansToday() {
        let draft = DraftExtractor.draft(from: "Standup at 4:30 PM", now: now)
        XCTAssertEqual(Calendar.current.isDate(draft.date ?? .distantPast, inSameDayAs: now), true)
    }
}
